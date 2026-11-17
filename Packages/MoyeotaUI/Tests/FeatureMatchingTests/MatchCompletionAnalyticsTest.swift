@testable import FeatureMatching
import Foundation
import MoyeotaDomain
import Testing

// 21 매칭 대기가 핵심 퍼널 3단계(`complete_match`)를 **정원이 찬 것을 처음 본 순간 한 번만** 기록하는지 본다.
// 스냅샷·변경분·폴백 상세 어느 길로 알게 되든 `publish` 하나를 지나므로 같은 자리다.
//
// ### 🔴 판정 근거가 status 에서 **목록**으로 바뀌었다 (2026-11-12) ★
// 예전 판정은 「status 로만」이었다. 서버가 COMPLETED 의 뜻을 「정원 충족」에서 「방장이 약속을
// 확정했다」로 바꾸면서(`b16551b7`) 그 식이 **양쪽으로 거짓**이 됐다 — 2/3 확정 방을 세고, 정원이
// 꽉 찬 미확정 방은 안 셌다. 그래서 여기 쓰는 방의 **members/capacity 가 이제 판정 입력**이고 status 는
// 집계에 영향을 주지 않는다. 식 자체는 `WaitingStageTest` 가 못 박는다.

private struct StubError: Error {}

private final class AnalyticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [AnalyticsEvent] = []
    func add(_ event: AnalyticsEvent) { lock.withLock { entries.append(event) } }
    var seen: [AnalyticsEvent] { lock.withLock { entries } }
}

private enum AnalyticsCapture {
    @TaskLocal static var current: AnalyticsRecorder?
}

private let me = User(id: "me", nickname: "나", verifiedLabel: "", rating: 0, rideCount: 0, isMe: true)
private let others = (1...2).map { User(id: "u\($0)", nickname: "남\($0)", verifiedLabel: "", rating: 0, rideCount: 0) }

private func ride(members: [User], status: RideStatus, capacity: Int = 3) -> Ride {
    Ride(
        id: "1", origin: "부산대", destination: "서면", departureLabel: "지금 출발", capacity: capacity,
        members: members, farePerPerson: 0, totalFare: 0, status: status
    )
}

/// SSE 를 테스트가 직접 밀어 넣는다. 폴백은 영원히 대기하는 sleep 으로 막는다.
private final class FakeRepository: RideRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<PartyEvent, any Error>.Continuation] = []
    var detail: PartyDetail
    var leaveCalls = 0
    /// 나가기·출발이 던질 실패. nil 이면 성공한다.
    var leaveError: (any Error)?
    var departError: (any Error)?

    init(detail: PartyDetail) {
        self.detail = detail
    }

    var subscriptions: Int { lock.withLock { continuations.count } }

    func latest() -> AsyncThrowingStream<PartyEvent, any Error>.Continuation? {
        lock.withLock { continuations.last }
    }

    func observePartyEvents(partyId: Int64) -> AsyncThrowingStream<PartyEvent, any Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { continuations.append(continuation) }
        }
    }

    func getPartyDetailWithVersion(partyId: Int64) async throws -> PartyDetail { lock.withLock { detail } }
    func leaveParty(partyId: Int64) async throws {
        let error = lock.withLock { () -> (any Error)? in
            leaveCalls += 1
            return leaveError
        }
        if let error { throw error }
    }
    func getNearbyParties() -> [Ride] { [] }
    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] { throw StubError() }
    func getPartyDetail(partyId: Int64) async throws -> Ride { throw StubError() }
    func findRealtimeCandidates(departureLat: Double, departureLng: Double, destinationLat: Double, destinationLng: Double) async throws -> [MatchCandidate] { throw StubError() }
    func createParty(request: NewParty) async throws -> Ride { throw StubError() }
    func joinParty(partyId: Int64) async throws -> PartyStatus { throw StubError() }
    func previewRoute(departureLat: Double, departureLng: Double, destinationLat: Double, destinationLng: Double) async throws -> RouteEstimate { throw StubError() }

    // 예약 방 — 이 지원 클래스가 보는 분석 이벤트는 아직 없다.
    func createReservation(request: NewReservation) async throws -> Ride { throw StubError() }
    func getReservationsSoon(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] { throw StubError() }
    func searchReservations(departureLat: Double, departureLng: Double, date: String, destination: ReservationDestination?) async throws -> [ReservationSearchResult] { throw StubError() }

    // 약속 확정·도착 — 이 지원 클래스가 보는 분석 이벤트는 없다. 출발은 `finish_party` 의 기록 지점이다
    // (「합승 완료」가 서버에서 사라지면서 옮겨 왔다).
    func confirmMeeting(
        partyId: Int64,
        departureAt: String,
        latitude: Double,
        longitude: Double,
        placeName: String
    ) async throws { throw StubError() }
    func arriveAtDeparture(partyId: Int64, latitude: Double, longitude: Double) async throws { throw StubError() }
    func departParty(partyId: Int64) async throws {
        if let error = lock.withLock({ departError }) { throw error }
    }
}

