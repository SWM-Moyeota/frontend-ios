import Foundation
import MoyeotaDomain

// 38 노쇼 기록·이의 신청과 35 제재 표시의 **판정 규칙** — 어떤 줄에 이의 신청 버튼이 생기고,
// 무엇을 글자로 만들며, 무엇을 말하지 않는가.
//
// ### 왜 화면에서 떼어 내는가 — 여기는 틀려도 화면에 보이지 않는다 ★
// 이 파일의 1급 규칙은 **「`objectionStatus == nil && !isVoided` 인 줄에만 이의 신청 버튼을
// 보여 준다」** 다(서버 Swagger 지시). 이걸 한 칸 잘못 잡은 화면은 **스크린샷으로 구분할 수
// 없다** — 버튼이 하나 더 보이는 것뿐이고, 틀렸다는 사실은 사용자가 그 버튼을 눌러
// **409 `NOT_NO_SHOW`·`ALREADY_OBJECTED`** 를 받는 순간에만 드러난다. 그 사용자는 「이의를 낼 수
// 있다」고 믿고 사유를 다 쓴 뒤에 거절당한다.
//
// 그래서 판정을 SwiftUI 도 UIKit 도 모르는 순수 함수로 빼고 `now` 를 **인자로** 받는다 —
// 어느 함수도 안에서 `Date()` 를 부르지 않는다(부르면 테스트가 경계를 고정할 수 없다). 기본값으로만 둔다.
// 같은 모듈의 `RideHistoryDisplay.swift`·`MyPageMenu.swift` 와 같은 자리·같은 이유다.
//
// ### 문구가 지켜야 하는 두 가지
// 1. **운영 처리를 약속하지 않는다.** 이의는 운영자가 사람 손으로 본다. 앱에는 결과 푸시가 없고
//    (서버에 그 알림이 없다) 사용자가 아는 길은 **이 화면을 다시 열어 `objectionStatus` 를 보는
//    것**뿐이다. 시한("며칠 안에")·알림("알려 드려요")·결과("풀어 드려요")를 적으면 그 순간
//    거짓이 된다 — 이 저장소는 그런 문구 19건을 들어낸 이력이 있다(`ProductClaimsTest` 주석).
// 2. **403·409 에 「다시 시도」류를 붙이지 않는다.** 다시 눌러도 같은 답이다
//    (`FinishFailureMessageTest` 가 세운 바). `NoShowObjectionFailure.isTerminal` 이 그 금지를
//    문구가 아니라 **버튼 상태**로도 옮긴다.
//
// ### 색은 여기서 정하지 않는다
// 상태별 **글자**만 만들고 `NoticeKind` 매핑은 화면이 한다. 이 파일을 SwiftUI 를 모르는
// 파일로 유지하기 위해서다(그래서 단위 테스트가 화면 없이 그냥 돈다).

// ─────────────────────────── 목록 화면의 고정 문구 ───────────────────────────

/// 노쇼가 한 건도 없을 때. **「없어요」까지가 사실이고 그 이상을 약속하지 않는다**
/// (`RIDE_HISTORY_EMPTY_TEXT` 와 같은 규칙). 「앞으로도 없게 해 주세요」 같은 훈계를 붙이지 않는다 —
/// 이 화면에 들어온 사람의 절반은 **자기가 노쇼로 찍혔는지 확인하러** 온 사람이다.
let NO_SHOW_EMPTY_TEXT = "노쇼로 기록된 적이 없어요"

/// 조회 실패. 사용자가 할 일은 「다시 시도」 하나뿐이라 사유를 가르지 않는다.
let NO_SHOW_ERROR_TEXT = "노쇼 기록을 불러오지 못했어요"

/// 목록 맨 위 안내 — **제재의 계산식을 그대로 적는다.**
///
/// 서버가 하는 일이 이것뿐이다: 노쇼 1건마다 **그 방 약속 시간부터** 24시간, 건수만큼 누적.
/// 「약속 시간부터」가 빠지면 사용자는 노쇼로 찍힌 시각(= 누군가 출발을 누른 때)부터 센다고 읽고,
/// 그러면 자기 제한이 언제 풀리는지 계산이 어긋난다.
let NO_SHOW_RULE_TEXT =
    "노쇼 1건마다 그 방 약속 시간부터 24시간 동안 방·예약을 만들거나 참여할 수 없어요"

