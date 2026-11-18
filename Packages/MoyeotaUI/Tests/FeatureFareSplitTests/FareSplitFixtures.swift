@testable import FeatureFareSplit
import MoyeotaDomain

/// 정산 테스트가 함께 쓰는 값 만들기.
///
/// 한 곳에 모으는 이유: `FareSplitDetail` 은 필드가 열세 개라 테스트마다 다시 적으면 **무엇을 보려고
/// 만든 값인지가 잡음에 묻힌다.** 기본값은 「가장 흔한 정상 상태」(OPEN · 받는 사람 화면 · 보내는 사람 둘)로
/// 두고, 각 테스트는 보려는 한 가지만 바꾼다.

let PAYER_ID = "payer-uuid"
let SENDER_A = "sender-a-uuid"
let SENDER_B = "sender-b-uuid"

func transfer(
    _ publicId: String = SENDER_A,
    _ nickname: String = "동승자A",
    _ amount: Int = 6_233,
    status: TransferStatus = .notSent,
    maskedRealName: String? = nil
) -> FareSplitTransfer {
    FareSplitTransfer(
        senderPublicId: publicId,
        nickname: nickname,
        amount: amount,
        status: status,
        sentAt: status != .notSent ? "2026-11-12T01:00:00Z" : nil,
        confirmedAt: status == .confirmed ? "2026-11-12T02:00:00Z" : nil,
        maskedRealName: maskedRealName
    )
}

/// 내 송금 상태가 **역할을 따라가는** 기본값을 갖도록 따로 표시한다.
///
/// 받는 사람은 서버가 **일부러 nil** 을 준다(`FareSplit.transferStatusOf` 가 빈 값). 그 기본값을 `.notSent` 로
/// 두면 테스트가 실제로 올 수 없는 응답을 만들어 「방장에게 「보냈어요」가 뜨는」 결함을 통과시킨다.
enum MyTransfer {
    case byRole
    case value(TransferStatus?)
}

func detail(
    status: FareSplitStatus = .open,
    role: FareSplitRole = .payer,
    myTransferStatus: MyTransfer = .byRole,
    totalFare: Int = 18_700,
    myAmount: Int = 6_234,
    accountNumber: String? = "3333012345678",
    tossDeeplink: String? = nil,
    transfers: [FareSplitTransfer] = [
        transfer(SENDER_A, "동승자A", 6_233),
        transfer(SENDER_B, "동승자B", 6_233),
    ],
    payer: FareSplitParticipant = FareSplitParticipant(publicId: PAYER_ID, nickname: "방장"),
    bank: FareSplitBank = FareSplitBank(code: Bank.kakao.code, displayName: Bank.kakao.displayName, known: .kakao)
) -> FareSplitDetail {
    let mine: TransferStatus? = switch myTransferStatus {
    case .byRole: role == .sender ? .notSent : nil
    case .value(let value): value
    }
    return FareSplitDetail(
        partyId: 42,
        status: status,
        totalFare: totalFare,
        payer: payer,
        myRole: role,
        myAmount: myAmount,
        myTransferStatus: mine,
        bank: bank,
        accountNumber: accountNumber,
        tossDeeplink: tossDeeplink,
        transfers: transfers,
        createdAt: "2026-11-12T00:00:00Z",
        closedAt: status == .open ? nil : "2026-11-12T03:00:00Z"
    )
}

func member(
    _ id: String,
    _ nickname: String? = nil,
    isMe: Bool = false,
    isHost: Bool = false,
    arrived: Bool = true
) -> User {
    User(
        id: id,
        nickname: nickname ?? id,
        verifiedLabel: "",
        rating: 0,
        rideCount: 0,
        isMe: isMe,
        isHost: isHost,
        hasArrived: arrived
    )
}

func ride(
    status: RideStatus = .completed,
    members: [User] = [
        member(PAYER_ID, "방장", isMe: true, isHost: true),
        member(SENDER_A, "동승자A"),
        member(SENDER_B, "동승자B"),
    ],
    estimatedFare: Int? = nil
) -> Ride {
    Ride(
        id: "42",
        origin: "센텀시티역 3번 출구",
        destination: "서면역 1번 출구",
        departureLabel: "지금 출발",
        capacity: 3,
        members: members,
        farePerPerson: 0,
        totalFare: 0,
        status: status,
        estimatedFare: estimatedFare
    )
}

func myFareSplit(
    partyId: Int64 = 42,
    departure: String? = "센텀시티역",
    destination: String? = "서면역",
    myAmount: Int = 6_233,
    status: TransferStatus = .notSent
) -> MyFareSplit {
    MyFareSplit(
        partyId: partyId,
        departure: departure,
        destination: destination,
        payer: FareSplitParticipant(publicId: PAYER_ID, nickname: "방장"),
        myAmount: myAmount,
        status: status,
        createdAt: "2026-11-12T00:00:00Z"
    )
}

/// 서버 코드 하나로 만든 실패. `serverMessage` 는 **일부러 사람이 읽을 만한 한국어**로 둔다 —
/// 그래도 화면이 그걸 쓰지 않는지 보는 테스트가 있다(`FareSplitFailureMessageTest`).
func failure(
    _ code: String?,
    httpStatus: Int? = 400,
    serverMessage: String? = "서버가 보낸 원문입니다",
    isNetwork: Bool = false
) -> FareSplitException {
    FareSplitException(code: code, serverMessage: serverMessage, httpStatus: httpStatus, isNetwork: isNetwork)
}

/// 시작 폼 하나 — 방장 + 동승자 둘, 택시비 18,700원, 은행·계좌까지 채운 정상 상태.
func readyStartDraft() -> FareSplitDraftState {
    guard case .ready(let state) = startDraftGate(ride: ride()) else {
        fatalError("기본 방은 시작할 수 있어야 한다")
    }
    return state
        .withFare(raw: "18700")
        .withBank(bank: .kakao)
        .withAccount(raw: "3333-01-2345678")
}
