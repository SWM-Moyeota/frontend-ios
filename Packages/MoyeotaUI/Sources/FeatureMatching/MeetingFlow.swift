import Foundation
import MoyeotaDomain
import PresentationCore

// 21 매칭 대기의 **약속 확정 → 출발지 도착 → 출발** 판정과 문구를 모아 둔다.
//
// ### 왜 화면에서 떼어 내는가
// 이 파일의 판정은 **전부 시계에 달려 있다** — 「약속 10분 전부터」·「약속 시간 뒤에만」. 경계를
// 한 칸 잘못 잡아도 스크린샷에는 아무것도 보이지 않는다: 버튼이 10분 전에 떠야 하는데 9분 전에
// 뜨는 화면과 올바른 화면은 눈으로 구분할 수 없고, 그 차이는 **서버 409 `ARRIVAL_NOT_OPEN`** 으로만
// 드러난다. 그래서 판정을 SwiftUI 를 모르는 순수 함수로 빼고 `now` 를 **인자로** 받는다 —
// 어느 함수도 `Date()` 를 안에서 부르지 않는다(부르면 테스트가 경계를 고정할 수 없다).
//
// 34 지난 탑승 기록의 `RideHistoryDisplay.swift` 와 같은 자리·같은 이유다: 화면을 모르는 파일로
// 두면 단위 테스트가 그냥 돈다.
//
// ### 서버가 최종 판정이다
// 여기 있는 게이트는 **누를 수 없는 버튼을 만들지 않기 위한 것**이지 서버 검사의 사본이 아니다.
// 특히 **출발지 100m 반경은 앱이 재지 않는다** — 서버가 PostGIS 로 재고 400
// `TOO_FAR_FROM_DEPARTURE` 로 답한다. 앱이 같은 거리를 다시 재면 두 개의 진실이 생기고(좌표 정확도가
// 수십 m 씩 흔들린다) **서버는 받아 주는데 앱이 막는** 경우가 생긴다. 거리는 묻지 말고 보내고,
// 거절당하면 서버가 말한 사유를 그대로 보여 준다(`arriveFailureMessage`).

// ─────────────────────────── 약속 시간 프리셋 ───────────────────────────

/// 「약속 시간 정하기」가 내놓는 **유일한 선택지** — 지금부터 10·20·30·45·60분 뒤.
///
/// 자유 입력(시간 피커)을 두지 않는 이유는 취향이 아니라 **계약**이다. 서버는 약속 시간을
/// **지금부터 1시간 안**으로만 받고(지난 시각도 불가), 벗어나면 400 `INVALID_MEETING_TIME` 이다.
/// 피커를 주면 사용자가 그 400 을 **스스로 만들 수 있게** 되고, 거절당한 뒤에 할 수 있는 일은
/// 「더 가까운 시간을 고르는 것」뿐이다 — 애초에 고를 수 없게 하는 UI 가 낫다.
///
/// 그래도 `confirmFailureMessage` 에 `INVALID_MEETING_TIME` 분기를 남긴다. 기기 시계가 서버보다
/// 앞서 있으면(스큐) 60분 프리셋이 서버 기준 1시간을 **넘길 수 있다** — 프리셋은 그 400 을
/// 사용자의 실수에서 지우는 것이지 물리적으로 없애지는 못한다.
let MEETING_PRESET_MINUTES = [10, 20, 30, 45, 60]

/// 프리셋 하나가 가리키는 실제 시각 — **분 단위로 내림**한다.
///
/// 내림하는 이유가 둘이다.
/// 1. **표시와 실제가 어긋나지 않는다.** 15:13:47 에 「10분 뒤」를 눌러 15:23:47 을 보내면 화면은
///    「오후 3:23」이라 적으면서 실제 경계는 3:23:47 이다. 약속 시간을 1초 단위로 다투는 자리가
///    아니고(출발 버튼이 그때 열린다), 보이는 시각이 곧 보낸 시각인 편이 설명하기 쉽다.
/// 2. **60분 프리셋의 여유를 벌어 준다.** 서버는 「지금부터 1시간 안」을 보는데, 앱의 `now` 와
///    서버의 `now` 사이에는 왕복 시간과 시계 스큐가 있다. 내림으로 최대 59초를 돌려받는다.
///
/// 내림해도 **지난 시각이 될 수 없다** — 최소 프리셋이 10분이라 어떤 초를 깎아도 지금보다 뒤다.
func meetingPresetAt(now: Date, minutes: Int) -> Date {
    let shifted = now.timeIntervalSince1970 + TimeInterval(minutes * 60)
    return Date(timeIntervalSince1970: (shifted / 60).rounded(.down) * 60)
}

/// 서버에 보낼 ISO-8601 문자열 — `2026-11-03T08:30:00Z`.
///
/// 앱은 시각을 **문자열 그대로** 다룬다(`Ride.departureAt`·`RideRecord`·`ChatMessage` 와 같은 관례):
/// 보내는 자리에서만 만들고 읽는 자리에서만 파싱한다.
///
/// `Date.ISO8601FormatStyle` 기본값은 UTC `Z` 표기이고 **초를 늘 적는다** — `meetingPresetAt` 이 분으로
/// 내림하므로 실제로 나가는 값은 `2026-11-03T08:30:00Z` 다. (원본 주석은 `Instant.toString` 이 초가 0 이면
/// `:00` 을 생략한다고 적었지만 사실이 아니다 — `ISO_INSTANT` 는 초를 늘 적고, 원본 테스트도 `:00` 을
/// 기대한다.) 서버(Jackson `Instant`)는 어느 쪽이든 같게 읽는다. 시간대·오프셋 표기를 따로 정하지 않도록
/// 기본 형식을 그대로 쓴다 — 사람이 읽을 값이 아니다.
func meetingPresetIso(now: Date, minutes: Int) -> String {
    meetingPresetAt(now: now, minutes: minutes).formatted(.iso8601)
}

