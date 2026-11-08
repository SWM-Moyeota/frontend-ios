import Foundation
import MoyeotaDomain
import PresentationCore

// **예약 방**(서버 `RoomType.RESERVED`)을 만드는 데 쓰는 판정과 문구를 모아 둔다 — 16 도착지 확인의
// 출발 모드·정원·시각 슬롯·보내는 값·실패 문구.
//
// 17 탐색·20 합류 확인과 **함께 쓰는 몫**(한국 달력의 7일 창 `KOREA_ZONE`·`RESERVATION_WINDOW_DAYS`,
// 날짜·시각 문구, 나갈 수 없다는 안내)은 `PresentationCore/ReservationRules.swift` 에 있다.
//
// ### 왜 화면에서 떼어 내는가
// 이 파일의 규칙은 전부 **시계와 달력**에 달려 있다 — 「지금부터 7일 안」·「오늘~7일 뒤」·「예약은
// 2명부터」. 경계를 한 칸 잘못 잡아도 스크린샷에는 아무것도 보이지 않는다: 7일 뒤 23:30 을 고를 수
// 있는 화면과 올바른 화면은 눈으로 구분할 수 없고, 그 차이는 **서버 400 `INVALID_DEPARTURE_TIME`**
// 으로만 드러난다. 그래서 판정을 SwiftUI 를 모르는 순수 함수로 빼고 `now` 를 **인자로** 받는다 —
// 어느 함수도 안에서 `Date()` 를 부르지 않는다(부르면 테스트가 경계를 고정할 수 없다).
//
// 21 약속 확정의 `MeetingFlow.swift`·34 기록의 `RideHistoryDisplay.swift` 와 같은 자리·같은 이유다.
// 화면을 모르는 파일이라 단위 테스트(`ReservationRulesTest`)가 그냥 돈다.
//
// ### 왜 홈(16)에 있는가 — 17 탐색이 쓰는 몫만 떼어 냈다
// 예약의 **시간 계약**은 방을 만드는 쪽(16 도착지 확인)이 서버와 맺는다: 「지금부터 7일 안」이
// 생성의 조건이고, 검색의 「오늘~7일 뒤」는 **그 계약의 그림자**다. 두 곳이 각자 7을 들고 있으면
// 한쪽만 서버를 따라가므로, 원본은 창을 정하는 상수와 날짜 계산을 이 파일 한 곳에 두고 탐색이
// import 한다. 기능 모듈끼리는 서로 import 할 수 없어 그 몫만 PresentationCore 로 옮겼다
// (`headcountLabel` 과 같은 선례) — 창의 숫자는 여전히 한 곳(`RESERVATION_WINDOW_DAYS`)에만 있다.
//
// ### 서버가 최종 판정이다
// 여기 있는 게이트는 **보낼 수 없는 값을 사용자가 고르지 못하게** 하려는 것이지 서버 검증의
// 사본이 아니다. 특히 **「출발 2시간 안에 다른 예약」(409 `PARTY_TIME_CONFLICT`)은 앱이 예측하지
// 않는다** — 내 다른 예약 목록을 이 화면이 들고 있지 않고, 들고 있어도 낡는다. 그건 막는 대신
// 거절당했을 때 **사유별 문구**로 받는다(`reservationOpenFailureMessage`).

/// 시각 칩의 간격(분). 30분 단위인 이유는 **고를 수 있는 값의 수**다 — 10분 단위면 하루 144개,
/// 1시간 단위면 약속 시간을 30분 뒤로 미루지도 못한다. 자유 입력(시간 피커)을 두지 않는 근거는
/// `MEETING_PRESET_MINUTES` 와 같다: 피커를 주면 사용자가 **스스로 400 을 만들 수 있다**(지난 시각·
/// 7일 밖). 칩만 두면 고를 수 있는 모든 값이 **구성상** 유효하다.
let RESERVATION_SLOT_MINUTES = 30

/// 가장 이른 슬롯까지 두는 여유 — **지금부터 10분**.
///
/// 두 가지를 산다. ① 왕복 시간과 시계 스큐: 「1분 뒤」 슬롯은 요청이 서버에 닿는 사이 과거가 되어
/// 400 `INVALID_DEPARTURE_TIME` 이 된다(`meetingPresetAt` 이 분 단위로 내림해 여유를 버는 것과 같은
/// 자리다). ② 뜻: 5분 뒤에 타려는 사람에게 필요한 것은 예약 방이 아니라 **지금 출발**이고, 그쪽은
/// 경로·요금 추정까지 받는다.
let RESERVATION_MIN_LEAD_MINUTES = 10

