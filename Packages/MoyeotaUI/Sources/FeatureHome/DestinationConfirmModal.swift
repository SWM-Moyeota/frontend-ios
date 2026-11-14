import Foundation
import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 16 지도·요약 칩·요금 문구에 쓰이는 경로 미리보기 값 (POST /matching/routes 응답).
///
/// 방을 만들기 **전**이라 서버가 확정한 값이 아니다 — 좌표만으로 뽑은 추정치이며,
/// 실패해도 방 생성은 막지 않는다(서버가 생성 시 어차피 다시 계산한다).
/// 셋 다 nil 이고 `loading` 이 false 면 「값 없음」 — 칩·요금 문구를 감춘다.
public struct RoutePreviewUi: Equatable, Sendable {
    public var loading: Bool
    public var estimatedMinutes: Int?
    public var estimatedFare: Int? // 미터기 추정 총액(1인 요금 아님)
    public var encodedPath: String? // Google Encoded Polyline — 21 대기·22 상세의 지도와 같은 형식

    public init(
        loading: Bool = false,
        estimatedMinutes: Int? = nil,
        estimatedFare: Int? = nil,
        encodedPath: String? = nil
    ) {
        self.loading = loading
        self.estimatedMinutes = estimatedMinutes
        self.estimatedFare = estimatedFare
        self.encodedPath = encodedPath
    }
}

/// 16 에서 고른 매칭 조건 — **정원과 출발 시각**.
///
/// 「출발지 반경」·「도착지 반경」 칩은 지웠다(2026-10-14). 서버가 방 생성 요청에서 반경을 빼고
/// 고정값(500m)을 쓰기로 했다(Backend `a668aee`) — 보내도 버려진다. 그전에도 어떤 조회·판정도
/// 그 값을 읽지 않아(합류에 거리 검사가 없고 목록은 지도 뷰포트만 본다) 사용자는 **아무 영향 없는
/// 값**을 「매칭 조건」이라는 이름으로 고르고 있었다. 「준비 중」 자리표시를 두지 않고 요소째 내렸다.
///
/// 「동성만」 토글도 없다 — 성별은 매칭에 쓰이지 않는다(백엔드 `matching` 패키지에 성별 필드 0건).
/// 고를 수는 있는데 아무 일도 일어나지 않는 조건은 두지 않는다.
public struct MatchConditions: Equatable, Sendable {
    public var capacity: Int
    /// 예약 방의 출발 시각(ISO-8601 **순간** 문자열). **nil 이면 실시간 방**이다.
    ///
    /// 이 한 값이 **다른 엔드포인트**를 고른다 — nil 이면 `POST /matching/rooms`, 값이 있으면
    /// `POST /matching/reservations`(`CreatePartyViewModel.createParty`). 불리언 플래그를 따로 두지
    /// 않는 이유: 「예약이다」와 「그 시각」이 각각 참·거짓이 될 수 있으면 **시각 없는 예약**이라는
    /// 보낼 수 없는 조합이 타입에 생긴다. 시각이 곧 예약 여부다.
    ///
    /// 문자열로 들고 다니는 것은 이 저장소의 관례다(`Ride.departureAt`·`RideRecord`·`ChatMessage`) —
    /// 만드는 자리(`reservationDepartureIso`)와 읽는 자리에서만 파싱한다.
    public var departureAt: String?

    public init(capacity: Int, departureAt: String? = nil) {
        self.capacity = capacity
        self.departureAt = departureAt
    }
}

/// 원본 `"%,d".format` 자리. 기기 로케일의 묶음 기호를 쓴다.
func groupedAmount(_ amount: Int, locale: Locale = .current) -> String {
    amount.formatted(.number.locale(locale).grouping(.automatic))
}

/// 요약 칩 문구 — 거리는 서버 응답에 없어 시간·총요금으로 대체한다(와이어프레임의 2값 구조 유지).
/// nil 이면 실패 — 칩 자체를 감춘다. 틀린 값보다 없는 편이 낫다.
func routeSummaryLabel(routePreview: RoutePreviewUi, locale: Locale = .current) -> String? {
    if routePreview.loading { return "예상 경로 계산 중" }
    if let minutes = routePreview.estimatedMinutes, let fare = routePreview.estimatedFare {
        return "예상 \(minutes)분 · 총 \(groupedAmount(fare, locale: locale))원"
    }
    return nil
}

/// 시트 푸터 「1인 예상 요금」 줄의 **금액 칸**. 1인 요금 = 미터기 추정 총액 ÷ 인원, 10원 단위 반올림(`farePerPersonWon`
/// — 20 합류·22 상세가 쓰는 서버 값 계산식과 **같은 규칙**이다). 추정이 아직 없거나 실패했어도 CTA 는 살려 둔다.
///
/// 이름표(「1인 예상 요금」)와 금액을 두 칸으로 나눴다(디자인 QA S16-3) — 예전엔 「예상 요금 1인 2,630원」 한 줄이었다.
/// 계산 중이면 「계산 중」, 추정이 없으면 「—」.
func fareFooterValue(routePreview: RoutePreviewUi, peopleCount: Int, locale: Locale = .current) -> String {
    if routePreview.loading { return "계산 중" }
    if let total = routePreview.estimatedFare {
        return "\(groupedAmount(farePerPersonWon(totalFare: total, people: peopleCount), locale: locale))원"
    }
    return "—"
}

/// 이름이 이미 실주소면 호출부가 주소 칸을 비워 보낸다 — 구분자만 남지 않게 합친다
func destinationBadgeLabel(destinationName: String, destinationAddress: String) -> String {
    [destinationName, destinationAddress]
        .filter { !$0.isBlank }
        .joined(separator: " · ")
}

/// 16 · 도착지 확인 · 매칭 조건 (모달) [신규]
///
/// 이동(디스크립션):
/// - 닫기·배경 탭 → 15 (onDismiss) — 공통 규칙: 모달은 배경 탭·닫기로만 종료
/// - CTA → 방 생성 성공 시 21 매칭 대기 (onFindCompanions). 고른 조건(인원·출발 시각)을 그대로 넘긴다.
///   **출발 시각이 CTA 가 부르는 엔드포인트를 가른다** — 「지금 출발」은 `POST /matching/rooms`,
///   「시간 정하기」는 `POST /matching/reservations`(`MatchConditions.departureAt`).
///
/// 선택 규칙(디스크립션):
/// - **출발 시각: 「지금 출발」(기본) / 「시간 정하기」.** 뒤쪽을 고르면 날짜 띠(오늘~7일 뒤,
///   `ReservationDateStrip`)와 10분 단위 시·분 휠(`ReservationTimeWheel`)이 열린다 — 휠은 그 날의 범위
///   (`reservationTimeRange`) 안 값만 담아 고를 수 있는 모든 조합이 **구성상** 서버 창(지금~7일) 안이다.
///   휠은 늘 값을 보여 주므로 **기본 선택은 그 날의 가장 이른 시각**이고 CTA 는 켜져 있다
///   (`reservationSelectedTime` — 칩 시절의 「기본 선택 없음」 규칙을 바꾼 근거가 거기 있다)
/// - 인원(나 포함) → 예상 1인 요금 재계산 (`RoutePreviewUi.estimatedFare` ÷ 인원, `farePerPersonWon`).
///   기본값 3명. **범위가 모드에 따라 다르다** — 실시간 1~3, **예약은 2~3**(`capacityChoices`).
///   1 을 고른 채 「시간 정하기」로 바꾸면 보낼 수 없는 상태가 되므로 전송·표시 값만 2 로 접고
///   (`capacityFor`) 그 사실을 한 줄로 말한다(`RESERVATION_CAPACITY_NOTICE`)
/// - **1명을 고르면** 칩 행 아래에 「혼자 출발한다」 안내가 붙는다(`soloCapacityNotice`) —
///   정원 1 은 만든 즉시 꽉 찬 방이라 아무도 합류할 수 없다. 선택지와 전송 값은 그대로다
/// - **예약에서는 경로 요약 칩과 예상 요금을 감춘다**(`RESERVATION_NO_ESTIMATE_NOTICE`) — 서버가
///   예약 방에 요금·경로·소요 시간을 넣지 않아서, 추정치를 그대로 보여 주면 **방에는 없는 숫자**를
///   보고 동의하게 된다. 지도의 경로선은 남긴다(핀 사이의 길 모양은 예측이 아니다)
/// - 예약에서는 「걸어서 가까운 방」 추천도 감춘다 — 그건 **지금 출발하는** 방 목록이고
///   (`POST /rooms/realtime`), 시간을 정하러 온 사람이 탭하면 지금 타는 방에 합류하게 된다
///
/// 레이아웃(디스크립션):
/// - 지도가 헤더 아래를 전부 채우고, 그 위에 **드래그로 접었다 펴는 시트**가 얹힌다
/// - 펼침 = 매칭 조건까지 전부 보임(지도 160pt 노출) / 접힘 = 도착지·요금·CTA 만 보이고 지도가 넓어짐
/// - CTA 는 시트 하단에 고정이라 두 상태 모두에서 보인다
public struct DestinationConfirmModal: View {
    private let destinationName: String
    private let destinationAddress: String
    private let originStopName: String
    private let departureTimeLabel: String
    private let arrivalTimeLabel: String
    private let destinationPosition: LatLng?
    private let originPosition: LatLng?
    private let routePreview: RoutePreviewUi
    private let creating: Bool
    private let errorMessage: String?
    private let onDismiss: () -> Void
    private let onAdjustPositions: (LatLng?, LatLng?) -> Void
    private let onFindCompanions: (MatchConditions) -> Void
    private let nearbyCandidates: [MatchCandidate]
    private let onCandidateClick: (MatchCandidate) -> Void
    private let nearbyLoadFailed: Bool
    private let onRetryNearby: () -> Void