/// 확정 다이얼로그가 들고 있는 선택 — 고른 프리셋(`minutes`)과 **그때 만든 약속 시각**(`departureAt`).
///
/// 둘을 함께 드는 이유가 이 타입의 전부다. `minutes` 는 어느 칩이 눌려 있는지 보여 주는 데만 쓰고,
/// **서버로 가는 값은 `departureAt`** 이다. 분만 들고 다니면 다이얼로그 제목과 실제 요청이 시계를
/// 따로 읽어, 그 사이 분이 바뀌면 **사용자가 동의한 시각과 확정되는 시각이 갈린다.**
struct ConfirmingPreset: Equatable, Sendable {
    let minutes: Int
    let departureAt: String
}

// ─────────────────────────── 단계 판정 ───────────────────────────

/// 21 이 지금 **어느 단계**인가 — 리더가 정한 화면 상태표를 그대로 타입으로 옮긴 것이다.
///
/// 불리언 여럿으로 흩어 두지 않는 이유: 「확정됐고 · 도착 창이 열렸고 · 내가 아직 도착하지 않았고 ·
/// 약속 시간은 지나지 않았다」 같은 조합을 화면이 매번 다시 세우면 **조합 하나를 빠뜨려도 컴파일이
/// 통과한다**. 하나의 enum 으로 모으면 `switch` 가 빠진 가지를 잡아 주고, 상태표 전체를 테스트
/// 하나로 고정할 수 있다(`meetingStage`).
enum MeetingStage: Sendable {
    /// 모집 중 — 지금까지와 같다. 약속·도착·출발이 끼어들지 않는다
    case recruiting

    /// 정원이 찼고 · 아직 확정 전이고 · **내가 약속 시간을 정할 수 있다**(방장 · 실시간 방 · 2명 이상).
    /// 프리셋 버튼을 보여 준다.
    case confirmByMe

    /// 정원이 찼고 · 아직 확정 전이고 · 내가 방장이 아니다 — **방장이 정한다**고 알린다
    case confirmByHost

    /// 정원은 찼지만 **이 방에서는 약속 시간을 정할 수 없다** — 실시간 방이 아니거나 멤버가 2명 미만이다.
    ///
    /// 서버가 `NOT_REALTIME_PARTY`·`NOT_ENOUGH_MEMBERS` 로 거절하는 자리라 프리셋을 띄우면 누를 수
    /// 없는 버튼이 된다. 그래서 **약속 흐름이 붙기 전의 화면 그대로** 둔다 — 방장은 「합승 완료」로
    /// 끝내고, 비방장은 그 안내문을 읽는다.
    case finishOnly

    /// 확정됐고 · 내가 아직 도착하지 않았고 · **도착 창이 아직 안 열렸다**(약속 10분 전 이전).
    ///
    /// `departureAt` 을 파싱할 수 없을 때도 여기로 온다 — 창이 열렸는지 **알 수 없으면 열지 않는다**.
    /// 열어 두고 409 `ARRIVAL_NOT_OPEN` 을 맞게 하는 것보다 낫다.
    case confirmedWaiting

    /// 확정됐고 · 약속 **10분 전부터** · 내가 미도착 — 「출발지 도착했어요」
    case arriveOpen

    /// 확정됐고 · 내가 도착했고 · 아직 약속 시간 전 — 기다리는 상태(누를 것이 없다)
    case arrivedWaiting

    /// 확정됐고 · 내가 도착했고 · 약속 시간이 지났다 — 「출발」
    case departOpen

    /// 방이 닫혔다(FINISHED·CANCELED). Route 가 곧 화면을 떠나지만 그 사이 한 프레임을 그린다
    case closed
}

/// 도착 창이 열리는 시각 — 약속 시간의 **10분 전**. 서버 `arrive` 의 `ARRIVAL_NOT_OPEN` 경계다.
///
/// 상수로 빼 둔 이유는 문구가 같은 숫자를 말하기 때문이다(`ARRIVE_NOT_OPEN_NOTICE` ·
/// `arriveFailureMessage`) — 한쪽만 고치면 화면이 서버와 다른 약속을 하게 된다.
let ARRIVAL_OPENS_MINUTES_BEFORE: Int64 = 10

