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
// 특히 **출발지 반경은 앱이 재지 않는다** — 서버가 PostGIS 로 재고 400
// `TOO_FAR_FROM_DEPARTURE` 로 답한다. 앱이 같은 거리를 다시 재면 두 개의 진실이 생기고(좌표 정확도가
// 수십 m 씩 흔들린다) **서버는 받아 주는데 앱이 막는** 경우가 생긴다. 거리는 묻지 말고 보내고,
// 거절당하면 서버가 말한 사유를 그대로 보여 준다(`arriveFailureMessage`).
//
// 숫자만은 말해 준다 — 그리고 그 숫자는 **방 종류로 갈린다**(`arrivalRadiusMeters`).

// ─────────────────────────── 약속 시간 고르기 ───────────────────────────

/// 약속 시간 휠의 간격 — **5분 단위**.
///
/// ### 「몇 분 뒤」 칩 대신 시각을 고르게 바꿨다 (2026-11-18)
/// 예전에는 「지금부터 10·20·30·45·60분 뒤」 칩 다섯 개였다. 채팅으로 「2시 5분에 3번 출구」처럼
/// **시각으로** 약속을 잡고 나면, 방장이 그 시각이 몇 분 뒤인지 계산해 가장 가까운 칩을 골라야 했다(오너 요청).
/// 그래서 **실제 시각**을 휠로 보여 준다.
///
/// 휠에는 **서버가 받는 값만** 넣는다 — 서버는 약속 시간을 **지금부터 5분 뒤 ~ 1시간**으로만 받고, 벗어나면
/// 400 `INVALID_MEETING_TIME` 이다. 고를 수 없는 시각을 띄워 두고 거절당하게 하지 않는다(`meetingTimeOptions`).
let MEETING_TIME_STEP_MINUTES = 5

/// 가장 이른 약속 — **지금부터 10분 뒤**(서버 하한은 5분).
///
/// 5분이 아니라 10분인 이유: 도착 버튼은 **약속 10분 전부터** 열린다(`canArriveAtDeparture`). 10분 안쪽으로
/// 잡으면 확정하자마자 도착 창이 열려 있어 「언제 오면 되는지」를 말해 줄 틈이 없고, 시트를 몇 분 들고 있기만
/// 해도 서버 하한(5분) 아래로 내려간다.
let MEETING_EARLIEST_MINUTES = 10

/// 가장 늦은 약속 — **지금부터 1시간 뒤**. 서버 상한 그대로다.
let MEETING_LATEST_MINUTES = 60

/// 지금 고를 수 있는 약속 시각들 — `MEETING_EARLIEST_MINUTES` 뒤부터 `MEETING_LATEST_MINUTES` 뒤까지 **5분
/// 단위 정각**(:00·:05·…)만, 이른 순서로.
///
/// - 처음 값은 「10분 뒤」를 **올림**한 5분 정각이다(13:47 → 13:57 → **14:00**). 내림하면 10분이 안 된다
/// - 끝 값은 「1시간 뒤」를 **내림**한 5분 정각이다(13:47 → 14:47 → **14:45**). 올림하면 서버 상한을 넘는다 —
///   기기 시계가 서버보다 조금 앞서 있어도 내림한 몫만큼 여유가 생긴다
/// - 초는 늘 0 이다 — 휠이 보여 주는 「오후 2:00」이 곧 보내는 값이다
///
/// 5분 정각을 epoch 초(300의 배수)로 자른다. 한국 표준시는 UTC+9 정시라 UTC 의 5분 정각이 KST 의 5분 정각과 같다.
/// 자정을 넘는 범위(23:30 → 00:30)도 시각을 그대로 늘어놓으므로 따로 다루지 않는다.
func meetingTimeOptions(now: Date) -> [Date] {
    let step = Int64(MEETING_TIME_STEP_MINUTES * 60)
    let nowSeconds = Int64(now.timeIntervalSince1970.rounded(.down))
    let earliest = floorDiv(nowSeconds + Int64(MEETING_EARLIEST_MINUTES * 60) + step - 1, step) * step
    let latest = floorDiv(nowSeconds + Int64(MEETING_LATEST_MINUTES * 60), step) * step
    guard earliest <= latest else { return [] }
    return stride(from: earliest, through: latest, by: Int(step)).map { Date(timeIntervalSince1970: TimeInterval($0)) }
}

/// Kotlin `Math.floorDiv` — 음수에서도 아래로 내린다(Swift `/` 는 0 쪽으로 자른다).
private func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}

/// 휠이 가리킬 값 — 고른 시각이 **아직 고를 수 있으면 그대로**, 시간이 흘러 목록에서 빠졌으면(또는 아직
/// 안 골랐으면) **가장 이른 시각**.
///
/// 화면의 시계는 몇 초마다 돈다. 휠을 2:00 에 둔 채 몇 분 지나면 2:00 이 「10분 뒤」보다 앞이 되어 목록에서
/// 빠지는데, 그 값을 그대로 들고 있으면 휠은 다른 칸을 보여 주면서 확정은 빠진 값으로 나간다.
func meetingSelectedTime(options: [Date], picked: Date?) -> Date? {
    if let picked, options.contains(picked) { return picked }
    return options.first
}

/// 휠 아래 되읽기 — 「지금부터 15분 뒤」. 시각만 보이면 얼마나 남았는지 다시 계산해야 한다.
func meetingMinutesFromNowLabel(now: Date, at: Date) -> String {
    let seconds = Int64(at.timeIntervalSince1970.rounded(.down)) - Int64(now.timeIntervalSince1970.rounded(.down))
    return "지금부터 \(floorDiv(seconds + 59, 60))분 뒤"
}

/// 서버에 보낼 ISO-8601 문자열 — `2026-11-03T08:30:00Z`.
///
/// 앱은 시각을 **문자열 그대로** 다룬다(`Ride.departureAt`·`RideRecord`·`ChatMessage` 와 같은 관례):
/// 보내는 자리에서만 만들고 읽는 자리에서만 파싱한다. `Date.ISO8601FormatStyle` 기본값은 UTC `Z` 표기이고
/// 초를 늘 적는다 — 서버(Jackson `Instant`)는 어느 쪽이든 같게 읽는다.
func meetingTimeIso(_ at: Date) -> String {
    at.formatted(.iso8601)
}

// ─────────────────────────── 단계 판정 ───────────────────────────

