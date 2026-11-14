import MoyeotaDesignSystem
import MoyeotaDomain
@preconcurrency import NMapsMap
import PresentationCore
import QuartzCore
import SwiftUI

let ExploreSheetStateKey = "explore.sheetState"
let ExplorePartyListScrollKey = "explore.partyList"
let ExploreReservationListScrollKey = "explore.reservationList"

/// 바텀시트 3단계 — 17 지도(peek) / 18 지도+리스트(half) / 19 리스트(full)
public enum ExploreSheetState: CaseIterable, Hashable, Sendable {
    case peek, half, full
}

/// 지도에 그릴 기기 실위치 1건.
///
/// 좌표만으로는 「얼마나 믿을 수 있는 위치인지」를 그릴 수 없어 오차 반경·방향을 함께 받는다.
/// 세 값이 항상 같은 fix 에서 나와야 원과 점이 어긋나지 않으므로 하나로 묶는다.
///
/// - Parameters:
///   - accuracyMeters: 수평 오차 반경(m). nil 이면 정확도 원을 그리지 않는다
///   - bearingDegrees: 진행 방향(도, 0 = 북). nil 이면 방향 표시 없이 점만 그린다
public struct MyLocationFix: Equatable, Sendable {
    public var position: LatLng
    public var accuracyMeters: Float?
    public var bearingDegrees: Float?

    public init(position: LatLng, accuracyMeters: Float? = nil, bearingDegrees: Float? = nil) {
        self.position = position
        self.accuracyMeters = accuracyMeters
        self.bearingDegrees = bearingDegrees
    }
}

/// 조회 영역을 가시 영역보다 이만큼 넓힌다(각 변의 폭·높이 대비 비율).
///
/// 서버는 **출발지가 영역 안**인 방만 돌려주므로, 보이는 만큼만 물으면 카메라가 조금만 움직여도
/// 가장자리의 방이 목록에서 빠져 **마커가 깜빡인다**(실기 QA: 확대·축소 중 출발지가 화면에 있는데도
/// 사라졌다 나타남). 조회 영역이 화면보다 넓으면 그 경계가 화면 밖에 있어 눈에 띄지 않는다.
/// 지도 앱이 뷰포트보다 넓게 미리 받아 두는 것과 같은 이유다.
private let BoundsMarginRatio = 0.3

/// 지도에 지금 보이는 영역 — 방 목록 조회 범위.
///
/// 필드 순서를 서버 파라미터 순서(swLat → swLng → neLat → neLng)와 맞춰 둔다.
/// 위도·경도가 뒤바뀌어도 서버는 오류가 아니라 **빈 목록**을 돌려주므로,
/// 순서를 틀리면 「이 근처엔 방이 없네」로 보여 발견이 늦는다.
public struct MapBounds: Hashable, Sendable {
    public var swLat: Double
    public var swLng: Double
    public var neLat: Double
    public var neLng: Double

    public init(swLat: Double, swLng: Double, neLat: Double, neLng: Double) {
        self.swLat = swLat
        self.swLng = swLng
        self.neLat = neLat
        self.neLng = neLng
    }

    /// 가시 영역을 `BoundsMarginRatio` 만큼 넓힌 조회용 영역.
    /// 위도는 ±90, 경도는 ±180 을 넘지 않게 자른다.
    func expanded(ratio: Double = BoundsMarginRatio) -> MapBounds {
        let latMargin = (neLat - swLat) * ratio
        let lngMargin = (neLng - swLng) * ratio
        return MapBounds(
            swLat: max(swLat - latMargin, -90.0),
            swLng: max(swLng - lngMargin, -180.0),
            neLat: min(neLat + latMargin, 90.0),
            neLng: min(neLng + lngMargin, 180.0)
        )
    }
}

/// 예약 모드가 그릴 것 전부 — 모드·날짜 선택지·목록·상태.
///
/// 파라미터 10개를 `ExploreScreen` 에 늘어놓지 않고 한 덩어리로 묶는다. 묶을 수 있는 근거는 이
/// 값들이 **함께만 뜻이 있다**는 것이다: 모드가 `ExploreMode.realtime` 이면 나머지는 쓰이지 않고,
/// `ExploreMode.byDate` 가 아니면 날짜 선택지도 쓰이지 않는다.
///
/// **기본값이 「예약 기능 전」의 화면**이다 — 아무것도 넘기지 않으면 지금까지와 똑같이 실시간 목록만
/// 그린다(예시 방이 새지 않도록 목록에 기본값을 두지 않는 `parties` 와 같은 조심).
///
/// - Parameters:
///   - items: 서버가 준 **순서 그대로**. 화면도 뷰모델도 재정렬하지 않는다
///     (`ReservationFinderViewModel.UiState.success`)
///   - loading: **새 목록**(날짜·도착지·모드)을 아직 읽지 못했다. `items` 는 비어 있고(앞 날짜의 줄을 남기지
///     않는다) 목록 자리는 비워 둔다 — 가운데 스피너 없이 새로고침 버튼의 도는 고리만 기다림을 보여 준다
///     (버튼이 없을 때만 목록 맨 위에 작은 스피너, `showListLoadingFallback`).
///     같은 목록을 다시 읽을 때(주기·버튼·지도 이동·복귀)는 false 다(보던 목록을 그대로 둔다)
///   - locating: 「날짜로 찾기」인데 아직 내 좌표가 없다 — 조회를 **못 한 것**이지 실패가 아니다
///   - destinationName: 검색에 **실어 보낸** 도착지의 이름. nil 이면 도착지 없이 검색했다
///     (그때 서버는 `destinationNearby` 를 주지 않는다)
///   - now: 「오늘」·「내일」·출발 시각 표기의 기준 시각. 순수 판정 함수들은 시계를 읽지 않으므로
///     (`ReservationRules` 주석) **화면도 호출부가 넘긴 이 값만** 쓴다 — 그릴 때마다 시계를
///     읽으면 같은 목록이 프레임마다 다른 글자를 갖는다
public struct ReservationPaneUi: Hashable, Sendable {
    public var mode: ExploreMode
    public var dates: [LocalDate]
    public var selectedDate: LocalDate?
    public var items: [ReservationCardUi]
    public var loading: Bool
    public var failed: Bool
    public var locating: Bool
    public var destinationName: String?
    public var now: Date

    public init(
        mode: ExploreMode = .realtime,
        dates: [LocalDate] = [],
        selectedDate: LocalDate? = nil,
        items: [ReservationCardUi] = [],
        loading: Bool = false,
        failed: Bool = false,
        locating: Bool = false,
        destinationName: String? = nil,
        now: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.mode = mode
        self.dates = dates
        self.selectedDate = selectedDate
        self.items = items
        self.loading = loading
        self.failed = failed
        self.locating = locating
        self.destinationName = destinationName
        self.now = now
    }

    /// 접힘 요약·목록 제목·빈 상태 문구가 함께 쓰는 「오늘」·「11월 9일 (일)」. 날짜가 없으면 nil.
    var selectedDateLabel: String? {
        selectedDate.map { reservationDateLabel(date: $0, today: dates.first ?? $0) }
    }

    /// 도착지를 실어 보냈는가 — 정렬 설명과 배지 노출이 이 값으로 갈린다.
    var destinationSent: Bool { destinationName != nil }
}

/// 지도 카메라 1건 (중심 + 줌)
private struct MapCamera: Equatable {
    var center: LatLng
    var zoom: Double
}

/// 지도 카메라 — **화면 레벨**에서 들고 있는다.
///
/// 지도는 시트 단계와 무관하게 하나지만, 스택 위 화면에서 돌아오는 등으로 지도 인스턴스가 다시 만들어질 수 있다.
/// 카메라를 지도 안에만 두면 그때마다 기준점으로 되돌아가 보던 목록이 통째로 사라진다.
///
/// 값이 바뀌어도 화면을 다시 그릴 일이 없어 관찰 대상으로 두지 않는다(원본도 지도를 만들 때 한 번만 읽는다).
@MainActor
private final class ExploreCameraState {
    /// 마지막으로 본 카메라. nil 이면 아직 지도가 한 번도 뜨지 않은 상태
    var camera: MapCamera?

    /// 첫 실위치로 한 번 옮겼는가. 매 fix 마다 따라가면 사용자가 지도를 팬할 수 없다
    var centeredOnMyLocation = false
}

/// 접힘(17) 시트 높이 — 손잡이 줄 + 요약.
///
/// 디자인 다듬기(2026-11)에서 다시 쟀다: 손잡이 줄 28(`PeekHandleZone`) + 제목 `HeadingLg` 한 줄(18×1.35 ≈ 24)
/// + 부제 `BodySm` 최대 두 줄(13×1.5×2 = 39) = 91 → 4/8 격자로 올려 **96 그대로**다.
/// 실시간 목록이 있을 때는 부제가 없어(디자인 QA E7) 요약 줄이 남는 높이 가운데에 선다(`PeekSummaryRow`).
///
/// 상태마다 높이를 바꾸지 않는 이유: 이 값은 지도 `contentPadding` 이기도 해서, 목록이 0건↔N건을
/// 오갈 때마다 높이가 바뀌면 지도의 보이는 영역이 흔들리고 그 영역으로 다시 조회한다.
private let PeekSheetHeight: CGFloat = 96

/// 시트 맨 위 손잡이 줄 — 위 12 + 손잡이 4 + 아래 12 (`MapSheetScaffold` 와 같다)
private let PeekHandleZone: CGFloat = 28

/// 반펼침(18)에서 시트 위로 남기는 지도 높이
private let HalfMapHeight: CGFloat = 300

/// 시트 앵커 사이를 오가는 정착 애니메이션(ms)
private let SheetAnimMs = 260.0

/// 이 속도(px/s) 이상으로 던지면 위치와 무관하게 그 방향의 다음 앵커로 붙는다 (`MapSheetScaffold` 와 같은 값).
/// 단위가 px 라 제스처 속도(pt/s)에 화면 배율을 곱해 비교한다.
private let SheetFlingVelocity: CGFloat = 400

/// 목록 헤더와 첫 카드 사이 간격 — 18·19 공통.
private let ListHeaderGap: CGFloat = 12

/// 시트 아래 「새 동승 방 만들기」 줄의 위아래 여백 — 새로고침 버튼이 FULL 에서 CTA 윗변을 잴 때도 쓴다.
private let SheetCtaPadding: CGFloat = MoyeotaSpacing.Xs

/// 새로고침 버튼이 없을 때 목록 맨 위에 두는 스피너 자리(`ListLoadingFallback`) — 예전 목록 스피너의 높이다.
private let ListLoadingFallbackHeight: CGFloat = 120

/// 앵커 = 시트 높이. HALF 는 지도 300 을 남기고, FULL 은 지도를 다 덮는다
func exploreSheetAnchor(_ state: ExploreSheetState, containerHeight: CGFloat) -> CGFloat {
    switch state {
    case .peek: PeekSheetHeight
    case .half: max(containerHeight - HalfMapHeight, PeekSheetHeight)
    case .full: containerHeight
    }
}