/// 화면 상태표의 **단일 판정**. 위에서부터 읽는다 — 앞의 가지가 뒤를 가린다.
///
/// | 조건 | 결과 |
/// |---|---|
/// | 방이 닫혔다 | `MeetingStage.closed` |
/// | 확정됐다 · 내가 도착 · `now ≥ 약속 시간` | `MeetingStage.departOpen` |
/// | 확정됐다 · 내가 도착 | `MeetingStage.arrivedWaiting` |
/// | 확정됐다 · `now ≥ 약속 − 10분` | `MeetingStage.arriveOpen` |
/// | 확정됐다 | `MeetingStage.confirmedWaiting` |
/// | 정원 참 · 방장 · 실시간 · 2명 이상 | `MeetingStage.confirmByMe` |
/// | 정원 참 · 실시간 · 2명 이상 | `MeetingStage.confirmByHost` |
/// | 정원 참 | `MeetingStage.finishOnly` |
/// | 그 밖 | `MeetingStage.recruiting` |
///
/// **확정 판정이 정원 판정보다 위에 있는 게 요점이다.** 서버는 확정과 함께 모집을 끝내므로
/// (ACTIVE→COMPLETED) 확정된 방은 늘 정원 단계지만, 그 반대가 성립하지 않는 순간이 있다 —
/// SSE `confirmed` 는 `isConfirmed` 만 세우고 status 는 건드리지 않는다
/// (`MatchWaitingViewModel.applyEvent` 참고). 순서가 뒤집히면 **이미 확정된 방에 「약속 시간 정하기」가
/// 다시 뜬다**(눌러 봐야 409 `ALREADY_CONFIRMED`).
///
/// **도착 여부가 시각보다 위에 있는 것도 요점이다.** 약속 시간이 지난 뒤에도 도착은 누를 수 있어야
/// 하므로(서버 도착 창에 상한이 없다) 미도착이면 `MeetingStage.arriveOpen` 에 머문다 — 거기서
/// 「약속 시간이 됐다」는 사실은 `isMeetingTimePassed` 가 따로 말한다.
///
/// - Parameter now: 지금 시각. **반드시 호출부가 넘긴다** — 이 함수가 시계를 읽으면 경계를 테스트할 수 없다
func meetingStage(ride: Ride, now: Date) -> MeetingStage {
    if !isWaitingForMembers(status: ride.status) { return .closed }

    if ride.isConfirmed {
        let meetAt = ride.departureAt.toMeetingInstantOrNull()
        if hasArrivedMyself(ride: ride), let meetAt, now >= meetAt { return .departOpen }
        if hasArrivedMyself(ride: ride) { return .arrivedWaiting }
        if let meetAt, now >= meetAt.addingTimeInterval(-TimeInterval(ARRIVAL_OPENS_MINUTES_BEFORE * 60)) {
            return .arriveOpen
        }
        return .confirmedWaiting
    }

    if !isFinishStage(status: ride.status) { return .recruiting }
    if !ride.allowsMeetingConfirm { return .finishOnly }
    return ride.isHostedByMe ? .confirmByMe : .confirmByHost
}

extension Ride {
    /// 이 방이 **약속 시간을 정할 수 있는 종류인가** — 서버 `confirm` 의 방 조건 둘을 그대로 본다.
    ///
    /// | 조건 | 서버 거절 |
    /// |---|---|
    /// | 실시간 방이어야 한다 | 409 `NOT_REALTIME_PARTY` |
    /// | 멤버가 2명 이상이어야 한다 | 409 `NOT_ENOUGH_MEMBERS` |
    ///
    /// 멤버 수를 `capacity` 가 아니라 **목록 길이**로 센다 — 정원 1인 방이 「정원 참」이어도 혼자이고,
    /// 그 방에서 프리셋을 띄우면 무엇을 눌러도 409 다. 목록이 유실 신호로 만들어진 값이라 틀릴 수 있지만
    /// (`hasMemberDrift` 가 그걸 잡아 상세를 다시 읽는다) 이 판정에서 틀렸을 때의 대가는 **버튼이 잠깐
    /// 늦게/이르게 뜨는 것**이고, 서버가 최종 판정이라 되돌릴 수 있다.
    ///
    /// 방장 조건은 여기 넣지 않는다 — **방의 성질과 내 권한은 다른 질문**이다(`isFinishStage` 와
    /// `canFinishParty` 를 갈라 둔 것과 같은 이유). 비방장에게 「방장이 정해요」를 안내하려면 "이 방은
    /// 정할 수 있다"가 방장 여부와 별개로 참이어야 한다.
    var allowsMeetingConfirm: Bool {
        roomType == .realtime && members.count >= 2
    }
}

/// 「약속 시간 정하기」를 **내게** 보여 줄 때.
///
/// `canFinishParty` 와 같은 모양이다 — 단계(`isFinishStage`) · 방장(`Ride.isHostedByMe`) ·
/// 방 조건(`Ride.allowsMeetingConfirm`) · 아직 확정 전. true 라도 **서버가 최종 판정**인 것도 같다:
/// 방장은 멤버가 들고 날 때마다 바뀌고 그 승계 신호는 한 번뿐이라 내 스냅샷이 낡을 수 있어,
/// 403 `NOT_PARTY_HOST` 경로는 노출을 막은 뒤에도 남는다(`confirmFailureMessage`).
func canConfirmMeeting(ride: Ride) -> Bool {
    isFinishStage(status: ride.status) && !ride.isConfirmed && ride.allowsMeetingConfirm && ride.isHostedByMe
}

