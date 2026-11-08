import Foundation
import MoyeotaDomain

// **예약 방**(서버 `RoomType.RESERVED`)을 만들고 찾는 데 쓰는 판정과 문구 중, 16 도착지 확인과
// 17 탐색·20 합류 확인이 **함께 쓰는 몫**을 모아 둔다 — 한국 달력의 7일 창, 날짜·시각 문구, 나갈 수
// 없다는 안내.
//
// ### 왜 화면에서 떼어 내는가
// 이 파일의 규칙은 전부 **시계와 달력**에 달려 있다 — 「지금부터 7일 안」·「오늘~7일 뒤」. 경계를 한
// 칸 잘못 잡아도 스크린샷에는 아무것도 보이지 않고, 그 차이는 **서버 400** 으로만 드러난다. 그래서
// 판정을 SwiftUI 를 모르는 순수 함수로 빼고 `now` 를 **인자로** 받는다 — 어느 함수도 안에서 `Date()`
// 를 부르지 않는다(부르면 테스트가 경계를 고정할 수 없다). 날짜·시각은 기기 시간대가 아니라
// **한국 시간대**로 셈한다(`KOREA_ZONE`).
//
// ### 왜 PresentationCore 인가
// 원본은 이 몫까지 `feature/home/ReservationRules.kt` 한 파일에 두고 17 탐색이 import 한다 — 예약의
// **시간 계약**은 방을 만드는 쪽(16)이 서버와 맺고 검색의 「오늘~7일 뒤」는 그 계약의 그림자라, 창을
// 정하는 상수와 날짜 계산을 한 곳에 둔 것이다. 기능 모듈끼리는 서로 import 할 수 없어 17·20 이 쓰는
// 몫만 여기로 옮겼고(`headcountLabel` 과 같은 선례), 나머지(출발 모드·정원·시각 슬롯·실패 문구)는
// `FeatureHome/ReservationRules.swift` 에 있다.
//
// ### 서버가 최종 판정이다
// 여기 있는 게이트는 **보낼 수 없는 값을 사용자가 고르지 못하게** 하려는 것이지 서버 검증의
// 사본이 아니다. 특히 **「출발 2시간 안에 다른 예약」(409 `PARTY_TIME_CONFLICT`)은 앱이 예측하지
// 않는다** — 내 다른 예약 목록을 화면이 들고 있지 않고, 들고 있어도 낡는다. 그건 막는 대신
// 거절당했을 때 **사유별 문구**로 받는다(`reservationOpenFailureMessage`).

/// 예약의 날짜·시각을 **한국 시간대**로 계산한다 — 기기 시간대가 아니다.
///
/// 서버 검색 파라미터 `date` 는 「한국 날짜 `yyyy-MM-dd`」이고(Swagger 명시), 그건 **순간(instant)이
/// 아니라 달력 날짜**다. 기기 시간대로 계산하면 기기가 KST 가 아닌 사용자(해외 체류·수동 설정)에게
/// **검색이 하루 밀린다**: 앱이 「오늘」이라고 적은 칩이 서버의 오늘과 다른 날을 가리키고, 그 날은
/// 「오늘~7일 뒤」 범위를 벗어나 400 `INVALID_SEARCH_DATE` 가 되기도 한다.
///
/// 고르는 **시각**도 같은 시간대로 묶는다. 사용자가 「오후 6:30」을 고르면 그건 한국에서 타는 택시의
/// 6시 30분이고, 기기 시간대로 읽으면 화면의 숫자와 서버에 보낸 순간이 어긋난다 — 그러면 표시된
/// 약속 시간과 실제 약속 시간이 다른 방이 만들어진다(되돌릴 수 없다: 예약 방은 시간을 바꿀 수 없다).
///
/// 34 기록·21 약속 표기가 `TimeZone.current` 를 쓰는 것과 **일부러 다르다.** 그쪽은 이미
/// 일어난(또는 1시간 안의) 일을 기기 시계로 읽어 주는 자리라 기기 시간대가 맞다. 이쪽은 **서버의
/// 달력에 값을 보내는** 자리다.
public let KOREA_ZONE: TimeZone = LocalDate.seoulZone