private let blockingSleep: @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) }

@MainActor
@Suite(.serialized)
final class MatchCompletionAnalyticsTest {
    private let recorder = AnalyticsRecorder()

    init() {
        Analytics.install { event in AnalyticsCapture.current?.add(event) }
    }

    deinit {
        Analytics.reset()
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    private var completions: [AnalyticsEvent] { recorder.seen.filter { $0.name == "complete_match" } }

    /// 변경분으로 마지막 자리가 채워지는 경로. 서버가 싣는 status 는 **ACTIVE 그대로**다
    /// (정원이 차도 바뀌지 않는다) — 그래서 이 경로는 **목록 길이로만** 집계된다.
    ///
    /// 같은 방이 몇 번 와도 한 번이다(스냅샷은 재연결마다 다시 온다). status 를 RECRUITING 으로 두는 것이
    /// 요점이다 — **서버가 정원이 찬 방을 ACTIVE 로 둔다.** 여기서 `.confirmed` 를 쓰면 옛 식
    /// (`status == .matched`)으로도 통과해 회귀를 못 잡는다.
    @Test("모집 중 → 정원 충족 변경분을 받으면 complete_match 를 한 번 기록한다")
    func fullTransitionTracksOnce() async {
        let recruiting = ride(members: [me, others[0]], status: .recruiting)
        let repository = FakeRepository(detail: PartyDetail(ride: recruiting, version: 1))

        await AnalyticsCapture.$current.withValue(recorder) {
            let viewModel = MatchWaitingViewModel(repository: repository, partyId: 1, sleep: blockingSleep)
            #expect(await eventually { repository.subscriptions == 1 })
            repository.latest()?.yield(.snapshot(ride: recruiting, version: 1))
            #expect(await eventually { viewModel.uiState == .success(ride: recruiting) })
            #expect(completions.isEmpty, "모집 중에는 완료가 아니다")

            repository.latest()?.yield(.memberJoined(member: others[1], status: .recruiting, version: 2))
            #expect(await eventually { !completions.isEmpty })

            // 같은 방의 스냅샷이 다시 와도 두 번 세지 않는다
            let full = ride(members: [me] + others, status: .recruiting)
            repository.latest()?.yield(.snapshot(ride: full, version: 3))
            await settle()
            withExtendedLifetime(viewModel) {}
        }

        #expect(completions.count == 1)
        guard case .matchCompleted(let capacity, let memberCount, let waitedSeconds) = completions[0] else {
            Issue.record("complete_match 가 아니다: \(completions)")
            return
        }
        #expect(capacity == 3)
        #expect(memberCount == 3)
        #expect(waitedSeconds >= 0)
    }

    @Test("처음부터 정원이 찬 방(마지막 자리를 채운 합류)도 완료로 센다")
    func alreadyFullSnapshotCounts() async {
        let full = ride(members: [me] + others, status: .recruiting)
        let repository = FakeRepository(detail: PartyDetail(ride: full, version: 5))

        await AnalyticsCapture.$current.withValue(recorder) {
            let viewModel = MatchWaitingViewModel(repository: repository, partyId: 1, sleep: blockingSleep)
            #expect(await eventually { repository.subscriptions == 1 })
            repository.latest()?.yield(.snapshot(ride: full, version: 5))
            #expect(await eventually { viewModel.uiState == .success(ride: full) })
            withExtendedLifetime(viewModel) {}
        }

        #expect(completions.count == 1)
    }

    /// 🔴 ★ **2/3 짜리 확정 방은 매칭 완료가 아니다** — 옛 식이 거짓을 말한 바로 그 경우다.
    ///
    /// `status == .matched` 로 세면 이 방이 `complete_match` 로 집계된다. 서버 COMPLETED 는
    /// 「방장이 약속을 확정했다」일 뿐이고 정원과 아무 관계가 없다(`b16551b7`) — 퍼널 3단계가
    /// 「같이 타면 택시비가 싸진다를 경험한 순간」을 세는 자리라, 2명으로 간 방을 섞으면 **그 지표가
    /// 거짓이 된다.** 화면만 봐서는 알 수 없는 종류의 거짓이라 값으로 고정한다.
    ///
    /// (옛 「닫힌 방(만료·취소)은 완료가 아니다」는 지웠다 — 판정이 status 를 보지 않으므로 그 테스트가
    /// 못 박던 가지가 없다. 닫힌 방은 이 판정에 닿기 전에 Route 가 화면을 떠난다 — `isMatchFull` 주석.)
    @Test("정원이 차지 않은 확정 방은 매칭 완료로 세지 않는다")
    func confirmedButNotFullIsNotCompletion() async {
        var confirmed = ride(members: [me, others[0]], status: .confirmed)
        confirmed.isConfirmed = true
        let repository = FakeRepository(detail: PartyDetail(ride: confirmed, version: 2))

        await AnalyticsCapture.$current.withValue(recorder) {
            let viewModel = MatchWaitingViewModel(repository: repository, partyId: 1, sleep: blockingSleep)
            #expect(await eventually { repository.subscriptions == 1 })
            repository.latest()?.yield(.snapshot(ride: confirmed, version: 2))
            #expect(await eventually { viewModel.uiState == .success(ride: confirmed) })
            withExtendedLifetime(viewModel) {}
        }

        #expect(completions.isEmpty)
    }

    /// ★ **정원을 모르는 방(`capacity` 0)은 세지 않는다.** 목록·추천 응답으로 만든 `Ride` 가 그렇고,
    /// 0 은 「정원이 0명」이 아니라 「정원을 모른다」다 — `0 >= 0` 이 참이라 가드가 없으면 **방금
    /// 만든 1인 방까지** 매칭 완료가 된다.
    @Test("정원을 모르는 방은 매칭 완료로 세지 않는다")
    func unknownCapacityIsNotCompletion() async {
        let unknown = ride(members: [me], status: .recruiting, capacity: 0)
        let repository = FakeRepository(detail: PartyDetail(ride: unknown, version: 2))

        await AnalyticsCapture.$current.withValue(recorder) {
            let viewModel = MatchWaitingViewModel(repository: repository, partyId: 1, sleep: blockingSleep)
            #expect(await eventually { repository.subscriptions == 1 })
            repository.latest()?.yield(.snapshot(ride: unknown, version: 2))
            #expect(await eventually { viewModel.uiState == .success(ride: unknown) })
            withExtendedLifetime(viewModel) {}
        }

        #expect(completions.isEmpty)
    }

    @Test("「그만 찾기」가 성공하면 그때의 인원과 함께 cancel_match 를 기록한다")
    func leaveTracksCancel() async {
        let recruiting = ride(members: [me, others[0]], status: .recruiting)
        let repository = FakeRepository(detail: PartyDetail(ride: recruiting, version: 1))

        await AnalyticsCapture.$current.withValue(recorder) {
            let viewModel = MatchWaitingViewModel(repository: repository, partyId: 1, sleep: blockingSleep)
            #expect(await eventually { repository.subscriptions == 1 })
            repository.latest()?.yield(.snapshot(ride: recruiting, version: 1))
            #expect(await eventually { viewModel.uiState == .success(ride: recruiting) })

            viewModel.leaveParty()
            #expect(await eventually { viewModel.actionState.left })
        }

        #expect(recorder.seen.contains(.matchCanceled(capacity: 3, memberCount: 2)))
        #expect(completions.isEmpty)
    }

    @Test("나가기가 실패하면 cancel_match 를 보내지 않는다")
    func failedLeaveDoesNotTrack() async {
        let recruiting = ride(members: [me, others[0]], status: .recruiting)
        let repository = FakeRepository(detail: PartyDetail(ride: recruiting, version: 1))
        // 코드 이름이 `PARTY_NOT_RECRUITING` 이었다 — 서버가 단계 검사를 묶으면서 통일했다(`b16551b7`).
        repository.leaveError = PartyLeaveException(code: PartyLeaveException.PARTY_CLOSED, serverMessage: nil, httpStatus: 409)

        await AnalyticsCapture.$current.withValue(recorder) {
            let viewModel = MatchWaitingViewModel(repository: repository, partyId: 1, sleep: blockingSleep)
            #expect(await eventually { viewModel.uiState == .success(ride: recruiting) })

            viewModel.leaveParty()
            #expect(await eventually { viewModel.actionState.errorMessage != nil })
        }

        #expect(recorder.seen.isEmpty, "\(recorder.seen)")
    }

    /// 🔴 **`finish_party` 의 기록 지점이 「합승 완료」에서 「출발」로 옮겨 왔다** (2026-11-12) ★
    ///
    /// 옛 기록 지점은 「합승 완료」 성공이었다. 서버가 `/finish` 를 없애면서(`b16551b7`) 그 액션이
    /// 사라졌고, **그대로 두면 Mixpanel 퍼널의 마지막 단계가 조용히 0 이 된다** — 이벤트가 세는 사실
    /// (「방이 끝났다」)은 그대로이고 끝내는 버튼만 바뀐 것이므로 `MatchWaitingViewModel.departParty` 로
    /// 옮겼다.
    ///
    /// `member_count` 의 뜻도 지킨다: **방을 끝낼 때 방에 있던 인원**이다(도착한 인원이 아니다 —
    /// 그건 다른 숫자라 같은 프로퍼티에 담으면 대시보드가 조용히 다른 값을 보게 된다).
    ///
    /// ⚠️ 이 이벤트 이름(`finish_party`)은 **대시보드와 Android 가 보는 문자열**이다 — 두 플랫폼이 같은
    /// 자리(출발 성공)에서 기록해야 숫자가 합쳐진다.
    @Test("출발 성공이 finish_party 를 보낸다 - 실패면 보내지 않는다")
    func departTracksFinish() async {
        let full = ride(members: [me] + others, status: .recruiting)
        let repository = FakeRepository(detail: PartyDetail(ride: full, version: 1))
        repository.departError = PartyDepartException(code: PartyDepartException.NOT_PARTY_HOST, serverMessage: nil, httpStatus: 403)

        await AnalyticsCapture.$current.withValue(recorder) {
            let viewModel = MatchWaitingViewModel(repository: repository, partyId: 1, sleep: blockingSleep)
            #expect(await eventually { viewModel.uiState == .success(ride: full) })

            viewModel.departParty()
            #expect(await eventually { viewModel.actionState.errorMessage != nil && !viewModel.actionState.inProgress })
            #expect(recorder.seen.map(\.name) == ["complete_match"])

            repository.departError = nil
            viewModel.departParty()
            #expect(await eventually { viewModel.actionState.departed })
        }

        #expect(recorder.seen.map(\.name) == ["complete_match", "finish_party"])
        #expect(recorder.seen.last == .partyFinished(memberCount: 3))
    }
}
