import Foundation
import MoyeotaDomain
import PresentationCore

// 17 탐색에서 **예약 방을 찾는** 판정과 문구.
//
// ### 세 가지 목록은 서로 다른 영역을 본다 ★ 이 파일의 1급 사실
// | 모드 | 서버 | 영역 | 시간 |
// |---|---|---|---|
// | `ExploreMode.realtime` | `GET /matching/rooms` | **지도에 보이는 범위** | 지금 모집 중 |
// | `ExploreMode.soon` | `GET /matching/reservations/soon` | **지도에 보이는 범위** | 30분 안에 출발 |
// | `ExploreMode.byDate` | `GET /matching/reservations/search` | **내 위치에서 1km** | 그 날 하루 |
//
// 영역이 다른 목록을 한 화면에 섞어 그리면 **거짓말이 된다**: 「곧 출발」에 없는 방이 「날짜로
// 찾기」에는 있을 수 있고(1km 밖·지도 안), 반대도 된다(지도를 당겨 1km 밖을 보는 동안). 그래서
// 세 목록을 **합치지 않고** 모드로 갈라 한 번에 하나만 그리고, 각 모드가 **무엇을 기준으로 찾았는지**
// 화면에 적는다(`exploreAreaNote`). 이 파일이 존재하는 이유의 절반이 그 문구다.
//
// ### 왜 SwiftUI 를 모르는 파일인가
// 날짜 범위·도착지 둘다/아니다·조회 가능 여부 판정은 **값을 보고 틀렸는지 알 수 있어야** 한다 —
// 틀려도 화면에는 「방이 없어요」로만 보이고(서버가 400 을 주거나 빈 배열을 준다) 스크린샷으로는
// 구별되지 않는다. `MeetingFlow.swift`·`ReservationRules.swift` 와 같은 자리·같은 이유다.
//
// ### 날짜 규칙은 여기서 다시 정의하지 않는다
// 「오늘~7일 뒤」·`yyyy-MM-dd`·한국 시간대는 생성 쪽(`ReservationRules`)이 서버와 맺은 계약이고
// 검색은 그 그림자다 — 그 파일의 함수를 가져다 쓴다(17 이 `headcountLabel` 을 16 에서 가져다
// 쓰는 것과 같은 선례). 기능 모듈끼리는 서로 import 할 수 없어 17 이 쓰는 몫은 PresentationCore 에 있다.

/// 17 탐색이 지금 **무엇을 찾고 있는가**.
///
/// 불리언 두 개(예약인가 · 날짜 검색인가)로 흩어 두지 않는 이유는 조합 하나가 **없는 상태**이기
/// 때문이다(실시간인데 날짜 검색). enum 이면 `switch` 가 빠진 가지를 잡아 준다.
// `internal` 이 아니다 — `ExploreScreen` 의 공개 파라미터(`ReservationPaneUi`·`onModeSelect`)에 실려
// 나가므로 internal 이면 「public 이니셜라이저가 internal 타입을 쓴다」로 컴파일이 막힌다. 같은 모듈의
// `ExploreSheetState`·`MapBounds`·`MyLocationFix` 가 같은 이유로 공개 타입이다 — 화면 수준의 UI
// 타입은 공개, 판정·조회 계약(`ReservationQuery`·`ReservationFeed`)은 internal 로 둔다.
public enum ExploreMode: CaseIterable, Sendable {
    /// 지금 모집 중인 실시간 방 — 이 화면이 지금까지 보여 준 유일한 목록이다(기본값).
    case realtime

    /// 30분 안에 출발하는 예약 방(`/reservations/soon`). **지도 범위**로 찾는다.
    ///
    /// 예약 셋 중 이게 먼저 있는 이유: 20분 뒤에 출발하는 방은 사용자가 **지금 합류할 수 있는** 방이다.
    case soon

    /// 고른 날짜에 출발하는 예약 방(`/reservations/search`). **내 위치 1km**로 찾는다.
    case byDate
}

