import CoreLocation
import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 15 에서 지금 검색 입력을 받고 있는 필드 — 출발지·도착지가 같은 검색 UI 를 공유한다
public enum DestinationField: Sendable {
    case origin, destination
}

extension Array where Element == FavoritePlace {
    /// 검색 결과 한 건이 **이미 담긴 곳인지** — 담겼으면 그 `FavoritePlace.id`, 아니면 nil.
    /// ★ 가 채워질지, 누를 때 담기인지 빼기인지가 전부 이 값으로 갈린다.
    ///
    /// ### 이름 **하나로** 맞추면 안 된다 — 엉뚱한 즐겨찾기가 지워진다
    /// 서버가 같은 `placeName` 재등록을 409 `FAVORITE_PLACE_DUPLICATED` 로 막으므로(실측 2026-11-01,
    /// 로컬 `:8080`) **저장된 쪽**의 이름은 유저당 유일하다. 하지만 **검색 결과 쪽**은 그렇지 않다 —
    /// 같은 이름의 다른 지점이 여러 행으로 나온다. 이름만 보면 그 행들에 전부 채운 ★ 가 그려지고,
    /// 그중 아무거나 누르면 **담아 둔 적 없는 지점을 눌렀는데 진짜 즐겨찾기가 확인도 없이 지워진다.**
    /// ★ 가 「담기 전용」일 때는 이름 대조로 충분했지만, 빼기가 붙은 지금은 파괴적 동작이다.
    ///
    /// ### 그래서 도로명까지 함께 본다
    /// 좌표로 맞추지 않는 이유는 그대로다 — 검색 응답의 소수점은 카카오 데이터가 갱신되면 흔들려
    /// 담아 둔 곳인데도 빈 ★ 로 보인다. 도로명은 같은 출처에서 저장된 값이라 안정적이고 지점을 가른다.
    ///
    /// 저장된 도로명이 비어 있으면(지번만 있는 건물·지하철역 — 서버가 카카오의 `road_address_name` 을
    /// 그대로 흘린다) 이름만으로 되돌아간다. 그 경우는 가를 근거 자체가 없고, 빼기를 막아 두면
    /// 도로명 없는 즐겨찾기를 **영영 못 지우게** 된다.
    ///
    /// 빗나가면 어떻게 되나: 빈 ★ 로 보이고, 누르면 담기가 된다. 서버는 `placeName` 만 대조하므로 같은
    /// 이름의 다른 지점도 409 `FAVORITE_PLACE_DUPLICATED` 로 거절하고, 사용자는 「이미 담아 둔 곳이에요」를
    /// 본 채 ★ 는 빈 채로 남는다. 그 지점에는 틀린 말이지만 **남의 즐겨찾기를 지우는 것보다 낫다.**
    ///
    /// internal 인 이유: 화면을 그리지 않고 이 규칙만 보는 테스트가 있다(`FavoriteStarToggleTest`).
    func savedFavoriteIdFor(_ place: Place) -> Int64? {
        first { saved in
            saved.name == place.name &&
                (saved.roadName.isBlank || saved.roadName == place.roadName)
        }?.id
    }
}

/// 출발지와 도착지가 사실상 같은 자리로 볼 반경 — 합승이 성립하지 않는 거리
private let SameSpotRadiusM: Float = 50

// 좌표가 없으면 판정하지 않는다(이름 비교가 남아 있다) — 근거 없는 차단이 더 나쁘다
func isSameSpot(originLatitude: Double?, originLongitude: Double?, destination: Place) -> Bool {
    guard let originLatitude, let originLongitude else { return false }
    if !originLatitude.isFinite || !originLongitude.isFinite { return false }
    // 원본 `distanceBetween` 은 NaN 을 돌려줘 아래 비교가 거짓이 된다. `CLLocation` 은 무효 좌표의 결과가
    // NaN 이라는 보장이 없어(음수면 비교가 참이 된다) 먼저 거른다.
    if !destination.latitude.isFinite || !destination.longitude.isFinite { return false }
    let meters = CLLocation(latitude: originLatitude, longitude: originLongitude)
        .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
    if meters < 0 { return false }
    return Float(meters) <= SameSpotRadiusM
}

