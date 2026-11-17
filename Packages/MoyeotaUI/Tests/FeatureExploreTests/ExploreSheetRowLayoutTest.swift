import SwiftUI
import Testing
import UIKit
@testable import FeatureExplore

/// 원본에는 없는 테스트. 17 접힘 요약과 18·19 목록 헤더의 높이가 원본 레이아웃과 같은지 잰다.
///
/// 디자인 다듬기(2026-11) 뒤로 두 줄의 높이는 글자 상자가 아니라 **정해 둔 값**이 정한다:
/// - 접힘 요약은 접힘 시트 96 에서 손잡이 줄 28 을 뺀 **68** 을 채우고 그 가운데에 선다(원본 `heightIn(min = 68.dp)`) —
///   부제가 없어진 실시간 목록에서도 높이가 줄지 않아야 지도 `contentPadding` 이 흔들리지 않는다
/// - 목록 헤더는 「지도 접기」 글자 버튼의 **48 터치 높이**다(원본 `TextLinkButton` 의 `minimumInteractiveComponentSize`)
@MainActor
@Suite struct ExploreSheetRowLayoutTest {
    private func height(_ view: some View) -> CGFloat {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: 402, height: 2000))
            .height
    }

    @Test("접힘 요약 행은 손잡이 줄을 뺀 접힘 높이 68 을 채운다")
    func peekRowHeight() {
        let filled = height(PeekSummaryRow(mode: .realtime, count: 3, dateLabel: nil, myPartyHidden: false, statusText: nil, onRaise: {}))
        let empty = height(PeekSummaryRow(mode: .realtime, count: 0, dateLabel: nil, myPartyHidden: false, statusText: nil, onRaise: {}))
        let reservation = height(PeekSummaryRow(mode: .soon, count: 2, dateLabel: nil, myPartyHidden: false, statusText: nil, onRaise: {}))
        #expect(abs(filled - 68) < 0.4)
        #expect(abs(empty - 68) < 0.4)
        #expect(abs(reservation - 68) < 0.4)
    }

    @Test("목록 헤더 행은 지도 접기 버튼의 터치 높이 48 이다")
    func listHeaderHeight() {
        let half = height(ListHeaderRow(mode: .realtime, count: 3, dateLabel: nil, destinationSent: false, mapShown: true, onToggleMap: {}))
        let full = height(ListHeaderRow(mode: .realtime, count: 3, dateLabel: nil, destinationSent: false, mapShown: false, onToggleMap: {}))
        #expect(abs(half - 48) < 0.4)
        #expect(abs(full - 48) < 0.4)
    }
}
