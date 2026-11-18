/// 택시비 정산 — 동승이 끝난 방에서 **방장이 전액을 내고**, 사람마다 부담 금액을 적은 장부를 만들면
/// 함께 탄 나머지가 토스·은행 앱으로 각자 보낸다. **앱은 돈을 옮기지 않는다.**
///
/// ### 쓰기 응답이 두 모양뿐이다
/// | 하는 일 | 서버 응답 | 그래서 |
/// |---|---|---|
/// | 시작·수정 | 정산 상세 | 돌려받은 `FareSplitDetail` 로 화면을 **그대로 갈아 끼운다**(다시 조회할 필요 없다) |
/// | 보냈어요·받았어요·못 받았어요 | **204, 본문 없음** | 바뀐 결과를 알 길이 없다 → 성공 뒤 `getFareSplit` 을 **반드시 다시 부른다** |
///
/// 뒤쪽 셋은 한 건을 바꾸는 것처럼 보이지만 **정산 전체를 움직일 수 있다** — 마지막 송금이
/// 확인되면 서버가 정산을 COMPLETED 로 닫고 **계좌번호를 지운다**. 즉 화면이 들고 있던
/// `FareSplitDetail.accountNumber` 가 그 순간 과거가 된다. 한 행만 낙관적으로 고치면 닫힌 정산에
/// 계좌번호가 남아 보인다.
///
/// 홈 배너(`getMyFareSplits`)도 함께 낡는다 — 「보냈어요」가 성공하면 그 방은 `notSent` 목록에서
/// 빠져야 한다. 배너는 목록을 다시 받는 것 외에 갱신 수단이 없다.
///
/// ### 실패는 전부 `FareSplitException` 이다
/// presentation 은 네트워크 계층을 의존하지 않으므로(`MoyeotaUI` 는 `MoyeotaCore` 중 `MoyeotaDomain` 만 본다)
/// HTTP 를 그대로 올리면 화면이 403 다섯 가지를 구분할 수 없다. 코드별 뜻과 처방은
/// `FareSplitException` 주석의 표에 있다.
public protocol FareSplitRepository: Sendable {

    /// 정산을 시작한다(`POST /matching/rooms/{partyId}/fare-split`, 201). **방장만** 부를 수 있고,
    /// 방장이 받는 사람(PAYER)이 된다.
    ///
    /// 시작 조건은 셋이다 — 끝난 방(FINISHED) · 방장이 탑승자 · 탑승자 2명 이상. 어느 쪽으로 막혀도
    /// 사용자가 할 수 있는 일이 다르므로 `FareSplitException` 의
    /// `isPartyNotFinished`·`isNotARider`·`isNotEnoughRiders` 로 갈라 안내한다.
    ///
    /// **`draft` 의 `payments` 는 앱이 채운다** — 서버는 검사만 한다
    /// (`FareSplitPolicy.splitEvenly`).
    ///
    /// - Returns: 시작한 정산 상세(받는 사람 화면).
    /// - Throws: `FareSplitException`. **409 `FARE_SPLIT_ALREADY_EXISTS` 는 실패로 보여 주지 말 것** —
    ///   이미 있는 정산을 `FareSplitException.existing` 에 담아 준다(없으면 `getFareSplit` 으로 다시 받는다).
    func startFareSplit(partyId: Int64, draft: FareSplitDraft) async throws -> FareSplitDetail

    /// 정산 상세(`GET /matching/rooms/{partyId}/fare-split`). **받는 사람과 보내는 사람만** 볼 수 있다.
    ///
    /// ### 정산이 없으면 **nil** 이다 — 예외가 아니다
    /// 404 `FARE_SPLIT_NOT_FOUND` 는 「아직 아무도 시작하지 않았다」는 뜻이고, 그건 끝난 방의
    /// **정상 상태**다(방장에게 「정산 시작하기」를 띄울 자리다). 예외로 올리면 모든 호출자가
    /// 「정상인 404」와 「진짜 실패」를 가리려고 do/catch 를 쓰게 되고, 한 곳만 빠뜨리면 멀쩡한 방에
    /// 빨간 에러가 뜬다.
    ///
    /// 접는 것은 **그 404 하나뿐**이다. 403 `NOT_FARE_SPLIT_PARTICIPANT` 는 그대로 올린다 —
    /// 「정산이 없다」와 「정산은 있는데 내가 당사자가 아니다」는 화면이 할 말이 다르고(앞은 시작하기,
    /// 뒤는 안내 후 나가기), nil 로 접으면 도착을 누르지 않은 사람에게 **「정산 시작하기」가 뜬다**
    /// (눌러도 403 `NOT_A_RIDER` 다).
    ///
    /// (`PlaceRepository` 의 즐겨찾기 삭제가 404 를 **삼키지 않는** 것과 어긋나 보이지만 사정이 반대다 —
    /// 그쪽 404 에는 「이미 지워졌다」·「없다」·「남의 것」 셋이 섞여 있어 접으면 남의 행 삭제가 성공처럼
    /// 보인다. 이쪽 404 는 뜻이 **하나뿐**이다.)
    ///
    /// - Returns: 정산 상세, 또는 이 방에 정산이 없으면 nil.
    func getFareSplit(partyId: Int64) async throws -> FareSplitDetail?