/// 출발지 = 도착지이면 차단한다 (이름이 같거나 50m 안)
func isTooClose(selectedPlace: Place?, origin: String?, originLatitude: Double?, originLongitude: Double?) -> Bool {
    guard let selectedPlace, let origin else { return false }
    return selectedPlace.name.trim() == origin.trim() ||
        isSameSpot(originLatitude: originLatitude, originLongitude: originLongitude, destination: selectedPlace)
}

/// 도로명이 빈 장소가 있다(지번만 있는 건물 등) — 그대로 이으면 「선택: 이름 · 」로
/// 구분자만 남는다. 없으면 이름만 보여 준다.
func selectedPlaceLabel(_ place: Place) -> String {
    "선택: \(place.name)" + (place.roadName.isBlank ? "" : " · \(place.roadName)")
}

/// 기본값일 때만 "현재 위치" — 사용자가 직접 고른 출발지는 "변경" 로 구분.
/// 출발지가 비었으면 "검색" — 눌러서 채우라는 신호.
/// 출발지 이름이 이미 「현재 위치」면 꼬리표를 달지 않는다(nil, 디자인 QA S15-2) —
/// 「현재 위치 … 현재 위치」로 같은 말이 한 줄에 두 번 나왔다.
func originBadgeLabel(origin: String?, originIsDefault: Bool) -> String? {
    guard let origin else { return "검색" }
    if originIsDefault {
        let tag = "현재 위치"
        return origin.trim() != tag ? tag : nil
    }
    return "변경"
}

/// 15 · 목적지 · 매칭 조건 [S10]
///
/// 이동(디스크립션):
/// - 뒤로 → 14 (onBack)
/// - 출발지 행 탭 → 출발지 검색 모드 (onFieldFocus(.origin)) — 결과에서 고르면 출발지 교체
/// - 도착지 행 탭/입력 → 도착지 검색 모드 (onFieldFocus(.destination))
/// - 두 필드 모두 서버 장소 검색(GET /places) 결과를 공유한다 (onQueryChange → searchResults)
/// - 자주 가는 곳 카드 탭 → 활성 필드에 장소 선택 (좌표까지 확정)
/// - 최근 검색 목록은 두지 않는다 — 서버에 검색 기록 API 가 없다(develop 기준). 검색어가 비면 결과 영역도 비운다
/// - 검색 결과 행의 ★ → 자주 가는 곳 담기/빼기 토글 (onAddFavorite / onRemoveFavorite)
///   — 이미 담은 곳은 채운 ★ 가 되고, 한 번 더 누르면 빠진다. 담은 직후 취소할 길이 여기다
/// - 「경로 확인하기」 → 16 도착지 확인 모달 (onConfirmRoute)
///
/// 유효값 검증:
/// - 좌표가 있는 도착지를 고르기 전에는 CTA 비활성 (방 생성에 좌표가 필수)
/// - 출발지 = 도착지이면 「너무 가까워요」 로 차단 (이름이 같거나 50m 안)
/// - 출발지를 고르지 않으면 기기 실위치("현재 위치")를 쓴다. 실위치도 없으면(`origin` nil) 출발지 칸을
///   비워 두고 CTA 를 막은 채 「현재 위치를 확인하거나 출발지를 검색해 주세요」를 안내한다 — 고정 좌표로 채우지 않는다
public struct DestinationScreen: View {
    /// 출발지 이름. nil = 실위치도 없고 고른 출발지도 없음 → 비워 두고 CTA 비활성
    private let origin: String?
    private let originIsDefault: Bool // true = 사용자가 고르지 않은 기본 출발지 → "현재 위치" 라벨
    // 출발지 좌표 — 「너무 가까워요」 판정용. 실위치 출발지는 이름이 "현재 위치" 라 이름 비교만으로는
    // 같은 자리를 못 걸러낸다 (nil 이면 이름 비교만 한다)
    private let originLatitude: Double?
    private let originLongitude: Double?
    private let originQuery: String
    private let activeField: DestinationField
    private let onFieldFocus: (DestinationField) -> Void
    private let query: String
    private let onQueryChange: (String) -> Void
    private let searchResults: [Place]
    private let searchLoading: Bool
    private let searchErrorMessage: String?
    private let favoritePlaces: [FavoritePlace]
    private let favoritesLoading: Bool
    private let favoritesErrorMessage: String?
    private let selectedPlace: Place?
    private let favoriteActionMessage: String?
    /// 담기·빼기 요청이 날아간 동안 true — ★ 를 잠근다(아래 `onRemoveFavorite` 주석 참고)
    private let favoriteActionLoading: Bool
    private let onPlaceSelect: (Place) -> Void
    private let onAddFavorite: (Place) -> Void
    /// 담은 곳을 다시 빼기(DELETE .../favorite-places/{placeId}). 인자는 `FavoritePlace.id` 다.
    ///
    /// **같은 id 를 두 번 지우면 404 다**(멱등이 아니다) — 연타가 「지우지 못했어요」로 보이므로
    /// 요청 중에는 `favoriteActionLoading` 으로 ★ 를 잠근다.
    /// 되돌릴 수 있는 동작이라 확인 다이얼로그를 두지 않는다(같은 ★ 를 한 번 더 누르면 다시 담긴다).
    private let onRemoveFavorite: (Int64) -> Void
    private let onBack: () -> Void
    private let onConfirmRoute: (Place) -> Void