/// 「출발지 도착했어요」를 누를 수 있는 단계인가 — 확정됐고 · **약속 10분 전부터** · 내가 미도착.
///
/// ### 경계
/// `now ≥ 약속 시간 − 10분` 이면 참이다. **정확히 10분 전 그 순간이 참**이다(서버가 「10분 전부터」라
/// 적었다). 상한은 없다 — 약속 시간이 지난 뒤에도 도착은 알릴 수 있어야 한다(늦게 온 사람이 노쇼를
/// 면할 유일한 길이고, 서버 도착 창에도 상한이 없다).
///
/// ### 거리는 보지 않는다 ★
/// 서버가 출발지 100m 를 PostGIS 로 재고 400 `TOO_FAR_FROM_DEPARTURE` 로 답한다. 앱이 같은 거리를
/// 다시 재면 **서버는 받아 주는데 앱이 막는** 경우가 생긴다 — GPS 오차가 수십 m 씩 흔들리는데 그
/// 판정의 기준점(방 출발지 좌표)은 목록 응답으로 만든 `Ride` 에 아예 없을 수도 있다. 거리는 묻지 말고
/// 보내고, 거절당하면 서버가 말한 사유를 보여 준다.
///
/// `departureAt` 을 파싱할 수 없으면 **거짓**이다 — 창이 열렸는지 알 수 없으면 열지 않는다.
func canArriveAtDeparture(ride: Ride, now: Date) -> Bool {
    meetingStage(ride: ride, now: now) == .arriveOpen
}

/// 「출발」을 누를 수 있는 단계인가 — 확정됐고 · **내가 도착했고** · 약속 시간이 지났다.
///
/// ### 방장 전용이 아니다 ★
/// 서버가 그렇게 만들었다 — **도착한 멤버면 누구나** 누를 수 있다(`NOT_ARRIVED` 만 본다).
/// 「합승 완료」(`canFinishParty`)와 여기서 갈린다. 방장 조건을 베껴 오면 **방장이 늦는 방이 영원히
/// 출발하지 못한다**.
///
/// ### 경계
/// `now ≥ 약속 시간` 이면 참이다. 약속 시간 **정각이 참**이다(서버는 약속 시간 전에만 409
/// `MEETING_NOT_STARTED` 를 던진다). 파싱할 수 없는 `departureAt` 은 거짓 — 같은 이유다.
///
/// 멤버 2명 이상 조건(서버 `NOT_ENOUGH_MEMBERS`)은 여기서 보지 않는다. 이 단계에 닿으려면 방이
/// 확정돼 있어야 하고, 확정 자체가 2명 이상에서만 되기 때문이다 — 같은 조건을 두 번 세우면 한쪽만
/// 서버를 따라가게 된다. 그래도 그 사이 누군가 나가는 경로가 생기면 서버가 409 로 막고
/// `departFailureMessage` 가 받는다.
func canDepartParty(ride: Ride, now: Date) -> Bool {
    meetingStage(ride: ride, now: now) == .departOpen
}

/// 약속 시간이 **지났는가**. `MeetingStage` 가 답하지 않는 한 가지를 따로 본다 — 미도착인 사람은
/// 약속 시간이 지나도 `MeetingStage.arriveOpen` 에 머물러서(도착은 계속 누를 수 있어야 한다)
/// 「약속 시간이 됐다」는 사실이 단계에 드러나지 않는다.
///
/// 그 사실을 말해 줘야 하는 이유: 그 사람이 지금 보고 있는 화면에는 「출발」이 없는데, 다른 사람의
/// 화면에는 있다. 아무 말도 하지 않으면 **왜 나만 출발할 수 없는지** 알 길이 없다(`DEPART_NEEDS_ARRIVAL_NOTICE`).
func isMeetingTimePassed(departureAt: String?, now: Date) -> Bool {
    guard let meetAt = departureAt.toMeetingInstantOrNull() else { return false }
    return now >= meetAt
}

/// **내가** 출발지에 도착했다고 서버에 알렸는가 — 멤버 목록의 내 줄 하나만 본다.
///
/// `Ride.isHostedByMe` 와 같은 모양이고 같은 주의가 붙는다: 내가 목록에 없으면(식별자 없는 목록·
/// 생성 응답) false 이고, 그건 「도착하지 않았다」가 아니라 **「도착했다고 말해 주는 근거가 없다」**다.
/// 그 경우 화면은 도착 버튼을 띄우고, 이미 도착했다면 서버가 멱등하게 204 로 받아 준다(시각 유지).
func hasArrivedMyself(ride: Ride) -> Bool {
    ride.members.first(where: { $0.isMe })?.hasArrived == true
}

/// 도착했다고 알린 멤버 수. 「도착 2/3」 표시와 출발 확인 문구가 함께 본다.
func arrivedCount(ride: Ride) -> Int {
    ride.members.filter { $0.hasArrived }.count
}

/// **아직 도착하지 않은** 멤버 수 — 「출발」을 누르면 **노쇼로 기록될 사람 수**다.
///
/// 이 숫자가 확인 다이얼로그의 핵심이라(`departConfirmMessage`) 멤버 목록 하나만 본다. 목록이
/// 유실 신호로 만들어진 값이라 틀릴 수 있지만, 같은 목록이 바로 위에 도착 배지와 함께 그려져 있어
/// 사용자가 눈으로 맞춰 볼 수 있다 — 그게 다른 근거를 들이지 않는 이유다.
func notArrivedCount(ride: Ride) -> Int {
    ride.members.filter { !$0.hasArrived }.count
}

/// 「도착」 배지를 그릴 줄인가 — 확정된 방에서만 뜻이 있다(확정 전에는 도착 개념이 없다).
func showsArrivedBadge(member: User, confirmed: Bool) -> Bool {
    confirmed && member.hasArrived
}

// ─────────────────────────── 시각 표기 ───────────────────────────