/// 예약 출발 시각의 상한 — **지금부터 7일**. 서버 `ReservationService` 가 그 밖을 400
/// `INVALID_DEPARTURE_TIME` 으로 거절하고, 검색 `date` 도 「오늘~7일 뒤」로 같은 창을 쓴다.
public let RESERVATION_WINDOW_DAYS = 7

/// ★ **예약 방에서는 나갈 수 없다** — 누르기 **전에** 말해야 하는 단 하나의 사실.
///
/// ### 근거 (서버 소스 실측)
/// 예약 방은 만들어진 순간부터 확정 상태라(`Ride.isConfirmed` 가 늘 true) `DELETE /matching/leave/{id}`
/// 가 **언제나** 409 `CANNOT_LEAVE_CONFIRMED_PARTY` 다. 즉 들어간 사람에게 방을 벗어날 길이 **없고**,
/// 출발 시각에 나타나지 않으면 누군가 「출발」을 누르는 순간 **노쇼로 기록된다**(그 대가는
/// `departConfirmMessage` 가 이미 말하는 그 제재다 — 약속 시간부터 노쇼 횟수 × 24시간).
///
/// ### 왜 다이얼로그가 아니라 버튼 **앞**인가
/// 실시간 방은 「그만 찾기」로 언제든 빠져나올 수 있어서, 사용자는 **방에 들어가는 일을 되돌릴 수
/// 있는 선택으로 배워 왔다.** 예약은 같은 모양의 버튼으로 전혀 다른 약속을 하게 만든다 — 그 차이를
/// 누른 뒤에 알리면 늦다(`MEETING_CONFIRM_HELP` 가 확정 버튼 앞에 같은 이유로 놓여 있다).
///
/// ### 두 자리가 한 문장을 공유한다
/// 만드는 쪽(16)과 합류하는 쪽(20 합류 확인)이 같은 결과를 맞는데, 둘이 각자 문구를 들고 있으면
/// 한쪽만 다듬어져 **같은 제약이 다른 무게로** 읽힌다. 바뀌는 것은 동사 하나뿐이다.
///
/// 「알림을 보내 드려요」류를 붙이지 않는다 — 서버에 예약 리마인더 푸시가 있지만 앱이 그 발송을
/// 확인할 길이 없고, 확인할 수 없는 것을 약속하지 않는 것이 이 저장소의 규칙이다.
///
/// - Parameter joining: 합류하는 쪽인가(false 면 만드는 쪽)
public func reservationCommitmentNotice(joining: Bool) -> String {
    let action = joining ? "합류하면" : "만들면"
    return "예약 방은 \(action) 나갈 수 없어요. 출발 시각에 안 가면 노쇼로 기록돼요"
}

/// 고를 수 있는 날짜 — **오늘부터 7일 뒤까지 8개**(한국 달력).
///
/// 검색(`GET /matching/reservations/search`)의 `date` 범위와 생성의 출발 시각 창이 같은 7일이라
/// 한 함수가 둘을 함께 댄다. 오늘을 포함하는 건 서버 규칙이다 — 오늘이면 「이미 출발한 방은 빠진다」.
///
/// - Parameters:
///   - now: 지금 시각. **호출부가 넘긴다** — 안에서 시계를 읽으면 경계를 테스트할 수 없다
///   - zone: 달력을 셈하는 시간대. 기본값이 `KOREA_ZONE` 인 근거는 그 상수의 주석에 있다
public func reservationDates(now: Date, zone: TimeZone = KOREA_ZONE) -> [LocalDate] {
    let today = LocalDate.ofInstant(now, zone)
    return (0...RESERVATION_WINDOW_DAYS).map { today.plusDays($0) }
}