    // 기본값: 3인 (디스크립션 유효값 규칙)
    @State private var peopleCount = 3
    // 기본값: 지금 출발 — **지금까지의 동작이 기본값이다**(`DepartureMode`)
    @State private var departureMode: DepartureMode
    // 핀 조정 화면(모달 내 확장 상태). nil 이면 닫혀 있다.
    @State private var adjustTarget: PinTarget?

    // 예약 날짜·시각 계산의 기준 시각. **한 번만 읽는다** — 매 다시 그리기마다 시계를 읽으면
    // 휠의 범위가 1초마다 다시 만들어지고(지난 값이 사라지며) 고른 칸이 손가락 아래에서 움직인다.
    // 이 모달은 몇 분 안에 닫히는 화면이라 그 사이 기준이 낡아도 가장 이른 값이 10분 여유를
    // 갖고 있어(`RESERVATION_MIN_LEAD_MINUTES`) 서버 창을 벗어나지 않는다. 그리고 보내는 시각은
    // **휠에 보이는 값 그대로**다(`ReservationPick.departureAt`) — 보내는 순간 시계를 다시 읽어 고치지 않는다.
    // 기준을 옮기는 길(CTA 직전의 다시 재기 · 화면 복귀의 `onAppear`)은 `moveClock(to:)` 하나다 — 고른 날짜를 지킨다.
    @State private var now = Date()
    // 고른 날짜는 **오늘로부터의 일수**로 들고 있는다 — 원본은 `LocalDate` 를 `rememberSaveable` 에
    // 그대로 담을 수 없어 일수(Int)를 쓴다. 같은 값을 그대로 옮겼다. 일수는 `now` 의 「오늘」로부터 센 값이라
    // `now` 만 옮기면 자정을 넘긴 경우 다른 날을 가리킨다 — 그래서 둘을 함께 옮긴다(`moveClock(to:)`).
    @State private var dateOffset = 0
    // 휠로 고른 시각(하루의 분). -1 = 아직 휠을 건드리지 않았다 → **그 날의 가장 이른 시각이 기본 선택**이다.
    //
    // 칩 시절에는 기본 선택이 없었다(아무도 원하지 않은 00:00 예약이 한 번의 탭으로 만들어진다는 이유).
    // 휠은 늘 값을 보여 주므로 「안 골랐다」를 그릴 수 없고, 그래서 규칙을 바꿨다 — 근거와 대신 세운
    // 방어(크게 보이는 휠 값 + CTA 위 되읽기 줄)는 `reservationSelectedTime` 설명에 있다.
    @State private var selectedMinuteOfDay = -1
    // CTA 직전 다시 재기가 실패해 휠을 옮겼다는 안내(`reservationClockMovedNotice`). nil 이면 없다.
    // 휠·날짜 띠를 만지거나 CTA 를 다시 누르면 걷는다 — 사용자가 바뀐 값을 보고 손을 댔다는 뜻이다.
    @State private var clockMovedNotice: String?
    // 시트 아래 내비게이션 바 인셋의 실측 높이 — 접힘 높이 추정치에 더한다(아래 `MapSheetScaffold` 주석).
    @State private var navigationBarHeight: CGFloat = 0

    // 원본 `remember(key)` 자리 — 시트를 끄는 동안 지도 슬롯이 프레임마다 다시 평가되므로,
    // 폴리라인 해석과 카메라 계산을 그때마다 돌리지 않는다.
    @State private var routeMemo = Remembered<String?, [LatLng]>()
    @State private var fitMemo = Remembered<FitKey, (first: LatLng, second: Double)?>()

    /// - Parameters:
    ///   - destinationName: 이름 자리에는 검색 장소명 대신 **역지오코딩 실주소**가 들어올 수 있다(핀 조정·GPS 출발지).
    ///     「부산광역시 금정구 부산대학로63번길 2 부산대학교」처럼 길어지므로 표기는 전부 1줄 말줄임이다 —
    ///     시/도 접두 제거 같은 가공은 하지 않는다(서버가 조합해 준 값을 그대로 보여준다).
    ///   - destinationPosition: 지도 좌표 — 도착지가 있으면 실지도, 없으면 자리표시자 (15 를 거치지 않은 진입)
    ///   - creating: 방 생성 요청 중 — 중복 제출 차단
    ///   - onAdjustPositions: 핀 조정 확정 — (출발지, 도착지) 좌표. 조정하지 않은 쪽은 들어온 값 그대로 돌아온다
    ///   - nearbyCandidates: 「걸어서 가까운 방」 추천. **빈 목록이 기본값이자 기본 상태**다 — 서버가 출발지·도착지
    ///     각각 300m 안(AND)에서만 고르기 때문에 초기에는 거의 항상 비어 있다. 비면 섹션을 그리지 않는다.
    ///     서버가 도보 시간 순으로 정렬해 준 순서 그대로 받는다 — **여기서 다시 정렬하지 않는다.**
    ///   - onCandidateClick: 추천 카드를 누르면 그 방의 합류 확인(19)으로 간다 — 합류 흐름은 이미 있는 걸 그대로 쓴다.
    ///   - nearbyLoadFailed: 추천 **조회가 실패**했다 — 「주변에 방이 없다」와 구별해야 하는 상태다.
    ///     둘을 합치면 다음 행동이 정반대인 두 상황이 같게 보인다: 후보 0건이면 방을 만드는 게 맞지만,
    ///     조회 실패(OSRM 장애·배포 중 503)면 **300m 안에 방이 있어도** 섹션이 사라져 사용자가 모르고
    ///     새 방을 만든다. 합승 매칭이 조용히 꺼지는 자리라 작은 재시도 줄을 둔다 — 차단형 배너가
    ///     아닌 이유는 추천이 부가 기능이라는 기존 판단을 유지하기 때문이다.
    ///   - initiallyScheduled: 처음부터 「시간 정하기」(예약)로 열 것인가. **기본값이 지금까지의 동작**이다 —
    ///     15 목적지 확정으로 열면 아무것도 넘기지 않고, 17 탐색의 예약 탭에서 「방 만들기」로 열 때만 참이 온다
    ///     (`MainNavGraph.createScheduled` → `DestinationConfirmRoute`).
    ///     파라미터로 둔 이유는 17 탐색의 `initialSheetState` 와 같다: 예약 상태의 화면을 바로 띄워 볼 수
    ///     있어야 한다(내부 상태만으로는 그 화면을 만들 수 없다).
    ///     `DepartureMode` 가 아니라 **Bool** 인 이유는 이 뷰가 공개 API 라는 점이다 — 그 enum 은 모듈
    ///     안의 판정 타입(internal)이고, 공개 파라미터가 internal 타입을 받으면 컴파일이 막힌다. 공개
    ///     자리에는 도메인 타입과 원시값만 둔다(이 저장소의 관례).
    public init(
        destinationName: String,
        destinationAddress: String,
        originStopName: String,
        departureTimeLabel: String = "지금",
        arrivalTimeLabel: String = "도착 계산 중",
        destinationPosition: LatLng? = nil,
        originPosition: LatLng? = nil,
        routePreview: RoutePreviewUi = RoutePreviewUi(),
        creating: Bool = false,
        errorMessage: String? = nil,
        onDismiss: @escaping () -> Void = {},
        onAdjustPositions: @escaping (LatLng?, LatLng?) -> Void = { _, _ in },
        onFindCompanions: @escaping (MatchConditions) -> Void = { _ in },
        nearbyCandidates: [MatchCandidate] = [],
        onCandidateClick: @escaping (MatchCandidate) -> Void = { _ in },
        nearbyLoadFailed: Bool = false,
        onRetryNearby: @escaping () -> Void = {},
        initiallyScheduled: Bool = false
    ) {
        self.destinationName = destinationName
        self.destinationAddress = destinationAddress
        self.originStopName = originStopName
        self.departureTimeLabel = departureTimeLabel
        self.arrivalTimeLabel = arrivalTimeLabel
        self.destinationPosition = destinationPosition
        self.originPosition = originPosition
        self.routePreview = routePreview
        self.creating = creating
        self.errorMessage = errorMessage
        self.onDismiss = onDismiss
        self.onAdjustPositions = onAdjustPositions
        self.onFindCompanions = onFindCompanions
        self.nearbyCandidates = nearbyCandidates
        self.onCandidateClick = onCandidateClick
        self.nearbyLoadFailed = nearbyLoadFailed
        self.onRetryNearby = onRetryNearby
        _departureMode = State(initialValue: initiallyScheduled ? .scheduled : .now)
    }

