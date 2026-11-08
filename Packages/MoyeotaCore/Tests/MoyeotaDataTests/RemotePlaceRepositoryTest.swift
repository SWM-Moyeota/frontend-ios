import MoyeotaDomain
import Testing
@testable import MoyeotaData

/// 즐겨찾기 **등록·삭제의 실패 처리**를 못 박는다. 서버가 **한 상태 코드에 여러 뜻을 담으므로**
/// 「상태 코드만으로 다루지 않는다」가 이 저장소의 판단이고, 경로마다 갈린다:
///
/// - 삭제 단건·다건의 404 → **올린다.** 서버가 「없는 것」과 「남의 것」을 같은 404 로 숨기므로
///   성공으로 접으면 남의 행을 지우려는 시도까지 성공으로 보이고, 화면은 서버와 어긋난 목록을 든다.
/// - `/all` 의 404 → **삼킨다.** 「이미 비어 있다」는 부른 쪽이 원한 상태가 이미 참이라는 뜻이다.
/// - 등록의 409 → **코드를 실어 올린다.** 중복과 상한 초과가 같은 409 인데 사용자가 할 일이 반대다.
@Suite struct RemotePlaceRepositoryTest {

    /// 못 박는 것: **목록이 비어 보일 때도 전체 삭제가 끝까지 간다.** 매퍼가 placeId·좌표 없는 행을
    /// 버리므로 화면의 목록이 비어 있어도 서버에는 행이 남아 있을 수 있고, 전체 삭제가 그 행을 치우는
    /// 유일한 길이다. 404 를 그대로 올리면 사용자는 아무 일도 안 했는데 「지우지 못했어요」를 본다.
    @Test("전체 삭제는 이미 비어 있다는 404 를 실패로 올리지 않는다")
    func deleteAllSwallows404() async throws {
        let api = FakePlaceApi(allDeleteError: httpException(404, Self.FAVORITE_PLACE_NOT_FOUND_BODY))

        // 던지면 테스트가 실패한다 — 확인할 것은 「안 터진다」가 전부다.
        try await RemotePlaceRepository(api: api).deleteAllFavoritePlaces()

        #expect(api.allDeleteCalls.value == 1)
    }

    /// 404 만 삼킨다는 경계. 500 까지 삼키면 서버 장애가 「다 지웠어요」로 보인다.
    @Test("전체 삭제의 500 은 그대로 올린다")
    func deleteAllRaises500() async {
        let api = FakePlaceApi(allDeleteError: httpException(500, #"{"code":"INTERNAL","message":"서버 오류"}"#))

        let e = await #expect(throws: FavoritePlaceException.self) {
            try await RemotePlaceRepository(api: api).deleteAllFavoritePlaces()
        }

        #expect(e?.httpStatus == 500)
        #expect(e?.isNotFound == false, "500 이 「없음」으로 접혔다")
    }

    /// 못 박는 것: 빈 선택으로는 **서버를 부르지 않는다.** 서버는 400 `INVALID_PLACE_IDS` 를 주고
    /// (실측: `{"placeIds":[]}` → 400), 그 에러가 화면에 「지우지 못했어요」로 서는데 사용자가 고른
    /// 것은 애초에 없다.
    @Test("다건 삭제에 빈 목록을 주면 서버를 부르지 않는다")
    func emptyBatchDoesNotCallServer() async throws {
        let api = FakePlaceApi()

        try await RemotePlaceRepository(api: api).deleteFavoritePlaces(ids: [])

        #expect(api.batchDeleteCalls.value == [])
    }

    /// 키 이름이 틀리면 서버가 조용히 400 을 준다 — 저장소를 거쳐도 `placeIds` 로 실리는지 본다.
    @Test("다건 삭제는 고른 id 를 placeIds 로 그대로 넘긴다")
    func batchPassesIds() async throws {
        let api = FakePlaceApi()

        try await RemotePlaceRepository(api: api).deleteFavoritePlaces(ids: [19, 20])

        #expect(api.batchDeleteCalls.value == [[19, 20]])
    }

    /// 못 박는 것: **전부-아니면-전무의 404 를 성공으로 접지 않는다.** 실측에서 `[19, 999999]` 는
    /// 404 였고 19 도 지워지지 않았다 — 성공으로 접으면 화면이 「지웠다」고 믿고 목록에서 빼
    /// 서버와 영구히 어긋난다.
    @Test("다건 삭제의 404 는 도메인 예외로 올라온다")
    func batch404Raises() async {
        let api = FakePlaceApi(batchDeleteError: httpException(404, Self.FAVORITE_PLACE_NOT_FOUND_BODY))

        let e = await #expect(throws: FavoritePlaceException.self) {
            try await RemotePlaceRepository(api: api).deleteFavoritePlaces(ids: [19, 999_999])
        }

        #expect(e?.isNotFound == true, "404 FAVORITE_PLACE_NOT_FOUND 가 「없음」으로 읽히지 않았다")
        #expect(e?.code == "FAVORITE_PLACE_NOT_FOUND")
    }