/// 검색 파라미터 `date` 에 실을 값 — `yyyy-MM-dd`.
///
/// `LocalDate.toString()` 이 곧 ISO-8601 달력 날짜라 하는 일은 없지만 **함수로 둔다**: 이 값을
/// 「ISO 문자열을 잘라서」 만들지 말라는 금지를 이름으로 남기는 자리다. 서버가 UTC 로 내려주는
/// 순간 문자열에서 앞 10자를 떼면 KST 자정 직후가 **전날**이 된다(채팅·34 기록에서 실제로 났던
/// 결함과 같은 함정). 날짜는 `reservationDates` 가 시간대를 거쳐 만든 `LocalDate` 에서만 나온다.
public func reservationDateApiValue(date: LocalDate) -> String {
    date.toString()
}

/// 그 날짜가 **검색할 수 있는 날**인가 — 오늘~7일 뒤(한국 달력). 서버 400 `INVALID_SEARCH_DATE` 경계다.
///
/// 칩이 `reservationDates` 에서 나오므로 화면에서는 늘 참이다. 그래도 두는 이유는 **날짜가 다른 길로
/// 들어올 수 있기** 때문이다: 탐색 탭은 오래 살아 있어서(백스택에 남는다) 자정을 넘기면 어제 고른
/// 칩이 그대로 남는다 — 그때 이 검사가 조회를 막고 화면이 날짜를 다시 고르게 한다.
public func isReservationSearchDate(date: LocalDate, now: Date, zone: TimeZone = KOREA_ZONE) -> Bool {
    let dates = reservationDates(now: now, zone: zone)
    guard let first = dates.first, let last = dates.last else { return false }
    return date >= first && date <= last
}

/// 요일 한 글자. 로케일 표기에 맡기지 않는다 — 기기 로케일이 영어면 「Sun」이 섞인다.
private let KoreanDayOfWeek: [DayOfWeek: String] = [
    .monday: "월",
    .tuesday: "화",
    .wednesday: "수",
    .thursday: "목",
    .friday: "금",
    .saturday: "토",
    .sunday: "일",
]

/// 날짜 칩의 문구 — 오늘·내일은 **이름으로**, 그 뒤는 `11월 9일 (일)`.
///
/// 요일을 붙이는 이유: 7일 창에서 사람이 고르는 기준은 날짜 숫자가 아니라 「토요일 저녁」 같은
/// 요일이다. 반대로 오늘·내일에 숫자를 함께 적지 않는 건 칩 폭 때문이다 — 가로 스크롤 칩 8개가
/// 한 줄에 들어와야 어제 고른 칩이 어디 있는지 보인다.
///
/// - Parameter today: `reservationDates` 의 첫 원소. **호출부가 넘긴다** — 같은 시간대로 셈한 오늘이어야
///   「오늘」 칩과 보내는 날짜가 어긋나지 않는다
public func reservationDateLabel(date: LocalDate, today: LocalDate) -> String {
    switch date {
    case today: "오늘"
    case today.plusDays(1): "내일"
    default: "\(date.monthValue)월 \(date.dayOfMonth)일 (\(KoreanDayOfWeek[date.dayOfWeek] ?? ""))"
    }
}

/// 시각 칩·카드의 시각 문구 — `오후 6:30`.
///
/// 0시·12시가 12 가 되어야 한다(`hour % 12` 만 쓰면 자정이 「오전 0:30」이 된다 — `meetingTimeLabel`·
/// `rideHistoryDateLabel` 과 같은 함정·같은 처방).
///
/// 분은 기기 로케일과 무관하게 ASCII 숫자로 적는다(`String(format:)` 은 POSIX 로케일이다). 원본
/// `"%02d".format` 은 기기 로케일의 숫자를 따른다 — `meetingTimeLabel` 과 같은 차이다.
public func reservationTimeLabel(time: LocalTime) -> String {
    let meridiem = time.hour < 12 ? "오전" : "오후"
    let hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12
    return "\(meridiem) \(hour12):\(String(format: "%02d", time.minute))"
}