    public init(
        origin: String? = nil,
        originIsDefault: Bool = true,
        originLatitude: Double? = nil,
        originLongitude: Double? = nil,
        originQuery: String = "",
        activeField: DestinationField = .destination,
        onFieldFocus: @escaping (DestinationField) -> Void = { _ in },
        query: String = "",
        onQueryChange: @escaping (String) -> Void = { _ in },
        searchResults: [Place] = [],
        searchLoading: Bool = false,
        searchErrorMessage: String? = nil,
        favoritePlaces: [FavoritePlace] = [],
        favoritesLoading: Bool = false,
        favoritesErrorMessage: String? = nil,
        selectedPlace: Place? = nil,
        favoriteActionMessage: String? = nil,
        favoriteActionLoading: Bool = false,
        onPlaceSelect: @escaping (Place) -> Void = { _ in },
        onAddFavorite: @escaping (Place) -> Void = { _ in },
        onRemoveFavorite: @escaping (Int64) -> Void = { _ in },
        onBack: @escaping () -> Void = {},
        onConfirmRoute: @escaping (Place) -> Void = { _ in }
    ) {
        self.origin = origin
        self.originIsDefault = originIsDefault
        self.originLatitude = originLatitude
        self.originLongitude = originLongitude
        self.originQuery = originQuery
        self.activeField = activeField
        self.onFieldFocus = onFieldFocus
        self.query = query
        self.onQueryChange = onQueryChange
        self.searchResults = searchResults
        self.searchLoading = searchLoading
        self.searchErrorMessage = searchErrorMessage
        self.favoritePlaces = favoritePlaces
        self.favoritesLoading = favoritesLoading
        self.favoritesErrorMessage = favoritesErrorMessage
        self.selectedPlace = selectedPlace
        self.favoriteActionMessage = favoriteActionMessage
        self.favoriteActionLoading = favoriteActionLoading
        self.onPlaceSelect = onPlaceSelect
        self.onAddFavorite = onAddFavorite
        self.onRemoveFavorite = onRemoveFavorite
        self.onBack = onBack
        self.onConfirmRoute = onConfirmRoute
    }

    private var originActive: Bool { activeField == .origin }