// 서버 시각 해석기(`toMeetingInstantOrNull`)는 PresentationCore `MeetingInstant.swift` 에 있다.
// 17·20 예약(FeatureExplore)이 같은 서버 필드(`Ride.departureAt`)를 읽어 한 사본을 함께 쓴다 —
// 여기에 사본을 다시 두면 Swift 가 조용히 이 모듈의 것을 골라 공유 해석기가 쓰이지 않는다.

/// 약속 시각 표기 — `오후 3:23`. 파싱할 수 없으면 **nil** 이고, 그 자리는 비운다.
///
/// 날짜를 붙이지 않는다: 서버가 약속을 **지금부터 1시간 안**으로만 받으므로 언제나 오늘이고,
/// 자정을 넘기는 경우에도 「몇 시에 만나는가」가 전부다. 날짜를 붙이면 줄만 길어진다.
///
/// **문자열을 잘라 쓰지 않는다.** 서버는 UTC 로 내려주므로 `T` 뒤를 잘라 쓰면 KST 오후 3시가
/// 오전 6시로 보인다 — 채팅에서 실제로 났던 결함(QA 결함-3)과 같은 함정이다.
///
/// 분은 기기 로케일과 무관하게 ASCII 숫자로 적는다(`String(format:)` 은 POSIX 로케일이다). 원본
/// `"%02d".format` 은 기기 로케일의 숫자를 따른다.
func meetingTimeLabel(departureAt: String?, zone: TimeZone = .current) -> String? {
    guard let instant = departureAt.toMeetingInstantOrNull() else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let at = calendar.dateComponents([.hour, .minute], from: instant)
    guard let hour = at.hour, let minute = at.minute else { return nil }
    let meridiem = hour < 12 ? "오전" : "오후"
    // 0시·12시가 12 가 되어야 한다 — `hour % 12` 만 쓰면 자정이 「오전 0:05」로 찍힌다.
    let hour12 = hour % 12 == 0 ? 12 : hour % 12
    return "\(meridiem) \(hour12):\(String(format: "%02d", minute))"
}

/// 확정된 방의 헤드라인. 시각을 읽을 수 있으면 **그 시각을 말하고**, 읽을 수 없으면 **확정됐다는
/// 사실만** 말한다.
///
/// 폴백에서 시각을 지어내지 않는 것이 요점이다 — 틀린 약속 시간은 사람을 엉뚱한 때에 모이게 한다.
func meetingHeadline(departureAt: String?, zone: TimeZone = .current) -> String {
    meetingTimeLabel(departureAt: departureAt, zone: zone).map { "\($0)에 만나요" } ?? "약속 시간이 정해졌어요"
}

/// 비방장이 「약속 시간 정하기」가 있던 자리에서 읽는 안내문 — **버튼을 숨긴 자리를 비워 두지 않는다**
/// (`finishHostNotice` 와 같은 자리·같은 이유).
///
/// 비활성 버튼을 두지 않는다: 누를 수 없는 버튼은 왜 못 누르는지 말해 주지 못한다. 대신 **누가
/// 정하는지**와 **정해지면 어떻게 되는지**를 한 줄로 적는다.
///
/// 이름을 쓸 수 있을 때만 이름으로 부른다(`hostDisplayNameOrNull`).
/// 못 쓰는 경우(요약 없음·탈퇴·아무도 지목되지 않음)에는 지어내지 않고 **조건**을 말한다 — 서버
/// `Party.hostId()` 가 현재 멤버 중 `min(joinedAt, memberId)` 라 「가장 먼저 참여한 분」은 사실이다.
func meetingHostNotice(hostNickname: String?) -> String {
    if let hostNickname, !hostNickname.isBlank {
        "방장 \(hostNickname)님이 약속 시간을 정해요. 정해지면 여기에 보여요"
    } else {
        "방장(가장 먼저 참여한 분)이 약속 시간을 정해요. 정해지면 여기에 보여요"
    }
}

/// 「약속 시간 정하기」 블록의 설명 한 줄 — **확정이 되돌릴 수 없는 행동**이라는 것을 버튼 앞에서 말한다.
///
/// 세 가지가 전부 서버 계약이다: ① 확정하면 모집이 끝난다(ACTIVE→COMPLETED) ② 그 뒤로는 **아무도
/// 방을 나갈 수 없다** ③ 한 번만 정할 수 있다(409 `ALREADY_CONFIRMED`). 특히 ②는 사용자가 되돌릴
/// 수 없는 쪽으로 밀어 넣는 변화라, 다이얼로그에서만 말하면 늦다.
let MEETING_CONFIRM_HELP = "약속 시간을 정하면 모집이 끝나요. 그 뒤로는 아무도 방을 나갈 수 없고 시간도 바꿀 수 없어요"

/// 프리셋 묶음 위에 붙는 물음. 칩은 「10분」처럼 숫자만 적으므로 이 줄이 단위를 말한다.
let MEETING_PRESET_PROMPT = "몇 분 뒤에 만날까요?"

/// 프리셋이 왜 1시간까지뿐인지 — 서버가 그렇게 받는다. 없는 제약을 말하지 않는다.
let MEETING_PRESET_LIMIT_NOTE = "약속 시간은 지금부터 1시간 안으로만 정할 수 있어요"