    private var scheduled: Bool { departureMode == .scheduled }

    // 보낼 수 있는 정원. 모드가 바뀌어도 `peopleCount` 는 그대로 둔다 — 되돌리면 고른 값이 살아 있다
    private var capacity: Int { capacityFor(mode: departureMode, selected: peopleCount) }

    private var reservation: ReservationPick {
        ReservationPick(now: now, dateOffset: dateOffset, selectedMinuteOfDay: selectedMinuteOfDay)
    }

    /// 기준 시각을 `fresh` 로 옮긴다 — 일수를 새 띠에서 **보던 날짜의 자리**로 다시 셈한다. 일수만 두면 자정을 넘긴
    /// 기준에서 「내일」이 「모레」가 된다(원본 리뷰 반영, PR #99). 보던 날이 범위를 벗어났으면 고를 수 있는 첫 날이다
    /// (`reservationDateOffsetAfterClockMove`).
    ///
    /// 돌려주는 값은 옮긴 뒤 띠에 **칠해질** 날짜다(`ReservationPick.selectedDate` 와 같은 접기) — CTA 의 안내가 날짜도
    /// 바뀌었는지 가른다(`reservationClockMovedNotice`).
    @discardableResult
    private func moveClock(to fresh: Date) -> LocalDate {
        let freshDates = reservationDates(now: fresh)
        let freshSelectable: (LocalDate) -> Bool = { reservationTimeRange(date: $0, now: fresh) != nil }
        let offset = reservationDateOffsetAfterClockMove(
            selectedDate: reservation.selectedDate,
            newDates: freshDates,
            isSelectable: freshSelectable
        )
        dateOffset = offset
        now = fresh
        return freshDates[reservationSelectableDateIndex(storedIndex: offset, dates: freshDates, isSelectable: freshSelectable)]
    }

    /// 예약 날짜·시각 선택에서 나오는 값. 원본은 컴포저블 본문의 지역 값이다 — 여기서는 시트 조각
    /// (경로 요약·매칭 조건·푸터)마다 쓰므로 조각마다 한 번 셈해 둔다.
    struct ReservationPick {
        let dateOptions: [LocalDate]
        let today: LocalDate
        /// 그 날에 고를 시각이 남아 있는가 — 늦은 밤의 「오늘」만 false 다. 띠는 그 칸을 누르지 못하게 그린다.
        let dateSelectable: (LocalDate) -> Bool
        /// 기본값(오늘)이 고를 수 없는 날이면 **고를 수 있는 첫 날**로 본다 — 누를 수 없는 칸이 선택된 채
        /// 열리면 휠 자리에 「고를 시간이 없어요」만 남는다(`reservationSelectableDateIndex`).
        let selectedDate: LocalDate
        let timeRange: ReservationTimeRange?
        /// 날짜를 바꾸면 **보여 줄 값만** 그 날의 범위로 접는다(고른 값은 남는다 — 정원의 `capacityFor` 와
        /// 같은 처방). 이 값이 휠에 보이는 값이자 서버로 가는 값이다.
        let selectedTime: LocalTime?

        init(now: Date, dateOffset: Int, selectedMinuteOfDay: Int) {
            let dates = reservationDates(now: now)
            let selectable: (LocalDate) -> Bool = { date in reservationTimeRange(date: date, now: now) != nil }
            dateOptions = dates
            today = dates[0]
            dateSelectable = selectable
            let date = dates[reservationSelectableDateIndex(storedIndex: dateOffset, dates: dates, isSelectable: selectable)]
            selectedDate = date
            let range = reservationTimeRange(date: date, now: now)
            timeRange = range
            selectedTime = reservationSelectedTime(
                stored: selectedMinuteOfDay >= 0
                    ? LocalTime(hour: selectedMinuteOfDay / 60, minute: selectedMinuteOfDay % 60)
                    : nil,
                range: range
            )
        }

        /// 서버로 가는 출발 시각 = **휠에 보이는 그 값**(`selectedTime`)과 띠에 칠해진 그 날(`selectedDate`).
        /// 누르는 순간 시계를 다시 읽거나 값을 다시 접지 않는다 — 화면과 보낸 값이 1분이라도 어긋나면 표시된
        /// 약속 시간과 실제 약속 시간이 다른 방이 만들어지고, 예약 방은 시간을 바꿀 수 없다.
        var departureAt: String? {
            selectedTime.map { reservationDepartureIso(date: selectedDate, time: $0) }
        }
    }

    private struct FitKey: Equatable {
        let routePath: [LatLng]
        let origin: LatLng?
        let destination: LatLng?
        let widthDp: Float
        let heightDp: Float
    }

