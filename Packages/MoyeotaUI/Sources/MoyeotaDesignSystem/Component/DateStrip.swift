import SwiftUI

/// 날짜 칸의 요일 색 — 달력의 관습(토 파랑 · 일 빨강)을 그대로 따른다.
///
/// 색만으로 요일을 구분하지 않는다: 칸에는 늘 요일 **글자**가 함께 있다(색은 덧붙인 단서다).
public enum DateStripTone: Hashable, Sendable {
    case weekday
    case saturday
    case sunday
}

/// 날짜 칸 하나가 그릴 것 — **글자는 호출부가 다 만들어 넘긴다.**
///
/// 이 모듈은 도메인과 달력 계산을 모른다. 「오늘이 언제인가」·「한국 시간대인가」·「요일 글자」·「그 날에 고를
/// 시각이 있는가」는 전부 호출부의 순수 함수가 정한다(`PresentationCore` 의 `reservationDateCells`) — 그래야 그
/// 규칙을 단위 테스트로 고정할 수 있다.
///
/// - Parameters:
///   - weekday: 위 줄 — 요일 한 글자(「토」)
///   - day: 아래 줄 — 일(「14」)
///   - isToday: 오늘이면 숫자 아래 작은 점을 찍는다(선택 여부와 무관하게)
///   - enabled: false 면 **누를 수 없고** 숫자가 흐려진다 — 그 날에 고를 수 있는 시각이 없을 때
///     (늦은 밤의 「오늘」). 칸을 지우지 않는 이유: 8칸 달력에서 한 칸이 빠지면 요일 줄이 밀려 「오늘」을
///     찾을 수 없다
///   - contentDescription: VoiceOver 문장 — 「오늘, 11월 12일 목요일」 같은 완결된 말
public struct DateStripCell: Hashable, Sendable {
    public var weekday: String
    public var day: String
    public var tone: DateStripTone
    public var isToday: Bool
    public var contentDescription: String
    public var enabled: Bool

    public init(
        weekday: String,
        day: String,
        tone: DateStripTone,
        isToday: Bool,
        contentDescription: String,
        enabled: Bool = true
    ) {
        self.weekday = weekday
        self.day = day
        self.tone = tone
        self.isToday = isToday
        self.contentDescription = contentDescription
        self.enabled = enabled
    }
}

public enum DateStripDefaults {
    /// 칸 높이 — 요일(12) · 2 · 날짜 원(36) · 2 · 오늘 점(4). 44pt 터치 타깃을 세로로 넉넉히 넘는다.
    public static let CellHeight: CGFloat = 60

    /// 선택 표시 원의 지름 — 날짜 숫자를 감싼다.
    public static let SelectionDiameter: CGFloat = 36

    /// 「한 줄에 8칸을 나눠 담는다」가 성립하는 칸 최소 폭. 360 폭 폰의 가장 좁은 자리(16 카드 안 288)가
    /// 정확히 36 이다. 이보다 좁으면(320 폭 — iPhone SE 의 확대 보기) 칸을 `ScrollCellWidth` 로 고정하고
    /// 가로로 스크롤한다.
    public static let MinEqualCellWidth: CGFloat = 36

    /// 스크롤로 떨어질 때의 칸 폭.
    public static let ScrollCellWidth: CGFloat = 44
}

/// 칸 폭을 같게 나눌 수 있는가 — 아니면 가로 스크롤로 떨어진다(`DateStripDefaults.MinEqualCellWidth`).
func weekDateStripFitsEqually(width: CGFloat, contentPadding: EdgeInsets, cellCount: Int) -> Bool {
    guard cellCount > 0 else { return true }
    return (width - contentPadding.leading - contentPadding.trailing) / CGFloat(cellCount) >= DateStripDefaults.MinEqualCellWidth
}