/// 프리셋을 누르면 뜨는 확인 다이얼로그의 제목 — **고른 시각을 숫자로 되읽어 준다**.
///
/// 칩에는 「10분」만 적혀 있어서, 그것이 몇 시를 뜻하는지 확인할 기회가 여기 한 번뿐이다.
func meetingConfirmTitle(timeLabel: String?) -> String {
    timeLabel.map { "\($0)에 만날까요?" } ?? "약속 시간을 정할까요?"
}

/// 확정 다이얼로그 본문 — `MEETING_CONFIRM_HELP` 와 같은 사실을 되읽어 준다(누르기 직전이 마지막 기회다).
let MEETING_CONFIRM_DIALOG_BODY =
    "정하면 모집이 끝나고 모두에게 약속 시간이 보여요. 그 뒤로는 아무도 방을 나갈 수 없고 시간도 바꿀 수 없어요"

/// 도착 창이 아직 안 열렸을 때. **숫자를 말해 줘야** 언제 다시 보면 되는지 알 수 있다.
let ARRIVE_NOT_OPEN_NOTICE = "약속 10분 전부터 「출발지 도착했어요」를 누를 수 있어요"

/// 도착을 알린 뒤 · 약속 시간 전. 한 일과 다음에 일어날 일만 적는다.
let ARRIVED_WAITING_NOTICE = "도착했다고 알렸어요. 약속 시간이 되면 출발할 수 있어요"

/// 약속 시간이 지났는데 **내가 아직 도착을 알리지 않았을 때**.
///
/// 이 자리가 비어 있으면 그 사람은 남들에게만 보이는 「출발」을 두고 영문을 모른다. 서버 조건
/// (`NOT_ARRIVED`)을 그대로 말해 주는 것이 가장 짧은 설명이다.
let DEPART_NEEDS_ARRIVAL_NOTICE = "약속 시간이 됐어요. 도착했다고 알린 사람만 출발할 수 있어요"

/// 위치 권한이 없을 때 도착 버튼 자리에 들어가는 안내 — **왜 필요한지**를 말한다.
///
/// 21 은 진입할 때 권한을 자동 요청하지 않는다(대기 화면의 본질이 지도가 아니다). 그래서 도착
/// 단계에 처음 닿은 사람이 권한을 거부해 둔 상태일 수 있고, 그때 비활성 버튼만 두면 왜 안 되는지
/// 알 수 없다 — 17 탐색의 `LocationPermissionNotice` 와 같은 처방이다(안내 + 다시 요청할 버튼).
let ARRIVE_NEEDS_PERMISSION_NOTICE = "도착을 알리려면 위치 권한이 필요해요. 서버가 출발지에서 100m 안인지 확인해요"

/// 권한은 있는데 아직 첫 좌표가 안 들어왔다. 사용자가 할 일이 없으므로 **기다리라고만** 한다.
let ARRIVE_LOCATING_LABEL = "현재 위치를 확인하는 중…"

/// 「출발」 확인 다이얼로그 본문 — **노쇼가 생긴다는 사실과 그 대가**를 누르기 전에 말한다.
///
/// 이 다이얼로그가 이 작업에서 가장 조심한 자리다. 「출발」은 되돌릴 수 없고, 그 순간 도착하지 않은
/// 사람에게는 **실제 제재**가 붙는다 — 약속 시간부터 (노쇼 횟수 × 24시간) 동안 방을 만들지도
/// 참여하지도 못한다. 누르는 사람은 보통 자기 제재가 아니라 **남의 제재**를 만들게 되므로, 숫자를
/// 보여 주지 않으면 그 무게를 알 수 없다.
///
/// 서버가 하지 않는 일을 말하지 않는다: 「알림이 가요」·「잠시 기다려 주세요」 같은 완충 문구는
/// 넣지 않았다 — 앱이 아는 것은 「방이 끝난다」와 「미도착자가 노쇼로 기록된다」 둘뿐이다.
///
/// `notArrivedCount` 가 0 이면 노쇼 문장을 **아예 뺀다**. 아무도 기록되지 않는데 제재를 말하면
/// 겁만 주고, 다음에 정말 노쇼가 생길 때 같은 문구가 무게를 잃는다.
func departConfirmMessage(notArrivedCount: Int) -> String {
    if notArrivedCount <= 0 {
        "모두 도착했어요. 출발하면 같이 탄 사람 모두의 방이 끝나요"
    } else {
        "같이 탄 사람 모두의 방이 끝나요. 아직 도착하지 않은 \(notArrivedCount)명은 노쇼로 기록돼요 — "
            + "약속 시간부터 노쇼 횟수 × 24시간 동안 방·예약을 만들거나 참여할 수 없어요"
    }
}

/// 「도착 2/3」 — 확정된 방에서 사람들이 가장 자주 확인하는 숫자다. 확정 전에는 뜻이 없어 nil.
func arrivalCountLabel(ride: Ride) -> String? {
    if !ride.isConfirmed || ride.members.isEmpty { return nil }
    return "도착 \(arrivedCount(ride: ride))/\(ride.members.count)"
}

// ─────────────────────────── 실패 문구 ───────────────────────────

