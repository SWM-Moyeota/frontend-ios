import Foundation
import MoyeotaDomain
import Testing
@testable import MoyeotaData

/// 정산 저장소의 **실패 처리**를 못 박는다. 서버가 상태 코드 하나에 뜻을 여러 개 담으므로
/// (403 에 5종, 404 에 3종, 409 에 6종) 「상태 코드만으로 다루지 않는다」가 이 저장소의 판단이고,
/// 경로마다 갈린다:
///
/// - 조회의 404 `FARE_SPLIT_NOT_FOUND` → **nil 로 접는다.** 「아직 아무도 시작하지 않았다」는 끝난
///   방의 정상 상태다.
/// - 조회의 404 `PARTY_NOT_FOUND`·403 → **올린다.** 「정산이 없다」와 뜻이 달라서, 접으면 사라진 방이나
///   당사자 아닌 사람에게 「정산 시작하기」가 뜨고 눌렀을 때 또 막힌다.
/// - 시작의 409 `FARE_SPLIT_ALREADY_EXISTS` → **실패로 올리되 기존 정산을 담아** 올린다. 서버가
///   「GET 으로 본다」라고 복구 경로를 명시한 실패다.
/// - 멱등 204 둘 → **성공으로만.** 「이미 그 상태였다」와 「지금 바뀌었다」를 알 길이 없다.
@Suite struct RemoteFareSplitRepositoryTest {
    private let partyId: Int64 = 42
    private let senderPublicId = "22222222-2222-2222-2222-222222222222"

    private let draft = FareSplitDraft(
        totalFare: 18_700,
        bankCode: "KAKAO",
        accountNumber: "3333-01-2345678",
        shares: [FareShare(riderPublicId: "11111111-1111-1111-1111-111111111111", amount: 18_700)]
    )

    // ─── 조회 ───

    /// 못 박는 것: **정산이 없는 방이 에러로 보이지 않는다.** 예외로 올리면 모든 호출자가 「정상인
    /// 404」와 「진짜 실패」를 가리려고 do/catch 를 쓰게 되고, 한 곳만 빠뜨리면 멀쩡한 방에 빨간
    /// 에러가 뜬다(방장이 정산을 시작할 자리가 그 화면이다).
    @Test("정산이 없다는 404 는 null 로 돌려준다")
    func fareSplitNotFoundIsNil() async throws {
        let api = FakeFareSplitApi(detailError: httpError(404, "FARE_SPLIT_NOT_FOUND", "이 방의 택시비 정산이 없습니다."))

        #expect(try await RemoteFareSplitRepository(api: api).getFareSplit(partyId: partyId) == nil)
    }

    /// **같은 404 를 상태 코드로만 접으면 안 된다.** `PARTY_NOT_FOUND` 를 「정산이 없다」로 읽으면
    /// 사라진 방에 「정산 시작하기」가 뜨고, 눌렀을 때 또 404 를 받는다 — 사용자는 앱이 고장났다고 읽는다.
    @Test("방이 없다는 404 는 정산이 없는 것으로 접지 않는다")
    func partyNotFoundIsNotFolded() async throws {
        let api = FakeFareSplitApi(detailError: httpError(404, "PARTY_NOT_FOUND", "존재하지 않는 방입니다."))

        let e = try await thrownError(FareSplitException.self) {
            _ = try await RemoteFareSplitRepository(api: api).getFareSplit(partyId: partyId)
        }

        #expect(e.isPartyNotFound)
        #expect(!e.isFareSplitNotFound, "PARTY_NOT_FOUND 가 「정산 없음」으로 접혔다")
    }

