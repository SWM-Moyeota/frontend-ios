@testable import FeatureMatching
import Foundation
import MoyeotaDomain
import Testing

/// 「약속 시간 정하기」가 서버에 **무엇을 보내는지** — 2026-11-12 에 본문이 한 필드에서 넷으로 늘었다.
///
/// ### 왜 이 테스트가 필요한가 ★
/// 서버 `confirm` 은 `departureAt` 외에 **만남 장소(위도·경도·이름)를 전부 `@NotNull`/`@NotBlank`**
/// 로 받는다(`2732cc75`). 넷 중 하나라도 빠지거나 0 이면:
///
/// | 보낸 값 | 서버 | 사용자가 보는 것 |
/// |---|---|---|
/// | 장소 필드 누락 | 400 `INVALID_REQUEST` | 「약속 시간을 정하지 못했어요」 — **어떤 사유 코드도 아니다** |
/// | 좌표를 0.0 으로 채움 | 400 `OUT_OF_SERVICE_AREA` | 적도 한가운데라고 거절당한다 |
/// | 빈 장소 이름 | 400 `INVALID_REQUEST` | 같은 일반 문구 |
///
/// 세 경우 다 **가장 찾기 어려운 실패**다: 사유가 일반 문구로만 보이고, 확정이 방을 끝내는 길의
/// 첫 단계라 그게 막히면 **그 방을 끝낼 방법이 아예 없다**(옛 「합승 완료」가 서버에서 사라졌다).
/// 그래서 「무엇을 보냈는가」를 값으로 고정한다 — 화면을 봐서는 알 수 없는 종류다.
///
/// ### 앱은 **방의 지금 출발지를 그대로** 보낸다
/// 채팅으로 다른 곳을 정하는 UI 는 아직 없다. 그래도 서버 쪽에서는 그게 「출발지를 이 값으로
/// 덮어쓴다」는 뜻이므로, 보낸 값이 **곧 방의 새 출발지**가 된다(`Ride.withMeetingConfirmed`).
@MainActor
struct MeetingConfirmRequestTest {
    private struct StubError: Error {}

    /// 보낸 네 값을 그대로 받아 두는 기록기 — 「무엇을 보냈는가」가 이 파일의 주제다.
    private struct SentConfirm: Equatable {
        let departureAt: String
        let latitude: Double
        let longitude: Double
        let placeName: String
    }

    private final class FakeRepository: RideRepository, @unchecked Sendable {
        private let lock = NSLock()
        private var _current: Ride
        private var _detailReads = 0
        private var _sent: SentConfirm?

        init(current: Ride) {
            _current = current
        }

        var detailReads: Int { lock.withLock { _detailReads } }
        var sent: SentConfirm? { lock.withLock { _sent } }

        func getPartyDetailWithVersion(partyId: Int64) async throws -> PartyDetail {
            lock.withLock {
                _detailReads += 1
                return PartyDetail(ride: _current, version: nil)
            }
        }

        func confirmMeeting(
            partyId: Int64,
            departureAt: String,
            latitude: Double,
            longitude: Double,
            placeName: String
        ) async throws {
            lock.withLock {
                _sent = SentConfirm(departureAt: departureAt, latitude: latitude, longitude: longitude, placeName: placeName)
            }
        }

        /// 연결은 열어 두되 아무것도 보내지 않는다 — 상세 1회 조회가 화면을 세운다. 이음새를 쥐고 있어야
        /// 스트림이 종결로 끝나지 않는다(끝나면 폴백이 곧바로 상세를 읽어 조회 횟수가 섞인다).
        private var continuations: [AsyncThrowingStream<PartyEvent, any Error>.Continuation] = []

        func observePartyEvents(partyId: Int64) -> AsyncThrowingStream<PartyEvent, any Error> {
            AsyncThrowingStream { continuation in
                lock.withLock { continuations.append(continuation) }
            }
        }

