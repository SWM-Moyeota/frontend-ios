import Foundation
import MoyeotaDomain
import Testing
@testable import MoyeotaData

/// 정산 7경로가 **실제로 어떤 요청으로 나가는지**를 진짜 `RestClient` 로 확인한다.
/// 하네스는 `PlaceApiDeleteTest` 와 같다 — `StubServer` 가 `URLProtocol` 로 가로채므로 소켓이 열리지 않는다.
///
/// ### 왜 이 계층을 테스트하나
/// 경로·동사 선언은 문자열이라 **컴파일러도 매퍼 테스트도 못 잡는다.** 틀리면 실행 시점의 4xx 로만
/// 드러나고, 이 모듈에서는 그 4xx 가 특히 **원인을 가린다**:
///
/// | 틀리는 모양 | 오는 응답 | 왜 원인이 가려지나 |
/// |---|---|---|
/// | 수정을 PATCH 대신 POST | **409 `FARE_SPLIT_ALREADY_EXISTS`** | `POST …/fare-split` 매핑이 **이미 있다**(= 정산 시작). 405 가 아니라 「이미 있다」로 보인다 |
/// | `not-received` 를 `received` 로 | **204 성공** | 되돌리려던 송금이 **확인으로 닫힌다.** 마지막 한 건이면 정산이 COMPLETED 가 되고 계좌번호가 지워진다 — 되돌릴 수 없다 |
/// | `status` 쿼리 누락 | 200 + **다른 목록** | 서버 `defaultValue = "NOT_SENT"` 가 메워 줘서 지금은 우연히 맞는다. 서버가 기본값을 바꾸면 홈 배너가 조용히 다른 목록을 그린다 |
///
/// 경로는 컨트롤러 소스(`faresplit/FareSplitController.java`, 2026-11-12) 대조다.
@Suite struct FareSplitApiContractTest {
    private let partyId: Int64 = 42
    private let senderPublicId = "22222222-2222-2222-2222-222222222222"

    private func api(_ stub: StubServer) throws -> RestFareSplitApi {
        RestFareSplitApi(rest: try stub.rest())
    }

    private let draftDto = FareSplitRequestDto(
        totalFare: 18_700,
        bankCode: "KAKAO",
        accountNumber: "3333012345678",
        payments: [FareSplitRequestDto.PaymentDto(userPublicId: "11111111-1111-1111-1111-111111111111", amount: 18_700)]
    )