/// 「새 동승 방 만들기」를 누르면 16 도착지 확인을 **시간 정하기로 열까.**
///
/// 예약 탭을 보다 누른 사람은 **예약 방을 찾다가 없어서** 만들러 가는 것이다. 거기서 「지금 출발」로
/// 열면 화면이 방금까지 한 일을 잊은 꼴이고, 사용자는 모달에서 「시간 정하기」를 한 번 더 눌러야 한다.
/// 그 한 번을 없애는 것이 전부다 — **고르는 쪽을 바꿀 뿐 가둬 두지 않는다.** 예약 탭에서 눌렀어도
/// 모달에서 「지금 출발」로 되돌릴 수 있다.
///
/// `isReservation`(`!= .realtime`) 대신 `switch` 로 적는 이유는 `ExploreMode` 가 늘어날 때 **컴파일이 깨지게**
/// 하려는 것이다(`DepartureMode` 가 불리언이 아닌 것과 같은 판단). 새 탭이 생기면 「이 탭에서 만들면 예약인가」를
/// 그 자리에서 정하게 된다 — 기본값에 조용히 쓸려 가지 않는다.
func createOpensScheduled(mode: ExploreMode) -> Bool {
    switch mode {
    case .realtime: false
    case .soon, .byDate: true
    }
}

/// 모드 칩의 문구. 영역·시간 기준은 칩에 적지 않고 아래 한 줄이 말한다(`exploreAreaNote`).
func exploreModeLabel(mode: ExploreMode) -> String {
    switch mode {
    case .realtime: "실시간"
    case .soon: "곧 출발"
    case .byDate: "날짜로 찾기"
    }
}

extension ExploreMode {
    /// 예약인가 — 실시간 폴링을 멈출지, 예약 조회를 돌릴지 가른다(`ExploreRoute`).
    var isReservation: Bool { self != .realtime }
}

extension MapBounds {
    /// 「곧 출발」을 **물어볼 수 있는 범위인가** — 서버가 뷰포트를 **엄격 비교**로 검사한다.
    ///
    /// `swLat >= neLat || swLng >= neLng` 면 400 `INVALID_MAP_BOUNDS` 다. 실시간 목록
    /// (`RideRepository.getPartiesWithin`)도 서버 검사는 같다(같은 400). 그쪽은 지도가 알려 준 범위를
    /// `NMGLatLngBounds.toMapBoundsOrNull`(ExploreScreen)이 같은 엄격 비교로 먼저 거르고, 예약 쪽은
    /// 조회를 만드는 `reservationQueryOrNull` 이 범위를 직접 받으므로 그 자리에서 한 번 더 본다.
    ///
    /// 0 폭 뷰포트는 지도가 레이아웃되기 전이나 완전히 줌인한 순간에 실제로 나온다
    /// (`NMGLatLngBounds.toMapBoundsOrNull` 도 같은 이유로 그 범위를 거른다 — 이 판정은 그 방어가
    /// 지나간 뒤에도 기본 범위·확장 계산을 거친 값을 한 번 더 본다).
    var isQueryable: Bool {
        swLat < neLat && swLng < neLng
    }
}

/// 도착지 좌표를 **보낼 수 있는 모양으로만** 통과시킨다 — 이 함수가 400 두 가지를 막는다.
///
/// | 걸러내는 것 | 막는 실패 |
/// |---|---|
/// | 한쪽만 있다 | 400 `INCOMPLETE_DESTINATION` — 서버가 「둘 다 또는 둘 다 아니다」로 못 박았다 |
/// | (0, 0) · 유한하지 않은 값 | 400 `OUT_OF_SERVICE_AREA` — 0 은 **값이 빠졌을 때의 기본값**이고 서비스 지역(위 33~39 / 경 124~132) 밖이다 |
///
/// 둘째 줄이 실제로 겪은 함정이다: 서버 요청 record 가 전부 primitive `double` 이라 필드가 빠지면
/// 0.0 이 들어가고, 그러면 사유가 「서비스 지역 밖」으로 보여 **좌표가 아니라 지역을 의심하게** 된다
/// (`RealtimeMatchException.isOutOfServiceArea` 주석의 경고와 같은 자리).
///
/// **서비스 지역 자체는 다시 재지 않는다.** 위·경도 범위를 앱이 들고 있으면 서버와 두 개의 진실이
/// 생기고(서버가 넓히면 앱만 막는다), 사용자가 고른 도착지는 15 목적지 검색을 통과한 좌표다.
/// 거절은 서버가 하고 문구가 받는다.
func reservationDestinationOrNull(latitude: Double?, longitude: Double?) -> ReservationDestination? {
    guard let latitude, let longitude else { return nil }
    if !latitude.isFinite || !longitude.isFinite { return nil }
    if latitude == 0.0 && longitude == 0.0 { return nil }
    return ReservationDestination(latitude: latitude, longitude: longitude)
}

