/// 택시비 정산 7개 엔드포인트 — 경로 기준: `faresplit/FareSplitController.java`
/// (`@RequestMapping("/api/v1")` + 메서드별 `"/matching/..."`·`"/users/me/fare-splits"`).
///
/// ### 왜 `MatchingApi` 에 넣지 않았나
/// 여섯 개가 `/matching/rooms/{partyId}/fare-split` 아래라 프리픽스만 보면 매칭 API 로 보인다. 그래도
/// 가른 이유는 **서버가 가른 것과 같다** — 정산은 `faresplit` 모듈이고 방(`matching`)과는 에러 코드
/// 집합이 다르다(`FareSplitErrorCode` 18종). 한 프로토콜에 섞으면 저장소도 섞이고, 그러면
/// 매칭 실패를 `FareSplitException` 으로 좁히거나 그 반대가 된다.
/// (노쇼를 `MatchingApi` 에 둔 것과 다른 판단인 이유: 그쪽은 컨트롤러만 다르고 **에러 모델이 같았다.**)
///
/// 일곱째(`/users/me/fare-splits`)만 프리픽스가 다르지만 같은 컨트롤러·같은 에러 모델이라 여기 둔다.
///
/// ### 전부 토큰 필수다
/// 예외가 없다(Security 가 `/api/v1/auth/` 하위를 뺀 전 경로를 보호한다). 게다가 서버가 **보는
/// 사람에 맞춰 응답을 만들므로**(`myRole`·`myAmount`·`maskedRealName`) 토큰이 없으면 401 이기 전에
/// 애초에 의미가 없는 호출이다.
///
/// ### 응답이 두 모양뿐이다
/// - 시작·조회·수정 → `FareSplitDetailResponse`
/// - 보냈어요·받았어요·못 받았어요 → **204, 본문 없음**(돌려받을 값이 없어 반환값이 없다 — `RestClient.callUnit`)
///
/// 경로·동사는 `FareSplitApiContractTest` 가 실제 요청으로 못 박는다 — 선언 문자열은
/// 컴파일러도 단위 테스트도 그냥은 못 잡고, 틀리면 실행 시점에 404 로만 드러난다.
///
/// 컨트롤러 소스(2026-11-12) 대조로 만들었고, 원본(Android)이 로컬 서버 실측으로 7경로를 확인했다
/// (`backend/http/faresplit.http` 는 **낡았다** — 생성·수정 본문에 `payments` 가 없고 지금 없는
/// `…/fare-split/cancel` 이 남아 있다. 그대로 쓰면 400·404 다).
public protocol FareSplitApi: Sendable {

    /// 정산 시작. **201** + 정산 상세. 방장만, 끝난(FINISHED) 방에서, 탑승자 2명 이상일 때.
    ///
    /// 실패가 많고 **상태 코드로 갈리지 않는다** — 400 넷(`INVALID_ACCOUNT_NUMBER`·
    /// `PAYMENT_TARGET_MISMATCH`·`PAYMENTS_NOT_EQUAL_FARE`·`INVALID_REQUEST`), 403 둘
    /// (`NOT_PARTY_HOST`·`NOT_A_RIDER`), 404 `PARTY_NOT_FOUND`, 409 셋(`PARTY_NOT_FINISHED`·
    /// `NOT_ENOUGH_RIDERS`·`FARE_SPLIT_ALREADY_EXISTS`). 전환은 `toFareSplitException` 이 한다.
    ///
    /// **409 `FARE_SPLIT_ALREADY_EXISTS` 는 복구 가능한 실패다** — 서버 Swagger 원문이 「GET 으로 본다」다.
    /// 저장소가 그 GET 을 이어서 해 준다(`RemoteFareSplitRepository.startFareSplit`).
    func createFareSplit(partyId: Int64, request: FareSplitRequestDto) async throws -> FareSplitDetailResponse

