import Foundation

/// 즐겨찾기 등록·삭제 실패를 화면이 다룰 수 있는 형태로 좁힌 예외.
///
/// presentation 은 네트워크 계층을 의존하지 않으므로(`MoyeotaUI` 는 `MoyeotaCore` 중 `MoyeotaDomain` 만 본다)
/// HTTP 상태를 그대로 올리면 화면이 404 와 500 을 구분할 수 없다. `ChatException` 과 같은 경계다.
///
/// ### 상태 코드로는 안 갈린다 — 그래서 `code` 를 들고 다닌다
/// 등록의 409 에는 `isDuplicated` 와 `isLimitExceeded` 가 함께 들어 있고, 삭제의 404 에는
/// 「이미 지워졌다」·「없다」·「남의 것」이 함께 들어 있다. 앞의 둘은 사용자가 할 일이 반대라
/// (하나를 빼면 담긴다 / 할 일이 없다) 반드시 가려야 하고, 뒤의 셋은 서버가 일부러 숨긴 것이라
/// 가리지 않는다.
///
/// ### 왜 404 를 성공으로 접지 않는가
/// 삭제는 **멱등이 아니다** — 같은 id 두 번째도, 없는 id 도, **남의 id 도 전부 같은
/// 404 `FAVORITE_PLACE_NOT_FOUND`** 다(실측(2026-11-01, 로컬 `:8080`); 403 이 아니라 존재 은닉이다).
/// 「이미 지워졌으니 성공」으로 접으면 남의 행을 지우려는 시도까지 성공으로 보이고, 화면은 서버와
/// 어긋난 목록을 계속 들고 있는다. 그래서 실패로 올리고 **화면이 목록을 다시 받게** 한다.
///
/// 404 를 삼키는 자리는 전체 삭제 하나뿐이다 — 「이미 비어 있다」는 부른 쪽이 원한 상태가 이미
/// 참이라는 뜻이고, 그건 리포지토리가 처리하므로 이 예외까지 올라오지 않는다
/// (`RemotePlaceRepository.deleteAllFavoritePlaces`).
public struct FavoritePlaceException: Throwable {
    /// 서버 에러 코드(`FAVORITE_PLACE_NOT_FOUND`·`INVALID_PLACE_IDS` 등). 본문이 없거나 파싱 실패면 null.
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 null.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체를 받지 못했으면 null.
    public let httpStatus: Int?
    /// 응답을 받지 못한 실패(연결 거부·타임아웃·DNS). 사용자에게는 재시도를 안내한다.
    public let isNetwork: Bool
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        isNetwork: Bool = false,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.isNetwork = isNetwork
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "즐겨찾기 요청에 실패했습니다." }

    /// 404 `FAVORITE_PLACE_NOT_FOUND` — **이미 지워졌거나 내 것이 아니다.**
    /// 서버가 둘을 구분해 주지 않으므로 문구도 구분하지 않는다. 이 값이 참이면 화면이 보고 있는 목록이
    /// 서버와 어긋났다는 뜻이라 재조회가 필요하다.
    public var isNotFound: Bool {
        code == "FAVORITE_PLACE_NOT_FOUND" || (code == nil && httpStatus == 404)
    }

    /// 409 `FAVORITE_PLACE_LIMIT_EXCEEDED` — **`FavoritePlacePolicy.MAX_COUNT` 개가 이미 찼다.**
    /// `isDuplicated` 와 같은 409 라서 상태만으로는 못 가린다 — 코드를 봐야 한다.
    /// 할 일이 분명한 실패다(하나를 빼면 담긴다). 그래서 상한을 문구에 적어 준다.
    public var isLimitExceeded: Bool {
        code == "FAVORITE_PLACE_LIMIT_EXCEEDED"
    }

    /// 409 `FAVORITE_PLACE_DUPLICATED` — **같은 이름이 이미 담겨 있다.**
    /// 서버는 장소가 아니라 이름(`placeName`)만 대조한다(`FavoritePlaceService.save`).
    ///
    /// `isLimitExceeded` 와 **반대로 할 일이 없는 실패**다 — 대개 같은 장소라 원한 상태가 이미 참이다
    /// (같은 이름의 다른 지점이면 참이 아니다 — `savedFavoriteIdFor` 참고). 둘을 한 문구로
    /// 뭉개면(「중복이거나 10개를 넘었을 수 있어요」) 사용자가 둘 중 어느 쪽인지 몰라 목록을 열어
    /// 세어 보게 된다. 서버가 가려 주는 것을 화면도 가린다.
    public var isDuplicated: Bool {
        code == "FAVORITE_PLACE_DUPLICATED"
    }
}