/// 예약 조회 한 건. 모드마다 **필요한 입력이 다르다**는 사실을 타입으로 들고 있다 —
/// `soon` 은 지도 범위만, `byDate` 는 내 좌표와 날짜가 있어야 한다.
enum ReservationQuery: Equatable, Sendable {
    /// `GET /matching/reservations/soon` — 뷰포트 안 30분 내 출발.
    case soon(bounds: MapBounds)

    /// `GET /matching/reservations/search` — 출발지 1km 안, 그 날 하루.
    ///
    /// - `date`: `yyyy-MM-dd` 한국 달력 날짜(`reservationDateApiValue`) — 순간 문자열을 자른 값이 아니다
    /// - `destination`: nil = 도착지 없이 검색(서버가 `destinationNearby` 를 null 로 준다)
    case byDate(
        departureLat: Double,
        departureLng: Double,
        date: String,
        destination: ReservationDestination?
    )
}

/// 지금 조회할 수 있는 요청 — **못 하면 nil** 이고 화면은 그 이유를 적는다.
///
/// 조회를 막는 조건이 곧 이 함수의 내용이다. 위에서부터 읽는다.
///
/// | 조건 | nil 인 이유 |
/// |---|---|
/// | 실시간 모드 | 예약 조회가 아니다 — 기존 뷰포트 목록(`ExploreViewModel`)이 그린다 |
/// | `bounds` 가 없거나 0 폭이다(SOON) | 지도가 아직 범위를 알려주지 않았거나 두 모서리가 같은 점이다 — 그대로 물으면 400 `INVALID_MAP_BOUNDS` 다(`MapBounds.isQueryable`) |
/// | 내 좌표가 없다(BY_DATE) | 1km 의 중심이 없다. **지도 중심으로 대신하지 않는다** — 화면이 「내 위치에서 1km」라고 적는데 지도를 옮긴 사람에게 그 말이 거짓이 된다 |
/// | 날짜가 없거나 창을 벗어났다 | 서버 400 `INVALID_SEARCH_DATE`. 탐색 탭은 오래 살아 있어 **자정을 넘기면** 어제 고른 칩이 그대로 남는다(`isReservationSearchDate`) |
///
/// - Parameter now: 지금 시각. **호출부가 넘긴다**(날짜 창 판정에 쓴다 — 안에서 시계를 읽으면 테스트가 경계를 고정할 수 없다)
func reservationQueryOrNull(
    mode: ExploreMode,
    bounds: MapBounds?,
    myLatitude: Double?,
    myLongitude: Double?,
    date: LocalDate?,
    destination: ReservationDestination?,
    now: Date,
    zone: TimeZone = KOREA_ZONE
) -> ReservationQuery? {
    switch mode {
    case .realtime:
        return nil
    case .soon:
        guard let bounds, bounds.isQueryable else { return nil }
        return .soon(bounds: bounds)
    case .byDate:
        guard let myLatitude, let myLongitude, let date else { return nil }
        guard isReservationSearchDate(date: date, now: now, zone: zone) else { return nil }
        return .byDate(
            departureLat: myLatitude,
            departureLng: myLongitude,
            date: reservationDateApiValue(date: date),
            destination: destination
        )
    }
}