    /// 정산 상세. 받는 사람과 보내는 사람만 볼 수 있다(그 밖에는 403 `NOT_FARE_SPLIT_PARTICIPANT`).
    ///
    /// **404 `FARE_SPLIT_NOT_FOUND` 는 정상 상태다** — 「아직 아무도 시작하지 않았다」는 뜻이고,
    /// 저장소가 그것만 nil 로 접는다(`FareSplitRepository.getFareSplit`).
    /// `RestClient.response`(Retrofit `Response<T>` 자리)로 받지 않는 이유: 판정에 **본문의 code 까지**
    /// 필요하다(같은 404 에 `PARTY_NOT_FOUND`·`FARE_SPLIT_TRANSFER_NOT_FOUND` 도 있다). 그 판별은
    /// `toFareSplitException` 이 이미 하고 있으므로 예외를 거쳐 접는 쪽이 코드가 한 군데로 모인다.
    func getFareSplit(partyId: Int64) async throws -> FareSplitDetailResponse

    /// 정산 수정. 받는 사람만, **전원 NOT_SENT** 인 OPEN 정산만(아니면 409
    /// `FARE_SPLIT_ALREADY_STARTED`·`FARE_SPLIT_CLOSED`).
    ///
    /// **PATCH 지만 부분 수정이 아니다** — 본문은 시작과 같은 `FareSplitRequestDto` 이고 네 필드가
    /// 전부 필수다. 「바뀐 것만 보내기」로 만들면 400 `INVALID_REQUEST` 다.
    ///
    /// 동사를 POST 로 잘못 쓰면 서버에 `POST …/fare-split` 매핑이 **이미 있어서**(= 시작) 405 가 아니라
    /// **409 `FARE_SPLIT_ALREADY_EXISTS`** 가 온다 — 「수정이 안 된다」가 아니라 「이미 있다」로 보여
    /// 원인이 완전히 가려진다. 그래서 동사를 테스트로 못 박는다.
    func editFareSplit(partyId: Int64, request: FareSplitRequestDto) async throws -> FareSplitDetailResponse

    /// 「보냈어요」. **204, 본문 없음.** 보내는 사람 전용(받는 사람은 403 `NOT_FARE_SPLIT_SENDER`).
    ///
    /// **멱등이다** — 이미 SENT·CONFIRMED 면 아무것도 바꾸지 않고 같은 204 다(알림도 다시 가지 않는다).
    /// 「이미 그 상태였다」와 「지금 바뀌었다」를 **응답으로 구분할 수 없으므로** 앱은 성공으로만 다룬다.
    ///
    /// 본문이 없는 POST 다(`MatchingApi.departParty` 와 같은 모양) — 본문을 붙이지 말 것.
    func markSent(partyId: Int64) async throws

    /// 「받았어요」. **204, 본문 없음.** 받는 사람 전용(보내는 사람은 403 `NOT_FARE_SPLIT_PAYER`).
    /// `markSent` 와 같은 뜻의 멱등이고, NOT_SENT 인 송금도 바로 확인할 수 있다(현금).
    ///
    /// **마지막 확인이 정산을 닫는다** — 전원 CONFIRMED 가 되면 서버가 COMPLETED 로 닫고 계좌번호를
    /// 지운다. 그래서 204 를 받은 뒤 상세 재조회는 선택이 아니다.
    ///
    /// - Parameter senderPublicId: 보내는 사람의 publicId. 서버가 `@PathVariable UUID` 로 받으므로
    ///   **UUID 모양이 아니면 400** `INVALID_REQUEST` 이고, UUID 지만 이 정산의 보내는 사람이 아니면
    ///   404 `FARE_SPLIT_TRANSFER_NOT_FOUND` 다 — 둘이 다른 실패라 빈 문자열을 넘기지 말 것.
    func confirmReceived(partyId: Int64, senderPublicId: String) async throws

    /// 「못 받았어요」(SENT → NOT_SENT, sentAt 삭제). **204, 본문 없음.** 받는 사람 전용.
    ///
    /// **셋 중 유일하게 멱등이 아니다** — SENT 인 송금에서만 되고, 아니면 409 `TRANSFER_NOT_SENT` 다.
    /// 「두 번 눌러도 괜찮다」가 성립하지 않는 유일한 동작이다.
    ///
    /// 경로가 `confirmReceived` 와 **마지막 세그먼트만 다르다**(`received` ↔ `not-received`).
    /// 바꿔 쓰면 **돈을 받았다고 확인해 정산을 닫아 버린다** — 되돌릴 수 없고, 사용자가 누른 것은
    /// 그 반대다. 두 경로를 테스트로 함께 못 박는 이유가 이것이다.
    func markNotReceived(partyId: Int64, senderPublicId: String) async throws

