import QuartzCore
import SwiftUI

/// `MapSheetScaffold` 가 슬롯에 넘겨 주는 값. 배경(지도)이 카메라를 맞추고 플로팅 UI 를
/// 시트 위에 띄우는 데 필요한 치수만 담는다.
public struct MapSheetState: Equatable, Sendable {
    /// 시트가 펼쳐져 있는가. 드래그 중에도 **정착 목표** 기준이라 값이 흔들리지 않는다
    public let expanded: Bool
    /// 시트가 **손잡이만 남기고 내려가 있는가**(`hideable` 시트만 — 14 홈). 이때 지도는 손잡이 줄 위를
    /// 전부 쓴다. `expanded` 와 같이 **정착 목표** 기준이다.
    public let hidden: Bool
    public let containerWidth: CGFloat
    public let containerHeight: CGFloat
    /// 앵커 기준 시트 높이. 드래그·정착 애니메이션 중에도 **목표값**이라 프레임마다 변하지 않는다.
    /// 카메라 fit·contentPadding 은 반드시 이 값을 써야 한다 — 실측값(`sheetHeight`)을 쓰면
    /// 애니메이션 매 프레임 카메라가 다시 잡혀 사용자의 팬·줌과 싸운다.
    public let settledSheetHeight: CGFloat
    /// 실측 시트 높이. 콘텐츠가 정하므로 `settledSheetHeight` 와 몇 dp 다를 수 있다.
    /// 지도 위 플로팅 버튼을 시트 **바로 위**에 붙일 때만 쓴다.
    public let sheetHeight: CGFloat

    public init(
        expanded: Bool,
        hidden: Bool = false,
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        settledSheetHeight: CGFloat,
        sheetHeight: CGFloat
    ) {
        self.expanded = expanded
        self.hidden = hidden
        self.containerWidth = containerWidth
        self.containerHeight = containerHeight
        self.settledSheetHeight = settledSheetHeight
        self.sheetHeight = sheetHeight
    }

    /// 시트에 가리지 않고 실제로 보이는 지도 높이(앵커 기준). `fitMapCamera` 의 heightDp 다.
    public var visibleMapHeight: CGFloat {
        max(containerHeight - settledSheetHeight, 1)
    }
}

public enum MapSheetDefaults {
    /// 펼친 시트 위로 남겨두는 지도 높이
    public static let MapRevealHeight: CGFloat = 160

    /// 접은 시트의 대략적인 높이. **추정치**다 — 실제 높이는 콘텐츠가 정한다(에러 배너가 뜨면 커진다).
    /// 드래그 앵커와 카메라 계산에만 쓰이므로 몇 dp 어긋나도 펼침 상태에서 남는 지도 높이가
    /// 그만큼 달라질 뿐 동작에는 영향이 없다. 화면마다 접힘 콘텐츠가 다르니 각자 넘긴다.
    public static let CollapsedSheetHeight: CGFloat = 176
}

/// 이 속도(px/s) 이상으로 던지면 위치와 무관하게 그 방향의 앵커로 붙는다.
/// 단위가 px 라 제스처 속도(pt/s)에 화면 배율을 곱해 비교한다.
let SheetFlingVelocity: CGFloat = 400

/// 시트의 앵커 셋. `hidden` 은 `hideable` 시트에만 있다. 선언 순서가 아래 → 위(위치 오름차순)다.
enum SheetAnchor: CaseIterable, Sendable {
    case hidden, collapsed, expanded
}

/// 손잡이 줄 높이 = 위 12 + 손잡이 4 + 아래 12. 손잡이만 남을 때 보이는 높이이기도 하다.
let SheetHandleZoneHeight: CGFloat = 28

/// 접고 편 상세 영역의 최대 높이. 접힘 ↔ 펼침 사이의 거리다.
func mapSheetDetailMax(containerHeight: CGFloat, mapRevealHeight: CGFloat, collapsedSheetHeight: CGFloat) -> CGFloat {
    max(containerHeight - mapRevealHeight - collapsedSheetHeight, 0)
}