    /// 본문의 키 순서가 원본과 다르다 — `MoyeotaJSON.encoder` 가 키를 정렬한다(JSON 객체는 순서가 없어
    /// 서버 계약은 같다). 못 박는 것은 **키 이름 넷과 값**이다.
    @Test("정산 시작은 rooms partyId fare-split 의 POST 이고 본문을 싣는다")
    func createIsPostWithBody() async throws {
        let stub = StubServer(status: 201, body: "{}")

        _ = try await api(stub).createFareSplit(partyId: partyId, request: draftDto)

        let request = try stub.requests.single()
        #expect(request.method == "POST")
        #expect(request.urlString == stub.url("api/v1/matching/rooms/42/fare-split"))
        #expect(
            request.bodyString
                == #"{"accountNumber":"3333012345678","bankCode":"KAKAO","#
                + #""payments":[{"amount":18700,"userPublicId":"11111111-1111-1111-1111-111111111111"}],"totalFare":18700}"#
        )
    }

    @Test("정산 조회는 같은 경로의 GET 이고 본문이 없다")
    func getIsGetWithoutBody() async throws {
        let stub = StubServer(body: "{}")

        _ = try await api(stub).getFareSplit(partyId: partyId)

        let request = try stub.requests.single()
        #expect(request.method == "GET")
        #expect(request.urlString == stub.url("api/v1/matching/rooms/42/fare-split"))
        #expect(request.body == nil, "조회에 본문이 실렸다")
        #expect(request.query == nil)
    }

    /// **동사가 PATCH 여야 한다.** POST 로 나가면 405 가 아니라 **409 `FARE_SPLIT_ALREADY_EXISTS`** 를
    /// 받는다 — 같은 경로에 POST 매핑(= 정산 시작)이 이미 있기 때문이다. 「수정이 안 된다」가 아니라
    /// 「이미 있다」로 보여 디버깅이 엉뚱한 곳으로 간다.
    @Test("정산 수정은 PATCH 이고 시작과 같은 본문을 전부 싣는다")
    func editIsPatchWithFullBody() async throws {
        let stub = StubServer(body: "{}")

        _ = try await api(stub).editFareSplit(partyId: partyId, request: draftDto)

        let request = try stub.requests.single()
        #expect(request.method == "PATCH")
        #expect(request.urlString == stub.url("api/v1/matching/rooms/42/fare-split"))
        let body = try #require(request.bodyString)
        #expect(
            body.contains(#""totalFare""#) && body.contains(#""bankCode""#)
                && body.contains(#""accountNumber""#) && body.contains(#""payments""#),
            "수정 본문에 네 필드가 전부 실려야 한다 — 부분 수정 PATCH 가 아니다"
        )
    }

    /// 「보냈어요」는 **본문 없는 POST** 다(`MatchingApi.departParty` 와 같은 모양).
    ///
    /// 스텁은 빈 본문을 「본문 없음」으로 보므로(`StubURLProtocol.readBody`) Content-Length 0 은 요청을
    /// 만드는 자리에서 본다 — 소켓에서의 확인은 `LoopbackWireTest` 의 「본문 없는 POST」가 한다.
    @Test("보냈어요는 fare-split sent 의 POST 이고 본문이 없다")
    func markSentIsBodylessPost() async throws {
        let stub = StubServer(status: 204)

        try await api(stub).markSent(partyId: partyId)

        let request = try stub.requests.single()
        #expect(request.method == "POST")
        #expect(request.urlString == stub.url("api/v1/matching/rooms/42/fare-split/sent"))
        #expect(request.body == nil)
        let built = try stub.rest().newRequest(FareSplitApiRoute.markSent.route, path: ["partyId": partyId])
        #expect(built.httpBody == Data(), "본문 없는 POST 는 Content-Length 0 으로 나간다")
    }

    /// **두 경로를 함께 못 박는다.** 마지막 세그먼트 하나(`received` ↔ `not-received`)만 다르고,
    /// 바꿔 쓰면 **되돌리려던 송금이 확인으로 닫힌다** — 204 성공으로 보이고, 마지막 한 건이면
    /// 정산이 COMPLETED 가 되어 계좌번호까지 지워진다. 사용자가 누른 것은 그 반대다.
    @Test("받았어요와 못 받았어요는 마지막 세그먼트만 다른 두 경로다")
    func receivedAndNotReceivedPaths() async throws {
        let received = StubServer(status: 204)
        let notReceived = StubServer(status: 204)

        try await api(received).confirmReceived(partyId: partyId, senderPublicId: senderPublicId)
        try await api(notReceived).markNotReceived(partyId: partyId, senderPublicId: senderPublicId)

        let receivedRequest = try received.requests.single()
        let notReceivedRequest = try notReceived.requests.single()
        #expect(receivedRequest.method == "POST")
        #expect(
            receivedRequest.urlString
                == received.url("api/v1/matching/rooms/42/fare-split/transfers/\(senderPublicId)/received")
        )
        #expect(notReceivedRequest.method == "POST")
        #expect(
            notReceivedRequest.urlString
                == notReceived.url("api/v1/matching/rooms/42/fare-split/transfers/\(senderPublicId)/not-received")
        )
        // publicId 는 **경로**에 싣는다 — 쿼리로 돌리면 서버 {publicId} 매핑에 닿지 못한다
        #expect(receivedRequest.query == nil)
        #expect(notReceivedRequest.query == nil)
    }

    /// (iOS 전용) publicId 는 **이 앱에서 처음으로 경로에 실리는 문자열**이다 — 그 전에는 경로 변수가
    /// 전부 `Int64` 였다. Retrofit `@Path` 처럼 `/` 는 인코딩돼야 하고(아니면 값 하나가 세그먼트 여럿이
    /// 되어 **다른 엔드포인트**로 간다), `.`·`..` 는 아예 거절돼야 한다(경로를 거슬러 올라간다).
    @Test("경로에 싣는 publicId 는 세그먼트를 쪼개지 못하게 인코딩된다")
    func stringPathSegmentIsEncoded() async throws {
        let stub = StubServer(status: 204)

        try await api(stub).confirmReceived(partyId: partyId, senderPublicId: "a/b c")

        #expect(
            try stub.requests.single().urlString
                == stub.url("api/v1/matching/rooms/42/fare-split/transfers/a%2Fb%20c/received")
        )
        await #expect(throws: IllegalArgumentException.self) {
            try await api(stub).confirmReceived(partyId: partyId, senderPublicId: "..")
        }
        #expect(stub.requests.count == 1, "경로를 거스르는 요청이 나갔다")
    }

    /// 홈 배너 목록은 `users/me` 아래다(방 경로가 아니다) — 서버가 같은 컨트롤러에 두었지만
    /// 프리픽스가 다르다. `status` 는 **늘 명시해 보낸다**(위 표의 셋째 줄).
    @Test("내 정산 목록은 users me fare-splits 의 GET 이고 status 를 쿼리로 싣는다")
    func myListIsGetWithStatusQuery() async throws {
        let stub = StubServer(body: "{}")

        _ = try await api(stub).getMyFareSplits(status: "NOT_SENT")

        let request = try stub.requests.single()
        #expect(request.method == "GET")
        #expect(request.urlString == stub.url("api/v1/users/me/fare-splits?status=NOT_SENT"))
        #expect(request.queryParameter("status") == "NOT_SENT")
    }

    /// 세 동작 모두 **204 + 빈 본문**으로 끝난다 — 돌려받을 값이 없으니 「안 터진다」가 확인할 전부다.
    @Test("204 는 본문 없이 성공으로 끝난다")
    func noContentSucceeds() async throws {
        let api = try api(StubServer(status: 204, body: ""))

        try await api.markSent(partyId: partyId)
        try await api.confirmReceived(partyId: partyId, senderPublicId: senderPublicId)
        try await api.markNotReceived(partyId: partyId, senderPublicId: senderPublicId)
    }

    /// 일곱 경로 전부가 `api/v1` 프리픽스를 쓴다 — 하나라도 빠지면 Security 가 보호 경로로 잡지 않아
    /// **401 이 아니라 404** 가 오고, 그 404 는 「정산이 없다」로 읽혀 화면이 「정산 시작하기」를 띄운다.
    @Test("일곱 경로 전부가 api v1 프리픽스를 쓴다")
    func allSevenUseApiV1Prefix() {
        let paths = FareSplitApiRoute.allCases.map(\.route.path)

        #expect(paths.count == 7, "경로가 일곱이 아니다 — 엔드포인트가 늘거나 줄었다")
        #expect(paths.allSatisfy { $0.hasPrefix("api/v1/") }, "api/v1 프리픽스가 빠진 경로가 있다: \(paths)")
    }
}
