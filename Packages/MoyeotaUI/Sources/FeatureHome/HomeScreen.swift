import CoreLocation
import MoyeotaDesignSystem
import MoyeotaDomain
@preconcurrency import NMapsMap
import PresentationCore
import SwiftUI

/// 첫 실위치로 옮길 때의 줌 — 동네 단위가 보이는 수준(26 운행 중과 같은 값)
private let HomeMyLocationZoom = 15.0

/// 펼친 시트 위로 남기는 지도 높이 — 예전 홈의 「화면 약 30%」 지도 노출과 비슷한 값
private let HomeMapRevealHeight: CGFloat = 200

/// 접힘 높이 추정치 = 손잡이 줄(28) + `HomeSearchHeader`(위 4 + 제목 30 + 간격 12 + 검색 바 52 + 아래 16 = 114)
/// = 142. 드래그 앵커·카메라 계산에만 쓰인다(실제 높이는 콘텐츠가 정한다 — MapSheetDefaults 설명 참고).
///
/// 예전 226 은 인사말·27pt 제목·설명 한 줄·64 검색 카드를 담던 값이다. 그 셋을 걷어내(디자인 QA H1)
/// 접힘에서도 지도가 84 더 보인다. 손잡이만 남기는 세 번째 앵커는 위·아래를 **실측**해 거리를 정하므로
/// 이 값과 무관하게 그대로 동작한다.
private let HomeCollapsedSheetHeight: CGFloat = 142

/// 14 · 홈 — 어디로 갈까요 [S09]
///
/// 이동(디스크립션):
/// - 상단 「{단계} · {목적지} 보기」 배너 → 진행 중인 방의 단계 화면 21/25/26 (onActiveRideClick)
///   — 진행 중인 방이 없으면(`activeRide` nil) 배너 자체가 없다
/// - 「목적지 검색」 바 탭 → 15 (onSearchClick)
/// - 「즐겨찾기」 행 탭 → 15, 도로명주소로 검색어 자동 입력 (onFavoritePlaceClick)
/// - 하단탭 합승/채팅/마이 → 17/24/35 (onTabSelect)
///
/// 상태:
/// - 즐겨찾기는 서버 목록(`favoritePlaces`)을 sequence 순으로 전부 세로 목록에 그린다.
///   행 = 이름 · 도로명주소 · 내 위치 기준 직선 거리(`myLocation` 이 nil 이면 거리 생략)
/// - 비어 있으면 목록 대신 「즐겨찾기를 등록하면…」 안내 문구 (등록은 15 의 ★)
///
/// 레이아웃: 와이어프레임 B1「풀스크린 지도」 — 네이버 지도가 배경 레이어이고
/// 홈 UI 는 그 위 **드래그 시트**(`MapSheetScaffold`)다. 앵커가 **셋**이다:
/// - 펼침(기본) — 「어디로 갈까요?」·검색 바 + 즐겨찾기 목록
/// - 접힘 — 즐겨찾기가 접혀 지도가 검색 바 위까지 드러난다
/// - **손잡이만**(2026-11, 오너 UX 피드백) — 한 번 더 끌어내리면 시트가 하단탭 뒤로 내려가고 손잡이 줄만
///   남아 **지도가 전부** 보인다. 예전에는 제목·검색 바가 늘 떠 있어 지도를 다 볼 길이 없었다.
///   손잡이를 끌어올리거나 **누르면** 접힘으로 돌아온다(누르기는 끌 수 없는 사용자를 위한 길이다).
///   검색 진입(「목적지 검색」 바 → 15)은 그대로다 — 손잡이만 남은 동안에는 바가 보이지 않을 뿐이다.
public struct HomeScreen: View {
    /// 지금 진행 중인 내 방. nil 이면 지도 위 배너를 그리지 않는다
    private let activeRide: Ride?
    /// 기기 실위치. nil(권한 없음·아직 fix 없음)이면 파란 점을 그리지 않고 카메라도 옮기지 않는다
    private let myLocation: UserCoordinates?
    /// 서버 즐겨찾기(GET /users/me/favorite-places). 호출부가 sequence 순으로 정렬해 넘긴다
    private let favoritePlaces: [FavoritePlace]
    /// 즐겨찾기 편집 모드. 행 탭이 15 이동 대신 선택 토글이 되고 삭제 손잡이가 나온다
    private let editingFavorites: Bool
    /// 편집 모드에서 고른 `FavoritePlace.id` 들
    private let selectedFavoriteIds: Set<Int64>
    /// 삭제 요청이 날아간 동안 true — 손잡이를 모두 잠근다(아래 `onDeleteSelected` 주석 참고)
    private let deletingFavorites: Bool
    /// 삭제 실패 문구. 성공하면 nil 로 돌아온다
    private let favoriteErrorMessage: String?
    /// 목록 조회가 **한 번이라도 성공**했는가. 「전체 삭제」를 그릴지의 근거다 —
    /// 못 받은 상태에서 그리면 서버에 멀쩡히 있는 즐겨찾기를 지우는 버튼이 된다(`onDeleteAll` 참고).
    private let favoritesLoaded: Bool
    /// 목록 조회가 실패했다. **빈 목록과 다르게** 그려야 한다 — 섞으면 위 버튼의 근거가 거짓이 된다
    private let favoritesLoadFailed: Bool
    private let onRetryFavorites: () -> Void
    private let onSearchClick: () -> Void
    private let onActiveRideClick: () -> Void
    private let onFavoritePlaceClick: (FavoritePlace) -> Void
    private let onEditFavoritesToggle: () -> Void
    private let onFavoriteSelectToggle: (FavoritePlace) -> Void
    /// 「선택한 N곳 삭제」. 1곳이어도 다건 삭제(batch-delete)로 보낸다 — 서버가 전부-아니면-전무라
    /// 3개 중 1개만 지워진 어중간한 상태가 생기지 않는다(단건 삭제를 N번 돌리면 중간 404 에서
    /// 목록과 서버가 어긋난다).
    private let onDeleteSelected: () -> Void
    /// 「전체 삭제」. **목록이 비어 보일 때도 쓸 수 있어야 한다** — placeId·좌표가 없는 레거시 행은
    /// 매퍼가 버려 화면에 안 나오는데 서버에서는 10칸 중 하나를 계속 차지하고, 고를 수 없으니
    /// 이 경로가 유일한 탈출구다.
    ///
    /// **단 `favoritesLoaded` 가 true 일 때만 그린다.** 「비어 보인다」가 조회 실패 때문일 수도 있고,
    /// 그때는 서버에 멀쩡한 즐겨찾기가 있다 — 탈출구가 아니라 파괴 버튼이 된다.
    private let onDeleteAll: () -> Void
    private let onTabSelect: (MoyeotaTab) -> Void