/// 16 도착지 확인에서 고른 **출발 시점의 종류**.
///
/// 두 값이 서로 다른 엔드포인트로 간다 — `now` 는 `POST /matching/rooms`(실시간), `scheduled` 는
/// `POST /matching/reservations`(예약). 그래서 정원 범위·보여 주는 추정·실패 문구가 전부 갈린다.
/// 「예약 여부」를 불리언으로 두지 않은 이유는 그 분기들이 화면 곳곳에 있어 `switch` 가 빠진 가지를
/// 잡아 주는 편이 안전하기 때문이다(21 의 `MeetingStage` 와 같은 판단).
enum DepartureMode: CaseIterable, Sendable {
    /// 지금 모집을 시작하는 실시간 방 — 이 앱이 지금까지 만들던 유일한 종류다.
    case now

    /// 출발 시각을 정해 두는 예약 방. 서버 `RESERVED`.
    case scheduled
}

/// 「출발 시각」 칩 두 개의 문구. `DepartureMode.now` 가 기본값이라 **지금까지의 동작이 기본**이다.
func departureModeLabel(mode: DepartureMode) -> String {
    switch mode {
    case .now: "지금 출발"
    case .scheduled: "시간 정하기"
    }
}

/// 고를 수 있는 정원 — **예약은 2~3, 실시간은 1~3**.
///
/// 서버가 그렇게 받는다: 실시간 `Capacity` 는 1~3 인데 예약은 2 이상이어야 하고(`capacity 2~3`),
/// 벗어나면 400 `INVALID_CAPACITY` 다. 혼자 타는 방을 **미리** 예약하는 것은 서버가 인정하지 않는
/// 쓰임이라(합승이 아니다) 선택지에서 지운다 — 띄워 놓고 400 을 맞게 하지 않는다.
///
/// 1 을 고른 채 「시간 정하기」로 바꾸는 길이 **반드시 있다**(기본값은 3 이지만 사용자는 1 을 고를 수
/// 있다). 그 상태를 그대로 보내면 400 이므로 `capacityFor` 가 끌어올린다.
func capacityChoices(mode: DepartureMode) -> [Int] {
    switch mode {
    case .now: [1, 2, 3]
    case .scheduled: [2, 3]
    }
}

/// **지금 고른 정원을 이 모드에서 보낼 수 있는 값으로 접는다.**
///
/// 「1명」을 고른 뒤 「시간 정하기」로 바꾼 순간이 이 함수가 있는 이유다. 그 상태는 서버에 보낼 수
/// 없는데(400 `INVALID_CAPACITY`), 사용자가 정원 칩을 다시 건드릴 이유는 없다 — 화면에서 1 칩이
/// 사라졌을 뿐 자기가 고친 적이 없으니 2 로 바뀐 것도 모른다. 그래서 **고른 값을 지우지 않고**
/// (모드를 되돌리면 1 이 그대로 선택돼 있다) 전송·표시용 값만 범위 안으로 접고, 화면은 그 사실을
/// 한 줄로 말한다(`RESERVATION_CAPACITY_NOTICE`).
///
/// 범위를 벗어난 값은 **가장 가까운 유효값**이 된다(1 → 2). 0 이나 4 처럼 화면에 없는 값이 들어와도
/// 같은 규칙이다 — `coerceIn` 과 같은 뜻이고, 선택지가 연속 구간이라 그걸로 충분하다.
func capacityFor(mode: DepartureMode, selected: Int) -> Int {
    let choices = capacityChoices(mode: mode)
    guard let lowest = choices.first, let highest = choices.last else { return selected }
    return min(max(selected, lowest), highest)
}

/// 「시간 정하기」에서 정원 칩 아래 붙는 한 줄 — **1 칩이 사라진 이유**를 고르는 자리에서 말한다.
///
/// `soloCapacityNotice` 와 같은 자리·같은 모양(13pt Medium 보조 문구)이지만 뜻이 반대다: 저쪽은
/// 「1 을 골랐으니 혼자 간다」, 이쪽은 「예약에서는 1 을 고를 수 없다」. 서버 규칙을 그대로 적는다 —
/// 「왜 2명부터인가」를 설명하지 않는 이유는 앱이 그 이유를 모르기 때문이다(서버가 그렇게 받는다).
let RESERVATION_CAPACITY_NOTICE = "예약 방은 2명부터 만들 수 있어요"

