import Foundation
import MoyeotaDomain
import os
import Testing
@testable import MoyeotaData

/// 세션 uuid 와 첫 멤버의 publicId 가 같은 값이어야 "나" 판정이 성립한다.
private let UUID_ME = "01a06145-3caf-7614-a3bd-cee6e25316b1"
private let UUID_OTHER = "01a06145-3caf-7614-a3bd-cee6e2531999"

/// 이 방의 멤버 목록에 **없는** 계정 — "다른 방에 참여 중" 판정을 가르는 데 쓴다.
private let UUID_STRANGER = "01a06145-3caf-7614-a3bd-cee6e2531aaa"

/// 로그인한 사용자를 흉내 내는 세션. uuid 가 null 이면 미로그인/복원 전이다.
private struct FakeSession: UserSession {
    let authState: StateFlow<AuthState>

    init(uuid: String? = UUID_ME) {
        authState = MutableStateFlow<AuthState>(uuid.map { .authenticated(userUuid: $0) } ?? .unauthenticated)
    }
}

@Suite struct RemoteRideRepositoryTest {

    private func session(uuid: String? = UUID_ME) -> any UserSession { FakeSession(uuid: uuid) }

    /// 합류 응답이 방 상세 → `PartyStatusResponse` 로 바뀌었다(Backend #213). 동승자 목록은 오지 않으므로
    /// 저장소도 **상태만** 돌려준다 — 몰래 상세를 한 번 더 읽어 Ride 를 만들어 주면, 합류 왕복이 2회로
    /// 늘어난 걸 호출부가 모르게 된다(대기 화면은 SSE 스냅샷으로 상세를 받는다).
    @Test("합류는 상태와 인원만 돌려주고 상세를 부르지 않는다")
    func joinReturnsStatusOnly() async throws {
        let api = FakeMatchingApi()

        let status = try await RemoteRideRepository(api: api, session: session()).joinParty(partyId: 7)

        // 합류자는 Bearer 토큰이 정한다 — partyId 외에 아무것도 넘기지 않는다.
        #expect(api.joinCall.value == 7)
        #expect(api.detailCallCount.value == 0)
        #expect(status.status == .matched)
        #expect(status.currentMembers == 2)
    }

    /// 서버는 멤버 목록에 "누가 나인지"를 표시해 주지 않는다 — publicId 와 세션 uuid 비교가 유일한 근거다.
    /// 저장소가 세션을 매퍼에 흘려보내지 않으면 화면의 「나 제외」 카운트와 나 배지가 통째로 어긋난다.
    @Test("상세 응답의 멤버 중 세션 uuid 와 같은 사람을 나로 표시한다")
    func detailMarksMe() async throws {
        let repository = RemoteRideRepository(api: FakeMatchingApi(), session: session())

        let detail = try await repository.getPartyDetail(partyId: 7)

        #expect(detail.members.map(\.isMe) == [true, false])
        #expect(detail.members.map(\.nickname) == ["성윤", "다른사람"])
        #expect(detail.members[0].rideCount == 4)
    }

    /// 서버는 **멤버 추가를 먼저 커밋**하고 응답을 만든다. 그 응답을 앱이 놓치면 서버에는 들어가 있는데
    /// 화면은 실패로 끝나고, 재시도는 409 로 막힌다 — 복구가 없으면 30분 스윕 전까지 그 계정이
    /// 어떤 방에도 못 들어간다. 그래서 409 를 받으면 상세로 **내가 이미 멤버인지 확인해** 되돌린다.
    @Test("이미 참여 중 409 는 상세로 멤버십을 확인해 복구 신호로 올린다")
    func alreadyJoinedRecovers() async throws {
        let api = FakeMatchingApi(joinFailure: conflict("ALREADY_JOINED_OTHER_PARTY", "이미 참여 중인 방이 있습니다."))

        let error = try await thrownError(PartyJoinException.self) {
            _ = try await RemoteRideRepository(api: api, session: session()).joinParty(partyId: 7)
        }

        // 확인은 추측이 아니라 상세 조회다 — 한 번은 반드시 읽는다.
        #expect(api.detailCallCount.value == 1)
        #expect(error.isAlreadyInThisParty)
        #expect(!error.isAlreadyInAnotherParty)
        // 복구에 필요한 건 "그 방의 지금 상태" — 합류 성공과 같은 모양으로 넘길 수 있어야 한다.
        #expect(error.joinedStatus?.status == .matched)
        #expect(error.joinedStatus?.currentMembers == 2)
    }

    /// 상세에 내가 없으면 **다른 방**에 있는 것이다 — 그 방을 정리해야 들어갈 수 있다는 다른 안내가 필요하다.
    @Test("상세에 내가 없으면 다른 방에 참여 중으로 올린다")
    func alreadyJoinedOtherParty() async throws {
        let api = FakeMatchingApi(joinFailure: conflict("ALREADY_JOINED_OTHER_PARTY", "이미 참여 중인 방이 있습니다."))

        // 세션 uuid 가 멤버 목록에 없는 계정.
        let error = try await thrownError(PartyJoinException.self) {
            _ = try await RemoteRideRepository(api: api, session: session(uuid: UUID_STRANGER)).joinParty(partyId: 7)
        }

        #expect(!error.isAlreadyInThisParty)
        #expect(error.isAlreadyInAnotherParty)
        #expect(error.joinedStatus == nil)
    }

    /// 「이미 참여 중」이 아닌 실패는 상세를 읽을 이유가 없다 — 쓸데없는 왕복을 늘리지 않는다.
    @Test("정원 초과 409 는 상세를 읽지 않고 그대로 올린다")
    func partyFullDoesNotReadDetail() async throws {
        let api = FakeMatchingApi(joinFailure: conflict("PARTY_FULL", "정원이 가득 찬 방입니다."))

        let error = try await thrownError(PartyJoinException.self) {
            _ = try await RemoteRideRepository(api: api, session: session()).joinParty(partyId: 7)
        }

        #expect(api.detailCallCount.value == 0)
        #expect(error.isPartyFull)
        #expect(!error.isAlreadyInThisParty)
        #expect(error.httpStatus == 409)
        // 서버 원문을 그대로 들고 온다 — 화면 문구는 화면이 정한다.
        #expect(error.serverMessage == "정원이 가득 찬 방입니다.")
    }

    @Test("미로그인 상태에서는 아무도 나로 표시되지 않는다")
    func loggedOutMarksNobody() async throws {
        let ride = try await RemoteRideRepository(api: FakeMatchingApi(), session: session(uuid: nil))
            .getPartyDetail(partyId: 7)

        #expect(!ride.members.contains { $0.isMe })
    }

    @Test("나가기도 partyId 만 넘긴다 — 나가는 주체는 토큰이 정한다")
    func leavePassesPartyIdOnly() async throws {
        let api = FakeMatchingApi()

        try await RemoteRideRepository(api: api, session: session()).leaveParty(partyId: 7)

        #expect(api.leaveCall.value == 7)
    }

    @Test("방 생성 요청 본문에는 좌표 라벨 정원만 실린다 — 생성자는 토큰이 정한다")
    func createSendsCoordinatesLabelsCapacity() async throws {
        let api = FakeMatchingApi()

        let ride = try await RemoteRideRepository(api: api, session: session()).createParty(
            request: NewParty(
                departureLat: 37.5665,
                departureLng: 126.9780,
                destinationLat: 37.4979,
                destinationLng: 127.0276,
                departure: "서울시청",
                destination: "강남역",
                capacity: 3
            )
        )

        // 서버는 생성자를 토큰에서 정한다 — 본문에는 좌표·라벨·정원만 실린다.
        #expect(api.openRequest.value?.departure == "서울시청")
        #expect(ride.id == "12")
        // 생성 응답에 members 목록이 없어 currentMembers 만큼 자리 표시용 멤버를 만든다.
        #expect(ride.members.count == 1)
    }

    @Test("지도 범위 조회는 남서 북동 순서 그대로 API 에 넘기고 출발 좌표를 채워 돌려준다")
    func withinKeepsArgumentOrder() async throws {
        let api = FakeMatchingApi()

        let rides = try await RemoteRideRepository(api: api, session: session()).getPartiesWithin(
            swLat: 35.20,
            swLng: 129.05,
            neLat: 35.26,
            neLng: 129.12
        )

        // 순서가 뒤바뀌면 서버가 빈 목록을 돌려준다 — 인자 순서를 고정한다.
        #expect(api.withinCall.value == [35.20, 129.05, 35.26, 129.12])
        #expect(rides.count == 1)
        #expect(rides[0].id == "1")
        #expect(isClose(35.2313, rides[0].originLat, 0.00001))
        #expect(isClose(129.0838, rides[0].originLng, 0.00001))
        #expect(rides[0].status == .recruiting)
    }

