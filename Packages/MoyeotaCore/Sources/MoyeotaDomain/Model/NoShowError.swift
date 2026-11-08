import Foundation

/// 「노쇼 이의 신청」 실패를 화면이 **사유별로 안내할 수 있는 형태**로 좁힌 예외
/// (`NoShowRepository.submitObjection` 전용).
///
/// 액션마다 예외를 따로 두는 이유와 모양은 PR #82 의 셋
/// (`PartyConfirmException`·`PartyArriveException`·`PartyDepartException`)과 같다 — 사유가 여럿이고
/// **같은 코드가 다른 액션에서 다른 문장을 요구**하기 때문이다. 여기서 특히 그런 코드는
/// `NOT_PARTY_MEMBER` 다: 확정·도착·출발에서는 「방에서 나가진 상태예요」(지금 진행 중인 방 이야기)
/// 인데, 이의 신청에서는 **몇 주 전에 끝난 방**이라 「그 방의 참여자가 아니에요」여야 한다.
/// 한 예외로 묶으면 지난 기록을 보는 사용자에게 「방에서 나가졌어요」라고 말하게 된다.
///
/// ### 이 액션은 되돌릴 수 없다 — 그래서 사유가 더 중요하다 ★
/// 이의는 방마다 **한 번뿐**이다(서버 유니크 제약). 실패를 「다시 시도해 주세요」로 뭉개면 두 가지가
/// 함께 망가진다: ① 이미 접수된 사람은 눌러도 영원히 409 인데 접수된 줄 모르고, ② 아직 못 낸 사람은
/// 사유를 고칠 기회를 잃는다(400 은 글자 수 문제인데 그 말을 못 듣는다).
///
/// | 사유 | 서버 코드(HTTP) | 사용자가 할 일 |
/// |---|---|---|
/// | 사유가 비었거나 500자를 넘었다 | `INVALID_REQUEST` (400) | **글을 고친다** |
/// | 그 방의 참여자가 아니다 | `NOT_PARTY_MEMBER` (403) | 아무것도 — 대상이 아니다 |
/// | 방이 사라졌다 | `PARTY_NOT_FOUND` (404) | 목록을 다시 읽는다 |
/// | 그 방에서 노쇼가 아니거나 이미 무효다 | `NOT_NO_SHOW` (409) | 아무것도 — **낼 이유가 없다**(좋은 소식이다) |
/// | 이미 이의를 냈다 | `ALREADY_OBJECTED` (409) | 심사를 기다린다 |
///
/// 서버 검사 순서는 `Party.ensureNoShow` 그대로다: **참여자인가 → 노쇼인가 → 이미 냈는가.**
/// 앞의 검사가 걸리면 뒤 사유는 알 수 없으므로 화면이 "그리고 또…"를 붙이면 안 된다.
///
/// 분기 근거를 프로퍼티로 노출하는 것, **상태 코드로 폴백하지 않는 것**(409 가 두 가지다)도 같은
/// 이유다 — 코드를 모르면 `code` 는 null 이고 화면은 일반 문구로 떨어진다.
public struct NoShowObjectionException: Throwable {
    /// 서버 `MatchingErrorCode` 이름 또는 `INVALID_REQUEST`. 본문이 없거나 파싱 실패면 null.
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 null.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체가 없으면(네트워크 실패) null. 문구 분기에는 쓰지 않는다.
    public let httpStatus: Int?
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "이의를 신청하지 못했습니다." }

    /// 400 `INVALID_REQUEST` — 사유가 **비었거나(공백만) 500자를 넘었다**
    /// (서버 `@NotBlank` + `@Size(max = 500)`).
    ///
    /// **검증이 앞뒤 공백을 떼기 전에 돈다.** 즉 공백으로 패딩된 501자는 다듬으면 500자 이하여도
    /// 여기서 거절된다(서버가 `strip()` 하는 건 Bean Validation 을 통과한 **뒤**다). 그래서 앱이
    /// 보내기 전에 다듬어 두면 이 실패가 거의 사라진다 —
    /// `NoShowRepository.submitObjection` 이 그 일을 한다.
    ///
    /// 화면은 글자 수 제한을 **입력란에서** 막는 쪽이 맞다. 그래도 사유를 남기는 이유는 이 코드가
    /// **범용**이라서다: 본문이 깨졌거나(JSON 파싱 실패) 필드 이름이 틀려도 같은 400 이 온다 —
    /// 즉 이 사유가 뜨는데 입력이 멀쩡하면 **앱 버그를 의심해야 한다.**
    public var isInvalidReason: Bool { code == Self.INVALID_REQUEST }

    /// 403 `NOT_PARTY_MEMBER` — **그 방의 참여자가 아니다.** 서버가 가장 먼저 보는 검사라
    /// 이 403 이 오면 `isNotNoShow` 인지 아닌지는 알 수 없다.
    ///
    /// 화면이 자기가 받은 목록으로만 버튼을 띄우므로(그 목록은 내 노쇼뿐이다) 평소에는 오지 않는다 —
    /// 뜨면 **계정이 바뀐 뒤 낡은 목록을 들고 있는 것**이다(재로그인 후 재조회 전). 그래서 안내는
    /// 재시도가 아니라 **목록 새로 고침**이어야 한다.
    public var isNotMember: Bool { code == Self.NOT_PARTY_MEMBER }

    /// 404 `PARTY_NOT_FOUND` — 그 방이 사라졌다. 목록에서 빼고 다시 읽는다.
    public var isPartyNotFound: Bool { code == Self.PARTY_NOT_FOUND }

    /// 409 `NOT_NO_SHOW` — **그 방에서 노쇼가 아니거나, 이미 무효로 돌려졌다**
    /// (서버 판정: `noShowAt != null && noShowVoidedAt == null`).
    ///
    /// **실패지만 나쁜 소식이 아니다.** 두 번째 경우 — 이미 무효 — 는 사용자가 원하던 결과가 이미
    /// 이뤄진 상태다(다른 기기에서 냈던 이의가 인정됐거나, 운영자가 직접 풀어 줬다). 그래서 화면은
    /// 이 사유를 **에러 토스트로 끝내지 말고** 목록을 다시 읽어 `NoShowRecord.isVoided` 가 켜진 줄을
    /// 보여 주는 쪽이 맞다 — 그러면 「이 노쇼는 무효가 됐어요」라는 **정확한 상태**가 화면에 남는다.
    ///
    /// 목록이 `NoShowRecord.objectionStatus` `== nil && !isVoided` 인 줄에만 버튼을 띄우므로 평소에는
    /// 오지 않는다. 뜨는 경우는 들고 있는 목록이 낡았을 때다.
    public var isNotNoShow: Bool { code == Self.NOT_NO_SHOW }

    /// 409 `ALREADY_OBJECTED` — **이미 이의를 냈다.** 방마다 한 번뿐이다.
    ///
    /// **「이미 됨」에 가까운 실패다.** 서버가 이 코드를 주는 자리는 둘인데(사전 검사, 그리고 동시
    /// 요청에서 유니크 제약에 진 쪽) 둘 다 **내 이의가 서버에 들어 있다**는 뜻이다. 그래서 화면은
    /// 성공과 비슷하게 다뤄도 된다 — 목록을 다시 읽으면 그 줄의 상태가
    /// `ObjectionStatus.pending` 이상으로 와 있다.
    ///
    /// 다만 **저장소가 성공으로 되돌리지는 않는다.** 나가기의 403 과 달리
    /// (`PartyLeaveException` 주석) 이 코드는 「언제 낸 무엇이 어떤 상태인가」를 말해 주지 않아,
    /// 성공으로 접으면 화면이 「접수됐어요」를 **기각된 이의에도** 말하게 된다
    /// (`PartyConfirmException.isAlreadyConfirmed` 와 같은 판단이다). 상태는 목록 재조회가 준다.
    public var isAlreadyObjected: Bool { code == Self.ALREADY_OBJECTED }

    /// 서버가 이 엔드포인트에서 **실제로 던지는** 코드만 둔다
    /// (`NoShowObjectionService.object` → `Party.ensureNoShow` → 유니크 제약).
    ///
    /// `NO_SHOW_RESTRICTED` 는 **없다** — 제재 중인 사용자가 이의를 못 내면 제재를 풀 길이 없어지므로
    /// 서버가 이 경로에 그 검사를 걸지 않는다(걸린 사용자가 쓰는 유일한 출구다). 넣지 말 것.
    ///
    /// `INVALID_REQUEST` 는 `MatchingErrorCode` 가 아니라 공통 예외 핸들러의 문자열이지만, 이
    /// 엔드포인트에서는 **사유 글자 수를 뜻하는 실질 코드**라 여기 함께 둔다. `PartyOpenException` 이
    /// 같은 코드를 상수로 두지 **않는** 것과 반대 선택인데, 근거가 정확히 거울이다: 저쪽에서 그 코드는
    /// 좌표·이름·시각 누락까지 뜻하는 범용 코드라 사유가 될 수 없고, 이쪽은 본문에 필드가 **하나뿐**
    /// 이어서 그 400 이 사실상 「사유 글자 수」밖에 뜻하지 않는다.
    public static let INVALID_REQUEST = "INVALID_REQUEST"
    public static let NOT_PARTY_MEMBER = "NOT_PARTY_MEMBER"
    public static let PARTY_NOT_FOUND = "PARTY_NOT_FOUND"
    public static let NOT_NO_SHOW = "NOT_NO_SHOW"
    public static let ALREADY_OBJECTED = "ALREADY_OBJECTED"

    /// 서버 `@Size(max = …)` 와 같은 값. 입력란의 상한과 저장소의 사전 검사가 이 상수를 공유한다.
    public static let MAX_REASON_LENGTH = 500
}