/// 예약 방에 **경로·예상 요금·소요 시간이 없다**는 사실을 CTA 앞에서 말한다.
///
/// ### 이 문구가 이 작업에서 가장 조심한 자리다 ★
/// 16 모달은 지금까지 「예상 요금 1인 2,630원」과 「예상 N분 · 총 7,900원」을 보여 줬다. 그 값은
/// `POST /matching/routes`(좌표 두 개로 뽑는 추정)에서 오고, **예약에서도 호출은 성공한다** — 즉
/// 아무것도 고치지 않으면 화면은 예약 방에도 금액을 적는다. 그게 거짓이 되는 이유는 둘이다:
///
/// 1. **서버가 예약 방에 요금·경로·소요 시간을 넣지 않는다.** 만들어진 방은 세 값이 비어 있어
///    21 대기·22 상세에서 금액이 **사라진다** — 사용자는 2,630원을 보고 동의했는데 방에는 그 숫자가
///    없다. 어느 쪽이 참인지 알 길이 없는 어긋남이다.
/// 2. **그 추정은 「지금」의 값이다.** 3일 뒤 오후 6:30 의 요금·소요 시간을 지금의 교통으로 셈한
///    값이고, 서버는 그걸 그 방의 값으로 쓰지 않는다.
///
/// 그래서 숫자를 **감춘다**(0 원·「계산 중」 같은 자리값을 두지 않는다 — `RideHistoryFare` 가 1차 모드
/// 기록에서 요금 줄을 아예 그리지 않는 것과 같은 규칙). 대신 **왜 없는지**를 적는다: 자리가 비어
/// 있으면 사용자는 로딩 실패로 읽는다.
///
/// 지도의 경로선은 **지운 값이 아니다**. 그건 사용자가 찍은 두 핀 사이의 길 모양(기하)이고 시각·
/// 금액 예측이 아니다 — 어디로 가는 방인지 보여 주는 일은 예약에서도 참이다.
let RESERVATION_NO_ESTIMATE_NOTICE = "예약 방은 예상 요금과 소요 시간을 미리 알 수 없어요"

/// 출발 시각을 아직 고르지 않았다 — 비활성 CTA 옆에 **왜 못 누르는지**를 둔다(빈 비활성 버튼을 두지 않는다).
let RESERVATION_NEEDS_TIME_NOTICE = "출발 시각을 골라 주세요"

/// 그 날에 고를 수 있는 시각이 하나도 없다 — **늦은 밤의 「오늘」 칩**에서 나온다.
///
/// 오늘의 마지막 슬롯은 23:30 이고 가장 이른 슬롯은 「지금 + 10분」보다 뒤여야 하므로
/// (`RESERVATION_MIN_LEAD_MINUTES`) 23:20 을 넘기면 오늘 고를 수 있는 시각이 없다. 그때는
/// 「내일」부터 고르면 되고, 이 줄이 그 사실을 말한다 — 자리를 비워 두면 칩이 사라진 이유를 모른다.
///
/// 반대쪽 끝(7일 뒤)은 **비지는 않지만 짧아진다**: 그 날은 자정부터 「지금 시각」까지만 고를 수 있다
/// (`reservationTimeSlots` 의 둘째 경계).
let RESERVATION_NO_SLOT_NOTICE = "이 날은 고를 수 있는 시간이 없어요. 다른 날을 골라 주세요"

/// 그 날짜에 고를 수 있는 시각들 — **`RESERVATION_SLOT_MINUTES` 간격, 지금+`RESERVATION_MIN_LEAD_MINUTES`
/// 보다 뒤, 지금+`RESERVATION_WINDOW_DAYS`일 보다 앞**.
///
/// 두 경계가 각각 서버의 거절 하나를 지운다.
///
/// | 경계 | 없으면 |
/// |---|---|
/// | 지금 + 10분 보다 뒤 | 오늘 날짜에서 **이미 지난 시각**과 몇 분 뒤가 고를 수 있게 된다 → 400 `INVALID_DEPARTURE_TIME` |
/// | 지금 + 7일 보다 앞 | 7일 뒤 날짜의 **늦은 시각**이 창을 넘는다(지금이 09:00 이면 7일 뒤 09:30 은 이미 밖이다) → 같은 400 |
///
/// 둘째 경계가 눈에 안 보이는 쪽이다: 「7일 뒤」가 칩에 있으니 그 날은 아무 시각이나 될 것처럼
/// 보이는데, 실제로 허용되는 건 그 날 **자정부터 지금 시각까지**다. 그래서 마지막 날의 칩 목록은
/// 짧고, 아주 이른 시각(지금이 00:10 이전)에는 **비어 있다**(`RESERVATION_NO_SLOT_NOTICE`).
///
/// 경계는 **포함**이다: 정확히 「지금+7일」인 슬롯은 유효하다(서버가 `isAfter` 로 본다). 반대로
/// 여유 시간 쪽은 **초과**여야 한다 — 「지금+10분」 정각 슬롯은 왕복 시간에 먹힌다.
///
/// 두 경계는 원본 `Instant.plus` 처럼 **정확한 초**로 더한다(7일 = 7 × 86,400초). 서머타임이 없는
/// 한국 달력에서는 「7일 뒤 같은 벽시계 시각」과 같은 순간이다.
func reservationTimeSlots(
    date: LocalDate,
    now: Date,
    zone: TimeZone = KOREA_ZONE,
    stepMinutes: Int = RESERVATION_SLOT_MINUTES
) -> [LocalTime] {
    let step = max(stepMinutes, 1)
    let earliest = now.addingTimeInterval(TimeInterval(RESERVATION_MIN_LEAD_MINUTES * 60))
    let latest = now.addingTimeInterval(TimeInterval(RESERVATION_WINDOW_DAYS * 86_400))
    return stride(from: 0, to: 24 * 60, by: step)
        .compactMap { LocalTime(hour: $0 / 60, minute: $0 % 60) }
        .filter { time in
            let at = date.atTime(time, zone)
            return at > earliest && !(at > latest)
        }
}