/// 시트를 손잡이 줄만 남기고 내릴 거리 = (손잡이 + 위 + 아래) 실측 높이 − 손잡이 줄. `hideable` 이 아니면 0.
///
/// **상세 영역은 재지 않는다** — 애니메이션 중에 높이가 변하는 영역을 앵커 계산에 넣으면 앵커가 프레임마다 흔들린다.
func mapSheetHiddenSpan(hideable: Bool, topChromeHeight: CGFloat, footerHeight: CGFloat) -> CGFloat {
    hideable ? max(topChromeHeight + footerHeight - SheetHandleZoneHeight, 0) : 0
}

/// 앵커 셋을 **한 줄의 위치**로 놓는다: 0 = 손잡이만, `hiddenSpan` = 접힘, `hiddenSpan + detailMax` = 펼침.
func mapSheetAnchorPosition(_ anchor: SheetAnchor, hiddenSpan: CGFloat, detailMax: CGFloat) -> CGFloat {
    switch anchor {
    case .hidden: 0
    case .collapsed: hiddenSpan
    case .expanded: hiddenSpan + detailMax
    }
}

/// 한 줄의 위치에서 상세 높이(위쪽 구간)와 시트 내림 거리(아래쪽 구간)를 나눠 낸다.
func mapSheetSplit(position: CGFloat, hiddenSpan: CGFloat, detailMax: CGFloat) -> (detail: CGFloat, hide: CGFloat) {
    (
        detail: min(max(position - hiddenSpan, 0), detailMax),
        hide: min(max(hiddenSpan - position, 0), hiddenSpan)
    )
}

/// 앵커 기준 시트 높이(`MapSheetState.settledSheetHeight`).
func mapSheetSettledHeight(
    anchor: SheetAnchor,
    containerHeight: CGFloat,
    mapRevealHeight: CGFloat,
    collapsedSheetHeight: CGFloat
) -> CGFloat {
    switch anchor {
    case .expanded: max(containerHeight - mapRevealHeight, collapsedSheetHeight)
    case .collapsed: collapsedSheetHeight
    case .hidden: SheetHandleZoneHeight
    }
}

/// 손을 뗀 뒤 어느 앵커로 갈지. `velocity` 는 아래로 양수(px/s), `from`·`hiddenSpan`·`detailMax` 는 같은 단위(px)의 위치다.
///
/// - 아래로 던짐 → 지금 위치보다 낮은 앵커 중 가장 가까운 것(없으면 가장 낮은 것)
/// - 위로 던짐 → 지금 위치보다 높은 앵커 중 가장 가까운 것(없으면 가장 높은 것)
/// - 그 밖에는 가까운 앵커로. 같은 거리면 낮은 쪽이다(원본 `minBy` 는 앞의 것을 고른다)
func mapSheetSettleAnchor(
    velocity: CGFloat,
    from: CGFloat,
    hideable: Bool,
    hiddenSpan: CGFloat,
    detailMax: CGFloat
) -> SheetAnchor {
    let anchors = SheetAnchor.allCases.filter { hideable || $0 != .hidden }
    func position(_ anchor: SheetAnchor) -> CGFloat {
        mapSheetAnchorPosition(anchor, hiddenSpan: hiddenSpan, detailMax: detailMax)
    }
    if velocity > SheetFlingVelocity {
        return anchors.last { position($0) < from - 1 } ?? anchors[0]
    }
    if velocity < -SheetFlingVelocity {
        return anchors.first { position($0) > from + 1 } ?? anchors[anchors.count - 1]
    }
    var nearest = anchors[0]
    for anchor in anchors.dropFirst() where abs(position(anchor) - from) < abs(position(nearest) - from) {
        nearest = anchor
    }
    return nearest
}

/// Compose 기본 스프링(`spring()`: 감쇠비 1, 강성 1500)의 위치. 초기 속도는 0 이다.
/// 임계 감쇠의 해석해: x(t) = T + (x₀−T)(1 + ωt)e^(−ωt), ω = √강성.
func criticallyDampedSpring(from: CGFloat, target: CGFloat, elapsed: TimeInterval) -> CGFloat {
    let omega = sqrt(1500.0)
    let t = max(elapsed, 0)
    return target + (from - target) * CGFloat((1 + omega * t) * exp(-omega * t))
}