    /// 내가 보낼 정산 목록(홈 배너). 없으면 `{"fareSplits":[]}` 다.
    ///
    /// `status` 는 `NOT_SENT`·`SENT`·`CONFIRMED` 중 하나이고, 그 밖의 값은 400 `INVALID_REQUEST` 다.
    /// 서버에 `defaultValue = "NOT_SENT"` 가 있지만 **앱은 늘 명시해 보낸다** — 기본값을 서버에 맡기면
    /// 서버가 기본값을 바꿀 때 홈 배너가 조용히 다른 목록을 그린다(그 변화는 에러로 드러나지 않는다).
    /// 그래서 옵셔널이 아니다 — nil 이면 `RestClient` 가 쿼리 키를 아예 빼 버린다.
    ///
    /// **받는 사람으로 시작한 정산은 여기 나오지 않는다.** 방장의 할 일 배너를 이 목록으로 만들면
    /// 영구히 비어 있다.
    func getMyFareSplits(status: String) async throws -> MyFareSplitListResponse
}

enum FareSplitApiRoute: String, CaseIterable, ApiRouteSet {
    case createFareSplit, getFareSplit, editFareSplit, markSent, confirmReceived, markNotReceived, getMyFareSplits

    var route: ApiRoute {
        switch self {
        case .createFareSplit: .POST("api/v1/matching/rooms/{partyId}/fare-split")
        case .getFareSplit: .GET("api/v1/matching/rooms/{partyId}/fare-split")
        case .editFareSplit: .PATCH("api/v1/matching/rooms/{partyId}/fare-split")
        case .markSent: .POST("api/v1/matching/rooms/{partyId}/fare-split/sent")
        case .confirmReceived: .POST("api/v1/matching/rooms/{partyId}/fare-split/transfers/{publicId}/received")
        case .markNotReceived: .POST("api/v1/matching/rooms/{partyId}/fare-split/transfers/{publicId}/not-received")
        case .getMyFareSplits: .GET("api/v1/users/me/fare-splits", query: ["status"])
        }
    }
}

struct RestFareSplitApi: FareSplitApi {
    let rest: RestClient

    func createFareSplit(partyId: Int64, request: FareSplitRequestDto) async throws -> FareSplitDetailResponse {
        try await rest.call(FareSplitApiRoute.createFareSplit.route, path: ["partyId": partyId], body: request)
    }

    func getFareSplit(partyId: Int64) async throws -> FareSplitDetailResponse {
        try await rest.call(FareSplitApiRoute.getFareSplit.route, path: ["partyId": partyId])
    }

    func editFareSplit(partyId: Int64, request: FareSplitRequestDto) async throws -> FareSplitDetailResponse {
        try await rest.call(FareSplitApiRoute.editFareSplit.route, path: ["partyId": partyId], body: request)
    }

    // 204 + 빈 본문이라 `call<T>` 를 쓰면 Retrofit 처럼 예외다 — 세 동작 모두 `callUnit` 이다.
    func markSent(partyId: Int64) async throws {
        try await rest.callUnit(FareSplitApiRoute.markSent.route, path: ["partyId": partyId])
    }

    func confirmReceived(partyId: Int64, senderPublicId: String) async throws {
        try await rest.callUnit(
            FareSplitApiRoute.confirmReceived.route,
            path: ["partyId": partyId, "publicId": senderPublicId]
        )
    }

    func markNotReceived(partyId: Int64, senderPublicId: String) async throws {
        try await rest.callUnit(
            FareSplitApiRoute.markNotReceived.route,
            path: ["partyId": partyId, "publicId": senderPublicId]
        )
    }

    func getMyFareSplits(status: String) async throws -> MyFareSplitListResponse {
        try await rest.call(FareSplitApiRoute.getMyFareSplits.route, query: ["status": status])
    }
}