/// 30일 만료. `NO_SHOW_RULE_TEXT` 와 **따로 둔다** — 제한(24시간)과 횟수 만료(30일)는 다른 수이고,
/// 한 문장에 넣으면 「30일 동안 못 쓴다」로 읽힌다.
let NO_SHOW_EXPIRY_TEXT = "약속 시간부터 30일이 지나면 횟수에서 하나씩 빠져요"

/// 카드의 두 시각 줄 앞에 붙는 이름. 둘을 섞으면 어느 쪽이 내 약속이었는지 알 수 없다.
let NO_SHOW_FIELD_MEETING = "약속 시간"
let NO_SHOW_FIELD_MARKED = "노쇼 시각"

/// 목록 끝에 붙는 한 줄 — **「전체」가 아니라는 사실.**
///
/// 서버가 최신 `NoShowRepositoryDefaults.HISTORY_LIMIT`건에서 자르고 커서도 개수 파라미터도 주지 않는다.
/// 그보다 많은 노쇼가 있는 사용자는 **오래된 건을 볼 길이 없는데**, 아무 말도 없으면 그 목록이
/// 전부라고 읽고 「왜 2년 전 노쇼가 안 보이나」를 묻게 된다. 「더 보기」 버튼을 달 수는 없다 —
/// 누를 수 없는 버튼이 된다.
///
/// **꽉 찼을 때만** 적는다(그 아래면 잘린 적이 없으므로 할 말이 없다). 꽉 찬 목록이 정확히 20건인지
/// 잘린 건지는 응답으로 구분할 수 없지만, 「최근 20건만 볼 수 있어요」는 **두 경우 모두 참**이다.
func noShowHistoryCapNotice(size: Int) -> String? {
    if size >= NoShowRepositoryDefaults.HISTORY_LIMIT {
        return "최근 \(NoShowRepositoryDefaults.HISTORY_LIMIT)건만 볼 수 있어요"
    }
    return nil
}

// ─────────────────────────── 줄 상태 ───────────────────────────

/// 노쇼 한 줄이 지금 어떤 상태인가. **이 enum 하나가 배지·부연·버튼을 전부 결정한다.**
///
/// 다섯 갈래인 이유는 서버가 사실을 **두 필드로** 주기 때문이다(`isVoided` 와 `objectionStatus`).
/// 둘을 화면에서 각자 보면 「무효인데 이의 검토 중」처럼 서로 어긋나는 조합이 그려진다.
enum NoShowRowState: CaseIterable, Sendable {
    /// 아직 이의를 내지 않은 **살아 있는** 노쇼 — `objectionStatus == nil && !isVoided`.
    /// **이의 신청 버튼이 생기는 유일한 상태**이고, 서버가 201 을 주는 조건과 같다.
    case open

    /// 이의를 냈고 운영자가 보기 전 — `pending`. 더 낼 수는 없다(방마다 한 번).
    case pending

    /// 이의가 인정됐다 — `accepted`. 보통 서버가 같은 응답에서 `isVoided` 도 true 로 주므로
    /// 이 상태는 실제로는 거의 오지 않는다(`noShowRowState` 의 우선순위 설명 참고).
    case accepted

    /// 이의가 받아들여지지 않았다 — `rejected`. 노쇼는 그대로 남고 다시 낼 길은 없다.
    case rejected

    /// 무효 — `isVoided`. 이 노쇼는 횟수에 들어가지 않는다.
    case voided
}

extension NoShowRowState {
    /// 이의 신청 버튼을 그려도 되는가. **서버가 받아 주는 조건과 한 글자도 다르지 않아야 한다.**
    var allowsObjection: Bool { self == .open }
}