/// **공통 규칙** — 세 액션(확정·도착·출발)의 실패 문구는 전부 이 모양을 따른다
/// (`finishFailureMessage`·`leaveFailureMessage` 가 세운 선례다).
///
/// 1. **서버 코드로만 가른다.** HTTP 상태로 추측하지 않는다 — 확정은 403 이 두 가지 뜻
///    (`NOT_PARTY_HOST`/`NOT_PARTY_MEMBER`)이고 409 가 네 가지라, 상태로 고르면 반드시 절반은
///    틀린 말이 된다. 분기 근거는 도메인이 코드를 한 번 걸러 준 `is…` 프로퍼티다.
/// 2. **모르는 코드는 일반 문구로 떨어진다.** 서버가 `MatchingErrorCode` 를 늘려도 앱이 지어내지
///    않는다 — 모른다고 하는 편이 낫다. 코드가 없는 실패(네트워크·본문 파싱 실패)도 같은 자리다.
/// 3. **403·409 에 「다시 시도」류를 붙이지 않는다.** 다시 눌러도 같은 답이다. 방 사정이 바뀌어야
///    풀린다(`FinishFailureMessageTest`·`MeetingFailureMessageTest` 가 이 금지를 못 박는다).
/// 4. **서버가 하는 일만 적는다.** 100m 는 서버가 재는 값이므로 그대로 말하고, 「가까워지면 자동으로
///    알려 드려요」 같은 없는 기능은 말하지 않는다.
let CONFIRM_FAILED_MESSAGE = "약속 시간을 정하지 못했어요"

/// 「약속 시간 정하기」 실패 → 사용자 문구.
///
/// | 사유 | 서버 코드(HTTP) | 사용자가 할 일 |
/// |---|---|---|
/// | 1시간을 벗어났다 | `INVALID_MEETING_TIME` (400) | 더 가까운 프리셋을 고른다 |
/// | 방장이 아니다 | `NOT_PARTY_HOST` (403) | 가장 먼저 참여한 사람에게 부탁한다 |
/// | 멤버가 아니다 | `NOT_PARTY_MEMBER` (403) | 홈에서 진행 중인 방을 확인한다 |
/// | 실시간 방이 아니다 | `NOT_REALTIME_PARTY` (409) | 이 방에서는 할 수 없다 |
/// | 이미 정해졌다 | `ALREADY_CONFIRMED` (409) | 할 일이 없다(화면이 곧 확정 상태로 바뀐다) |
/// | 모집 단계가 아니다 | `PARTY_NOT_RECRUITING` (409) | 홈으로 돌아간다 — 방이 이미 닫혔다 |
/// | 2명 미만 | `NOT_ENOUGH_MEMBERS` (409) | 사람이 더 모여야 한다 |
/// | 방 없음 | `PARTY_NOT_FOUND` (404) | 홈으로 돌아간다 |
/// | 그 밖·네트워크 | 코드 없음 | `CONFIRM_FAILED_MESSAGE` |
///
/// `INVALID_MEETING_TIME` 만 **행동을 권한다** — 400 이고, 더 가까운 프리셋을 고르면 실제로 통과한다.
/// 프리셋이 이 400 을 사용자의 실수에서 지우지만 **없애지는 못한다**: 기기 시계가 서버보다 앞서 있으면
/// 60분 프리셋이 서버 기준 1시간을 넘을 수 있다(`MEETING_PRESET_MINUTES`).
///
/// 방장 안내가 「가장 먼저 참여한 분」인 건 서버가 방장을 그렇게 정하기 때문이다
/// (`Party.hostId()` = 현재 멤버 중 `min(joinedAt, memberId)`). **이름을 쓰지 않는다** — 이 403 은 내
/// 스냅샷이 가리킨 방장이 서버 기준으로 더 이상 방장이 아니라는 뜻이라, 그 스냅샷으로 이름을 부르면
/// **틀린 사람에게 부탁하라고 말하게 된다**(`finishFailureMessage` 와 같은 근거·같은 표현).
func confirmFailureMessage(e: PartyConfirmException) -> String {
    if e.isInvalidMeetingTime { return "약속 시간은 지금부터 1시간 안이어야 해요. 더 가까운 시간으로 골라 주세요" }
    if e.isNotHost { return "방장만 약속 시간을 정할 수 있어요. 가장 먼저 참여한 분에게 부탁해 주세요" }
    if e.isNotMember { return "이 방의 참여자가 아니에요. 홈에서 진행 중인 방을 확인해 주세요" }
    if e.isNotRealtimeParty { return "실시간으로 모인 방에서만 약속 시간을 정할 수 있어요" }
    if e.isAlreadyConfirmed { return "이미 약속 시간이 정해진 방이에요" }
    if e.isNotRecruiting { return "이미 끝난 방이에요. 홈으로 돌아가 주세요" }
    if e.isNotEnoughMembers { return "2명 이상 모여야 약속 시간을 정할 수 있어요" }
    if e.isPartyNotFound { return "이미 사라진 방이에요. 홈으로 돌아가 주세요" }
    return CONFIRM_FAILED_MESSAGE
}

/// 사유를 가릴 수 없는 도착 실패의 일반 문구 — 네트워크 실패와 **모르는 코드**가 여기로 떨어진다.
let ARRIVE_FAILED_MESSAGE = "도착을 알리지 못했어요"