/// **주간 달력 띠** — 위에 요일, 아래에 날짜 숫자가 있는 칸 8개(오늘~7일 뒤).
///
/// 16 도착지 확인(예약 날짜)과 17 탐색 「날짜로 찾기」가 **같은 컴포넌트**를 쓴다 — 같은 8일 창을 두
/// 화면이 다른 모양으로 고르면 같은 날이 다르게 보인다. 그래서 두 화면이 함께 보는 이 모듈에 둔다.
///
/// ### 모양 (디자인 QA 4-3)
/// - **8칸을 같은 폭으로** 나눠 한 줄에 담는다 — 달력은 한눈에 일주일이 보여야 달력이다. 그보다 좁으면
///   (`DateStripDefaults.MinEqualCellWidth` 미만) 가로 스크롤로 떨어지고, 그때는 **선택 칸이 다 보이지 않으면
///   그 칸까지 스크롤**해 보여 준다
/// - 글자: 요일 `CaptionMd`, 숫자 `BodyStrong`, 기본 색 `TextBody`. **토요일 `Primary600` · 일요일
///   `Danger600`** — 500 이 아니라 600 인 이유는 12pt 글자가 4.5:1 대비를 넘게 하려는 것이고, `Primary500`
///   은 선택 색이라 겹치면 토요일이 골라진 것처럼 보인다
/// - 선택: 숫자를 감싸는 36 `Primary500` 원 + 흰 숫자. 요일 글자는 제 색을 지킨다
/// - 오늘: 숫자 아래 4 `TextMute` 점(선택돼도 같다)
/// - 고를 수 없는 날(`DateStripCell.enabled` false): 요일·숫자 `TextPlaceholder`, 누르지 못한다
/// - 칩·테두리·그림자는 없다 — 카드 안에 또 하나의 카드를 만들지 않는다
///
/// ### 터치 타깃
/// 칸 사이에 틈을 두지 않고 **칸 전체(폭 × 60)를 누를 수 있게** 한다. 칸 폭은 36~39 로 권장보다 좁지만
/// (8칸을 한 줄에 담는다는 결정의 대가다), 틈이 없어 띠 어디를 눌러도 가장 가까운 날짜가 잡히고 세로는 60 이다.
///
/// ### 접근성
/// 칸은 「선택됨」 특성이 붙는 버튼이다 — 「8개 중 하나를 고른다」가 VoiceOver 에 전달된다. 칸 안의 글자는
/// 따로 읽히지 않고 `DateStripCell.contentDescription` 한 문장으로 읽힌다.
///
/// - Parameter contentPadding: 띠 양 끝 여백. 같은 폭 모드에서는 그만큼 안쪽에서 8칸을 나누고, 스크롤 모드에서는
///   스크롤 영역 **안쪽**에 둬서 첫 칸이 제목과 같은 선에서 시작하고 스크롤하면 가장자리까지 흐른다
public struct WeekDateStrip: View {
    private let cells: [DateStripCell]
    private let selectedIndex: Int
    private let onSelect: (Int) -> Void
    private let contentPadding: EdgeInsets

    public init(
        cells: [DateStripCell],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void,
        contentPadding: EdgeInsets = EdgeInsets()
    ) {
        self.cells = cells
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
        self.contentPadding = contentPadding
    }

