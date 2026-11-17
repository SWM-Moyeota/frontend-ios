import SwiftUI
import UIKit

public enum WheelPickerDefaults {
    /// 한 줄 높이. 5줄이면 200 — 16 시트의 스크롤 영역 안에서 한 화면에 들어오는 높이다.
    public static let ItemHeight: CGFloat = 40

    /// 보이는 줄 수(홀수). 가운데 한 줄이 선택이고 위아래 두 줄씩이 「앞뒤에 무엇이 있는지」를 보여 준다
    /// — 한국 앱의 흔한 시/분 휠 모양이다. 짝수면 가운데가 없으므로 홀수만 쓴다.
    public static let VisibleItemCount: Int = 5
}

/// 휠 피커의 틀 — **가운데 줄 뒤에 강조 띠**를 깔고, 그 위에 휠(`SnapWheelPicker`)과 단위 글자(「시」·「분」)를
/// 한 줄로 얹는다.
///
/// 띠를 휠마다 따로 그리지 않고 틀이 한 번 그리는 이유: 시·분 두 휠과 단위 글자가 **한 줄의 값**
/// (「18 시 30 분」)으로 읽혀야 하는데, 휠마다 띠가 있으면 칸이 끊겨 두 개의 따로 노는 선택처럼 보인다.
/// 색은 `SurfaceSoft` 채움 + `MoyeotaShape.Small`(6) 모서리 — **파랑이 아니다**(디자인 QA 4-4). 이 시트의 파랑은 CTA 하나에
/// 아껴 둔다(DESIGN-moyeota.md 「한 화면에 primary 는 드물게」).
///
/// 원본 `Row` 의 `Modifier.weight(1f)` 자리는 휠에 `.frame(maxWidth: .infinity)` 를 준다 — 두 휠이 남는 폭을 똑같이 나눈다.
public struct WheelPickerFrame<Content: View>: View {
    private let itemHeight: CGFloat
    private let visibleItemCount: Int
    private let content: Content

    public init(
        itemHeight: CGFloat = WheelPickerDefaults.ItemHeight,
        visibleItemCount: Int = WheelPickerDefaults.VisibleItemCount,
        @ViewBuilder content: () -> Content
    ) {
        self.itemHeight = itemHeight
        self.visibleItemCount = visibleItemCount
        self.content = content()
    }