/// 서버에 보낼 출발 시각 — ISO-8601 **순간** 문자열(`2026-11-09T09:30:00Z`).
///
/// 고른 것은 한국 달력의 날짜와 벽시계 시각이고, 서버가 받는 것은 `Instant` 다. 그 변환이 일어나는
/// 자리를 하나로 묶는다 — **오프셋 없는 로컬 시각(`"2026-11-09T18:30:00"`)은 400** 이고, 그 400 은
/// 어떤 사유 코드에도 걸리지 않아 일반 문구로 떨어진다(가장 찾기 어려운 실패다 —
/// `RideRepository.confirmMeeting` 주석의 ★ 참고).
///
/// `Date.ISO8601FormatStyle` 기본값은 UTC `Z` 표기이고 **초를 늘 적는다** — 실제 값은 `...T09:30:00Z` 다.
/// (원본 주석은 `Instant.toString` 이 초가 0 이면 `:00` 을 생략한다고 적었지만 사실이 아니다 —
/// `ISO_INSTANT` 는 초를 늘 적는다. `meetingPresetIso` 와 같은 판단.) 서버(Jackson `Instant`)는 어느
/// 쪽이든 같게 읽는다.
func reservationDepartureIso(
    date: LocalDate,
    time: LocalTime,
    zone: TimeZone = KOREA_ZONE
) -> String {
    date.atTime(time, zone).formatted(.iso8601)
}

/// 고른 출발 시각을 CTA 앞에서 **되읽어 준다** — `오늘 오후 6:30` · `11월 9일 (일) 오후 6:30`.
///
/// 날짜 칩과 시각 칩이 각각 떨어진 줄에 있어서, 두 선택이 합쳐져 무엇이 되는지 확인할 기회가 누르기
/// 직전의 이 한 줄뿐이다(`meetingConfirmTitle` 이 프리셋 「10분」을 시각으로 되읽어 주는 것과 같은
/// 이유). 예약 방은 만든 뒤 시간을 바꿀 수 없으므로 더 그렇다.
func reservationDepartureSummary(date: LocalDate, time: LocalTime, today: LocalDate) -> String {
    "\(reservationDateLabel(date: date, today: today)) \(reservationTimeLabel(time: time))"
}

/// 사유를 가릴 수 없는 예약 생성 실패의 일반 문구 — 네트워크 실패와 **모르는 코드**가 여기로 떨어진다.
/// `OPEN_FAILED_MESSAGE` 와 같은 모양이고 「예약 방」이라는 말만 다르다.
let RESERVATION_OPEN_FAILED_MESSAGE = "예약 방을 만들지 못했어요. 잠시 후 다시 시도해 주세요"

