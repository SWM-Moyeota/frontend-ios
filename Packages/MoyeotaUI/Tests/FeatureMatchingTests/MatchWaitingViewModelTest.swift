@testable import FeatureMatching
import Foundation
import MoyeotaDomain
import Testing

/// 뷰모델의 수집 루프 — **iOS 에서 추가한 테스트**다.
///
/// 원본은 presentation 테스트 의존성이 junit 뿐이라 판정 함수만 고정하고 루프는 QA 의 logcat 계수에 맡겼다.
/// 여기서 루프까지 보는 이유는 Swift 의 `for try await` 가 취소돼도 오류 없이 끝나 원본에 없던 함정이 있기 때문이다
/// (PORTING 6장). 틀리면 화면이 한 번 가려질 때마다 SSE 를 영영 다시 붙이지 않는다.
@MainActor
struct MatchWaitingViewModelTest {
    private struct StubError: Error {}

    private final class FakeRepository: RideRepository, @unchecked Sendable {
        private let lock = NSLock()
        private var _continuations: [AsyncThrowingStream<PartyEvent, any Error>.Continuation] = []
        private var _terminated = 0
        private var _detailReads = 0
        private var _detail: Result<PartyDetail, any Error>
        private var _hangDetail = false
        private var _detailCancelled = 0
        var leaveError: (any Error)?
        var finishError: (any Error)?
        var confirmError: (any Error)?
        var arriveError: (any Error)?
        var departError: (any Error)?
        private(set) var leaveCalls = 0
        private(set) var confirmedDepartureAt: [String] = []
        private(set) var arrivedAt: [(latitude: Double, longitude: Double)] = []
        private(set) var departCalls = 0

        init(detail: Result<PartyDetail, any Error>) {
            _detail = detail
        }

        var subscriptions: Int { lock.withLock { _continuations.count } }
        var terminated: Int { lock.withLock { _terminated } }
        var alive: Int { subscriptions - terminated }
        var detailReads: Int { lock.withLock { _detailReads } }
        var detailCancelled: Int { lock.withLock { _detailCancelled } }

        /// 상세 조회가 취소될 때까지 돌아오지 않게 한다 — 응답을 기다리는 도중의 이탈을 재현한다.
        func hangDetail() {
            lock.withLock { _hangDetail = true }
        }

        func setDetail(_ detail: Result<PartyDetail, any Error>) {
            lock.withLock { _detail = detail }
        }

        func latest() -> AsyncThrowingStream<PartyEvent, any Error>.Continuation? {
            lock.withLock { _continuations.last }
        }

        func observePartyEvents(partyId: Int64) -> AsyncThrowingStream<PartyEvent, any Error> {
            AsyncThrowingStream { continuation in
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    self.lock.withLock { self._terminated += 1 }
                }
                lock.withLock { _continuations.append(continuation) }
            }
        }

        func getPartyDetailWithVersion(partyId: Int64) async throws -> PartyDetail {
            let (result, hang) = lock.withLock {
                _detailReads += 1
                return (_detail, _hangDetail)
            }
            if hang {
                do {
                    try await Task.sleep(for: .seconds(3600))
                } catch {
                    lock.withLock { _detailCancelled += 1 }
                    throw error
                }
            }
            return try result.get()
        }

        func leaveParty(partyId: Int64) async throws {
            leaveCalls += 1
            if let leaveError { throw leaveError }
        }

        func finishParty(partyId: Int64) async throws {
            if let finishError { throw finishError }
        }

        func confirmMeeting(partyId: Int64, departureAt: String) async throws {
            confirmedDepartureAt.append(departureAt)
            if let confirmError { throw confirmError }
        }

        func arriveAtDeparture(partyId: Int64, latitude: Double, longitude: Double) async throws {
            arrivedAt.append((latitude, longitude))
            if let arriveError { throw arriveError }
        }

        func departParty(partyId: Int64) async throws {
            departCalls += 1
            if let departError { throw departError }
        }

        func getNearbyParties() -> [Ride] { [] }
        func getParties() async throws -> [Ride] { throw StubError() }
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