/// 두 서버 필드 → 한 줄 상태.
///
/// ### `isVoided` 가 `objectionStatus` 를 이긴다 ★
/// 「이 노쇼가 횟수에 들어가는가」를 정하는 필드는 **`isVoided` 하나**다. 이의가 인정되면 서버가
/// 둘을 함께 바꾸지만(accepted + voided), 운영자가 이의 없이 무효로 돌리는 길도 있어
/// `isVoided && objectionStatus == nil` 이 올 수 있다. 그때 `objectionStatus` 를 먼저 보면
/// **무효가 된 노쇼에 이의 신청 버튼을 달게 된다** — 서버는 409 `NOT_NO_SHOW` 로 거절한다
/// (「노쇼가 아니거나 이미 무효」가 같은 코드다).
///
/// 거꾸로 `accepted` 인데 `isVoided` 가 false 인 조합은 서버가 만들지 않는다. 와도
/// `NoShowRowState.accepted` 로 떨어뜨려 **「무효가 됐어요」라고 말하지 않는다** — 그 말의 근거는
/// `isVoided` 뿐이고, 없는 근거로 단정하면 그게 거짓 문구다.
///
/// 모르는 `objectionStatus` 값은 애초에 여기까지 오지 않는다 — 데이터 계층이 nil 로 떨어뜨리고
/// **pending 으로 추측하지 않는다**(도메인 계약). 그래서 이 함수의 nil 은 「안 냈다」가 아니라
/// 「안 냈거나 서버가 새 값을 보냈다」일 수 있는데, 둘 다 **버튼을 보여도 되는** 쪽이다(서버가
/// 최종 판정을 한다 — 이미 냈으면 409 `ALREADY_OBJECTED` 가 그 사실을 알려 주고, 화면은 그 줄을
/// `NoShowRowState.pending` 으로 고친다).
func noShowRowState(isVoided: Bool, objectionStatus: ObjectionStatus?) -> NoShowRowState {
    if isVoided { return .voided }
    switch objectionStatus {
    case nil: return .open
    case .pending: return .pending
    case .accepted: return .accepted
    case .rejected: return .rejected
    }
}

/// 상태 배지 글자. **`NoShowRowState.open` 은 nil 이다** — 배지 자리는 「이의가 어떻게 됐는가」를
/// 말하는 자리이고, 아직 이의를 내지 않은 줄에는 말할 것이 없다. 거기에 「노쇼」 배지를 달면
/// 화면 제목(노쇼 기록)을 줄마다 되풀이하는 장식이 된다 — 그 줄을 다른 줄과 가르는 것은
/// **이의 신청 버튼**이다.
func noShowBadgeText(state: NoShowRowState) -> String? {
    switch state {
    case .open: nil
    case .pending: "이의 검토 중"
    case .accepted: "이의 인정됨"
    case .rejected: "이의 거절됨"
    case .voided: "무효"
    }
}

/// 배지 아래 한 줄. **상태마다 사용자가 다음에 무엇을 할 수 있는지(또는 없는지)를 적는다.**
///
/// - `pending` — 여기가 이 화면에서 가장 조심할 자리다. 결과 푸시가 **없으므로** 「알려 드려요」를
///   쓸 수 없고, 운영 시한도 약속할 수 없다. 그래서 사용자가 **실제로 할 수 있는 일**만 적는다:
///   이 화면을 다시 열어 보는 것.
/// - `voided` — 횟수에서 빠졌다는 **사실**까지만. 「제한이 풀렸어요」는 적지 않는다 — 다른 노쇼가
///   남아 있으면 제한은 그대로다. 지금 제한 여부는 35 의 배너가 서버 `restrictedUntil` 로 말한다.
/// - `rejected` — 다시 낼 길이 없다는 것을 말해 줘야 한다. 그걸 빼면 사용자는 같은 방의 버튼을
///   계속 찾는다.
/// - `open` — nil. 버튼이 바로 아래에 있어 설명이 필요 없다.
func noShowNoteText(state: NoShowRowState) -> String? {
    switch state {
    case .open: nil
    case .pending: "운영자가 확인한 결과는 이 화면에서 볼 수 있어요"
    case .accepted: "이의가 인정됐어요"
    case .rejected: "이 방에는 다시 이의를 낼 수 없어요"
    case .voided: "이 노쇼는 횟수에 들어가지 않아요"
    }
}

// ─────────────────────────── 카드 한 장 ───────────────────────────

/// 카드 한 장이 그릴 값. **없는 값은 nil 이고, nil 인 자리는 그리지 않는다**
/// (`RideHistoryItem` 과 같은 규칙 — 「날짜 모름」 같은 자리값을 두지 않는다).
struct NoShowItem: Equatable, Sendable {
    var partyId: Int64
    /// `출발 → 도착`. 둘 중 하나라도 없으면 있는 쪽만, 둘 다 없으면 nil.
    var routeLabel: String?
    /// 약속 시각 표기. 파싱할 수 없으면 nil — 틀린 날짜보다 없는 편이 낫다.
    var meetingLabel: String?
    /// 노쇼로 찍힌 시각 표기. 같은 규칙.
    var markedLabel: String?
    var state: NoShowRowState
    /// 상태 배지 글자. `NoShowRowState.open` 이면 nil(배지를 그리지 않는다).
    var badgeText: String?
    /// 배지 아래 한 줄. 없으면 nil.
    var note: String?