/// 「출발지 도착했어요」 실패 → 사용자 문구.
///
/// | 사유 | 서버 코드(HTTP) | 사용자가 할 일 |
/// |---|---|---|
/// | 출발지에서 멀다 | `TOO_FAR_FROM_DEPARTURE` (400) | 출발지에 더 가까이 간다 |
/// | 서비스 지역 밖 | `OUT_OF_SERVICE_AREA` (400) | 좌표가 서비스 지역 밖이다 |
/// | 멤버가 아니다 | `NOT_PARTY_MEMBER` (403) | 홈에서 진행 중인 방을 확인한다 |
/// | 방이 닫혔다 | `PARTY_CLOSED` (409) | 홈으로 돌아간다 |
/// | 확정 전이다 | `PARTY_NOT_CONFIRMED` (409) | 약속 시간이 정해지기를 기다린다 |
/// | 창이 안 열렸다 | `ARRIVAL_NOT_OPEN` (409) | 약속 10분 전까지 기다린다 |
/// | 방 없음 | `PARTY_NOT_FOUND` (404) | 홈으로 돌아간다 |
/// | 그 밖·네트워크 | 코드 없음 | `ARRIVE_FAILED_MESSAGE` |
///
/// ### `TOO_FAR_FROM_DEPARTURE` 가 이 함수의 존재 이유다 ★
/// 앱은 **거리를 재지 않는다**(재면 서버와 다른 두 번째 진실이 생긴다 — `canArriveAtDeparture` 주석).
/// 그래서 「멀다」는 사실을 사용자에게 말해 줄 수 있는 자리가 **여기 하나뿐**이다. 숫자(100m)를
/// 적는 이유도 같다: 「조금 더 가까이」만으로는 10m 를 더 가야 하는지 300m 를 더 가야 하는지 모른다.
/// 그 100m 는 앱이 고른 값이 아니라 **서버가 PostGIS 로 재는 값**이다.
///
/// 「다시 시도」류를 넣지 않는다. 400 이지만 같은 자리에서 다시 눌러도 같은 400 이고, 사용자가 할 일은
/// 재시도가 아니라 **이동**이다.
func arriveFailureMessage(e: PartyArriveException) -> String {
    if e.isTooFarFromDeparture { return "출발지에서 100m 안에 있어야 도착을 알릴 수 있어요. 출발지로 더 가까이 가 주세요" }
    if e.isOutOfServiceArea { return "서비스 지역을 벗어난 위치예요" }
    if e.isNotMember { return "이 방의 참여자가 아니에요. 홈에서 진행 중인 방을 확인해 주세요" }
    if e.isPartyClosed { return "이미 끝난 방이에요. 홈으로 돌아가 주세요" }
    if e.isNotConfirmed { return "아직 약속 시간이 정해지지 않았어요" }
    if e.isArrivalNotOpen { return "약속 10분 전부터 도착을 알릴 수 있어요" }
    if e.isPartyNotFound { return "이미 사라진 방이에요. 홈으로 돌아가 주세요" }
    return ARRIVE_FAILED_MESSAGE
}

/// 사유를 가릴 수 없는 출발 실패의 일반 문구 — 네트워크 실패와 **모르는 코드**가 여기로 떨어진다.
let DEPART_FAILED_MESSAGE = "출발하지 못했어요"

/// 「출발」 실패 → 사용자 문구.
///
/// | 사유 | 서버 코드(HTTP) | 사용자가 할 일 |
/// |---|---|---|
/// | 도착하지 않았다 | `NOT_ARRIVED` (409) | 먼저 도착을 알린다 |
/// | 약속 시간 전 | `MEETING_NOT_STARTED` (409) | 약속 시간까지 기다린다 |
/// | 2명 미만 | `NOT_ENOUGH_MEMBERS` (409) | 혼자서는 출발할 수 없다 |
/// | 확정 전이다 | `PARTY_NOT_CONFIRMED` (409) | 약속 시간이 정해져야 한다 |
/// | 방이 닫혔다 | `PARTY_CLOSED` (409) | 홈으로 돌아간다 |
/// | 멤버가 아니다 | `NOT_PARTY_MEMBER` (403) | 홈에서 진행 중인 방을 확인한다 |
/// | 방 없음 | `PARTY_NOT_FOUND` (404) | 홈으로 돌아간다 |
/// | 그 밖·네트워크 | 코드 없음 | `DEPART_FAILED_MESSAGE` |
///
/// `NOT_ARRIVED` 문구가 **다음 행동을 알려 주는** 유일한 가지다 — 그 사람은 바로 위의
/// 「출발지 도착했어요」를 누르면 된다. 버튼 이름을 그대로 적는 이유: 「도착을 알려야 한다」만
/// 적으면 어디를 눌러야 하는지 찾아야 한다. 나머지는 기다리거나 떠나는 것 말고 할 일이 없으므로
/// 행동을 권하지 않는다(없는 길을 권하면 그게 거짓이다).
///
/// 「다시 시도」류는 한 줄도 없다 — 전부 다시 눌러도 같은 답이다.
func departFailureMessage(e: PartyDepartException) -> String {
    if e.isNotArrived { return "먼저 「출발지 도착했어요」를 눌러야 출발할 수 있어요" }
    if e.isMeetingNotStarted { return "약속 시간이 지나야 출발할 수 있어요" }
    if e.isNotEnoughMembers { return "2명 이상 모여야 출발할 수 있어요" }
    if e.isNotConfirmed { return "아직 약속 시간이 정해지지 않았어요" }
    if e.isPartyClosed { return "이미 끝난 방이에요. 홈으로 돌아가 주세요" }
    if e.isNotMember { return "이 방의 참여자가 아니에요. 홈에서 진행 중인 방을 확인해 주세요" }
    if e.isPartyNotFound { return "이미 사라진 방이에요. 홈으로 돌아가 주세요" }
    return DEPART_FAILED_MESSAGE
}