/// 17·18·19 · 근처 동승 찾기 [V07/V07b/V07c]
///
/// **지도는 하나다.** 시트 단계(PEEK/HALF/FULL)는 지도 위에 얹힌 시트의 **높이**만 바꾼다 —
/// 예전에는 단계마다 다른 화면(전체 지도 / 320dp 지도 / 지도 없음)으로 갈아끼워서
/// 단계를 바꿀 때마다 지도가 새로 만들어지고(타일 재로드·카메라 복원) 전환 애니메이션도 없었다(실기 QA).
/// 지금은 시트 높이가 앵커 사이를 애니메이션으로 오가고, 지도는 `contentPadding` 만 따라 바뀐다.
///
/// 시트 상태 전환:
/// - 핸들·헤더를 **드래그**하면 가까운 앵커(또는 던진 방향의 다음 앵커)로 정착 — 세 단계 모두
/// - PEEK 의 위 꺾쇠 버튼 → HALF · HALF/FULL 헤더의 「지도 접기 / 지도 펼치기」(+ 꺾쇠) → FULL/HALF
///   (접기·펼치기는 **이 한 버튼**뿐이다 — 타이틀 행의 「🗺 지도」는 행 높이를 흔들어 뺐다)
///
/// 이동(디스크립션):
/// - 「{단계} · {목적지} 보기」 배너 → 진행 중인 방의 단계 화면 21/25/26 (onOngoingRideClick)
/// - 지도 마커 탭 / 카드 「합류」 → 20 합류 확인 (onJoinParty)
/// - 「새 동승 방 만들기」 → 15 목적지 입력 (onCreateRoomClick)
/// - 하단탭 홈 / 채팅 / 마이 → 14 / 24 / 35 (onTabSelect)
///
/// 검증·상태:
/// - 방 목록은 **지도에 보이는 범위**로 조회한 결과다(`onVisibleBoundsChange`) — 마커·리스트·**헤더의 N개**가 같은 목록
/// - 지도는 네이버 실지도. 내 위치는 기기 GPS(`myLocation`) — 못 받으면 기본 카메라(`MoyeotaDefaultCamera`) 범위를 보여준다
/// - 위치 권한 없으면 지도 대신 권한 요청 안내 + 「위치 권한 허용」 버튼 (locationGranted)
/// - 후보 0건이면 peek 문구 자리에 빈 상태 + 지도를 움직여 보라는 안내
///   (**내 방을 걸러내 0건이 된 경우**는 다른 문구다 — `myPartyHidden`)
/// - 내가 이미 참여 중인 방은 목록·마커에 **없다**(`ExploreRoute` 의 `exploreList`) — 돌아가는 길은
///   맨 위 진행 중 방 배너 한 번이고, 목록 카드는 20 을 거치는 더 긴 우회로였다
/// - 진행 중 탑승 없으면 상단 배너 숨김 (`activeRide` 가 nil). 배너가 있으면 지도 줌 컨트롤이 그 아래로 내려간다
/// - 정원 찬 방(3/3)은 「합류」 비활성 + 「마감」 표기
/// - 15초 카운트다운 새로고침 버튼은 세 모드·세 시트 단계 모두에 있다(`refreshButtonPlacement`). **목록 가운데에
///   스피너를 두지 않는다** — 같은 목록을 다시 읽을 때는 보던 목록을 그대로 두고, 새 목록을 읽는 동안은 자리를 비우고
///   헤더에 개수를 적지 않는다. 기다림은 버튼의 도는 고리 하나로만 보인다 — 버튼이 없을 때(위치 권한 없음 등)만
///   목록 맨 위에 작은 스피너를 둔다(`showListLoadingFallback`)
public struct ExploreScreen: View {
    private let parties: [Ride]
    private let activeRide: Ride?
    private let myPartyHidden: Bool
    private let stale: Bool
    private let loading: Bool
    private let refresh: ExploreRefreshUi?
    private let onRefreshClick: () -> Void
    private let locationGranted: Bool
    private let myLocation: MyLocationFix?
    private let onJoinParty: (Ride) -> Void
    private let onOngoingRideClick: () -> Void
    private let onCreateRoomClick: () -> Void
    private let onRequestLocationPermission: () -> Void
    private let onVisibleBoundsChange: (MapBounds) -> Void
    private let reservations: ReservationPaneUi
    private let onModeSelect: (ExploreMode) -> Void
    private let onDateSelect: (LocalDate) -> Void
    private let onRetryReservations: () -> Void
    private let onPickSearchDestination: (() -> Void)?
    private let onClearSearchDestination: () -> Void
    private let onTabSelect: (MoyeotaTab) -> Void

    @State private var sheetState: ExploreSheetState
    // 스택 위 화면에서 돌아와도 보던 자리를 유지한다 (시트 단계 변경으로는 이제 지도가 재생성되지 않는다)
    @State private var cameraState = ExploreCameraState()
    // 진행 배너 높이 — 지도 위 contentPadding 으로 넘겨 줌 컨트롤(+/−)이 배너 아래로 내려가게 한다
    // (작은 폰에서 배너와 줌 버튼이 겹치던 문제)
    @State private var bannerHeight: CGFloat = 0
    @Environment(\.tabSavedState) private var tabSavedState

    /// - Parameters:
    ///   - parties: 지도에 보이는 범위의 방 목록. **기본값이 없다** — 예시 방이 프로덕션에 새는 길을 막는다.
    ///     **내가 참여 중인 방은 이미 빠져 있다**(`ExploreRoute` 의 `exploreList`) — 마커·카드·헤더의
    ///     N 이 모두 이 한 목록에서 나오므로 세 자리가 함께 빠진다.
    ///   - activeRide: 지금 진행 중인 내 방. nil 이면 상단 배너를 그리지 않는다
    ///   - myPartyHidden: `parties` 에서 **내 방을 실제로 빼냈는가**(`ExploreList.myPartyHidden`).
    ///     빈 목록 문구만 이 값으로 갈린다 — 주변에 방이 내 방뿐이면 걸러낸 뒤 목록이 0건이 되는데,
    ///     그때 「이 근처엔 동승이 없어요」는 **거짓말**이다(방은 있고, 그게 내 방이다).
    ///     목록이 비지 않았을 때는 아무것도 바꾸지 않는다: 「내 방 1개는 뺐어요」는 돌아갈 길이 이미
    ///     배너로 있는 상황에서 더해지는 소음이다.
    ///   - stale: 주기 갱신이 **연속으로** 실패해 목록이 낡았는가(`ExploreViewModel.UiState.success` 의 stale ·
    ///     「곧 출발」은 `ReservationFinderViewModel.UiState.success` 의 stale).
    ///     true 라도 보던 목록·마커는 그대로 둔다 — 지도를 에러 화면으로 바꾸지 않는다는 기존 판단을
    ///     지키고, 대신 타이틀 줄에 **비차단 표시**만 올린다. 기본값 false 는 「문제 없음」이다.
    ///   - loading: 실시간 목록을 **아직 읽지 못했다**(첫 조회·에러 화면의 「다시 시도」, `ExploreViewModel.UiState.loading`).
    ///     이 화면은 그동안에도 지도와 빈 목록을 그린다 — 가운데 스피너를 두지 않고, 기다림은 새로고침 버튼의 도는
    ///     고리 하나로만 보인다(버튼이 없으면 목록 맨 위의 작은 스피너, `showListLoadingFallback`). 헤더는 개수를
    ///     적지 않고(`exploreHeaderCount`) 빈 목록 문구(「이 근처엔 동승이 없어요」)도 그리지 않는다 — 아직 묻지도
    ///     못한 것을 「없다」고 말하지 않는다. 예약 모드는 `reservations.loading` 을 본다.
    ///   - refresh: **카운트다운 새로고침 버튼**이 그릴 것. **nil 이면 버튼이 없다** — 주기 갱신을 하지 않는 모드
    ///     (`exploreAutoRefreshes`, 지금은 없다)이거나 물어볼 것이 없을 때(「날짜로 찾기」가 내 위치를 기다리는 중)
    ///     호출부가 nil 을 넘긴다. 세 시트 단계 모두에서 보이고 자리는 `refreshButtonPlacement` 가 정한다.
    ///   - onRefreshClick: 새로고침 버튼 — 지금 보이는 목록을 즉시 다시 읽고 15초를 처음부터 센다.
    ///   - myLocation: 기기 실위치. nil = 권한 없음 · 아직 fix 없음 → 지도는 기본 카메라 위치에서 시작한다
    ///   - reservations: 예약 모드의 상태 전부. 기본값이 **예약 기능 전의 화면**이다(`ReservationPaneUi`).
    ///
    ///     목록·마커·헤더의 N 은 모드에 따라 `parties` 또는 `reservations.items` 에서 나오는데,
    ///     **한 번에 하나다** — 두 목록을 섞지 않는 근거는 둘이 서로 다른 영역을 본다는 것이다
    ///     (`ReservationFinder.swift` 의 1급 사실 표).
    ///   - onVisibleBoundsChange: 지도 카메라가 멈출 때마다 보이는 영역을 올려보낸다 → 그 범위의 방 목록으로 갱신
    ///   - onPickSearchDestination: 「날짜로 찾기」의 도착지를 고르러 간다(15 목적지). **nil 이면 칩을 그리지 않는다** —
    ///     배선되지 않은 버튼을 보여 주지 않기 위해서다. 도착지 없이도 검색은 정상이고
    ///     (서버 계약: 둘 다 또는 둘 다 아니다) 그때는 정렬이 출발 시각 순이다.
    public init(
        parties: [Ride],
        activeRide: Ride? = nil,
        myPartyHidden: Bool = false,
        stale: Bool = false,
        loading: Bool = false,
        refresh: ExploreRefreshUi? = nil,
        onRefreshClick: @escaping () -> Void = {},
        locationGranted: Bool = true,
        myLocation: MyLocationFix? = nil,
        initialSheetState: ExploreSheetState = .peek,
        reservations: ReservationPaneUi = ReservationPaneUi(),
        onJoinParty: @escaping (Ride) -> Void = { _ in },
        onOngoingRideClick: @escaping () -> Void = {},
        onCreateRoomClick: @escaping () -> Void = {},
        onRequestLocationPermission: @escaping () -> Void = {},
        onVisibleBoundsChange: @escaping (MapBounds) -> Void = { _ in },
        onModeSelect: @escaping (ExploreMode) -> Void = { _ in },
        onDateSelect: @escaping (LocalDate) -> Void = { _ in },
        onRetryReservations: @escaping () -> Void = {},
        onPickSearchDestination: (() -> Void)? = nil,
        onClearSearchDestination: @escaping () -> Void = {},
        onTabSelect: @escaping (MoyeotaTab) -> Void = { _ in }
    ) {
        self.parties = parties
        self.activeRide = activeRide
        self.myPartyHidden = myPartyHidden
        self.stale = stale
        self.loading = loading
        self.refresh = refresh
        self.onRefreshClick = onRefreshClick
        self.locationGranted = locationGranted
        self.myLocation = myLocation
        self.reservations = reservations
        self.onJoinParty = onJoinParty
        self.onOngoingRideClick = onOngoingRideClick
        self.onCreateRoomClick = onCreateRoomClick
        self.onRequestLocationPermission = onRequestLocationPermission
        self.onVisibleBoundsChange = onVisibleBoundsChange
        self.onModeSelect = onModeSelect
        self.onDateSelect = onDateSelect
        self.onRetryReservations = onRetryReservations
        self.onPickSearchDestination = onPickSearchDestination
        self.onClearSearchDestination = onClearSearchDestination
        self.onTabSelect = onTabSelect
        _sheetState = State(initialValue: initialSheetState)
    }