/// 21 이 지금 **어느 단계**인가 — 리더가 정한 화면 상태표를 그대로 타입으로 옮긴 것이다.
///
/// 불리언 여럿으로 흩어 두지 않는 이유: 「확정됐고 · 도착 창이 열렸고 · 내가 아직 도착하지 않았고 ·
/// 약속 시간은 지나지 않았다」 같은 조합을 화면이 매번 다시 세우면 **조합 하나를 빠뜨려도 컴파일이
/// 통과한다**. 하나의 enum 으로 모으면 `switch` 가 빠진 가지를 잡아 주고, 상태표 전체를 테스트
/// 하나로 고정할 수 있다(`meetingStage`).
enum MeetingStage: Sendable {
    /// 모집 중이고 **아직 약속을 정할 수 없다**(혼자이거나 실시간 방이 아니다) — 약속·도착·출발이 끼어들지 않는다
    case recruiting

    /// 아직 확정 전이고 · **내가 약속 시간을 정할 수 있다**(방장 · 실시간 방 · 2명 이상).
    /// 프리셋 버튼을 보여 준다.
    ///
    /// **정원이 찼는지는 보지 않는다** — 서버 `confirm` 이 보지 않기 때문이다. 3인 방에 2명이
    /// 모였을 때 「지금 인원으로 간다」가 방장의 선택지이고, 그 확정이 모집을 끝낸다.
    case confirmByMe

    /// 아직 확정 전이고 · 실시간 2명 이상인 방이고 · 내가 방장이 아니다 — **방장이 정한다**고 알린다
    case confirmByHost

    // `finishOnly`(정원은 찼지만 약속을 정할 수 없는 방 — 방장이 「합승 완료」로 끝내던 자리)는
    // **지웠다.** 서버가 `/finish` 를 없애(`b16551b7`) 그 단계에서 할 수 있는 일이 하나도 없어졌고,
    // 「정원이 찼다」를 알려 주던 status 도 뜻이 바뀌어(COMPLETED = 확정) 판정 근거조차 사라졌다.
    //
    // 그 조건(정원 참 · 약속 불가)을 만족하는 방은 지금 `recruiting` 으로 떨어진다. 실제로 그게
    // 맞다 — 정원이 찬 1인 방이나 예약 방에서 사용자가 할 수 있는 일은 **기다리거나 나가는 것**뿐이고,
    // 그건 모집 중 화면이 이미 말하는 바다.

    /// 확정됐고 · 내가 아직 도착하지 않았고 · **도착 창이 아직 안 열렸다**(약속 10분 전 이전).
    ///
    /// `departureAt` 을 파싱할 수 없을 때도 여기로 온다 — 창이 열렸는지 **알 수 없으면 열지 않는다**.
    /// 열어 두고 409 `ARRIVAL_NOT_OPEN` 을 맞게 하는 것보다 낫다.
    case confirmedWaiting

    /// 확정됐고 · 약속 **10분 전부터** · 내가 미도착 — 「출발지 도착했어요」
    case arriveOpen

    /// 확정됐고 · 내가 도착했고 · 아직 약속 시간 전 — 기다리는 상태(누를 것이 없다)
    case arrivedWaiting

    /// 확정됐고 · 내가 도착했고 · 약속 시간이 지났고 · **내가 방장이다** — 「출발」을 누른다.
    ///
    /// 출발은 `b16551b7` 부터 **방장 전용**이다(「출발은 도착한 방장만 누른다」). 그 전에는 도착한
    /// 멤버면 누구나였고, 그래서 이 단계가 방장 여부로 갈리지 않았다 — 지금 갈라 두지 않으면
    /// 비방장에게 **403 `NOT_PARTY_HOST` 로만 끝나는 버튼**을 띄운다.
    case departByMe

    /// 확정됐고 · 내가 도착했고 · 약속 시간이 지났지만 · **내가 방장이 아니다** — 방장이 누른다고 알린다.
    ///
    /// 누를 것이 없는데도 `arrivedWaiting` 과 갈라 두는 이유: 저쪽은 「아직 약속 시간 전」이라
    /// **기다리면 되는** 상태이고 이쪽은 **시간이 다 됐는데 내 화면에는 버튼이 없는** 상태다.
    /// 같은 말을 하면 「왜 나만 출발이 안 되지」에 답하지 못한다(`confirmByHost` 와 같은 형태의 분기다).
    case departByHost

    /// 방이 닫혔다(FINISHED·CANCELED). Route 가 곧 화면을 떠나지만 그 사이 한 프레임을 그린다
    case closed
}

/// 도착 창이 열리는 시각 — 약속 시간의 **10분 전**. 서버 `arrive` 의 `ARRIVAL_NOT_OPEN` 경계다.
///
/// 상수로 빼 둔 이유는 문구가 같은 숫자를 말하기 때문이다(`ARRIVE_NOT_OPEN_NOTICE` ·
/// `arriveFailureMessage`) — 한쪽만 고치면 화면이 서버와 다른 약속을 하게 된다.
let ARRIVAL_OPENS_MINUTES_BEFORE: Int64 = 10

/// 실시간 방의 도착 판정 반경(m) — 서버 `Party.REALTIME_ARRIVAL_RADIUS_METERS`.
private let REALTIME_ARRIVAL_RADIUS_METERS = 100

/// 예약 방의 도착 판정 반경(m) — 서버 `Party.RESERVATION_ARRIVAL_RADIUS_METERS`.
private let RESERVATION_ARRIVAL_RADIUS_METERS = 400

/// 서버가 도착을 받아 주는 반경(m) — **방 종류로 갈린다.** 실시간 100m · 예약 400m.
///
/// ### 한 숫자로 박으면 예약 방 사용자에게 거짓이 된다 ★
/// 오래 「100m」 하나였다. 서버가 `b16551b7` 에서 예약 방의 반경을 400m 로 넓혔다 — 예약 방의
/// 출발지는 **장소 검색 결과의 중심점**이고 확정으로 옮길 수도 없어서(409 `NOT_REALTIME_PARTY`),
/// 역 중심점에서 100m 를 요구하면 그 역에 서 있는 사람이 도착을 알릴 수 없다.
///
/// 숫자를 지우고 「가까이」로 뭉개지 않는 이유: 「조금 더 가까이」만으로는 10m 를 더 가야 하는지
/// 300m 를 더 가야 하는지 모른다. 거리를 **재지 않는** 앱이 사용자에게 줄 수 있는 유일한 단서다.
func arrivalRadiusMeters(roomType: RoomType) -> Int {
    switch roomType {
    case .realtime: REALTIME_ARRIVAL_RADIUS_METERS
    case .reservation: RESERVATION_ARRIVAL_RADIUS_METERS
    }
}