    public var body: some View {
        ZStack {
            MoyeotaShape.Small
                .fill(MoyeotaColor.SurfaceSoft)
                .frame(maxWidth: .infinity)
                .frame(height: itemHeight)
            HStack(alignment: .center, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: itemHeight * CGFloat(visibleItemCount))
    }
}

/// **손가락을 떼면 한 칸에 딱 붙는** 세로 휠.
///
/// 원본은 Compose 에 기본 휠 피커가 없어 `LazyColumn` + 스냅 플링으로 만든다. iOS 시스템 휠(`Picker(.wheel)`)은
/// 원통처럼 휜 줄, 휠마다 따로 그리는 선택 띠, 모든 줄이 같은 글자라 모양이 다르다. 그래서 줄은 SwiftUI 로 원본처럼
/// 그리고, 끌기·던지기·튕김만 투명한 `UIScrollView` 에 맡긴다(`docs/IOS-DIFFERENCES.md`).
///
/// ### 동작
/// - 위아래로 `visibleItemCount / 2` 줄만큼 여백을 둬서 **첫 항목과 끝 항목도 가운데 줄에 올 수 있다**.
///   그래서 「가운데에 있는 항목」 = 선택이다
/// - 스크롤이 **멈췄을 때만** `onSelectedIndexChange` 를 부른다 — 굴리는 도중의 값마다 부르면 부모가
///   그 값으로 범위를 다시 접고(시가 바뀌면 분 목록이 바뀐다) 다시 그리느라 휠이 손가락과 싸운다
/// - 부모가 `selectedIndex` 를 바꾸면(날짜를 바꿔 범위로 접혔을 때 등) 휠이 그 칸으로 **옮겨 간다**.
///   굴리는 중에는 옮기지 않는다(손가락이 이긴다)
/// - 항목을 탭하면 그 칸으로 굴러간다
/// - 한 칸 넘어갈 때마다 가벼운 햅틱 — 눈을 떼고 굴려도 몇 칸 움직였는지 손이 안다
/// - **세로 드래그를 끝까지 삼킨다** — 휠 끝에 닿은 손가락이 바깥(16 시트의 세로 스크롤)을 끌고 가면 휠을
///   굴리려던 사람의 화면이 통째로 움직인다. 안쪽 `UIScrollView` 가 끌기를 받으면 바깥 스크롤 뷰로 넘기지 않는다
///
/// ### 접근성 — 조절 가능한 값 하나
/// VoiceOver 사용자는 휠을 굴릴 수 없다. 그래서 휠 전체를 **하나의 조절 가능한 값**으로 내보내고, 줄 하나하나는
/// 접근성 트리에서 지운다 — 위아래 쓸기로 한 칸씩 바뀌고 「출발 시, 18시」처럼 읽힌다(`label` + `itemDescription`).
///
/// ### 빠지는 값 vs 흐린 값
/// 이 휠은 **받은 항목만** 그린다 — 고를 수 없는 값은 호출부가 목록에서 뺀다(예약의 「지난 시각」).
/// 흐리게 남겨 두면 손가락이 거기서 멈췄을 때 「되돌아가는」 동작이 필요하고, 그 사이 화면은 고를 수
/// 없는 값을 보여 준다.
///
/// - Parameters:
///   - items: 각 줄의 글자. 비어 있으면 아무것도 그리지 않는다
///   - label: 이 휠이 무엇을 고르는지(「출발 시」) — VoiceOver 가 값 앞에 읽는다
///   - itemDescription: VoiceOver 가 읽을 각 줄의 문장(「18시」). 단위가 따로 그려지는 휠이라
///     숫자만 읽히면 무엇의 18 인지 모른다. nil 이면 줄의 글자 그대로다
public struct SnapWheelPicker: View {
    private let items: [String]
    private let selectedIndex: Int
    private let onSelectedIndexChange: (Int) -> Void
    private let label: String
    private let itemHeight: CGFloat
    private let visibleItemCount: Int
    private let itemDescription: ((Int) -> String)?

    @State private var wheel: WheelScrollState

    public init(
        items: [String],
        selectedIndex: Int,
        onSelectedIndexChange: @escaping (Int) -> Void,
        label: String,
        itemHeight: CGFloat = WheelPickerDefaults.ItemHeight,
        visibleItemCount: Int = WheelPickerDefaults.VisibleItemCount,
        itemDescription: ((Int) -> String)? = nil
    ) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.onSelectedIndexChange = onSelectedIndexChange
        self.label = label
        self.itemHeight = itemHeight
        self.visibleItemCount = visibleItemCount
        self.itemDescription = itemDescription
        // 처음 그릴 때부터 선택 칸이 가운데다(원본 `initialFirstVisibleItemIndex`)
        _wheel = State(initialValue: WheelScrollState(position: CGFloat(wheelSafeIndex(selectedIndex, itemCount: items.count))))
    }

