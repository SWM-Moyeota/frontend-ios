import Foundation

/// 택시비 정산 요청 실패를 화면이 다룰 수 있는 형태로 좁힌 예외
/// (`ChatException`·`FavoritePlaceException` 과 같은 경계다 — presentation 은 네트워크 계층을 모른다).
///
/// ### 상태 코드로는 **아무것도** 갈리지 않는다
/// 서버 `FareSplitErrorCode` 18종이 네 상태에 몰려 있다:
///
/// | 상태 | 그 상태에 들어 있는 코드 수 | 들어 있는 것 |
/// |---|---|---|
/// | 400 | 4 (+공통 `INVALID_REQUEST`) | `INVALID_ACCOUNT_NUMBER`·`INVALID_PAYMENT`·`PAYMENT_TARGET_MISMATCH`·`PAYMENTS_NOT_EQUAL_FARE` |
/// | 403 | 5 | `NOT_PARTY_HOST`·`NOT_A_RIDER`·`NOT_FARE_SPLIT_PARTICIPANT`·`NOT_FARE_SPLIT_PAYER`·`NOT_FARE_SPLIT_SENDER` |
/// | 404 | 3 | `PARTY_NOT_FOUND`·`FARE_SPLIT_NOT_FOUND`·`FARE_SPLIT_TRANSFER_NOT_FOUND` |
/// | 409 | 6 | `FARE_SPLIT_ALREADY_EXISTS`·`PARTY_NOT_FINISHED`·`NOT_ENOUGH_RIDERS`·`FARE_SPLIT_CLOSED`·`FARE_SPLIT_ALREADY_STARTED`·`TRANSFER_NOT_SENT` |
///
/// 즉 `httpStatus` 만 보면 **한 상태 안에서 사용자가 할 일이 정반대인 것들**이 섞인다. 특히
/// 「정산을 시작할 수 없는」 세 실패는 **같은 403/409 인데 할 수 있는 일이 서로 다르다** — 문구를
/// 뭉치면 사용자가 기다려야 할 때 다시 누르고, 다시 누르면 될 때 포기한다:
///
/// | 코드 | 왜 막혔나 | 사용자가 할 수 있는 일 |
/// |---|---|---|
/// | `isPartyNotFinished` `PARTY_NOT_FINISHED`(409) | 아직 **출발을 누르지 않은** 방이다 | **있다** — 「출발」을 누른 뒤 다시 시작하면 된다 |
/// | `isNotARider` `NOT_A_RIDER`(403) | 방장이 **출발지 도착을 누르지 않아** 탑승자가 아니다(자동 정리된 방) | **없다.** 도착은 방이 끝난 뒤에 되돌릴 수 없다 — 이 방은 영구히 정산할 수 없다 |
/// | `isNotEnoughRiders` `NOT_ENOUGH_RIDERS`(409) | 도착을 누른 사람이 **방장 혼자**다 | **없다.** 혼자 탔으면 나눌 상대가 없다 — 「다른 사람이 도착을 누르면 된다」가 아니다(방이 이미 끝났다) |
///
/// 그래서 화면은 플래그로 분기하고, `code` 문자열을 직접 비교하지 않는다 — 서버가 enum 이름을
/// 바꾸면 조용히 어긋난다.
public struct FareSplitException: Throwable {
    /// 서버 `FareSplitErrorCode` 이름. 본문이 없거나 파싱 실패면 nil(그때는 `httpStatus` 만 근거).
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 nil.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체를 받지 못했으면(네트워크 실패) nil.
    public let httpStatus: Int?
    /// 응답을 받지 못한 실패(연결 거부·타임아웃·DNS). 사용자에게는 재시도를 안내한다.
    public let isNetwork: Bool
    /// **이미 그 방에 정산이 있었을 때** 저장소가 이어서 읽어 담아 주는 그 정산의 현재 상세.
    ///
    /// 409 `FARE_SPLIT_ALREADY_EXISTS` 는 서버가 「GET 으로 본다」라고 적어 둔 **복구 가능한 실패**다
    /// (Swagger 원문: 「이미 정산을 시작한 방(GET 으로 본다)」). 그래서 데이터 계층이 그 GET 을 대신
    /// 해 두고, 성공하면 여기에 담는다 — 추측이 아니라 **증거**다. 채워져 있으면 화면은 이 실패를
    /// 성공처럼 다뤄도 된다(시작 성공과 똑같이 상세로 넘기면 된다).
    ///
    /// `PartyJoinException.joinedStatus` 와 같은 배치이고 이유도 같다 — 서버가 「이미 됨」을 실패로
    /// 돌려줄 때, 그 실패를 화면까지 올려 보내면 사용자는 **이미 존재하는 자기 정산을 못 보게** 된다.
    ///
    /// 이어 읽은 GET 자체가 실패하면 nil 이다(그 실패는 삼킨다 — 원래 실패를 가리지 않는다).
    /// 그때도 `isAlreadyExists` 는 참이므로 화면은 상세를 직접 다시 받으면 된다.
    public let existing: FareSplitDetail?
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        isNetwork: Bool = false,
        existing: FareSplitDetail? = nil,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.isNetwork = isNetwork
        self.existing = existing
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "택시비 정산 요청에 실패했습니다." }

    // ─── 방·탑승 조건 (정산 시작) ───

    /// 404 `PARTY_NOT_FOUND` — 방이 없다(지워졌거나 id 가 틀렸다).
    public var isPartyNotFound: Bool { code == "PARTY_NOT_FOUND" }

    /// 403 `NOT_PARTY_HOST` — 방장만 정산을 시작할 수 있다. 시작 버튼을 방장에게만 띄우는 것이 1차 방어선이다.
    public var isNotPartyHost: Bool { code == "NOT_PARTY_HOST" }

    /// 403 `NOT_A_RIDER` — **방장이 출발지 도착을 누르지 않아 탑승자가 아니다.**
    ///
    /// 위 표의 세 실패 중 유일하게 **403** 이고, 되돌릴 길이 없다. 「도착을 눌러 주세요」로 안내하면
    /// 안 된다 — 방은 이미 끝났고(FINISHED) 도착은 더 이상 받지 않는다.
    public var isNotARider: Bool { code == "NOT_A_RIDER" }

    /// 409 `PARTY_NOT_FINISHED` — 아직 **출발을 누르지 않은** 방이다. 셋 중 **유일하게 사용자가 할 일이
    /// 있는** 실패다(「출발」을 누르면 풀린다).
    public var isPartyNotFinished: Bool { code == "PARTY_NOT_FINISHED" }

    /// 409 `NOT_ENOUGH_RIDERS` — 함께 탄 사람이 혼자다. 나눌 상대가 없어 되돌릴 길이 없다.
    public var isNotEnoughRiders: Bool { code == "NOT_ENOUGH_RIDERS" }

    // ─── 정산 존재·역할 ───

    /// 409 `FARE_SPLIT_ALREADY_EXISTS` — **이미 시작한 방이다.** 방마다 정산은 하나뿐이고 다시 만들
    /// 수 없다(고칠 수만 있다).
    ///
    /// **실패로 보여 주지 말 것.** 사용자가 원한 것(「정산을 보고 싶다」)은 이미 이뤄져 있다 —
    /// `existing` 이 채워져 있으면 그대로 상세로 넘기고, nil 이면 상세를 다시 받는다.
    public var isAlreadyExists: Bool { code == "FARE_SPLIT_ALREADY_EXISTS" }

    /// 404 `FARE_SPLIT_NOT_FOUND` — 이 방에 정산이 없다.
    ///
    /// 조회 경로에서는 **정상 상태**다(아직 아무도 시작하지 않았다). 화면은 에러가 아니라 「정산
    /// 시작하기」로 그려야 한다 — 조회 경로에서 저장소가 이 404 를 nil 로 접는 이유는
    /// `FareSplitRepository.getFareSplit` 주석에 있다(이 값이 참인 예외는 그 밖의 경로에서만 올라온다).
    public var isFareSplitNotFound: Bool { code == "FARE_SPLIT_NOT_FOUND" }

    /// 403 `NOT_FARE_SPLIT_PARTICIPANT` — 받는 사람도 보내는 사람도 아니다(그 택시를 타지 않았다).
    /// 방에는 있었지만 도착을 누르지 않은 사람이 상세를 열면 여기로 떨어진다.
    public var isNotParticipant: Bool { code == "NOT_FARE_SPLIT_PARTICIPANT" }

    /// 403 `NOT_FARE_SPLIT_PAYER` — **받는 사람만** 할 수 있는 일을 보내는 사람이 했다
    /// (수정·받았어요·못 받았어요).
    ///
    /// 이 값이 참이면 화면이 든 `FareSplitDetail.myRole` 이 서버와 어긋났다는 뜻이므로,
    /// 문구만 띄우지 말고 **상세를 다시 받아야** 한다.
    public var isNotPayer: Bool { code == "NOT_FARE_SPLIT_PAYER" }

    /// 403 `NOT_FARE_SPLIT_SENDER` — 받는 사람이 「보냈어요」를 눌렀다. `isNotPayer` 와 같은 처방이다.
    public var isNotSender: Bool { code == "NOT_FARE_SPLIT_SENDER" }

    /// 404 `FARE_SPLIT_TRANSFER_NOT_FOUND` — 그 publicId 는 이 정산의 보내는 사람이 아니다.
    ///
    /// 앱이 이 코드를 보는 경우는 둘이다: ① 들고 있던 상세가 낡았다 ② 화면이 publicId 가 빈 행의
    /// 버튼을 잠그지 않았다(`FareSplitTransfer.isConfirmable`). 둘 다 **상세 재조회**로 끝낸다.
    public var isTransferNotFound: Bool { code == "FARE_SPLIT_TRANSFER_NOT_FOUND" }

    // ─── 정산 상태 ───

    /// 409 `FARE_SPLIT_CLOSED` — 이미 닫힌(COMPLETED·EXPIRED) 정산이다. **모든 쓰기 경로의 공통 거절**이다.
    ///
    /// 닫힌 뒤에는 서버가 계좌번호를 지우므로, 이 실패를 받으면 화면에 남아 있는 계좌번호도 더 이상
    /// 유효하다고 말할 수 없다 — 상세를 다시 받아 **읽기 전용**으로 다시 그린다.
    public var isClosed: Bool { code == "FARE_SPLIT_CLOSED" }

    /// 409 `FARE_SPLIT_ALREADY_STARTED` — 누군가 「보냈어요」를 눌렀거나 확인된 송금이 있어 **고칠 수
    /// 없다.** `FareSplitDetail.canEdit` 가 미리 막지만, 상세를 받은 뒤 누군가 눌렀으면 여기로 온다.
    ///
    /// 수정 화면을 그냥 닫지 말 것 — 사용자가 입력한 값이 사라진다. 상세를 다시 받아 「이미 송금이
    /// 시작돼 고칠 수 없다」를 보여 주고 읽기 전용으로 바꾼다.
    public var isAlreadyStarted: Bool { code == "FARE_SPLIT_ALREADY_STARTED" }

    /// 409 `TRANSFER_NOT_SENT` — 「못 받았어요」는 **SENT 인 송금에서만** 된다(아직 안 보냈거나 이미
    /// 확인한 송금은 되돌릴 수 없다).
    ///
    /// 되돌리기는 **멱등이 아니다** — 「보냈어요」·「받았어요」가 이미 그 상태면 204 로 넘어가는 것과
    /// 다르다. 그래서 이 하나만 「두 번 눌러도 괜찮다」가 성립하지 않는다.
    public var isTransferNotSent: Bool { code == "TRANSFER_NOT_SENT" }

    // ─── 입력 검증 ───

    /// 400 `INVALID_ACCOUNT_NUMBER` — 계좌번호가 숫자 10~16자리가 아니다.
    /// `FareSplitPolicy.isAccountNumberValid` 가 미리 막아야 하는 실패다 — 여기까지 왔다면 화면이
    /// 전송 버튼을 잠그지 않았다는 뜻이다.
    public var isInvalidAccountNumber: Bool { code == "INVALID_ACCOUNT_NUMBER" }

    /// 400 `PAYMENT_TARGET_MISMATCH` — `payments` 에 탑승자가 빠졌거나, 탑승자가 아닌 사람이 있거나,
    /// 두 번 있다. **세 경우가 같은 코드**라 서버 응답만으로는 어느 쪽인지 알 수 없다.
    ///
    /// 원인은 거의 늘 하나다: 방 **멤버 전원**으로 채웠고 그중 도착을 누르지 않은 사람이 있었다
    /// (`Ride.fareSplitRiders` 로 골라야 한다). 처방은 방 상세 재조회다 — 금액을 고쳐서는 풀리지 않는다.
    public var isPaymentTargetMismatch: Bool { code == "PAYMENT_TARGET_MISMATCH" }

    /// 400 `PAYMENTS_NOT_EQUAL_FARE` — 부담 금액의 합이 택시비와 다르다.
    /// `isPaymentTargetMismatch` 와 **처방이 정반대**다(이쪽은 금액 칸을 고치면 풀린다) —
    /// 뭉치면 사용자가 고칠 수 있는 것을 고치지 못한다. `FareSplitPolicy.problemOf` 가 미리 막는다.
    public var isPaymentsNotEqualFare: Bool { code == "PAYMENTS_NOT_EQUAL_FARE" }

    /// 400 `INVALID_PAYMENT` — 부담 금액이 1원 미만이다(서버 `FarePayment` 의 불변식).
    ///
    /// 서버의 Bean Validation 이 먼저 걸리는 경우가 많아 실제로는 `INVALID_REQUEST` 로 올 수도 있다
    /// (`isInvalidRequest`) — 그래서 금액 하한은 **앱이 먼저** 본다
    /// (`FareSplitDraftProblem.shareBelowMinimum`).
    public var isInvalidPayment: Bool { code == "INVALID_PAYMENT" }

    /// 400 `INVALID_REQUEST` — Bean Validation 실패. 정산 도메인 코드가 아니라 **공통 코드**다.
    ///
    /// 서버 message 가 필드명을 그대로 담으므로(「totalFare: 택시비는 1원 이상이어야 합니다」)
    /// **사용자에게 그대로 보여 주면 안 된다** — 화면이 자기 문구로 갈아 끼운다
    /// (`ChatException.isInvalidRequest` 와 같은 관례).
    public var isInvalidRequest: Bool { code == "INVALID_REQUEST" }

    /// 401 — 토큰이 없거나 만료됐다. 재발급까지 실패한 뒤에만 여기까지 올라온다.
    public var isUnauthorized: Bool { httpStatus == 401 }
}