/// 화면 상태표의 **단일 판정**. 위에서부터 읽는다 — 앞의 가지가 뒤를 가린다.
///
/// | 조건 | 결과 |
/// |---|---|
/// | 방이 닫혔다 | `MeetingStage.closed` |
/// | 확정됐다 · 내가 도착 · `now ≥ 약속 시간` · **방장** | `MeetingStage.departByMe` |
/// | 확정됐다 · 내가 도착 · `now ≥ 약속 시간` | `MeetingStage.departByHost` |
/// | 확정됐다 · 내가 도착 | `MeetingStage.arrivedWaiting` |
/// | 확정됐다 · `now ≥ 약속 − 10분` | `MeetingStage.arriveOpen` |
/// | 확정됐다 | `MeetingStage.confirmedWaiting` |
/// | 방장 · 실시간 · 2명 이상 | `MeetingStage.confirmByMe` |
/// | 실시간 · 2명 이상 | `MeetingStage.confirmByHost` |
/// | 그 밖 | `MeetingStage.recruiting` |
///
/// ### 「정원 참」 가지가 **표에서 사라졌다** ★
/// 오래 맨 아래에 `정원 참 → finishOnly` 가 있었다. 두 가지가 동시에 없어졌다: 「합승 완료」라는
/// 동작이 서버에서 사라졌고(`/finish`), **정원이 찼는지를 status 로 알 수 없게 됐다**
/// (COMPLETED = 확정, 정원이 차도 ACTIVE — `b16551b7`). 정원은 이제 이 화면의 단계를 가르지 않는다.
///
/// **확정 판정이 맨 위에 있는 게 요점이다.** 확정은 실시간 방에서만 status 를 COMPLETED 로 옮기고
/// **예약 방은 확정인데도 ACTIVE** 다. 그래서 status 로 확정을 물으면 예약 방이 통째로 빠져
/// 도착·출발이 영원히 안 뜬다 — 묻는 창구는 `Ride.isConfirmed` 하나다. SSE `confirmed` 가
/// `isConfirmed` 만 세우고 status 는 건드리지 않는 것도 같은 이유로 안전하다
/// (`MatchWaitingViewModel.applyEvent` 참고).
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
        let meetingReached = meetAt.map { now >= $0 } ?? false

        // 출발은 방장 전용이다 — 도착한 비방장에게는 누를 것이 없다는 사실을 따로 말해야 한다.
        if hasArrivedMyself(ride: ride) && meetingReached { return ride.isHostedByMe ? .departByMe : .departByHost }
        if hasArrivedMyself(ride: ride) { return .arrivedWaiting }
        if let meetAt, now >= meetAt.addingTimeInterval(-TimeInterval(ARRIVAL_OPENS_MINUTES_BEFORE * 60)) {
            return .arriveOpen
        }
        return .confirmedWaiting
    }

    // **정원을 보지 않는 게 요점이다.** 서버 `confirm` 은 실시간 방 · 방장 · 2명 이상이면 받고,
    // 그 확정이 모집을 끝낸다(`Party.confirm`). 정원 참을 요구하면 **3인 방에 2명이 모인 방장이
    // 아무것도 할 수 없다** — 끝낼 길이 「확정 → 도착 → 출발」 하나뿐이므로 확정을 막는 것은
    // 그 방을 버리라는 말이 된다.
    if ride.allowsMeetingConfirm { return ride.isHostedByMe ? .confirmByMe : .confirmByHost }

    return .recruiting
}

extension Ride {
    /// 이 방이 **약속 시간을 정할 수 있는 종류인가** — 서버 `confirm` 의 방 조건 둘을 그대로 본다.
    ///
    /// | 조건 | 서버 거절 |
    /// |---|---|
    /// | 실시간 방이어야 한다 | 409 `NOT_REALTIME_PARTY` |
    /// | 멤버가 2명 이상이어야 한다 | 409 `NOT_ENOUGH_MEMBERS` |
    ///
    /// 멤버 수를 `capacity` 가 아니라 **목록 길이**로 센다 — 정원 1인 방은 「정원 참」이어도 혼자이고,
    /// 그 방에서 프리셋을 띄우면 무엇을 눌러도 409 다. 목록이 유실될 수 있는 신호로 만들어진 값이라 틀릴
    /// 수 있지만, 이 판정에서 틀렸을 때의 대가는 **버튼이 잠깐 늦게/이르게 뜨는 것**이고 서버가 최종
    /// 판정이라 되돌릴 수 있다.
    ///
    /// 방장 조건은 여기 넣지 않는다 — **방의 성질과 내 권한은 다른 질문**이다. 비방장에게
    /// 「방장이 정해요」를 안내하려면 "이 방은 정할 수 있다"가 방장 여부와 별개로 참이어야 한다.
    var allowsMeetingConfirm: Bool {
        roomType == .realtime && members.count >= 2
    }
}

/// 「약속 시간 정하기」를 **내게** 보여 줄 때.
///
/// ### 정원은 조건이 아니다 ★
/// 서버 `confirm` 이 요구하는 것은 **방장 · 실시간 방 · 멤버 2명 이상 · 열린 방 · 아직 확정 전**이고
/// 정원은 그 목록에 없다. 3인 방에 2명이 모인 방장은 「지금 인원으로 간다」를 고를 수 있다.
///
/// 한동안 이쪽이 「정원 참」을 요구했다. 그래서 **3인 방에 2명이 모이면 길이 막혔다**: 확정은 앱이
/// 숨기고 옛 「합승 완료」는 서버가 409 `PARTY_NOT_COMPLETED` 로 막아, 오지 않는 세 번째 사람을
/// 기다리거나 방을 버려야 했다. 지금은 그 「합승 완료」 자체가 없으므로 **확정을 막으면 끝낼 길이
/// 아예 없다** — 같은 실수를 다시 하면 대가가 더 크다.
///
/// true 라도 **서버가 최종 판정**인 것은 그대로다: 방장은 멤버가 들고 날 때마다 바뀌고 그 승계
/// 신호는 한 번뿐이라 내 스냅샷이 낡을 수 있어, 403 `NOT_PARTY_HOST` 경로는 노출을 막은 뒤에도
/// 남는다(`confirmFailureMessage`).
func canConfirmMeeting(ride: Ride) -> Bool {
    isWaitingForMembers(status: ride.status) && !ride.isConfirmed && ride.allowsMeetingConfirm && ride.isHostedByMe
}

