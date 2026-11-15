import SwiftUI
import Testing
import UIKit
@testable import MoyeotaDesignSystem

// 원본에 없는 테스트. 원본 `MapSheetScaffold` 의 세 앵커(손잡이만·접힘·펼침)는 Compose 안에서만 셈해 단위 테스트가 없다.
// iOS 는 같은 셈을 순수 함수로 꺼냈으므로(`mapSheetSettleAnchor` 등) 원본 식과 같은 답을 내는지 여기서 본다.

@Suite struct MapSheetAnchorTest {
    /// 손잡이 + 위 = 160, 아래 = 0 → 내릴 거리 160 − 28 = 132. 상세 최대 300.
    private let hiddenSpan = mapSheetHiddenSpan(hideable: true, topChromeHeight: 160, footerHeight: 0)
    private let detailMax: CGFloat = 300

    @Test("내릴 거리는 손잡이·위·아래 높이에서 손잡이 줄을 뺀 값이고 상세는 재지 않는다")
    func hiddenSpanExcludesDetail() {
        #expect(hiddenSpan == 132)
        #expect(mapSheetHiddenSpan(hideable: true, topChromeHeight: 100, footerHeight: 60) == 132)
        #expect(mapSheetHiddenSpan(hideable: false, topChromeHeight: 160, footerHeight: 60) == 0, "hideable 이 아니면 앵커가 없다")
        #expect(mapSheetHiddenSpan(hideable: true, topChromeHeight: 10, footerHeight: 0) == 0, "음수가 되지 않는다")
    }

    @Test("한 줄의 위치는 상세가 먼저 접히고 이어서 시트가 내려간다")
    func positionSplitsIntoDetailThenHide() {
        let expanded = mapSheetAnchorPosition(.expanded, hiddenSpan: hiddenSpan, detailMax: detailMax)
        let collapsed = mapSheetAnchorPosition(.collapsed, hiddenSpan: hiddenSpan, detailMax: detailMax)
        let hidden = mapSheetAnchorPosition(.hidden, hiddenSpan: hiddenSpan, detailMax: detailMax)

        #expect(mapSheetSplit(position: expanded, hiddenSpan: hiddenSpan, detailMax: detailMax) == (detail: 300, hide: 0))
        #expect(mapSheetSplit(position: collapsed + 100, hiddenSpan: hiddenSpan, detailMax: detailMax) == (detail: 100, hide: 0))
        #expect(mapSheetSplit(position: collapsed, hiddenSpan: hiddenSpan, detailMax: detailMax) == (detail: 0, hide: 0))
        #expect(mapSheetSplit(position: collapsed - 32, hiddenSpan: hiddenSpan, detailMax: detailMax) == (detail: 0, hide: 32))
        #expect(mapSheetSplit(position: hidden, hiddenSpan: hiddenSpan, detailMax: detailMax) == (detail: 0, hide: 132))
    }

    @Test("손을 놓으면 가까운 앵커로 가고 같은 거리면 낮은 쪽이다")
    func settlesToNearest() {
        func settle(_ from: CGFloat, hideable: Bool = true) -> SheetAnchor {
            mapSheetSettleAnchor(velocity: 0, from: from, hideable: hideable, hiddenSpan: hiddenSpan, detailMax: detailMax)
        }
        #expect(settle(10) == .hidden)
        #expect(settle(66) == .hidden, "손잡이만(0)과 접힘(132)의 한가운데 — 앞의 것")
        #expect(settle(100) == .collapsed)
        #expect(settle(282) == .collapsed, "접힘(132)과 펼침(432)의 한가운데 — 앞의 것")
        #expect(settle(300) == .expanded)
        #expect(settle(10, hideable: false) == .collapsed, "hideable 이 아니면 손잡이만 앵커가 없다")
    }