/// Compose `Animatable` 자리. SwiftUI 애니메이션은 진행 중인 값을 읽을 수 없는데, 정착 중에 시트를 다시 잡으면
/// 그 순간의 위치에서 이어 가야 하므로(원본 `dragPos ?: pos.value`) 값을 프레임마다 직접 계산한다.
@MainActor
@Observable
private final class SheetPositionAnimatable {
    /// nil 이면 앵커에 앉아 있다. 첫 프레임부터 목표 상태로 그리기 위한 값이다(깜빡임 없음).
    private(set) var value: CGFloat?

    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var from: CGFloat = 0
    @ObservationIgnored private var target: CGFloat = 0
    @ObservationIgnored private var startTime: CFTimeInterval = 0

    /// 정착 애니메이션이 도는 중인가(원본 `Animatable.isRunning`).
    var isRunning: Bool { displayLink != nil }

    func snapTo(_ newValue: CGFloat?) {
        stop()
        value = newValue
    }

    func animateTo(_ newTarget: CGFloat) {
        stop()
        from = value ?? newTarget
        target = newTarget
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(
            target: DisplayLinkProxy { [weak self] in
                self?.tick()
                return self != nil
            },
            selector: #selector(DisplayLinkProxy.fire(_:))
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        let next = criticallyDampedSpring(from: from, target: target, elapsed: CACurrentMediaTime() - startTime)
        if abs(next - target) < 0.01 {
            value = target
            stop()
        } else {
            value = next
        }
    }
}

@MainActor
private final class DisplayLinkProxy: NSObject {
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

/// 지도(또는 임의의 배경) 위에 **드래그로 접었다 펴는 시트**를 얹는 공용 레이아웃.
///
/// 접힘 ↔ 펼침은 시트 전체의 오프셋이 아니라 **가운데 `sheetDetail` 영역의 높이**(0 ↔ detailMax)로 움직인다.
/// 시트를 통째로 밀어 내리면 보이는 건 콘텐츠의 *윗부분*이라 하단에 고정된 CTA 가 화면 밖으로 나간다 —
/// 이 앱의 두 화면(16 도착지 확인, 21 매칭 대기) 모두 「같이 탈 사람 찾기」·「그만 찾기」가 접힘에서도
/// 보여야 해서 그 구조를 쓸 수 없다.
///
/// 시트 높이는 콘텐츠가 정한다. 에러 배너가 떠서 푸터가 커지면 시트가 그만큼 높아지고, 컨테이너보다 커지면
/// 원본 `Column` 처럼 컨테이너 높이에서 멈춰 위에서부터 쌓인 내용의 **아래쪽 푸터만** 잘린다(글자는 줄이지 않는다).
///
/// - Parameters:
///   - mapRevealHeight: 펼침 상태에서 시트 위로 남겨 둘 배경 높이
///   - collapsedSheetHeight: 접힘 높이 추정치 (`MapSheetDefaults.CollapsedSheetHeight` 설명 참고)
///   - hideable: true 면 접힘보다 한 단계 더 내려 **손잡이 줄(28)만** 남길 수 있다 — 아래 「세 번째 앵커」
///   - hiddenHandleLabel: 손잡이만 남았을 때 그 줄을 누르는 동작의 VoiceOver 이름(「검색 패널 펼치기」)
///   - background: 시트 뒤를 가득 채우는 내용(지도). 칩·버튼은 이 안에서 `frame(alignment:)` 로 얹는다
///   - sheetTop: 핸들 아래에 붙는 **항상 보이는** 내용. 핸들과 함께 실제 드래그 타깃이 된다
///   - sheetDetail: 접히면 높이가 0 이 되는 상세 영역. 내부는 세로 스크롤된다
///   - sheetFooter: 시트 하단에 **항상 보이는** 내용(CTA·요금 문구 등)
///
/// ### 세 번째 앵커 — 손잡이만 남기기 (`hideable`, 14 홈 · 2026-11 오너 UX 피드백)
/// 홈의 시트는 접어도 인사말·「어디로 갈까요?」·검색 바가 늘 떠 있어서 **지도를 다 볼 방법이 없었다.**
/// 그래서 접힘 아래에 앵커를 하나 더 둔다: 시트를 통째로 아래로 밀어 **손잡이 줄만** 하단탭 위에 남긴다.
///
/// - 앵커 셋을 **한 줄의 위치**로 다룬다 — 0 = 손잡이만, `hiddenSpan` = 접힘, `hiddenSpan + detailMax`
///   = 펼침. 드래그는 그 한 값을 움직이고, 상세 높이와 시트 내림 거리는 거기서 나눠 나온다(`mapSheetSplit`). 그래서 펼침에서
///   한 번에 끝까지 끌어내리면 상세가 먼저 접히고 이어서 시트가 내려간다(두 단계가 끊기지 않는다)
/// - `hiddenSpan` = (손잡이 + `sheetTop` + `sheetFooter`) 실측 높이 − 손잡이 줄. **상세 영역은 재지 않는다**
///   — 애니메이션 중에 높이가 변하는 영역을 앵커 계산에 넣으면 앵커가 프레임마다 흔들린다
/// - 손잡이만 남았을 때 그 줄을 **누르면** 접힘(검색 바가 보이는 상태)으로 돌아온다 — 드래그를 못 하는
///   사용자(VoiceOver·스위치 제어)를 위한 길이다(`hiddenHandleLabel`)
/// - 지도 `contentPadding` 은 손잡이 줄 높이가 된다(`MapSheetState.settledSheetHeight`) — 네이버 로고·축척이
///   손잡이 바로 위에 보인다
/// - 정착은 기존과 같은 기본 스프링(감쇠 1 — 튀지 않음)이다
///
/// `hideable` 이 false 면(16·21) 이 앵커가 없고 동작은 예전과 같다 — 그 두 화면은 접힘에서도 CTA 가
/// 보여야 해서 시트를 내릴 수 없다.
public struct MapSheetScaffold<Background: View, SheetTop: View, SheetDetail: View, SheetFooter: View>: View {
    private let mapRevealHeight: CGFloat
    private let collapsedSheetHeight: CGFloat
    private let hideable: Bool
    private let hiddenHandleLabel: String
    private let background: (MapSheetState) -> Background
    private let sheetTop: SheetTop
    private let sheetDetail: SheetDetail
    private let sheetFooter: SheetFooter

