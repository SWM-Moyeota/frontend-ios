@testable import FeatureExplore
import Foundation
import MoyeotaDomain
import Testing

// 20 합류 확인이 핵심 퍼널 2단계(`request_match`, method=join)를 **합류가 받아들여진 뒤에만** 기록하는지 본다.
// 「이미 이 방 멤버」로 복구된 경우도 서버에 내 자리가 있다는 뜻이라 같은 길이다.

private struct TestFailure: Error {}

private final class AnalyticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [AnalyticsEvent] = []
    func add(_ event: AnalyticsEvent) { lock.withLock { entries.append(event) } }
    var seen: [AnalyticsEvent] { lock.withLock { entries } }
}

private enum AnalyticsCapture {
    @TaskLocal static var current: AnalyticsRecorder?
}

private func room() -> Ride {
    Ride(
        id: "7", origin: "부산대 정문", destination: "서면역", departureLabel: "", capacity: 3,
        members: [User(id: "u-1", nickname: "동승자", verifiedLabel: "", rating: 0, rideCount: 0)],
        farePerPerson: 0, totalFare: 0, status: .recruiting, estimatedFare: 9_800
    )
}

private final class FakeRideRepository: RideRepository, @unchecked Sendable {
    var joinResult: @Sendable () async throws -> PartyStatus = { PartyStatus(status: .recruiting, currentMembers: 2) }

    func getPartyDetail(partyId: Int64) async throws -> Ride { room() }
    func joinParty(partyId: Int64) async throws -> PartyStatus { try await joinResult() }
    func getNearbyParties() -> [Ride] { [] }
    func getParties() async throws -> [Ride] { throw TestFailure() }
    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] { throw TestFailure() }
    func getPartyDetailWithVersion(partyId: Int64) async throws -> PartyDetail { throw TestFailure() }
    func findRealtimeCandidates(departureLat: Double, departureLng: Double, destinationLat: Double, destinationLng: Double) async throws -> [MatchCandidate] { throw TestFailure() }
    func createParty(request: NewParty) async throws -> Ride { throw TestFailure() }
    func leaveParty(partyId: Int64) async throws { throw TestFailure() }
    func finishParty(partyId: Int64) async throws { throw TestFailure() }
    func previewRoute(departureLat: Double, departureLng: Double, destinationLat: Double, destinationLng: Double) async throws -> RouteEstimate { throw TestFailure() }

    // 예약 방 — 이 지원 클래스가 보는 분석 이벤트는 아직 없다.
    func createReservation(request: NewReservation) async throws -> Ride { throw TestFailure() }
    func getReservations(from: String, to: String) async throws -> [Ride] { [] }
    func getReservationsSoon(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] { [] }
    func searchReservations(departureLat: Double, departureLng: Double, date: String, destination: ReservationDestination?) async throws -> [ReservationSearchResult] { [] }

    // 약속 확정·도착·출발 — 이 지원 클래스가 보는 분석 이벤트는 아직 없다. 기록 지점이 생기면
    // leave/finish 처럼 람다로 바꿔 호출을 세면 된다.
    func confirmMeeting(partyId: Int64, departureAt: String) async throws { throw TestFailure() }
    func arriveAtDeparture(partyId: Int64, latitude: Double, longitude: Double) async throws { throw TestFailure() }
    func departParty(partyId: Int64) async throws { throw TestFailure() }
}

/// 진행 중인 방을 돌려주는 가짜 저장소. 기본은 **없음**(nil) — 합류 실패 안내가 「막은 방을 모를 때」의
/// 문구로 떨어지는 것이 대부분의 테스트에 맞는 기본값이다(`alreadyInPartyMessage`).
private final class FakeActivePartyRepository: ActivePartyRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let active: Ride?
    private let resolveError: (any Error)?
    private var rememberedId: String?
    private var clearCount = 0

    var remembered: String? { lock.withLock { rememberedId } }
    var cleared: Int { lock.withLock { clearCount } }

    init(active: Ride? = nil, resolveError: (any Error)? = nil) {
        self.active = active
        self.resolveError = resolveError
    }

    func remember(partyId: String) async throws { lock.withLock { rememberedId = partyId } }
    func clear() async throws { lock.withLock { clearCount += 1 } }

    func resolve() async throws -> Ride? {
        if let resolveError { throw resolveError }
        return active
    }
}

@MainActor
@Suite(.serialized)
final class JoinAnalyticsTest {
    private let recorder = AnalyticsRecorder()
    private let repository = FakeRideRepository()

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

    /// 상세가 떠 있는 뷰모델. 합류 버튼은 그 상태에서만 눌릴 수 있다.
    private func loaded(activeParty: any ActivePartyRepository = FakeActivePartyRepository()) async -> JoinConfirmViewModel {
        let viewModel = JoinConfirmViewModel(repository: repository, activeParty: activeParty, partyId: 7)
        #expect(await eventually { viewModel.uiState == .success(ride: room()) })
        return viewModel
    }

    private func blockedByAnotherParty() {
        repository.joinResult = {
            throw PartyJoinException(code: PartyJoinException.ALREADY_JOINED_OTHER_PARTY, serverMessage: nil, httpStatus: 409)
        }
    }