    /// 정산을 고친다(`PATCH /matching/rooms/{partyId}/fare-split`). **받는 사람만**, **아무도 보내기
    /// 전**(전원 NOT_SENT)인 OPEN 정산만 고칠 수 있다(`FareSplitDetail.canEdit`).
    ///
    /// **일부가 아니라 전부 보낸다** — 택시비·은행·계좌번호·사람마다 부담 금액이 모두 필수이고
    /// 규칙은 시작과 같다. 금액만 고치려 해도 `draft` 를 전부 채워야 하므로, 기존 상세에서
    /// 은행 코드를 **그대로 되돌려** 담는다(`FareSplitDraft.bankCode`).
    ///
    /// 서버에 **정산 취소는 없다** — 잘못 넣었으면 고치고, 따로 받았으면 `confirmReceived` 로 닫는다.
    ///
    /// - Returns: 고친 정산 상세. 화면을 이것으로 갈아 끼운다.
    /// - Throws: `FareSplitException`. 409 `FARE_SPLIT_ALREADY_STARTED` 면 그사이 누가 「보냈어요」를 눌렀다.
    func editFareSplit(partyId: Int64, draft: FareSplitDraft) async throws -> FareSplitDetail

    /// 「보냈어요」(`POST …/fare-split/sent`, 204). **보내는 사람**이 토스·은행 앱으로 자기 몫을 보낸
    /// 뒤 누른다(NOT_SENT → SENT).
    ///
    /// ### 멱등이다 — 「이미 그 상태였다」와 「지금 바뀌었다」를 **구분할 수 없다**
    /// 이미 SENT·CONFIRMED 여도 서버는 **아무것도 바꾸지 않고 같은 204** 를 준다(알림도 다시 가지
    /// 않는다). 응답에 차이가 없으므로 앱은 그 차이를 알 길이 없고, **알 필요도 없다** — 두 경우 모두
    /// 사용자가 원한 상태가 참이 됐다. 그래서 **성공으로만** 처리한다(「이미 보냈습니다」 같은 문구를
    /// 지어내지 말 것 — 틀릴 수 있다).
    ///
    /// 성공 뒤에는 `getFareSplit` 과 `getMyFareSplits` 를 다시 받는다(이 호출은 본문을 주지 않는다).
    func markSent(partyId: Int64) async throws

    /// 「받았어요」(`POST …/fare-split/transfers/{publicId}/received`, 204). **받는 사람**이 그 송금을
    /// 받았다고 확인한다(→ CONFIRMED).
    ///
    /// `markSent` 와 같은 뜻의 멱등이다(이미 CONFIRMED 면 그대로 204). **보냈다고 누르기 전(NOT_SENT)
    /// 이어도 확인할 수 있다** — 현금으로 받은 경우다.
    ///
    /// ### 마지막 확인이 정산을 닫는다
    /// 모든 송금이 CONFIRMED 가 되면 서버가 정산을 COMPLETED 로 닫고 **계좌번호를 지운다**. 되돌리는
    /// 길은 없다. 그래서 성공 뒤 상세 재조회는 선택이 아니라 **필수**다 — 화면이 들고 있던 계좌번호가
    /// 이미 서버에 없을 수 있다.
    ///
    /// - Parameter senderPublicId: 보내는 사람의 publicId(`FareSplitTransfer.senderPublicId`).
    ///   빈 값이면 **부르지 말 것** — 서버가 404 `FARE_SPLIT_TRANSFER_NOT_FOUND` 로 막는다
    ///   (화면은 `FareSplitTransfer.isConfirmable` 로 버튼을 잠근다).
    func confirmReceived(partyId: Int64, senderPublicId: String) async throws

    /// 「못 받았어요」(`POST …/fare-split/transfers/{publicId}/not-received`, 204). 받는 사람이
    /// 아직 입금이 없다고 되돌린다(SENT → NOT_SENT, sentAt 삭제).
    ///
    /// **셋 중 유일하게 멱등이 아니다.** SENT 인 송금에서만 되고, 아직 안 보냈거나 이미 확인한
    /// 송금이면 409 `TRANSFER_NOT_SENT` 다(`FareSplitException.isTransferNotSent`). 「두 번 눌러도
    /// 괜찮다」가 성립하지 않는 유일한 동작이므로, 화면은 SENT 인 행에만 이 버튼을 띄운다.
    func markNotReceived(partyId: Int64, senderPublicId: String) async throws

    /// 내가 **보내는 사람인 진행 중(OPEN)** 정산 목록(`GET /users/me/fare-splits?status=…`).
    /// 정산 시작 최신순이고, 없으면 빈 목록이다.
    ///
    /// 기본값 `TransferStatus.notSent`(인자 없는 `getMyFareSplits()`)가 홈 배너(「아직 보내지 않은
    /// 택시비」)의 입력이다. **받는 사람으로 시작한 정산과 닫힌 정산은 나오지 않는다** — 즉 이 목록이
    /// 비었다는 것은 「내가 보낼 돈이 없다」는 뜻이고, 「정산이 없다」는 뜻이 아니다(받는 사람인 정산은
    /// 여기에 절대 나타나지 않는다). 방장의 할 일 배너를 이 목록으로 만들면 **영구히 비어 있다.**
    ///
    /// 각 줄의 `partyId` 로 상세를 연다(`getFareSplit`).
    func getMyFareSplits(status: TransferStatus) async throws -> [MyFareSplit]
}

extension FareSplitRepository {
    /// Kotlin 기본 인자 `status: TransferStatus = TransferStatus.NOT_SENT` 의 자리 — 홈 배너가 부르는 모양이다.
    public func getMyFareSplits() async throws -> [MyFareSplit] {
        try await getMyFareSplits(status: .notSent)
    }
}
