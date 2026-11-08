@testable import FeatureMatching
import Foundation
import MoyeotaDomain
import Testing

// 21 매칭 대기가 핵심 퍼널 3단계(`complete_match`)를 **정원이 찬 것을 처음 본 순간 한 번만** 기록하는지 본다.
// 스냅샷·변경분·폴백 상세 어느 길로 알게 되든 `publish` 하나를 지나므로 같은 자리다.

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

private func ride(members: [User], status: RideStatus) -> Ride {
    Ride(
        id: "1", origin: "부산대", destination: "서면", departureLabel: "지금 출발", capacity: 3,
        members: members, farePerPerson: 0, totalFare: 0, status: status
    )
}

/// SSE 를 테스트가 직접 밀어 넣는다. 폴백은 영원히 대기하는 sleep 으로 막는다.
private final class FakeRepository: RideRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<PartyEvent, any Error>.Continuation] = []
    var detail: PartyDetail
    var leaveCalls = 0

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
    func leaveParty(partyId: Int64) async throws { lock.withLock { leaveCalls += 1 } }
    func finishParty(partyId: Int64) async throws {}
    func getNearbyParties() -> [Ride] { [] }
    func getParties() async throws -> [Ride] { throw StubError() }
    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] { throw StubError() }
    func getPartyDetail(partyId: Int64) async throws -> Ride { throw StubError() }
    func findRealtimeCandidates(departureLat: Double, departureLng: Double, destinationLat: Double, destinationLng: Double) async throws -> [MatchCandidate] { throw StubError() }
    func createParty(request: NewParty) async throws -> Ride { throw StubError() }
    func joinParty(partyId: Int64) async throws -> PartyStatus { throw StubError() }
    func previewRoute(departureLat: Double, departureLng: Double, destinationLat: Double, destinationLng: Double) async throws -> RouteEstimate { throw StubError() }

    // 예약 방 — 이 지원 클래스가 보는 분석 이벤트는 아직 없다.
    func createReservation(request: NewReservation) async throws -> Ride { throw StubError() }
    func getReservations(from: String, to: String) async throws -> [Ride] { throw StubError() }
    func getReservationsSoon(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] { throw StubError() }
    func searchReservations(departureLat: Double, departureLng: Double, date: String, destination: ReservationDestination?) async throws -> [ReservationSearchResult] { throw StubError() }

    // 약속 확정·도착·출발 — 이 지원 클래스가 보는 분석 이벤트는 아직 없다. 기록 지점이 생기면
    // leave/finish 처럼 호출을 세면 된다.
    func confirmMeeting(partyId: Int64, departureAt: String) async throws { throw StubError() }
    func arriveAtDeparture(partyId: Int64, latitude: Double, longitude: Double) async throws { throw StubError() }
    func departParty(partyId: Int64) async throws { throw StubError() }
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

            repository.latest()?.yield(.memberJoined(member: others[1], status: .matched, version: 2))
            #expect(await eventually { !completions.isEmpty })

            // 같은 상태의 스냅샷이 다시 와도 두 번 세지 않는다
            let full = ride(members: [me] + others, status: .matched)
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
        let full = ride(members: [me] + others, status: .matched)
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

    @Test("닫힌 방(만료·취소)은 완료가 아니다")
    func closedPartyIsNotCompletion() async {
        let canceled = ride(members: [me], status: .canceled)
        let repository = FakeRepository(detail: PartyDetail(ride: canceled, version: 2))

        await AnalyticsCapture.$current.withValue(recorder) {
            let viewModel = MatchWaitingViewModel(repository: repository, partyId: 1, sleep: blockingSleep)
            #expect(await eventually { repository.subscriptions == 1 })
            repository.latest()?.yield(.snapshot(ride: canceled, version: 2))
            #expect(await eventually { viewModel.uiState == .success(ride: canceled) })
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

    /// 예전에는 `DISPATCHING`·`ONGOING` 도 참이었다(정원이 찬 뒤의 단계라서) — 서버가 그 두
    /// status 를 보낼 수 없게 되면서 참인 값이 하나로 줄었다.
    ///
    /// **거짓인 쪽을 열거형 전체로 훑는다.** 퍼널이 거짓을 말하는 길은 「아직 안 찬 방·닫힌 방을
    /// 매칭 완료로 센다」 하나이고, 단계가 늘면 그 새 값이 기본적으로 거짓이어야 한다.
    @Test("isMatchFull 은 정원이 찬 status 하나만 참이다")
    func fullStatusRule() {
        #expect(isMatchFull(status: .matched))
        for status in RideStatus.allCases where status != .matched {
            #expect(!isMatchFull(status: status), "\(status) 가 매칭 완료로 셈된다")
        }
    }
}