/// 예약 카드 한 장이 그릴 것 — 방과 **도착지도 가까운가**.
///
/// `destinationNearby` 를 `Ride` 에 넣지 않는 이유: 그건 방의 성질이 아니라 **내가 보낸 도착지와의
/// 관계**다(같은 방이 다른 검색에서 false 가 된다). 도착지를 보내지 않은 검색과 「곧 출발」에서는
/// 서버가 주지 않으므로 **nil** 이고, 그때는 배지를 아예 그리지 않는다
/// (`destinationNearbyBadge`) — false 로 접으면 「도착지가 멀다」는 없는 사실을 말하게 된다.
// `ExploreMode` 와 같은 이유로 공개 타입이다 — `ReservationPaneUi.items` 에 실려 나간다.
//
// 세 조회의 결과를 **화면에서는 한 타입으로** 모은다. 저장소가 그러지 않는 이유(「곧 출발」에
// 늘 null 인 필드를 들고 다니지 않겠다)는 `RideRepository.getReservationsSoon` 주석에 있고,
// 그 판단과 어긋나지 않는다: 저쪽은 **무엇을 물었는지**를 타입으로 말하는 자리이고, 이쪽은
// **한 목록으로 그리는** 자리다(모드가 하나라 카드는 한 종류여야 한다). 변환은 뷰모델 한 곳이다.
public struct ReservationCardUi: Hashable, Sendable {
    public var ride: Ride
    public var destinationNearby: Bool?

    public init(ride: Ride, destinationNearby: Bool? = nil) {
        self.ride = ride
        self.destinationNearby = destinationNearby
    }
}

/// 예약 목록에서 **내가 이미 참여 중인 방을 뺀 결과** — 실시간의 `ExploreList` 와 같은 모양이다.
///
/// - Parameters:
///   - myPartyHidden: 실제로 빼냈는가. 빈 목록 문구가 이 값으로 갈린다 — 그 날의 예약이 내
///     방뿐이면 「예약이 없어요」는 **거짓말**이다(`reservationEmptyCopy`)
struct ReservationFeed: Equatable {
    var items: [ReservationCardUi]
    var myPartyHidden: Bool
}

/// 내가 참여 중인 방을 예약 목록·마커에서 **뺀다** — `exploreList` 와 **같은 근거·같은 비교**다
/// (`samePartyId`).
///
/// 왜 예약에도 필요한가: 내가 만든 예약 방은 서버 검색 결과에 **그대로 들어온다**(내 방을 빼 주지
/// 않는다). 남의 방과 똑같은 「합류」 카드로 보이고, 그 버튼은 거짓이다 — 눌러도 20 이 409
/// `ALREADY_JOINED` 로 받아 돌려보낸다. 돌아갈 길은 이미 화면 맨 위 진행 중 방 배너로 더 짧게 있다.
///
/// 「곧 출발」에도 같은 규칙을 적용한다. 그쪽은 **더 그렇다**: 30분 안에 출발하는 내 예약이야말로
/// 지금 화면에 뜰 가능성이 가장 높은 방이다.
func reservationFeed(items: [ReservationCardUi], myPartyId: String?) -> ReservationFeed {
    guard let myPartyId, !myPartyId.isBlank else {
        return ReservationFeed(items: items, myPartyHidden: false)
    }
    let remaining = items.filter { !samePartyId($0.ride.id, myPartyId) }
    return ReservationFeed(items: remaining, myPartyHidden: remaining.count != items.count)
}

/// 카드의 출발 시각 — `오늘 오후 6:30` · `11월 9일 (일) 오후 6:30`. 읽을 수 없으면 **nil**.
///
/// ### 날짜를 붙이는 이유
/// 21 약속 시각(`meetingTimeLabel`)은 시각만 적는다 — 그쪽은 늘 1시간 안이라 날짜가 뻔하다. 예약은
/// **최대 7일 뒤**라 「오후 6:30」만 적으면 오늘인지 모레인지 알 수 없다. 「곧 출발」에서는 늘 오늘이지만
/// 같은 함수를 쓴다(「오늘」이 붙어도 틀린 말이 아니고, 두 모드가 다른 모양을 쓰면 같은 방이 목록마다
/// 다르게 보인다).
///
/// ### 문자열을 자르지 않는다
/// 파싱은 21 과 **같은 함수**를 쓴다(`toMeetingInstantOrNull`) — 둘 다 같은 서버 필드
/// (`Ride.departureAt`)를 읽으므로 사본을 하나 더 만들면 한쪽만 형식 변화를 따라간다. 서버는 UTC 로
/// 내려주므로 `T` 뒤를 떼어 쓰면 KST 오후 6시가 **오전 9시**로 보인다(채팅·34 기록에서 실제로 났던 결함).
///
/// - Parameter now: 「오늘」·「내일」을 가리기 위한 기준 시각
func reservationDepartureLabel(
    departureAt: String?,
    now: Date,
    zone: TimeZone = KOREA_ZONE
) -> String? {
    guard let at = departureAt.toMeetingInstantOrNull() else { return nil }
    let today = LocalDate.ofInstant(now, zone)
    let dateLabel = reservationDateLabel(date: LocalDate.ofInstant(at, zone), today: today)
    return "\(dateLabel) \(reservationTimeLabel(time: LocalTime.ofInstant(at, zone)))"
}