    public var body: some View {
        let originMissing = origin == nil
        let tooClose = isTooClose(
            selectedPlace: selectedPlace,
            origin: origin,
            originLatitude: originLatitude,
            originLongitude: originLongitude
        )
        let ctaEnabled = selectedPlace != nil && !originMissing && !tooClose

        VStack(spacing: 0) {
            StatusBarSpacer()

            // 헤더 — 다른 하위 화면과 같은 가운데 제목 앱바(G7)
            MoyeotaTopBar(title: "어디로 갈까요?", onBack: onBack)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 4)
                    fields
                    selectedPlaceConfirmation
                    Spacer().frame(height: MoyeotaSpacing.SectionGap)
                    favoritesSection
                    Spacer().frame(height: MoyeotaSpacing.SectionGap)
                    searchSection
                    Spacer().frame(height: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 하단 — 안내 · 오류 · CTA
            VStack(alignment: .leading, spacing: 0) {
                // 「같은 방향 사람만 보여드려요」는 지웠다 — 17 탐색 목록은 **지도 영역**으로만 거른다
                // (`getPartiesWithin`, 서버도 "출발지가 영역 안인 ACTIVE 방"). 도착지로 거르는 길이 없다.
                // 이 CTA 가 실제로 하는 일은 16 에서 경로·예상 요금을 보여주는 것이다(2026-10-13).
                Text("도착지를 넣으면 경로와 예상 요금을 알려드려요")
                    .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                    .frame(maxWidth: .infinity, alignment: .center)
                if originMissing {
                    Spacer().frame(height: 8)
                    NoticeBanner(kind: .info, text: "현재 위치를 확인하거나 출발지를 검색해 주세요")
                }
                if tooClose {
                    Spacer().frame(height: 8)
                    NoticeBanner(kind: .error, text: "너무 가까워요")
                }
                Spacer().frame(height: 12)
                PrimaryCtaButton(
                    text: "경로 확인하기",
                    onClick: { if let selectedPlace { onConfirmRoute(selectedPlace) } },
                    enabled: ctaEnabled
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            NavigationBarSpacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 흰 화면(디자인 QA G2) — 예전 회색 바탕(#F5F7FA)은 비활성 CTA(#F4F6FA)와 대비가 1.01:1 이라
        // 「경로 확인하기」 버튼 모양이 사라지고 회색 글자만 떠 있었다.
        .background(MoyeotaColor.SurfaceCanvas)
    }

    // ─── 출발지 · 도착지 ────────────────────────────────────────────────────

    @ViewBuilder
    private var fields: some View {
        // 출발지 행 — 비활성이면 선택된 이름만, 활성이면 도착지와 같은 검색 입력이 된다
        PlaceFieldRow(
            focused: originActive,
            onClick: { onFieldFocus(.origin) }
        ) {
            if originActive {
                SearchInput(
                    value: originQuery,
                    onValueChange: onQueryChange,
                    placeholder: "출발지를 검색해 주세요"
                )
                if searchLoading { FieldSpinner() }
            } else {
                Text(origin ?? "출발지를 검색해 주세요")
                    .moyeotaText(
                        (origin == nil ? MoyeotaType.BodyMd : MoyeotaType.BodyStrong).hangulTrimmed,
                        color: origin == nil ? MoyeotaColor.TextPlaceholder : MoyeotaColor.InkPrimary
                    )
                    .clippedSingleLine()
                    .allowsHitTesting(false)
                // 기본값일 때만 "현재 위치" — 사용자가 직접 고른 출발지는 "변경" 로 구분.
                // 출발지가 비었으면 "검색" — 눌러서 채우라는 신호.
                // 출발지 이름이 이미 「현재 위치」면 꼬리표를 달지 않는다(디자인 QA S15-2) —
                // 「현재 위치 … 현재 위치」로 같은 말이 한 줄에 두 번 나왔다.
                if let originTag = originBadgeLabel(origin: origin, originIsDefault: originIsDefault) {
                    Text(originTag)
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .fixedSize(horizontal: true, vertical: false)
                        .allowsHitTesting(false)
                }
            }
        }

        Spacer().frame(height: 8)

        // 도착지 입력 행
        PlaceFieldRow(
            focused: !originActive,
            onClick: { onFieldFocus(.destination) }
        ) {
            SearchInput(
                value: query,
                onValueChange: onQueryChange,
                placeholder: "도착지를 입력해 주세요",
                // 출발지 검색 중에는 도착지 칸을 편집 불가로 두고, 탭하면 포커스만 옮긴다
                enabled: !originActive
            )
            if searchLoading && !originActive { FieldSpinner() }
        }
    }

    // 선택한 장소 확인 — 좌표까지 확정된 상태임을 보여준다
    @ViewBuilder
    private var selectedPlaceConfirmation: some View {
        if let selectedPlace {
            Spacer().frame(height: 8)
            Text(selectedPlaceLabel(selectedPlace))
                .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.Primary600)
        }
    }

    // ─── 자주 가는 곳 ──────────────────────────────────────────────────────

    // 자주 가는 곳 — 서버(GET /users/me/favorite-places)
    @ViewBuilder
    private var favoritesSection: some View {
        SectionLabel(text: "자주 가는 곳") {
            if favoritesLoading {
                CircularProgressIndicator(size: 12, color: MoyeotaColor.Primary500, strokeWidth: 1.5)
            }
        }
        if let favoritesErrorMessage {
            Text(favoritesErrorMessage)
                .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.Danger600)
        } else if favoritePlaces.isEmpty && !favoritesLoading {
            Text("아직 등록한 장소가 없어요. 검색 결과의 ★ 를 눌러 등록해 보세요")
                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
        } else {
            HStack(alignment: .top, spacing: 8) {
                // 한 줄에 3개까지만 — 서버는 최대 10개를 내려준다.
                // **여기에는 삭제 손잡이를 두지 않는다**: take(3) 이라 전체가 안 보이는데
                // 「전체 삭제」를 이 자리에 두면 보이지 않는 7곳까지 지워진다. 목록 전체가
                // 보이는 14 홈 편집 모드가 삭제의 유일한 자리다.
                ForEach(Array(favoritePlaces.prefix(3)), id: \.id) { place in
                    FavoriteCard(place: place) {
                        onPlaceSelect(
                            Place(
                                name: place.name,
                                roadName: place.roadName,
                                latitude: place.latitude,
                                longitude: place.longitude
                            )
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        if let favoriteActionMessage {
            Spacer().frame(height: 8)
            Text(favoriteActionMessage)
                .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextBody)
        }
    }

    // ─── 검색 결과 ──────────────────────────────────────────────────────────

    // 검색 결과(서버) — 활성 필드 기준. 검색어가 비어 있으면 아무것도 그리지 않는다
    // (최근 검색 API 가 서버에 없어 더미 목록을 두지 않는다).
    @ViewBuilder
    private var searchSection: some View {
        let activeQuery = originActive ? originQuery : query
        if !activeQuery.isBlank {
            SectionLabel(text: originActive ? "출발지 검색 결과" : "검색 결과")
            if let searchErrorMessage {
                Text(searchErrorMessage)
                    .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.Danger600)
            } else if searchResults.isEmpty && !searchLoading {
                Text("검색 결과가 없어요")
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
            } else {
                resultsList
            }
        }
    }

    // 그림자 카드 없이 흰 화면 위에 줄로 바로(G4) — 줄 사이만 Hairline
    private var resultsList: some View {
        // 활성 필드의 마커색 — 출발지는 Primary, 도착지는 MarkerDestination
        let activeMarkerColor = originActive ? MoyeotaColor.Primary500 : MoyeotaColor.MarkerDestination
        // 같은 이름·주소의 행이 올 수 있어 자리로 구분한다(원본 `forEachIndexed`).
        return VStack(spacing: 0) {
            ForEach(Array(searchResults.enumerated()), id: \.offset) { index, place in
                let savedId = favoritePlaces.savedFavoriteIdFor(place)
                SearchResultRow(
                    place: place,
                    markerColor: activeMarkerColor,
                    savedId: savedId,
                    favoriteActionLoading: favoriteActionLoading,
                    onSelect: { onPlaceSelect(place) },
                    onStar: {
                        if let savedId { onRemoveFavorite(savedId) } else { onAddFavorite(place) }
                    }
                )
                if index != searchResults.count - 1 {
                    // 글자 시작(점 8 + 간격 12)부터 긋는다
                    HorizontalDivider(color: MoyeotaColor.Hairline)
                        .padding(.leading, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// ─── 부품 ───────────────────────────────────────────────────────────────────

private extension View {
    /// `maxLines = 1` + `weight(1f)` 자리. 원본은 한 줄을 넘으면 말줄임 없이 잘린다 — `lineLimit(1)` 은 「…」을 덧붙여
    /// 원본에 없는 글자가 생긴다. `minWidth: 0` 이 없으면 프레임이 글자 폭까지 늘어나 옆 칸을 밀어낸다.
    func clippedSingleLine() -> some View {
        fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }
}

/// 출발지·도착지 필드의 공통 껍데기.
/// focused 면 파랑 테두리 — 두 필드 중 어디에 검색어가 들어가는지 이걸로만 구분한다.
///
/// 그림자는 두지 않는다(디자인 QA G4) — 흰 화면 위의 입력칸이라 테두리(`MoyeotaColor.BorderStrong`,
/// 디자인 문서 text-input)로 모양이 선다. 예전엔 포커스 없는 칸에만 그림자를 줘서 두 칸이 서로 다른
/// 높이에 떠 보였다.
///
/// 탭은 내용 **뒤에 깔린** 버튼이 받는다. 버튼 라벨로 넣으면 입력 칸을 누를 때도 행이 눌린 것처럼 보이는데, 원본은
/// 켜진 입력 칸이 탭을 먼저 가져가 행까지 오지 않는다. 글자·꺼진 입력 칸은 탭을 통과시켜 이 버튼으로 내려보낸다.
private struct PlaceFieldRow<Content: View>: View {
    let focused: Bool
    let onClick: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        let shape = MoyeotaShape.Card
        HStack(alignment: .center, spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background {
            Button(action: onClick) {
                Color.clear
            }
            .buttonStyle(PressOverlayStyle(shape: shape))
        }
        .background(MoyeotaColor.SurfaceCanvas, in: shape)
        .overlay {
            shape
                .strokeBorder(focused ? MoyeotaColor.Primary500 : MoyeotaColor.BorderStrong, lineWidth: focused ? 1.5 : 1)
                .allowsHitTesting(false)
        }
    }
}

private struct SearchInput: View {
    let value: String
    let onValueChange: (String) -> Void
    let placeholder: String
    var enabled = true

    @State private var focus = FocusRequester()

    var body: some View {
        ZStack(alignment: .leading) {
            BasicTextField(
                value: value,
                onValueChange: onValueChange,
                // 입력한 글자는 본문 굵기(디자인 문서 text-input = body-md) — 예전엔 15pt Bold 였다
                textStyle: MoyeotaType.BodyMd.copy(color: MoyeotaColor.InkPrimary),
                singleLine: true,
                enabled: enabled,
                focusRequester: focus
            )
            .frame(maxWidth: .infinity)
            if value.isEmpty {
                Text(placeholder)
                    .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextPlaceholder)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        // 꺼진 칸의 탭은 행으로 내려가 포커스만 옮긴다.
        .allowsHitTesting(enabled)
        // 원본은 꺼진 칸이 포커스를 잃어 키보드가 닫힌다. `UITextField` 는 꺼져도 first responder 로 남을 수 있어,
        // 그대로 두면 출발지 검색으로 넘어간 뒤에도 키보드가 떠 있어 사용자가 검색어를 넣을 칸을 잘못 안다.
        .onChange(of: enabled) { _, isEnabled in
            if !isEnabled { focus.freeFocus() }
        }
    }
}

private struct FieldSpinner: View {
    var body: some View {
        Spacer().frame(width: 8, height: 8)
        CircularProgressIndicator(size: 16, color: MoyeotaColor.Primary500, strokeWidth: 2)
            .allowsHitTesting(false)
    }
}

/// 원본의 `weight(1f)` 타일 한 장 — ★ 위, 이름·도로명 아래(가운데는 남는 높이).
///
/// 그림자 대신 `MoyeotaColor.Border` 선(디자인 QA G4·S15-2) — 흰 화면 위의 타일이라 선 하나로 모양이 선다.
/// 주소는 10pt → 12pt(CaptionMd): 10pt 는 이 앱의 글자 크기 표 밖이고 거의 읽히지 않았다.
private struct FavoriteCard: View {
    let place: FavoritePlace
    let onClick: () -> Void

    var body: some View {
        let shape = MoyeotaShape.Card
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 0) {
                StarIcon(size: MoyeotaIconSize.Sm, tint: MoyeotaColor.TextPlaceholder)
                Spacer(minLength: 0)
                Text(place.name)
                    .moyeotaText(MoyeotaType.BodySm.copy(fontWeight: .semibold).hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(place.roadName)
                    .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 80)
            .background(MoyeotaColor.SurfaceCanvas, in: shape)
            .overlay(shape.strokeBorder(MoyeotaColor.Border, lineWidth: 1))
        }
        .buttonStyle(PressOverlayStyle(shape: shape))
    }
}

/// 검색 결과 한 행. 버튼 안에 버튼을 넣지 않으려고 행 탭은 내용 뒤에 깔린 버튼이 받고, ★ 만 위에서 탭을 가져간다.
private struct SearchResultRow: View {
    let place: Place
    let markerColor: Color
    let savedId: Int64?
    let favoriteActionLoading: Bool
    let onSelect: () -> Void
    let onStar: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Circle()
                .fill(markerColor)
                .frame(width: 8, height: 8)
                .allowsHitTesting(false)
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(place.name)
                    .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                // 서버가 도로명을 비워 주는 장소가 있다(지번만 있는 건물·역). 빈 줄을 세우면
                // 이름이 두 줄 칸의 위쪽에 붙고 점·★ 는 가운데에 남아 어긋나 보였다(S15-1).
                if !place.roadName.isBlank {
                    Text(place.roadName)
                        .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            // ★ 토글 — 안 담은 곳이면 등록, 이미 담은 곳이면 빼기
            //
            // **48 을 채운다.** 이 ★ 는 「담기 전용」이던 동안에는 17 아이콘에
            // 10 패딩(=37)이면 됐지만, 빼기가 붙으면서 **되돌릴 수 없는 삭제**가
            // 됐다. 게다가 이 자리는 행 전체를 먹는 탭 영역 안에 있어
            // 위아래·오른쪽 띠가 행의 것이다 — 작게 두면 행을 노린 탭이 ★ 를 빗맞히고
            // 반대로 ★ 를 노린 탭이 행으로 새어 15 가 열린다.
            Button(action: onStar) {
                StarIcon(
                    // 담긴 곳은 채운 ★ — 지금 상태가 무엇인지가 토글의 전부다
                    filled: savedId != nil,
                    tint: favoriteActionLoading ? MoyeotaColor.TextPlaceholder : MoyeotaColor.Primary500
                )
                .frame(width: 48, height: 48)
            }
            .buttonStyle(PressOverlayStyle(shape: Circle()))
            .disabled(favoriteActionLoading)
            // 원본의 꺼진 `clickable` 은 탭을 받지 않아 바깥 행으로 넘어간다. 잠긴 동안의 ★ 탭은 행 선택이 된다.
            .allowsHitTesting(!favoriteActionLoading)
            // 아이콘만 있는 버튼이라 VoiceOver 에 무엇을 하는지 알린다
            .accessibilityLabel(savedId != nil ? "즐겨찾기에서 빼기" : "즐겨찾기에 담기")
        }
        // 오른쪽 여백이 없는 건 ★ 가 48 을 스스로 차지하기 때문이다.
        .padding(.vertical, 4)
        // 도로명이 빈 행도 두 줄짜리 행과 같은 높이를 갖는다(S15-1)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background {
            Button(action: onSelect) {
                Color.clear
            }
            .buttonStyle(PressOverlayStyle(shape: Rectangle()))
        }
    }
}