    // 앵커 — 정착 목표
    @State private var anchor: SheetAnchor
    @State private var position = SheetPositionAnimatable()
    // 드래그 중에는 애니메이션을 건드리지 않고 이 값만 따라간다 — 손가락이 움직일 때마다 정착 값을 건드리면
    // 놓아준 뒤의 정착 애니메이션과 섞여 시트가 어중간한 높이에 멈춘다.
    @State private var drag = SheetDragTracker()
    // 시스템이 제스처를 취소하면(전화 수신·제어 센터·앱 전환) `onEnded` 가 불리지 않는다.
    // 끝났다는 신호를 받는 길은 이 값이 저절로 되돌아오는 것뿐이다.
    @GestureState private var dragging = false
    @State private var sheetHeight: CGFloat = 0
    // 시트를 손잡이 줄만 남기고 내릴 거리의 재료 — (손잡이 + 위) 와 아래의 실측 높이. 상세는 재지 않는다.
    @State private var topChromeHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    // 14 홈이 탭이라 원본 `rememberSaveable` 의 앵커·상세 스크롤이 탭을 다녀와도 남아야 한다. 탭이 아닌 화면에서는 nil 이다.
    @Environment(\.tabSavedState) private var tabSavedState

    public init(
        mapRevealHeight: CGFloat = MapSheetDefaults.MapRevealHeight,
        collapsedSheetHeight: CGFloat = MapSheetDefaults.CollapsedSheetHeight,
        initiallyExpanded: Bool = true,
        hideable: Bool = false,
        hiddenHandleLabel: String = "펼치기",
        @ViewBuilder background: @escaping (MapSheetState) -> Background,
        @ViewBuilder sheetTop: () -> SheetTop,
        @ViewBuilder sheetDetail: () -> SheetDetail,
        @ViewBuilder sheetFooter: () -> SheetFooter
    ) {
        self.mapRevealHeight = mapRevealHeight
        self.collapsedSheetHeight = collapsedSheetHeight
        self.hideable = hideable
        self.hiddenHandleLabel = hiddenHandleLabel
        self.background = background
        self.sheetTop = sheetTop()
        self.sheetDetail = sheetDetail()
        self.sheetFooter = sheetFooter()
        _anchor = State(initialValue: initiallyExpanded ? .expanded : .collapsed)
    }