    init(
        partyId: Int64,
        routeLabel: String?,
        meetingLabel: String?,
        markedLabel: String?,
        state: NoShowRowState,
        badgeText: String?,
        note: String?
    ) {
        self.partyId = partyId
        self.routeLabel = routeLabel
        self.meetingLabel = meetingLabel
        self.markedLabel = markedLabel
        self.state = state
        self.badgeText = badgeText
        self.note = note
    }

    /// 이 줄에 이의 신청 버튼을 그리는가. 화면이 다시 판정하지 않게 여기서 한 번만 정한다.
    var allowsObjection: Bool { state.allowsObjection }
}

extension NoShowRecord {
    /// 기록 한 건 → 카드 한 장.
    ///
    /// 시각 표기는 **34 지난 탑승 기록과 같은 함수**를 쓴다(`rideHistoryDateLabel`) — 두 기록 화면의
    /// 날짜가 서로 다른 모양이면 사용자는 같은 앱의 다른 화면에서 같은 시각을 다르게 읽는다. 서버가
    /// UTC ISO-8601 로 주므로 **문자열을 자르면 KST 오후 4시가 오전 7시로 보인다**(채팅에서 실제로 났던
    /// 결함) — 기기 시간대로 바꿔 쓰고, 파싱할 수 없으면 nil 로 그 줄을 비운다.
    func toNoShowItem(now: Date = Date(), zone: TimeZone = .current) -> NoShowItem {
        let state = noShowRowState(isVoided: isVoided, objectionStatus: objectionStatus)
        return NoShowItem(
            partyId: partyId,
            routeLabel: noShowRouteLabel(departure: departure, destination: destination),
            meetingLabel: meetingAt.flatMap { rideHistoryDateLabel(isoTime: $0, now: now, zone: zone) },
            markedLabel: noShowAt.flatMap { rideHistoryDateLabel(isoTime: $0, now: now, zone: zone) },
            state: state,
            badgeText: noShowBadgeText(state: state),
            note: noShowNoteText(state: state)
        )
    }
}

/// `출발 → 도착`. 한쪽이 비면 있는 쪽만, 둘 다 비면 nil 이다(빈 화살표를 그리지 않는다).
private func noShowRouteLabel(departure: String, destination: String) -> String? {
    if !departure.isBlank && !destination.isBlank { return "\(departure) → \(destination)" }
    if !departure.isBlank { return departure }
    if !destination.isBlank { return destination }
    return nil
}

// ─────────────────────────── 35 마이페이지의 제재 표시 ───────────────────────────

/// 제재 배너를 어떤 톤으로 그릴지. 색 매핑은 화면이 한다(이 파일은 SwiftUI 를 모른다).
enum NoShowSanctionKind: Sendable {
    /// 지금 방을 만들거나 참여할 수 없다 — 서버 `restrictedUntil` 이 미래다.
    case restricted

    /// 제한은 없지만 노쇼 횟수가 남아 있다 — 다음 노쇼에서 제한이 길어진다.
    case counted
}

struct NoShowSanction: Equatable, Sendable {
    var kind: NoShowSanctionKind
    var text: String