    /// 403 `NOT_FARE_SPLIT_PARTICIPANT` 를 nil 로 접으면 **도착을 누르지 않은 사람에게
    /// 「정산 시작하기」가 뜬다**(눌러도 403 `NOT_A_RIDER` 다). 두 실패는 화면이 할 말이 다르다.
    @Test("당사자가 아니라는 403 은 그대로 올린다")
    func notParticipantIsThrown() async throws {
        let api = FakeFareSplitApi(
            detailError: httpError(403, "NOT_FARE_SPLIT_PARTICIPANT", "이 택시비 정산에 참여하지 않았습니다.")
        )

        let e = try await thrownError(FareSplitException.self) {
            _ = try await RemoteFareSplitRepository(api: api).getFareSplit(partyId: partyId)
        }

        #expect(e.isNotParticipant)
        #expect(e.httpStatus == 403)
    }

    @Test("조회 성공은 요청한 방 번호로 상세를 돌려준다")
    func getUsesRequestedPartyId() async throws {
        let api = FakeFareSplitApi(detail: detailResponse(partyId: nil))

        let fetched = try await RemoteFareSplitRepository(api: api).getFareSplit(partyId: partyId)
        let detail = try #require(fetched)

        #expect(detail.partyId == partyId)
        #expect(detail.status == .open)
    }

    // ─── 시작 ───

    /// 못 박는 것: **409 가 막다른 길이 되지 않는다.** 서버 Swagger 원문이 「이미 정산을 시작한
    /// 방(GET 으로 본다)」이다 — 그 GET 을 화면마다 시키면 한 곳만 빠뜨려도 사용자는 이미 존재하는
    /// 자기 정산을 볼 수 없다(시작도 조회도 막힌 화면이 된다).
    ///
    /// 성공으로 **바꿔서** 돌려주지는 않는다 — 방금 입력한 금액·계좌는 저장되지 않았고, 성공으로
    /// 보여 주면 화면은 반영된 줄 안다.
    @Test("이미 정산이 있으면 그 정산을 예외에 담아 올린다")
    func alreadyExistsCarriesExisting() async throws {
        let api = FakeFareSplitApi(
            detail: detailResponse(totalFare: 20_000),
            createError: httpError(409, "FARE_SPLIT_ALREADY_EXISTS", "이미 택시비 정산을 시작한 방입니다.")
        )

        let e = try await thrownError(FareSplitException.self) {
            _ = try await RemoteFareSplitRepository(api: api).startFareSplit(partyId: partyId, draft: draft)
        }

        #expect(e.isAlreadyExists)
        #expect(e.httpStatus == 409, "원래 실패의 코드·상태가 보존되지 않았다")
        let existing = try #require(e.existing, "이어 읽은 기존 정산이 담기지 않았다")
        #expect(existing.totalFare == 20_000)
        #expect(api.detailCalls.value == 1, "이어 읽는 조회는 한 번뿐이어야 한다")
    }

    /// 이어 읽는 GET 이 실패하면 **그 실패로 갈아 끼우지 않는다.** 네트워크 오류 같은 것으로 바꾸면
    /// 화면이 「다시 시작해 보세요」로 안내하게 되고, 그건 영원히 409 다.
    @Test("이어 읽는 조회가 실패해도 원래 409 를 그대로 올린다")
    func followUpFailureKeepsOriginal409() async throws {
        let api = FakeFareSplitApi(
            createError: httpError(409, "FARE_SPLIT_ALREADY_EXISTS", "이미 택시비 정산을 시작한 방입니다."),
            detailError: IOException("연결 거부")
        )

        let e = try await thrownError(FareSplitException.self) {
            _ = try await RemoteFareSplitRepository(api: api).startFareSplit(partyId: partyId, draft: draft)
        }

        #expect(e.isAlreadyExists)
        #expect(e.existing == nil)
        #expect(!e.isNetwork, "이어 읽기 실패가 원래 실패를 네트워크 오류로 갈아 끼웠다")
    }