    public var body: some View {
        if !items.isEmpty {
            let lastIndex = items.count - 1
            let safeSelected = wheelSafeIndex(selectedIndex, itemCount: items.count)
            let position = wheel.position
            let centered = wheelCenteredIndex(position: position, lastIndex: lastIndex)
            let half = CGFloat(visibleItemCount / 2)
            ZStack(alignment: .top) {
                ForEach(wheelVisibleIndices(position: position, visibleItemCount: visibleItemCount, lastIndex: lastIndex), id: \.self) { index in
                    WheelRow(text: items[index], distance: abs(index - centered), itemHeight: itemHeight)
                        .offset(y: (CGFloat(index) - position + half) * itemHeight)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: itemHeight * CGFloat(visibleItemCount), alignment: .top)
            .clipped()
            .overlay {
                WheelScrollDriver(
                    state: wheel,
                    itemCount: items.count,
                    itemHeight: itemHeight,
                    selectedIndex: safeSelected
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(itemDescription?(safeSelected) ?? items[safeSelected])
            .accessibilityAdjustableAction { direction in
                let target: Int = switch direction {
                case .increment: min(safeSelected + 1, lastIndex)
                case .decrement: max(safeSelected - 1, 0)
                @unknown default: safeSelected
                }
                if target != safeSelected { onSelectedIndexChange(target) }
            }
            // 손가락을 떼고 스냅까지 끝났을 때 한 번 — 그때 가운데에 있는 칸이 새 선택이다
            .onChange(of: wheel.settleCount) { _, _ in
                let index = min(max(wheel.settledIndex, 0), lastIndex)
                if index != safeSelected { onSelectedIndexChange(index) }
            }
        }
    }
}

/// 휠의 한 줄. 가운데(선택) 줄만 크고 진하게, 멀어질수록 흐리게(0.6 → 0.3) — 휠의 「원통」 느낌을
/// 그림자·그라데이션 없이(DESIGN: 크롬에 그라데이션 금지) 글자 크기와 투명도만으로 낸다.
private struct WheelRow: View {
    let text: String
    let distance: Int
    let itemHeight: CGFloat

    var body: some View {
        let style = distance == 0 ? MoyeotaType.HeadingLg : MoyeotaType.BodyMd
        let color: Color = switch distance {
        case 0: MoyeotaColor.InkPrimary
        case 1: MoyeotaColor.TextMute.opacity(0.6)
        default: MoyeotaColor.TextMute.opacity(0.3)
        }
        Text(text)
            .moyeotaText(style, color: color)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: itemHeight)
    }
}

// ─────────────────────────── 계산 ───────────────────────────

/// 부모가 넘긴 선택을 목록 안으로 접는다(원본 `coerceIn(0, items.lastIndex)`). 빈 목록이면 0.
func wheelSafeIndex(_ index: Int, itemCount: Int) -> Int {
    min(max(index, 0), max(itemCount - 1, 0))
}

/// 가운데 줄에 가장 가까운 항목. `position` 은 가운데에 놓인 자리(항목 단위, 18.0 이면 18번째가 가운데)다.
/// 정확히 두 항목 사이면 앞 항목이다(원본 `minByOrNull` 은 먼저 나온 쪽을 고른다).
func wheelCenteredIndex(position: CGFloat, lastIndex: Int) -> Int {
    guard position.isFinite else { return 0 }
    return min(max(Int((position - 0.5).rounded(.up)), 0), max(lastIndex, 0))
}

/// 손을 뗀 뒤 멈출 칸 — 스크롤 뷰가 계산한 도착 자리(`offset`)에 가장 가까운 항목.
func wheelSnappedIndex(offset: CGFloat, itemHeight: CGFloat, lastIndex: Int) -> Int {
    guard itemHeight > 0 else { return 0 }
    return wheelCenteredIndex(position: offset / itemHeight, lastIndex: lastIndex)
}

/// 탭한 자리의 항목. 위아래 여백 줄(첫 항목 위·끝 항목 아래)에는 항목이 없어 nil 이다.
///
/// - Parameter locationY: 스크롤 뷰 **내용** 좌표의 y. 항목 i 의 가운데는 `i × itemHeight + viewportHeight / 2` 다
func wheelTappedIndex(locationY: CGFloat, viewportHeight: CGFloat, itemHeight: CGFloat, itemCount: Int) -> Int? {
    guard itemHeight > 0, itemCount > 0 else { return nil }
    let row = ((locationY - viewportHeight / 2 + itemHeight / 2) / itemHeight).rounded(.down)
    guard row.isFinite, row >= 0, row < CGFloat(itemCount) else { return nil }
    return Int(row)
}

/// 지금 보이는(위아래 한 줄씩 넉넉히) 항목들. 원본 `LazyColumn` 처럼 보이는 줄만 그린다.
func wheelVisibleIndices(position: CGFloat, visibleItemCount: Int, lastIndex: Int) -> [Int] {
    guard lastIndex >= 0, position.isFinite else { return [] }
    let half = visibleItemCount / 2
    let low = max(Int(position.rounded(.down)) - half - 1, 0)
    let high = min(Int(position.rounded(.up)) + half + 1, lastIndex)
    return low <= high ? Array(low...high) : []
}

// ─────────────────────────── 스크롤 ───────────────────────────

/// 휠의 스크롤 상태. 줄을 그리는 SwiftUI 와 끌기를 받는 `UIScrollView` 가 함께 본다.
@MainActor
@Observable
final class WheelScrollState {
    /// 가운데에 놓인 자리(항목 단위). 튕기는 동안에는 0 보다 작거나 끝 항목보다 클 수 있다.
    fileprivate(set) var position: CGFloat
    /// 손가락이 끌고 있거나, 던진 뒤 미끄러지거나, 탭한 칸으로 굴러가는 중인가(원본 `isScrollInProgress`).
    fileprivate(set) var isScrollInProgress = false
    /// 스크롤이 멈출 때마다 하나씩 는다. 멈춘 자리는 `settledIndex` 다.
    fileprivate(set) var settleCount = 0
    fileprivate(set) var settledIndex = 0

    init(position: CGFloat) {
        self.position = position
    }
}

/// 끌기·던지기·튕김을 맡는 투명한 스크롤 뷰. 내용은 비어 있고 높이만 있다 — 항목 i 가 가운데일 때 `contentOffset.y` 가
/// `i × itemHeight` 다.
private struct WheelScrollDriver: UIViewRepresentable {
    let state: WheelScrollState
    let itemCount: Int
    let itemHeight: CGFloat
    let selectedIndex: Int

    func makeCoordinator() -> WheelScrollCoordinator {
        WheelScrollCoordinator(state: state)
    }

    func makeUIView(context: Context) -> WheelScrollView {
        let view = WheelScrollView()
        view.backgroundColor = .clear
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceVertical = true
        view.alwaysBounceHorizontal = false
        view.scrollsToTop = false
        view.contentInsetAdjustmentBehavior = .never
        view.decelerationRate = .normal
        // 값은 바깥 SwiftUI 뷰가 조절 가능한 요소 하나로 알린다
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(WheelScrollCoordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: WheelScrollView, context: Context) {
        context.coordinator.update(itemCount: itemCount, itemHeight: itemHeight, selectedIndex: selectedIndex)
    }
}

private final class WheelScrollView: UIScrollView {
    var itemCount = 0
    var itemHeight: CGFloat = WheelPickerDefaults.ItemHeight
    /// 크기를 처음 알게 됐을 때 한 번 — 그 전에는 내용 크기가 없어 자리를 맞출 수 없다.
    var onFirstLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.height > 0 else { return }
        let height = CGFloat(max(itemCount - 1, 0)) * itemHeight + bounds.height
        let size = CGSize(width: bounds.width, height: height)
        if contentSize != size { contentSize = size }
        if let first = onFirstLayout {
            onFirstLayout = nil
            first()
        }
    }
}

@MainActor
private final class WheelScrollCoordinator: NSObject, UIScrollViewDelegate {
    private let state: WheelScrollState
    private weak var scrollView: WheelScrollView?
    private let haptics = UISelectionFeedbackGenerator()
    private var itemCount = 0
    private var itemHeight: CGFloat = WheelPickerDefaults.ItemHeight
    /// 크기를 알고 처음 자리를 맞춘 뒤부터 스크롤 값을 믿는다. 그 전의 `contentOffset` 은 0 이다.
    private var ready = false
    /// 마지막으로 맞춘 부모 선택과 항목 수(원본 `LaunchedEffect(safeSelected, items.size)` 의 키).
    private var appliedKey: (selected: Int, count: Int)?
    /// 마지막으로 햅틱을 울린(또는 시작한) 가운데 칸.
    private var lastCentered = 0

    init(state: WheelScrollState) {
        self.state = state
    }

    func attach(_ view: WheelScrollView) {
        scrollView = view
        view.onFirstLayout = { [weak self, weak view] in
            guard let self, let view else { return }
            self.ready = true
            self.moveWithoutScrolling(view, to: self.state.position)
        }
    }

    func update(itemCount: Int, itemHeight: CGFloat, selectedIndex: Int) {
        if let view = scrollView, view.itemCount != itemCount || view.itemHeight != itemHeight {
            view.itemCount = itemCount
            view.itemHeight = itemHeight
            view.setNeedsLayout()
        }
        self.itemCount = itemCount
        self.itemHeight = itemHeight
        let key = (selected: selectedIndex, count: itemCount)
        if let applied = appliedKey, applied == key { return }
        appliedKey = key
        // 원본 `LaunchedEffect(safeSelected, items.size)` 처럼 그리기가 끝난 다음 차례에 맞춘다 — 뷰를 고치는 도중에
        // 상태를 바꾸지 않는다.
        Task { @MainActor [weak self] in
            self?.alignToParent(selectedIndex: selectedIndex)
        }
    }

    /// 부모가 정한 선택으로 맞춘다(범위가 바뀌어 접힌 경우 등). 굴리는 중이면 손가락을 존중한다.
    ///
    /// 멈춰 있는 휠은 늘 칸에 붙어 있으므로 원본의 「가운데 칸이 선택과 다른가」는 「자리가 선택과 다른가」와 같다. 자리로 보는
    /// 이유는 항목이 줄어 가운데 자리가 목록 밖에 남은 경우(접힌 선택이 끝 항목이 된다)까지 함께 잡으려는 것이다 — 원본
    /// `LazyColumn` 은 그때 스크롤 자리를 스스로 줄인다.
    private func alignToParent(selectedIndex: Int) {
        guard !state.isScrollInProgress, itemCount > 0 else { return }
        let target = CGFloat(wheelSafeIndex(selectedIndex, itemCount: itemCount))
        guard state.position != target else { return }
        state.position = target
        lastCentered = Int(target)
        if ready, let view = scrollView {
            view.layoutIfNeeded()
            moveWithoutScrolling(view, to: target)
        }
    }

    /// 애니메이션 없이 자리를 옮긴다(원본 `scrollToItem`). 햅틱은 울리지 않는다.
    private func moveWithoutScrolling(_ view: UIScrollView, to position: CGFloat) {
        view.setContentOffset(CGPoint(x: 0, y: position * itemHeight), animated: false)
        lastCentered = wheelCenteredIndex(position: position, lastIndex: itemCount - 1)
    }

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard ready, itemHeight > 0 else { return }
        let position = scrollView.contentOffset.y / itemHeight
        if state.position != position { state.position = position }
        // 굴리는 동안 가운데 칸이 바뀔 때마다 한 번 — 부모가 옮기는 자리(범위로 접힘)에는 울리지 않는다
        let centered = wheelCenteredIndex(position: position, lastIndex: itemCount - 1)
        if centered != lastCentered {
            lastCentered = centered
            if state.isScrollInProgress {
                haptics.selectionChanged()
                haptics.prepare()
            }
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        state.isScrollInProgress = true
        haptics.prepare()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        // 손가락을 떼면 한 칸에 딱 붙는다 — 미끄러져 멈출 자리를 가장 가까운 칸으로 옮긴다
        let index = wheelSnappedIndex(offset: targetContentOffset.pointee.y, itemHeight: itemHeight, lastIndex: itemCount - 1)
        targetContentOffset.pointee.y = CGFloat(index) * itemHeight
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishOrAlign(scrollView) }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishOrAlign(scrollView)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        finishOrAlign(scrollView)
    }

    /// 칸에 딱 붙어 있으면 멈춘 것으로 친다. 아니면(속도 없이 놓았거나 미끄러지던 휠을 손가락이 붙잡았다) 가까운 칸으로 굴린다.
    private func finishOrAlign(_ scrollView: UIScrollView) {
        let index = wheelSnappedIndex(offset: scrollView.contentOffset.y, itemHeight: itemHeight, lastIndex: itemCount - 1)
        let aligned = CGFloat(index) * itemHeight
        if abs(scrollView.contentOffset.y - aligned) > 0.5 {
            state.isScrollInProgress = true
            scrollView.setContentOffset(CGPoint(x: 0, y: aligned), animated: true)
            return
        }
        guard state.isScrollInProgress else { return }
        state.isScrollInProgress = false
        state.settledIndex = index
        state.settleCount += 1
    }

    /// 항목을 탭하면 그 칸으로 굴러간다(원본 `animateScrollToItem`). 여백 줄을 탭하면 가까운 칸에 앉힌다 — 미끄러지던 휠을
    /// 손가락이 붙잡은 채로 끝났을 수 있어서다.
    @objc func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let scrollView = recognizer.view as? UIScrollView, itemHeight > 0 else { return }
        let location = recognizer.location(in: scrollView)
        guard let index = wheelTappedIndex(
            locationY: location.y,
            viewportHeight: scrollView.bounds.height,
            itemHeight: itemHeight,
            itemCount: itemCount
        ) else {
            finishOrAlign(scrollView)
            return
        }
        let target = CGFloat(index) * itemHeight
        if abs(scrollView.contentOffset.y - target) <= 0.5 {
            finishOrAlign(scrollView)
            return
        }
        state.isScrollInProgress = true
        haptics.prepare()
        scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
    }
}