    init(kind: NoShowSanctionKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// 35 프로필 카드 아래 배너 — **「왜 막혔나」와 「언제까지」를 말하는 유일한 자리.**
///
/// 이게 없던 동안 제재당한 사용자는 방 만들기·합류가 403 `NO_SHOW_RESTRICTED` 로 막히는 것만 보고
/// **이유도 기한도 알 수 없었다.** 그래서 마이페이지에 둔다 — 막힌 사람이 「내 계정에 무슨 문제가
/// 있나」를 찾는 자리다.
///
/// ### 판정
/// | `noShowCount` | `restrictedUntil` | 결과 |
/// |---|---|---|
/// | 무엇이든 | 미래 | `NoShowSanctionKind.restricted` |
/// | 무엇이든 | 파싱 불가(비어 있지 않음) | `NoShowSanctionKind.restricted` — 기한 없이 |
/// | 1 이상 | nil · 과거 | `NoShowSanctionKind.counted` |
/// | 0 | nil · 과거 | **nil — 배너를 그리지 않는다** |
///
/// **`restrictedUntil` 을 시각으로 다시 재는 이유:** 서버는 제한이 없으면 null 을 주지만, 응답은
/// 몇 분 전 값일 수 있고 24시간짜리 제한은 그 사이에 끝난다. nil 여부만 보면 **이미 풀린 제한을
/// 「지금 막혀 있어요」로** 보여 주고, 사용자는 실제로는 되는 방 만들기를 시도조차 하지 않는다.
///
/// **파싱 불가를 제한으로 보는 이유:** 값이 비어 있지 않다는 건 서버가 제한을 걸었다는 뜻이다.
/// 기한만 모르니 기한을 적지 않을 뿐, 「제한 없음」으로 접으면 막힌 이유를 설명할 유일한 배너가
/// 사라진다. 틀린 시각을 쓰지 않는 것과 제한 자체를 숨기는 것은 다른 문제다.
///
/// 횟수를 **1 이상일 때만** 문구에 넣는다 — 「노쇼 0회로 제한됐어요」는 그 자체로 모순이다.
func noShowSanction(
    noShowCount: Int,
    restrictedUntil: String?,
    now: Date = Date(),
    zone: TimeZone = .current
) -> NoShowSanction? {
    let raw = restrictedUntil.flatMap { $0.isBlank ? nil : $0 }
    let until = raw.flatMap { noShowRestrictionLabel(isoTime: $0, now: now, zone: zone) }
    let restricted = raw != nil && (until == nil || isNoShowRestricted(restrictedUntil: raw, now: now))
    let countPrefix = noShowCount > 0 ? "노쇼 \(noShowCount)건으로 " : ""
    if restricted, let until {
        return NoShowSanction(
            kind: .restricted,
            text: "\(countPrefix)\(until)까지 방·예약을 만들거나 참여할 수 없어요. "
                + "노쇼가 아니라고 생각하면 「노쇼 기록」에서 이의를 낼 수 있어요"
        )
    }
    // 기한을 모를 때. 「지금은」이 중요하다 — 언제 풀리는지 모르면서 기한을 암시하지 않는다.
    if restricted {
        return NoShowSanction(
            kind: .restricted,
            text: "\(countPrefix)지금은 방·예약을 만들거나 참여할 수 없어요. "
                + "노쇼가 아니라고 생각하면 「노쇼 기록」에서 이의를 낼 수 있어요"
        )
    }
    if noShowCount > 0 {
        return NoShowSanction(
            kind: .counted,
            text: "노쇼 \(noShowCount)건이 기록돼 있어요. \(NO_SHOW_EXPIRY_TEXT)"
        )
    }
    return nil
}

/// 제한이 **아직** 걸려 있는가. 파싱할 수 없는 값은 false — 판정은 `noShowSanction` 이 묶어서 한다.
///
/// 원본 `Instant.isAfter` 처럼 초와 나노초로 비교한다. `Date` 는 초를 `Double` 로 들고 있어
/// 서버 값(나노초까지)과 그대로 비교하면 경계에서 어긋날 수 있다(`RideHistoryInstant` 주석).
func isNoShowRestricted(restrictedUntil: String?, now: Date) -> Bool {
    guard let raw = restrictedUntil, !raw.isBlank, let at = raw.toInstantOrNull() else { return false }
    let seconds = now.timeIntervalSince1970
    let nowSecond = Int64(seconds.rounded(.down))
    let nowNano = min(Int(((seconds - Double(nowSecond)) * 1_000_000_000).rounded()), 999_999_999)
    return at.epochSecond > nowSecond || (at.epochSecond == nowSecond && at.nano > nowNano)
}

/// 제한이 풀리는 시각 표기 — **시·분을 절대 생략하지 않는다.**
///
/// `rideHistoryDateLabel` 를 쓰지 않는 이유가 이것뿐이다: 그쪽은 **다른 해**의 기록에서 시각을 떼고
/// 날짜만 남긴다(몇 달 전 탑승에서 분 단위는 줄만 길어진다). 여기는 거꾸로다 — 24시간짜리 제한에서
/// 사용자가 알아야 하는 것은 **몇 시에 풀리는가**이고, 연말에 걸린 제한(12월 31일 → 1월 1일)에서
/// 시각이 사라지면 그날 하루 종일 못 쓰는 것처럼 읽힌다.
///
/// 해는 다를 때만 붙인다. 파싱할 수 없으면 nil — 호출부가 기한 없는 문구로 떨어진다.
func noShowRestrictionLabel(isoTime: String, now: Date = Date(), zone: TimeZone = .current) -> String? {
    guard let at = isoTime.toInstantOrNull()?.local(zone: zone) else { return nil }
    let meridiem = at.hour < 12 ? "오전" : "오후"
    // 0시·12시가 12 가 되어야 한다 — `hour % 12` 만 쓰면 자정이 「오전 0:05」로 찍힌다.
    let hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12
    let clock = "\(meridiem) \(hour12):\(String(format: "%02d", at.minute))"
    let date = "\(at.month)월 \(at.day)일"
    let thisYear = RideHistoryInstant(
        epochSecond: Int64(now.timeIntervalSince1970.rounded(.down)),
        nano: 0
    ).local(zone: zone).year
    return at.year == thisYear ? "\(date) \(clock)" : "\(at.year)년 \(date) \(clock)"
}

// ─────────────────────────── 이의 신청 입력 ───────────────────────────

/// 서버 한도 — `reason` 은 **앞뒤 공백을 떼고 1~500자**다. 벗어나면 400 `INVALID_REQUEST` 이고,
/// 그 응답 문구로는 사용자가 무엇을 고쳐야 하는지 알 수 없다. 그래서 앱이 **보낼 수 없게** 만든다.
///
/// 숫자를 여기 적지 않고 도메인 상수를 끌어온다 — 서버 `@Size(max = …)` 와 같은 값을 아는 곳이
/// 하나여야 한다(24 채팅이 `ChatReportReason.MAX_DESCRIPTION_LENGTH` 를 그렇게 쓴다). 서버가 한도를
/// 바꾸면 도메인 한 줄만 고치면 카운터·버튼 잠금·안내가 함께 따라온다.
let OBJECTION_REASON_MAX = NoShowObjectionException.MAX_REASON_LENGTH

/// 입력창이 **받아 주는** 글자 수 — 서버 한도의 2배.
///
/// 한도대로 자르면 「넘었다」를 말해 줄 기회가 사라진다(500자에서 입력이 멈추는 칸은 고장으로
/// 읽힌다). 한도는 카운터가 말하게 두고, 이 값은 붙여넣기 폭주만 막는다 — 24 채팅의 신고 상세
/// 입력창이 같은 판단을 했다.
let OBJECTION_REASON_HARD_LIMIT = OBJECTION_REASON_MAX * 2

/// 한 입력 상태에서 **파생되는 것 전부** — 길이를 두 군데서 재면 카운터와 버튼의 기준이 갈린다.
struct ObjectionReasonUi: Equatable, Sendable {
    /// 「12/500자」. **항상 보인다** — 아래 `objectionReasonUi` 주석 참고.
    let counter: String
    let overLimit: Bool
    let submitEnabled: Bool
}

/// 「보내기」를 **누를 수 있는가**와 카운터를 함께 뽑는다.
///
/// ### 길이는 **trim 한 뒤** 센다 ★
/// 서버가 `reason.trim()` 을 검사하므로, 공백만 쓴 글은 서버에서 0자다. trim 전 길이로 재면
/// 스페이스 세 개를 쓴 사용자에게 **버튼이 열리고** 400 이 돌아온다 — 앱이 막을 수 있었던 거절이다.
///
/// 길이는 **UTF-16 단위**다 — 원본 `String.length` 와 서버 `@Size` 가 그렇게 센다(24 채팅의
/// `chatReportSubmitUi` 와 같다). 문자소로 세면 이모지 하나가 1자로 보여 서버의 501자가 앱에서
/// 500자로 통과한다.
///
/// ### 카운터를 **항상** 그리는 이유
/// 채팅 입력창은 한도 100자 앞에서야 카운터를 띄운다(말풍선 높이를 상시로 빼앗지 않으려고).
/// 여기는 반대다: 이 시트에는 입력칸 하나뿐이고, **버튼이 처음부터 잠겨 있다.** 잠긴 이유를
/// 말해 주는 것이 카운터의 「0/500자」다 — 없으면 사용자는 왜 안 눌리는지 모른 채 버튼만 누른다.
///
/// 넘겼을 때 **몇 자를 줄여야 하는지**까지 적는다. 「500자를 넘었어요」만 적으면 517자를 쓴 사람이
/// 얼마를 지워야 하는지 직접 세야 한다.
func objectionReasonUi(reason: String, submitting: Bool = false) -> ObjectionReasonUi {
    let length = reason.trim().utf16.count
    let overLimit = length > OBJECTION_REASON_MAX
    return ObjectionReasonUi(
        counter: overLimit
            ? "\(length)/\(OBJECTION_REASON_MAX)자 — \(length - OBJECTION_REASON_MAX)자 줄여야 보낼 수 있어요"
            : "\(length)/\(OBJECTION_REASON_MAX)자",
        overLimit: overLimit,
        submitEnabled: !submitting && (1...OBJECTION_REASON_MAX).contains(length)
    )
}

// ─────────────────────────── 이의 신청 시트의 문구 ───────────────────────────

/// 시트 제목. 「이의 신청」이라는 행위 이름보다 **무엇을 쓰는 칸인지**를 먼저 말한다.
let OBJECTION_SHEET_TITLE = "왜 노쇼가 아닌지 알려 주세요"

/// 시트 안내 — **이의가 처리되는 방식에 대해 앱이 말할 수 있는 전부.**
///
/// 세 가지를 **의도적으로 빼** 뒀다: 처리 시한(운영 약속이 없다) · 결과 알림(푸시가 없다) ·
/// 결과 예측(운영자가 판단한다). 대신 서버 계약으로 참인 둘만 적는다 — 방마다 한 번뿐이라는 것과,
/// 결과를 확인하는 길이 이 화면이라는 것.
let OBJECTION_SHEET_NOTICE =
    "방마다 한 번만 낼 수 있어요. 운영자가 확인한 결과는 이 화면에서 볼 수 있어요"

let OBJECTION_INPUT_PLACEHOLDER = "그날 어떤 상황이었는지 적어 주세요"

let OBJECTION_SUBMIT_LABEL = "이의 보내기"

let OBJECTION_SUBMITTING_LABEL = "보내는 중"

/// 201 을 받은 뒤 목록 위에 뜨는 안내.
///
/// **「접수됐습니다」로 끝내지 않는다** — 그 말을 들은 사용자는 알림을 기다린다. 결과를 보는
/// 길(이 화면)을 같은 문장에서 알려 줘야 한다. 「인정되면 제한이 풀려요」는 쓰지 않는다:
/// 인정 여부는 운영자가 정하고, 앱은 그걸 약속할 수 없다.
let OBJECTION_SENT_TEXT = "이의를 보냈어요. 운영자가 확인한 결과는 이 화면에서 볼 수 있어요"

// ─────────────────────────── 이의 신청 실패 ───────────────────────────

/// 이의 신청이 거절된 사유. **서버 코드 문자열도 HTTP 상태도 여기까지 오지 않는다** —
/// 도메인 예외의 `is…` 프로퍼티를 Route 가 이 enum 으로 한 번 접는다
/// (`NoShowRecordsRoute.swift` 의 `toNoShowObjectionFailure`).
///
/// 그렇게 두는 이유가 둘 있다. (1) 문구 테스트가 예외 생성자에 묶이지 않는다 — 서버가 코드를
/// 늘리거나 예외 모양이 바뀌어도 문구는 그대로 고정된다. (2) HTTP 상태로 사유를 고르는 길을
/// **타입으로** 막는다. 이 엔드포인트의 409 는 두 가지 뜻(`NOT_NO_SHOW`·`ALREADY_OBJECTED`)이라
/// 상태로 고르면 반드시 절반이 틀린 말이 된다.
enum NoShowObjectionFailure: CaseIterable, Sendable {
    /// 400 `INVALID_REQUEST` — 사유가 비었거나 500자를 넘었다. **이 화면에서 고칠 수 있는 유일한
    /// 실패**라 다른 넷과 성격이 다르다(`isTerminal` 가 그 차이를 든다).
    ///
    /// `objectionReasonUi` 가 버튼을 잠그므로 평소에는 오지 않는다. 그래도 분기를 두는 이유는 서버가
    /// 이 코드를 **범용**으로 쓰기 때문이다 — 본문이 깨졌거나 필드 이름이 틀려도 같은 400 이다.
    /// 즉 입력이 멀쩡한데 이 문구가 보이면 **앱 버그**이고, 그때도 사용자에게는 고칠 수 있는 쪽
    /// (글자 수)을 말해 주는 것이 할 수 있는 최선이다.
    case invalidReason

    /// 409 `NOT_NO_SHOW` — 이 방에서 노쇼가 아니거나 **이미 무효**다(서버가 둘을 같은 코드로 준다).
    case notNoShow

    /// 409 `ALREADY_OBJECTED` — 이미 냈다. 방마다 한 번뿐이다.
    case alreadyObjected

    /// 403 `NOT_PARTY_MEMBER` — 그 방의 참여자가 아니다.
    case notMember

    /// 404 `PARTY_NOT_FOUND` — 방이 사라졌다.
    case partyNotFound

    /// 코드를 모르는 실패와 네트워크 실패. **서버가 코드를 늘려도 앱이 지어내지 않는다.**
    case unknown

    /// **같은 글을 그대로 다시 보내면 같은 답인가.**
    ///
    /// 403·409·404 가 전부 그렇다 — 서버가 방의 사실을 보고 거절한 것이라 이 화면에서 바꿀 수 있는
    /// 것이 없다. 그래서 문구에 「다시 시도」류를 넣지 않는 것으로 끝내지 않고
    /// (`FinishFailureMessageTest` 의 바) **보내기 버튼을 잠근다** — 문구는 읽지 않아도 버튼은 본다.
    /// 그 넷은 「내 목록이 낡았다」는 신호이기도 해서, Route 가 이 플래그로 **목록 재조회**까지 건다.
    ///
    /// 두 가지만 false 다. `unknown` 에는 연결이 끊긴 경우가 섞여 있어 다시 보내면 통할 수 있고,
    /// `invalidReason` 은 **글을 고치면 통한다** — 여기를 true 로 두면 사유를 줄여도 보낼 수 없는
    /// 시트에 갇힌다(쓴 글을 버리고 다시 열어야 한다).
    var isTerminal: Bool { self != .unknown && self != .invalidReason }
}

/// 사유를 가릴 수 없는 실패의 일반 문구 — 네트워크 실패와 **모르는 코드**가 여기로 떨어진다.
let OBJECTION_FAILED_MESSAGE = "이의를 보내지 못했어요"

/// 이의 신청 실패 → 사용자 문구.
///
/// | 사유 | 서버 코드(HTTP) | 사용자가 아는 것 |
/// |---|---|---|
/// | 사유가 비었거나 길다 | `INVALID_REQUEST` (400) | **글을 고치면 보낼 수 있다** |
/// | 노쇼가 아니다·이미 무효 | `NOT_NO_SHOW` (409) | 이 방에는 이의를 낼 일이 없다 |
/// | 이미 냈다 | `ALREADY_OBJECTED` (409) | 한 번만 낼 수 있다 |
/// | 참여자가 아니다 | `NOT_PARTY_MEMBER` (403) | 이 방에는 낼 수 없다 |
/// | 방 없음 | `PARTY_NOT_FOUND` (404) | 사라진 방이다 |
/// | 그 밖·네트워크 | 코드 없음 | `OBJECTION_FAILED_MESSAGE` |
///
/// **「홈으로 돌아가 주세요」류를 붙이지 않는다.** 21 매칭의 같은 코드들은 진행 중인 방을 전제로
/// 그렇게 안내하지만(돌아갈 방이 있다), 여기는 **끝난 방의 기록**이다 — 홈에 가도 할 일이 없다.
/// 할 수 있는 일이 없을 때는 **없다고만** 말한다. 없는 길을 권하면 그게 거짓이다.
func noShowObjectionFailureMessage(failure: NoShowObjectionFailure) -> String {
    switch failure {
    // 유일하게 **행동을 권하는** 가지다 — 400 이고, 글자 수를 맞추면 실제로 통과한다.
    case .invalidReason:
        "이의 사유는 1~\(OBJECTION_REASON_MAX)자로 적어야 보낼 수 있어요"
    case .notNoShow:
        "이 방에서는 노쇼로 기록돼 있지 않아요. 이미 무효가 된 기록일 수 있어요"
    case .alreadyObjected:
        "이 방에는 이미 이의를 냈어요. 방마다 한 번만 낼 수 있어요"
    case .notMember:
        "이 방의 참여자가 아니라 이의를 낼 수 없어요"
    case .partyNotFound:
        "이미 사라진 방이에요. 이 방에는 이의를 낼 수 없어요"
    case .unknown:
        OBJECTION_FAILED_MESSAGE
    }
}