    /// **마커·카드·헤더의 N 이 나오는 단 하나의 목록.** 모드가 그 출처를 고르고, 아래 어디에서도
    /// 두 목록을 합치지 않는다 — 실시간 목록은 지도 범위, 예약은 모드마다 다른 영역이라
    /// (`ReservationFinder.swift` 표) 섞이면 「지도에 보이는데 목록에 없는 방」이 생긴다.
    private var shownRides: [Ride] {
        reservations.mode.isReservation ? reservations.items.map(\.ride) : parties
    }

    public var body: some View {
        let mode = reservations.mode
        VStack(spacing: 0) {
            StatusBarSpacer()

            // 타이틀 행 — 탭 첫 화면 공용 머리줄(`MoyeotaTabHeader`, 52 **고정 높이**). 단계에 따라 버튼이
            // 생기고 사라지면 행 높이가 흔들려 제목이 움직였다.
            //
            // 낡은 목록 표시는 **고정 높이인 이 줄**에 둔다 — 지도 위에 띄우면 시트를 끝까지 올린
            // 상태(FULL, 지도가 통째로 가려짐)에서 보이지 않고, 시트 안에 두면 접힘(PEEK) 높이가
            // 흔들린다. 이 자리면 세 단계 모두에서 같은 자리에 보이고 레이아웃도 밀리지 않는다.
            //
            // **주기 갱신이 없는 모드(「날짜로 찾기」)에서는 그리지 않는다.** `stale` 은 주기 조회의 연속
            // 실패 표시인데 그 모드에서는 주기 조회가 없어서, 남아 있던 true 를 그리면 지금 보고 있는
            // 목록이 낡았다는 **거짓 경고**가 된다. 「곧 출발」은 15초 주기가 생겨 이제 그린다.
            if stale && exploreAutoRefreshes(mode: mode) {
                // 머리줄은 trailing 이 있으면 끝 여백을 4 로 줄인다(아이콘 버튼 자리) — 배지는 버튼이 아니라
                // 나머지 12 를 직접 줘서 16 화면 여백에 맞춘다
                MoyeotaTabHeader(title: "근처 동승 찾기") {
                    StaleListNotice()
                        .fixedSize()
                        .padding(.trailing, 12)
                }
            } else {
                MoyeotaTabHeader(title: "근처 동승 찾기")
            }

            // 모드 칩 — **지도 위가 아니라 지도 밖**에 둔다. 시트를 끝까지 올린 상태(FULL)에서도
            // 보여야 모드를 되돌릴 수 있고, 시트 안에 두면 접힘 높이가 모드에 따라 흔들린다
            // (낡은 목록 표시를 타이틀 줄에 둔 것과 같은 근거).
            ExploreModeRow(selected: mode, onSelect: onModeSelect)

            GeometryReader { geometry in
                mapAndSheet(containerHeight: geometry.size.height)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }

            MoyeotaBottomBar(selected: .explore, onSelect: onTabSelect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
        // 원본 `rememberSaveable` 의 `sheetState` 자리 — 탭을 다녀와도 같은 단계로 돌아온다(`ExploreRoute` 가 초깃값으로 넘긴다).
        .onChange(of: sheetState) { _, state in
            tabSavedState?.set(ExploreSheetStateKey, state)
            // 원본은 접힘에서 목록이 컴포지션에서 빠져 스크롤 위치가 사라진다. 탭 이동으로는 사라지면 안 되므로 여기서만 지운다.
            if state == .peek {
                tabSavedState?.remove(ExplorePartyListScrollKey)
                tabSavedState?.remove(ExploreReservationListScrollKey)
            }
        }
        // 모드가 실시간과 예약 사이를 오가면 원본은 빠진 쪽 목록이 컴포지션에서 내려가 그 스크롤 위치도 사라진다.
        // 예약 두 모드 사이에서는 같은 목록 자리라 남는다.
        .onChange(of: mode.isReservation) { _, reservation in
            tabSavedState?.remove(reservation ? ExplorePartyListScrollKey : ExploreReservationListScrollKey)
        }
    }

    private func mapAndSheet(containerHeight: CGFloat) -> some View {
        // 배경 지도 — 단계가 바뀌어도 같은 인스턴스. 시트에 덮이는 높이만 contentPadding 으로 알린다.
        // FULL 에서는 지도가 통째로 가려지므로 HALF 기준으로 고정한다(패딩이 뷰 높이를 넘으면 안 된다)
        let mapBottomInset = min(
            exploreSheetAnchor(sheetState, containerHeight: containerHeight),
            exploreSheetAnchor(.half, containerHeight: containerHeight)
        )
        let mode = reservations.mode
        return ZStack(alignment: .top) {
            if locationGranted {
                ExploreMap(
                    rides: shownRides,
                    // 예약 마커는 캡션에 **시각을 먼저** 적는다 — 「곧 출발」에서 고르는 기준이
                    // 인원이 아니라 몇 시냐다(`reservationMarkerCaption`). 실시간은 그대로 인원만.
                    reservationCaptions: mode.isReservation,
                    now: reservations.now,
                    myLocation: myLocation,
                    cameraState: cameraState,
                    onMarkerClick: onJoinParty,
                    onVisibleBoundsChange: onVisibleBoundsChange,
                    contentPadding: EdgeInsets(top: bannerHeight, leading: 0, bottom: mapBottomInset, trailing: 0)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LocationPermissionNotice(onRequestPermission: onRequestLocationPermission)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let activeRide {
                ActiveRideBanner(ride: activeRide, onClick: onOngoingRideClick)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    .padding(.vertical, 4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bannerHeight = $0 }
            }

            ExploreSheet(
                sheetState: $sheetState,
                containerHeight: containerHeight,
                parties: parties,
                shownCount: shownRides.count,
                loading: loading,
                myPartyHidden: myPartyHidden,
                reservations: reservations,
                // 새로고침 버튼은 시트를 따라 움직여야 해서 시트 뷰가 그린다(`ExploreSheet` 설명). 권한이 없어
                // 지도가 없을 때는 넘기지 않는다(`refreshButtonShown`) — 조회는 기준 범위로 그대로 돌고, 그동안의
                // 기다림은 목록의 대체 로딩 표시가 보여 준다(`showListLoadingFallback`).
                refresh: refreshButtonShown(refresh: refresh, locationGranted: locationGranted) ? refresh : nil,
                onRefreshClick: onRefreshClick,
                onJoinParty: onJoinParty,
                onCreateRoomClick: onCreateRoomClick,
                onDateSelect: onDateSelect,
                onRetryReservations: onRetryReservations,
                onPickSearchDestination: onPickSearchDestination,
                onClearSearchDestination: onClearSearchDestination
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Compose `Animatable` + `tween(SheetAnimMs)` 자리. SwiftUI 애니메이션은 진행 중인 값을 읽을 수 없는데, 정착 중에
/// 시트를 다시 잡으면 그 순간의 높이에서 이어 가야 하므로(원본 `dragPx ?: sheetPx.value`) 값을 프레임마다 직접 계산한다.
@MainActor
@Observable
private final class ExploreSheetAnimatable {
    /// nil 이면 앵커에 앉아 있다. 첫 프레임부터 목표 상태로 그리기 위한 값이다(깜빡임 없음).
    private(set) var value: CGFloat?

    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var from: CGFloat = 0
    @ObservationIgnored private var target: CGFloat = 0
    @ObservationIgnored private var startTime: CFTimeInterval = 0

    func snapTo(_ newValue: CGFloat?) {
        stop()
        value = newValue
    }

    func animateTo(_ newTarget: CGFloat, from start: CGFloat) {
        stop()
        from = start
        target = newTarget
        value = start
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(
            target: SheetDisplayLinkProxy { [weak self] in
                self?.tick()
                return self != nil
            },
            selector: #selector(SheetDisplayLinkProxy.fire(_:))
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        let fraction = (CACurrentMediaTime() - startTime) * 1000 / SheetAnimMs
        if fraction >= 1 {
            value = target
            stop()
        } else {
            value = from + (target - from) * CGFloat(FastOutSlowIn.value(at: fraction))
        }
    }
}

/// Compose `FastOutSlowInEasing` — `tween` 의 기본 곡선이다.
private let FastOutSlowIn = UnitCurve.bezier(
    startControlPoint: UnitPoint(x: 0.4, y: 0),
    endControlPoint: UnitPoint(x: 0.2, y: 1)
)

@MainActor
private final class SheetDisplayLinkProxy: NSObject {
    // false 를 돌려주면 주인이 사라진 것이다. 런루프가 링크를 잡고 있어 직접 끊어야 한다.
    private let action: @MainActor () -> Bool

    init(action: @escaping @MainActor () -> Bool) {
        self.action = action
    }

    @objc func fire(_ link: CADisplayLink) {
        if !action() {
            link.invalidate()
        }
    }
}

/// 시트 — 높이만 앵커 사이를 오간다. 내용은 **목표 단계** 기준이라 애니메이션 중에 흔들리지 않는다.
///
/// 원본은 한 함수 안에 있지만 프레임마다 바뀌는 높이를 이 뷰에 가둔다. 위로 새면 애니메이션 내내 지도까지 다시 계산된다.
/// 같은 이유로 **카운트다운 새로고침 버튼**도 여기서 그린다 — 원본은 버튼 자리를 시트의 실측 높이(드래그·정착 중의
/// 값)와 하단 CTA 의 실측 높이로 정한다(`refreshButtonPlacement`: 접힘·반펼침은 시트 윗변 16 위, FULL 은 목록 위
/// CTA 16 위). 그 두 높이를 아는 곳이 이 뷰뿐이다.
private struct ExploreSheet: View {
    @Binding var sheetState: ExploreSheetState
    let containerHeight: CGFloat
    let parties: [Ride]
    /// 헤더·요약의 N — 모드가 고른 목록(`ExploreScreen.shownRides`)의 방 수다
    let shownCount: Int
    /// 실시간 목록을 아직 읽지 못했다(`ExploreScreen` 의 같은 이름 설명)
    let loading: Bool
    let myPartyHidden: Bool
    let reservations: ReservationPaneUi
    /// nil 이면 새로고침 버튼이 없다(물어볼 것이 없음·권한 없음 — `refreshButtonShown`). 그때 읽는 중이면 목록이
    /// 작은 스피너를 둔다(`showListLoadingFallback`)
    let refresh: ExploreRefreshUi?
    let onRefreshClick: () -> Void
    let onJoinParty: (Ride) -> Void
    let onCreateRoomClick: () -> Void
    let onDateSelect: (LocalDate) -> Void
    let onRetryReservations: () -> Void
    let onPickSearchDestination: (() -> Void)?
    let onClearSearchDestination: () -> Void

    @State private var animatable = ExploreSheetAnimatable()
    // 하단 CTA(「새 동승 방 만들기」)의 실측 높이 — FULL 에서 새로고침 버튼을 그 16 위에 띄운다
    @State private var ctaHeight: CGFloat = 0
    // 드래그 중에는 이 값만 따라간다 (`MapSheetScaffold` 와 같은 이유 — 매 프레임 정착 값을 건드리면 정착을 끊는다)
    @State private var drag = SheetDragTracker()
    // 시스템이 제스처를 취소하면(전화 수신·제어 센터·앱 전환) `onEnded` 가 불리지 않는다.
    // 끝났다는 신호를 받는 길은 이 값이 저절로 되돌아오는 것뿐이다.
    @GestureState private var dragging = false

    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase

    private func anchor(_ state: ExploreSheetState) -> CGFloat {
        exploreSheetAnchor(state, containerHeight: containerHeight)
    }

    /// 드래그가 없을 때의 시트 높이 — 정착 중이면 그 값, 아니면 앵커.
    private var restingHeight: CGFloat {
        animatable.value ?? anchor(sheetState)
    }

    var body: some View {
        let sheetHeight = drag.height ?? restingHeight
        // FULL 에서는 모서리를 각지게 — 둥근 모서리 틈으로 뒤의 지도가 비친다.
        // 모서리·그림자는 다른 시트와 같은 토큰이다(디자인 QA G3·G4: 20 · 8)
        let radius: CGFloat = sheetState == .full ? 0 : MoyeotaShape.SheetRadius
        let sheetShape = UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .circular)
        let mode = reservations.mode
        // 카운트다운 새로고침 버튼 — **세 시트 단계 모두에서 보인다**(2026-11, 오너 UX 피드백 2차).
        // 접힘·반펼침은 네이버 줌 컨트롤과 같은 세로선(`RefreshButtonEndInset`), 시트 윗변 16 위(지도 위)이고,
        // 지도가 다 가려지는 FULL 에서는 목록 위 오른쪽 아래에 뜬다(CTA 16 위). 자리는 `refreshButtonPlacement` 가
        // 정하고, 시트를 따라 움직이도록 **실측 높이**(드래그·정착 애니메이션 중의 값)를 넘긴다. 끝까지 끌어 올리는
        // 중 지도 위에 다 들어가지 못하면 그 순간 목록 위로 내려온다. 권한이 없어 지도가 없을 때는 없다(호출부가 nil,
        // `refreshButtonShown`) — 그때 읽는 중이면 목록이 작은 스피너를 둔다(`showListLoadingFallback`).
        let placement = refreshButtonPlacement(
            sheetState: sheetState,
            containerHeight: containerHeight,
            sheetHeight: sheetHeight,
            // CTA 는 접힘에서는 없다. 있으면 아래 여백 + 버튼 높이가 그 윗변이다
            bottomCtaTop: sheetState == .peek ? nil : SheetCtaPadding + ctaHeight
        )
        // 버튼이 목록 위에 떠 있으면 목록 끝에 그만큼 여백을 둔다 — 끝까지 내린 마지막 줄의 「합류」가 버튼 밑에 깔리지 않게
        let listBottomPadding: CGFloat = refresh != nil && placement.spot == .overList ? RefreshButtonListClearance : 0

        VStack(alignment: .trailing, spacing: 0) {
            if let refresh, placement.spot == .aboveSheet {
                ExploreRefreshButton(ui: refresh, onClick: onRefreshClick)
                    .padding(.trailing, placement.end)
                    .padding(.bottom, RefreshButtonGap)
            }
            sheetBody(mode: mode, sheetHeight: sheetHeight, sheetShape: sheetShape, listBottomPadding: listBottomPadding)
        }
        // 목록 위에 뜬 버튼 — 시트 아래 끝(= 컨테이너 아래 끝)에서 잰다. 시트 **위에** 그린다
        .overlay(alignment: .bottomTrailing) {
            if let refresh, placement.spot == .overList {
                ExploreRefreshButton(ui: refresh, onClick: onRefreshClick)
                    .padding(.trailing, placement.end)
                    .padding(.bottom, placement.bottom)
            }
        }
        // 단계가 바뀌면(탭·드래그 정착) 그 앵커로 애니메이션
        .onChange(of: sheetState) { oldState, newState in
            animatable.animateTo(anchor(newState), from: animatable.value ?? anchor(oldState))
        }
        // 컨테이너 높이가 바뀌면 다시 앉힌다. 앵커에 앉은 채라면(nil) 저절로 새 앵커를 따라간다.
        .onChange(of: containerHeight) { _, _ in
            guard let current = animatable.value else { return }
            animatable.animateTo(anchor(sheetState), from: current)
        }
        // 떠나면 정착을 끝낸 것으로 친다. 돌아왔을 때 어중간한 높이에 머물지 않게 앵커로 앉힌다.
        .onDisappear {
            animatable.snapTo(nil)
            drag.clear()
        }
        // 원본 `draggable` 의 `onDragStopped` 는 포인터 입력이 취소돼도 불린다. 같은 결과가 되게 여기서 정착시킨다.
        // 정상 종료에서는 `onEnded` 와 이 신호의 순서에 기대지 않는다 — `settleDrag` 는 어느 순서로 불려도 같은 곳에 닿는다.
        .onChange(of: dragging) { _, active in
            if !active { settleInterruptedDrag() }
        }
        // 앱이 전면에서 내려가면 드래그는 이어질 수 없다. `@GestureState` 가 되돌아오는 길과 겹쳐도 한 번만 정착한다.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { settleInterruptedDrag() }
        }
    }

    private func sheetBody(
        mode: ExploreMode,
        sheetHeight: CGFloat,
        sheetShape: UnevenRoundedRectangle,
        listBottomPadding: CGFloat
    ) -> some View {
        // 헤더의 N — 목록을 아직 읽지 못했으면 적지 않는다(「0개」는 「없다」로 읽힌다)
        let headerCount = mode.isReservation
            ? exploreHeaderCount(
                shownCount,
                loading: reservations.loading,
                locating: reservations.locating,
                failed: reservations.failed
            )
            : exploreHeaderCount(shownCount, loading: loading, locating: false, failed: false)
        return VStack(spacing: 0) {
            // 드래그 타깃 = 핸들 + 그 아래 한 줄(요약 또는 헤더)
            VStack(spacing: 0) {
                SheetHandle()
                    .frame(maxWidth: .infinity)
                    .frame(height: PeekHandleZone)
                if sheetState == .peek {
                    PeekSummaryRow(
                        mode: mode,
                        count: shownCount,
                        dateLabel: reservations.selectedDateLabel,
                        myPartyHidden: myPartyHidden,
                        // 접힘 요약은 **개수만** 보므로 실패·대기 중에도 0건이다 — 그 상태에서
                        // 「없어요」라고 적지 않도록 이유를 받아 둔다(`reservationStatusTitle`).
                        statusText: mode.isReservation
                            ? reservationStatusTitle(
                                loading: reservations.loading,
                                locating: reservations.locating,
                                failed: reservations.failed
                            )
                            : (loading ? NEARBY_LOADING_TEXT : nil),
                        onRaise: { sheetState = .half }
                    )
                } else {
                    ListHeaderRow(
                        mode: mode,
                        count: headerCount,
                        dateLabel: reservations.selectedDateLabel,
                        destinationSent: reservations.destinationSent,
                        mapShown: sheetState == .half,
                        onToggleMap: { sheetState = sheetState == .half ? .full : .half }
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture)

            if sheetState != .peek {
                Spacer(minLength: 0).frame(height: ListHeaderGap)
                if sheetState == .full {
                    HorizontalDivider(color: MoyeotaColor.Hairline)
                    Spacer(minLength: 0).frame(height: ListHeaderGap)
                }
                // **이 목록이 무엇을 기준으로 찾은 것인가.** 예약 모드에서만 한 줄 붙는다 —
                // 「곧 출발」은 지도 범위, 「날짜로 찾기」는 내 위치 1km 라서 적어 두지 않으면
                // 지도를 옮겨 둔 사람이 결과를 잘못 읽는다(`exploreAreaNote`).
                if let note = exploreAreaNote(mode: mode, destinationSent: reservations.destinationSent) {
                    Text(note)
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    Spacer(minLength: 0).frame(height: ListHeaderGap)
                }
                // 날짜·도착지 선택은 「날짜로 찾기」에서만 뜻이 있다(「곧 출발」은 30분 고정이다)
                if mode == .byDate {
                    ReservationDateRow(
                        dates: reservations.dates,
                        selected: reservations.selectedDate,
                        destinationName: reservations.destinationName,
                        onDateSelect: onDateSelect,
                        onPickDestination: onPickSearchDestination,
                        onClearDestination: onClearSearchDestination
                    )
                    Spacer(minLength: 0).frame(height: ListHeaderGap)
                }
                if mode.isReservation {
                    ReservationList(
                        pane: reservations,
                        myPartyHidden: myPartyHidden,
                        onJoin: onJoinParty,
                        onRetry: onRetryReservations,
                        loadingFallback: showListLoadingFallback(
                            loading: reservations.loading,
                            refreshButtonShown: refresh != nil
                        ),
                        bottomPadding: listBottomPadding
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    PartyList(
                        parties: parties,
                        loading: loading,
                        loadingFallback: showListLoadingFallback(loading: loading, refreshButtonShown: refresh != nil),
                        myPartyHidden: myPartyHidden,
                        onJoinParty: onJoinParty,
                        showEndOfList: sheetState == .full,
                        bottomPadding: listBottomPadding
                    )
                    .frame(maxHeight: .infinity)
                }
                // 문구는 모드와 무관하게 그대로 둔다 — 누르면 15 목적지로 가고, 예약 방을
                // 만드는 길도 그 뒤의 16 모달 안에 있다(「예약 방 만들기」로 바꾸면 16 이
                // 기본값 「지금 출발」로 열리는 것과 어긋난다).
                //
                // 공용 주 CTA 다(디자인 QA E3) — 예전 전용 버튼(r16·48)은 앱의 다른 주 CTA(알약·52)와
                // 모양이 달랐다. 이 시트의 **단 하나뿐인 솔리드 파랑**이고, 줄마다의 「합류」는 옅은 알약이다.
                // 「＋」 글자는 뺐다 — 아이콘 대신 쓴 글자다(G10).
                PrimaryCtaButton(text: "새 동승 방 만들기", onClick: onCreateRoomClick)
                    // 여백 바깥이 아니라 버튼 자체를 잰다 — 새로고침 버튼을 이 윗변 16 위에 띄운다
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { ctaHeight = $0 }
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    .padding(.vertical, SheetCtaPadding)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: sheetHeight, alignment: .top)
        .background(MoyeotaColor.SurfaceCanvas)
        .clipShape(sheetShape)
        .sheetShadow(sheetShape)
    }

    private var dragGesture: some Gesture {
        // 시트가 드래그를 따라 움직이므로 지역 좌표로 재면 값이 되먹임된다. 전역 좌표로 잰다.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                drag.track(y: value.location.y, resting: restingHeight, range: anchor(.peek)...anchor(.full))
            }
            .onEnded { value in
                settleDrag(velocity: value.velocity.height)
            }
    }

    /// 취소된 드래그를 정착시킨다. 던진 속도를 알 수 없으니 가까운 앵커로 간다(원본도 취소 때 속도 0 이다).
    /// 이미 끝난 드래그면 아무것도 하지 않는다.
    private func settleInterruptedDrag() {
        if drag.height != nil { settleDrag(velocity: 0) }
    }

    /// - Parameter velocity: 드래그 속도(pt/s)
    private func settleDrag(velocity: CGFloat) {
        let from = drag.finish(resting: restingHeight)
        let target = settleTarget(
            fromPx: from * displayScale,
            velocity: velocity * displayScale,
            anchorPx: { anchor($0) * displayScale }
        )
        // 단계가 그대로면 `onChange` 가 불리지 않으므로 늘 직접 정착시킨다.
        // 단계가 바뀌면 `onChange` 가 같은 값에서 다시 시작할 뿐이라 결과가 같다.
        animatable.animateTo(anchor(target), from: from)
        sheetState = target
    }
}

/// 손을 뗀 위치·속도로 정착할 앵커. 빠르게 던지면 그 방향의 **다음** 앵커, 아니면 가장 가까운 앵커.
func settleTarget(
    fromPx: CGFloat,
    velocity: CGFloat,
    anchorPx: (ExploreSheetState) -> CGFloat
) -> ExploreSheetState {
    let ordered = ExploreSheetState.allCases.sorted { anchorPx($0) < anchorPx($1) }
    if velocity > SheetFlingVelocity {
        // 아래로 던짐 → 현재 위치보다 낮은 앵커 중 가장 가까운 것
        return ordered.last { anchorPx($0) < fromPx - 1 } ?? ordered[0]
    }
    if velocity < -SheetFlingVelocity {
        return ordered.first { anchorPx($0) > fromPx + 1 } ?? ordered[ordered.count - 1]
    }
    return ordered.min { abs(anchorPx($0) - fromPx) < abs(anchorPx($1) - fromPx) } ?? ordered[0]
}

/// 목록이 0건일 때의 두 줄 — 접힘 요약(17)과 리스트 빈 상태(18·19)가 **같은 말**을 쓴다.
///
/// 걸러내기 전의 목록에 내 방이 있었는가(`myPartyHidden`)로 갈린다. 「이 근처엔 동승이 없어요」는
/// 주변에 내 방뿐일 때 **거짓말**이다 — 방은 있고 그게 내 방이며, 그래서 목록이 빈 것이다.
/// 그 경우 사실만 말한다: 이 범위에 남의 방이 없다.
///
/// 내 방으로 **돌아가는 길을 문구로 가리키지 않는다**(「위 배너를 누르세요」를 쓰지 않았다) —
/// 시트를 끝까지 올린 상태(FULL)에서는 그 배너가 시트에 가려 보이지 않아 위치를 말하는 문장이
/// 그 순간 틀린 말이 된다. 배너는 PEEK·HALF 에서 바로 보이고, 두 줄의 역할은 「왜 비었는지」까지다.
func emptyListCopy(myPartyHidden: Bool) -> (first: String, second: String) {
    myPartyHidden
        ? (first: "지금은 내 방뿐이에요", second: "지도를 움직여 다른 방을 찾아보세요")
        : (first: "이 근처엔 동승이 없어요", second: "지도를 움직여 보세요")
}

/// 실시간 목록을 아직 읽지 못했다 — 접힘 요약 한 줄이 쓴다(예약의 `RESERVATION_LOADING_TEXT` 와 같은 자리).
///
/// 0건을 「이 근처엔 동승이 없어요」로 말하지 않기 위한 문구다. 목록 쪽은 글도 스피너도 두지 않고 자리를
/// 비워 둔다 — 기다림은 새로고침 버튼의 도는 고리가 보여 준다(버튼이 없으면 작은 스피너, `showListLoadingFallback`).
let NEARBY_LOADING_TEXT = "동승 목록을 불러오는 중이에요"

/// 17 접힘 요약 — 「주변 합승 N개」. N 은 헤더·마커와 같은 목록의 방 수다.
///
/// 제목·빈 상태 문구는 **모드가 정한다**(`explorePeekTitle`·`reservationEmptyCopy`) — 실시간 쪽
/// 문구는 한 글자도 바뀌지 않았다.
struct PeekSummaryRow: View {
    let mode: ExploreMode
    let count: Int
    let dateLabel: String?
    let myPartyHidden: Bool
    let statusText: String?
    let onRaise: () -> Void

    var body: some View {
        let isEmpty = count == 0
        let (emptyTitle, emptySubtitle) = mode.isReservation
            ? reservationEmptyCopy(mode: mode, dateLabel: dateLabel, myPartyHidden: myPartyHidden)
            : emptyListCopy(myPartyHidden: myPartyHidden)
        // 0건일 때 **왜 0건인지**가 있으면 그것부터 — 실패·대기를 「없어요」로 말하지 않는다
        let title: String = if isEmpty, let statusText {
            statusText
        } else if isEmpty {
            emptyTitle
        } else {
            explorePeekTitle(mode: mode, count: count, dateLabel: dateLabel)
        }
        // 「목적지 정하면 바로 자동 매칭」은 지웠다 — 목적지를 정하면 **새 방이 만들어지고**
        // (16 「같이 탈 사람 찾기」 → `POST /matching/rooms`) 사람이 합류하기를 기다린다.
        // 목적지로 기존 방에 자동으로 넣어 주는 기능은 없다(2026-10-13).
        //
        // 예약 모드에서는 **무엇을 기준으로 찾았는지**를 그 자리에 적는다(`exploreAreaNote`) —
        // 접힘 상태에서는 목록 위의 같은 줄이 보이지 않아 여기가 유일한 자리다.
        // 예약 모드에서는 **도착지 정렬 설명을 빼고** 영역 기준만 적는다(destinationSent = false) —
        // 접힘 한 줄에 두 문장을 넣으면 잘린다. 그 설명은 목록 위의 같은 줄이 맡는다.
        //
        // 실시간 목록이 있을 때는 **부제를 두지 않는다**(디자인 QA E7). 예전 「위로 올리면 리스트, 목적지를
        // 정하면 새 방을 만들어요」는 화면 사용법을 글로 설명한 줄이었다 — 손잡이와 위 꺾쇠가 이미 그 말을 한다.
        let subtitle: String? = if isEmpty && statusText == nil {
            emptySubtitle
        } else if mode.isReservation {
            exploreAreaNote(mode: mode, destinationSent: false)
        } else if isEmpty {
            emptySubtitle
        } else {
            nil
        }
        // 남는 높이(`PeekSheetHeight` − 손잡이 줄) 가운데에 선다 — 부제가 없는 상태에서 제목이 위에 붙고
        // 아래가 비어 보이지 않게. 끝 여백 4 는 48 꺾쇠 버튼의 아이콘이 16 화면 여백에 오게 한다.
        HStack(spacing: 0) {
            if !isEmpty {
                Circle()
                    .fill(MoyeotaColor.Primary500)
                    .frame(width: 8, height: 8)
                Spacer(minLength: 0).frame(width: 8)
            }
            // 제목은 한 줄, 부제는 두 줄까지 — 넘치면 말줄임한다(원본 `maxLines`·`Ellipsis`)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .moyeotaText(MoyeotaType.HeadingLg.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle, !subtitle.isBlank {
                    Text(subtitle)
                        .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 48 버튼 — 예전엔 18 꺾쇠 그림 자체만 눌렸다(디자인 QA G12)
            Button(action: onRaise) {
                ChevronIcon(direction: .up, size: MoyeotaIconSize.Md, tint: MoyeotaColor.TextMute)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(PressFeedbackStyle())
            .accessibilityLabel("목록 펼치기")
        }
        .padding(.leading, MoyeotaSpacing.ScreenGutter)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity)
        .frame(minHeight: PeekSheetHeight - PeekHandleZone)
    }
}

/// 18·19 목록 헤더 — 「주변 합승 N개 · 가까운 순」 + 지도 접기/펼치기 **단일** 토글.
///
/// 정렬을 말하는 조건이 모드마다 다르다(`exploreListTitle`) — 서버가 보장하는 것만 적는다.
struct ListHeaderRow: View {
    let mode: ExploreMode
    /// nil 이면 개수를 적지 않는다 — 목록을 아직 읽지 못했다(`exploreHeaderCount`)
    let count: Int?
    let dateLabel: String?
    let destinationSent: Bool
    let mapShown: Bool
    let onToggleMap: () -> Void

    var body: some View {
        // 끝 여백 8 + 버튼 안쪽 8 = 글자 끝이 16 화면 여백에 온다
        HStack(spacing: 0) {
            Text(exploreListTitle(mode: mode, count: count, dateLabel: dateLabel, destinationSent: destinationSent))
                .moyeotaText(MoyeotaType.HeadingLg.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0).frame(width: 8)
            // 글자로 쓰던 꺾쇠(⌄ ⌃)는 그린 아이콘으로 바꿨다(G10) — 글꼴마다 모양·높이가 달랐다.
            // 파랑을 쓰지 않는다: 이 시트의 파랑은 「새 동승 방 만들기」 하나다. 48 터치(G12).
            TextLinkButton(
                text: mapShown ? "지도 접기" : "지도 펼치기",
                onClick: onToggleMap,
                color: MoyeotaColor.TextBody,
                style: MoyeotaType.BodySm.copy(fontWeight: .semibold)
            ) {
                ChevronIcon(
                    direction: mapShown ? .down : .up,
                    size: MoyeotaIconSize.Sm,
                    tint: MoyeotaColor.TextBody
                )
            }
            // 토글은 접히지 않는다(원본 `TextLinkButton` 의 `maxLines = 1`·`softWrap = false`) — 줄어드는 쪽은 제목이다
            .fixedSize()
        }
        .padding(.leading, MoyeotaSpacing.ScreenGutter)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity)
    }
}

/// 「실시간 / 곧 출발 / 날짜로 찾기」 칩 한 줄.
///
/// 하단탭(`MoyeotaBottomBar`)처럼 보이지 않게 **칩**으로 둔다 — 이건 화면 이동이 아니라 같은 화면의
/// 필터이고, 지도 카메라·시트 단계는 모드를 바꿔도 그대로다. 디자인시스템의 `MoyeotaChip` 을 쓴다
/// (앱의 단 하나뿐인 칩이다 — 디자인 QA G6).
///
/// ### 간격 (2026-11, 오너 UX 피드백 · 디자인 QA 4-8)
/// 예전에는 칩 줄이 제목 줄과 지도 사이에 위아래 여백 없이 끼어 지도에 맞닿아 있었다.
/// - **시작선**: 제목과 같은 `MoyeotaSpacing.ScreenGutter`(16) — 두 줄이 한 머리글로 읽힌다
///   (`MoyeotaTabHeader` 도 같은 값을 쓴다)
/// - **칩 사이 8**, 제목 아래 **8**, 지도 위 **12** — 4/8 리듬(`spacing.xs`·`spacing.sm`)
/// - **터치 타깃 48**: 칩의 보이는 높이는 36 이고 `MoyeotaChip` 이 스스로 위아래 6 씩 눌리는 자리를
///   더한다. 그 6 은 투명하므로 위 「8·12」는 **보이는 칩 테두리 기준**이다(줄 여백 2·6 + 터치 여유 6)
///
/// 세 칩이 393pt 폭에 들어오지만 큰 글꼴 설정에서는 넘칠 수 있어 가로 스크롤을 둔다. 여백을 스크롤
/// **안쪽**에 둬서 첫 칩은 제목 선에서 시작하고 스크롤하면 가장자리까지 흐른다.
private struct ExploreModeRow: View {
    let selected: ExploreMode
    let onSelect: (ExploreMode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExploreMode.allCases, id: \.self) { mode in
                    MoyeotaChip(
                        text: exploreModeLabel(mode: mode),
                        selected: mode == selected,
                        onClick: { onSelect(mode) }
                    )
                }
            }
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
        // 높이는 칩 한 줄만 — 아래 지도·목록이 남은 높이를 갖는다
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }
}

/// 「날짜로 찾기」의 **주간 달력 띠**(오늘~7일 뒤)와 그 아래 **도착지 칩**.
///
/// 날짜는 16 도착지 확인과 **같은 컴포넌트**다(`ReservationDateStrip`) — 같은 8일 창을 두 화면이 다른
/// 모양(칩 vs 달력)으로 고르면 같은 날이 다르게 보인다(2026-11, 오너 UX 피드백). 띠 위에는 덮는 달을
/// 한 줄로 적는다(`reservationMonthLabel`) — 칸에는 일(日) 숫자만 있다.
///
/// 도착지 칩은 띠 **아래 자기 줄**(8 간격)로 옮겼다 — 예전에는 날짜 칩 끝에 붙어 가로 스크롤 끝까지
/// 가야 보였다. 둘 다 같은 검색 요청의 입력이라 붙어 있되, 도착지는 **있어도 되고 없어도 되는 값**이라
/// 날짜와 다른 줄이 낫다. `onPickDestination` 이 nil 이면 칩을 **그리지 않는다**: 도착지를 고르는 길
/// (15 목적지)이 배선되지 않았을 수 있고, 그때 칩을 보여 주면 눌러도 아무 일도 일어나지 않는다.
/// 도착지 없이 검색하는 것은 서버가 인정하는 정상 경로다(둘 다 또는 둘 다 아니다).
///
/// 「전체」 칸은 없다 — 검색은 하루 단위다(`date` 필수).
private struct ReservationDateRow: View {
    let dates: [LocalDate]
    let selected: LocalDate?
    let destinationName: String?
    let onDateSelect: (LocalDate) -> Void
    let onPickDestination: (() -> Void)?
    let onClearDestination: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 달 표기는 묶음 머리말이다(디자인 QA 4-3 — 「11월」·「11–12월」) — 아래 8 은 SectionLabel 이 준다
            if let month = reservationMonthLabel(dates: dates) {
                SectionLabel(text: month)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            }
            ReservationDateStrip(
                dates: dates,
                selected: selected,
                onSelect: onDateSelect,
                // 띠의 첫 칸이 시트 본문(16 화면 여백)과 같은 선에서 시작한다
                contentPadding: EdgeInsets(
                    top: 0,
                    leading: MoyeotaSpacing.ScreenGutter,
                    bottom: 0,
                    trailing: MoyeotaSpacing.ScreenGutter
                )
            )
            if destinationName != nil || onPickDestination != nil {
                // 띠와 칩 사이는 **보이는 칩 테두리 기준 8** — 칩이 위아래로 둔 투명한 터치 여유 6 에 2 를 더한다
                Spacer(minLength: 0).frame(height: 2)
                HStack(spacing: 0) {
                    if let destinationName {
                        // 고른 도착지는 **이름으로** 보여 준다 — 「도착지 1곳」 같은 말로는 어디를 보냈는지
                        // 알 수 없고, 그 좌표가 결과 순서를 바꾼다(가까운 방이 먼저).
                        MoyeotaChip(
                            text: "\(destinationName) \(RESERVATION_CLEAR_DESTINATION_LABEL)",
                            selected: true,
                            onClick: onClearDestination
                        )
                    } else if let onPickDestination {
                        MoyeotaChip(
                            text: RESERVATION_ADD_DESTINATION_LABEL,
                            selected: false,
                            onClick: onPickDestination
                        )
                    }
                }
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ─── 공용 조각 ──────────────────────────────────────────────────────────────

/// 카드 더미가 아니라 **목록 줄**이다(디자인 QA E5) — 흰 시트 안에 흰 테두리 카드를 쌓으면 반펼침에서
/// 두 장 남짓만 보였다. 줄은 화면 폭을 다 쓰고 줄 사이는 안쪽으로 들인 헤어라인 하나다.
private struct PartyList: View {
    let parties: [Ride]
    /// 아직 읽지 못했다 — 빈 목록 문구를 그리지 않고 자리를 비워 둔다(기다림은 새로고침 버튼이 보여 준다)
    let loading: Bool
    /// 읽는 중인데 새로고침 버튼이 없다 — 비워 두면 빈 화면이라 작은 스피너를 둔다(`showListLoadingFallback`)
    let loadingFallback: Bool
    let myPartyHidden: Bool
    let onJoinParty: (Ride) -> Void
    let showEndOfList: Bool
    /// 목록 끝 여백 — 새로고침 버튼이 목록 위에 떠 있을 때 마지막 줄이 그 밑에 깔리지 않게(원본 `contentPadding`)
    let bottomPadding: CGFloat

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(parties.enumerated()), id: \.offset) { index, ride in
                    if index > 0 { ListRowDivider() }
                    PartyCard(ride: ride, onJoin: onJoinParty)
                }
                if parties.isEmpty {
                    if !loading {
                        EmptyListNotice(myPartyHidden: myPartyHidden)
                    } else if loadingFallback {
                        ListLoadingFallback()
                    }
                } else if showEndOfList {
                    // 스펙 19: 마지막 페이지면 목록의 끝을 알린다 (범위 기준)
                    Text("이 근처는 여기까지예요")
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.bottom, bottomPadding)
            .savedScrollOffset(ExplorePartyListScrollKey)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity)
    }
}

/// 목록 줄 사이 — 화면 여백만큼 안쪽으로 들인 헤어라인
private struct ListRowDivider: View {
    var body: some View {
        HorizontalDivider(color: MoyeotaColor.Hairline)
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
    }
}

/// 새로고침 버튼이 없을 때 목록 자리의 기다림 표시(`showListLoadingFallback`) — 앱 공용 스피너(`LoadingBox`)를
/// 목록 맨 위 `ListLoadingFallbackHeight` 안에 둔다. 예전처럼 목록 한가운데를 차지하지 않는다.
private struct ListLoadingFallback: View {
    var body: some View {
        LoadingBox()
            .frame(maxWidth: .infinity)
            .frame(height: ListLoadingFallbackHeight)
    }
}

/// 예약 목록 — `PartyList` 와 같은 모양이고 **카드와 빈 상태만 다르다**.
///
/// 「목록의 끝」 줄(`PartyList` 의 `showEndOfList`)을 두지 않는다: 서버가 검색을 **최대 100개**로
/// 자르는데 그게 「이 날은 여기까지」인지 「100개에서 잘렸는지」를 앱이 알 수 없어, 끝을 단정하면
/// 거짓이 될 수 있다. 실시간 쪽은 뷰포트 전부를 받아 그 말이 참이었다.
private struct ReservationList: View {
    let pane: ReservationPaneUi
    let myPartyHidden: Bool
    let onJoin: (Ride) -> Void
    let onRetry: () -> Void
    /// 읽는 중인데 새로고침 버튼이 없다 — 비워 두면 빈 화면이라 작은 스피너를 둔다(`showListLoadingFallback`)
    let loadingFallback: Bool
    /// 목록 끝 여백 — 새로고침 버튼이 목록 위에 떠 있을 때 마지막 줄이 그 밑에 깔리지 않게(원본 `contentPadding`)
    let bottomPadding: CGFloat

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(pane.items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { ListRowDivider() }
                    ReservationCard(item: item, now: pane.now, onJoin: onJoin)
                }
                if pane.items.isEmpty {
                    ReservationEmptyState(
                        pane: pane,
                        myPartyHidden: myPartyHidden,
                        loadingFallback: loadingFallback,
                        onRetry: onRetry
                    )
                }
            }
            .padding(.bottom, bottomPadding)
            .savedScrollOffset(ExploreReservationListScrollKey)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity)
    }
}

/// 예약 목록이 비었을 때의 **네 가지 상태** — 섞으면 안 되는 것들이다.
///
/// | 상태 | 뜻 | 사용자가 할 일 |
/// |---|---|---|
/// | 조회 중 | 아직 모른다 | 기다린다 — 자리를 **비워 둔다**. 기다림은 새로고침 버튼의 도는 고리가 보여 준다(가운데 스피너 없음). 버튼이 없으면 작은 스피너(`showListLoadingFallback`) |
/// | 내 위치 확인 중 | **아직 묻지도 못했다**(1km 의 중심이 없다) | 기다린다 |
/// | 실패 | 못 물어봤다 | 다시 시도 |
/// | 0건 | 물어봤고 **없다** | 날짜를 바꾸거나 지도를 옮긴다 |
///
/// 아래 둘을 합치면 장애가 「그 날은 예약이 없네」로 위장되고 사용자는 날짜만 계속 바꾼다
/// (16 추천의 `nearbyLoadFailed` 가 같은 이유로 갈라져 있다).
private struct ReservationEmptyState: View {
    let pane: ReservationPaneUi
    let myPartyHidden: Bool
    let loadingFallback: Bool
    let onRetry: () -> Void

    var body: some View {
        if pane.loading {
            // 비워 둔다 — 예전의 가운데 스피너(`LoadingBox`)는 「날짜로 찾기」에서 날짜를 바꿀 때마다 목록 한가운데를
            // 차지했다(2026-11, 오너 UX 피드백 2차). 헤더도 개수를 적지 않는다(`exploreHeaderCount`).
            // 새로고침 버튼이 없을 때만(위치 권한 없음 등) 작은 스피너를 둔다(`showListLoadingFallback`)
            if loadingFallback { ListLoadingFallback() }
        } else if pane.locating {
            ReservationNotice(text: RESERVATION_LOCATING_TEXT)
        } else if pane.failed {
            ReservationNotice(text: RESERVATION_LOAD_FAILED_TEXT, onRetry: onRetry)
        } else {
            let (title, subtitle) = reservationEmptyCopy(
                mode: pane.mode,
                dateLabel: pane.selectedDateLabel,
                myPartyHidden: myPartyHidden
            )
            VStack(spacing: 4) {
                Text(title)
                    .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            .padding(.vertical, 32)
        }
    }
}

/// 한 줄 안내(+ 선택적 재시도). 화면을 통째로 덮지 않는다 — 지도·모드 칩은 그대로 둔다.
private struct ReservationNotice: View {
    let text: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                .multilineTextAlignment(.center)
            if let onRetry {
                // 48 터치 + 눌림 표시(G12) — 예전엔 글자 크기만큼만 눌렸다
                TextLinkButton(text: "다시 시도", onClick: onRetry)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
        .padding(.vertical, 32)
    }
}

/// 예약 방 줄 하나 — `PartyCard` 와 **같은 조각으로 짜되 출발 시각이 맨 위**다.
///
/// 실시간 줄은 `departureLabel`(서버가 만든 「3분 후 출발 예정 · 6.2km」)을 장소 아래에 둔다.
/// 예약에서 그 자리에 시각을 두면 가장 중요한 값이 세 번째 줄로 내려간다 — 이 목록에서 고르는
/// 기준은 **몇 시에 출발하는가**이고(오늘 오후 6:30 과 내일 오전 9:00 은 전혀 다른 방이다) 장소는
/// 그다음이다. 시각을 읽을 수 없으면 줄을 **그리지 않는다**(`reservationDepartureLabel` 이 nil) —
/// 「시간 미정」 같은 자리값을 두면 약속 시간이 정해진 방을 미정으로 보여 주는 거짓이 된다.
///
/// 「도착지도 1km 안」 배지는 서버가 true 라고 말했을 때만 붙는다(`destinationNearbyBadge`).
private struct ReservationCard: View {
    let item: ReservationCardUi
    let now: Date
    let onJoin: (Ride) -> Void

    var body: some View {
        let ride = item.ride
        // 정원을 모르면(0) 「마감」이라고 단정하지 않는다 — `PartyCard` 와 같은 규칙이다.
        let full = ride.capacity > 0 && ride.members.count >= ride.capacity
        let headcount = headcountLabel(joined: ride.members.count, capacity: ride.capacity)
        let nearby = destinationNearbyBadge(destinationNearby: item.destinationNearby)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // 출발 시각이 이 줄의 제목이다 — 검정 굵은 글자로 둔다. 파랑은 시트의 CTA 몫이라 쓰지 않고,
                // 숫자 폭을 고정해 줄마다 시각의 끝이 출렁이지 않게 한다
                if let departure = reservationDepartureLabel(departureAt: ride.departureAt, now: now) {
                    // 원본 `maxLines = 1` 은 말줄임 없이 잘린다 — `lineLimit(1)` 은 원본에 없는 「…」을 덧붙인다
                    Text(departure)
                        .moyeotaText(MoyeotaType.BodyStrong.tabularNums().hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }
                // 제목이 시각이라 장소는 부제 모양(24 채팅 목록과 같은 조각, emphasizePlace = false)
                RoutePlaceLine(place: RoutePlace(label: "출발지", place: ride.origin))
                RoutePlaceLine(place: RoutePlace(label: "목적지", place: ride.destination))
                if !headcount.isEmpty || nearby != nil {
                    HStack(spacing: 6) {
                        if !headcount.isEmpty { StatusBadge(kind: .neutral, text: headcount) }
                        // 「도착지도 1km 안」 — 인원 배지(회색)와 **다른 색**이어야 다른 종류의 사실로 읽힌다.
                        // 서버가 확인해 준 사실이라 초록을 그대로 둔다(디자인 QA E2)
                        if let nearby { StatusBadge(kind: .success, text: nearby) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0).frame(width: 8)
            JoinButton(full: full, onClick: { onJoin(ride) })
        }
        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

private struct PartyCard: View {
    let ride: Ride
    let onJoin: (Ride) -> Void

    var body: some View {
        // 정원을 모르면(0) 「마감」이라고 단정하지 않는다 — `0 >= 0` 이 참이라 전에는 인원·정원을 둘 다
        // 모르는 방이 **마감으로 보였다.** 인원 문구를 지우면서 버튼만 마감으로 남기면 같은 카드가 두
        // 가지 말을 한다. 실제로 찼는지는 탭해서 들어간 20 이 방 상세로 다시 판정한다(`joinGate`).
        let full = ride.capacity > 0 && ride.members.count >= ride.capacity
        // 인원 문구는 16 추천 카드와 **같은 함수**를 쓴다(`headcountLabel`) — 리터럴로 쓰던 동안
        // 인원을 모르는 방을 「0/3명」, 정원을 모르는 방을 「2/0명」으로 그렸다(없는 상태다).
        // 빈 문자열이면 배지째 지운다(그 판단은 `headcountLabel` 설명에 있다).
        //
        // 회색 배지다(디자인 QA E2) — 예전 호박색 바탕 + 흰 11 은 대비가 2.15:1 이었고, 호박색은 이 앱에서
        // 「기다리는 중」이라는 **상태**를 뜻한다. 인원은 상태가 아니라 사실이다.
        let headcount = headcountLabel(joined: ride.members.count, capacity: ride.capacity)
        // 겹친 빈 아바타(사진·이름 없는 회색 원 N개)는 지웠다(디자인 QA E4) — 바로 옆 「2/3명」 배지와
        // 같은 말을 그림으로 한 번 더 했을 뿐이다.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // 출발지·목적지를 라벨 붙여 두 줄로 — 「A → B」 한 줄은 주소가 길면 어디서 갈리는지 읽기 어렵다.
                // 이 줄에는 다른 제목이 없어 장소가 제목이다(emphasizePlace) — 24 채팅 목록과 같은 조각이다
                RoutePlaceLine(place: RoutePlace(label: "출발지", place: ride.origin), emphasizePlace: true)
                RoutePlaceLine(place: RoutePlace(label: "목적지", place: ride.destination), emphasizePlace: true)
                // 서버 목록 매핑(`PartyMappers`)은 이 값을 늘 빈 문자열로 둔다 — 그대로 그리면 모든 줄에 빈 줄이
                // 하나씩 생겼다(디자인 QA E1). 값이 올 때만 세운다
                if !ride.departureLabel.isBlank {
                    Text(ride.departureLabel)
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !headcount.isEmpty {
                    StatusBadge(kind: .neutral, text: headcount)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0).frame(width: 8)
            JoinButton(full: full, onClick: { onJoin(ride) })
        }
        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

/// 줄 끝의 「합류」 — 정원 찬 방(3/3)은 비활성 + 「마감」 표기 (스펙 18).
///
/// 공용 `CompactPillButton` 이다(디자인 QA E3): 보이는 높이 32·터치 48 의 옅은 파랑 알약. 예전 34
/// 솔리드 파랑 버튼은 손가락에 작았고 줄마다 하나씩 있어 시트의 진짜 주 CTA(「새 동승 방 만들기」)를 묻었다.
private struct JoinButton: View {
    let full: Bool
    let onClick: () -> Void

    var body: some View {
        CompactPillButton(text: full ? "마감" : "합류", onClick: onClick, enabled: !full)
    }
}

// 위치 권한 없을 때 지도 대신 안내 (스펙 17).
// 자동 요청을 한 번 거부한 뒤에도 여기서 다시 요청할 수 있어야 지도로 돌아올 길이 남는다
// (iOS 는 시스템이 한 번만 물으므로 두 번째부터 이 버튼이 설정 앱으로 보낸다 — `MyLocationController.requestPermission`).
private struct LocationPermissionNotice: View {
    let onRequestPermission: () -> Void

    var body: some View {
        ZStack {
            MoyeotaColor.SurfaceSoft
            VStack(spacing: 4) {
                Text("위치 권한이 필요해요")
                    .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                Text("권한을 허용하면 내 주변 동승을 지도로 볼 수 있어요")
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                    .multilineTextAlignment(.center)
                // 보이는 알약은 36, 눌리는 자리는 48(G12) — 이 상태에서 화면의 유일한 행동이라 솔리드 파랑이다
                Button(action: onRequestPermission) {
                    Text("위치 권한 허용")
                        .moyeotaText(MoyeotaType.ButtonMd.hangulTrimmed, color: MoyeotaColor.TextOnDark)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(MoyeotaColor.Primary500, in: MoyeotaShape.Pill)
                        .frame(minWidth: 48, minHeight: 48)
                        .contentShape(MoyeotaShape.Pill)
                }
                .buttonStyle(PressFeedbackStyle())
            }
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
        }
    }
}

/// 「최신 정보를 받지 못했어요」 — 목록을 **덮지 않는** 표시.
///
/// 띄우는 조건은 `staleAfterPollFailures` 가 정한다(연속 실패 2회 = 30초). 여기서 하는 일은 그
/// 사실을 조용히 알리는 것뿐이고, 이 표시에는 재시도 버튼을 달지 않는다 — 폴링이 15초마다 알아서 다시
/// 읽고 한 번 성공하면 이 표시가 사라진다. 지금 바로 다시 읽고 싶으면 지도의 새로고침 버튼이 있다
/// (`ExploreRefreshButton`) — 같은 일을 하는 버튼을 두 자리에 두지 않는다.
private struct StaleListNotice: View {
    var body: some View {
        // 공용 상태 배지(빨강 = 오류)다 — 예전 전용 알약(11 Bold)과 색은 같고 글자 규칙만 맞췄다
        StatusBadge(kind: .error, text: "최신 정보를 받지 못했어요")
    }
}

private struct EmptyListNotice: View {
    let myPartyHidden: Bool

    var body: some View {
        // 접힘 요약(17)과 **같은 두 줄**이다 — 같은 상황을 두 자리가 다르게 말하지 않게 한 곳에서 뽑는다
        let (title, subtitle) = emptyListCopy(myPartyHidden: myPartyHidden)
        VStack(spacing: 4) {
            Text(title)
                .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
        .padding(.vertical, 32)
    }
}

// ─── 지도 (네이버 실지도 + 내 위치·합승 마커) ────────────────────────────────

/// 내 주변 1km 남짓이 한 화면에 들어오는 줌 — 첫 범위 조회가 이 정도를 훑는다
private let ExploreZoom = 15.0

/// 지도가 아직 범위를 알려주지 못할 때 쓰는 기준 범위의 반변(도).
///
/// `ExploreZoom` 의 실제 가시 영역(Pixel 6 실측 위도 ±0.006 · 경도 ±0.004)에 맞춘 값이다.
/// 지도가 뜨면 곧바로 실제 `NMFMapView.contentBounds` 로 덮어쓰지만, 그 사이에 「지도에 없는
/// 방」이 리스트에 잠깐 떴다 사라지지 않도록 처음부터 비슷한 크기로 묻는다.
private let DefaultBoundsHalfSpanDeg = 0.006

/// 지도가 범위를 알려주기 전의 첫 조회 범위.
///
/// `center` 가 nil(위치 권한 거부·아직 fix 없음)이면 지도가 처음 보여주는 기본 카메라
/// (`MoyeotaDefaultCamera`) 주변을 조회한다 — 지도에 보이는 곳과 목록이 어긋나지 않게.
public func defaultExploreBounds(center: LatLng?) -> MapBounds {
    let origin = center ?? MoyeotaDefaultCamera
    return MapBounds(
        swLat: origin.latitude - DefaultBoundsHalfSpanDeg,
        swLng: origin.longitude - DefaultBoundsHalfSpanDeg,
        neLat: origin.latitude + DefaultBoundsHalfSpanDeg,
        neLng: origin.longitude + DefaultBoundsHalfSpanDeg
    )
}

/// `rememberUpdatedState` 자리. 이펙트가 잡아 둔 콜백이 낡지 않게 최신 참조를 들고 있다
/// — 이펙트 키에 넣으면 람다가 새로 생길 때마다 이펙트가 다시 돈다.
@MainActor
private final class LatestValue<Value> {
    var value: Value?
}

/// 합승 탐색 지도 — 내 위치를 중심으로 한 네이버 실지도.
///
/// 지도는 화면의 **바닥 레이어**다. 위에 얹히는 배너·시트는 자기 영역에서만 터치를 소비하므로
/// 남는 영역의 팬·줌은 그대로 지도로 전달된다 (홈 14 와 동일한 처리).
///
/// 합승 마커는 서버가 좌표를 준 방만 찍는다 — 좌표가 없거나 범위를 벗어난 값은
/// `latLngOrNull` 이 걸러 렌더를 건너뛴다. 마커가 없어도 리스트의 「합류」로 같은 곳에 갈 수 있다.
///
/// - Parameters:
///   - myLocation: 기기 실위치. nil 이면 기본 카메라(`MoyeotaDefaultCamera`)에서 시작하고 내 위치 표시는 없다
///   - onVisibleBoundsChange: 카메라가 멈출 때 보이는 영역. 이 범위로 방 목록을 다시 읽는다
///   - contentPadding: 시트가 지도를 덮는 영역. 카메라 중심이 시트 뒤로 밀리지 않게 한다
private struct ExploreMap: View {
    private let rides: [Ride]
    /// 캡션에 출발 시각을 먼저 적는가(예약 모드) — `reservationMarkerCaption`
    private let reservationCaptions: Bool
    /// 「오늘 오후 6:30」을 셈하는 기준 시각. 예약 모드에서만 쓰인다
    private let now: Date
    private let myLocation: MyLocationFix?
    private let cameraState: ExploreCameraState
    private let onMarkerClick: (Ride) -> Void
    private let onVisibleBoundsChange: (MapBounds) -> Void
    private let contentPadding: EdgeInsets

    @State private var map: NMFMapView?
    // `NaverMapView` 에 넘기는 카메라는 **이 지도 인스턴스를 만들 때 한 번** 정하고 그 뒤로는
    // 사용자 조작이 주인이다. idle 로 읽은 카메라를 그대로 center 로 돌려주면 안 된다 —
    // SDK 가 돌려주는 좌표가 우리가 넣은 값과 부동소수점 끝자리만큼 달라
    // 「적용 → idle → 적용」이 끝없이 돌고, 매 idle 이 조회를 재시작시켜 목록이 영영 갱신되지 않는다.
    // 사용자가 움직인 카메라는 `cameraState` 에만 적어 두고, 지도가 새로 만들어질 때 그 값에서 시작한다.
    @State private var mapCamera: MapCamera

    @Environment(\.mapCameraMemory) private var cameraMemory

    init(
        rides: [Ride],
        reservationCaptions: Bool = false,
        now: Date = Date(timeIntervalSince1970: 0),
        myLocation: MyLocationFix?,
        cameraState: ExploreCameraState,
        onMarkerClick: @escaping (Ride) -> Void,
        onVisibleBoundsChange: @escaping (MapBounds) -> Void,
        contentPadding: EdgeInsets
    ) {
        self.rides = rides
        self.reservationCaptions = reservationCaptions
        self.now = now
        self.myLocation = myLocation
        self.cameraState = cameraState
        self.onMarkerClick = onMarkerClick
        self.onVisibleBoundsChange = onVisibleBoundsChange
        self.contentPadding = contentPadding
        _mapCamera = State(
            initialValue: cameraState.camera
                ?? MapCamera(center: myLocation?.position ?? MoyeotaDefaultCamera, zoom: ExploreZoom)
        )
    }

    var body: some View {
        ZStack {
            NaverMapView(
                center: mapCamera.center,
                zoom: mapCamera.zoom,
                contentPadding: contentPadding,
                onMapReady: { map = $0 }
            )

            MapIdleReporter(
                map: map,
                cameraState: cameraState,
                onVisibleBoundsChange: onVisibleBoundsChange
            )

            if let myLocation {
                // 실위치가 있으면 SDK 내장 위치 오버레이(파란 점 + 오차 원 + 방향)를 쓴다 — 14 홈과 같은 컴포넌트
                MyLocationOverlay(
                    map: map,
                    position: myLocation.position,
                    accuracyMeters: myLocation.accuracyMeters,
                    bearingDegrees: myLocation.bearingDegrees
                )
            }

            // id 로 묶어야 범위 조회로 목록이 바뀔 때 마커 상태가 옆 항목으로 밀리지 않는다
            ForEach(rides, id: \.id) { ride in
                ExploreMarker(
                    map: map,
                    position: latLngOrNull(latitude: ride.originLat, longitude: ride.originLng),
                    tint: MoyeotaColor.Primary500,
                    // 캡션도 카드 배지와 **같은 함수**다(`headcountLabel`) — 리터럴로 쓰던 동안 인원을
                    // 모르는 방의 마커가 「0명」이라고 적혀 있었고, 같은 방의 카드는 「최대 3명」이었다.
                    // 둘 다 모르면 빈 문자열이 오고, 그때는 캡션을 아예 달지 않는다(`ExploreMarker`).
                    //
                    // 예약 모드는 **시각 · 인원**이다(`reservationMarkerCaption`) — 그 함수도 둘 다
                    // 모를 때 빈 문자열을 돌려주므로 위 계약이 그대로 유지된다.
                    caption: reservationCaptions
                        ? reservationMarkerCaption(
                            departureAt: ride.departureAt,
                            joined: ride.members.count,
                            capacity: ride.capacity,
                            now: now
                        )
                        : headcountLabel(joined: ride.members.count, capacity: ride.capacity),
                    onClick: { onMarkerClick(ride) } // 마커 탭 → 20 합류 확인
                )
            }
        }
        // 카메라를 **처음 잡힌 실위치로 한 번만** 옮긴다.
        // 주기 갱신(1초)마다 center 를 바꾸면 그때마다 카메라가 되돌아가 사용자가 지도를 팬·줌할 수
        // 없다 (`RouteMapView` 의 driverPosition 과 같은 이유). 파란 점은 계속 최신 좌표를 따라간다.
        // 플래그는 `cameraState` 와 `cameraMemory` — 지도가 다시 만들어져도 이미 옮겼다는 사실이 남아야 한다.
        .task(id: myLocation?.position) {
            guard let fix = myLocation?.position else { return }
            if !cameraState.centeredOnMyLocation && cameraMemory?.centeredOnMyLocation != true {
                cameraState.centeredOnMyLocation = true
                cameraMemory?.centeredOnMyLocation = true
                let moved = MapCamera(center: fix, zoom: ExploreZoom)
                cameraState.camera = moved
                mapCamera = moved // 이 값의 변경만이 실제로 카메라를 움직인다
            }
        }
    }
}

/// 카메라가 멈출 때마다 「지금 보이는 영역」과 카메라 위치를 위로 올려보내는 부분.
///
/// 카메라가 **멈췄을 때**만(`mapViewCameraIdle`) 보고한다 — 드래그 중 매 프레임 보고하면
/// 손가락을 떼기도 전에 조회가 수십 번 나간다.
///
/// 범위는 `NMFMapView.contentBounds` 로 읽는다. 뷰 크기 기준이 아니라
/// **contentInset 을 뺀 실제로 보이는 영역**이라, 시트에 가린 방이 목록에 섞이지 않는다.
///
/// 지도가 준비된 직후에도 한 번 보고한다. idle 은 「카메라가 움직였다 멈춤」에만 오므로,
/// 사용자가 지도를 건드리지 않으면 첫 이벤트가 영영 오지 않을 수 있다.
private struct MapIdleReporter: View {
    let map: NMFMapView?
    let cameraState: ExploreCameraState
    let onVisibleBoundsChange: (MapBounds) -> Void

    @State private var currentCallback = LatestValue<(MapBounds) -> Void>()

    var body: some View {
        let _ = currentCallback.value = onVisibleBoundsChange
        DisposableEffect(key: map.map(ObjectIdentifier.init)) {
            guard let map else { return nil }
            let report: @MainActor () -> Void = {
                let position = map.cameraPosition
                cameraState.camera = MapCamera(center: LatLng(position.target), zoom: position.zoom)
                if let bounds = map.contentBounds.toMapBoundsOrNull() {
                    currentCallback.value?(bounds)
                }
            }
            report()
            let listener = MapCameraIdleListener(onIdle: report)
            map.addCameraDelegate(delegate: listener)
            return { map.removeCameraDelegate(delegate: listener) }
        }
    }
}

@MainActor
private final class MapCameraIdleListener: NSObject, @preconcurrency NMFMapViewCameraDelegate {
    private let onIdle: @MainActor () -> Void

    init(onIdle: @escaping @MainActor () -> Void) {
        self.onIdle = onIdle
    }

    func mapViewCameraIdle(_ mapView: NMFMapView) {
        onIdle()
    }
}

private extension NMGLatLngBounds {
    /// 조회에 쓸 수 있는 범위인지 확인하고 변환한다.
    ///
    /// 지도가 아직 레이아웃되지 않은 순간에는 두 모서리가 같은 점이거나 범위 밖 좌표가 나온다.
    /// 서버는 뷰포트를 **엄격 비교**로 검사해 `swLat >= neLat || swLng >= neLng` 면 400 `INVALID_MAP_BOUNDS` 를
    /// 돌려주므로, 그대로 조회하면 그 400 이 **목록 조회 실패**로 보인다(지도에는 아무 문제가 없는데). 같은
    /// 비교로 먼저 거르고 다음 idle 을 기다린다.
    func toMapBoundsOrNull() -> MapBounds? {
        if !southWest.isValid || !northEast.isValid { return nil }
        if southWest.lat >= northEast.lat || southWest.lng >= northEast.lng { return nil }
        return MapBounds(
            swLat: southWest.lat,
            swLng: southWest.lng,
            neLat: northEast.lat,
            neLng: northEast.lng
        )
    }
}

/// 지도 마커 하나. 오버레이는 `mapView` 프로퍼티로 붙고 떨어지므로 값이 바뀌면 떼었다 다시 붙인다.
///
/// - Parameter caption: 마커 아래 글자. **빈 문자열이면 캡션을 달지 않는다** — `captionText` 의 SDK 기본값이
///   ""(캡션 없음)이므로 아예 세우지 않는 것과 같고, 빈 글자를 넣어 마커 아래에 빈 자리가 생기거나
///   SDK 버전에 따라 빈 라벨이 그려지는 일을 피한다. 호출부는 「인원·정원을 둘 다 모른다」를 이 빈
///   문자열로 넘긴다(`headcountLabel`) — 「0명」처럼 없는 사실을 지도에 박지 않기 위해서다.
private struct ExploreMarker: View {
    let map: NMFMapView?
    let position: LatLng?
    let tint: Color
    let caption: String
    var onClick: (() -> Void)?

    // 콜백은 최신 참조 유지 — 이펙트 키에 넣으면 람다가 새로 생길 때마다 마커가 재생성된다
    @State private var currentOnClick = LatestValue<() -> Void>()

    private struct Key: Equatable {
        let map: ObjectIdentifier?
        let position: LatLng?
        let tint: Color
        let caption: String
    }

    var body: some View {
        let _ = currentOnClick.value = onClick
        DisposableEffect(key: Key(map: map.map(ObjectIdentifier.init), position: position, tint: tint, caption: caption)) {
            guard let map, let position else { return nil }
            let marker = NMFMarker()
            marker.position = position.nmgLatLng
            marker.iconImage = NMF_MARKER_IMAGE_BLACK
            marker.iconTintColor = tint.toUIColor()
            if !caption.isEmpty { marker.captionText = caption }
            let holder = currentOnClick
            marker.touchHandler = { _ in
                // SDK 는 메인 스레드에서 터치를 알린다.
                MainActor.assumeIsolated {
                    let handler = holder.value
                    handler?()
                    return handler != nil // 처리한 클릭만 소비 (내 위치 마커는 지도로 흘려보낸다)
                }
            }
            marker.mapView = map
            return { marker.mapView = nil }
        }
    }
}