    /// 못 박는 것: 단건 삭제의 404 도 올린다. 같은 id 두 번째도, 없는 id 도, **남의 id 도** 같은
    /// 404 라서(실측) 성공으로 접으면 남의 행 삭제 시도까지 성공으로 보인다.
    @Test("한 건 삭제의 404 는 성공으로 접히지 않는다")
    func single404Raises() async {
        let api = FakePlaceApi(singleDeleteError: httpException(404, Self.FAVORITE_PLACE_NOT_FOUND_BODY))

        let e = await #expect(throws: FavoritePlaceException.self) {
            try await RemotePlaceRepository(api: api).deleteFavoritePlace(id: 19)
        }

        #expect(e?.isNotFound == true)
    }

    /// `{code,message}` 가 아닌 에러 본문에서도 터지지 않아야 한다 — `POST .../favorite-places/all` 의
    /// 405 가 Spring 기본 `{timestamp,status,error,path}` 다(실측). 코드 파싱이 null 로 떨어지고
    /// 상태 코드만 근거로 남는다.
    @Test("code 가 없는 에러 본문도 상태 코드만으로 다룬다")
    func bodyWithoutCode() async {
        let body = #"{"timestamp":"2026-11-01T00:00:00Z","status":405,"error":"Method Not Allowed","path":"/x"}"#
        let api = FakePlaceApi(singleDeleteError: httpException(405, body))

        let e = await #expect(throws: FavoritePlaceException.self) {
            try await RemotePlaceRepository(api: api).deleteFavoritePlace(id: 19)
        }

        #expect(e?.httpStatus == 405)
        #expect(e?.code == nil)
    }

    /// ★ 못 박는 것: **등록 실패도 `FavoritePlaceException` 으로 좁혀진다.**
    ///
    /// 한동안 등록만 이 경계를 안 거쳐 raw `HttpException` 이 화면까지 올라갔다. presentation 은
    /// 네트워크 계층을 의존하지 않으므로(`MoyeotaUI` 는 `MoyeotaDomain` 만 본다) 화면이 할 수
    /// 있는 일은 `catch` 하나뿐이었고, 실제로 두 409 를 「중복이거나 10개를 넘었을 수 있어요」
    /// 한 문구로 뭉갰다. 이 테스트가 그 되돌이를 막는다 — 코드가 실려 와야 화면이 가를 수 있다.
    @Test("등록 실패도 코드를 실은 FavoritePlaceException 으로 올린다")
    func addRaisesWithCode() async throws {
        let api = FakePlaceApi(addError: httpException(409, Self.FAVORITE_PLACE_LIMIT_EXCEEDED_BODY))

        let e = await #expect(throws: FavoritePlaceException.self) {
            try await RemotePlaceRepository(api: api).addFavoritePlace(place: place())
        }

        #expect(e?.httpStatus == 409)
        #expect(e?.isLimitExceeded == true, "상한 초과를 가리지 못했다 — 화면이 「하나를 빼 주세요」를 말할 수 없다")
        #expect(e?.isDuplicated == false, "상한 초과가 중복으로도 참이면 두 문구가 겹친다")
        // 화면 문구가 이 상수로 「N개까지」를 만든다 — 서버 원문과 어긋나면 다른 수를 말하게 된다
        let serverMessage = try #require(e?.serverMessage)
        #expect(
            serverMessage.contains("\(FavoritePlacePolicy.MAX_COUNT)개"),
            "서버 원문의 상한과 FavoritePlacePolicy.MAX_COUNT 가 어긋났다: \(serverMessage)"
        )
    }

    /// 같은 409 의 다른 뜻. **상태 코드로는 안 갈리므로** 코드로만 갈린다 —
    /// 상한은 하나를 빼면 담기고, 중복은 할 일이 없다.
    @Test("등록의 409 두 가지를 코드로 가른다")
    func add409SplitByCode() async {
        let api = FakePlaceApi(addError: httpException(409, Self.FAVORITE_PLACE_DUPLICATED_BODY))

        let e = await #expect(throws: FavoritePlaceException.self) {
            try await RemotePlaceRepository(api: api).addFavoritePlace(place: place())
        }

        #expect(e?.isDuplicated == true)
        #expect(e?.isLimitExceeded == false, "중복이 상한 초과로도 참이면 「10개를 넘었어요」라고 거짓말한다")
    }

    /// 400 `INVALID_COORDINATES` 같은 다른 실패를 409 로 추측하지 않는다.
    @Test("등록의 400 은 409 사유로 추측하지 않는다")
    func add400IsNot409Reason() async {
        let body = #"{"code":"INVALID_COORDINATES","message":"좌표가 올바르지 않습니다."}"#
        let api = FakePlaceApi(addError: httpException(400, body))

        let e = await #expect(throws: FavoritePlaceException.self) {
            try await RemotePlaceRepository(api: api).addFavoritePlace(place: place())
        }

        #expect(e?.httpStatus == 400)
        #expect(e?.isDuplicated == false && e?.isLimitExceeded == false && e?.isNotFound == false)
    }

    private func place() -> Place {
        Place(
            name: "판교역",
            roadName: "경기 성남시 분당구 판교역로 160",
            latitude: 37.3947,
            longitude: 127.1112
        )
    }

    private func httpException(_ code: Int, _ body: String) -> HttpException {
        HttpException(Response<Void>.error(code, body))
    }

    /// 실측 본문 그대로(2026-11-01, 로컬 `:8080`) — 없는 것·남의 것·두 번째 삭제가 모두 이것이다.
    private static let FAVORITE_PLACE_NOT_FOUND_BODY =
        #"{"code":"FAVORITE_PLACE_NOT_FOUND","message":"등록되지 않은 즐겨찾기입니다."}"#

    /// 서버 `PlaceErrorCode` 원문 그대로. 상한값이 `FavoritePlacePolicy.MAX_COUNT` 와 같아야 한다.
    private static let FAVORITE_PLACE_LIMIT_EXCEEDED_BODY =
        #"{"code":"FAVORITE_PLACE_LIMIT_EXCEEDED","message":"자주가는 장소는 최대 10개까지만 등록할 수 있습니다."}"#

    private static let FAVORITE_PLACE_DUPLICATED_BODY =
        #"{"code":"FAVORITE_PLACE_DUPLICATED","message":"이미 등록된 장소입니다."}"#
}

