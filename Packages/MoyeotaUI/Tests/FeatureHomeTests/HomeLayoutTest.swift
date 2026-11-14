import MoyeotaDomain
import SwiftUI
import Testing
import UIKit
@testable import FeatureHome

/// 원본에는 없는 테스트. 원본 `HomeScreen.kt` 의 여백·토큰이 실제 높이로 옮겨졌는지 잰다.
///
/// 기대값은 원본 `HomeScreen.kt` 의 값을 더한 것이다. 시트의 접힘 높이와 목록의 밀도가 여기서 정해진다.
/// 글자 한 줄은 토큰의 한글 글자 상자(`MoyeotaType.hangulTrimmed` — 크기 × 1.44)다: 원본 토큰 글은 첫 줄 위·끝 줄
/// 아래를 대체 글꼴 상자에서 자른다(22pt 30 이 아니라 31.68, 15pt 21.6, 13pt 18.72, 12pt 17.28).
@MainActor
@Suite struct HomeLayoutTest {

    private func height(_ view: some View) -> CGFloat {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: 393, height: 2000))
            .height
    }

    private func place(roadName: String) -> FavoritePlace {
        FavoritePlace(id: 1, name: "집", roadName: roadName, latitude: 35, longitude: 129, sequence: 1)
    }

    private func row(roadName: String, distanceLabel: String? = "850m") -> FavoritePlaceRow {
        FavoritePlaceRow(
            place: place(roadName: roadName),
            distanceLabel: distanceLabel,
            editing: false,
            selected: false,
            enabled: true,
            onClick: {}
        )
    }

    private func detail(
        loadFailed: Bool = false,
        errorMessage: String? = nil
    ) -> FavoritesDetail {
        FavoritesDetail(
            myLocation: nil,
            favoritePlaces: [],
            editingFavorites: false,
            selectedFavoriteIds: [],
            deletingFavorites: false,
            favoriteErrorMessage: errorMessage,
            favoritesLoaded: !loadFailed,
            favoritesLoadFailed: loadFailed,
            onRetryFavorites: {},
            onFavoritePlaceClick: { _ in },
            onEditFavoritesToggle: {},
            onFavoriteSelectToggle: { _ in },
            onConfirm: { _ in }
        )
    }

    /// 위 4 + 제목 31.68(HeadingXl 22) + 12 + 검색 바 52 + 아래 16. 원본 주석의 114 는 제목을 줄 높이 30 으로 센 값이다.
    /// 인사말·설명·64 검색 카드를 걷어낸 디자인 QA H1(최소안)의 높이 — 예전 히어로는 215 였다.
    @Test("검색 머리줄 높이는 제목과 검색 바만의 합이다")
    func searchHeaderHeight() {
        #expect(abs(height(HomeSearchHeader(onSearchClick: {})) - 115.68) < 1)
    }

    /// 상태바 인셋별 배너 위 여백. 62 는 iPhone 17, 48.8 은 원본 렌더의 인셋이다.
    @Test("배너 위 여백은 원본 자리까지만 줄어든다")
    func bannerTopPadding() {
        #expect(homeBannerTopPadding(statusBarHeight: 62) == 0)
        #expect(homeBannerTopPadding(statusBarHeight: 20) == 8)
        #expect(homeBannerTopPadding(statusBarHeight: 48.8) == 8)
        #expect(abs(homeBannerTopPadding(statusBarHeight: 54) - 2.8) < 0.01)
    }

    /// 배너 묶음 높이 118 은 iPhone 17 렌더의 값(상태바 62 + 배너 48 + 아래 8)이다. 가시 영역 끝은 지도 노출 높이 200 이다.
    @Test("줌 컨트롤은 배너와 겹치지 않는 만큼만 올라간다")
    func zoomControlOffset() {
        #expect(homeZoomControlOffsetY(bannerHeight: 118, visibleBottom: 200) == -2)
        // 컨트롤 위 끝 (136 + 200 − 89) / 2 = 123.5, 배너 아래 끝 128: 이미 겹치면 더 올리지 않는다.
        #expect(homeZoomControlOffsetY(bannerHeight: 136, visibleBottom: 200) == 0)
        // 컨트롤 위 끝 117.5, 배너 아래 끝 116: 그 사이 1.5 만큼만 올라간다.
        #expect(homeZoomControlOffsetY(bannerHeight: 124, visibleBottom: 200) == -1.5)
    }

    /// 위아래 12 + 이름 21.6(BodyStrong 15) + 도로명 18.72(BodySm 13).
    @Test("즐겨찾기 행 높이는 이름과 도로명 두 줄의 합이다")
    func rowHeight() {
        #expect(abs(height(row(roadName: "부산 금정구 부산대학로 63번길 2")) - 64.32) < 1)
    }

    /// 도로명이 빈 즐겨찾기는 실제로 있다(`favoritePlaceQuery` 참고). 빈 줄을 세우지 않고(15 검색 결과와 같은 규칙)
    /// 행의 최소 높이 56 이 목록의 밀도를 지킨다.
    @Test("도로명이 빈 행은 최소 높이 56 이다")
    func rowHeightWithBlankRoad() {
        #expect(abs(height(row(roadName: "")) - 56) < 1)
    }

    /// 위 8 + 머리말 줄 56(「편집」 48 터치 + 아래 8) + 안내 18.72 + 아래 16.
    @Test("빈 목록 안내까지의 상세 높이는 머리말과 안내 한 줄의 합이다")
    func emptyDetailHeight() {
        #expect(abs(height(detail()) - 98.72) < 1)
    }

    /// 안내 18.72 + 4 + 「다시 시도」 48 자리.
    @Test("조회 실패 상세 높이는 안내와 다시 시도 줄의 합이다")
    func failedDetailHeight() {
        #expect(abs(height(detail(loadFailed: true)) - 150.72) < 1)
    }

    /// 실패 문구 한 줄은 위 8 + CaptionMd 한 줄 17.28 을 더한다.
    @Test("삭제 실패 문구는 한 줄을 차지한다")
    func errorMessageHeight() {
        #expect(abs(height(detail(errorMessage: "즐겨찾기를 지우지 못했어요")) - 124) < 1)
    }
}