    @Test("던지면 그 방향의 바로 다음 앵커로 간다")
    func flingMovesOneAnchor() {
        func fling(_ velocity: CGFloat, from: CGFloat, hideable: Bool = true) -> SheetAnchor {
            mapSheetSettleAnchor(velocity: velocity, from: from, hideable: hideable, hiddenSpan: hiddenSpan, detailMax: detailMax)
        }
        // 펼침에서 아래로 던지면 접힘에서 멈춘다(한 번에 손잡이만으로 가지 않는다)
        #expect(fling(1_000, from: 420) == .collapsed)
        #expect(fling(1_000, from: 132) == .hidden)
        #expect(fling(1_000, from: 0) == .hidden, "가장 낮은 앵커 아래는 없다")
        #expect(fling(-1_000, from: 0) == .collapsed)
        #expect(fling(-1_000, from: 140) == .expanded)
        #expect(fling(-1_000, from: 432) == .expanded)
        // 기준 속도(400px/s) 이하면 던진 것이 아니다
        #expect(fling(400, from: 420) == .expanded)
        // 원본 두 앵커 동작과 같다
        #expect(fling(1_000, from: 300, hideable: false) == .collapsed)
        #expect(fling(-1_000, from: 140, hideable: false) == .expanded)
    }

    @Test("앵커 기준 시트 높이는 손잡이만 남으면 손잡이 줄 높이다")
    func settledHeightPerAnchor() {
        #expect(mapSheetSettledHeight(anchor: .hidden, containerHeight: 700, mapRevealHeight: 160, collapsedSheetHeight: 226) == 28)
        #expect(mapSheetSettledHeight(anchor: .collapsed, containerHeight: 700, mapRevealHeight: 160, collapsedSheetHeight: 226) == 226)
        #expect(mapSheetSettledHeight(anchor: .expanded, containerHeight: 700, mapRevealHeight: 160, collapsedSheetHeight: 226) == 540)
    }
}

// ─── 창에 올려 실제 배치를 읽는다 ───

@MainActor
private final class HiddenSheetProbe {
    var state: MapSheetState?
    var top: CGRect?
}

private struct HiddenSheetHarness: View {
    let probe: HiddenSheetProbe
    let saved: TabSavedState

    var body: some View {
        MapSheetScaffold(
            mapRevealHeight: 160,
            collapsedSheetHeight: 226,
            hideable: true,
            background: { sheet in
                Color.clear.onChange(of: sheet, initial: true) { _, value in probe.state = value }
            },
            sheetTop: {
                Color.red
                    .frame(height: 132)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("probe")) } action: { probe.top = $0 }
            },
            sheetDetail: { Color.blue.frame(height: 40) },
            sheetFooter: { EmptyView() }
        )
        .frame(width: 393, height: 700)
        .coordinateSpace(name: "probe")
        .environment(\.tabSavedState, saved)
    }
}

@MainActor
@Suite(.serialized) struct MapSheetHiddenLayoutTest {
    private func render(_ saved: TabSavedState) async -> HiddenSheetProbe {
        let probe = HiddenSheetProbe()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = UIHostingController(rootView: HiddenSheetHarness(probe: probe, saved: saved))
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<40 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(25))
        }
        return probe
    }

    @Test("손잡이만 남으면 시트 위가 손잡이 줄만큼만 보이고 지도는 그 위를 다 쓴다")
    func hiddenLeavesHandleOnly() async throws {
        let saved = TabSavedState()
        saved.set("mapSheet.hidden", true)
        let probe = await render(saved)
        let state = try #require(probe.state)
        let top = try #require(probe.top)

        #expect(state.hidden)
        #expect(!state.expanded)
        #expect(state.settledSheetHeight == 28)
        #expect(abs(state.sheetHeight - 28) < 1, "보이는 시트는 손잡이 줄뿐이다: \(state.sheetHeight)")
        // 손잡이 줄(28) 바로 아래에 놓이는 위 내용은 컨테이너 바닥 아래로 내려가 있다
        #expect(abs(top.minY - 700) < 1, "위 내용의 위 끝 \(top.minY)")
    }

    @Test("저장된 접힘은 손잡이만 앵커가 아니다")
    func collapsedRestore() async throws {
        let saved = TabSavedState()
        saved.set("mapSheet.expanded", false)
        let probe = await render(saved)
        let state = try #require(probe.state)
        let top = try #require(probe.top)

        #expect(!state.hidden)
        #expect(!state.expanded)
        #expect(state.settledSheetHeight == 226)
        // 접힘: 손잡이 줄 + 위(132) 만 보인다 — 위 내용은 바닥에서 132 위에 있다
        #expect(abs(top.minY - (700 - 132)) < 1, "위 내용의 위 끝 \(top.minY)")
        #expect(saved.value("mapSheet.hidden") == false)
    }
}