    // 확인 다이얼로그 대상. nil 이면 다이얼로그 없음 — 탈퇴·로그아웃과 같은 방식으로
    // 화면 안에 들고 있는다(ViewModel 까지 올릴 상태가 아니다).
    // 원본은 시트 상세 슬롯 안에 두지만, 여기서는 시트 안에 두면 오버레이가 시트 모양으로 잘려 화면 단위로 올렸다.
    @State private var confirming: FavoriteDeleteKind?

    public init(
        activeRide: Ride? = nil,
        myLocation: UserCoordinates? = nil,
        favoritePlaces: [FavoritePlace] = [],
        editingFavorites: Bool = false,
        selectedFavoriteIds: Set<Int64> = [],
        deletingFavorites: Bool = false,
        favoriteErrorMessage: String? = nil,
        favoritesLoaded: Bool = false,
        favoritesLoadFailed: Bool = false,
        onRetryFavorites: @escaping () -> Void = {},
        onSearchClick: @escaping () -> Void = {},
        onActiveRideClick: @escaping () -> Void = {},
        onFavoritePlaceClick: @escaping (FavoritePlace) -> Void = { _ in },
        onEditFavoritesToggle: @escaping () -> Void = {},
        onFavoriteSelectToggle: @escaping (FavoritePlace) -> Void = { _ in },
        onDeleteSelected: @escaping () -> Void = {},
        onDeleteAll: @escaping () -> Void = {},
        onTabSelect: @escaping (MoyeotaTab) -> Void = { _ in }
    ) {
        self.activeRide = activeRide
        self.myLocation = myLocation
        self.favoritePlaces = favoritePlaces
        self.editingFavorites = editingFavorites
        self.selectedFavoriteIds = selectedFavoriteIds
        self.deletingFavorites = deletingFavorites
        self.favoriteErrorMessage = favoriteErrorMessage
        self.favoritesLoaded = favoritesLoaded
        self.favoritesLoadFailed = favoritesLoadFailed
        self.onRetryFavorites = onRetryFavorites
        self.onSearchClick = onSearchClick
        self.onActiveRideClick = onActiveRideClick
        self.onFavoritePlaceClick = onFavoritePlaceClick
        self.onEditFavoritesToggle = onEditFavoritesToggle
        self.onFavoriteSelectToggle = onFavoriteSelectToggle
        self.onDeleteSelected = onDeleteSelected
        self.onDeleteAll = onDeleteAll
        self.onTabSelect = onTabSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 배경 = 풀스크린 지도, 그 위에 **드래그로 접었다 펴는** 시트(16·21 과 같은 MapSheetScaffold).
            // 펼침(기본)에서는 예전 홈처럼 지도 약 200 + 검색·즐겨찾기,
            // 핸들을 내리면 상세(즐겨찾기)가 접혀 **지도가 검색 바 위까지 전부** 보인다.
            MapSheetScaffold(
                mapRevealHeight: HomeMapRevealHeight,
                collapsedSheetHeight: HomeCollapsedSheetHeight,
                // 손잡이 줄만 남기는 세 번째 앵커 — 지도를 다 보고 싶은 사람의 길(위 설명). 지도의
                // contentPadding 은 시트가 손잡이 줄 높이를 알려 주므로(settledSheetHeight) 따로 손대지 않는다.
                hideable: true,
                hiddenHandleLabel: "검색 패널 펼치기",
                background: { sheet in
                    HomeMapBackground(
                        sheet: sheet,
                        activeRide: activeRide,
                        myLocation: myLocation,
                        onActiveRideClick: onActiveRideClick
                    )
                },
                // 항상 보이는 줄 = 「어디로 갈까요?」 + 검색 바 (핸들과 함께 드래그 타깃)
                sheetTop: {
                    HomeSearchHeader(onSearchClick: onSearchClick)
                },
                // 접히면 사라지는 상세 = 즐겨찾기 목록
                sheetDetail: {
                    FavoritesDetail(
                        myLocation: myLocation,
                        favoritePlaces: favoritePlaces,
                        editingFavorites: editingFavorites,
                        selectedFavoriteIds: selectedFavoriteIds,
                        deletingFavorites: deletingFavorites,
                        favoriteErrorMessage: favoriteErrorMessage,
                        favoritesLoaded: favoritesLoaded,
                        favoritesLoadFailed: favoritesLoadFailed,
                        onRetryFavorites: onRetryFavorites,
                        onFavoritePlaceClick: onFavoritePlaceClick,
                        onEditFavoritesToggle: onEditFavoritesToggle,
                        onFavoriteSelectToggle: onFavoriteSelectToggle,
                        onConfirm: { confirming = $0 }
                    )
                },
                sheetFooter: { EmptyView() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            MoyeotaBottomBar(selected: .home, onSelect: onTabSelect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
        // 되돌릴 수 없는 삭제라 확인을 받는다(탈퇴·로그아웃과 같은 모양 — 앱 공용 확인 다이얼로그, G11).
        // 다이얼로그는 목록을 되풀이하지 않는다 — 「되돌릴 수 없다」 한 가지만 말한다.
        .overlay {
            if let pending = confirming {
                MoyeotaConfirmDialog(
                    title: pending.title,
                    confirmText: "삭제",
                    onConfirm: {
                        confirming = nil
                        switch pending {
                        case .selected: onDeleteSelected()
                        case .all: onDeleteAll()
                        }
                    },
                    onDismiss: { confirming = nil },
                    body: pending.message,
                    destructive: true
                )
            }
        }
        // 편집 모드가 바뀌면 열려 있던 다이얼로그를 닫는다 — 안 닫으면 「완료」를 누른 뒤에
        // 확인 창만 떠 있어 무엇에 대한 확인인지 알 수 없다.
        .onChange(of: editingFavorites) { _, _ in confirming = nil }
        // 원본 `remember` 는 화면이 컴포지션에서 빠지면 사라진다. `@State` 는 스택에 있는 동안 남으므로 직접 비운다.
        .onDisappear { confirming = nil }
    }

    /// 테스트가 확인창이 열린 상태를 만드는 입구. 창에 올린 화면이라도 코드로는 SwiftUI 버튼을 누를 수 없다.
    func seeded(confirming: FavoriteDeleteKind?) -> Self {
        var copy = self
        copy._confirming = State(initialValue: confirming)
        return copy
    }
}

// ─── 배경 지도 ──────────────────────────────────────────────────────────────

/// 진행 배너 위 여백(iOS 전용 계산). 원본은 상태바 아래 8 이고, 렌더에서 배너 위 끝은 화면 위에서 56.8dp 다.
///
/// iPhone 상태바 인셋은 안드로이드(48.8dp)보다 13pt 높아 8 을 그대로 두면 배너가 그만큼 내려온다. 그러면 배너와 시트
/// 사이가 13pt 좁아져 그 가운데 놓이는 줌 컨트롤의 − 가 시트 밑으로 들어간다(원본은 − 가 보인다). 그래서 배너가 원본
/// 자리보다 내려가는 만큼을 이 여백에서 먼저 뺀다. 안전 영역 안으로는 들어가지 않고, 인셋이 낮은 기기는 원본과 같은 8 이다.
func homeBannerTopPadding(statusBarHeight: CGFloat) -> CGFloat {
    min(max(56.8 - statusBarHeight, 0), 8)
}

/// 펼친 시트 위에서 진행 배너가 있을 때 줌 컨트롤을 옮기는 값(iOS 전용, 위로 음수).
///
/// 배너를 올려도 iPhone 은 안전 영역 때문에 약 5pt 아래에 남아, − 가 시트에 거의 붙는다. 2pt 올리면 +·− 가 원본 자리와
/// 1~2pt 안으로 맞는다. 원본 주석이 막으려는 배너와의 겹침은 만들지 않는다 — 상태바가 더 높은 기기에서는 배너에 닿는 데서 멈춘다.
func homeZoomControlOffsetY(bannerHeight: CGFloat, visibleBottom: CGFloat) -> CGFloat {
    let controlTop = (bannerHeight + visibleBottom - NaverMapZoomControlHeight) / 2
    // 배너 묶음의 아래 여백이 8 이다.
    let bannerBottom = bannerHeight - 8
    return -min(2, max(controlTop - bannerBottom, 0))
}

private struct HomeMapBackground: View {
    let sheet: MapSheetState
    let activeRide: Ride?
    let myLocation: UserCoordinates?
    let onActiveRideClick: () -> Void

    // 진행 배너(상태바 포함) 높이 — 지도 top contentPadding 으로 넘겨 줌 컨트롤(+/−)이
    // 배너 아래로 내려가게 한다(작은 폰에서 배너와 줌 버튼이 겹치던 문제)
    @State private var bannerHeight: CGFloat = 0
    @State private var statusBarHeight: CGFloat = 0
    @State private var map: NMFMapView?
    @State private var centeredOnMe = false

    @Environment(\.mapCameraMemory) private var cameraMemory

    private struct CenterKey: Equatable {
        let map: ObjectIdentifier?
        let position: LatLng?
    }

    var body: some View {
        let myPosition = latLngOrNull(latitude: myLocation?.latitude, longitude: myLocation?.longitude)
        ZStack(alignment: .top) {
            NaverMapView(
                // 앵커 기준 시트 높이를 빼 카메라 중심이 시트 뒤가 아니라 실제 보이는 영역에 잡히게 한다
                contentPadding: EdgeInsets(top: bannerHeight, leading: 0, bottom: sheet.settledSheetHeight, trailing: 0),
                zoomControlOffsetY: sheet.expanded && activeRide != nil
                    ? homeZoomControlOffsetY(
                        bannerHeight: bannerHeight,
                        visibleBottom: sheet.containerHeight - sheet.settledSheetHeight
                    )
                    : 0,
                onMapReady: { map = $0 }
            )
            // 첫 실위치로 **한 번만** 옮긴다. 주기 갱신(1초)마다 카메라를 되돌리면 지도를 팬·줌할 수
            // 없다(합승 탭·26 과 같은 규칙). 그 뒤로는 파란 점만 최신 좌표를 따라간다.
            // NaverMapView 의 center 는 기본값(상수)이라 이 이동을 되돌리지 않는다.
            .task(id: CenterKey(map: map.map(ObjectIdentifier.init), position: myPosition)) {
                centerOnFirstFix(myPosition)
            }

            if let myPosition {
                MyLocationOverlay(
                    map: map,
                    position: myPosition,
                    accuracyMeters: myLocation?.accuracyMeters,
                    bearingDegrees: myLocation?.bearingDegrees
                )
            }
            // 진행 중인 방이 있으면 지도 위에 복귀 배너 하나만 얹는다 — 배너 밖은 여전히 지도의 것이다
            if let activeRide {
                VStack(spacing: 0) {
                    StatusBarSpacer()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { statusBarHeight = $0 }
                    ActiveRideBanner(ride: activeRide, onClick: onActiveRideClick)
                        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                        .padding(.top, homeBannerTopPadding(statusBarHeight: statusBarHeight))
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bannerHeight = $0 }
            }
        }
    }

    private func centerOnFirstFix(_ myPosition: LatLng?) {
        guard let map, let fix = myPosition else { return }
        // 원본 `rememberSaveable` 은 탭을 옮겨 다녀도 값이 남는다. 탭 호스트가 뷰를 다시 만드는 경로에서는
        // 카메라를 복원해 주는 `mapCameraMemory` 에 함께 맡긴다 — 안 맡기면 돌아올 때마다 내 위치로 튄다.
        if centeredOnMe || cameraMemory?.centeredOnMyLocation == true { return }
        map.moveCamera(NMFCameraUpdate(scrollTo: fix.nmgLatLng, zoomTo: HomeMyLocationZoom))
        centeredOnMe = true
        cameraMemory?.centeredOnMyLocation = true
    }
}


// ─── 시트 상세: 즐겨찾기 ────────────────────────────────────────────────────

struct FavoritesDetail: View {
    let myLocation: UserCoordinates?
    let favoritePlaces: [FavoritePlace]
    let editingFavorites: Bool
    let selectedFavoriteIds: Set<Int64>
    let deletingFavorites: Bool
    let favoriteErrorMessage: String?
    let favoritesLoaded: Bool
    let favoritesLoadFailed: Bool
    let onRetryFavorites: () -> Void
    let onFavoritePlaceClick: (FavoritePlace) -> Void
    let onEditFavoritesToggle: () -> Void
    let onFavoriteSelectToggle: (FavoritePlace) -> Void
    let onConfirm: (FavoriteDeleteKind) -> Void

    var body: some View {
        // 시트 안에 회색 띠를 깔지 않는다(디자인 QA G2·H3) — 예전엔 흰 시트 → 파란 띠 → 회색 띠 →
        // 그림자 카드로 한 시트에 바탕색이 넷이었다. 목록은 흰 시트 위에 바로 놓이고 줄 사이만 선으로 나눈다.
        VStack(alignment: .leading, spacing: 0) {
            // 검색 바 아래 16(sheetTop) + 8 = 묶음 간격 24
            Spacer().frame(height: 8)

            // 즐겨찾기 — 서버 등록 순서(sequence) 그대로 전부
            SectionLabel(text: "즐겨찾기") {
                // **목록이 비어 보여도 숨기지 않는다** — 그때가 「전체 삭제」가 유일한
                // 탈출구인 경우(매퍼가 버린 레거시 행)라서 숨기면 탈출구가 함께 사라진다.
                TextLinkButton(
                    text: editingFavorites ? "완료" : "편집",
                    onClick: onEditFavoritesToggle,
                    enabled: !deletingFavorites
                )
            }
            // 「편집」 글자 끝을 16 화면 여백에 맞춘다(TextLinkButton 안쪽 여백 8 만큼 덜 띄운다)
            .padding(.leading, MoyeotaSpacing.ScreenGutter)
            .padding(.trailing, 8)

            if favoritePlaces.isEmpty {
                emptyFavorites
            } else {
                favoritesList
            }

            // ★ 「전체 삭제」는 **조회에 한 번이라도 성공했을 때만** 그린다.
            // 레거시 행 탈출구라는 명분은 「목록을 받아 왔고 그 결과가 비었다」일 때만 선다 —
            // 못 받은 상태에서 그리면 멀쩡한 즐겨찾기를 지우는 버튼이 된다.
            if editingFavorites && favoritesLoaded {
                Spacer().frame(height: 12)
                // 파괴적 동작 두 줄이 맞닿아 있으면 「선택한 N곳」을 노린 손가락이
                // 「전체 삭제」를 집는다. 둘 사이를 벌려 둔다.
                VStack(alignment: .leading, spacing: 8) {
                    // TextButton 자리를 쓰지 않는다 — 이 앱에서 TextButton 은 다이얼로그 안에만 있다.
                    if !favoritePlaces.isEmpty {
                        DangerTextRow(
                            text: "선택한 \(selectedFavoriteIds.count)곳 삭제",
                            // 0곳이면 서버가 400 INVALID_PLACE_IDS 를 준다 — 누를 수 없게 둔다
                            enabled: !selectedFavoriteIds.isEmpty && !deletingFavorites,
                            onClick: { onConfirm(.selected) }
                        )
                    }
                    DangerTextRow(
                        text: "전체 삭제",
                        enabled: !deletingFavorites,
                        onClick: { onConfirm(.all) }
                    )
                }
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            }

            if let favoriteErrorMessage {
                Spacer().frame(height: 8)
                Text(favoriteErrorMessage)
                    .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.Danger600)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            }

            Spacer().frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ★ 「못 받았다」와 「없다」를 절대 같게 그리지 않는다.
    // 둘을 섞으면 조회가 끊긴 사용자에게 화면이 「등록한 곳이 없어요」라고 말하고,
    // 편집 중이면 거기에 더해 「전체 삭제로 비울 수 있어요」까지 권한다 —
    // 서버에는 멀쩡한 즐겨찾기가 있고, 통신이 돌아오는 순간 그게 전부 지워진다.
    @ViewBuilder
    private var emptyFavorites: some View {
        if favoritesLoadFailed {
            VStack(alignment: .leading, spacing: 0) {
                Text("즐겨찾기를 불러오지 못했어요")
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                Spacer().frame(height: 4)
                // 글자 시작을 위 문장과 맞춘다(안쪽 여백 8 만큼 바깥으로)
                TextLinkButton(text: "다시 시도", onClick: onRetryFavorites)
                    .offset(x: -8)
            }
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
        } else {
            // 편집 중에 비어 보이는 목록은 「등록해 보세요」로 끝낼 수 없다 —
            // 서버에 남은 안 보이는 행을 치우려고 편집에 들어온 경우가 그 자리다.
            // 단 **조회에 성공한 뒤**에만 그렇게 말할 수 있다(위 분기가 그걸 보장한다).
            Text(
                editingFavorites
                    ? "목록에 안 보이는 장소가 서버에 남아 있을 수 있어요. 「전체 삭제」로 비울 수 있어요"
                    // 등록은 15 목적지 화면에서 ★ 로 한다
                    : "즐겨찾기를 등록하면 여기서 바로 부를 수 있어요"
            )
            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
        }
    }

    // 그림자 카드 없이 시트 위에 바로 — 줄 사이만 화면 여백 안쪽의 Hairline 으로 나눈다
    private var favoritesList: some View {
        VStack(spacing: 0) {
            ForEach(Array(favoritePlaces.enumerated()), id: \.element.id) { index, place in
                FavoritePlaceRow(
                    place: place,
                    distanceLabel: distanceLabel(from: myLocation, place: place),
                    editing: editingFavorites,
                    selected: selectedFavoriteIds.contains(place.id),
                    enabled: !deletingFavorites,
                    // 편집 중에는 15 로 튀어나가지 않는다 — 화면이 바뀌면 고른 것이 날아간다
                    onClick: {
                        if editingFavorites {
                            onFavoriteSelectToggle(place)
                        } else {
                            onFavoritePlaceClick(place)
                        }
                    }
                )
                if index != favoritePlaces.count - 1 {
                    HorizontalDivider(color: MoyeotaColor.Hairline)
                        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 시트의 늘 보이는 줄 — 「어디로 갈까요?」 한 줄 + 검색 바.
///
/// 예전엔 인사말(「○○님, 반가워요」) · 27pt 제목 · 설명 한 줄이 옅은 파란 띠 위에 세 줄로 쌓여 있었다
/// (디자인 QA H1 — 오너 결정으로 「최소안」). 제목 하나만 남기고 `MoyeotaType.HeadingXl`(22/600)로 내린다:
/// 지도 앱의 첫 화면에서 말이 많으면 지도가 그만큼 가려진다.
///
/// 검색 바는 카드가 아니라 **입력칸**이다(H2): 높이 52, 옅은 면(`MoyeotaColor.SurfaceSoft`), 그림자·테두리
/// 없음. 오른쪽 끝의 파란 화살표 타일을 지웠다 — 바 전체가 이미 누르는 자리라 타일은 장식이었고, 이 화면의
/// 두 번째 솔리드 파랑이었다.
struct HomeSearchHeader: View {
    let onSearchClick: () -> Void

    var body: some View {
        let shape = MoyeotaShape.Card
        VStack(alignment: .leading, spacing: 0) {
            // 손잡이 줄(아래 12)과 합쳐 제목 위 여백이 된다
            Spacer().frame(height: 4)
            Text("어디로 갈까요?")
                .moyeotaText(MoyeotaType.HeadingXl.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer().frame(height: 12)
            // 목적지 검색 바 → 15
            Button(action: onSearchClick) {
                HStack(alignment: .center, spacing: 0) {
                    SearchIcon(size: MoyeotaIconSize.Md, tint: MoyeotaColor.TextMute)
                    Spacer().frame(width: 8)
                    Text("목적지 검색")
                        .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextPlaceholder)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(MoyeotaColor.SurfaceSoft, in: shape)
            }
            .buttonStyle(PressOverlayStyle(shape: shape))
            Spacer().frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
    }
}

/// 어떤 삭제의 확인을 받는 중인지. 다이얼로그 제목·본문·동작이 전부 이 값으로 갈린다
enum FavoriteDeleteKind {
    case selected, all

    var title: String {
        switch self {
        case .selected: "선택한 곳을 지울까요?"
        case .all: "즐겨찾기를 모두 지울까요?"
        }
    }

    var message: String {
        switch self {
        case .selected: "지우면 되돌릴 수 없어요"
        case .all: "등록해 둔 곳이 모두 사라지고 되돌릴 수 없어요"
        }
    }
}

/// 즐겨찾기 한 행 — 이름/도로명주소 · (실위치가 있을 때만) 직선 거리.
///
/// 행 앞의 회색 점은 지웠다(디자인 QA H3) — 아무것도 구분하지 않는 장식이었다. 이름은 `MoyeotaType.BodyStrong`,
/// 주소·거리는 `MoyeotaType.BodySm` `MoyeotaColor.TextMute`(예전 `#8A93A0` 은 흰 바탕 대비 3.1:1 이었다).
///
/// 편집 모드(`editing`)에서는 거리 라벨 자리를 체크박스가 대신한다. **제스처는 쓰지 않는다** —
/// 이 목록은 세로로 드래그되는 시트 안이고 그 배경은 패닝되는 지도라, 행 위 가로 스와이프가
/// 시트 드래그와 지도 제스처 둘 다와 싸운다. 편집 모드는 탭만 쓴다.
struct FavoritePlaceRow: View {
    let place: FavoritePlace
    let distanceLabel: String?
    let editing: Bool
    let selected: Bool
    let enabled: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(place.name)
                        .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    // 도로명이 빈 장소가 있다(지번만 있는 건물·역) — 빈 줄을 세우지 않는다(15 검색 결과와 같은 규칙)
                    if !place.roadName.isBlank {
                        Text(place.roadName)
                            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                if editing {
                    Spacer().frame(width: 12)
                    SelectBox(selected: selected)
                } else if let distanceLabel {
                    Spacer().frame(width: 12)
                    Text(distanceLabel)
                        .moyeotaText(MoyeotaType.BodySm.tabularNums(), color: MoyeotaColor.TextMute)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(PressOverlayStyle(shape: Rectangle()))
        // 삭제가 날아간 동안 탭을 막는다 — 단건·다건 삭제가 멱등이 아니라서(두 번째가 404)
        // 연타가 「지우지 못했어요」로 보인다
        .disabled(!enabled)
    }
}

/// 파괴적 동작 한 줄. 눌러서 **다이얼로그를 여는 것**까지가 역할이고 삭제는 확인 뒤에 일어난다.
///
/// `TextButton` 자리를 쓰지 않는 이유: 이 앱은 화면 본문에 TextButton 을 두지 않는다 —
/// 쓰인 자리가 전부 AlertDialog 안이다(프로필 수정 화면 주석의 방침).
private struct DangerTextRow: View {
    let text: String
    let enabled: Bool
    let onClick: () -> Void

    var body: some View {
        let shape = MoyeotaShape.Small
        Button(action: onClick) {
            Text(text)
                .moyeotaText(
                    MoyeotaType.ButtonMd.hangulTrimmed,
                    color: enabled ? MoyeotaColor.Danger500 : MoyeotaColor.TextPlaceholder
                )
                .padding(.vertical, 12)
                // 되돌릴 수 없는 동작이라 터치 타깃을 48 로 채운다. 세로 패딩만으로는 38 이었고,
                // 바로 아래 「전체 삭제」와 맞닿아 손가락이 옆 줄을 집었다.
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        }
        .buttonStyle(PressOverlayStyle(shape: shape))
        .disabled(!enabled)
    }
}

/// 편집 모드의 선택 상자 — 체크는 공용 아이콘 세트(`CheckIcon`)를 쓴다
private struct SelectBox: View {
    let selected: Bool

    var body: some View {
        let shape = MoyeotaShape.Small
        ZStack {
            if selected {
                CheckIcon(size: MoyeotaIconSize.Sm, tint: MoyeotaColor.TextOnDark)
            }
        }
        .frame(width: 20, height: 20)
        .background(selected ? MoyeotaColor.Primary500 : MoyeotaColor.SurfaceCanvas, in: shape)
        .overlay(shape.strokeBorder(selected ? MoyeotaColor.Primary500 : MoyeotaColor.BorderStrong, lineWidth: 1.5))
    }
}

/// 내 위치 → 즐겨찾기 직선 거리 라벨. 1km 미만은 "850m", 이상은 소수 첫째 자리 "6.2km".
/// 실위치가 없거나 좌표가 유한하지 않으면 nil — 행에서 거리 칸을 생략한다.
func distanceLabel(from: UserCoordinates?, place: FavoritePlace) -> String? {
    guard let from else { return nil }
    if !from.latitude.isFinite || !from.longitude.isFinite { return nil }
    if !place.latitude.isFinite || !place.longitude.isFinite { return nil }
    let meters = CLLocation(latitude: from.latitude, longitude: from.longitude)
        .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
    // 원본 `Location.distanceBetween` 처럼 Float 로 받아 같은 값으로 자른다.
    return distanceLabel(meters: Float(meters))
}

/// 원본 `String.format(Locale.US, "%.1fkm", …)` 는 정확히 반에 걸린 값을 올리고(HALF_UP) C `printf` 는 짝수로 보낸다
/// (1250m → 원본 「1.3km」, printf 「1.2km」). 그래서 직접 올림한다. Float 에 10 을 곱해도 Double 안에서 정확하다.
func distanceLabel(meters: Float) -> String? {
    guard meters.isFinite else { return nil }
    if meters < 1000 {
        return "\(Int(meters.rounded()))m"
    }
    let tenths = Int((Double(meters / 1000) * 10 + 0.5).rounded(.down))
    return "\(tenths / 10).\(tenths % 10)km"
}