        func leaveParty(partyId: Int64) async throws { throw StubError() }
        func arriveAtDeparture(partyId: Int64, latitude: Double, longitude: Double) async throws { throw StubError() }
        func departParty(partyId: Int64) async throws { throw StubError() }
        func getNearbyParties() -> [Ride] { [] }
        func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] {
            throw StubError()
        }
        func getPartyDetail(partyId: Int64) async throws -> Ride { throw StubError() }
        func findRealtimeCandidates(
            departureLat: Double,
            departureLng: Double,
            destinationLat: Double,
            destinationLng: Double
        ) async throws -> [MatchCandidate] { throw StubError() }
        func createParty(request: NewParty) async throws -> Ride { throw StubError() }
        func joinParty(partyId: Int64) async throws -> PartyStatus { throw StubError() }
        func previewRoute(
            departureLat: Double,
            departureLng: Double,
            destinationLat: Double,
            destinationLng: Double
        ) async throws -> RouteEstimate { throw StubError() }
        func createReservation(request: NewReservation) async throws -> Ride { throw StubError() }
        func getReservationsSoon(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] {
            throw StubError()
        }
        func searchReservations(
            departureLat: Double,
            departureLng: Double,
            date: String,
            destination: ReservationDestination?
        ) async throws -> [ReservationSearchResult] { throw StubError() }
    }

    /// 상세 조회·SSE 스냅샷이 주는 모양 — **좌표가 채워져 있다.**
    private static func detailRide(
        origin: String = "부산대 정문",
        originLat: Double? = 35.2314,
        originLng: Double? = 129.0846
    ) -> Ride {
        Ride(
            id: "1",
            origin: origin,
            destination: "서면",
            departureLabel: "지금 출발",
            capacity: 3,
            members: [
                User(id: "me", nickname: "나", verifiedLabel: "", rating: 0, rideCount: 0, isMe: true, isHost: true),
                User(id: "u2", nickname: "남", verifiedLabel: "", rating: 0, rideCount: 0),
            ],
            farePerPerson: 0,
            totalFare: 0,
            status: .recruiting,
            originLat: originLat,
            originLng: originLng
        )
    }

    /// 폴백 주기가 저절로 돌지 않게 취소될 때까지 멈춰 있는 대기.
    private static let blockingSleep: @Sendable (Duration) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(3600))
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// 화면에 방이 선 뒤의 뷰모델 — 확정은 **들고 있는 방**의 출발지를 읽으므로 그 전에는 보낼 게 없다.
    private func enter(_ repository: FakeRepository, ride: Ride) async -> MatchWaitingViewModel {
        let viewModel = MatchWaitingViewModel(repository: repository, partyId: 1, sleep: Self.blockingSleep)
        #expect(await eventually { viewModel.uiState == .success(ride: ride) })
        return viewModel
    }

    @Test("방의 지금 출발지를 좌표와 이름까지 그대로 보낸다")
    func sendsCurrentOrigin() async {
        let ride = Self.detailRide()
        let repository = FakeRepository(current: ride)
        let viewModel = await enter(repository, ride: ride)

        viewModel.confirmMeeting(departureAt: "2026-11-06T06:30:00Z")

        #expect(await eventually { repository.sent != nil })
        #expect(
            repository.sent
                == SentConfirm(
                    departureAt: "2026-11-06T06:30:00Z",
                    latitude: 35.2314,
                    longitude: 129.0846,
                    placeName: "부산대 정문"
                )
        )
    }

    /// ★ **성공하면 보낸 장소가 그 자리에서 방의 출발지가 된다.**
    ///
    /// SSE `confirmed` 가 같은 셋을 들고 오지만 그 스트림은 at-most-once 이고 망에 따라 아예 붙지
    /// 않는다. 기다리면 **도착 버튼이 옛 출발지를 기준으로 판정**돼 약속 장소에 서 있는 사람이
    /// 400 `TOO_FAR_FROM_DEPARTURE` 를 맞는다.
    ///
    /// 지금은 보내는 값이 방의 출발지와 같아 좌표가 움직이지 않지만, 확정 사실과 약속 시각은 바뀐다 —
    /// 그 둘이 서지 않으면 화면이 확정 단계로 넘어가지 않는다(`meetingStage`).
    @Test("확정이 성공하면 기다리지 않고 방을 고친다")
    func fixesRideOnSuccess() async {
        let ride = Self.detailRide()
        let repository = FakeRepository(current: ride)
        let viewModel = await enter(repository, ride: ride)

        viewModel.confirmMeeting(departureAt: "2026-11-06T06:30:00Z")

        #expect(await eventually {
            if case .success(let held) = viewModel.uiState { return held.isConfirmed }
            return false
        }, "확정 사실이 서지 않으면 도착 버튼이 영원히 뜨지 않는다")
        guard case .success(let held) = viewModel.uiState else { return }
        #expect(held.departureAt == "2026-11-06T06:30:00Z")
        #expect(held.origin == "부산대 정문")
    }

    /// 🔴 ★ **좌표를 모르면 요청을 만들지 않는다** — 0.0 으로 채우지 않는다.
    ///
    /// `Ride.originLat`·`Ride.originLng` 는 **옵셔널**이다(목록·추천 응답으로 만든 `Ride` 에는
    /// 좌표가 없다). 21 대기 화면이 보는 방은 상세·SSE 스냅샷에서 오므로 실제로는 늘 채워져 있지만
    /// **타입이 그걸 보장하지 않는다** — 그래서 막는다.
    ///
    /// 0.0 으로 채우면 서버가 400 `OUT_OF_SERVICE_AREA` 로 거절하고, 그건 **방을 끝낼 길이
    /// 사라지는** 실패다. 대신 사실을 말하고 **상세를 다시 읽어 둔다**: 상세 응답에는 좌표가 있으므로
    /// 다시 누르면 통과한다. 「다시 시도해 주세요」를 붙이는 유일한 실패 문구인 근거다.
    @Test("출발지 좌표를 모르면 보내지 않고 상세를 다시 읽는다")
    func unknownOriginRereads() async {
        let ride = Self.detailRide(originLat: nil, originLng: nil)
        let repository = FakeRepository(current: ride)
        let viewModel = await enter(repository, ride: ride)
        let readsBefore = repository.detailReads

        viewModel.confirmMeeting(departureAt: "2026-11-06T06:30:00Z")

        #expect(viewModel.actionState.errorMessage == CONFIRM_PLACE_UNKNOWN_MESSAGE)
        #expect(await eventually { repository.detailReads > readsBefore }, "상세를 다시 읽지 않으면 다시 눌러도 같은 실패다")
        await settle()
        #expect(repository.sent == nil, "좌표를 지어내 보냈다 — 서버가 400 OUT_OF_SERVICE_AREA 로 거절한다")
        // 확정되지 않았다는 사실도 그대로여야 한다 — 보내지 않았으니 방은 그대로다
        #expect(viewModel.uiState == .success(ride: ride))
    }

    /// 장소 **이름**이 비어 있어도 같다 — 서버가 `@NotBlank` 로 받는다(400 `INVALID_REQUEST`).
    ///
    /// 빈 이름을 보내면 그 방의 출발지 이름이 **빈 값으로 덮어써진다** — 그러면 모두의 화면에서
    /// 「어디서 만나는지」가 사라진다. 좌표보다 조용한 사고다.
    @Test("장소 이름이 비어 있으면 보내지 않는다")
    func blankPlaceNameNotSent() async {
        let ride = Self.detailRide(origin: "   ")
        let repository = FakeRepository(current: ride)
        let viewModel = await enter(repository, ride: ride)

        viewModel.confirmMeeting(departureAt: "2026-11-06T06:30:00Z")

        #expect(viewModel.actionState.errorMessage == CONFIRM_PLACE_UNKNOWN_MESSAGE)
        await settle()
        #expect(repository.sent == nil)
    }

    /// 순수 판정만 따로 — 셋이 다 있을 때만 보낼 수 있다.
    @Test("보낼 장소는 좌표와 이름이 다 있을 때만 만들어진다")
    func meetingPlaceNeedsAllThree() {
        #expect(
            meetingPlaceOrNull(ride: Self.detailRide())
                == MeetingPlace(latitude: 35.2314, longitude: 129.0846, name: "부산대 정문")
        )
        #expect(meetingPlaceOrNull(ride: Self.detailRide(originLat: nil)) == nil)
        #expect(meetingPlaceOrNull(ride: Self.detailRide(originLng: nil)) == nil)
        #expect(meetingPlaceOrNull(ride: Self.detailRide(origin: "")) == nil)
        #expect(meetingPlaceOrNull(ride: Self.detailRide(origin: " ")) == nil)
    }
}