    public var body: some View {
        GeometryReader { geometry in
            content(containerSize: geometry.size)
        }
    }

    private func content(containerSize: CGSize) -> some View {
        let track = SheetTrack(
            hiddenSpan: mapSheetHiddenSpan(hideable: hideable, topChromeHeight: topChromeHeight, footerHeight: footerHeight),
            detailMax: mapSheetDetailMax(
                containerHeight: containerSize.height,
                mapRevealHeight: mapRevealHeight,
                collapsedSheetHeight: collapsedSheetHeight
            ),
            hideable: hideable
        )
        // 한 줄의 위치에서 두 값을 나눠 낸다: 위쪽 구간은 상세 높이, 아래쪽 구간은 시트 내림 거리
        let split = mapSheetSplit(
            position: drag.height ?? position.value ?? track.position(anchor),
            hiddenSpan: track.hiddenSpan,
            detailMax: track.detailMax
        )
        let state = MapSheetState(
            expanded: anchor == .expanded,
            hidden: anchor == .hidden,
            containerWidth: containerSize.width,
            containerHeight: containerSize.height,
            settledSheetHeight: mapSheetSettledHeight(
                anchor: anchor,
                containerHeight: containerSize.height,
                mapRevealHeight: mapRevealHeight,
                collapsedSheetHeight: collapsedSheetHeight
            ),
            // 실제로 보이는 높이 — 내려간 만큼 뺀다(지도 위 플로팅 버튼이 시트 바로 위에 붙도록)
            sheetHeight: max(sheetHeight - split.hide, 0)
        )
        let sheetShape = MoyeotaShape.Sheet

        return ZStack(alignment: .bottom) {
            background(state)
                .frame(width: containerSize.width, height: containerSize.height)

            VStack(alignment: .leading, spacing: 0) {
                // 드래그 손잡이 — 핸들과 그 아래 항상 보이는 줄 전체가 실제 드래그 타깃이다
                VStack(alignment: .leading, spacing: 0) {
                    SheetHandle()
                        .frame(maxWidth: .infinity)
                        .frame(height: SheetHandleZoneHeight)
                        .contentShape(Rectangle())
                        // 손잡이만 남았을 때 그 줄을 누르면 접힘(검색 바가 보이는 상태)으로 돌아온다 — 끌 수 없는 사용자를
                        // 위한 길. 그때 보이는 것이 이 줄뿐이라 누르는 자리도 이 줄이다. 다른 상태에서는 누르는 동작을
                        // 싣지 않는다(손잡이가 「누를 수 없는 버튼」으로 읽히지 않게).
                        .modifier(
                            HiddenHandleAction(active: anchor == .hidden, label: hiddenHandleLabel) {
                                settle(to: .collapsed, from: position.value ?? track.position(.hidden), track: track)
                            }
                        )
                    sheetTop
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topChromeHeight = $0 }
                .contentShape(Rectangle())
                .gesture(dragGesture(track: track))

                // 접히면 높이가 0 이 되는 상세 영역
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        sheetDetail
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .savedScrollOffset("mapSheet.detail")
                }
                .scrollBounceBehavior(.basedOnSize)
                // 원본 `verticalScroll` 은 스크롤 막대를 그리지 않는다.
                .scrollIndicators(.hidden)
                .frame(height: split.detail)

                VStack(alignment: .leading, spacing: 0) {
                    sheetFooter
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SheetColumnHeight())
            .background(MoyeotaColor.SurfaceCanvas)
            .clipShape(sheetShape)
            // 잘려 나간 푸터 아래쪽이 시트 밖의 터치를 가로채지 않게 한다(`clipShape` 는 터치를 자르지 않는다).
            .contentShape(sheetShape)
            // 시트 가장자리만 그림자를 갖는다(G4 — 8). 시트 **안의** 카드·칩에는 그림자를 두지 않는다
            .sheetShadow(sheetShape)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
            // 손잡이만 남기는 앵커 쪽으로 내려간 거리. 실측 높이(`sheetHeight`)는 내리기 전 값이다.
            .offset(y: split.hide)
        }
        .frame(width: containerSize.width, height: containerSize.height)
        // 내려간 시트가 컨테이너(하단탭 위) 밖으로 그려지지도, 터치를 받지도 않게 자른다
        .modifier(HideableSheetClip(active: hideable))
        .onAppear {
            if let saved: Bool = tabSavedState?.value("mapSheet.expanded") { anchor = saved ? .expanded : .collapsed }
            let hidden: Bool? = tabSavedState?.value("mapSheet.hidden")
            if hideable, hidden == true { anchor = .hidden }
        }
        .onChange(of: anchor) { _, value in
            tabSavedState?.set("mapSheet.expanded", value == .expanded)
            tabSavedState?.set("mapSheet.hidden", value == .hidden)
        }
        // 회전 등으로 앵커가 바뀌면(또는 위·아래 높이가 처음 재어지면) 현재 앵커로 다시 앉힌다.
        // 정착 애니메이션 중이면 건드리지 않는다 — 끝나는 자리가 이미 새 앵커다.
        .onChange(of: track) { _, _ in
            if !position.isRunning { position.snapTo(nil) }
        }
        // 떠나면 정착을 끝낸 것으로 친다. 돌아왔을 때 어중간한 높이에 머물지 않게 앵커로 앉힌다.
        .onDisappear {
            position.snapTo(nil)
            drag.clear()
        }
        // 원본 `draggable` 의 `onDragStopped` 는 포인터 입력이 취소돼도 불린다. 같은 결과가 되게 여기서 정착시킨다.
        // 정상 종료에서는 `onEnded` 와 이 신호의 순서에 기대지 않는다 — 어느 순서로 불려도 같은 앵커에 닿는다.
        .onChange(of: dragging) { _, active in
            if !active { settleInterruptedDrag(track: track) }
        }
        // 앱이 전면에서 내려가면 드래그는 이어질 수 없다. `@GestureState` 가 되돌아오는 길과 겹쳐도 한 번만 정착한다.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { settleInterruptedDrag(track: track) }
        }
    }