private final class FakePlaceApi: PlaceApi {
    private let singleDeleteError: (any Error)?
    private let batchDeleteError: (any Error)?
    private let allDeleteError: (any Error)?
    private let addError: (any Error)?

    let singleDeleteCalls = Locked<[Int64]>([])
    let batchDeleteCalls = Locked<[[Int64]]>([])
    let allDeleteCalls = Locked(0)

    init(
        singleDeleteError: (any Error)? = nil,
        batchDeleteError: (any Error)? = nil,
        allDeleteError: (any Error)? = nil,
        addError: (any Error)? = nil
    ) {
        self.singleDeleteError = singleDeleteError
        self.batchDeleteError = batchDeleteError
        self.allDeleteError = allDeleteError
        self.addError = addError
    }

    func searchPlaces(query: String) async throws -> PlaceSearchListResponse { PlaceSearchListResponse() }

    func reverseGeocode(latitude: Double, longitude: Double) async throws -> Response<AddressResponseDto> {
        .success(AddressResponseDto())
    }

    func addFavoritePlace(request: FavoritePlaceRequestDto) async throws {
        if let addError { throw addError }
    }

    func getFavoritePlaces() async throws -> FavoritePlaceListResponse { FavoritePlaceListResponse() }

    func deleteFavoritePlace(placeId: Int64) async throws {
        singleDeleteCalls.append(placeId)
        if let singleDeleteError { throw singleDeleteError }
    }

    func deleteFavoritePlaces(request: FavoritePlaceDeleteRequestDto) async throws {
        batchDeleteCalls.append(request.placeIds)
        if let batchDeleteError { throw batchDeleteError }
    }

    func deleteAllFavoritePlaces() async throws {
        allDeleteCalls.update { $0 += 1 }
        if let allDeleteError { throw allDeleteError }
    }
}