    /// **409 가 아닌 실패에는 이어 읽지 않는다.** 「출발을 누르지 않은 방」에 조회를 덧붙이면 쓸모
    /// 없는 왕복이 하나 늘고, 그 조회의 404 가 로그에 섞여 원인을 가린다.
    @Test("정산을 시작할 수 없는 실패에는 이어 읽지 않는다")
    func otherStartFailuresDoNotFollowUp() async throws {
        let api = FakeFareSplitApi(
            createError: httpError(409, "PARTY_NOT_FINISHED", "동승이 끝난 방에서만 택시비를 정산할 수 있습니다.")
        )

        let e = try await thrownError(FareSplitException.self) {
            _ = try await RemoteFareSplitRepository(api: api).startFareSplit(partyId: partyId, draft: draft)
        }

        #expect(e.isPartyNotFinished)
        #expect(api.detailCalls.value == 0, "불필요한 상세 조회가 나갔다")
    }

    /// 셋이 같은 403/409 인데 **사용자가 할 수 있는 일이 서로 다르다** — 문구를 뭉치면 기다려야 할 때
    /// 다시 누르고, 다시 누르면 될 때 포기한다. 플래그가 서로 **배타적**인지까지 못 박는다.
    @Test("정산을 시작할 수 없는 세 이유를 서로 다르게 가른다")
    func threeStartBlockersAreDistinct() async throws {
        let cases: [(HttpException, [Bool])] = [
            (httpError(409, "PARTY_NOT_FINISHED", "x"), [true, false, false]),
            (httpError(403, "NOT_A_RIDER", "x"), [false, true, false]),
            (httpError(409, "NOT_ENOUGH_RIDERS", "x"), [false, false, true]),
        ]

        for (error, expected) in cases {
            let e = try await thrownError(FareSplitException.self) {
                _ = try await RemoteFareSplitRepository(api: FakeFareSplitApi(createError: error))
                    .startFareSplit(partyId: partyId, draft: draft)
            }

            #expect(
                [e.isPartyNotFinished, e.isNotARider, e.isNotEnoughRiders] == expected,
                "\(e.code ?? "nil") 의 분기가 섞였다"
            )
        }
    }

    /// 계좌번호 정규화가 **저장소를 거쳐도** 적용되는지 — 화면이 원문을 그대로 넘겨도 된다는 계약이다.
    @Test("보내는 계좌번호에서 하이픈이 떨어진다")
    func accountNumberIsNormalizedOnTheWayOut() async throws {
        let api = FakeFareSplitApi(detail: detailResponse())

        _ = try await RemoteFareSplitRepository(api: api).startFareSplit(partyId: partyId, draft: draft)

        let request = try api.createdRequests.value.single()
        #expect(request.accountNumber == "3333012345678")
        #expect(request.bankCode == "KAKAO")
    }

    // ─── 멱등 204 ───

    /// 못 박는 것: **멱등 204 를 성공으로만 다룬다.** 정산이 **열려 있는 동안** 서버는 이미
    /// SENT·CONFIRMED 여도 같은 204 를 주므로(실측), 「이미 그 상태였다」와 「지금 바뀌었다」를
    /// 응답으로 구분할 수 없다 — 알아낸 척하는 반환값을 만들면 화면이 그 값으로 **틀린 문구**를
    /// 띄운다. 확인할 것은 「안 터진다」가 전부다.
    ///
    /// 정산이 **닫힌 뒤**로는 둘의 사정이 갈린다 — 「받았어요」는 409 를 접고 「보냈어요」는 올린다
    /// (바로 아래 두 테스트).
    @Test("보냈어요와 받았어요는 다시 불러도 성공으로 끝난다")
    func idempotentCallsSucceed() async throws {
        let api = FakeFareSplitApi()
        let repository = RemoteFareSplitRepository(api: api)

        try await repository.markSent(partyId: partyId)
        try await repository.markSent(partyId: partyId)
        try await repository.confirmReceived(partyId: partyId, senderPublicId: senderPublicId)
        try await repository.confirmReceived(partyId: partyId, senderPublicId: senderPublicId)

        #expect(api.sentCalls.value == 2)
        #expect(api.receivedCalls.value == [senderPublicId, senderPublicId])
    }

    /// 못 박는 것: **「받았어요」의 409 `FARE_SPLIT_CLOSED` 를 성공으로 접는다** — 실측으로 알아낸 동작이다.
    ///
    /// 서버 Swagger 는 「이미 CONFIRMED 면 아무것도 바꾸지 않고 204」라고 적어 두었다. **사실이 아니다.**
    /// 마지막 송금을 확인하면 정산이 COMPLETED 로 닫히고, 그다음부터는 닫힘 검사가 먼저 걸려 409 다
    /// (원본 로컬 실측 2026-11-12, partyId 4143):
    ///
    /// | 호출 | 서버 |
    /// |---|---|
    /// | 1회 | 204 — 확인됐고 정산이 닫혔다 |
    /// | 2회 | **409 `FARE_SPLIT_CLOSED`** |
    ///
    /// 접지 않으면 204 가 터널에서 유실된 뒤 다시 누른 받는 사람에게 「이미 끝난 정산입니다」가 뜬다 —
    /// **자기가 방금 닫은 정산인데** 실패로 보인다. 「확인했다」와 「이미 확인돼 닫혔다」는 사용자가
    /// 할 일이 같다(아무것도 없다).
    ///
    /// 접어도 안전한 근거: 정산이 닫히는 조건이 **모든 송금이 CONFIRMED** 인 것이므로,
    /// 닫힌 정산에 남은 미확인 송금은 **존재할 수 없다**.
    @Test("받았어요의 닫힘 409 는 성공으로 접는다")
    func confirmReceivedFoldsClosed409() async throws {
        let api = FakeFareSplitApi(receivedError: httpError(409, "FARE_SPLIT_CLOSED", "이미 끝난 택시비 정산입니다."))

        try await RemoteFareSplitRepository(api: api).confirmReceived(partyId: partyId, senderPublicId: senderPublicId)

        #expect(api.receivedCalls.value == [senderPublicId])
    }

    /// 못 박는 것: **그 외 실패는 그대로 올린다** — 닫힘만 접는다.
    ///
    /// `FARE_SPLIT_TRANSFER_NOT_FOUND`(그 publicId 가 이 정산의 보내는 사람이 아니다)를 함께 접으면
    /// **받는 사람이 엉뚱한 사람의 송금을 확인한 것이 성공으로 보인다** — 화면은 확인됐다고 그리고,
    /// 서버에는 그 송금이 그대로 남아 정산이 영구히 닫히지 않는다.
    @Test("받았어요의 다른 실패는 접지 않는다")
    func confirmReceivedKeepsOtherFailures() async throws {
        let api = FakeFareSplitApi(
            receivedError: httpError(404, "FARE_SPLIT_TRANSFER_NOT_FOUND", "이 정산에서 택시비를 보내는 사람이 아닙니다.")
        )

        let e = try await thrownError(FareSplitException.self) {
            try await RemoteFareSplitRepository(api: api).confirmReceived(partyId: partyId, senderPublicId: senderPublicId)
        }

        #expect(e.isTransferNotFound)
        #expect(!e.isClosed, "닫힘으로 잘못 읽었다")
    }

    /// **「못 받았어요」만 멱등이 아니다.** 409 `TRANSFER_NOT_SENT` 를 삼키면 안 된다 —
    /// 「되돌릴 것이 없었다」는 받는 사람이 보고 있는 목록이 서버와 어긋났다는 뜻이라 **재조회가
    /// 필요한 신호**다.
    @Test("못 받았어요의 409 는 삼키지 않는다")
    func markNotReceivedKeeps409() async throws {
        let api = FakeFareSplitApi(
            notReceivedError: httpError(409, "TRANSFER_NOT_SENT", "보냈다고 표시된 송금만 못 받았다고 되돌릴 수 있습니다.")
        )

        let e = try await thrownError(FareSplitException.self) {
            try await RemoteFareSplitRepository(api: api).markNotReceived(partyId: partyId, senderPublicId: senderPublicId)
        }

        #expect(e.isTransferNotSent)
    }

    /// 응답을 받지 못한 실패는 재시도를 안내할 수 있게 `FareSplitException.isNetwork` 로 표시된다.
    @Test("네트워크 실패는 재시도 안내로 좁혀진다")
    func networkFailureIsMarked() async throws {
        let api = FakeFareSplitApi(sentError: IOException("타임아웃"))

        let e = try await thrownError(FareSplitException.self) {
            try await RemoteFareSplitRepository(api: api).markSent(partyId: partyId)
        }

        #expect(e.isNetwork)
        #expect(e.httpStatus == nil)
        #expect(e.code == nil)
    }

    /// `{code,message}` 가 아닌 본문(스프링 기본 404·405)에서도 터지지 않는다 — 상태 코드만 남는다.
    @Test("에러 본문이 code message 모양이 아니어도 터지지 않는다")
    func nonApiErrorBodyDoesNotCrash() async throws {
        let body = #"{"timestamp":"2026-11-12T00:00:00Z","status":405,"error":"Method Not Allowed","path":"/api/v1/..."}"#
        let api = FakeFareSplitApi(sentError: HttpException(Response<Void>.error(405, body)))

        let e = try await thrownError(FareSplitException.self) {
            try await RemoteFareSplitRepository(api: api).markSent(partyId: partyId)
        }

        #expect(e.httpStatus == 405)
        #expect(e.code == nil)
    }

    // ─── 내 정산 목록 ───

    /// 상태를 **늘 명시해 보낸다** — 서버 `defaultValue = "NOT_SENT"` 에 맡기면 서버가 기본값을 바꿀 때
    /// 홈 배너가 조용히 다른 목록을 그린다(에러로 드러나지 않는다).
    @Test("내 정산 목록은 상태 이름을 쿼리 값으로 넘긴다")
    func myListSendsStatusName() async throws {
        let api = FakeFareSplitApi()
        let repository = RemoteFareSplitRepository(api: api)

        _ = try await repository.getMyFareSplits()
        _ = try await repository.getMyFareSplits(status: .sent)

        #expect(api.myListQueries.value == ["NOT_SENT", "SENT"])
    }

    @Test("내 정산 목록이 비어 있어도 실패가 아니다")
    func emptyMyListIsNotFailure() async throws {
        let api = FakeFareSplitApi(myList: MyFareSplitListResponse())

        #expect(try await RemoteFareSplitRepository(api: api).getMyFareSplits().isEmpty)
    }

    // ─── 취소 ───

    /// (iOS 전용) **취소는 에러가 아니다** — 특히 409 뒤에 **이어 읽는** 조회가 걸려 있는 동안의 취소다.
    /// 원본은 그 자리에서 `runCatching` 을 일부러 피했다(취소까지 삼켜 「409 였다」로 바뀌어 올라간다).
    /// 여기서는 `URLError(.cancelled)` 도 취소라 일반 `catch` 가 삼키기 더 쉬운 자리다 — 화면을 떠나는
    /// 동작이 「이미 정산을 시작한 방입니다」로 보이면 안 된다.
    @Test("이어 읽는 조회 중의 취소는 그대로 전파된다", .timeLimit(.minutes(1)))
    func cancellationDuringFollowUpPropagates() async {
        let entered = AsyncSignal()
        let api = FakeFareSplitApi(
            createError: httpError(409, "FARE_SPLIT_ALREADY_EXISTS", "이미 택시비 정산을 시작한 방입니다."),
            detailGate: entered
        )
        let repository = RemoteFareSplitRepository(api: api)
        let draft = draft
        let partyId = partyId

        let job = Task { try await repository.startFareSplit(partyId: partyId, draft: draft) }
        await entered.wait()
        job.cancel()

        switch await job.result {
        case .success:
            Issue.record("취소됐는데 성공으로 끝났다")
        case .failure(let error):
            #expect(error is CancellationError, "취소가 \(type(of: error)) 로 바뀌었다")
        }
    }

    // ─── 하네스 ───

    private func httpError(_ status: Int, _ code: String, _ message: String) -> HttpException {
        HttpException(Response<Void>.error(status, #"{"code":"\#(code)","message":"\#(message)"}"#))
    }

    private func detailResponse(partyId: Int64? = 42, totalFare: Int = 18_700) -> FareSplitDetailResponse {
        FareSplitDetailResponse(
            partyId: partyId,
            status: "OPEN",
            totalFare: totalFare,
            payer: FareSplitPayerDto(publicId: "11111111-1111-1111-1111-111111111111", nickname: "방장"),
            myRole: "PAYER",
            myAmount: totalFare,
            bank: FareSplitDetailResponse.BankDto(code: "KAKAO", name: "카카오뱅크"),
            accountNumber: "3333012345678"
        )
    }
}

private final class FakeFareSplitApi: FareSplitApi {
    private let detail: FareSplitDetailResponse
    private let myList: MyFareSplitListResponse
    private let createError: (any Error)?
    private let detailError: (any Error)?
    private let editError: (any Error)?
    private let sentError: (any Error)?
    private let receivedError: (any Error)?
    private let notReceivedError: (any Error)?
    /// 조회가 **들어왔음**을 알리고 그대로 멈춰 선다 — 취소 전파를 보기 위한 장치다.
    private let detailGate: AsyncSignal?

    let createdRequests = Locked<[FareSplitRequestDto]>([])
    let editedRequests = Locked<[FareSplitRequestDto]>([])
    let myListQueries = Locked<[String]>([])
    let receivedCalls = Locked<[String]>([])
    let notReceivedCalls = Locked<[String]>([])
    let detailCalls = Locked(0)
    let sentCalls = Locked(0)

    init(
        detail: FareSplitDetailResponse = FareSplitDetailResponse(),
        myList: MyFareSplitListResponse = MyFareSplitListResponse(),
        createError: (any Error)? = nil,
        detailError: (any Error)? = nil,
        editError: (any Error)? = nil,
        sentError: (any Error)? = nil,
        receivedError: (any Error)? = nil,
        notReceivedError: (any Error)? = nil,
        detailGate: AsyncSignal? = nil
    ) {
        self.detail = detail
        self.myList = myList
        self.createError = createError
        self.detailError = detailError
        self.editError = editError
        self.sentError = sentError
        self.receivedError = receivedError
        self.notReceivedError = notReceivedError
        self.detailGate = detailGate
    }

    func createFareSplit(partyId: Int64, request: FareSplitRequestDto) async throws -> FareSplitDetailResponse {
        createdRequests.append(request)
        if let createError { throw createError }
        return detail
    }

    func getFareSplit(partyId: Int64) async throws -> FareSplitDetailResponse {
        detailCalls.update { $0 += 1 }
        if let detailGate {
            detailGate.complete()
            // 영원히 기다린다 — 깨우는 것은 취소뿐이다(취소되면 `CancellationError` 를 던진다).
            try await Task.sleep(for: .seconds(3_600))
        }
        if let detailError { throw detailError }
        return detail
    }

    func editFareSplit(partyId: Int64, request: FareSplitRequestDto) async throws -> FareSplitDetailResponse {
        editedRequests.append(request)
        if let editError { throw editError }
        return detail
    }

    func markSent(partyId: Int64) async throws {
        sentCalls.update { $0 += 1 }
        if let sentError { throw sentError }
    }

    func confirmReceived(partyId: Int64, senderPublicId: String) async throws {
        receivedCalls.append(senderPublicId)
        if let receivedError { throw receivedError }
    }

    func markNotReceived(partyId: Int64, senderPublicId: String) async throws {
        notReceivedCalls.append(senderPublicId)
        if let notReceivedError { throw notReceivedError }
    }

    func getMyFareSplits(status: String) async throws -> MyFareSplitListResponse {
        myListQueries.append(status)
        return myList
    }
}
