import SwiftUI
import Testing
import UIKit
@testable import MoyeotaDesignSystem

// 원본에 없는 테스트. iOS 휠은 줄을 SwiftUI 로 그리고 끌기를 투명한 `UIScrollView` 에 맡긴다(`docs/IOS-DIFFERENCES.md`).
// 둘을 잇는 약속 — 처음 자리, 부모가 바꾼 선택으로 옮겨 가기, 손을 떼면 칸에 붙고 멈춘 뒤에만 알리기 — 을 창에 올려 본다.
// 손가락은 흉내 낼 수 없어 스크롤 뷰 대리자에 끌기의 순서대로 신호를 보낸다.

@MainActor
@Observable
private final class WheelModel {
    var selected = 18
    var changes: [Int] = []
}

private struct WheelHarness: View {
    let model: WheelModel

    var body: some View {
        WheelPickerFrame {
            SnapWheelPicker(
                items: (0..<24).map { String($0) },
                selectedIndex: model.selected,
                onSelectedIndexChange: { index in
                    model.changes.append(index)
                    model.selected = index
                },
                label: "출발 시",
                itemDescription: { "\($0)시" }
            )
            .frame(maxWidth: .infinity)
            Text("시")
        }
        .frame(width: 288)
    }
}

private func scrollViews(in view: UIView) -> [UIScrollView] {
    ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
}

@MainActor
@Suite(.serialized) struct SnapWheelPickerHostTest {
    private func host(_ model: WheelModel) async -> (UIWindow, UIScrollView?) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = UIHostingController(rootView: WheelHarness(model: model))
        window.isHidden = false
        await settle(window)
        return (window, window.rootViewController.flatMap { scrollViews(in: $0.view).first })
    }

    private func settle(_ window: UIWindow) async {
        for _ in 0..<20 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test("처음부터 선택 칸이 가운데다")
    func startsAtSelection() async throws {
        let model = WheelModel()
        let (window, found) = await host(model)
        defer { window.isHidden = true }
        let scroll = try #require(found)

        #expect(scroll.bounds.height == 200, "5줄 × 40")
        #expect(abs(scroll.contentOffset.y - 18 * 40) < 0.5)
        #expect(abs(scroll.contentSize.height - (23 * 40 + 200)) < 0.5, "첫·끝 항목도 가운데에 올 수 있는 높이")
        #expect(model.changes.isEmpty, "처음 그릴 때 선택을 바꿨다고 알리지 않는다")
    }

    @Test("부모가 선택을 바꾸면 그 칸으로 옮겨 가고 되알리지 않는다")
    func followsParentSelection() async throws {
        let model = WheelModel()
        let (window, found) = await host(model)
        defer { window.isHidden = true }
        let scroll = try #require(found)

        model.selected = 5
        await settle(window)

        #expect(abs(scroll.contentOffset.y - 5 * 40) < 0.5)
        #expect(model.changes.isEmpty)
    }

    @Test("손을 떼면 가장 가까운 칸에 붙고 멈춘 뒤에 한 번 알린다")
    func dragSnapsAndReportsOnce() async throws {
        let model = WheelModel()
        let (window, found) = await host(model)
        defer { window.isHidden = true }
        let scroll = try #require(found)
        let delegate = try #require(scroll.delegate)

        delegate.scrollViewWillBeginDragging?(scroll)
        scroll.contentOffset.y = 7.3 * 40
        #expect(model.changes.isEmpty, "굴리는 도중에는 알리지 않는다")
        var target = CGPoint(x: 0, y: 7.3 * 40)
        withUnsafeMutablePointer(to: &target) { pointer in
            delegate.scrollViewWillEndDragging?(scroll, withVelocity: .zero, targetContentOffset: pointer)
        }
        #expect(abs(target.y - 7 * 40) < 0.001, "도착 자리를 가장 가까운 칸으로 옮긴다: \(target.y)")
        scroll.contentOffset = target
        delegate.scrollViewDidEndDecelerating?(scroll)
        await settle(window)

        #expect(model.changes == [7])
        #expect(abs(scroll.contentOffset.y - 7 * 40) < 0.5)
    }
}
