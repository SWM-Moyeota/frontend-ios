import SwiftUI

/// 앱 전체가 함께 쓰는 **그린 아이콘 한 벌** (디자인 QA G10, 2026-11).
///
/// 이 앱은 아이콘 라이브러리 의존성을 두지 않는다(`BackArrowIcon`·하단탭과 같다). 그래서 화면마다
/// `ChevronRightIcon`·`CheckIcon`·`SearchIcon` 을 따로 그렸고, 크기(16·18)와 선 굵기(1.8·2)가 조금씩 달라
/// 나란히 놓이면 "다른 세트"로 보였다. 또 `⌄ ⌃ ＋ › → ₩ 📍` 같은 **글자를 아이콘 대신** 쓴 곳이 있었다 —
/// 글꼴마다 모양이 달라지고 색·크기를 토큰으로 맞출 수 없다(no-emoji-icons).
///
/// ### 규칙
/// - 모든 아이콘은 **24 격자**에 그리고 선 굵기는 `IconStrokeWidth` 1.75(디자인 문서). 20·16 으로 줄이면
///   선도 같은 비율로 준다 — 작은 아이콘만 굵어 보이지 않게
/// - 크기는 `MoyeotaIconSize` 셋만 쓴다
/// - VoiceOver 이름은 **감싸는 버튼**이 준다. 아이콘 자체는 장식이다
///
/// 원본 주석은 iOS 에서 같은 이름의 SF Symbol 을 쓰라고 하지만, 원본이 Canvas 로 그린 아이콘은 `Canvas` 로 옮긴다
/// (`docs/PORTING.md` 4절) — 같은 좌표를 그대로 그려 두 플랫폼의 모양·선 굵기가 같다. SF Symbol 은 선 끝·굵기 단계가
/// 달라 `BackArrowIcon`·하단탭과 또 "다른 세트"가 된다.
public enum MoyeotaIconSize {
    public static let Lg: CGFloat = 24
    public static let Md: CGFloat = 20
    public static let Sm: CGFloat = 16
}

/// 24 기준 선 굵기 — 아이콘 크기에 비례해 준다
public let IconStrokeWidth: CGFloat = 1.75

public enum ChevronDirection: Sendable {
    case left, right, up, down
}

/// 꺾쇠 — 「다음 화면으로」(오른쪽)·「펼치기/접기」(위·아래)
public struct ChevronIcon: View {
    private let direction: ChevronDirection
    private let size: CGFloat
    private let tint: Color

    public init(
        direction: ChevronDirection = .right,
        size: CGFloat = MoyeotaIconSize.Sm,
        tint: Color = MoyeotaColor.TextPlaceholder
    ) {
        self.direction = direction
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let points: [(CGFloat, CGFloat)] = switch direction {
        case .right: [(9, 6), (15, 12), (9, 18)]
        case .left: [(15, 6), (9, 12), (15, 18)]
        case .up: [(6, 15), (12, 9), (18, 15)]
        case .down: [(6, 9), (12, 15), (18, 9)]
        }
        let tint = tint
        return GridIcon(size: size) { context, u, stroke in
            context.stroke(gridPolyline(points, u), with: .color(tint), style: stroke)
        }
    }
}

/// 체크 표시 — 완료·확인된 사실
public struct CheckIcon: View {
    private let size: CGFloat
    private let tint: Color

    public init(size: CGFloat = MoyeotaIconSize.Sm, tint: Color = MoyeotaColor.TextMute) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let tint = tint
        return GridIcon(size: size) { context, u, stroke in
            context.stroke(gridPolyline([(5, 12.5), (10, 17.5), (19, 7)], u), with: .color(tint), style: stroke)
        }
    }
}

/// 별 — 즐겨찾기. `filled` 면 채운다
public struct StarIcon: View {
    private let filled: Bool
    private let size: CGFloat
    private let tint: Color

    public init(filled: Bool = false, size: CGFloat = MoyeotaIconSize.Md, tint: Color = MoyeotaColor.TextPlaceholder) {
        self.filled = filled
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let filled = filled
        let tint = tint
        return GridIcon(size: size) { context, u, stroke in
            var path = Path()
            let cx = 12 * u
            let cy = 12.6 * u
            let outer = 9.5 * u
            let inner = 4.2 * u
            for i in 0..<10 {
                let r = i % 2 == 0 ? outer : inner
                let angle = (-90 + Double(i) * 36) * .pi / 180
                let point = CGPoint(x: cx + r * CGFloat(cos(angle)), y: cy + r * CGFloat(sin(angle)))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            if filled { context.fill(path, with: .color(tint)) }
            // 빈 별은 외곽선만, 채운 별도 외곽선을 둘러 모서리를 둥글게
            context.stroke(path, with: .color(tint), style: stroke)
        }
    }
}

/// 돋보기 — 검색
public struct SearchIcon: View {
    private let size: CGFloat
    private let tint: Color

    public init(size: CGFloat = MoyeotaIconSize.Lg, tint: Color = MoyeotaColor.TextBody) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let tint = tint
        return GridIcon(size: size) { context, u, stroke in
            context.stroke(gridCircle(radius: 6.5 * u, center: CGPoint(x: 11 * u, y: 11 * u)), with: .color(tint), style: stroke)
            context.stroke(gridPolyline([(15.8, 15.8), (20, 20)], u), with: .color(tint), style: stroke)
        }
    }
}