    public var body: some View {
        ZStack {
            // Scrim 배경 — 탭 시 닫기
            MoyeotaColor.Scrim
                .onTapGesture(perform: onDismiss)

            // 모달 카드 (풀스크린 라우트 겸용) — 내부 탭은 소비
            VStack(spacing: 0) {
                header

                // 지도(헤더 아래 전부) 위에 드래그 시트를 얹는다 — 시트 메커니즘은 21 과 공유한다
                // 접힘 = 핸들 + 도착지 배지 + 요금 줄 + CTA (기본값과 같은 구성) + 내비게이션 바 인셋.
                // 인셋을 더하는 이유: 모달이 화면 끝까지 그린 뒤로(S16-1) CTA 아래 `NavigationBarSpacer`
                // 가 실제 높이를 갖는다 — 추정치에 넣지 않으면 그만큼 펼침 상태의 지도 노출이 줄어든다.
                MapSheetScaffold(
                    collapsedSheetHeight: 176 + navigationBarHeight,
                    background: { sheet in
                        mapBackground(sheet: sheet)
                    },
                    sheetTop: { sheetTop },
                    sheetDetail: { sheetDetail },
                    sheetFooter: { sheetFooter }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 핀 조정 — 같은 화면의 최상단 레이어로 덮는다(신규 목적지 아님)
            if let adjustTarget {
                PinAdjustOverlay(
                    originName: originStopName,
                    destinationName: destinationName,
                    originPosition: originPosition,
                    destinationPosition: destinationPosition,
                    initialTarget: adjustTarget,
                    onCancel: { self.adjustTarget = nil },
                    onConfirm: { adjustedOrigin, adjustedDestination in
                        self.adjustTarget = nil
                        onAdjustPositions(adjustedOrigin, adjustedDestination)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 디자인 QA S16-1: 모달이 **화면 끝까지** 그린다. 예전엔 안전 영역 안에만 그려 상태바·홈 인디케이터 두 줄에
        // 아래 화면의 어두운 딤이 띠처럼 남았다. 끝까지 넓히면 헤더의 `StatusBarSpacer` 와 푸터의 `NavigationBarSpacer`
        // 가 실제 인셋을 받아 그 자리를 흰색으로 칠한다(원본은 대화상자 창의 `decorFitsSystemWindows = false`).
        // 키보드 영역은 그대로 둔다 — 이 화면에는 입력 칸이 없다.
        .ignoresSafeArea(.container)
        // 원본 `adjustTarget` 은 `remember` 다. 위에 다른 화면이 쌓였다 돌아오면 핀 조정이 닫혀 있고
        // `peopleCount`·`departureMode`·`dateOffset`·`selectedMinuteOfDay`(저장값)만 남는다.
        .onDisappear { adjustTarget = nil }
        // 기준 시각도 원본은 돌아오면 다시 읽힌다 — 덮인 동안의 낡은 기준이 남으면 이미 지난
        // 시각을 고를 수 있게 된다(400 `INVALID_DEPARTURE_TIME`). 처음 뜰 때도 불리지만 init 직후의 값이다.
        // 덮인 사이 자정을 넘길 수 있어 고른 날짜를 지키며 옮긴다(`moveClock(to:)`).
        .onAppear { moveClock(to: Date()) }
    }

    // 상단 헤더 — 다른 하위 화면과 같은 가운데 제목 앱바(디자인 QA G7·4-6). 상태바 자리도 흰색으로
    // 칠한다: 모달이 화면 끝까지 그리므로(S16-1) 인셋이 실제 값이다.
    private var header: some View {
        VStack(spacing: 0) {
            // 시작값(창 인셋)이 실제 겹침과 같아 첫 레이아웃 뒤에 높이가 바뀌지 않는다 — 바뀌면 아래 지도의 크기가 첫
            // 카메라 뒤에 달라져 지도가 늘어난 높이의 절반만큼 내려앉는다(`StatusBarSpacer(startsCollapsed:)` 설명).
            StatusBarSpacer()
            // 오른쪽 방패 아이콘은 지웠다(2026-11, 오너 UX 피드백) — 누를 수도 없고 가리키는
            // 기능도 없는 장식이었다. 안전 기능(원터치 신고)은 2차 범위라 이 화면에 그 약속을
            // 그려 둘 근거가 없다(DESIGN-moyeota.md: 방패는 비상 신고 진입점에만 쓴다).
            // 그 자리에 빈칸을 남기지 않는다 — 가운데 제목이라 오른쪽이 비어도 균형이 깨지지 않는다.
            MoyeotaTopBar(title: "도착지 확인", onBack: onDismiss)
        }
        .frame(maxWidth: .infinity)
        .background(MoyeotaColor.SurfaceCanvas.onTapGesture {})
    }

    private func mapBackground(sheet: MapSheetState) -> some View {
        // 폴리라인 디코딩은 21 대기·22 상세의 지도와 같은 decodePolyline 을 쓴다.
        // **예약에서도 그린다** — 두 핀 사이의 길 모양은 시각·금액 예측이 아니라 기하다
        // (`RESERVATION_NO_ESTIMATE_NOTICE` 의 마지막 단락).
        let routePath = routeMemo.value(key: routePreview.encodedPath) {
            routePreview.encodedPath.map { decodePolyline(encoded: $0) } ?? []
        }
        let widthDp = Float(sheet.containerWidth)
        // fit 기준은 **시트에 가리지 않고 실제로 보이는 지도 높이**다.
        // 앵커가 바뀔 때만 값이 변하므로 드래그·정착 중 카메라가 매 프레임 튀지 않는다.
        let visibleMapHeightDp = Float(sheet.visibleMapHeight)
        let fitted = fitMemo.value(
            key: FitKey(
                routePath: routePath,
                origin: originPosition,
                destination: destinationPosition,
                widthDp: widthDp,
                heightDp: visibleMapHeightDp
            )
        ) {
            fitMapCamera(
                points: routePath + [originPosition, destinationPosition].compactMap { $0 },
                widthDp: widthDp,
                heightDp: visibleMapHeightDp
            )
        }
        // 「위치 조정」 버튼은 **실측** 시트 높이를 써서 시트 바로 위에 붙인다 —
        // 앵커 추정치를 쓰면 에러 배너가 떠 시트가 커졌을 때 버튼이 가린다.
        let sheetHeight = sheet.sheetHeight
        let canAdjust = destinationPosition != nil || originPosition != nil
        // 요약 칩 — 예약 방에는 소요 시간도 요금도 없다. 「지금」 기준 추정을 미래 출발에 붙이지 않는다
        let label = scheduled ? nil : routeSummaryLabel(routePreview: routePreview)

        return ZStack(alignment: .topLeading) {
            if let destinationPosition {
                RouteMapView(
                    routePath: routePath, // previewRoute 의 encodedPath — 2점 미만이면 그려지지 않는다
                    originPosition: originPosition,
                    destinationPosition: destinationPosition,
                    center: fitted?.first ?? destinationPosition,
                    // 경로가 없을 땐 도착지 주변 블록이 식별될 정도로 당겨 본다
                    zoom: fitted?.second ?? 15.0,
                    // 가려지는 영역을 지도에 알려 카메라 중심이 보이는 영역 기준으로 잡히게 한다
                    contentPadding: EdgeInsets(top: 0, leading: 0, bottom: sheet.settledSheetHeight, trailing: 0)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MapPlaceholder()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 지도를 덮는 투명 탭 레이어는 두지 않는다 — 그 레이어가 터치를 전부 먹어
            // SDK 줌 컨트롤(+/-)·핀치·팬이 통째로 죽어 있었다. 핀 조정 진입은
            // 아래 「위치 조정」 버튼 하나로 충분하다.

            // 경로 미리보기 실패 시엔 칩을 통째로 감춘다 — 틀린 값보다 없는 편이 낫다
            if let label {
                MapOverlayPill {
                    Text(label)
                        .moyeotaText(
                            MoyeotaType.BodySm.copy(fontWeight: .semibold).tabularNums().hangulTrimmed,
                            color: MoyeotaColor.InkPrimary
                        )
                }
                .padding(MoyeotaSpacing.ScreenGutter)
                .allowsHitTesting(false)
            }

            // 지도 조정 진입점. 오른쪽 아래는 SDK 줌 컨트롤(+/-) 자리라 왼쪽에 둔다.
            // 보이는 알약은 32 지만 **터치 영역은 48** 이다(디자인 QA G12) — 바깥 상자가 48 을
            // 잡아 두고 그 가운데에 알약을 그린다. 글자는 파랑이 아니라 검정이다: 이 화면의 파랑은
            // CTA 하나에만 둔다(예전엔 한 시트에 파랑이 여섯 번 나왔다 — S16-2).
            if canAdjust {
                Button {
                    adjustTarget = .destination
                } label: {
                    Text("위치 조정")
                        .moyeotaText(MoyeotaType.ButtonSm.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(MoyeotaColor.SurfaceCanvas, in: MoyeotaShape.Pill)
                        .mapOverlayShadow(MoyeotaShape.Pill)
                        .frame(minWidth: 48, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressFeedbackStyle())
                // 바깥 48 상자의 위아래 8 만큼 덜 띄워 알약과 시트 사이를 12 로 맞춘다
                .padding(.leading, MoyeotaSpacing.ScreenGutter)
                .padding(.bottom, sheetHeight + 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    // 도착지 배지 — 접힌 상태에서도 보이는 최소 정보.
    // 배지는 **회색**이다(디자인 QA S16-5): 초록은 이 앱에서 「매칭됨·확정」을 뜻해서, 아직 아무것도
    // 확정되지 않은 화면에 초록 배지를 달면 없는 상태를 말하게 된다. 「도착지」는 상태가 아니라 이름표다.
    private var sheetTop: some View {
        HStack(alignment: .center, spacing: 0) {
            StatusBadge(kind: .neutral, text: "도착지")
            Spacer().frame(width: 8)
            Text(destinationBadgeLabel(destinationName: destinationName, destinationAddress: destinationAddress))
                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
    }

    // 상세 영역은 시트가 접히면 높이 0 이 된다 — 좌우 여백은 여기서 준다
    private var sheetDetail: some View {
        let reservation = self.reservation
        // 경로 요약의 시각 두 칸.
        // - 예약: 출발 칸에 **고른 시각**을 적고(그 날에 시각이 없으면 비운다) 도착 칸은 **비운다** —
        //   서버가 예약 방에 소요 시간을 주지 않아 도착 시각을 셈할 근거가 없다. 「지금」 기준 추정으로
        //   채우면 3일 뒤 도착 시각을 오늘 교통으로 단정하는 말이 된다.
        // - 지금 출발: 호출부가 넘긴 값 그대로(기존 동작).
        let departureText = scheduled
            ? reservation.selectedTime.map { reservationTimeLabel(time: $0) } ?? ""
            : departureTimeLabel
        let arrivalText = scheduled ? "" : arrivalTimeLabel
        return VStack(alignment: .leading, spacing: 0) {
            // 「도착지」 배지 줄(sheetTop)과 아래 경로 요약 사이의 숨 쉴 자리 — 예전에는 둘이
            // 맞닿아 배지 줄이 카드의 머리처럼 보였다(오너 UX 피드백). 12 는 4/8 리듬의
            // `MoyeotaSpacing.Sm` 이다. **상세 영역 안에** 두는 이유: 시트를 접으면 상세가 통째로
            // 0 이 되므로 이 간격도 함께 사라져 접힘 높이(176 추정치)가 흔들리지 않는다.
            Spacer().frame(height: MoyeotaSpacing.Sm)
            // 경로 요약 — 판(배경) 없이 흰 시트 위에 바로(디자인 QA S16-2 · G9). 20·22 와 같은 조각이다.
            // 이름은 굵게, 시각은 보통 굵기 + 고정폭 숫자로 — 예전엔 네 줄이 모두 15 Bold 라
            // 무엇이 중요한지 읽히지 않았다. 출발지·도착지 각각에 「조정」을 둔다(무엇을 조정하는지
            // 애매하지 않게 — 오너 결정으로 지도의 「위치 조정」까지 진입점 셋을 유지한다).
            // 좌표가 없는 쪽은 조정할 핀이 없어 「조정」을 그리지 않는다(예전과 같은 조건).
            // 출발지 → 도착지 연결선만 그린다. 도보 거리·시간은 서버가 주지 않아 표기하지 않는다.
            RouteSummary(
                origin: originStopName,
                destination: destinationName,
                originMeta: departureText,
                destinationMeta: arrivalText,
                onAdjustOrigin: originPosition != nil ? { adjustTarget = .origin } : nil,
                onAdjustDestination: destinationPosition != nil ? { adjustTarget = .destination } : nil
            )

            Spacer().frame(height: MoyeotaSpacing.SectionGap)

            SectionLabel(text: "매칭 조건")

            conditions(reservation: reservation)

            // 「걸어서 가까운 방」 — 후보가 있을 때만 그린다. 없는 게 기본 상태라
            // (서버가 출발지·도착지 **각각** 300m 안에서만 고른다) 「없음」을 강조하면
            // 방을 만들러 온 사람에게 실패처럼 읽힌다.
            //
            // **예약에서는 통째로 감춘다**(실패 줄까지). 이 추천은 `POST /rooms/realtime`
            // 의 결과 = **지금 출발하는** 방이고, 탭하면 그 방의 합류 확인(19)으로 간다.
            // 3일 뒤 출발을 정하러 온 사람에게 그 카드는 「지금 타는 방」이라는 사실이
            // 보이지 않아, 시간을 정했다고 생각하며 지금 출발하는 방에 들어가게 된다.
            // 조회 자체는 막지 않는다 — 모드를 되돌리면 그 결과가 그대로 보인다.
            if !scheduled {
                if !nearbyCandidates.isEmpty {
                    Spacer().frame(height: 16)
                    NearbyCandidateSection(
                        candidates: nearbyCandidates,
                        onCandidateClick: onCandidateClick
                    )
                } else if nearbyLoadFailed {
                    // 후보 0건과 달리 **못 물어봤다**는 뜻이라 사실을 말하고 길을 준다.
                    Spacer().frame(height: 16)
                    HStack(alignment: .center, spacing: 0) {
                        Text("가까운 방을 불러오지 못했어요")
                            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                        // 글자만 보이지만 48 로 눌린다(G12) — 예전엔 12pt 글자 크기 그대로였다
                        TextLinkButton(text: "다시 시도", onClick: onRetryNearby)
                    }
                }
            }

            Spacer().frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
    }

    // 매칭 조건 — 시트 안에 그림자 카드를 또 두지 않는다(디자인 QA S16-4 · G4). 줄은 흰 시트
    // 위에 바로 놓이고, 「출발 시각」 묶음과 「인원」 줄 사이만 Hairline 으로 나눈다.
    private func conditions(reservation: ReservationPick) -> some View {
        let capacity = self.capacity
        return VStack(alignment: .leading, spacing: 0) {
            // 「출발 시각」이 **맨 위**에 있는 이유: 이 선택이 아래 모든 것을 바꾼다
            // (정원 범위·요금 표시·CTA 가 부르는 엔드포인트). 아래에 두면 사용자가
            // 정원을 고른 뒤에 선택지가 줄어드는 것을 보게 된다.
            ConditionRow(label: "출발 시각") {
                ForEach(DepartureMode.allCases, id: \.self) { mode in
                    MoyeotaChip(
                        text: departureModeLabel(mode: mode),
                        selected: departureMode == mode,
                        onClick: { departureMode = mode }
                    )
                }
            }

            if scheduled {
                // 날짜는 **주간 달력 띠**, 시각은 **시·분 휠**이다(2026-11, 오너 UX 피드백) —
                // 예전 칩(「오늘·내일·11월 14일 (토)」 8개 + 30분 시각 칩 최대 48개)은 가로로
                // 길게 밀어야 해서 요일을 한눈에 볼 수 없었고, 30분 단위는 약속에 거칠었다.
                // 띠는 17 「날짜로 찾기」와 **같은 컴포넌트**다(`ReservationDateStrip`).
                // 띠는 16 화면 여백 안에 놓여 첫 칸이 「매칭 조건」 머리말과 같은 선에서 시작한다
                // (디자인 QA 4-3 — 예전엔 카드 안쪽 20 이 더해져 36 이었다)
                PickerSection(label: "날짜", trailing: reservationMonthLabel(dates: reservation.dateOptions)) {
                    ReservationDateStrip(
                        dates: reservation.dateOptions,
                        selected: reservation.selectedDate,
                        onSelect: { date in
                            dateOffset = reservation.dateOptions.firstIndex(of: date) ?? 0
                            clockMovedNotice = nil
                        },
                        isSelectable: reservation.dateSelectable
                    )
                }
                if let range = reservation.timeRange, let selectedTime = reservation.selectedTime {
                    PickerSection(label: "시각") {
                        ReservationTimeWheel(
                            range: range,
                            selected: selectedTime,
                            onSelect: { time in
                                selectedMinuteOfDay = time.hour * 60 + time.minute
                                clockMovedNotice = nil
                            }
                        )
                    }
                } else {
                    // 고를 수 있는 날이 하나도 없을 때만 닿는다 — 늦은 밤의 「오늘」은 띠가 누를 수
                    // 없게 그리고 기본 선택도 다음 날로 옮긴다(`reservationSelectableDateIndex`).
                    // 그래도 이 길을 남겨 두는 이유: 빈 휠보다 사실을 말하는 한 줄이 낫다.
                    ConditionNotice(text: RESERVATION_NO_SLOT_NOTICE)
                }
            }

            HorizontalDivider(color: MoyeotaColor.Hairline)

            // 라벨에 「나 포함」을 박았다 — 서버 정원(`Capacity`)은 **방장을 포함한 총
            // 인원**이라(`Party.open` 이 생성자를 멤버로 넣고 `members.size == capacity`
            // 면 꽉 찬 것으로 본다) 「3인」만 쓰면 「나 외 3명」으로 읽힌다. 「나 포함 N명」을
            // 칩마다 쓰지 않고 라벨로 올린 건 레이아웃 때문이다 — 칩 3개가 좁은 폰(360dp)에서
            // 카드 밖으로 밀려 잘린 전례가 있다(`ConditionRow` 주석).
            //
            // 선택지가 **모드에 따라 다르다**(`capacityChoices`) — 예약에서 1 칩은
            // 보내도 400 이라 지운다. 선택 표시는 전송값(`capacity`)을 보므로 1 을
            // 고른 채 예약으로 넘어오면 2 가 선택된 것으로 보인다(그리고 아래 한 줄이
            // 그 이유를 말한다).
            ConditionRow(label: "인원(나 포함)") {
                ForEach(capacityChoices(mode: departureMode), id: \.self) { count in
                    MoyeotaChip(
                        text: "\(count)명",
                        selected: capacity == count,
                        onClick: { peopleCount = count }
                    )
                }
            }
            // 예약에서 1 칩이 사라진 이유를 **고르는 자리에서** 말한다. 실시간의
            // 「혼자 출발한다」 안내와 같은 자리·같은 모양이고, 두 문구는 함께 뜨지
            // 않는다(예약에서는 capacity 가 1 이 될 수 없다).
            if scheduled {
                ConditionNotice(text: RESERVATION_CAPACITY_NOTICE)
            }
            // 「1명」을 고른 사람에게만 **고르는 자리에서** 결과를 말해 준다
            // (`soloCapacityNotice`). 1 은 지우지 않았다 — 혼자 타기를 상품으로
            // 인정한 결정이다. 다만 그 선택의 결과(정원 1 = 만든 즉시 꽉 찬 방 =
            // 아무도 합류 못 함)는 서버 규약을 아는 사람만 읽어 낼 수 있어서,
            // 안내가 없으면 「1명」은 그냥 「나 외 1명」처럼 보인다.
            //
            // 자리를 늘 비워 두지 **않고** 1명일 때만 줄을 넣은 근거:
            // 이 줄은 `MapSheetScaffold` 의 sheetDetail 안에 있고 그 영역은
            // **앵커가 정한 고정 높이 + 세로 스크롤**이다(콘텐츠가 높이를 정하지
            // 않는다). 그래서 이 줄이 생겨도 시트 높이·지도 노출·CTA 위치는 **한
            // 픽셀도 움직이지 않고**, 아래의 「걸어서 가까운 방」 섹션만 그만큼
            // 밀린다 — 손가락이 닿아 있는 칩 행은 안내보다 **위**라 제자리다.
            // 상시 빈 자리를 두면 2·3명(기본값 3)에서 늘 비어 있는 ~30pt 가
            // 좁은 폰의 스크롤 영역에서 추천 카드 한 줄만큼을 먹는다.
            //
            // 색·크기는 이 파일의 보조 문구 관습(`ConditionNotice` — BodySm + TextMute)이다.
            // 빨강·경고 아이콘을 쓰지 않는다 — 정상 선택이고, 오류로 읽히면
            // 사용자는 고를 수 있는 값을 「막힌 값」으로 본다.
            // 줄바꿈을 막지 않는다 — 큰 글꼴 설정에서 잘린 안내보다 두 줄이 낫고, 스크롤 영역 안이라 잘릴 일도 없다.
            if let notice = soloCapacityNotice(capacity: capacity) {
                ConditionNotice(text: notice)
            }
            // 「출발지 반경」·「도착지 반경」 행은 지웠다(2026-10-14) — 서버가 방 생성
            // 요청에서 반경을 빼고 고정값(500m)을 쓴다(Backend `a668aee`). 고른 값이
            // 전송조차 되지 않고, 전송됐을 때도 매칭이 읽지 않던 값이다(`MatchConditions`).
            //
            // 「매칭 방식 · 주요 승차지점」 행은 지웠다(2026-10-13) — 그런 매칭 방식이
            // 없다. 서버에 승차지점 개념이 없고(방은 사용자가 찍은 좌표 그대로 만들어진다)
            // 칩도 항상 선택된 채 무동작이었다. 고를 것도, 가리킬 기능도 없는 줄이었다.
            //
            // 카드는 걷어냈다(디자인 QA S16-4) — 「출발 시각」·「인원」 두 줄이 시트 위에 바로 놓이고
            // 둘 사이만 Hairline 으로 나눈다.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 요금 안내(예약이면 **고른 시각**) + CTA — 접힘·펼침 모두에서 보이도록 시트 하단에
    // 고정한다. 추정 실패 시에도 CTA 는 막지 않는다 — 방 생성 요청을 받으면 서버가
    // 요금을 다시 계산한다.
    //
    // 예약은 이 자리가 **두 줄**이 된다: 고른 시각을 되읽어 주는 줄
    // (`reservationDepartureSummary` — 날짜 띠와 시각 휠이 떨어져 있어 둘이 합쳐져
    // 무엇이 되는지 확인할 마지막 기회다. 휠에 **기본값이 생긴 뒤로는** 손대지 않은 값이
    // 무엇인지 알려 주는 자리이기도 하다 — 그래서 `BodyStrong` 으로 눈에 띄게 둔다)과
    // 요금·소요 시간이 **없다는 사실**
    // (`RESERVATION_NO_ESTIMATE_NOTICE`). 접힘 높이가 한 줄만큼 커지지만 시트 높이는
    // 콘텐츠가 정하므로(`MapSheetScaffold`) 잘리는 것은 없다.
    private var sheetFooter: some View {
        let reservation = self.reservation
        let capacity = self.capacity
        // **「지금 출발」이면 싣지 않는다** — 휠은 늘 값이 있어 실으면 실시간 방이 예약 방이 된다(`matchDepartureAt`).
        let departureAt = matchDepartureAt(
            scheduled: scheduled,
            date: reservation.selectedDate,
            time: reservation.selectedTime
        )
        return VStack(spacing: 0) {
            if scheduled {
                Text(
                    reservation.selectedTime.map {
                        "\(reservationDepartureSummary(date: reservation.selectedDate, time: $0, today: reservation.today)) 출발"
                    } ?? RESERVATION_NEEDS_TIME_NOTICE
                )
                // body-strong(15/600) — 디자인 QA 4-4 의 되읽기 줄
                .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                Spacer().frame(height: 2)
                // 예약 방에는 요금이 없다 — 「—」로 비워 두면 로딩 실패로 읽히므로
                // 왜 없는지 적는다(없는 숫자를 지어내지 않는 것이 1급 규칙이다).
                // **예약이면 아예 셈하지 않는다**(서버가 그 방에 요금을 넣지 않는다).
                Text(RESERVATION_NO_ESTIMATE_NOTICE)
                    .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                    // 접힘 높이가 문구 길이에 따라 흔들리지 않게 한 줄로 고정한다
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            } else {
                // 1인 예상 요금 — **이 화면의 주인공 숫자**다(디자인 QA S16-3). 예전엔 가운데 정렬
                // 12pt 회색(흰 바탕 대비 2.6:1) 한 줄이라 CTA 바로 위에서도 읽히지 않았다. 이름표는 왼쪽
                // 작은 회색, 금액은 오른쪽 HeadingMd 검정으로 나눠 CTA 위 12 에 둔다.
                // 뒤에 붙던 설명 문구(「인원이 확정되면…」)는 뺐다 — 금액만으로 충분하다.
                HStack(alignment: .center, spacing: 0) {
                    Text("1인 예상 요금")
                        .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(fareFooterValue(routePreview: routePreview, peopleCount: capacity))
                        .moyeotaText(MoyeotaType.HeadingMd.tabularNums().hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                // 이름표와 금액을 한 문장으로 읽힌다(「1인 예상 요금, 3,200원」)
                .accessibilityElement(children: .combine)
            }
            // ★ **나갈 수 없다**는 사실은 CTA 앞에 둔다(`reservationCommitmentNotice`) —
            // 실시간 방은 「그만 찾기」로 빠져나올 수 있어서 사용자는 방에 들어가는 일을
            // 되돌릴 수 있는 선택으로 배워 왔고, 예약은 **같은 모양의 버튼으로 전혀 다른
            // 약속**을 하게 만든다. 요금 문구와 달리 두 줄을 허용한다(잘리면 뜻이 반쪽이 된다).
            //
            // **가운데 정렬 + 어절 단위 줄바꿈**(2026-11, 오너 UX 피드백): 예전에는 왼쪽 정렬에
            // 음절 단위로 끊겨 마지막 「요」 한 글자가 혼자 둘째 줄을 차지했다 — 버튼 바로 위라
            // 오류처럼 보였다. 문구는 한 글자도 바꾸지 않는다(`KoreanParagraphText` 가 줄바꿈만 바꾼다).
            // 모양은 `BodySm` · `TextMute`, 최대 두 줄, CTA 위 8(디자인 QA 4-5) — 경고가 아니라
            // 알아 둘 사실이라 조용한 보조 글이다.
            if scheduled {
                Spacer().frame(height: 8)
                KoreanParagraphText(
                    text: reservationCommitmentNotice(joining: false),
                    style: MoyeotaType.BodySm.copy(color: MoyeotaColor.TextMute).hangulTrimmed,
                    maxLines: 2
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            }
            // CTA 위 안내 자리 하나를 둘이 나눠 쓴다. 다시 재기 안내가 먼저다 — 방금 누른 것에 대한 답이고,
            // 서버 오류는 그 앞의 시도에 대한 말이다. 다시 재기 안내는 예약 휠 이야기라 예약일 때만 보인다.
            let clockNotice = scheduled ? clockMovedNotice : nil
            if let clockNotice {
                Spacer().frame(height: 12)
                NoticeBanner(kind: RESERVATION_CLOCK_MOVED_NOTICE_KIND, text: clockNotice)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            } else if let errorMessage {
                Spacer().frame(height: 12)
                NoticeBanner(kind: .error, text: errorMessage)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            }
            // 예약 안내가 CTA 바로 위에 올 때는 8 로 붙인다 — 그 안내는 이 버튼에 대한 말이다
            Spacer().frame(height: scheduled && clockNotice == nil && errorMessage == nil ? 8 : 12)
            PrimaryCtaButton(
                // 예약은 **무엇이 만들어지는지** 적는다 — 「같이 탈 사람 찾기」는 지금
                // 모집을 시작하는 말이라, 시간을 정해 둔 방에는 맞지 않는다.
                text: scheduled ? "이 시간으로 예약 방 만들기" : "같이 탈 사람 찾기",
                onClick: {
                    // 휠은 기본값(그 날의 가장 이른 시각)이 늘 있어 한 번도 안 건드려도 보낼 수 있다. 모달을
                    // 연 채 오래 머물면 그 값이 이미 지났거나 여유가 없을 수 있다 — 그대로 보내면 서버가 400
                    // `INVALID_DEPARTURE_TIME` 으로 막고, 안내는 「7일 안이어야 해요」라 원인과 어긋난다.
                    // 그래서 **지금 시계로 다시 재고, 범위를 벗어났으면 보내지 않고 기준만 옮긴다** — 휠이
                    // 새 범위로 접혀 보이는 값이 바뀌고, 사용자는 바뀐 시각을 보고 다시 누른다
                    // (보이는 값 = 보내는 값 원칙은 그대로다).
                    // 기준을 옮길 때 고른 날짜는 지킨다(`moveClock(to:)`) — 자정을 넘겨도 「내일」이 「모레」가 되지 않는다.
                    // 옮겼으면 CTA 위에 **왜 안 보냈는지** 한 줄 남긴다(원본 리뷰 반영 2차) — 휠 숫자만 슬쩍 바뀌면
                    // 「안 눌렸다」로 읽혀 바뀐 값을 보지 않고 다시 누른다. 다시 누르면 먼저 걷는다.
                    clockMovedNotice = nil
                    let fresh = Date()
                    if scheduled
                        && !reservationTimeStillValid(
                            date: reservation.selectedDate, time: reservation.selectedTime, now: fresh
                        ) {
                        let shownDate = moveClock(to: fresh)
                        clockMovedNotice = reservationClockMovedNotice(dateChanged: shownDate != reservation.selectedDate)
                    } else {
                        onFindCompanions(MatchConditions(capacity: capacity, departureAt: departureAt))
                    }
                },
                // 시각이 없는 예약은 보낼 수 없다 — 휠이 늘 값을 주므로 고른 날에 남은 시각이 없을
                // 때만 꺼진다. 그때 비활성 버튼 위에 **왜 못 누르는지**를 적어 둔다
                // (`RESERVATION_NEEDS_TIME_NOTICE`). 비활성 버튼만 두면 이유를 모른다.
                enabled: !scheduled || departureAt != nil,
                loading: creating
            )
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            // CTA 아래 16 + 내비게이션 바 인셋. 모달이 화면 끝까지 그리므로(S16-1) 인셋이 실제 값이고,
            // 시트의 흰 바탕이 홈 인디케이터 뒤까지 이어진다.
            Spacer().frame(height: 16)
            NavigationBarSpacer()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { navigationBarHeight = $0 }
        }
        .frame(maxWidth: .infinity)
    }
}

/// CTA 직전 다시 재기 안내(`reservationClockMovedNotice`)의 배너 종류 — **회색 안내(info)**.
///
/// 오류가 아니다: 아무것도 실패하지 않았고, 앱이 시간이 지난 값을 고쳐 두고 확인을 부탁할 뿐이다. 빨강(error)은
/// 서버가 거절한 일에 쓰는 색이라 여기 쓰면 「방을 못 만들었다」로 읽힌다. 호박(waiting)은 「기다리는 중」이라는 뜻을
/// 싣는 색이라(매칭 대기) 맞지 않는다 — 뜻이 없는 회색 안내가 이 말의 무게다(`NoticeKind` 설명).
let RESERVATION_CLOCK_MOVED_NOTICE_KIND = NoticeKind.info

/// `remember(key) { … }` 의 자리 — 키가 같으면 다시 계산하지 않는다.
@MainActor
final class Remembered<Key: Equatable, Value> {
    private var entry: (key: Key, value: Value)?

    func value(key: Key, compute: () -> Value) -> Value {
        if let entry, entry.key == key { return entry.value }
        let value = compute()
        entry = (key, value)
        return value
    }
}

/// 「걸어서 가까운 방」 추천 목록. **후보가 있을 때만** 불린다(빈 목록은 호출부가 거른다).
///
/// 기존 17 탐색 카드보다 **정보가 적다** — 서버 응답에 인원·요금이 없어서다. 그래서 숫자를
/// 지어내 채우지 않고, 가진 것(출발·도착·도보 시간·정원)만 보여 준다. 인원 현황은 탭해서 들어간
/// 합류 확인(19)이 방 상세를 읽어 채운다.
private struct NearbyCandidateSection: View {
    let candidates: [MatchCandidate]
    let onCandidateClick: (MatchCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "걸어서 가까운 방")
            // 「N분 소요」라고 쓰면 목적지까지 N분으로 읽힌다 — 걷는 시간이라는 걸 못 박는다.
            Text("타러 가고, 내려서 걷는 시간을 더한 값이에요")
                .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
            Spacer().frame(height: 4)
            // 그림자 카드 대신 줄 + Hairline(디자인 QA S16-6) — 시트 안에서 카드가 또 떠 있지 않게 한다
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                if index > 0 { HorizontalDivider(color: MoyeotaColor.Hairline) }
                NearbyCandidateRow(candidate: candidate, onClick: { onCandidateClick(candidate) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NearbyCandidateRow: View {
    let candidate: MatchCandidate
    let onClick: () -> Void

    var body: some View {
        let headcount = headcountLabel(joined: candidate.ride.members.count, capacity: candidate.ride.capacity)
        Button(action: onClick) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(candidate.ride.origin) → \(candidate.ride.destination)" as String)
                        .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !headcount.isEmpty {
                        Spacer().frame(height: 2)
                        Text(headcount)
                            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 12)
                // 파랑이 아니라 본문 회색 SemiBold — 이 시트의 파랑은 CTA 하나다(S16-6)
                Text(walkMinutesLabel(walkSeconds: candidate.walkSeconds))
                    .moyeotaText(MoyeotaType.BodySm.copy(fontWeight: .semibold).hangulTrimmed, color: MoyeotaColor.TextBody)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressOverlayStyle(shape: Rectangle()))
    }
}

/// 예상 총 요금 ÷ 인원 = 1인 요금(원), **10원 단위 반올림**.
///
/// **이 규칙은 data 쪽 `farePerPerson` 과 한 글자도 다르면 안 된다.** 16 모달은 방을 만들기 **전**의
/// 추정치(`POST /matching/routes`)를 인원으로 나누고, 20 합류·21 대기·22 상세는 서버가 방에 박아 둔
/// 요금을 정원으로 나눈 값(`Ride.farePerPerson`)을 쓴다 — 나누는 수가 같은 값(정원)이므로 **반올림
/// 규칙만 어긋나도 같은 방이 화면마다 다른 금액**을 보여 준다(실제로 7,900원·3인 방이 16 에서
/// 2,630원, 22 에서 2,633원이었다). 모듈 경계(presentation ↔ data) 때문에 함수를 공유할 수 없어
/// 규칙을 양쪽에 적고, 「두 값이 같다」는 `FarePerPersonRuleTest`(여기)와 `PartyMappersTest`(data)가
/// **같은 표**로 못 박는다.
///
/// 10원 단위인 근거는 택시 요금 표기 관례다 — 1원 단위 금액은 실제로 낼 수 없다.
/// `people` 이 0 이하면 0 을 돌려준다(data 쪽의 `capacity <= 0` 가드와 같은 자리). 화면에서는 칩이
/// 1~3 뿐이라 닿지 않는 길이지만, 두 규칙을 같은 모양으로 유지해 비교 테스트가 성립하게 둔다.
func farePerPersonWon(totalFare: Int, people: Int) -> Int {
    if people <= 0 { return 0 }
    return roundToInt((Double(totalFare) / Double(people)) / 10.0) &* 10
}

/// Kotlin `Double.roundToInt()` — 정확히 .5 는 양의 무한대 쪽으로 올린다. Swift `rounded()` 는 음수에서 0 의
/// 반대쪽으로 가서 어긋난다.
private func roundToInt(_ value: Double) -> Int {
    let floor = value.rounded(.down)
    return Int(value - floor >= 0.5 ? floor + 1 : floor)
}

/// 「인원(나 포함)」에서 **1명**을 고른 상태의 안내 문구. 1 이 아니면 nil — 줄을 그리지 않는다.
///
/// 왜 필요한가: 서버 `Capacity` 는 **방장을 포함한 총 인원**이고 `Party.open` 이 생성자를 멤버로
/// 넣는다(`MatchConditions`). 그래서 1 로 방을 만들면 `members.size == capacity` 가 **만든 즉시**
/// 참이 되어 아무도 합류할 수 없고, 사용자는 「같이 탈 사람 찾기」를 눌렀는데 혼자 출발한다.
/// 선택지에서 1 을 지우지 않기로 한 결정(혼자 타기를 상품으로 인정)이 성립하려면, 그 결과를
/// **고르는 자리에서** 말해 주는 것이 조건이다.
///
/// 문구 규칙:
/// - 「1/1 로 꽉 찬 방」·「정원」 같은 내부 용어를 쓰지 않는다. 사용자가 겪는 일은 두 가지뿐이다 —
///   **동승자를 받지 않고, 혼자 출발한다.** 둘 다 적는다(하나만 적으면 나머지를 추측하게 된다).
/// - 「같이 탈 사람」은 이 화면 CTA 와 **같은 말**이다. 「동승자」·「합승 인원」으로 바꾸지 말 것 —
///   CTA 가 「같이 탈 사람 찾기」인데 안내가 다른 단어를 쓰면 같은 대상인지 한 번 더 생각해야 한다.
/// - 요금과 모순되지 않는다: 1명이면 `farePerPersonWon` 이 총액을 1 로 나눠 **1인 요금 = 총 요금**이
///   되고(「예상 N분 · 총 7,900원」 칩과 푸터의 「1인 예상 요금 7,900원」이 같은 수가 된다) 그건 혼자
///   출발하는 방의 **사실**이다. 그래서 요금 문구는 손대지 않았다 — 여기서 「요금을 전부 부담한다」를
///   한 번 더 말하면 같은 사실을 두 자리에서 말하게 되고, 한 줄 안내가 두 줄로 늘어난다.
func soloCapacityNotice(capacity: Int) -> String? {
    capacity == 1 ? "같이 탈 사람을 받지 않고 혼자 출발해요" : nil
}

/// 도보 시간(초) → 표시 문구. **「걸어서」를 반드시 붙인다** — 서버가 주는 값은 탑승지까지 걷는
/// 시간과 내려서 걷는 시간의 **합**이고 차 타는 시간은 안 들어 있다. 「7분」만 쓰면 목적지까지
/// 7분으로 읽힌다.
///
/// 1분 미만도 「걸어서 1분」으로 올린다 — 「0분」은 걸을 필요가 없다는 뜻으로 읽히는데 그런 경우가
/// 아니고(좌표가 다르니 거리는 있다), 반올림해 0 이 되는 값일 뿐이다.
func walkMinutesLabel(walkSeconds: Int) -> String {
    let minutes = max((walkSeconds + 59) / 60, 1)
    return "걸어서 \(minutes)분"
}


/// 매칭 조건의 보조 문구 한 줄 — 「혼자 출발한다」·「예약은 2명부터」·「고를 시간이 없다」가 쓴다.
///
/// 세 자리가 **같은 모양**이어야 하는 이유는 세 문구가 같은 성질이기 때문이다: 정상 선택의 결과를
/// 알려 주는 말이고, 오류가 아니다. 빨강·경고 아이콘을 쓰지 않는 근거는 `soloCapacityNotice` 를 그리는
/// 자리의 주석에 적어 둔 그대로다 — 오류로 읽히면 사용자는 고를 수 있는 값을 「막힌 값」으로 본다.
/// 줄바꿈을 막지 않는다(줄 수 제한 없음): 큰 글꼴 설정에서 잘린 안내보다 두 줄이 낫고, 이 줄은
/// 세로 스크롤 영역 안이라 잘릴 일이 없다.
private struct ConditionNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 12)
    }
}

/// 라벨을 **윗줄**로 올리고 그 아래에 고르는 조각(날짜 띠·시각 휠)을 놓는 조건 행.
///
/// `ConditionRow` 의 「라벨 + 남는 폭에 오른쪽 정렬」은 칩 서너 개짜리 모양이라 띠(8칸)·휠(두 개)을 담지
/// 못한다 — 그래서 라벨을 위로 올리고 조각이 폭을 다 쓰게 한다. 예전 이름은 `ScrollableChipRow`
/// 였다(날짜·시각이 가로 스크롤 칩이던 시절).
///
/// - Parameter trailing: 라벨 줄 오른쪽 끝의 보조 글(날짜 띠 위의 「11월」 — `reservationMonthLabel`). 없으면 nil
private struct PickerSection<Content: View>: View {
    let label: String
    var trailing: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text(label)
                    .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing)
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .fixedSize()
                }
            }
            Spacer().frame(height: 8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

private struct ConditionRow<Chips: View>: View {
    let label: String
    @ViewBuilder let chips: () -> Chips

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(label)
                .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer().frame(width: 12)
            // 칩 행이 **남는 폭 안에서** 오른쪽 정렬된다. 예전엔 라벨 뒤 Spacer(weight) + 고정폭 칩이라
            // 작은 폰(360dp)에서 칩 3개가 카드 밖으로 밀려 「500m」이 잘리고 선택 칩의 파란 배경이 카드
            // 모서리를 넘어 보였다(실기 QA). 칩은 앱 공용 `MoyeotaChip` 이고 칩 사이는 8(터치 간격 규칙)이다.
            HStack(alignment: .center, spacing: 8) {
                chips()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        // 칩이 48 터치 영역을 가지므로(`MoyeotaChip`) 위아래 4 만 더해 줄 높이 56 이 된다
        .padding(.vertical, 4)
    }
}