/// 「출발지 도착했어요」를 누를 수 있는 단계인가 — 확정됐고 · **약속 10분 전부터** · 내가 미도착.
///
/// ### 경계
/// `now ≥ 약속 시간 − 10분` 이면 참이다. **정확히 10분 전 그 순간이 참**이다(서버가 「10분 전부터」라
/// 적었다). 상한은 없다 — 약속 시간이 지난 뒤에도 도착은 알릴 수 있어야 한다(늦게 온 사람이 **그 방의
/// 탑승자로 남을 유일한 길**이고, 서버 도착 창에도 상한이 없다).
///
/// ### 거리는 보지 않는다 ★
/// 서버가 출발지 반경을 PostGIS 로 재고 400 `TOO_FAR_FROM_DEPARTURE` 로 답한다. 앱이 같은 거리를
/// 다시 재면 **서버는 받아 주는데 앱이 막는** 경우가 생긴다 — GPS 오차가 수십 m 씩 흔들리는데 그
/// 판정의 기준점(방 출발지 좌표)은 목록 응답으로 만든 `Ride` 에 아예 없을 수도 있다. 거리는 묻지 말고
/// 보내고, 거절당하면 서버가 말한 사유를 보여 준다.
///
/// `departureAt` 을 파싱할 수 없으면 **거짓**이다 — 창이 열렸는지 알 수 없으면 열지 않는다.
func canArriveAtDeparture(ride: Ride, now: Date) -> Bool {
    meetingStage(ride: ride, now: now) == .arriveOpen
}

/// 「출발지 도착했어요」가 **되돌릴 수 없는 버튼**이라는 사실 — 누르기 전에 말해야 한다.
///
/// 서버에 **도착 취소 API 가 없다.** 그리고 `b16551b7` 부터 도착을 누른 사람은 **방을 나갈 수 없다**
/// (409 `ARRIVED_MEMBER_CANNOT_LEAVE`) — 도착한 멤버가 곧 탑승자이고 택시비 정산 대상이라
/// 장부에서 빠질 수 없기 때문이다. 즉 이 버튼이 지금 **유일하게 사용자를 방에 묶는 동작**이다.
///
/// 예전에는 묶는 것이 「약속 확정」이었고(`MEETING_CONFIRM_HELP` 가 그걸 말하고 있었다) 도착은
/// 노쇼를 면하는 신고에 가까웠다. 서버가 그 둘을 맞바꿨다 — 확정은 나가기를 막지 않고, 도착이 막는다.
let ARRIVE_LOCKS_IN_NOTICE = "도착을 알리면 이 방에서 나갈 수 없어요. 취소할 수 없고, 출발하면 방이 끝나요"