/// 예약 방 생성 실패 → 사용자 문구. `openFailureMessage` 와 **갈라 두는 쪽**이다.
///
/// | 사유 | 서버 코드(HTTP) | 사용자가 할 일 |
/// |---|---|---|
/// | 노쇼 제재 중 | `NO_SHOW_RESTRICTED` (403) | **지금은 없다.** 제재가 끝나야 풀린다 |
/// | 출발 2시간 안에 다른 예약 | `PARTY_TIME_CONFLICT` (409) | 다른 시간을 고른다 |
/// | 출발 시각이 창을 벗어났다 | `INVALID_DEPARTURE_TIME` (400) | 다른 시간을 고른다 |
/// | 이미 참여 중인 방 | `ALREADY_JOINED_OTHER_PARTY` (409) | 홈 배너로 그 방을 정리한다 |
/// | 출발지 = 도착지 | `SAME_DEPARTURE_DESTINATION` (400) | 핀을 옮긴다 |
/// | 서비스 지역 밖 | `OUT_OF_SERVICE_AREA` (400) | 다른 장소를 고른다 |
/// | 정원이 2~3 아님 | `INVALID_CAPACITY` (400) | 인원을 다시 고른다(사실상 앱 버그다) |
/// | 그 밖·네트워크 | 코드 없음 | `RESERVATION_OPEN_FAILED_MESSAGE` |
///
/// ### 왜 실시간 문구를 그대로 쓰지 않는가
/// 겹치는 네 가지는 **같은 문장을 재사용한다**(아래에서 `openFailureMessage` 를 부른다). 갈라야
/// 하는 것은 두 곳이다.
///
/// 1. **정원.** 실시간은 「1~3명」, 예약은 「2~3명」이다. 같은 문구를 쓰면 예약에서 400 을 맞은
///    사람에게 **고를 수 없는 1 을 고르라고** 말하게 된다.
/// 2. **실시간 표에 갈래가 없는 세 코드**(403 `NO_SHOW_RESTRICTED`·409 `PARTY_TIME_CONFLICT` — 둘 다
///    실시간 생성에도 온다 — 와 예약 전용 400 `INVALID_DEPARTURE_TIME`). 특히 앞의 둘은 갈라 두지
///    않으면 둘 다 「잠시 후 다시 시도해 주세요」가 된다 — **영구히 거짓**이다(제재는 시각이 지나야
///    풀리고, 시간 충돌은 다른 시간을 골라야 풀린다).
///
/// ### 403·409 에 「다시 시도」류를 붙이지 않는다 ★
/// `FinishFailureMessageTest` 가 세운 규칙이다. 특히 403 `NO_SHOW_RESTRICTED` 는 **재시도할 수
/// 없는 실패**다 — 끝나는 시각(`restrictedUntil`)이 서버에 있고 그 시각까지는 몇 번 눌러도 같은
/// 403 이다. 그 시각을 **여기서 말하지 않는 것**도 규칙이다: 이 화면은 그 값을 읽지 않는다(프로필
/// 응답에 있다). 모르는 숫자를 적지 않고, 다른 화면이 보여 준다고 약속하지도 않는다 — 말할 수 있는
/// 것은 **왜 막혔는가**와 **무엇이 바뀌어야 풀리는가**뿐이다.
///
/// 경로 실패(`ROUTE_*`) 가지는 **일부러 없다.** 서버는 예약 방에 경로를 계산하지 않으므로 그 코드가
/// 올 수 없고, 올 수 없는 사유를 적으면 모르는 코드가 그 문장으로 떨어져 **없는 원인**을 말한다.
func reservationOpenFailureMessage(e: PartyOpenException) -> String {
    // 서버 코드 문자열은 **도메인이 걸러 준 프로퍼티로만** 본다 — presentation 이 코드 이름을
    // 알면 서버가 enum 을 바꿀 때 조용히 어긋난다(`PartyOpenException` 주석).
    if e.isNoShowRestricted {
        return "노쇼 제재 중에는 방을 만들 수 없어요. 제재가 끝나면 다시 만들 수 있어요"
    }
    if e.isPartyTimeConflict {
        return "출발 2시간 안에 다른 예약이 있어요. 다른 시간으로 골라 주세요"
    }
    if e.isInvalidDepartureTime {
        return "출발 시각은 지금부터 7일 안이어야 해요. 다른 시간으로 골라 주세요"
    }
    if e.isInvalidCapacity { return "예약 방 인원은 2~3명이어야 해요" }
    // 아래 네 가지(이미 참여 중·출발지=도착지·서비스 지역 밖·그 밖)는 실시간과 **같은 사실**이라
    // 같은 문장을 쓴다. 다만 「그 밖」의 일반 문구만 예약 쪽으로 바꿔 끼운다 — 「동승 방을 만들지
    // 못했어요」는 예약을 만들려던 사람에게 무엇이 실패했는지 모호하다.
    if e.isAlreadyInAnotherParty || e.isSameDepartureDestination || e.isOutOfServiceArea {
        return openFailureMessage(e: e)
    }
    return RESERVATION_OPEN_FAILED_MESSAGE
}