    @Test("더미 저장소는 범위 밖 방을 걸러낸다")
    func dummyFiltersByBounds() async throws {
        let repository = DummyRideRepository()

        // 성결대 주변(37.37~37.39, 126.91~126.94)만 포함하는 범위.
        #expect(try await repository.getPartiesWithin(swLat: 37.37, swLng: 126.91, neLat: 37.39, neLng: 126.94).count == 2)
        // 부산 범위에는 아무것도 없다.
        #expect(try await repository.getPartiesWithin(swLat: 35.20, swLng: 129.05, neLat: 35.26, neLng: 129.12).isEmpty)
    }

    @Test("경로 미리보기는 좌표 4개를 본문으로 보내고 path 를 encodedPath 로 돌려준다")
    func previewRouteMapsPath() async throws {
        let api = FakeMatchingApi()

        let estimate = try await RemoteRideRepository(api: api, session: session()).previewRoute(
            departureLat: 35.2313,
            departureLng: 129.0838,
            destinationLat: 35.1580,
            destinationLng: 129.0594
        )

        // 순서가 뒤바뀌면 엉뚱한 경로가 나온다 — 출발/도착 좌표 배치를 고정한다.
        #expect(
            api.routeRequest.value == RouteRequestDto(
                departureLat: 35.2313,
                departureLng: 129.0838,
                destinationLat: 35.1580,
                destinationLng: 129.0594
            )
        )
        #expect(estimate.estimatedFare == 12_800)
        #expect(estimate.estimatedMinutes == 35)
        // 서버 응답 필드명은 route 가 아니라 path 다.
        #expect(estimate.encodedPath == "ub`vEwtzrW?BQxA")
    }

    @Test("더미 경로 미리보기는 거리에 비례한 요금과 두 점짜리 폴리라인을 돌려준다")
    func dummyPreviewRoute() async throws {
        // 부산대 정문 → 서면역: 직선 약 8.4km.
        let estimate = try await DummyRideRepository().previewRoute(
            departureLat: 35.2313,
            departureLng: 129.0838,
            destinationLat: 35.1580,
            destinationLng: 129.0594
        )

        #expect(estimate.estimatedFare > 4_800, "요금이 기본요금보다 커야 한다")
        #expect(estimate.estimatedMinutes > 3, "소요시간이 승하차 시간보다 커야 한다")
        // 정확히 두 점을 인코딩한 폴리라인(Google precision 5).
        #expect(estimate.encodedPath == "sb`vEwtzrWbiMnwC")
    }

    /// 25·26 의 주기 조회가 **상세로 옮겨왔다** — 가벼운 상태 조회(`/status`)가 백엔드에서 삭제됐기
    /// 때문이다(`04f6be7`). 그 호출을 되살리면 404 라, 저장소에 남아 있으면 안 된다.
    ///
    /// 같은 방을 두 번 읽으면 `==` 로 같아야 한다 — 그게 두 화면이 「안 바뀌었다」를 판정하는 유일한
    /// 근거이고(지문이 하던 일), 어긋나면 매 주기 화면 상태가 갈려 화면 갱신이 멈추지 않는다.
    @Test("주기 조회는 상세를 읽고 같은 방을 두 번 읽으면 서로 같다")
    func pollingReadsDetailStable() async throws {
        let api = FakeMatchingApi()
        let repository = RemoteRideRepository(api: api, session: session())

        let first = try await repository.getPartyDetail(partyId: 7)
        let second = try await repository.getPartyDetail(partyId: 7)

        #expect(api.detailCallCount.value == 2)
        #expect(first == second)
        #expect(first.status == .matched)
        #expect(first.members.count == 2)
    }

    /// 더미 저장소도 같은 방을 두 번 읽으면 같아야 한다 — 디버그 빌드에서 폴링이 헛돌지 않게.
    @Test("더미 저장소의 상세도 두 번 읽으면 서로 같다")
    func dummyDetailStable() async throws {
        let repository = DummyRideRepository()

        let first = try await repository.getPartyDetail(partyId: 1)
        let second = try await repository.getPartyDetail(partyId: 1)
        #expect(first == second)
    }

    // MARK: - 「합승 완료」 실패 (403·409 가 각각 두 가지 뜻)

    /// 「합승 완료」는 **방장 전용**이 됐다(Backend #237). 비방장이 누르면 403 `NOT_PARTY_HOST` 다.
    /// 버튼 노출을 먼저 막아도(`members[].host`, Backend #240) 승계 신호를 놓치면 내 스냅샷이 낡아 이 403 이
    /// 남는다(`RideRepository.finishParty` 주석) — 그때는 **이 실패가 사유를 들고 올라오는 것**이 안내 수단이다.
    @Test("합승 완료 403 은 방장 아님을 코드로 구분해 올린다")
    func finish403NotHost() async throws {
        let api = FakeMatchingApi(
            finishFailure: httpError(403, "NOT_PARTY_HOST", "방장만 수행할 수 있습니다.")
        )

        let error = try await thrownError(PartyFinishException.self) {
            try await RemoteRideRepository(api: api, session: session()).finishParty(partyId: 7)
        }

        #expect(api.finishCall.value == 7)
        #expect(error.isNotHost)
        // 같은 403 인 「멤버 아님」과 섞이면 방 멤버가 아닌 사람에게 방장을 찾으라고 말하게 된다.
        #expect(!error.isNotMember)
        #expect(error.httpStatus == 403)
        // 서버 원문을 그대로 들고 온다 — 화면 문구는 화면이 정한다.
        #expect(error.serverMessage == "방장만 수행할 수 있습니다.")
    }

    /// 같은 403 이지만 뜻이 다르다 — 멤버가 아니면 방장을 찾는 게 할 일이 아니다.
    @Test("합승 완료 403 중 멤버 아님은 방장 아님과 갈린다")
    func finish403NotMember() async throws {
        let api = FakeMatchingApi(
            finishFailure: httpError(403, "NOT_PARTY_MEMBER", "해당 방에 참여하고 있지 않습니다.")
        )

        let error = try await thrownError(PartyFinishException.self) {
            try await RemoteRideRepository(api: api, session: session()).finishParty(partyId: 7)
        }

        #expect(error.isNotMember)
        #expect(!error.isNotHost)
    }

    /// 409 는 이제 **정원 미달 하나뿐**이다. `DRIVER_ALREADY_ASSIGNED` 는 서버가 기사·배차를 걷어내며
    /// **에러 코드째 지웠다**(서버 `MatchingErrorCode` 에 없다).
    ///
    /// 그래도 그 코드가 오는 경우를 함께 고정한다 — 옛 서버나 되돌린 배포가 보낼 수 있고, 그때 앱은
    /// **사유를 추측하지 않고** 코드만 들고 와 일반 문구로 떨어져야 한다. 삭제한 분기가 「어느 사유도
    /// 아님」으로 떨어지는 것까지가 이 삭제의 안전함이다.
    @Test("합승 완료 409 는 정원 미달뿐이고 사라진 기사 코드는 사유가 되지 않는다")
    func finish409OnlyNotCompleted() async throws {
        let notCompleted = try await thrownError(PartyFinishException.self) {
            try await RemoteRideRepository(
                api: FakeMatchingApi(finishFailure: conflict("PARTY_NOT_COMPLETED", "정원이 다 차지 않은 방입니다.")),
                session: session()
            ).finishParty(partyId: 7)
        }

        let removedDriverCode = try await thrownError(PartyFinishException.self) {
            try await RemoteRideRepository(
                api: FakeMatchingApi(finishFailure: conflict("DRIVER_ALREADY_ASSIGNED", "이미 기사가 배정된 방입니다.")),
                session: session()
            ).finishParty(partyId: 7)
        }

        #expect(notCompleted.isNotCompleted)

        #expect(removedDriverCode.code == "DRIVER_ALREADY_ASSIGNED")
        #expect(!removedDriverCode.isNotCompleted)
        #expect(!removedDriverCode.isNotHost)
        #expect(!removedDriverCode.isNotMember)
    }

    /// **서버가 코드를 늘려도 앱이 틀린 말을 하면 안 된다.** 모르는 코드·빈 본문은 code = null 로 올라와
    /// 화면이 일반 문구로 떨어진다 — 403 이라고 「방장만」을, 409 라고 「정원 미달」을 **추측하지 않는다**.
    @Test("모르는 코드와 빈 본문은 code 가 null 이고 사유를 추측하지 않는다")
    func finishUnknownCodeAndEmptyBody() async throws {
        let unknownCode = try await thrownError(PartyFinishException.self) {
            try await RemoteRideRepository(
                api: FakeMatchingApi(finishFailure: httpError(409, "PARTY_SOMETHING_NEW", "새 규칙입니다.")),
                session: session()
            ).finishParty(partyId: 7)
        }

        let bodyless = try await thrownError(PartyFinishException.self) {
            try await RemoteRideRepository(api: FakeMatchingApi(finishFailure: bodylessError(403)), session: session())
                .finishParty(partyId: 7)
        }

        // 모르는 코드는 그대로 들고 오지만 어느 사유도 아니다.
        #expect(unknownCode.code == "PARTY_SOMETHING_NEW")
        #expect(!unknownCode.isNotCompleted)
        #expect(!unknownCode.isNotHost)
        #expect(!unknownCode.isNotMember)

        #expect(bodyless.code == nil)
        #expect(!bodyless.isNotHost)
        #expect(!bodyless.isNotMember)
        #expect(bodyless.httpStatus == 403)
    }

    /// 성공은 204 로 몸통이 없다 — partyId 만 보내고 아무것도 돌려주지 않는다(주체는 Bearer 토큰).
    @Test("합승 완료 성공은 partyId 만 보낸다")
    func finishSuccess() async throws {
        let api = FakeMatchingApi()

        try await RemoteRideRepository(api: api, session: session()).finishParty(partyId: 7)

        #expect(api.finishCall.value == 7)
        #expect(api.detailCallCount.value == 0)
    }

    // MARK: - 방 생성 실패 (409 는 영구 교착, 400 은 사용자가 고쳐야 한다)

    /// **생성 409 가 이 묶음의 이유다.** 서버 `PartyService.open` 첫 줄이 `validateNotInOngoingParty` 이고,
    /// 거기서 보는 「진행 중」은 `!(CANCELED || FINISHED)` 다. 그런데 30분 스윕(`CompletedPartySweeper`)은
    /// **COMPLETED 만** 쓸어내므로 **아무도 합류하지 않은 ACTIVE 방은 영구히 남아** 그 계정의 생성·합류를
    /// 계속 막는다. 사유가 code 로 올라오지 않으면 화면은 「잠시 후 다시 시도해 주세요」만 말할 수 있고,
    /// 그건 영원히 틀린 안내다(기다려서 풀리지 않는다).
    @Test("생성 409 는 이미 참여 중인 방으로 좁혀진다")
    func open409AlreadyInParty() async throws {
        let api = FakeMatchingApi(
            openFailure: conflict("ALREADY_JOINED_OTHER_PARTY", "이미 참여 중인 방이 있습니다.")
        )

        let error = try await thrownError(PartyOpenException.self) {
            _ = try await RemoteRideRepository(api: api, session: session()).createParty(request: newParty())
        }

        #expect(error.isAlreadyInAnotherParty)
        // 합류와 달리 **상세를 읽지 않는다** — 만들려던 방은 아직 없으니 확인할 멤버십이 없다.
        #expect(api.detailCallCount.value == 0)
        #expect(error.httpStatus == 409)
        #expect(error.serverMessage == "이미 참여 중인 방이 있습니다.")
    }

    /// 400 이 네 가지다 — **상태 코드로는 가를 수 없다.** 섞이면 「핀을 옮겨 주세요」를 서비스 지역 밖
    /// 좌표에게, 「인원을 다시」를 좌표 문제에게 말하게 된다.
    @Test("생성 400 은 각 code 로 갈린다")
    func open400ByCode() async throws {
        let same = try await openError(httpError(400, "SAME_DEPARTURE_DESTINATION", "출발지와 도착지가 같습니다."))
        let area = try await openError(httpError(400, "OUT_OF_SERVICE_AREA", "서비스 지역을 벗어난 좌표입니다."))
        let capacity = try await openError(httpError(400, "INVALID_CAPACITY", "방 정원은 1~3명이어야 합니다."))
        let estimate = try await openError(httpError(400, "INVALID_ROUTE_ESTIMATE", "경로 정보가 올바르지 않습니다."))

        #expect(same.isSameDepartureDestination)
        #expect(!same.isOutOfServiceArea)
        #expect(area.isOutOfServiceArea)
        #expect(!area.isSameDepartureDestination)
        #expect(capacity.isInvalidCapacity)
        #expect(!capacity.isRouteUnavailable)
        // 경로 관련 400 은 502 와 **같은 갈래**다 — 사용자가 할 수 있는 일이 같다(위 주석).
        #expect(estimate.isRouteUnavailable)
        #expect(!estimate.isInvalidCapacity)
    }

    /// 502 는 경로 엔진 장애다. 본문이 없어도 상태 코드로 같은 갈래로 떨어뜨린다(게이트웨이 응답 대비).
    @Test("생성 502 는 본문이 없어도 경로 실패로 다룬다")
    func open502IsRouteFailure() async throws {
        #expect(try await openError(httpError(502, "ROUTE_SEARCH_FAILED", "경로 조회에 실패했습니다.")).isRouteUnavailable)
        #expect(try await openError(bodylessError(502)).isRouteUnavailable)
    }

    /// **에러 본문이 JSON 이 아닐 수 있다** — 게이트웨이·프록시가 가로챈 503 은 HTML 을 돌려준다.
    /// 그때 `readApiError()` 는 null 이고, 사유를 **추측하지 않고** 일반 문구로 떨어져야 한다.
    @Test("생성 실패 본문이 HTML 이면 code 없는 예외가 된다")
    func openHtmlBody() async throws {
        let error = try await openError(htmlError(503))

        #expect(error.code == nil)
        #expect(error.serverMessage == nil)
        #expect(error.httpStatus == 503)
        #expect(!error.isAlreadyInAnotherParty)
        #expect(!error.isSameDepartureDestination)
        #expect(!error.isOutOfServiceArea)
        #expect(!error.isInvalidCapacity)
        // 503 을 502 처럼 「경로 실패」로 지어내지 않는다.
        #expect(!error.isRouteUnavailable)
    }

    /// 응답을 아예 못 받은 실패(네트워크)도 code 없는 `PartyOpenException` 이다 — 화면은 일반 문구다.
    @Test("생성 네트워크 실패도 같은 예외로 좁힌다")
    func openNetworkFailure() async throws {
        let error = try await openError(IOException("connection reset"))

        #expect(error.code == nil)
        #expect(error.httpStatus == nil)
        #expect(!error.isAlreadyInAnotherParty)
    }

    // MARK: - 나가기 실패 (403 은 "이미 됨")

    /// **403 `NOT_PARTY_MEMBER` 는 성공이다** — 나가기의 목표가 정확히 「이 방에 내가 없다」이기 때문이다.
    ///
    /// 되돌리지 않으면 204 응답이 유실된 사용자가(터널·타임아웃) 「나가지 못했어요」를 보고 다시 눌러
    /// **같은 문구의 403** 을 맞는다. 로컬 기억과 홈 배너는 그 방을 계속 들고 있으니 화면상 나는 아직
    /// 그 방에 있고, 벗어날 길이 없다. 합류가 409 를 성공으로 되돌리는 것과 대칭인 처방이다.
    @Test("나가기 403 은 성공으로 다룬다")
    func leave403IsSuccess() async throws {
        let api = FakeMatchingApi(
            leaveFailure: httpError(403, "NOT_PARTY_MEMBER", "해당 방에 참여하고 있지 않습니다.")
        )

        // 예외가 나오면 이 줄에서 실패한다 — "성공으로 다룬다"가 곧 "던지지 않는다"다.
        try await RemoteRideRepository(api: api, session: session()).leaveParty(partyId: 7)

        #expect(api.leaveCall.value == 7)
        // 합류의 복구와 달리 **상세로 확인하지 않는다** — 이 403 자체가 "이 방에 내가 없다"다.
        #expect(api.detailCallCount.value == 0)
    }

    /// 409 는 **다른 뜻**이다 — 매칭이 시작돼 나갈 수 없다. 재시도 안내로 뭉개면 영원히 같은 409 다.
    @Test("나가기 409 는 모집 중이 아님으로 좁혀진다")
    func leave409NotRecruiting() async throws {
        let api = FakeMatchingApi(leaveFailure: conflict("PARTY_NOT_RECRUITING", "모집 중인 방이 아닙니다."))

        let error = try await thrownError(PartyLeaveException.self) {
            try await RemoteRideRepository(api: api, session: session()).leaveParty(partyId: 7)
        }

        #expect(error.isNotRecruiting)
        #expect(!error.isPartyNotFound)
        #expect(error.httpStatus == 409)
    }

    /// 404 는 방이 사라진 것 — 나갈 방이 없으므로 홈으로 보내면 된다. 코드 없는 404 도 같게 다룬다.
    @Test("나가기 404 는 방 없음으로 좁혀진다")
    func leave404NotFound() async throws {
        #expect(try await leaveError(httpError(404, "PARTY_NOT_FOUND", "존재하지 않는 방입니다.")).isPartyNotFound)
        #expect(try await leaveError(bodylessError(404)).isPartyNotFound)
    }

    /// 모르는 코드는 그대로 들고 오지만 어느 사유도 아니다 — 서버가 코드를 늘려도 틀린 말을 하지 않는다.
    @Test("나가기 모르는 코드는 사유를 추측하지 않는다")
    func leaveUnknownCode() async throws {
        let error = try await leaveError(httpError(409, "PARTY_SOMETHING_NEW", "새 규칙입니다."))

        #expect(error.code == "PARTY_SOMETHING_NEW")
        #expect(!error.isNotRecruiting)
        #expect(!error.isPartyNotFound)
    }

    // MARK: - 약속 확정 (방을 끝내는 정식 경로의 첫 단계)
    //
    // 실패 사유가 일곱 가지인데 **상태 코드로는 셋으로밖에 안 갈린다**(400·403·409). 그래서 코드로
    // 갈라 두고, 액션마다 예외 타입을 따로 둔다 — 같은 코드가 도착·출발에서는 다른 문장을 요구한다
    // (`PartyConfirmException` 주석의 표).

    /// 본문은 **약속 시간 하나**다. 장소를 싣지 않는 게 계약이다 — 약속 장소는 늘 방의 출발지다.
    /// 좌표를 같이 보내고 싶어지는 자리라, 보내는 것이 그 하나뿐임을 값으로 못박는다.
    @Test("약속 확정은 partyId 와 약속 시간만 보낸다")
    func confirmSendsPartyIdAndTime() async throws {
        let api = FakeMatchingApi()

        try await RemoteRideRepository(api: api, session: session())
            .confirmMeeting(partyId: 7, departureAt: "2026-11-03T08:30:00Z")

        #expect(api.confirmCall.value == 7)
        #expect(api.confirmRequest.value == ConfirmMeetingRequestDto(departureAt: "2026-11-03T08:30:00Z"))
        // 성공 뒤 상세를 다시 읽지 않는다 — 확정 사실·시간·상태가 모두 SSE `confirmed` 에 실려 온다.
        #expect(api.detailCallCount.value == 0)
    }

    /// 앱은 시간을 **검사하지 않고 그대로 싣는다** — 범위 판정은 서버 것이고, 두 벌 들면 한쪽만 낡는다.
    @Test("약속 시간 문자열을 앱이 고치지 않고 그대로 싣는다")
    func confirmSendsTimeVerbatim() async throws {
        let api = FakeMatchingApi()

        // 오프셋이 +09:00 인 모양도 서버가 받는다(ISO-8601 instant). 앱이 Z 로 바꿔 쓰지 않는다.
        try await RemoteRideRepository(api: api, session: session())
            .confirmMeeting(partyId: 7, departureAt: "2026-11-03T17:30:00+09:00")

        #expect(api.confirmRequest.value?.departureAt == "2026-11-03T17:30:00+09:00")
    }

    /// 같은 403 이지만 뜻이 다르다 — 멤버가 아닌 사람에게 「방장을 기다려 주세요」라고 말하면 안 된다.
    @Test("약속 확정 403 은 방장 아님과 멤버 아님으로 갈린다")
    func confirm403HostOrMember() async throws {
        let notHost = try await confirmError(httpError(403, "NOT_PARTY_HOST", "방장만 수행할 수 있습니다."))
        let notMember = try await confirmError(httpError(403, "NOT_PARTY_MEMBER", "해당 방에 참여하고 있지 않습니다."))

        #expect(notHost.isNotHost)
        #expect(!notHost.isNotMember)
        #expect(notMember.isNotMember)
        #expect(!notMember.isNotHost)
        #expect(notHost.serverMessage == "방장만 수행할 수 있습니다.")
        #expect(notHost.httpStatus == 403)
    }

    /// **409 가 네 가지다.** 섞이면 「2명 이상 모여야 해요」를 이미 확정한 방에, 「이미 정했어요」를
    /// 예약 방에 말하게 된다 — 네 사유의 다음 행동이 전부 다르다(기다린다 / 상세를 다시 읽는다 /
    /// 아무것도 못 한다 / 홈으로 간다).
    @Test("약속 확정 409 네 가지가 각 code 로 갈린다")
    func confirm409ByCode() async throws {
        let reserved = try await confirmError(conflict("NOT_REALTIME_PARTY", "실시간 방에서만 할 수 있습니다."))
        let already = try await confirmError(conflict("ALREADY_CONFIRMED", "이미 약속 시간을 확정한 방입니다."))
        let notRecruiting = try await confirmError(conflict("PARTY_NOT_RECRUITING", "모집 중인 방이 아닙니다."))
        let alone = try await confirmError(conflict("NOT_ENOUGH_MEMBERS", "함께 탈 인원이 부족합니다."))

        #expect(reserved.isNotRealtimeParty)
        #expect(already.isAlreadyConfirmed)
        #expect(notRecruiting.isNotRecruiting)
        #expect(alone.isNotEnoughMembers)
        // 서로 섞이지 않는다 — 한 사유가 다른 사유로도 참이면 화면이 두 문구를 동시에 띄운다.
        #expect(!reserved.isAlreadyConfirmed)
        #expect(!already.isNotRecruiting)
        #expect(!notRecruiting.isNotEnoughMembers)
        #expect(!alone.isNotRealtimeParty)
    }

    /// 400 `INVALID_MEETING_TIME` — 지금부터 1시간 밖이다. 화면이 프리셋으로만 고르게 하므로 거의
    /// 오지 않지만 **60분 프리셋이 경계에 붙어 있어** 고르고 누르는 사이 밀리면 떨어진다.
    @Test("약속 확정 400 은 약속 시간 범위로 갈린다")
    func confirm400InvalidTime() async throws {
        let error = try await confirmError(
            httpError(400, "INVALID_MEETING_TIME", "약속 시간은 지금부터 1시간 이내여야 합니다.")
        )

        #expect(error.isInvalidMeetingTime)
        #expect(!error.isNotHost)
        #expect(error.httpStatus == 400)
    }

    /// 404 는 방이 사라진 것. **코드가 없는 404 는 사유로 쓰지 않는다** — 상태 코드로 사유를 지어내지 않는다.
    @Test("약속 확정 404 는 코드가 있을 때만 방 없음이다")
    func confirm404OnlyWithCode() async throws {
        #expect(try await confirmError(httpError(404, "PARTY_NOT_FOUND", "존재하지 않는 방입니다.")).isPartyNotFound)

        let bodyless = try await confirmError(bodylessError(404))
        #expect(bodyless.code == nil)
        #expect(!bodyless.isPartyNotFound)
        #expect(bodyless.httpStatus == 404)
    }

    // MARK: - 출발지 도착

    /// 본문은 **지금 내 위치**다. 방 출발지 좌표를 그대로 보내면 서버의 100m 검사가 **늘 통과**해
    /// 「오지 않은 사람이 도착」이 되고, 그 상태로 누가 출발을 누르면 실제로 안 온 사람에게 노쇼가
    /// 안 찍힌다 — 즉 이 테스트가 깨지면 **노쇼 기록이 조용히 틀린다**.
    @Test("도착은 지금 내 위치를 본문에 싣는다")
    func arriveSendsMyLocation() async throws {
        let api = FakeMatchingApi()

        try await RemoteRideRepository(api: api, session: session())
            .arriveAtDeparture(partyId: 7, latitude: 37.4979, longitude: 127.0276)

        #expect(api.arriveCall.value == 7)
        #expect(api.arriveRequest.value == ArriveRequestDto(latitude: 37.4979, longitude: 127.0276))
        // 위도·경도가 뒤바뀌면 (127, 37) 은 서비스 지역 밖이라 400 OUT_OF_SERVICE_AREA 다.
        #expect(isClose(37.4979, api.arriveRequest.value?.latitude, 1e-9))
        #expect(isClose(127.0276, api.arriveRequest.value?.longitude, 1e-9))
    }

    /// 400 이 두 가지다. 「멀다」와 「서비스 지역 밖」은 사용자가 할 일이 다르고(걸어간다 / 좌표를
    /// 의심한다), 뒤쪽은 **측위 실패를 0.0 으로 채워 보냈을 때**도 온다.
    @Test("도착 400 은 거리와 서비스 지역으로 갈린다")
    func arrive400ByCode() async throws {
        let tooFar = try await arriveError(httpError(400, "TOO_FAR_FROM_DEPARTURE", "출발지에서 100m 안에 있어야 합니다."))
        let outside = try await arriveError(httpError(400, "OUT_OF_SERVICE_AREA", "서비스 지역을 벗어난 좌표입니다."))

        #expect(tooFar.isTooFarFromDeparture)
        #expect(!tooFar.isOutOfServiceArea)
        #expect(outside.isOutOfServiceArea)
        #expect(!outside.isTooFarFromDeparture)
    }

    /// 409 가 셋이다. **「도착 창이 아직 안 열렸다」를 「멀다」와 뭉개면 이미 출발지에 서 있는 사람에게
    /// 더 가까이 가라고 말한다** — 이 액션에서 가장 쉽게 나는 오안내다.
    @Test("도착 409 는 닫힘 미확정 창안열림으로 갈린다")
    func arrive409ByCode() async throws {
        let closed = try await arriveError(conflict("PARTY_CLOSED", "마감된 방입니다."))
        let notConfirmed = try await arriveError(conflict("PARTY_NOT_CONFIRMED", "약속 시간이 확정되지 않은 방입니다."))
        let notOpen = try await arriveError(conflict("ARRIVAL_NOT_OPEN", "도착은 약속 시간 10분 전부터 누를 수 있습니다."))

        #expect(closed.isPartyClosed)
        #expect(notConfirmed.isNotConfirmed)
        #expect(notOpen.isArrivalNotOpen)
        #expect(!notOpen.isTooFarFromDeparture)
        #expect(!notOpen.isNotConfirmed)
    }

    /// **도착과 출발은 시간 코드가 다르다.** 도착이 안 열린 것은 `ARRIVAL_NOT_OPEN`(약속 10분 전 경계,
    /// 백엔드 PR #307)이고 `MEETING_NOT_STARTED` 는 **출발**의 코드다(약속 시간 경계).
    ///
    /// 둘을 한 속성으로 묶으면 화면이 틀린 시각을 말한다 — 도착은 10분 전부터, 출발은 약속 시간
    /// 뒤부터다. 그래서 도착 예외에 `MEETING_NOT_STARTED` 가 와도 **사유가 되지 않는** 것까지 고정한다.
    @Test("도착에 출발의 시간 코드가 오면 사유가 되지 않는다")
    func arriveIgnoresDepartTimeCode() async throws {
        let error = try await arriveError(conflict("MEETING_NOT_STARTED", "아직 약속 시간이 되지 않았습니다."))

        #expect(error.code == "MEETING_NOT_STARTED")
        #expect(!error.isArrivalNotOpen)
        #expect(!error.isNotConfirmed)
        #expect(!error.isPartyClosed)
        #expect(!error.isTooFarFromDeparture)
    }

    // MARK: - 출발 (되돌릴 수 없고 남에게 제재를 남긴다)

    /// 본문이 **없다**. 주체는 Bearer 토큰이고, 방장이 아니어도 된다 — 도착한 멤버면 누구나.
    @Test("출발은 본문 없이 partyId 만 보낸다")
    func departSendsPartyIdOnly() async throws {
        let api = FakeMatchingApi()

        try await RemoteRideRepository(api: api, session: session()).departParty(partyId: 7)

        #expect(api.departCall.value == 7)
        // 합승 완료(finish)와 **다른 엔드포인트**다 — 확정된 방에 finish 를 부르면 409 다.
        #expect(api.finishCall.value == nil)
        #expect(api.detailCallCount.value == 0)
    }

    /// 409 가 다섯이다. 그중 `NOT_ARRIVED` 는 **다음 행동이 명확한 유일한 사유**다 — 「출발지 도착했어요」를
    /// 먼저 누르면 된다. 「다시 시도」로 뭉개면 같은 409 를 영원히 맞는다.
    @Test("출발 409 는 다섯 가지로 갈린다")
    func depart409ByCode() async throws {
        let notArrived = try await departError(conflict("NOT_ARRIVED", "출발지에 도착한 사람만 출발할 수 있습니다."))
        let notStarted = try await departError(conflict("MEETING_NOT_STARTED", "아직 약속 시간이 되지 않았습니다."))
        let alone = try await departError(conflict("NOT_ENOUGH_MEMBERS", "함께 탈 인원이 부족합니다."))
        let notConfirmed = try await departError(conflict("PARTY_NOT_CONFIRMED", "약속 시간이 확정되지 않은 방입니다."))
        let closed = try await departError(conflict("PARTY_CLOSED", "마감된 방입니다."))

        #expect(notArrived.isNotArrived)
        #expect(notStarted.isMeetingNotStarted)
        #expect(alone.isNotEnoughMembers)
        #expect(notConfirmed.isNotConfirmed)
        #expect(closed.isPartyClosed)
        #expect(!notArrived.isMeetingNotStarted)
        #expect(!closed.isNotArrived)
    }

    /// **출발은 방장 전용이 아니다** — 그래서 `NOT_PARTY_HOST` 를 사유로 두지 않았다. 옛 서버나
    /// 되돌린 배포가 그 코드를 보내도 **사유가 되지 않고** 일반 문구로 떨어져야 한다
    /// (「방장만 할 수 있어요」라고 말하면 도착한 멤버가 출발을 포기한다).
    @Test("출발에 방장 전용 코드가 와도 사유가 되지 않는다")
    func departIgnoresHostCode() async throws {
        let error = try await departError(httpError(403, "NOT_PARTY_HOST", "방장만 수행할 수 있습니다."))

        #expect(error.code == "NOT_PARTY_HOST")
        #expect(!error.isNotMember)
        #expect(!error.isNotArrived)
        #expect(error.httpStatus == 403)
    }

    /// 세 액션 모두 **모르는 코드·빈 본문·HTML 본문·네트워크 실패**에서 사유를 지어내지 않는다 —
    /// code = null 이면 화면이 일반 문구로 떨어진다(서버가 코드를 늘려도 앱이 틀린 말을 하지 않는다).
    @Test("세 액션의 모르는 코드와 본문 없는 실패는 사유를 추측하지 않는다")
    func meetingActionsDoNotGuess() async throws {
        let unknownConfirm = try await confirmError(conflict("PARTY_SOMETHING_NEW", "새 규칙입니다."))
        #expect(unknownConfirm.code == "PARTY_SOMETHING_NEW")
        #expect(!unknownConfirm.isAlreadyConfirmed)
        #expect(!unknownConfirm.isNotRecruiting)

        // 게이트웨이가 가로챈 응답(HTML)·본문 없는 응답은 code 가 없다.
        let html = try await arriveError(htmlError(503))
        #expect(html.code == nil)
        #expect(html.serverMessage == nil)
        #expect(!html.isTooFarFromDeparture)
        #expect(html.httpStatus == 503)

        let bodyless = try await departError(bodylessError(409))
        #expect(bodyless.code == nil)
        #expect(!bodyless.isNotArrived)
        #expect(!bodyless.isPartyClosed)

        // 응답 자체를 못 받은 실패도 같은 예외로 좁힌다 — httpStatus 조차 없다.
        let network = try await confirmError(IOException("connection reset"))
        #expect(network.code == nil)
        #expect(network.httpStatus == nil)
        #expect(!network.isNotHost)
    }

    /// 도착·출발이 함께 쓰는 나머지 두 사유. **멤버 아님(403)과 방 없음(404)은 「다시 시도」가 아니라
    /// 「홈으로」**이고, 두 액션에서 뜻이 같아 같은 자리에서 본다.
    ///
    /// 404 는 **코드가 있을 때만** 방 없음이다(본문 없는 404 는 경로 오타·게이트웨이일 수 있어
    /// 사유로 삼지 않는다 — 확정 쪽 테스트와 같은 정책).
    @Test("도착과 출발의 멤버 아님과 방 없음도 사유로 갈린다")
    func arriveDepartMemberAndNotFound() async throws {
        let arriveNotMember = try await arriveError(httpError(403, "NOT_PARTY_MEMBER", "해당 방에 참여하고 있지 않습니다."))
        let departNotMember = try await departError(httpError(403, "NOT_PARTY_MEMBER", "해당 방에 참여하고 있지 않습니다."))
        let arriveGone = try await arriveError(httpError(404, "PARTY_NOT_FOUND", "존재하지 않는 방입니다."))
        let departGone = try await departError(httpError(404, "PARTY_NOT_FOUND", "존재하지 않는 방입니다."))

        #expect(arriveNotMember.isNotMember)
        #expect(!arriveNotMember.isPartyNotFound)
        #expect(departNotMember.isNotMember)
        #expect(arriveGone.isPartyNotFound)
        #expect(departGone.isPartyNotFound)

        // 본문 없는 404 는 사유가 아니다 — 상태 코드로 「방이 사라졌어요」를 지어내지 않는다.
        let arriveBodyless = try await arriveError(bodylessError(404))
        let departBodyless = try await departError(bodylessError(404))
        #expect(!arriveBodyless.isPartyNotFound)
        #expect(!departBodyless.isPartyNotFound)
    }

    /// 더미 저장소도 세 액션을 구현한다 — 디버그/프리뷰 빌드가 버튼을 눌러도 터지지 않아야 한다.
    @Test("더미 저장소의 세 액션은 성공한 척한다")
    func dummyMeetingActionsSucceed() async throws {
        let repository = DummyRideRepository()

        try await repository.confirmMeeting(partyId: 1, departureAt: "2026-11-03T08:30:00Z")
        try await repository.arriveAtDeparture(partyId: 1, latitude: 37.4979, longitude: 127.0276)
        try await repository.departParty(partyId: 1)
    }

    // MARK: - SSE 재연결 백오프
    //
    // 이 두 테스트가 **여기 있는 건 원본 배치를 따랐기 때문**이다(제자리는 `PartySseEventTest` 다).
    // 보는 대상은 `PartyEventSource` 의 순수 함수다.

    /// 재연결 간격이 **고정 3초였다.** 실패를 세지 않아 서버가 502/503 을 내거나 Redis 가 죽은 동안에도
    /// 간격이 그대로였고, 그때 이 루프는 재기동 중인 서버를 때리는 하드 루프가 된다 — 대기 화면에
    /// 12명이 있으면 분당 240회다. 그래서 횟수에 따라 늘리고 상한을 둔다.
    @Test("재연결 간격은 실패 횟수만큼 늘고 30초에서 멈춘다")
    func reconnectBackoffTable() {
        // 지터 0 = 표의 값 그대로. 지터는 아래 테스트가 따로 본다.
        #expect(PartyEventSource.reconnectDelayMs(failures: 1, jitter: 0.0) == 3_000)
        #expect(PartyEventSource.reconnectDelayMs(failures: 2, jitter: 0.0) == 6_000)
        #expect(PartyEventSource.reconnectDelayMs(failures: 3, jitter: 0.0) == 12_000)
        #expect(PartyEventSource.reconnectDelayMs(failures: 4, jitter: 0.0) == 30_000)
        // 상한 뒤로는 머문다 — 재시도를 멈추지는 않는다(폴백 폴링이 더 비싸다).
        #expect(PartyEventSource.reconnectDelayMs(failures: 50, jitter: 0.0) == 30_000)
        // 세는 쪽이 틀려도 0ms 하드 루프가 되지 않게 — 0·음수는 첫 간격이다.
        #expect(PartyEventSource.reconnectDelayMs(failures: 0, jitter: 0.0) == 3_000)
        #expect(PartyEventSource.reconnectDelayMs(failures: -3, jitter: 0.0) == 3_000)
    }

    /// 지터는 **더하기만** 한다 — 상한(30초)과 하한(3초)이 둘 다 지키려는 값이다. 12명이 같은 장애로
    /// 동시에 끊겼을 때 같은 초에 다시 몰리는 것을 푸는 게 목적이다.
    @Test("재연결 간격에 지터를 더한다 - 기준값 아래로는 내려가지 않는다")
    func reconnectJitterOnlyAdds() {
        #expect(PartyEventSource.reconnectDelayMs(failures: 1, jitter: 1.0) == 3_600) // 3s + 20%
        #expect(PartyEventSource.reconnectDelayMs(failures: 9, jitter: 1.0) == 36_000) // 30s + 20%
        for failures in 1...6 {
            for jitter in [0.0, 0.3, 0.5, 1.0] {
                let wait = PartyEventSource.reconnectDelayMs(failures: failures, jitter: jitter)
                #expect(wait >= 3_000, "간격이 첫 값보다 짧다 (failures=\(failures), jitter=\(jitter))")
                #expect(wait <= 36_000, "상한+지터를 넘었다 (failures=\(failures), jitter=\(jitter))")
            }
        }
    }

    // MARK: - 걸어서 가까운 방 추천

    /// **요청 좌표가 제자리로 가는지.** 서버 record 필드명이 `destLat`/`destLng` 인데 응답 쪽만
    /// `destinationLat`/`destinationLng` 이다. 기존 DTO 를 복사해 쓰면 도착 좌표가 빠지고, 전부
    /// primitive double 이라 서버에서 `0.0` 이 되며, (0,0) 은 서비스 지역 밖이라 **400
    /// OUT_OF_SERVICE_AREA** 가 떨어진다. 즉 이 테스트가 깨지면 사용자에게는 "서비스 지역이
    /// 아니에요" 로 보인다.
    @Test("추천 요청은 네 좌표를 제자리에 싣는다")
    func realtimeRequestCoordinates() async throws {
        let api = FakeMatchingApi()

        _ = try await RemoteRideRepository(api: api, session: session()).findRealtimeCandidates(
            departureLat: 37.4979, departureLng: 127.0276,
            destinationLat: 37.3948, destinationLng: 127.1112
        )

        let sent = try #require(api.realtimeRequest.value)
        #expect(isClose(37.4979, sent.departureLat, 1e-9))
        #expect(isClose(127.0276, sent.departureLng, 1e-9))
        #expect(isClose(37.3948, sent.destLat, 1e-9), "도착 위도가 빠졌다 — 서버에서 0.0 이 되어 400 이 된다")
        #expect(isClose(127.1112, sent.destLng, 1e-9), "도착 경도가 빠졌다 — 서버에서 0.0 이 되어 400 이 된다")
    }

    /// 후보가 없는 건 **정상**이다 — 빈 목록을 돌려주고 예외를 던지지 않는다.
    @Test("후보가 없으면 빈 목록이다")
    func realtimeEmpty() async throws {
        let repository = RemoteRideRepository(api: FakeMatchingApi(realtimeCandidates: []), session: session())

        let candidates = try await repository.findRealtimeCandidates(
            departureLat: 1.0, departureLng: 2.0, destinationLat: 3.0, destinationLng: 4.0
        )

        #expect(candidates.isEmpty)
    }

    /// 502 는 도보 경로 엔진 장애다 — 화면이 "지금은 추천을 못 가져왔어요" 로 갈리게 좁혀 던진다.
    @Test("경로 엔진 실패는 RealtimeMatchException 으로 좁힌다")
    func realtimeRouteFailure() async throws {
        let api = FakeMatchingApi(realtimeFailure: error502())
        let repository = RemoteRideRepository(api: api, session: session())

        let realtime = try await thrownError(RealtimeMatchException.self) {
            _ = try await repository.findRealtimeCandidates(
                departureLat: 1.0, departureLng: 2.0, destinationLat: 3.0, destinationLng: 4.0
            )
        }

        #expect(realtime.isRouteUnavailable)
        #expect(!realtime.isAlreadyInParty)
    }

    /// 409 면 이미 방에 들어가 있다 — 화면은 추천 섹션 자체를 숨겨야 하므로 사유가 갈려야 한다.
    @Test("이미 방이 있으면 그 사유로 갈린다")
    func realtimeAlreadyInParty() async throws {
        let api = FakeMatchingApi(realtimeFailure: error409AlreadyJoined())
        let repository = RemoteRideRepository(api: api, session: session())

        let realtime = try await thrownError(RealtimeMatchException.self) {
            _ = try await repository.findRealtimeCandidates(
                departureLat: 1.0, departureLng: 2.0, destinationLat: 3.0, destinationLng: 4.0
            )
        }

        #expect(realtime.isAlreadyInParty)
        #expect(!realtime.isRouteUnavailable)
    }

    // 생성 실패만 바꿔 끼우는 호출 — 네 좌표·라벨·정원은 어느 테스트에서도 같다.
    private func openError(_ failure: any Error) async throws -> PartyOpenException {
        try await thrownError(PartyOpenException.self) {
            _ = try await RemoteRideRepository(api: FakeMatchingApi(openFailure: failure), session: session())
                .createParty(request: newParty())
        }
    }

    private func leaveError(_ failure: any Error) async throws -> PartyLeaveException {
        try await thrownError(PartyLeaveException.self) {
            try await RemoteRideRepository(api: FakeMatchingApi(leaveFailure: failure), session: session())
                .leaveParty(partyId: 7)
        }
    }

    private func confirmError(_ failure: any Error) async throws -> PartyConfirmException {
        try await thrownError(PartyConfirmException.self) {
            try await RemoteRideRepository(api: FakeMatchingApi(confirmFailure: failure), session: session())
                .confirmMeeting(partyId: 7, departureAt: "2026-11-03T08:30:00Z")
        }
    }

    private func arriveError(_ failure: any Error) async throws -> PartyArriveException {
        try await thrownError(PartyArriveException.self) {
            try await RemoteRideRepository(api: FakeMatchingApi(arriveFailure: failure), session: session())
                .arriveAtDeparture(partyId: 7, latitude: 37.4979, longitude: 127.0276)
        }
    }

    private func departError(_ failure: any Error) async throws -> PartyDepartException {
        try await thrownError(PartyDepartException.self) {
            try await RemoteRideRepository(api: FakeMatchingApi(departFailure: failure), session: session())
                .departParty(partyId: 7)
        }
    }

    private func newParty() -> NewParty {
        NewParty(
            departureLat: 37.5665,
            departureLng: 126.9780,
            destinationLat: 37.4979,
            destinationLng: 127.0276,
            departure: "서울시청",
            destination: "강남역",
            capacity: 3
        )
    }

    /// 게이트웨이가 가로챈 응답 — 본문이 JSON 이 아니라 HTML 이다. `readApiError()` 가 null 을 돌려준다.
    private func htmlError(_ status: Int) -> HttpException {
        HttpException(
            Response<Void>.error(status, "<html><body><h1>503 Service Temporarily Unavailable</h1></body></html>")
        )
    }

    /// 서버 공통 에러 본문 그대로 — 저장소가 code 를 읽어 분기한다.
    private func conflict(_ code: String, _ message: String) -> HttpException {
        httpError(409, code, message)
    }

    private func httpError(_ status: Int, _ code: String, _ message: String) -> HttpException {
        HttpException(Response<Void>.error(status, #"{"code":"\#(code)","message":"\#(message)"}"#))
    }

    private func error502() -> HttpException {
        HttpException(Response<Void>.error(502, #"{"code":"ROUTE_SEARCH_FAILED","message":"경로 조회에 실패했습니다."}"#))
    }

    private func error409AlreadyJoined() -> HttpException {
        HttpException(Response<Void>.error(409, #"{"code":"ALREADY_JOINED_OTHER_PARTY","message":"이미 참여 중인 방이 있습니다."}"#))
    }

    /// 본문 없는 실패 — 게이트웨이·프록시가 가로챈 응답이 이렇게 온다(서버 코드가 없다).
    private func bodylessError(_ status: Int) -> HttpException {
        HttpException(Response<Void>.error(status, ""))
    }
}

/// 원본에 대응 테스트가 없는 iOS 쪽 경계. 원본은 `CancellationException` 타입으로 갈랐고 여기는
/// `catch` 절이 갈라야 해서, 한 줄만 빠져도 화면 이탈이 「실패」로 보인다. 신고·SSE 배선도 원본 테스트가
/// 지나가지 않는 경로라 함께 본다.
@Suite(.timeLimit(.minutes(1)))
struct RemoteRideRepositoryBoundaryTest {
    private func session(uuid: String? = UUID_ME) -> any UserSession { FakeSession(uuid: uuid) }

    private static let joined409 = HttpException(
        Response<Void>.error(409, #"{"code":"ALREADY_JOINED_OTHER_PARTY","message":"이미 참여 중인 방이 있습니다."}"#)
    )

    private static let cancellations: [any Error] = [CancellationError(), URLError(.cancelled)]

    @Test("액션의 취소는 전용 예외로 좁히지 않고 그대로 올린다", arguments: cancellations)
    func actionsPropagateCancellation(_ cancellation: any Error) async {
        func expectCancellation(_ body: () async throws -> Void) async {
            do {
                try await body()
                Issue.record("던지지 않았다")
            } catch {
                #expect(isCancellation(throwable: error), "취소가 \(type(of: error)) 로 바뀌었다")
            }
        }

        let api = FakeMatchingApi(
            joinFailure: cancellation,
            finishFailure: cancellation,
            realtimeFailure: cancellation,
            openFailure: cancellation,
            leaveFailure: cancellation,
            confirmFailure: cancellation,
            arriveFailure: cancellation,
            departFailure: cancellation
        )
        let repository = RemoteRideRepository(api: api, session: session())

        await expectCancellation {
            _ = try await repository.createParty(
                request: NewParty(
                    departureLat: 1, departureLng: 2, destinationLat: 3, destinationLng: 4,
                    departure: "가", destination: "나", capacity: 3
                )
            )
        }
        await expectCancellation { _ = try await repository.joinParty(partyId: 7) }
        await expectCancellation { try await repository.leaveParty(partyId: 7) }
        await expectCancellation { try await repository.finishParty(partyId: 7) }
        await expectCancellation { try await repository.confirmMeeting(partyId: 7, departureAt: "2026-11-03T08:30:00Z") }
        await expectCancellation { try await repository.arriveAtDeparture(partyId: 7, latitude: 37.4979, longitude: 127.0276) }
        await expectCancellation { try await repository.departParty(partyId: 7) }
        await expectCancellation {
            _ = try await repository.findRealtimeCandidates(
                departureLat: 1, departureLng: 2, destinationLat: 3, destinationLng: 4
            )
        }
    }

    /// 원본은 여기서 `runCatching` 이 취소까지 삼켜 합류 실패로 올렸다. 같은 파일의 다른 호출이 전부
    /// 되던지는 이유(「화면 이탈이 에러로 보이지 않게」)가 여기도 그대로라 되던진다.
    @Test("합류 복구 조회 중 취소는 합류 실패가 아니라 취소다")
    func recoveryPropagatesCancellation() async {
        let api = FakeMatchingApi(joinFailure: Self.joined409, detailFailure: CancellationError())

        await #expect(throws: CancellationError.self) {
            _ = try await RemoteRideRepository(api: api, session: session()).joinParty(partyId: 7)
        }
    }

    /// 없는 멤버십을 있다고 하면 더 나쁘다 — 상세까지 실패하면 복구 신호를 올리지 않는다.
    @Test("합류 복구 조회가 실패하면 복구를 포기한다")
    func recoveryGivesUpOnFailure() async throws {
        let api = FakeMatchingApi(joinFailure: Self.joined409, detailFailure: IOException("끊김"))

        let error = try await thrownError(PartyJoinException.self) {
            _ = try await RemoteRideRepository(api: api, session: session()).joinParty(partyId: 7)
        }

        #expect(error.joinedStatus == nil)
        #expect(error.httpStatus == 409)
    }

    @Test("순번 조회는 상세를 한 번만 읽고 순번을 함께 넘긴다")
    func detailWithVersionReadsOnce() async throws {
        let api = FakeMatchingApi(detailVersion: 42)

        let detail = try await RemoteRideRepository(api: api, session: session()).getPartyDetailWithVersion(partyId: 7)

        #expect(api.detailCallCount.value == 1)
        #expect(detail.version == 42)
        #expect(detail.ride.members.map(\.isMe) == [true, false])
    }

    @Test("근처 방 목록은 주입한 저장소에 위임하고 기본값은 더미다")
    func nearbyDelegatesToLocal() {
        let repository = RemoteRideRepository(api: FakeMatchingApi(), session: session())

        #expect(repository.getNearbyParties() == DummyRideRepository().getNearbyParties())
    }

    @Test("SSE 를 주입하지 않으면 흐름은 바로 끝난다")
    func noEventSourceFinishes() async throws {
        var events: [PartyEvent] = []
        for try await event in RemoteRideRepository(api: FakeMatchingApi(), session: session()).observePartyEvents(partyId: 7) {
            events.append(event)
        }

        #expect(events.isEmpty)
    }

    @Test("SSE 프레임은 세션 uuid 로 나를 표시한 도메인 이벤트가 된다")
    func eventsMarkMe() async throws {
        let snapshot = #"{"id":7,"status":"ACTIVE","members":[{"publicId":"\#(UUID_ME)","nickname":"성윤"}]}"#
        let stub = StubServer { _ in
            StubResponse(
                status: 200,
                body: "event: connected\ndata: \(snapshot)\n\nevent: closed\ndata: 7\n\n",
                headers: ["Content-Type": "text/event-stream"]
            )
        }
        let repository = RemoteRideRepository(
            api: FakeMatchingApi(),
            session: session(),
            partyEvents: PartyEventSource(baseUrl: stub.baseUrl, client: HttpClient(session: stub.session()))
        )

        var events: [PartyEvent] = []
        for try await event in repository.observePartyEvents(partyId: 7) {
            events.append(event)
        }

        #expect(events.count == 2)
        guard case .snapshot(let ride, _) = events.first else {
            Issue.record("스냅샷이 아니다: \(String(describing: events.first))")
            return
        }
        #expect(ride.members.map(\.isMe) == [true])
        #expect(events.last == .closed)
    }

    /// 호출부가 받는 이 예외로 「화면을 떠나라」와 「폴백 폴링」이 갈린다 — 저장소 포장이 삼키면 안 된다.
    @Test("SSE 403 은 흐름의 예외로 그대로 올라온다")
    func eventsPropagateMembershipLoss() async throws {
        let stub = StubServer(status: 403)
        let repository = RemoteRideRepository(
            api: FakeMatchingApi(),
            session: session(),
            partyEvents: PartyEventSource(baseUrl: stub.baseUrl, client: HttpClient(session: stub.session()))
        )

        let error = try await thrownError(PartyMembershipLostException.self) {
            for try await _ in repository.observePartyEvents(partyId: 7) {}
        }

        #expect(error.partyId == 7)
    }

    /// 원본 `collect` 는 취소되면 `CancellationException` 을 던져 `MatchWaitingRoute` 의 다음 줄
    /// (`streamEnded.value = true`)을 지나지 않는다. Swift `for try await` 는 **오류 없이 끝나** 그 줄에 닿으므로,
    /// 대기 화면 포팅은 루프 뒤에 `try Task.checkCancellation()` 을 둔다(`RideRepository.observePartyEvents` 주석).
    /// 안 두면 화면이 가려질 때마다 종결로 적혀 복귀해도 SSE 를 다시 붙이지 않는다.
    @Test("수집을 취소하면 오류 없이 끝나므로 취소 확인으로 종결과 가른다")
    func cancelledCollectionIsNotTerminal() async throws {
        let server = try LoopbackStreamServer { exchange in
            exchange.send("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\nevent: connected\ndata: {\"id\":7,\"status\":\"ACTIVE\"}\n\n")
        }
        let baseUrl = try await server.start()
        defer { server.stop() }
        let repository = RemoteRideRepository(
            api: FakeMatchingApi(),
            session: session(),
            partyEvents: PartyEventSource(baseUrl: baseUrl, client: HttpClient(session: URLSession(configuration: .ephemeral)))
        )
        let received = OSAllocatedUnfairLock(initialState: 0)
        let loopEnded = OSAllocatedUnfairLock(initialState: false)

        let collector = Task {
            for try await _ in repository.observePartyEvents(partyId: 7) {
                received.withLock { $0 += 1 }
            }
            loopEnded.withLock { $0 = true }
            try Task.checkCancellation()
        }
        #expect(await waitUntil { received.withLock { $0 } == 1 })

        collector.cancel()
        let result = await collector.result

        #expect(loopEnded.withLock { $0 }, "취소가 루프 밖으로 던져지게 바뀌었다면 이 주석과 포팅 지침을 함께 고친다")
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test("방이 없어 끝난 수집은 취소 확인을 지나 종결로 적힌다")
    func notFoundCollectionIsTerminal() async throws {
        let stub = StubServer(status: 404)
        let repository = RemoteRideRepository(
            api: FakeMatchingApi(),
            session: session(),
            partyEvents: PartyEventSource(baseUrl: stub.baseUrl, client: HttpClient(session: stub.session()))
        )

        for try await _ in repository.observePartyEvents(partyId: 7) {}
        try Task.checkCancellation()

        #expect(stub.requests.count == 1)
    }

    /// Swift `...` 범위는 하한이 상한보다 크면 트랩한다. 원본 `..` 은 빈 범위다.
    @Test("더미 저장소는 뒤집힌 범위를 앱을 죽이지 않고 빈 목록으로 답한다")
    func dummyInvertedBounds() async throws {
        let rides = try await DummyRideRepository().getPartiesWithin(swLat: 37.39, swLng: 126.94, neLat: 37.37, neLng: 126.91)

        #expect(rides.isEmpty)
    }

    @Test("더미 저장소의 경로 미리보기는 NaN 좌표에 앱을 죽이지 않고 던진다")
    func dummyNaNCoordinates() async {
        await #expect(throws: IllegalArgumentException.self) {
            _ = try await DummyRideRepository().previewRoute(
                departureLat: .nan, departureLng: 0, destinationLat: 0, destinationLng: 0
            )
        }
    }
}

private final class FakeMatchingApi: MatchingApi {
    private let joinFailure: (any Error)?
    private let finishFailure: (any Error)?
    private let realtimeCandidates: [MatchCandidateResponse]
    private let realtimeFailure: (any Error)?
    private let openFailure: (any Error)?
    private let leaveFailure: (any Error)?
    private let confirmFailure: (any Error)?
    private let arriveFailure: (any Error)?
    private let departFailure: (any Error)?
    private let detailFailure: (any Error)?
    private let detailVersion: Int64?

    let realtimeRequest = Locked<RealTimeMatchingRequestDto?>(nil)
    let joinCall = Locked<Int64?>(nil)
    let finishCall = Locked<Int64?>(nil)
    let leaveCall = Locked<Int64?>(nil)
    let confirmCall = Locked<Int64?>(nil)
    let confirmRequest = Locked<ConfirmMeetingRequestDto?>(nil)
    let arriveCall = Locked<Int64?>(nil)
    let arriveRequest = Locked<ArriveRequestDto?>(nil)
    let departCall = Locked<Int64?>(nil)
    let openRequest = Locked<OpenPartyRequestDto?>(nil)
    let detailCallCount = Locked(0)
    let withinCall = Locked<[Double]?>(nil)
    let routeRequest = Locked<RouteRequestDto?>(nil)

    init(
        joinFailure: (any Error)? = nil,
        finishFailure: (any Error)? = nil,
        realtimeCandidates: [MatchCandidateResponse] = [],
        realtimeFailure: (any Error)? = nil,
        openFailure: (any Error)? = nil,
        leaveFailure: (any Error)? = nil,
        confirmFailure: (any Error)? = nil,
        arriveFailure: (any Error)? = nil,
        departFailure: (any Error)? = nil,
        detailFailure: (any Error)? = nil,
        detailVersion: Int64? = nil
    ) {
        self.joinFailure = joinFailure
        self.finishFailure = finishFailure
        self.realtimeCandidates = realtimeCandidates
        self.realtimeFailure = realtimeFailure
        self.openFailure = openFailure
        self.leaveFailure = leaveFailure
        self.confirmFailure = confirmFailure
        self.arriveFailure = arriveFailure
        self.departFailure = departFailure
        self.detailFailure = detailFailure
        self.detailVersion = detailVersion
    }

    func getParties() async throws -> PartyListResponse { PartyListResponse() }

    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> PartyListResponse {
        withinCall.value = [swLat, swLng, neLat, neLng]
        return PartyListResponse(
            list: [
                PartyListResponse.PartyItem(
                    partyId: 1,
                    departure: "부산대 정문",
                    destination: "서면역",
                    currentMembers: 1,
                    capacity: 3,
                    status: "ACTIVE",
                    departureLat: 35.2313,
                    departureLng: 129.0838
                ),
            ]
        )
    }

    func getRealtimeCandidates(request: RealTimeMatchingRequestDto) async throws -> [MatchCandidateResponse] {
        realtimeRequest.value = request
        if let realtimeFailure { throw realtimeFailure }
        return realtimeCandidates
    }

    func getPartyDetail(partyId: Int64) async throws -> PartyDetailResponse {
        detailCallCount.update { $0 += 1 }
        if let detailFailure { throw detailFailure }
        return detail(partyId: partyId)
    }

    func openParty(request: OpenPartyRequestDto) async throws -> OpenPartyResponse {
        openRequest.value = request
        if let openFailure { throw openFailure }
        return OpenPartyResponse(
            id: 12,
            departure: request.departure,
            destination: request.destination,
            capacity: request.capacity,
            currentMembers: 1,
            status: "ACTIVE",
            estimateFare: 9600,
            estimateTime: 14,
            route: "_p~iF~ps|U"
        )
    }

    // 합류 응답은 상태·인원 두 값뿐이다(Backend #213 + `04f6be7` 로 지문 제거).
    // 상세와 **같은 방**을 가리키도록 같은 상태·인원을 쓴다.
    func joinParty(partyId: Int64) async throws -> PartyStatusResponse {
        joinCall.value = partyId
        if let joinFailure { throw joinFailure }
        return PartyStatusResponse(status: "COMPLETED", currentMembers: 2)
    }

    func finishParty(partyId: Int64) async throws {
        finishCall.value = partyId
        if let finishFailure { throw finishFailure }
    }

    func leaveParty(partyId: Int64) async throws {
        leaveCall.value = partyId
        if let leaveFailure { throw leaveFailure }
    }

    // 셋 다 204 라 돌려줄 값이 없다 — 확인할 것은 **무엇을 보냈는가** 뿐이다.
    func confirmMeeting(partyId: Int64, request: ConfirmMeetingRequestDto) async throws {
        confirmCall.value = partyId
        confirmRequest.value = request
        if let confirmFailure { throw confirmFailure }
    }

    func arriveAtDeparture(partyId: Int64, request: ArriveRequestDto) async throws {
        arriveCall.value = partyId
        arriveRequest.value = request
        if let arriveFailure { throw arriveFailure }
    }

    func departParty(partyId: Int64) async throws {
        departCall.value = partyId
        if let departFailure { throw departFailure }
    }

    // 실서버(localhost:8080) 응답을 축약한 값 — 폴리라인 필드명이 path 다.
    func previewRoute(request: RouteRequestDto) async throws -> RouteEstimateResponse {
        routeRequest.value = request
        return RouteEstimateResponse(
            estimateFare: 12_800,
            estimateTime: 35,
            path: "ub`vEwtzrW?BQxA"
        )
    }

    // 정원이 차서 서버가 COMPLETED 로 마감한 방 — 앱이 매칭 시작을 트리거하지 않는다.
    private func detail(partyId: Int64) -> PartyDetailResponse {
        PartyDetailResponse(
            id: partyId,
            departure: "서울시청",
            destination: "강남역",
            capacity: 3,
            currentMembers: 2,
            status: "COMPLETED",
            members: [
                PartyDetailResponse.MemberInfo(
                    publicId: UUID_ME,
                    nickname: "성윤",
                    rideCount: 4
                ),
                PartyDetailResponse.MemberInfo(
                    publicId: UUID_OTHER,
                    nickname: "다른사람"
                ),
            ],
            estimateFare: 9600,
            estimateTime: 14,
            route: "_p~iF~ps|U",
            version: detailVersion
        )
    }
}