    private func dragGesture(track: SheetTrack) -> some Gesture {
        // 시트가 드래그를 따라 움직이므로 지역 좌표로 재면 값이 되먹임된다. 전역 좌표로 잰다.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                // 아래로 끌면 위치가 낮아진다 — 상세가 먼저 접히고, 이어서 시트가 내려간다
                drag.track(
                    y: value.location.y,
                    resting: position.value ?? track.position(anchor),
                    range: track.range
                )
            }
            .onEnded { value in
                settleDrag(velocity: value.velocity.height, track: track)
            }
    }

    /// 취소된 드래그를 정착시킨다. 던진 속도를 알 수 없으니 가까운 앵커로 간다(원본도 취소 때 속도 0 이다).
    /// 이미 끝난 드래그면 아무것도 하지 않는다.
    private func settleInterruptedDrag(track: SheetTrack) {
        if drag.height != nil { settleDrag(velocity: 0, track: track) }
    }

    /// - Parameter velocity: 드래그 속도(pt/s)
    private func settleDrag(velocity: CGFloat, track: SheetTrack) {
        let from = drag.finish(resting: position.value ?? track.position(anchor))
        let target = mapSheetSettleAnchor(
            velocity: velocity * displayScale,
            from: from * displayScale,
            hideable: hideable,
            hiddenSpan: track.hiddenSpan * displayScale,
            detailMax: track.detailMax * displayScale
        )
        settle(to: target, from: from, track: track)
    }