        // 예약 방 — 21 대기 뷰모델은 부르지 않는다(만들기·찾기는 16·17 의 일이다).
        func createReservation(request: NewReservation) async throws -> Ride { throw StubError() }
        func getReservations(from: String, to: String) async throws -> [Ride] { throw StubError() }
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

    private static let me = User(id: "me", nickname: "나", verifiedLabel: "", rating: 0, rideCount: 0, isMe: true)
    private static let other = User(id: "u2", nickname: "남", verifiedLabel: "", rating: 0, rideCount: 0)

    private static func ride(members: [User] = [me], status: RideStatus = .recruiting) -> Ride {
        Ride(
            id: "1",
            origin: "부산대",
            destination: "서면",
            departureLabel: "지금 출발",
            capacity: 3,
            members: members,
            farePerPerson: 0,
            totalFare: 0,
            status: status
        )
    }

    private static func okDetail(ride: Ride = ride(), version: Int64? = 1) -> Result<PartyDetail, any Error> {
        .success(PartyDetail(ride: ride, version: version))
    }

    /// 폴백 주기가 저절로 돌지 않게 취소될 때까지 멈춰 있는 대기.
    private static let blockingSleep: @Sendable (Duration) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(3600))
    }

    /// 조건이 설 때까지 기다린다. 시간 안에 안 서면 false.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// 지금 쌓인 태스크들이 돌 틈을 준다 — 「일어나지 않아야 하는 일」을 볼 때 쓴다.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    private func make(
        _ repository: FakeRepository,
        sleep: @escaping @Sendable (Duration) async throws -> Void = blockingSleep
    ) -> MatchWaitingViewModel {
        MatchWaitingViewModel(repository: repository, partyId: 1, sleep: sleep)
    }

    /// 원본 `viewModelScope` 는 엔트리가 빠지면 진행 중인 조회를 끊는다. 태스크가 왕복 동안 뷰모델을 잡으면
    /// 해제되지 않아 취소도 오지 않고, 응답이나 타임아웃(20초)까지 요청과 뷰모델이 함께 남는다.
    @Test("refresh - 첫 조회 도중 화면을 떠나면 뷰모델이 해제되고 조회가 취소된다")
    func refreshReleasesViewModelWhileLoading() async {
        let repository = FakeRepository(detail: Self.okDetail())
        repository.hangDetail()
        weak var released: MatchWaitingViewModel?
        do {
            let viewModel = make(repository)
            released = viewModel
            #expect(await eventually { repository.detailReads == 1 })
        }
        #expect(await eventually { released == nil }, "조회가 뷰모델을 잡고 있다")
        #expect(await eventually { repository.detailCancelled == 1 }, "뷰모델이 해제됐는데 조회가 끊기지 않았다")
    }

    /// 쪼갠 뒤에도 원본 규칙이 그대로다 — 실패는 에러 화면, 다시 시도의 성공은 방 표시.
    @Test("refresh - 실패하면 에러를 띄우고 다시 시도가 성공하면 방을 그린다")
    func refreshPublishesResult() async {
        let repository = FakeRepository(detail: .failure(StubError()))
        let viewModel = make(repository)
        #expect(await eventually { viewModel.uiState == .error(message: "매칭 정보를 불러오지 못했어요") })

        repository.setDetail(Self.okDetail())
        viewModel.refresh()
        #expect(await eventually { viewModel.uiState == .success(ride: Self.ride()) })
    }

    /// **PORTING 6장의 그 규칙.** 가려져서 취소된 수집은 종결이 아니다 — 복귀하면 다시 붙어야 한다.
    @Test("streamEnded - 가려져서 끊긴 구독은 종결로 적히지 않고 복귀 때 다시 붙는다")
    func hiddenStreamIsNotTerminal() async {
        let repository = FakeRepository(detail: Self.okDetail())
        let viewModel = make(repository)
        #expect(await eventually { repository.subscriptions == 1 })

        viewModel.onScreenStop()
        #expect(await eventually { repository.terminated == 1 })
        await settle()
        #expect(repository.subscriptions == 1, "가려진 동안 다시 붙으면 안 된다")

        viewModel.onScreenStart()
        #expect(await eventually { repository.subscriptions == 2 }, "복귀해도 SSE 를 다시 붙이지 않는다")
        #expect(repository.alive == 1, "살아 있는 수집은 하나뿐이어야 한다")
    }

    /// 빠르게 토글해도 겹치지 않는다 — 겹치면 서버가 서로의 연결을 끊는 무한 재연결이 된다.
    @Test("수집은 어느 순간에도 하나뿐이다 - 가시성이 빠르게 토글돼도")
    func rapidToggleSingleCollector() async {
        let repository = FakeRepository(detail: Self.okDetail())
        let viewModel = make(repository)
        #expect(await eventually { repository.subscriptions == 1 })

        for _ in 0..<5 {
            viewModel.onScreenStop()
            viewModel.onScreenStart()
            await settle()
            #expect(repository.alive <= 1)
        }
        #expect(await eventually { repository.alive == 1 })
    }

    /// 스스로 끝난 스트림은 종결이다 — 복귀해도 붙지 않고, 폴백이 6초를 기다리지 않고 바로 읽는다.
    @Test("streamEnded - 스스로 끝난 스트림은 다시 붙지 않고 폴백이 즉시 읽는다")
    func finishedStreamIsTerminal() async {
        let repository = FakeRepository(detail: Self.okDetail())
        let viewModel = make(repository)
        #expect(await eventually { repository.subscriptions == 1 && repository.detailReads == 1 })

        repository.latest()?.finish()
        #expect(await eventually { repository.detailReads == 2 }, "READ_NOW 로 즉시 읽어야 한다")

        viewModel.onScreenStop()
        await settle()
        viewModel.onScreenStart()
        await settle()
        #expect(repository.subscriptions == 1, "종결로 끝난 스트림을 다시 붙였다")
    }

    /// 403 — 화면을 떠나게 하고 내가 없는 방을 더 읽지 않는다.
    @Test("403 - 멤버십 상실이 서고 폴백이 읽지 않는다")
    func membershipLostStops() async {
        let repository = FakeRepository(detail: Self.okDetail())
        let viewModel = make(repository)
        #expect(await eventually { repository.subscriptions == 1 && repository.detailReads == 1 })

        repository.latest()?.finish(throwing: PartyMembershipLostException(partyId: 1))
        #expect(await eventually { viewModel.membershipLost })
        await settle()

        #expect(repository.detailReads == 1, "내가 없는 방을 읽었다")
        #expect(!viewModel.partyClosed, "방이 닫힌 것과 뭉개면 안 된다")
    }

    /// 화면을 떠나 뷰모델이 해제되면 연결도 끊긴다. 태스크가 뷰모델을 강하게 잡으면 영영 남는다.
    @Test("뷰모델이 해제되면 SSE 수집도 끝난다")
    func deinitCancelsStream() async {
        let repository = FakeRepository(detail: Self.okDetail())
        var viewModel: MatchWaitingViewModel? = make(repository)
        weak let released = viewModel
        #expect(await eventually { repository.subscriptions == 1 && repository.detailReads == 1 })

        viewModel = nil

        #expect(await eventually { released == nil }, "뷰모델이 해제되지 않았다")
        #expect(await eventually { repository.terminated == 1 }, "연결이 남았다")
    }

    @Test("스냅샷으로 방을 그리고, 살아 있는 동안 폴백은 읽지 않는다")
    func snapshotAndNoPolling() async {
        let repository = FakeRepository(detail: .failure(StubError()))
        // 대기가 곧바로 끝나 폴백이 빠르게 돈다 — 살아 있으면 그래도 읽지 않아야 한다.
        let viewModel = make(repository, sleep: { _ in try await Task.sleep(for: .milliseconds(5)) })
        #expect(await eventually { repository.subscriptions == 1 })

        let ride = Self.ride(members: [Self.me, Self.other])
        repository.latest()?.yield(.snapshot(ride: ride, version: 3))
        #expect(await eventually { viewModel.uiState == .success(ride: ride) })

        let reads = repository.detailReads
        await settle()
        #expect(repository.detailReads == reads, "SSE 가 살아 있는데 상세를 읽었다")

        repository.latest()?.yield(.disconnected)
        #expect(await eventually { repository.detailReads > reads }, "끊겼는데 폴백이 돌지 않았다")
    }

    @Test("closed 신호를 받으면 방이 닫혔다고 알린다")
    func closedSignal() async {
        let repository = FakeRepository(detail: Self.okDetail())
        let viewModel = make(repository)
        #expect(await eventually { repository.subscriptions == 1 })

        repository.latest()?.yield(.closed)

        #expect(await eventually { viewModel.partyClosed })
        #expect(!viewModel.membershipLost)
    }

    /// 재연결 스냅샷이 낡았으면 반영한 합류를 지우지 않는다.
    @Test("낡은 스냅샷이 반영한 합류를 지우지 않는다")
    func staleSnapshotDropped() async {
        let repository = FakeRepository(detail: .failure(StubError()))
        let viewModel = make(repository)
        #expect(await eventually { repository.subscriptions == 1 })

        repository.latest()?.yield(.snapshot(ride: Self.ride(), version: 1))
        repository.latest()?.yield(.memberJoined(member: Self.other, status: .recruiting, version: 2))
        let joined = Self.ride(members: [Self.me, Self.other])
        #expect(await eventually { viewModel.uiState == .success(ride: joined) })

        repository.latest()?.yield(.snapshot(ride: Self.ride(), version: 1))
        await settle()
        #expect(viewModel.uiState == .success(ride: joined))
    }

    @Test("첫 조회가 실패하면 에러 문구를 띄우고, 다시 시도하면 방을 그린다")
    func refreshErrorThenRetry() async {
        let repository = FakeRepository(detail: .failure(StubError()))
        let viewModel = make(repository)
        #expect(await eventually { viewModel.uiState == .error(message: "매칭 정보를 불러오지 못했어요") })

        repository.setDetail(Self.okDetail())
        viewModel.refresh()

        #expect(await eventually { viewModel.uiState == .success(ride: Self.ride()) })
    }

    @Test("상세의 목록에서 내가 사라지면 멤버십 상실이 선다")
    func detailDetectsLostMembership() async {
        let repository = FakeRepository(detail: Self.okDetail())
        let viewModel = make(repository)
        #expect(await eventually { viewModel.uiState == .success(ride: Self.ride()) })

        repository.setDetail(Self.okDetail(ride: Self.ride(members: [Self.other]), version: 2))
        viewModel.refresh()

        #expect(await eventually { viewModel.membershipLost })
    }

    @Test("나가기 - 성공하면 left 가 서고 진행 표시가 내려간다")
    func leaveSuccess() async {
        let repository = FakeRepository(detail: Self.okDetail())
        let viewModel = make(repository)

        viewModel.leaveParty()
        #expect(viewModel.actionState.inProgress, "두 번째 탭을 막으려면 바로 서야 한다")
        viewModel.leaveParty()

        #expect(await eventually { viewModel.actionState.left && !viewModel.actionState.inProgress })
        #expect(repository.leaveCalls == 1, "중복 실행 차단이 듣지 않았다")
    }

    @Test("나가기·합승 완료 실패는 사유별 문구로 옮긴다")
    func actionFailureMessages() async {
        let repository = FakeRepository(detail: Self.okDetail())
        let viewModel = make(repository)

        repository.leaveError = PartyLeaveException(
            code: PartyLeaveException.PARTY_NOT_RECRUITING,
            serverMessage: nil,
            httpStatus: 409
        )
        viewModel.leaveParty()
        #expect(await eventually { viewModel.actionState.errorMessage == "이미 끝난 방이에요. 홈으로 돌아가 주세요" })
        #expect(!viewModel.actionState.inProgress)
        #expect(!viewModel.actionState.left)

        repository.leaveError = StubError()
        viewModel.leaveParty()
        #expect(await eventually { viewModel.actionState.errorMessage == "방에서 나가지 못했어요" })

        repository.finishError = PartyFinishException(
            code: PartyFinishException.NOT_PARTY_HOST,
            serverMessage: nil,
            httpStatus: 403
        )
        viewModel.finishParty()
        #expect(await eventually {
            viewModel.actionState.errorMessage == "방장만 합승을 완료할 수 있어요. 가장 먼저 참여한 분에게 부탁해 주세요"
        })

        repository.finishError = StubError()
        viewModel.finishParty()
        #expect(await eventually { viewModel.actionState.errorMessage == "합승을 완료하지 못했어요" })
        #expect(!viewModel.actionState.finished)
    }

    // ─── 약속 확정 · 도착 · 출발 ───────────────────────────────────────────────

    /// 확정 프레임은 `isConfirmed` 와 약속 시각만 싣는다 — status 는 문자열이라 건드리지 않는다
    /// (`Ride.withMeetingConfirmed`). 그래도 화면이 확정 단계를 그리는 근거가 이 두 값이다.
    @Test("confirmed - SSE 가 확정을 알리면 isConfirmed 와 약속 시각을 반영한다")
    func confirmedFrameApplies() async {
        let repository = FakeRepository(detail: .failure(StubError()))
        let viewModel = make(repository)
        #expect(await eventually { repository.subscriptions == 1 })

        let held = Self.ride(members: [Self.me, Self.other])
        repository.latest()?.yield(.snapshot(ride: held, version: 3))
        #expect(await eventually { viewModel.uiState == .success(ride: held) })

        repository.latest()?.yield(.confirmed(status: "COMPLETED", departureAt: "2026-11-06T06:30:00Z", version: 4))

        // status 는 들고 있던 RECRUITING 그대로다 — 프레임의 문자열 status 로 RideStatus 를 바꾸지 않는다.
        var confirmed = held
        confirmed.isConfirmed = true
        confirmed.departureAt = "2026-11-06T06:30:00Z"
        #expect(await eventually { viewModel.uiState == .success(ride: confirmed) })
    }

    /// 아는 사람의 도착은 그 줄만 고치고, 모르는 사람의 도착은 **목록이 낡았다**는 뜻이라 상세를 읽는다
    /// (`Ride.withMemberArrived`) — 노쇼 인원 수가 이 목록에서 나오기 때문이다.
    @Test("memberArrived - 아는 사람은 그 줄만 고치고, 모르는 사람이면 상세를 다시 읽는다")
    func memberArrivedFrame() async {
        let repository = FakeRepository(detail: .failure(StubError()))
        let viewModel = make(repository)
        #expect(await eventually { repository.subscriptions == 1 })

        let held = Self.ride(members: [Self.me, Self.other])
        repository.latest()?.yield(.snapshot(ride: held, version: 3))
        #expect(await eventually { viewModel.uiState == .success(ride: held) })
        let reads = repository.detailReads

        repository.latest()?.yield(.memberArrived(publicId: "u2", version: 4))
        var arrived = held
        arrived.members[1].hasArrived = true
        #expect(await eventually { viewModel.uiState == .success(ride: arrived) })
        await settle()
        #expect(repository.detailReads == reads, "목록에 있는 사람인데 상세를 읽었다")

        repository.latest()?.yield(.memberArrived(publicId: "u9", version: 5))
        #expect(await eventually { repository.detailReads == reads + 1 }, "목록에 없는 사람의 도착인데 상세를 읽지 않았다")
        #expect(viewModel.uiState == .success(ride: arrived), "없는 줄을 지어내면 안 된다")
    }

    /// 204 면 확정은 사실이다 — SSE 를 기다리지 않고 들고 있는 방을 고친다. 보낸 값은 화면이 넘긴 그 문자열이다.
    @Test("confirmMeeting - 성공하면 보낸 시각 그대로 확정된 방을 그린다")
    func confirmMeetingSuccess() async {
        let held = Self.ride(members: [Self.me, Self.other])
        let repository = FakeRepository(detail: Self.okDetail(ride: held))
        let viewModel = make(repository)
        #expect(await eventually { viewModel.uiState == .success(ride: held) })

        viewModel.confirmMeeting(departureAt: "2026-11-06T06:30:00Z")

        var confirmed = held
        confirmed.isConfirmed = true
        confirmed.departureAt = "2026-11-06T06:30:00Z"
        #expect(await eventually { viewModel.uiState == .success(ride: confirmed) && !viewModel.actionState.inProgress })
        #expect(repository.confirmedDepartureAt == ["2026-11-06T06:30:00Z"], "다이얼로그가 보여 준 값이 아닌 시각을 보냈다")
    }

    /// 내 도착은 `member-arrived` 를 기다리지 않고 그 자리에서 고친다 — 고치지 않으면 같은 버튼을 다시 누른다.
    @Test("arriveAtDeparture - 성공하면 내 줄이 도착으로 바뀐다")
    func arriveSuccess() async {
        var held = Self.ride(members: [Self.me, Self.other])
        held.isConfirmed = true
        let repository = FakeRepository(detail: Self.okDetail(ride: held))
        let viewModel = make(repository)
        #expect(await eventually { viewModel.uiState == .success(ride: held) })

        viewModel.arriveAtDeparture(latitude: 35.1688, longitude: 129.1306)

        var arrived = held
        arrived.members[0].hasArrived = true
        #expect(await eventually { viewModel.uiState == .success(ride: arrived) && !viewModel.actionState.inProgress })
        #expect(repository.arrivedAt.map(\.latitude) == [35.1688])
        #expect(repository.arrivedAt.map(\.longitude) == [129.1306])
    }

    /// 출발은 방을 모두에게 닫는다 — `departed` 가 Route 를 홈으로 보내는 신호다.
    @Test("departParty - 성공하면 departed 가 선다")
    func departSuccess() async {
        let repository = FakeRepository(detail: Self.okDetail())
        let viewModel = make(repository)

        viewModel.departParty()

        #expect(await eventually { viewModel.actionState.departed && !viewModel.actionState.inProgress })
        #expect(repository.departCalls == 1)
        #expect(!viewModel.actionState.finished, "합승 완료와 다른 신호다")
    }

    @Test("약속 확정·도착·출발 실패는 사유별 문구로 옮긴다")
    func meetingActionFailureMessages() async {
        let repository = FakeRepository(detail: Self.okDetail())
        let viewModel = make(repository)

        repository.confirmError = PartyConfirmException(code: PartyConfirmException.ALREADY_CONFIRMED, serverMessage: nil)
        viewModel.confirmMeeting(departureAt: "2026-11-06T06:30:00Z")
        #expect(await eventually { viewModel.actionState.errorMessage == "이미 약속 시간이 정해진 방이에요" })

        repository.arriveError = PartyArriveException(code: PartyArriveException.TOO_FAR_FROM_DEPARTURE, serverMessage: nil)
        viewModel.arriveAtDeparture(latitude: 35.0, longitude: 129.0)
        #expect(await eventually {
            viewModel.actionState.errorMessage
                == "출발지에서 100m 안에 있어야 도착을 알릴 수 있어요. 출발지로 더 가까이 가 주세요"
        })

        repository.departError = StubError()
        viewModel.departParty()
        #expect(await eventually { viewModel.actionState.errorMessage == "출발하지 못했어요" })
        #expect(!viewModel.actionState.departed)
        #expect(!viewModel.actionState.inProgress)
    }

    /// 약속 시계는 SSE·폴백과 같은 가시성 스위치에 묶인다 — 가려진 동안 멈추고, 돌아오면 **곧바로** 찍는다.
    @Test("약속 시계는 화면이 보이는 동안에만 흐르고 복귀하면 곧바로 찍는다")
    func meetingClockFollowsVisibility() async {
        final class Ticker: @unchecked Sendable {
            private let lock = NSLock()
            private var value: Int64 = 0
            func next() -> Int64 { lock.withLock { value += 1; return value } }
        }
        let ticker = Ticker()
        let repository = FakeRepository(detail: Self.okDetail())
        // 10초 틱만 빨리 돌리고, 폴백 대기(6초)는 막아 둔다.
        let viewModel = MatchWaitingViewModel(
            repository: repository,
            partyId: 1,
            clock: { ticker.next() },
            sleep: { duration in
                if duration == .seconds(10) {
                    try await Task.sleep(for: .milliseconds(5))
                } else {
                    try await Task.sleep(for: .seconds(3600))
                }
            }
        )
        let start = viewModel.nowMillis
        #expect(await eventually { viewModel.nowMillis > start + 2 }, "보이는 동안 시계가 흐르지 않는다")

        viewModel.onScreenStop()
        await settle()
        let frozen = viewModel.nowMillis
        await settle()
        #expect(viewModel.nowMillis == frozen, "가려진 동안 시계가 흐른다")

        viewModel.onScreenStart()
        #expect(await eventually { viewModel.nowMillis > frozen }, "복귀했는데 시계가 다시 찍히지 않는다")
    }
}