/// 「출발」을 누를 수 있는가 — 확정됐고 · **내가 도착했고** · 약속 시간이 지났고 · **내가 방장이다**.
///
/// ### 방장 전용이다 ★ (서버가 `b16551b7` 에서 바꿨다)
/// 오래 아니었다 — 도착한 멤버면 누구나 눌러 방을 끝낼 수 있었고, 이 주석은 「방장 조건을 베껴 오면
/// **방장이 늦는 방이 영원히 출발하지 못한다**」고 경고하고 있었다. 서버가 그 트레이드오프를 반대로
/// 골랐다(「출발은 도착한 방장만 누른다」). 그래서 지금 **방장이 오지 않는 방은 실제로 출발할 수 없고**,
/// 앱이 할 수 있는 일은 그 사실을 비방장에게 **말해 주는 것**뿐이다(`MeetingStage.departByHost`).
///
/// 방장 조건을 빼면 비방장에게 403 `NOT_PARTY_HOST` 로만 끝나는 버튼을 띄운다. 숨기는 쪽이 맞다 —
/// 그 자리에는 누가 눌러야 하는지를 말하는 안내문이 들어간다.
///
/// ### 경계
/// `now ≥ 약속 시간` 이면 참이다. 약속 시간 **정각이 참**이다(서버는 약속 시간 전에만 409
/// `MEETING_NOT_STARTED` 를 던진다). 파싱할 수 없는 `departureAt` 은 거짓 — 같은 이유다.
///
/// 멤버 2명 이상 조건(서버 `NOT_ENOUGH_MEMBERS`)은 여기서 보지 않는다. 이 단계에 닿으려면 방이
/// 확정돼 있어야 하고, 확정 자체가 2명 이상에서만 되기 때문이다 — 같은 조건을 두 번 세우면 한쪽만
/// 서버를 따라가게 된다. 그 사이 누군가 나가면 서버가 409 로 막고 `departFailureMessage` 가 받는다
/// (확정 방에서 혼자 남으면 서버가 방을 닫으므로 실제로는 `MeetingStage.closed` 로 간다).
func canDepartParty(ride: Ride, now: Date) -> Bool {
    meetingStage(ride: ride, now: now) == .departByMe
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

/// **아직 도착하지 않은** 멤버 수 — 「출발」을 누르면 **그 방의 탑승자에서 빠지는 사람 수**다.
///
/// 예전에는 「노쇼로 기록될 사람 수」였다. 서버가 노쇼 기능을 통째로 지웠지만(`b16551b7`, V37)
/// **대가가 사라진 건 아니다**: 서버는 「도착을 누른 멤버 = 탑승자」로 세므로(`Party.riderIds`)
/// 미도착자는 탑승 기록·탑승 횟수·**택시비 정산 대상**에서 함께 빠진다. 제재는 없어지고 **기록이
/// 남는 쪽**으로 바뀐 것이다.
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
/// (`departHostNotice` 와 같은 자리·같은 이유).
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
/// 네 가지가 전부 서버 계약이다: ① 확정하면 모집이 끝난다(ACTIVE→COMPLETED) ② 한 번만 정할 수 있다
/// (409 `ALREADY_CONFIRMED`) ③ 도착은 **약속 10분 전부터**(`ARRIVAL_NOT_OPEN`) ④ 출발은 **약속 시각
/// 뒤**, 그리고 **도착한 방장만**(`MEETING_NOT_STARTED`·`NOT_PARTY_HOST`).
///
/// ### 「그 뒤로는 아무도 방을 나갈 수 없다」를 **지웠다** ★
/// 오래 이 줄의 핵심이었다(「②가 사용자에게 가장 무겁다」고 적혀 있었다). 서버가 그 규칙을 버렸다
/// (`b16551b7`: 「확정 방에서도 나갈 수 있고, 확정 방에서 혼자 남으면 닫는다」). 지금 나가기를 막는
/// 것은 **도착을 누른 본인**뿐이고(`ARRIVE_LOCKS_IN_NOTICE`), 그 말은 이 자리가 아니라 도착 버튼
/// 앞에 있어야 한다 — 여기 남겨 두면 **서버가 허용하는 일을 못 한다고 말하는** 거짓이 되고, 그
/// 거짓을 믿은 사람은 못 가게 된 방에 그대로 묶여 있는다.
///
/// 「노쇼로 기록돼요」도 함께 지웠다 — 노쇼 기능이 서버에서 사라졌다(V37). 그 자리를 10분의 창
/// (③④)이 메운다: 「확정하면 모집이 끝난다」만 말하면 **그래서 어떻게 끝내는지**를 모르고, 약속이
/// 깨져 아무도 가지 않으면 방이 열린 채 남아 서버가 다른 방 합류·방 만들기·예약을 전부 막는다
/// (`ALREADY_JOINED_OTHER_PARTY`). 끝내는 길을 **들어가기 전에** 말하는 것이 유일한 방어다.
let MEETING_CONFIRM_HELP =
    "약속 시간을 정하면 모집이 끝나고 시간은 바꿀 수 없어요. 약속 10분 전부터 「출발지 도착했어요」를 " +
        "누를 수 있고, 약속 시간이 지나면 도착한 방장이 「출발」을 눌러 방이 끝나요"

/// 약속 시간 휠 위에 붙는 물음. 휠이 「오후 2:05」처럼 **시각**을 보여 준다.
let MEETING_TIME_PROMPT = "몇 시에 만날까요?"

/// 휠에 왜 10분 뒤부터 1시간 뒤까지만 있는지 — 서버가 그렇게 받는다(`meetingTimeOptions`). 없는 제약을 말하지
/// 않는다. 상한만 말하면 사용자는 「3분 뒤」가 왜 없는지 모르고, 5분 단위를 말하지 않으면 「2:03」을 찾는다.
let MEETING_TIME_LIMIT_NOTE = "약속 시간은 지금부터 10분 ~ 1시간 사이에서 5분 단위로 고를 수 있어요"

/// 약속 시간 시트의 확정 버튼 — **고른 시각을 되읽는다**(「오후 2:05에 만나기」). 확정은 한 번뿐이라
/// (409 `ALREADY_CONFIRMED`) 누르는 버튼에 그 시각을 적는다. 버튼에 적힌 시각이 그대로 서버로 간다 — 휠이 가리키는
/// 값 하나를 버튼과 요청이 함께 쓴다(예전에 제목과 요청이 시계를 따로 읽어 「오전 10:59에 만날까요?」로 묻고 11:00 으로
/// 확정된 적이 있다, 실측 2026-11-06).
func meetingConfirmButtonText(timeLabel: String?) -> String {
    timeLabel.map { "\($0)에 만나기" } ?? "이 시간으로 정하기"
}

/// 약속 시간 시트 본문 — `MEETING_CONFIRM_HELP` 와 같은 사실을 되읽어 준다(누르기 직전이 마지막 기회다).
///
/// 「그 뒤로는 아무도 방을 나갈 수 없다」·「노쇼로 기록돼요」를 지운 근거는 `MEETING_CONFIRM_HELP` 와
/// 같다 — 서버가 두 규칙을 버렸고, 남겨 두면 **마지막 확인 화면이 거짓을 말한다.**
let MEETING_CONFIRM_DIALOG_BODY =
    "정하면 모집이 끝나고 모두에게 약속 시간이 보여요. 시간은 다시 바꿀 수 없어요. " +
        "약속 10분 전부터 도착을 알리고, 약속 시간이 지나면 도착한 방장이 「출발」을 눌러 방이 끝나요"

/// 도착 창이 아직 안 열렸을 때. **숫자를 말해 줘야** 언제 다시 보면 되는지 알 수 있다.
let ARRIVE_NOT_OPEN_NOTICE = "약속 10분 전부터 「출발지 도착했어요」를 누를 수 있어요"

/// 도착을 알린 뒤 · 약속 시간 전 — **10분의 창**을 설명하는 자리다.
///
/// 서버가 도착과 출발의 문을 **다른 시각에** 연다: 도착은 약속 10분 전부터(`ARRIVAL_NOT_OPEN`),
/// 출발은 약속 시각 **뒤**부터(`MEETING_NOT_STARTED`). 그 사이 최대 10분 동안 사용자는 **할 일이
/// 없는데 버튼도 없는** 상태로 서 있다. 아무 말도 하지 않으면 「눌렀는데 아무 일도 안 일어났다」로 읽힌다.
///
/// ### 방장 여부로 갈린다 ★
/// 출발은 `b16551b7` 부터 **방장 전용**이다. 비방장에게 「약속 시간이 되면 출발할 수 있어요」라고
/// 하면 **지킬 수 없는 약속**이 된다 — 그 사람의 화면에는 약속 시간이 지나도 버튼이 생기지 않고
/// (`MeetingStage.departByHost`), 그때 「왜 나만 안 되지」에 답할 자리를 미리 잃는다.
func arrivedWaitingNotice(isHost: Bool) -> String {
    if isHost {
        "도착했다고 알렸어요. 약속 시간이 지나면 「출발」을 눌러 방을 끝낼 수 있어요"
    } else {
        "도착했다고 알렸어요. 약속 시간이 지나면 방장이 「출발」을 눌러요"
    }
}

/// 약속 시간이 지났는데 **내가 아직 도착을 알리지 않았을 때**.
///
/// 이 자리가 비어 있으면 그 사람은 남들에게만 보이는 「출발」을 두고 영문을 모른다. 서버 조건
/// (`NOT_ARRIVED`)을 그대로 말해 주는 것이 가장 짧은 설명이다.
let DEPART_NEEDS_ARRIVAL_NOTICE = "약속 시간이 됐어요. 도착했다고 알린 사람만 출발할 수 있어요"

/// 약속 시간이 지났고 · 내가 도착했는데 · **내가 방장이 아니라 「출발」이 없을 때**
/// (`MeetingStage.departByHost`).
///
/// ### 이 안내문은 옛 `finishHostNotice` 를 **옮겨 온 것**이다 ★
/// 그 함수는 비방장이 「합승 완료」가 있던 자리에서 읽던 안내문이었고(「다 타면 방장 ○○님이
/// 「합승 완료」를 눌러 방을 끝내요」), 서버가 `/finish` 를 없애면서 가리킬 버튼을 잃었다. 그런데
/// **그 역할이 필요한 자리가 새로 생겼다**: 출발이 방장 전용이 되면서(`b16551b7`) 도착했고 시간도
/// 됐는데 **내 화면에만 버튼이 없는** 상태가 만들어졌다. 지우지 않고 그 자리로 옮긴 이유가 그것이다 —
/// 숨기기만 하면 할 일이 하나도 없는 화면이 되고, 「왜 나만 출발이 안 되지」에 답할 자리가 없다.
///
/// `hostNickname` 이 있으면 **이름으로 부른다**(`hostDisplayNameOrNull`).
/// 못 쓰는 경우는 셋이다 — 방장의 유저 요약이 없거나(식별자가 빈 값), 방장이 **탈퇴했거나**
/// (soft delete: 식별자는 살아 있고 닉네임만 「탈퇴한 사용자」로 가려진다), 아무도 방장으로 지목되지
/// 않았거나. 그때는 지어내지 않고 **조건**을 말한다: 서버 `Party.hostId()` 가 현재 멤버 중
/// `min(joinedAt, memberId)` 라 「가장 먼저 참여한 분」은 사실이다(`meetingHostNotice` 와 같은 처방).
///
/// 「잠시 후 다시 시도」류는 넣지 않는다 — 기다려서 풀리는 일이 아니다. 방장이 와서 도착을 누르고
/// 출발하거나, 방장이 나가 내게 승계되어야 바뀐다.
func departHostNotice(hostNickname: String?) -> String {
    if let hostNickname, !hostNickname.isBlank {
        "약속 시간이 됐어요. 도착한 방장 \(hostNickname)님이 「출발」을 눌러 방을 끝내요"
    } else {
        "약속 시간이 됐어요. 도착한 방장(가장 먼저 참여한 분)이 「출발」을 눌러 방을 끝내요"
    }
}

/// 위치 권한이 없을 때 도착 버튼 자리에 들어가는 안내 — **왜 필요한지**를 말한다.
///
/// 21 은 진입할 때 권한을 자동 요청하지 않는다(대기 화면의 본질이 지도가 아니다). 그래서 도착
/// 단계에 처음 닿은 사람이 권한을 거부해 둔 상태일 수 있고, 그때 비활성 버튼만 두면 왜 안 되는지
/// 알 수 없다 — 17 탐색의 `LocationPermissionNotice` 와 같은 처방이다(안내 + 다시 요청할 버튼).
///
/// 숫자가 방 종류로 갈리므로 상수가 아니라 함수다(`arrivalRadiusMeters`) — 예약 방에 「100m」를
/// 적으면 역 중심점에서 400m 까지 받아 주는 서버보다 **앱이 더 엄하게 말한다.**
func arriveNeedsPermissionNotice(roomType: RoomType) -> String {
    "도착을 알리려면 위치 권한이 필요해요. 서버가 출발지에서 \(arrivalRadiusMeters(roomType: roomType))m 안인지 확인해요"
}

/// 권한은 있는데 아직 첫 좌표가 안 들어왔다. 사용자가 할 일이 없으므로 **기다리라고만** 한다.
let ARRIVE_LOCATING_LABEL = "현재 위치를 확인하는 중…"

/// 「출발」 확인 다이얼로그 본문 — **미도착자에게 무슨 일이 생기는지**를 누르기 전에 말한다.
///
/// 이 다이얼로그가 이 작업에서 가장 조심한 자리다. 「출발」은 되돌릴 수 없고, 그 순간 도착하지 않은
/// 사람은 **그 방의 탑승자에서 빠진다.** 누르는 사람은 보통 자기 손해가 아니라 **남의 손해**를 만들게
/// 되므로, 숫자를 보여 주지 않으면 그 무게를 알 수 없다.
///
/// ### 「노쇼로 기록돼요」를 다시 썼다 ★
/// 예전 문구는 「아직 도착하지 않은 N명은 노쇼로 기록돼요 — 약속 시간부터 노쇼 횟수 × 24시간 동안
/// 방·예약을 만들거나 참여할 수 없어요」였다. 서버가 **노쇼 기능을 통째로 지웠다**(`b16551b7`, V37 이
/// 테이블까지 떨어뜨린다) — 그 제재는 이제 **존재하지 않는 일**이라, 남겨 두면 겁을 주고 그 겁이
/// 거짓이다.
///
/// 그렇다고 대가가 사라진 건 아니다. 서버는 「도착을 누른 멤버 = 탑승자」로 세므로(`Party.riderIds`)
/// 미도착자는 **탑승 기록 · 탑승 횟수 · 택시비 정산 대상**에서 함께 빠진다. 같이 탔는데도 정산
/// 장부에 이름이 없는 것이 지금의 대가다. 그래서 **겁주지 않고 사실만** 적는다 — 「제외됩니다」같은
/// 처벌조가 아니라 「빠져요」로 적고, 복구 방법을 약속하지 않는다(서버에 그런 길이 없다).
///
/// `notArrivedCount` 가 0 이면 그 문장을 **아예 뺀다**. 아무도 빠지지 않는데 빠진다고 말하면 다음에
/// 정말 미도착자가 있을 때 같은 문구가 무게를 잃는다.
func departConfirmMessage(notArrivedCount: Int) -> String {
    if notArrivedCount <= 0 {
        "모두 도착했어요. 출발하면 같이 탄 사람 모두의 방이 끝나요"
    } else {
        "같이 탄 사람 모두의 방이 끝나요. 아직 도착하지 않은 \(notArrivedCount)명은 "
            + "탑승 기록과 택시비 정산에서 빠져요"
    }
}

/// 「도착 2/3」 — 확정된 방에서 사람들이 가장 자주 확인하는 숫자다. 확정 전에는 뜻이 없어 nil.
func arrivalCountLabel(ride: Ride) -> String? {
    if !ride.isConfirmed || ride.members.isEmpty { return nil }
    return "도착 \(arrivedCount(ride: ride))/\(ride.members.count)"
}

// ─────────────────────────── 실패 문구 ───────────────────────────

/// **공통 규칙** — 세 액션(확정·도착·출발)의 실패 문구는 전부 이 모양을 따른다
/// (`leaveFailureMessage` 가 세운 선례다 — 넷째였던 「합승 완료」의 `finishFailureMessage` 는
/// 서버가 `/finish` 를 없애면서 함께 지웠다).
///
/// 1. **서버 코드로만 가른다.** HTTP 상태로 추측하지 않는다 — 확정은 403 이 두 가지 뜻
///    (`NOT_PARTY_HOST`/`NOT_PARTY_MEMBER`)이고 409 가 네 가지라, 상태로 고르면 반드시 절반은
///    틀린 말이 된다. 분기 근거는 도메인이 코드를 한 번 걸러 준 `is…` 프로퍼티다.
/// 2. **모르는 코드는 일반 문구로 떨어진다.** 서버가 `MatchingErrorCode` 를 늘려도 앱이 지어내지
///    않는다 — 모른다고 하는 편이 낫다. 코드가 없는 실패(네트워크·본문 파싱 실패)도 같은 자리다.
/// 3. **403·409 에 「다시 시도」류를 붙이지 않는다.** 다시 눌러도 같은 답이다. 방 사정이 바뀌어야
///    풀린다(`MeetingFailureMessageTest` 가 이 금지를 못 박는다 — 원래 `FinishFailureMessageTest` 가
///    세운 규칙이고, 그 파일은 「합승 완료」와 함께 사라졌다).
/// 4. **서버가 하는 일만 적는다.** 반경은 서버가 재는 값이므로 그대로 말하고(`arrivalRadiusMeters`),
///    「가까워지면 자동으로 알려 드려요」 같은 없는 기능은 말하지 않는다.
let CONFIRM_FAILED_MESSAGE = "약속 시간을 정하지 못했어요"

/// 「약속 시간 정하기」 실패 → 사용자 문구.
///
/// | 사유 | 서버 코드(HTTP) | 사용자가 할 일 |
/// |---|---|---|
/// | 5분~1시간을 벗어났다 | `INVALID_MEETING_TIME` (400) | 다른 프리셋을 고른다 |
/// | 방장이 아니다 | `NOT_PARTY_HOST` (403) | 가장 먼저 참여한 사람에게 부탁한다 |
/// | 멤버가 아니다 | `NOT_PARTY_MEMBER` (403) | 홈에서 진행 중인 방을 확인한다 |
/// | 실시간 방이 아니다 | `NOT_REALTIME_PARTY` (409) | 이 방에서는 할 수 없다 |
/// | 이미 정해졌다 | `ALREADY_CONFIRMED` (409) | 할 일이 없다(화면이 곧 확정 상태로 바뀐다) |
/// | 방이 닫혔다 | `PARTY_CLOSED` (409) | 홈으로 돌아간다 — 방이 이미 닫혔다 |
/// | 2명 미만 | `NOT_ENOUGH_MEMBERS` (409) | 사람이 더 모여야 한다 |
/// | 방 없음 | `PARTY_NOT_FOUND` (404) | 홈으로 돌아간다 |
/// | 그 밖·네트워크 | 코드 없음 | `CONFIRM_FAILED_MESSAGE` |
///
/// 「모집 단계가 아니다」 줄의 코드가 `PARTY_NOT_RECRUITING` 에서 `PARTY_CLOSED` 로 **바뀌었다** —
/// 서버가 `Party` 의 단계 검사를 `validateOpen()` 하나로 묶으면서 코드를 통일했다(`b16551b7`).
/// 사용자 문구는 그대로다(어느 이름이든 사실은 「이미 끝난 방」이다).
///
/// `INVALID_MEETING_TIME` 만 **행동을 권한다** — 400 이고, 휠에서 다시 고르면 실제로 통과한다.
/// **「더 가까운」이 아니라 「다시」인 것이 요점이다**: 서버 범위(5분 ~ 1시간)를 **양쪽에서** 어길 수 있다 —
/// 시트를 5분 넘게 열어 두면 가장 이른 시각이 하한 아래로 내려가고, 기기 시계가 서버보다 앞서 있으면 가장
/// 늦은 시각이 상한을 넘는다. 그때 「더 가까운 시간」을 권하면 반대 방향으로 보내게 된다.
/// 그래서 범위를 그대로 적고 다시 고르게 한다.
///
/// 방장 안내가 「가장 먼저 참여한 분」인 건 서버가 방장을 그렇게 정하기 때문이다
/// (`Party.hostId()` = 현재 멤버 중 `min(joinedAt, memberId)`). **이름을 쓰지 않는다** — 이 403 은 내
/// 스냅샷이 가리킨 방장이 서버 기준으로 더 이상 방장이 아니라는 뜻이라, 그 스냅샷으로 이름을 부르면
/// **틀린 사람에게 부탁하라고 말하게 된다**(`departFailureMessage` 의 같은 403 과 같은 근거·같은 표현).
func confirmFailureMessage(e: PartyConfirmException) -> String {
    if e.isInvalidMeetingTime { return "약속 시간은 지금부터 10분 ~ 1시간 뒤여야 해요. 다시 골라 주세요" }
    if e.isNotHost { return "방장만 약속 시간을 정할 수 있어요. 가장 먼저 참여한 분에게 부탁해 주세요" }
    if e.isNotMember { return "이 방의 참여자가 아니에요. 홈에서 진행 중인 방을 확인해 주세요" }
    if e.isNotRealtimeParty { return "실시간으로 모인 방에서만 약속 시간을 정할 수 있어요" }
    if e.isAlreadyConfirmed { return "이미 약속 시간이 정해진 방이에요" }
    if e.isPartyClosed { return "이미 끝난 방이에요. 홈으로 돌아가 주세요" }
    if e.isNotEnoughMembers { return "2명 이상 모여야 약속 시간을 정할 수 있어요" }
    if e.isPartyNotFound { return "이미 사라진 방이에요. 홈으로 돌아가 주세요" }
    return CONFIRM_FAILED_MESSAGE
}

/// **방의 지금 출발지를 「만남 장소」로 그대로 보낼 수 있는가** — 셋이 다 있을 때만 non-nil.
///
/// ### 왜 타입으로 막는가 ★
/// 서버 `confirm` 은 `departureAt` 외에 **위도·경도·장소 이름을 전부 `@NotNull`/`@NotBlank` 로**
/// 받는다(`2732cc75`). 그런데 `Ride.originLat`·`Ride.originLng` 는 **옵셔널**이다 — 목록·추천
/// 응답으로 만든 `Ride` 에는 좌표가 없다.
///
/// | 없을 때 어떻게 하나 | 결과 |
/// |---|---|
/// | 0.0 으로 채워 보낸다 | 적도 한가운데 → 400 `OUT_OF_SERVICE_AREA`. **방을 끝낼 길이 사라진다** |
/// | 빈 이름으로 보낸다 | 400 `INVALID_REQUEST` — 어느 사유 코드도 아니라 일반 문구로만 보인다 |
/// | 보내지 않는다(이쪽) | 화면이 사실을 말하고 상세를 다시 읽는다 → 좌표가 채워지면 다시 누를 수 있다 |
///
/// 21 대기 화면이 보는 `Ride` 는 **상세 조회나 SSE 스냅샷**에서 오므로 실제로는 늘 채워져 있다.
/// 그래도 막는 이유는 **타입이 그걸 보장하지 않기** 때문이다: 지금은 참이어도 누군가 목록에서 만든
/// `Ride` 를 이 화면에 흘려 넣으면 컴파일은 통과하고 사용자는 영구 400 을 맞는다.
struct MeetingPlace: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let name: String
}