    public var body: some View {
        if !cells.isEmpty {
            GeometryReader { geometry in
                if weekDateStripFitsEqually(width: geometry.size.width, contentPadding: contentPadding, cellCount: cells.count) {
                    HStack(spacing: 0) {
                        ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                            DateStripCellView(cell: cell, selected: index == selectedIndex) { onSelect(index) }
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.leading, contentPadding.leading)
                    .padding(.trailing, contentPadding.trailing)
                } else {
                    ScrollingDateStrip(
                        cells: cells,
                        selectedIndex: selectedIndex,
                        onSelect: onSelect,
                        contentPadding: contentPadding,
                        viewportWidth: geometry.size.width
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: DateStripDefaults.CellHeight)
        }
    }
}

/// 좁은 기기용 — 칸 폭을 고정하고 가로로 스크롤한다. 선택 칸이 다 보이지 않으면 데려온다.
private struct ScrollingDateStrip: View {
    let cells: [DateStripCell]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let contentPadding: EdgeInsets
    let viewportWidth: CGFloat

    /// 칸마다 보이는 영역(스크롤 뷰 좌표) 안의 자리. 「이미 다 보이는가」를 판정한다.
    @State private var cellFrames: [Int: CGRect] = [:]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                        DateStripCellView(cell: cell, selected: index == selectedIndex) { onSelect(index) }
                            .frame(width: DateStripDefaults.ScrollCellWidth)
                            .id(index)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DateStripViewport)) } action: {
                                cellFrames[index] = $0
                            }
                    }
                }
                .padding(.leading, contentPadding.leading)
                .padding(.trailing, contentPadding.trailing)
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(.named(DateStripViewport))
            // 처음에는 선택 칸을 첫 칸 자리로 연다(원본 `initialFirstVisibleItemIndex`).
            .onAppear {
                guard selectedIndex > 0, cells.indices.contains(selectedIndex) else { return }
                proxy.scrollTo(selectedIndex, anchor: startAnchor)
            }
            // 이미 보이는 칸을 누를 때는 움직이지 않는다 — 누른 칸이 손가락 아래에서 도망가면 안 된다
            .onChange(of: SelectionKey(index: selectedIndex, count: cells.count)) { _, key in
                guard cells.indices.contains(key.index) else { return }
                let fullyVisible = cellFrames[key.index].map { $0.minX >= 0 && $0.maxX <= viewportWidth } ?? false
                if !fullyVisible {
                    withAnimation { proxy.scrollTo(key.index, anchor: startAnchor) }
                }
            }
        }
    }

    /// 칸의 앞 끝을 여백(`contentPadding.leading`) 바로 뒤에 놓는 기준점. 원본 `animateScrollToItem` 은 칸을 시작 여백
    /// 뒤에 놓는다. `scrollTo` 의 기준점은 칸과 보이는 영역의 같은 비율 자리를 맞추므로 여백 ÷ (영역 폭 − 칸 폭)이다.
    private var startAnchor: UnitPoint {
        let room = viewportWidth - DateStripDefaults.ScrollCellWidth
        guard room > 0 else { return .leading }
        return UnitPoint(x: min(max(contentPadding.leading / room, 0), 1), y: 0.5)
    }

    private struct SelectionKey: Equatable {
        let index: Int
        let count: Int
    }
}

private let DateStripViewport = "weekDateStrip.viewport"

private struct DateStripCellView: View {
    let cell: DateStripCell
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        let toneColor: Color = switch cell.tone {
        case .saturday: MoyeotaColor.Primary600
        case .sunday: MoyeotaColor.Danger600
        case .weekday: MoyeotaColor.TextBody
        }
        let dayColor: Color = if selected {
            MoyeotaColor.TextOnDark
        } else if !cell.enabled {
            MoyeotaColor.TextPlaceholder
        } else {
            toneColor
        }
        Button(action: onClick) {
            VStack(spacing: 0) {
                Text(cell.weekday)
                    .moyeotaText(.CaptionMd, color: cell.enabled ? toneColor : MoyeotaColor.TextPlaceholder)
                Spacer().frame(height: 2)
                Text(cell.day)
                    .moyeotaText(.BodyStrong, color: dayColor)
                    .frame(width: DateStripDefaults.SelectionDiameter, height: DateStripDefaults.SelectionDiameter)
                    .background(selected ? MoyeotaColor.Primary500 : Color.clear, in: Circle())
                // 오늘 표시 — 다른 칸에도 같은 자리를 비워 둬서 오늘 칸만 위로 밀려 보이지 않게 한다
                Circle()
                    .fill(cell.isToday ? MoyeotaColor.TextMute : Color.clear)
                    .frame(width: 4, height: 4)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: DateStripDefaults.CellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackStyle())
        .disabled(!cell.enabled)
        // 칸 안의 글자(「토」·「14」)는 따로 읽히지 않고 한 문장으로 읽힌다
        .accessibilityLabel(cell.contentDescription)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