    /// ★ 못 박는 것: **배선이 실제로 돈다.** 문구 분기(`alreadyInPartyMessage`)는 순수 함수라 따로
    /// 검증되지만, 「막은 방을 조회해서 그 값을 넘기는가」는 뷰모델만 보여 줄 수 있다.
    ///
    /// 이게 빠지면 분기는 멀쩡한데 늘 nil 이 넘어가 **영원히 「홈에서 확인해 주세요」**만 나온다 —
    /// 테스트가 다 통과하면서 고친 게 사라지는 모양이다.
    @Test("다른 방에 막혔을 때 그 방이 확정된 방이면 출발로 끝내라고 안내한다")
    func confirmedBlockingPartySaysDepart() async {
        var blockingRide = room()
        blockingRide.isConfirmed = true
        let viewModel = await loaded(activeParty: FakeActivePartyRepository(active: blockingRide))
        blockedByAnotherParty()

        viewModel.join()

        #expect(await eventually { viewModel.joinState.errorMessage != nil })
        #expect(
            viewModel.joinState.errorMessage
                == "약속이 정해진 방에 참여 중이에요. 출발지에서 「출발」을 눌러 그 방을 끝낸 뒤에 합류할 수 있어요"
        )
        #expect(viewModel.joinState.joinedPartyId == nil)
    }

    /// 확정 전 방이 막고 있으면 지금까지의 안내(나온 뒤 합류)가 그대로 맞다.
    @Test("막은 방이 확정 전이면 나온 뒤 합류하라고 안내한다")
    func unconfirmedBlockingPartySaysLeave() async {
        let viewModel = await loaded(activeParty: FakeActivePartyRepository(active: room()))
        blockedByAnotherParty()

        viewModel.join()

        #expect(await eventually { viewModel.joinState.errorMessage != nil })
        #expect(viewModel.joinState.errorMessage == "이미 참여 중인 방이 있어요. 그 방에서 나온 뒤 합류해 주세요")
    }

    /// 막은 방 조회가 실패해도 **안내는 선다.** 정확한 한 줄을 만들려다 안내 자체를 잃으면 더 나쁘다.
    /// (원본의 `IOException("네트워크")` 자리 — iOS 의 전송 실패는 `URLError` 다.)
    @Test("막은 방 조회가 실패해도 안내 문구는 뜬다")
    func blockingPartyLookupFailureStillShowsMessage() async {
        let viewModel = await loaded(activeParty: FakeActivePartyRepository(resolveError: URLError(.notConnectedToInternet)))
        blockedByAnotherParty()

        viewModel.join()

        #expect(await eventually { viewModel.joinState.errorMessage != nil })
        #expect(viewModel.joinState.errorMessage == "이미 참여 중인 방이 있어요. 홈에서 진행 중인 방을 확인해 주세요")
    }

    @Test("합류가 받아들여지면 click → request_match(join) 를 기록하고 정원·요금은 상세에서 가져온다")
    func joinTracksRequest() async {
        let viewModel = await loaded()

        await AnalyticsCapture.$current.withValue(recorder) {
            viewModel.join()
            #expect(await eventually { viewModel.joinState.joinedPartyId == 7 })
        }

        #expect(recorder.seen == [
            .partyJoinClicked,
            .matchRequested(method: .join, capacity: 3, originArea: nil, destinationArea: nil, estimatedFare: 9_800),
        ])
    }

    @Test("이미 이 방 멤버였던 복구도 매칭 신청으로 센다")
    func alreadyInThisPartyCounts() async {
        let viewModel = await loaded()
        repository.joinResult = {
            throw PartyJoinException(
                code: PartyJoinException.ALREADY_JOINED_OTHER_PARTY, serverMessage: nil, httpStatus: 409,
                joinedStatus: PartyStatus(status: .recruiting, currentMembers: 2)
            )
        }

        await AnalyticsCapture.$current.withValue(recorder) {
            viewModel.join()
            #expect(await eventually { viewModel.joinState.joinedPartyId == 7 })
        }

        #expect(recorder.seen.map(\.name) == ["click_join_party", "request_match"])
    }

    @Test("거절되면 request_match 는 없고 사유 상수가 붙은 fail_match_request 만 남는다")
    func rejectionTracksReason() async {
        let viewModel = await loaded()
        repository.joinResult = { throw PartyJoinException(code: "PARTY_FULL", serverMessage: nil, httpStatus: 409) }

        await AnalyticsCapture.$current.withValue(recorder) {
            viewModel.join()
            #expect(await eventually { viewModel.joinState.errorMessage != nil })
        }

        #expect(recorder.seen == [
            .partyJoinClicked,
            .matchRequestFailed(method: .join, reason: "party_full"),
        ])
    }

    @Test("사유 상수는 문구 분기와 1:1 이다")
    func reasonsMirrorMessages() {
        #expect(joinFailureReason(e: PartyJoinException(code: "PARTY_CLOSED", serverMessage: nil)) == "party_closed")
        #expect(joinFailureReason(e: PartyJoinException(code: nil, serverMessage: nil, httpStatus: 404)) == "party_not_found")
        #expect(joinFailureReason(e: PartyJoinException(code: PartyJoinException.ALREADY_JOINED_OTHER_PARTY, serverMessage: nil)) == "already_in_party")
        #expect(joinFailureReason(e: PartyJoinException(code: nil, serverMessage: nil, isNetwork: true)) == "network")
        #expect(joinFailureReason(e: PartyJoinException(code: nil, serverMessage: nil, httpStatus: 500)) == "unknown")
    }
}