func meetingPlaceOrNull(ride: Ride) -> MeetingPlace? {
    guard let lat = ride.originLat, let lng = ride.originLng, !ride.origin.isBlank else { return nil }
    return MeetingPlace(latitude: lat, longitude: lng, name: ride.origin)
}

/// 방의 출발지 좌표를 몰라 확정 요청을 **보내지 않았을 때**의 문구(`meetingPlaceOrNull` 이 nil).
///
/// 「다시 시도해 주세요」를 붙이는 유일한 실패 문구다 — 다른 실패들과 달리 **정말로 다시 누르면
/// 풀린다**: 화면이 같은 순간 방 상세를 다시 읽고, 상세 응답에는 좌표가 들어 있다.
let CONFIRM_PLACE_UNKNOWN_MESSAGE = "출발지 위치를 아직 못 받았어요. 잠시 뒤에 다시 시도해 주세요"

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
/// 그래서 「멀다」는 사실을 사용자에게 말해 줄 수 있는 자리가 **여기 하나뿐**이다. 숫자를 적는 이유도
/// 같다: 「조금 더 가까이」만으로는 10m 를 더 가야 하는지 300m 를 더 가야 하는지 모른다.
/// 그 숫자는 앱이 고른 값이 아니라 **서버가 PostGIS 로 재는 값**이다.
///
/// ⚠️ **그 숫자가 방 종류로 갈린다**(`arrivalRadiusMeters`) — 그래서 `roomType` 을 받는다. 오래
/// 「100m」로 박혀 있었는데, 서버가 예약 방을 400m 로 넓힌 뒤로(`b16551b7`) 그 문구는 예약 방
/// 사용자에게 **거짓**이다: 역 중심점에서 300m 떨어진 사람에게 서버는 도착을 받아 주면서 앱은
/// 「100m 안에 있어야 한다」고 적는다.
///
/// 「다시 시도」류를 넣지 않는다. 400 이지만 같은 자리에서 다시 눌러도 같은 400 이고, 사용자가 할 일은
/// 재시도가 아니라 **이동**이다.
///
/// - Parameter roomType: 이 방의 종류. 반경 숫자를 가른다 — **기본값을 두지 않는다**(기본값을 두면 예약
///   방에서 빠뜨렸을 때 화면이 조용히 틀린 숫자를 말한다)
func arriveFailureMessage(e: PartyArriveException, roomType: RoomType) -> String {
    if e.isTooFarFromDeparture {
        return "출발지에서 \(arrivalRadiusMeters(roomType: roomType))m 안에 있어야 도착을 알릴 수 있어요. 출발지로 더 가까이 가 주세요"
    }
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
/// | **방장이 아니다** | `NOT_PARTY_HOST` (403) | 가장 먼저 참여한 분에게 부탁한다 |
/// | 약속 시간 전 | `MEETING_NOT_STARTED` (409) | 약속 시간까지 기다린다 |
/// | 2명 미만 | `NOT_ENOUGH_MEMBERS` (409) | 혼자서는 출발할 수 없다 |
/// | 확정 전이다 | `PARTY_NOT_CONFIRMED` (409) | 약속 시간이 정해져야 한다 |
/// | 방이 닫혔다 | `PARTY_CLOSED` (409) | 홈으로 돌아간다 |
/// | 멤버가 아니다 | `NOT_PARTY_MEMBER` (403) | 홈에서 진행 중인 방을 확인한다 |
/// | 방 없음 | `PARTY_NOT_FOUND` (404) | 홈으로 돌아간다 |
/// | 그 밖·네트워크 | 코드 없음 | `DEPART_FAILED_MESSAGE` |
///
/// ### `NOT_PARTY_HOST` 가 **새로 생긴 줄**이다 ★
/// 출발은 `b16551b7` 부터 방장 전용이다 — 예전에는 도착한 멤버면 누구나였고, 그래서 이 표에 그
/// 403 이 없었다. 화면이 비방장에게 버튼을 **숨기지만**(`canDepartParty`) 방장은 멤버가 들고 날
/// 때마다 승계되고 그 신호는 `member-left` 한 번뿐이라, 내 스냅샷이 낡으면 이 403 이 남는다.
/// **이름을 쓰지 않는다** — 이 403 은 「내 스냅샷의 방장이 서버 기준으로는 더 이상 방장이 아니다」는
/// 뜻이라, 그 스냅샷으로 이름을 부르면 **틀린 사람에게 부탁하라고** 말하게 된다
/// (버튼이 보이는 사람에게 이름으로 안내하는 자리는 `departHostNotice` 쪽이다).
///
/// `NOT_ARRIVED` 문구가 **다음 행동을 알려 주는** 유일한 가지다 — 그 사람은 바로 위의
/// 「출발지 도착했어요」를 누르면 된다. 버튼 이름을 그대로 적는 이유: 「도착을 알려야 한다」만
/// 적으면 어디를 눌러야 하는지 찾아야 한다. 나머지는 기다리거나 떠나는 것 말고 할 일이 없으므로
/// 행동을 권하지 않는다(없는 길을 권하면 그게 거짓이다).
///
/// 「다시 시도」류는 한 줄도 없다 — 전부 다시 눌러도 같은 답이다.
func departFailureMessage(e: PartyDepartException) -> String {
    if e.isNotArrived { return "먼저 「출발지 도착했어요」를 눌러야 출발할 수 있어요" }
    if e.isNotHost { return "방장만 출발할 수 있어요. 가장 먼저 참여한 분에게 부탁해 주세요" }
    if e.isMeetingNotStarted { return "약속 시간이 지나야 출발할 수 있어요" }
    if e.isNotEnoughMembers { return "2명 이상 모여야 출발할 수 있어요" }
    if e.isNotConfirmed { return "아직 약속 시간이 정해지지 않았어요" }
    if e.isPartyClosed { return "이미 끝난 방이에요. 홈으로 돌아가 주세요" }
    if e.isNotMember { return "이 방의 참여자가 아니에요. 홈에서 진행 중인 방을 확인해 주세요" }
    if e.isPartyNotFound { return "이미 사라진 방이에요. 홈으로 돌아가 주세요" }
    return DEPART_FAILED_MESSAGE
}
