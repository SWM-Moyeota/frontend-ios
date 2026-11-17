import MoyeotaDomain

/// 닉네임 규칙 — 서버 도메인 VO `Nickname` 과 **같은 정규식**이다(앞뒤 공백 strip 후
/// `^[가-힣a-zA-Z0-9]{2,10}$`). 화면이 같은 기준으로 먼저 걸러 400 왕복을 줄일 뿐,
/// 최종 판정은 서버다.
///
/// 2026-09 서버 변경으로 닉네임이 가입 필수가 되면서, 예전 「표시 이름 3~8자」 규칙을 대체했다.
/// 금칙어 목록은 서버에 없는 앱 자체 정책이라 그대로 유지한다.
public enum NicknamePolicy {
    /// 규칙 자체는 도메인 `AuthPolicy` 가 갖는다 — 여기서는 "왜 틀렸는지"만 문구로 옮긴다.
    public static let MAX_LENGTH = AuthPolicy.NICKNAME_MAX_LENGTH
    private static let MIN_LENGTH = AuthPolicy.NICKNAME_MIN_LENGTH

    /// 운영자 사칭어. **걸린 단어를 문구에 그대로 보여 준다**(2026-11-17 QA) — 「모두모여타요」처럼 사칭 뜻이
    /// 없는 닉네임도 글자가 겹치면 막히는데, 이유 없이 「사용할 수 없는 닉네임이에요」만 보이면 사용자가
    /// 무엇을 고쳐야 할지 알 수 없었다. 영문은 대소문자를 가리지 않는다(「Admin」도 사칭이다).
    private static let ImpersonationWords = ["모여타", "관리자", "운영자", "admin"]

    /// 욕설. 이쪽은 **단어를 되읽어 주지 않는다** — 화면에 욕설을 다시 적을 이유가 없다.
    private static let ProfanityWords = ["시발", "씨발", "병신", "새끼", "지랄", "미친", "좆", "썅"]

    public static func isValid(raw: String) -> Bool { validate(raw: raw) == nil }

    /// 형식 오류 문구. 규칙을 만족하면 nil.
    /// 빈 입력은 "아직 안 썼다"이지 오류가 아니므로 호출부가 먼저 걸러 쓴다.
    public static func validate(raw: String) -> String? {
        let value = raw.trim()
        if value.isEmpty { return "닉네임을 입력해 주세요" }
        if !matchesCharRule(value) { return "한글·영문·숫자만 쓸 수 있어요 (공백·특수문자·이모지 불가)" }
        if !AuthPolicy.isValidNickname(value: value) { return "닉네임은 \(MIN_LENGTH)~\(MAX_LENGTH)자로 입력해 주세요" }
        if let word = ImpersonationWords.first(where: { value.lowercased().contains($0) }) {
            // 조사(은/는)를 붙이지 않는 문장 — 「admin」·「모여타」 어느 쪽에도 맞는다
            return "운영자로 보일 수 있는 말(「\(word)」)은 닉네임에 쓸 수 없어요"
        }
        if ProfanityWords.contains(where: { value.contains($0) }) { return "욕설·비속어가 들어간 닉네임은 쓸 수 없어요" }
        return nil
    }

    /// `^[가-힣a-zA-Z0-9]+$`. 원본 정규식은 코드포인트 단위라 스칼라로 본다 —
    /// 문자소 단위로 비교하면 자모로 풀어 쓴 「가」(NFD)가 통과하는데 서버는 그런 닉네임을 거절한다.
    private static func matchesCharRule(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "가"..."힣", "a"..."z", "A"..."Z", "0"..."9": true
            default: false
            }
        }
    }
}