    private func settle(to target: SheetAnchor, from: CGFloat, track: SheetTrack) {
        anchor = target
        // 놓은 지점에서 이어서 정착시킨다(값을 먼저 옮기고 드래그 값을 비운다)
        drag.clear()
        position.snapTo(from)
        position.animateTo(track.position(target))
    }
}

/// 한 줄 위치의 눈금 — 앵커 셋의 자리와 드래그 범위.
private struct SheetTrack: Equatable {
    let hiddenSpan: CGFloat
    let detailMax: CGFloat
    let hideable: Bool

    func position(_ anchor: SheetAnchor) -> CGFloat {
        mapSheetAnchorPosition(anchor, hiddenSpan: hiddenSpan, detailMax: detailMax)
    }

    /// 손잡이만 남기는 앵커가 없으면(16·21) 접힘 아래로 끌리지 않는다.
    var range: ClosedRange<CGFloat> {
        (hideable ? 0 : hiddenSpan)...(hiddenSpan + detailMax)
    }
}

/// 손잡이만 남았을 때만 손잡이 줄에 「누르면 펼친다」를 싣는다.
/// 손잡이만 남은 시트의 손잡이 줄을 **누르면** 펼치는 동작 — 끌 수 없는 사용자(VoiceOver·스위치 제어)를 위한 길이다.
/// 14 홈(`MapSheetScaffold`)과 17 둘러보기 시트가 함께 쓴다. `active` 가 거짓이면 아무것도 싣지 않는다
/// (손잡이가 「누를 수 없는 버튼」으로 읽히지 않게).
public struct HiddenHandleAction: ViewModifier {
    let active: Bool
    let label: String
    let action: () -> Void

    public init(active: Bool, label: String, action: @escaping () -> Void) {
        self.active = active
        self.label = label
        self.action = action
    }

    public func body(content: Content) -> some View {
        if active {
            content
                // 탭은 위 드래그(8pt 이상 움직임)와 겹치지 않는다 — 움직이면 탭이 실패하고 드래그가 이어 받는다
                .onTapGesture(perform: action)
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
        } else {
            content
        }
    }
}

/// `hideable` 시트만 컨테이너 밖을 자른다(원본 `clipToBounds`). 그리기뿐 아니라 터치도 자른다 — 내려간 시트가
/// 하단탭 자리의 터치를 가로채지 않게.
private struct HideableSheetClip: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .clipped()
                .contentShape(Rectangle())
        } else {
            content
        }
    }
}

/// 원본 시트 `Column` 의 높이 규칙. 콘텐츠를 본래 높이로 재고(글자를 줄이지 않는다) **위에서부터** 놓되, 자기 크기는 부모
/// 높이를 넘지 않는다. 넘친 만큼은 아래쪽으로 나가 시트의 `clipShape` 에 잘린다.
///
/// `ZStack` 에 그대로 두면 큰 자식이 컨테이너 가운데에 놓여 넘친 만큼이 위아래로 나뉘고 VStack 은 글자를 줄이며,
/// `.frame(maxHeight:)` 는 제안 높이까지 늘어나 짧은 시트까지 컨테이너 높이가 된다.
private struct SheetColumnHeight: ViewModifier {
    func body(content: Content) -> some View {
        SheetColumnLayout { content }
    }
}

