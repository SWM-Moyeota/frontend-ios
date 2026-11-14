import SwiftUI
import Testing
@testable import MoyeotaDesignSystem

// 원본에 없는 테스트. 원본 휠(`SnapWheelPicker`)과 날짜 띠(`WeekDateStrip`)는 `LazyColumn`·`BoxWithConstraints` 안에서
// 셈해 단위 테스트가 없다. iOS 는 끌기를 `UIScrollView` 에 맡기고 줄을 직접 그리므로, 그 사이를 잇는 셈을 여기서 본다.

@Suite struct WheelPickerMathTest {
    @Test("가운데 칸은 가장 가까운 항목이고 두 항목 사이 한가운데면 앞 항목이다")
    func centeredIndex() {
        #expect(wheelCenteredIndex(position: 18, lastIndex: 23) == 18)
        #expect(wheelCenteredIndex(position: 18.4, lastIndex: 23) == 18)
        #expect(wheelCenteredIndex(position: 18.6, lastIndex: 23) == 19)
        #expect(wheelCenteredIndex(position: 18.5, lastIndex: 23) == 18, "원본 minByOrNull 은 먼저 나온 쪽")
        // 튕기는 동안 목록 밖으로 나가도 끝 항목이다
        #expect(wheelCenteredIndex(position: -0.8, lastIndex: 23) == 0)
        #expect(wheelCenteredIndex(position: 24.7, lastIndex: 23) == 23)
    }

    @Test("손을 떼면 미끄러져 멈출 자리에 가장 가까운 칸에 붙는다")
    func snapsToNearestRow() {
        #expect(wheelSnappedIndex(offset: 0, itemHeight: 40, lastIndex: 5) == 0)
        #expect(wheelSnappedIndex(offset: 59, itemHeight: 40, lastIndex: 5) == 1)
        #expect(wheelSnappedIndex(offset: 61, itemHeight: 40, lastIndex: 5) == 2)
        #expect(wheelSnappedIndex(offset: 900, itemHeight: 40, lastIndex: 5) == 5, "멀리 던져도 끝 항목에서 멈춘다")
        #expect(wheelSnappedIndex(offset: -120, itemHeight: 40, lastIndex: 5) == 0)
    }

    /// 휠 높이 200(5줄), 항목 i 의 가운데는 내용 좌표 `i × 40 + 100` 이다.
    @Test("탭한 줄의 항목을 고르고 위아래 여백 줄에는 항목이 없다")
    func tappedRow() {
        #expect(wheelTappedIndex(locationY: 100, viewportHeight: 200, itemHeight: 40, itemCount: 6) == 0)
        #expect(wheelTappedIndex(locationY: 119, viewportHeight: 200, itemHeight: 40, itemCount: 6) == 0)
        #expect(wheelTappedIndex(locationY: 121, viewportHeight: 200, itemHeight: 40, itemCount: 6) == 1)
        #expect(wheelTappedIndex(locationY: 300, viewportHeight: 200, itemHeight: 40, itemCount: 6) == 5)
        #expect(wheelTappedIndex(locationY: 79, viewportHeight: 200, itemHeight: 40, itemCount: 6) == nil, "첫 항목 위 여백")
        #expect(wheelTappedIndex(locationY: 321, viewportHeight: 200, itemHeight: 40, itemCount: 6) == nil, "끝 항목 아래 여백")
    }

    @Test("보이는 줄과 위아래 한 줄씩만 그린다")
    func visibleIndices() {
        #expect(wheelVisibleIndices(position: 0, visibleItemCount: 5, lastIndex: 23) == [0, 1, 2, 3])
        #expect(wheelVisibleIndices(position: 10, visibleItemCount: 5, lastIndex: 23) == Array(7...13))
        #expect(wheelVisibleIndices(position: 10.5, visibleItemCount: 5, lastIndex: 23) == Array(7...14))
        #expect(wheelVisibleIndices(position: 23, visibleItemCount: 5, lastIndex: 23) == Array(20...23))
        #expect(wheelVisibleIndices(position: 0, visibleItemCount: 5, lastIndex: -1).isEmpty)
    }

    @Test("부모가 넘긴 선택은 목록 안으로 접는다")
    func safeIndex() {
        #expect(wheelSafeIndex(-1, itemCount: 6) == 0)
        #expect(wheelSafeIndex(9, itemCount: 6) == 5)
        #expect(wheelSafeIndex(3, itemCount: 6) == 3)
        #expect(wheelSafeIndex(3, itemCount: 0) == 0)
    }
}

@Suite struct WeekDateStripMathTest {
    /// 원본 기준: 360 폭 폰의 16 카드 안(좌우 36)이 288 = 8 × 36 으로 딱 같은 폭 모드다.
    @Test("칸 폭이 36 이상이면 한 줄에 나눠 담고 그보다 좁으면 스크롤한다")
    func equalWidthThreshold() {
        let card = EdgeInsets(top: 0, leading: 36, bottom: 0, trailing: 36)
        #expect(weekDateStripFitsEqually(width: 360, contentPadding: card, cellCount: 8))
        #expect(!weekDateStripFitsEqually(width: 359, contentPadding: card, cellCount: 8))
        // iPhone SE 확대 보기(320 폭)의 17 시트(좌우 24)는 34 라 스크롤한다
        #expect(!weekDateStripFitsEqually(width: 320, contentPadding: EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24), cellCount: 8))
        #expect(weekDateStripFitsEqually(width: 375, contentPadding: card, cellCount: 8))
    }
}
