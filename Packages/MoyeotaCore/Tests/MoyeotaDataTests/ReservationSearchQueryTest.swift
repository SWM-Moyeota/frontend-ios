import Foundation
import MoyeotaDomain
import Testing
@testable import MoyeotaData

/// 로그인한 사용자를 흉내 내는 세션. 이 테스트는 「나」 판정을 보지 않는다 — 저장소 생성에 필요할 뿐이다.
private struct LoggedInSession: UserSession {
    let authState: StateFlow<AuthState> =
        MutableStateFlow<AuthState>(.authenticated(userUuid: "01a06145-3caf-7614-a3bd-cee6e25316b1"))
}

/// 예약 조회가 **실제로 어떤 URL 로 나가는지** 확인한다.
///
/// `AuthenticatedPathContractTest` 는 선언 값만 읽으므로 「도착지를 안 보낼 때 그 두 키가
/// 빠지는가」를 말해 주지 못한다. 그 답은 `RestClient` 의 동작(쿼리의 nil 을 생략한다 — Retrofit
/// `@Query` 와 같다)에 달려 있고, **하나만 실리면 서버가 400 `INCOMPLETE_DESTINATION`** 이다. 반대로
/// 둘 다 `destLat=` 처럼 빈 값으로 나가면 서버가 숫자 파싱에 실패해 400 `INVALID_REQUEST` 다 — 둘 다
/// 「검색이 안 된다」로 보이는데 원인이 URL 조립이라 추적이 어렵다.
///
/// `UserApiRideRecordQueryTest` 와 같은 수법이다: `StubServer` 가 요청을 가로채 응답을 직접 만들므로
/// 소켓이 열리지 않는다. 쿼리 이름이 선언(`ApiRoute.queryNames`)과 어긋나면 `RestClient` 가 요청을
/// 만들기 전에 거부하므로, 새 메서드의 선언·구현 조합이 유효한지도 함께 확인된다.
///
/// 저장소를 통해 부르는 것이 중요하다 — 「둘 다 또는 둘 다 아님」을 보장하는 자리가
/// `RemoteRideRepository.searchReservations` 의 파라미터 타입(`ReservationDestination`)이기 때문이다.
@Suite struct ReservationSearchQueryTest {
    private let emptyListBody = #"{"list":[]}"#

    private func makeApi() throws -> (RestMatchingApi, StubServer) {
        let stub = StubServer(status: 200, body: emptyListBody)
        return (RestMatchingApi(rest: try stub.rest()), stub)
    }

    private func makeRepository() throws -> (RemoteRideRepository, StubServer) {
        let (api, stub) = try makeApi()
        return (RemoteRideRepository(api: api, session: LoggedInSession()), stub)
    }

    /// 도착지를 안 넘기면 **두 키가 함께 빠진다.** 하나만 실리면 400 `INCOMPLETE_DESTINATION` 이므로
    /// 「빠짐」은 반드시 쌍이어야 한다 — 저장소가 한 값(nil)에서 두 쿼리를 만들기 때문에 쌍이 깨질
    /// 길이 없다는 것을 URL 로 확인한다.
    @Test("도착지가 없으면 destLat destLng 가 함께 빠진다")
    func destinationOmittedAsPair() async throws {
        let (repository, stub) = try makeRepository()

        _ = try await repository.searchReservations(
            departureLat: 37.4979,
            departureLng: 127.0276,
            date: "2026-11-13"
        )

        let request = try stub.requests.single()
        #expect(request.path == "/api/v1/matching/reservations/search")
        // 출발지 이름은 **줄어 있다** — departureLat 으로 나가면 서버 필수 파라미터가 누락된다.
        #expect(request.queryParameter("depLat") == "37.4979")
        #expect(request.queryParameter("depLng") == "127.0276")
        #expect(request.queryParameter("departureLat") == nil, "검색 쿼리에 departureLat 이 나갔다 — 서버 파라미터는 depLat 이다")
        // 날짜는 instant 가 아니라 한국 달력 날짜다.
        #expect(request.queryParameter("date") == "2026-11-13")
        #expect(request.queryParameter("destLat") == nil, "도착지를 안 보냈는데 destLat 이 나갔다")
        #expect(request.queryParameter("destLng") == nil, "도착지를 안 보냈는데 destLng 이 나갔다")
    }

    /// 도착지를 넘기면 **둘 다** 실린다. 이름은 `destinationLat` 이 아니라 `destLat` 이다.
    @Test("도착지를 넘기면 destLat destLng 가 함께 실린다")
    func destinationSentAsPair() async throws {
        let (repository, stub) = try makeRepository()

        _ = try await repository.searchReservations(
            departureLat: 37.4979,
            departureLng: 127.0276,
            date: "2026-11-13",
            destination: ReservationDestination(latitude: 37.3948, longitude: 127.1112)
        )

        let request = try stub.requests.single()
        #expect(request.queryParameter("destLat") == "37.3948")
        #expect(request.queryParameter("destLng") == "127.1112")
        #expect(request.queryParameter("destinationLat") == nil, "도착지가 destinationLat 으로 나갔다 — 그건 생성 본문 쪽 이름이다")
    }

    /// 기간 목록은 두 파라미터가 **늘 실린다**(non-null). 호출부가 하나를 빼는 길을 만들지 않는 이유는
    /// 그 400 의 본문이 `{code, message}` 가 아니어서(서버에 누락 파라미터 핸들러가 없다) 앱 에러
    /// 파서가 사유를 못 읽기 때문이다 — 화면에는 일반 문구만 뜬다.
    @Test("기간 목록은 from to 를 그대로 싣는다")
    func rangeSendsFromTo() async throws {
        let (repository, stub) = try makeRepository()

        _ = try await repository.getReservations(from: "2026-11-13T00:00:00Z", to: "2026-11-14T00:00:00Z")

        let request = try stub.requests.single()
        #expect(request.path == "/api/v1/matching/reservations")
        #expect(request.queryParameter("from") == "2026-11-13T00:00:00Z")
        #expect(request.queryParameter("to") == "2026-11-14T00:00:00Z")
    }

    /// 「곧 출발」은 **방 목록의 뷰포트 조회와 같은 이름·같은 순서**로 나간다. 섞이면 서버가
    /// 400 `INVALID_MAP_BOUNDS` 를 준다 — 그래서 값으로 못 박는다.
    @Test("곧 출발은 남서 북동 순서 그대로 네 쿼리를 싣는다")
    func soonSendsViewportInOrder() async throws {
        let (repository, stub) = try makeRepository()

        _ = try await repository.getReservationsSoon(swLat: 35.20, swLng: 129.05, neLat: 35.26, neLng: 129.12)

        let request = try stub.requests.single()
        #expect(request.path == "/api/v1/matching/reservations/soon")
        #expect(request.queryParameter("swLat") == "35.2")
        #expect(request.queryParameter("swLng") == "129.05")
        #expect(request.queryParameter("neLat") == "35.26")
        #expect(request.queryParameter("neLng") == "129.12")
    }

    /// 노쇼 기록 조회는 **쿼리가 하나도 없다** — 서버에 커서·개수 파라미터가 없다.
    @Test("노쇼 기록 조회는 쿼리 없이 나간다")
    func noShowsWithoutQuery() async throws {
        let (api, stub) = try makeApi()

        _ = try await api.getMyNoShows()

        let request = try stub.requests.single()
        #expect(request.path == "/api/v1/matching/no-shows")
        #expect(request.query == nil, "쿼리가 하나도 없어야 한다")
    }
}