private struct SheetColumnLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        return CGSize(
            width: proposal.width ?? natural.width,
            height: min(natural.height, proposal.height ?? natural.height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}

/// 드래그 중인 시트 높이와 직전 손가락 위치.
///
/// 드래그가 어떻게 끝나든(`onEnded`·시스템 취소) `finish` 나 `clear` 로 **둘을 함께** 비워야 한다. 높이가 남으면
/// 시트가 어중간한 자리에 멈춰 단계를 바꿔도 움직이지 않고, 위치가 남으면 다음 드래그의 첫 값이 튄다.
public struct SheetDragTracker: Equatable {
    public private(set) var height: CGFloat?
    private var lastY: CGFloat?

    public init() {}

    /// - Parameters:
    ///   - y: 손가락의 전역 y
    ///   - resting: 드래그가 없을 때의 시트 높이. 첫 값이 여기서 시작한다
    ///   - range: 높이 범위(접힘 앵커…펼침 앵커)
    public mutating func track(y: CGFloat, resting: CGFloat, range: ClosedRange<CGFloat>) {
        // 터치 슬롭을 넘긴 첫 값은 이동으로 치지 않는다(시트가 튀지 않게).
        let delta = lastY.map { y - $0 } ?? 0
        lastY = y
        height = min(max((height ?? resting) - delta, range.lowerBound), range.upperBound)
    }

    /// 드래그를 끝내고 정착을 시작할 높이를 돌려준다.
    public mutating func finish(resting: CGFloat) -> CGFloat {
        defer { clear() }
        return height ?? resting
    }

    public mutating func clear() {
        height = nil
        lastY = nil
    }
}

public extension MapSheetScaffold where SheetTop == EmptyView, SheetDetail == EmptyView, SheetFooter == EmptyView {
    init(
        mapRevealHeight: CGFloat = MapSheetDefaults.MapRevealHeight,
        collapsedSheetHeight: CGFloat = MapSheetDefaults.CollapsedSheetHeight,
        initiallyExpanded: Bool = true,
        hideable: Bool = false,
        hiddenHandleLabel: String = "펼치기",
        @ViewBuilder background: @escaping (MapSheetState) -> Background
    ) {
        self.init(
            mapRevealHeight: mapRevealHeight,
            collapsedSheetHeight: collapsedSheetHeight,
            initiallyExpanded: initiallyExpanded,
            hideable: hideable,
            hiddenHandleLabel: hiddenHandleLabel,
            background: background,
            sheetTop: { EmptyView() },
            sheetDetail: { EmptyView() },
            sheetFooter: { EmptyView() }
        )
    }
}

public extension MapSheetScaffold where SheetTop == EmptyView {
    init(
        mapRevealHeight: CGFloat = MapSheetDefaults.MapRevealHeight,
        collapsedSheetHeight: CGFloat = MapSheetDefaults.CollapsedSheetHeight,
        initiallyExpanded: Bool = true,
        hideable: Bool = false,
        hiddenHandleLabel: String = "펼치기",
        @ViewBuilder background: @escaping (MapSheetState) -> Background,
        @ViewBuilder sheetDetail: () -> SheetDetail,
        @ViewBuilder sheetFooter: () -> SheetFooter
    ) {
        self.init(
            mapRevealHeight: mapRevealHeight,
            collapsedSheetHeight: collapsedSheetHeight,
            initiallyExpanded: initiallyExpanded,
            hideable: hideable,
            hiddenHandleLabel: hiddenHandleLabel,
            background: background,
            sheetTop: { EmptyView() },
            sheetDetail: sheetDetail,
            sheetFooter: sheetFooter
        )
    }
}

/// 지도 위에 얹는 흰 알약 배지의 그림자 색 — 요약 칩·「위치 조정」 버튼이 함께 쓴다.
/// 값은 `MoyeotaColor.ShadowOverlay` 하나다(이 이름은 기존 호출부를 위해 남긴다). 새 코드는
/// `.mapOverlayShadow(shape)` 를 쓴다 — 높이까지 `MoyeotaElevation.MapOverlay` 로 묶여 있다.
public let MapOverlayShadow: Color = MoyeotaColor.ShadowOverlay

/// `MapSheetScaffold` 시트 안쪽 좌우 여백 — 16·21 이 같은 값을 쓴다
public let MapSheetContentPadding: CGFloat = 16

/// 배경(지도) 위에 떠 있는 알약 형태의 흰 배지 — 요약 칩·상태 배지에 쓴다
public struct MapOverlayPill<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = MoyeotaShape.Pill
        content
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(MoyeotaColor.SurfaceCanvas, in: shape)
            .mapOverlayShadow(shape)
    }
}

/// 배경을 가득 채우는 자리표시자가 필요할 때 (지도 좌표가 없는 진입)
struct MapSheetBackgroundPlaceholder: View {
    var body: some View {
        MapPlaceholder()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