/// 엑스 — 닫기·지우기
public struct CloseIcon: View {
    private let size: CGFloat
    private let tint: Color

    public init(size: CGFloat = MoyeotaIconSize.Lg, tint: Color = MoyeotaColor.TextBody) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let tint = tint
        return GridIcon(size: size) { context, u, stroke in
            context.stroke(gridPolyline([(6, 6), (18, 18)], u), with: .color(tint), style: stroke)
            context.stroke(gridPolyline([(18, 6), (6, 18)], u), with: .color(tint), style: stroke)
        }
    }
}

/// 시계 방향 화살표 — 새로고침
public struct RefreshIcon: View {
    private let size: CGFloat
    private let tint: Color

    public init(size: CGFloat = MoyeotaIconSize.Lg, tint: Color = MoyeotaColor.TextBody) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let tint = tint
        return GridIcon(size: size) { context, u, stroke in
            // 3시 → 아래 → 9시 → 12시로 도는 원호(270°), 이어서 오른쪽 위로 올라가 화살촉에 닿는다.
            // y 가 아래로 커지는 좌표계라 양수 각도가 시계 방향이다(원본 drawArc 와 같다).
            var arc = Path()
            arc.addRelativeArc(center: CGPoint(x: 12 * u, y: 12 * u), radius: 9 * u, startAngle: .degrees(0), delta: .degrees(270))
            context.stroke(arc, with: .color(tint), style: stroke)
            var tail = Path()
            tail.move(to: CGPoint(x: 12 * u, y: 3 * u))
            tail.addCurve(
                to: CGPoint(x: 18.7 * u, y: 5.7 * u),
                control1: CGPoint(x: 14.5 * u, y: 3 * u),
                control2: CGPoint(x: 16.9 * u, y: 4 * u)
            )
            tail.addLine(to: CGPoint(x: 21 * u, y: 8 * u))
            context.stroke(tail, with: .color(tint), style: stroke)
            context.stroke(gridPolyline([(21, 3), (21, 8), (16, 8)], u), with: .color(tint), style: stroke)
        }
    }
}

/// 오른쪽 위 화살표 — **앱 밖으로 나가는** 링크(약관·문의). 앱 안 이동은 `ChevronIcon`
public struct ExternalLinkIcon: View {
    private let size: CGFloat
    private let tint: Color

    public init(size: CGFloat = MoyeotaIconSize.Sm, tint: Color = MoyeotaColor.TextPlaceholder) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let tint = tint
        return GridIcon(size: size) { context, u, stroke in
            context.stroke(gridPolyline([(7, 17), (17, 7)], u), with: .color(tint), style: stroke)
            context.stroke(gridPolyline([(8, 7), (17, 7), (17, 16)], u), with: .color(tint), style: stroke)
        }
    }
}

/// 세로 점 셋 — 더보기 메뉴
public struct MoreVerticalIcon: View {
    private let size: CGFloat
    private let tint: Color

    public init(size: CGFloat = MoyeotaIconSize.Lg, tint: Color = MoyeotaColor.TextBody) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let tint = tint
        return GridIcon(size: size) { context, u, _ in
            for y: CGFloat in [5, 12, 19] {
                context.fill(gridCircle(radius: 1.6 * u, center: CGPoint(x: 12 * u, y: y * u)), with: .color(tint))
            }
        }
    }
}

/// 말풍선 — 채팅. 하단탭 채팅 아이콘과 같은 모양이다
public struct ChatBubbleIcon: View {
    private let size: CGFloat
    private let tint: Color

    public init(size: CGFloat = MoyeotaIconSize.Lg, tint: Color = MoyeotaColor.TextBody) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let tint = tint
        return Canvas { context, canvasSize in
            drawChatIcon(context, canvasSize, tint, iconStroke(canvasSize.width / 24))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// ─── 그리기 도구 ──────────────────────────────────────────────────────────────

/// 24 격자 단위 `u` 와 크기에 비례한 선을 넘겨 그린다
private struct GridIcon: View {
    let size: CGFloat
    let draw: (GraphicsContext, CGFloat, StrokeStyle) -> Void

    var body: some View {
        Canvas { context, canvasSize in
            let u = canvasSize.width / 24
            draw(context, u, iconStroke(u))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 크기에 비례한 둥근 선 — 24 에서 `IconStrokeWidth`
func iconStroke(_ u: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: IconStrokeWidth * u, lineCap: .round, lineJoin: .round)
}

private func gridPolyline(_ points: [(CGFloat, CGFloat)], _ u: CGFloat) -> Path {
    var path = Path()
    for (index, point) in points.enumerated() {
        let cgPoint = CGPoint(x: point.0 * u, y: point.1 * u)
        if index == 0 {
            path.move(to: cgPoint)
        } else {
            path.addLine(to: cgPoint)
        }
    }
    return path
}

private func gridCircle(radius: CGFloat, center: CGPoint) -> Path {
    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}