/// 「도착지도 1km 안」 배지 — **서버가 true 라고 말했을 때만**. nil·false 면 nil 이고 배지를 그리지 않는다.
///
/// false 에 아무것도 그리지 않는 이유: 도착지를 보낸 검색에서 false 는 「1km 밖」이라는 뜻이지만,
/// **얼마나 밖인지는 모른다**(1.1km 일 수도 20km 일 수도 있다). 「도착지가 멀어요」라고 쓰면 모르는
/// 것을 단정하게 된다. 그리고 목록은 **서버가 정렬해 준 순서**라(true 가 먼저) 배지가 붙은 묶음이
/// 위에 모여 있는 것 자체가 구분이 된다.
func destinationNearbyBadge(destinationNearby: Bool?) -> String? {
    destinationNearby == true ? "도착지도 1km 안" : nil
}

/// 지도 마커 캡션 — 예약은 **시각이 먼저**다.
///
/// 실시간 마커는 인원만 적는다(`headcountLabel`). 예약에서 인원만 적으면 「곧 출발」의 마커 세 개가
/// 똑같아 보이는데, 그 화면에서 고르는 기준은 **몇 시에 출발하는가**다(20분 뒤 방과 29분 뒤 방 중
/// 하나를 고른다).
///
/// **빈 문자열 계약을 지킨다**: 둘 다 모르면 `""` 를 돌려주고 호출부가 캡션을 아예 달지 않는다
/// (`ExploreMarker` 주석) — 「0명」처럼 없는 사실을 지도에 박지 않기 위한 기존 규칙이다.
func reservationMarkerCaption(
    departureAt: String?,
    joined: Int,
    capacity: Int,
    now: Date,
    zone: TimeZone = KOREA_ZONE
) -> String {
    let headcount = headcountLabel(joined: joined, capacity: capacity)
    return [
        reservationDepartureLabel(departureAt: departureAt, now: now, zone: zone),
        headcount.isEmpty ? nil : headcount,
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
}

/// 17 접힘(PEEK) 요약 줄의 제목. **실시간 문구는 한 글자도 바뀌지 않는다** — 이 작업은 모드를
/// 더한 것이고, 기존 화면의 말을 고치는 일이 아니다.
///
/// - Parameter dateLabel: `ExploreMode.byDate` 에서 고른 날짜의 문구(`오늘`·`11월 9일 (일)`). 다른 모드에서는 쓰이지 않는다
func explorePeekTitle(mode: ExploreMode, count: Int, dateLabel: String?) -> String {
    switch mode {
    case .realtime: "주변 동승 \(count)개 모집 중"
    case .soon: "곧 출발 \(count)개"
    case .byDate: "\(dateLabel ?? "선택한 날") 출발 \(count)개"
    }
}

/// 18·19 목록 헤더의 제목.
///
/// **정렬을 말하는 조건이 모드마다 다르다** — 서버가 보장하는 것만 적는다.
///
/// | 모드 | 적는 말 | 근거 |
/// |---|---|---|
/// | `ExploreMode.realtime` | `· 가까운 순` | 기존 문구를 그대로 둔다 |
/// | `ExploreMode.soon` | 없음 | 서버가 순서를 약속하지 않았다 — **모르는 정렬을 적지 않는다** |
/// | `ExploreMode.byDate` · 도착지 없음 | `· 출발 시간 순` | 서버가 출발 시각 순으로 준다 |
/// | `ExploreMode.byDate` · 도착지 있음 | 없음 | **도착지 가까운 방이 먼저**이고 그 안에서 시각 순이다. 「출발 시간 순」은 거짓이 되므로 `exploreAreaNote` 가 설명한다 |
///
/// - Parameter count: 목록의 방 수. **nil 이면 개수를 적지 않는다**(「11월 17일 (화) 출발 · 출발 시간 순」) — 아직 읽지
///   못한 목록에 「0개」를 적으면 「없다」를 단정하게 된다(`exploreHeaderCount`)
func exploreListTitle(
    mode: ExploreMode,
    count: Int?,
    dateLabel: String?,
    destinationSent: Bool = false
) -> String {
    let n = count.map { " \($0)개" } ?? ""
    switch mode {
    case .realtime:
        return "주변 동승\(n) · 가까운 순"
    case .soon:
        return "곧 출발\(n)"
    case .byDate:
        return destinationSent
            ? "\(dateLabel ?? "선택한 날") 출발\(n)"
            : "\(dateLabel ?? "선택한 날") 출발\(n) · 출발 시간 순"
    }
}

/// 목록 헤더에 적을 **개수** — 목록을 아직 읽지 못했으면 nil 이고 헤더는 개수 없이 그린다(`exploreListTitle`).
///
/// | 상태 | 개수 | 이유 |
/// |---|---|---|
/// | 새 목록을 읽는 중(날짜·도착지·모드를 바꿈, 첫 조회) | 없음 | 목록 자리는 비어 있고 기다림은 새로고침 버튼이 보여 준다. 「0개」는 「없다」로 읽힌다 |
/// | 내 위치를 기다리는 중 | 없음 | 아직 묻지도 못했다 |
/// | 조회 실패(보여 줄 목록 없음) | 없음 | 못 물어봤다 — 「0개」는 장애를 「없다」로 위장한다(`reservationStatusTitle` 과 같은 근거) |
/// | 읽은 목록(빈 목록 포함) | 그 수 | 사실이다 |
func exploreHeaderCount(_ count: Int, loading: Bool, locating: Bool, failed: Bool) -> Int? {
    loading || locating || failed ? nil : count
}

/// **이 목록이 무엇을 기준으로 찾은 것인가** — 예약 모드에서만 그리는 한 줄.
///
/// 이 파일의 1급 사실(맨 위 표)을 사용자에게 옮기는 자리다. 「곧 출발」은 **지도 범위**, 「날짜로 찾기」는
/// **내 위치 1km** 라서, 적어 두지 않으면 지도를 멀리 옮겨 둔 사람이 「날짜로 찾기」 결과를 보고
/// 「저 동네 방이 왜 안 보이지」라고 생각한다(지도가 거기를 비추고 있으니 당연히 그렇게 읽는다).
///
/// 실시간에서는 nil 이다 — 기존 화면에 없던 줄을 더하지 않는다(그쪽 기준은 바뀌지 않았다).
func exploreAreaNote(mode: ExploreMode, destinationSent: Bool) -> String? {
    switch mode {
    case .realtime:
        nil
    case .soon:
        "지도에 보이는 범위에서 30분 안에 출발하는 방이에요"
    case .byDate:
        destinationSent
            ? "내 위치에서 1km 안에서 찾았어요. 도착지도 가까운 방이 먼저 보여요"
            : "내 위치에서 1km 안에서 찾았어요"
    }
}

/// 예약 목록이 0건일 때의 두 줄 — 접힘 요약과 리스트 빈 상태가 **같은 말**을 쓴다
/// (실시간의 `emptyListCopy` 와 같은 규칙).
///
/// 「없다」까지가 사실이고 그 이상을 약속하지 않는다. 다음에 할 일은 모드에 따라 다르다 —
/// 지도 범위로 찾은 쪽은 **지도를 옮기는 것**이고, 날짜로 찾은 쪽은 **다른 날을 고르거나 직접
/// 만드는 것**이다(1km 는 사용자가 넓힐 수 없다 — 서버 고정값이라 「범위를 넓혀 보세요」는 거짓이다).
func reservationEmptyCopy(
    mode: ExploreMode,
    dateLabel: String?,
    myPartyHidden: Bool = false
) -> (first: String, second: String) {
    // 걸러내기 전의 목록에 **내 방이 있었다** — 그때 「예약이 없어요」는 거짓말이다(방은 있고
    // 그게 내 방이며, 그래서 목록이 비었다). 실시간의 `emptyListCopy` 와 같은 분기·같은 근거다.
    let subtitle = mode == .soon
        ? "지도를 움직여 다른 동네를 볼 수 있어요"
        : "다른 날짜를 고르거나 예약 방을 직접 만들어 보세요"
    if myPartyHidden { return (first: "지금은 내 방뿐이에요", second: subtitle) }
    switch mode {
    case .soon:
        return (first: "30분 안에 출발하는 예약이 없어요", second: subtitle)
    default:
        // 「{날짜}에 출발하는」으로 쓰지 않는다 — 날짜 문구가 「오늘」·「내일」일 때 조사가 어긋난다
        return (first: "\(dateLabel ?? "선택한 날") 출발 예약이 없어요", second: subtitle)
    }
}

/// 조회가 **실패**했다 — 「예약이 없다」와 구별해야 하는 상태다(16 추천의 `nearbyLoadFailed` 와 같은 근거).
///
/// 여기에는 「다시 시도」를 붙인다. 403·409 에 재시도를 금지하는 규칙
/// (`FinishFailureMessageTest`)과 어긋나지 않는다 — 그건 **되돌릴 수 없는 거절**에 붙이는 말이고,
/// 이건 조회 실패다(네트워크·일시 장애면 다음 호출이 성공한다).
let RESERVATION_LOAD_FAILED_TEXT = "예약 방을 불러오지 못했어요"

/// 「날짜로 찾기」인데 아직 내 좌표가 없다 — 권한은 있고 첫 fix 를 기다리는 중이다.
///
/// 사용자가 할 일이 없으므로 **기다리라고만** 한다(21 의 `ARRIVE_LOCATING_LABEL` 과 같은 자리).
/// 「권한이 필요해요」와 섞지 않는다 — 권한이 없으면 이 화면은 지도 대신 권한 안내를 그린다.
let RESERVATION_LOCATING_TEXT = "내 위치를 확인하는 중이에요"

/// 조회 중 — 접힘 요약 한 줄이 쓴다(0건을 「없어요」로 말하지 않게).
///
/// 목록 쪽은 이 글도 스피너도 두지 않는다 — 자리를 비워 두고, 기다림은 새로고침 버튼의 도는 고리가 보여 준다
/// (2026-11, 오너 UX 피드백 2차: 「날짜로 찾기」의 목록 가운데 큰 스피너를 걷었다).
let RESERVATION_LOADING_TEXT = "예약 방을 불러오는 중이에요"

/// 목록이 비어 있을 때 **「없다」고 말해도 되는 상태인가** — 아니면 그 이유를 돌려준다.
///
/// ★ 이 함수가 막는 것: 접힘 요약(17 PEEK)은 목록이 아니라 **개수**만 보기 때문에, 조회 실패나
/// 좌표 대기 중에도 0건이라 「30분 안에 출발하는 예약이 없어요」를 적게 된다. 그건 장애를 사실로
/// 바꿔 말하는 것이고, 사용자는 날짜만 계속 바꾼다 — 목록 쪽에서 네 상태를 갈라 둔 것과 **같은
/// 판정을 같은 근거로** 접힘 요약에도 쓴다.
///
/// 세 상태가 겹칠 수 있으므로 순서가 있다: 좌표 대기가 조회보다 앞이다(아직 물어보지도 못했다).
///
/// - Returns: 그릴 안내 문구. **nil 이면 「없다」가 사실이다**(`reservationEmptyCopy` 를 쓴다)
func reservationStatusTitle(loading: Bool, locating: Bool, failed: Bool) -> String? {
    if locating { return RESERVATION_LOCATING_TEXT }
    if loading { return RESERVATION_LOADING_TEXT }
    if failed { return RESERVATION_LOAD_FAILED_TEXT }
    return nil
}

/// 「날짜로 찾기」의 도착지를 아직 고르지 않았다 — 고르면 **도착지도 가까운 방이 먼저** 온다.
let RESERVATION_ADD_DESTINATION_LABEL = "＋ 도착지"

/// 고른 도착지를 지우는 칩의 꼬리표. 지우면 도착지 없이 다시 검색한다(둘 다 빼는 쪽이다).
let RESERVATION_CLEAR_DESTINATION_LABEL = "✕"
