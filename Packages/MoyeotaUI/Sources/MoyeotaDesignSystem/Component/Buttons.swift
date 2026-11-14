import SwiftUI

/// 머티리얼 잉크 리플 자리의 눌림 표시. 배경이 없는 탭 영역(아이콘 버튼, 하단탭)에 쓴다.
public struct PressFeedbackStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 머티리얼 버튼의 모양: 알약 + 활성/비활성 색 + 눌림 오버레이(상태 레이어 10%).
private struct CtaButtonStyle: ButtonStyle {
    let containerColor: Color
    let contentColor: Color
    let disabledContainerColor: Color
    let disabledContentColor: Color
    var border: Color?
    /// 비활성일 때의 테두리. nil 이면 `border` 그대로다.
    var disabledBorder: Color?

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let content = isEnabled ? contentColor : disabledContentColor
        let resolvedBorder = isEnabled ? border : (disabledBorder ?? border)
        configuration.label
            .foregroundStyle(content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isEnabled ? containerColor : disabledContainerColor, in: Capsule(style: .circular))
            .overlay {
                if configuration.isPressed {
                    Capsule(style: .circular).fill(content.opacity(0.1))
                }
            }
            .overlay {
                if let resolvedBorder {
                    Capsule(style: .circular).strokeBorder(resolvedBorder, lineWidth: 1)
                }
            }
            .contentShape(Capsule(style: .circular))
    }
}

/// 두 CTA 가 공유하는 본체. 색만 다르다.
private struct LoadingCtaButton: View {
    let text: String
    let onClick: () -> Void
    let enabled: Bool
    let loading: Bool
    let containerColor: Color
    var leadingIcon: AnyView?

    var body: some View {
        Button(action: onClick) {
            Group {
                if loading {
                    CircularProgressIndicator(size: 20, strokeWidth: 2)
                } else {
                    HStack(spacing: 0) {
                        if let leadingIcon {
                            leadingIcon
                                .frame(width: 18, height: 18)
                                // 장식이라 VoiceOver 는 글자만 읽는다
                                .accessibilityHidden(true)
                            Spacer().frame(width: 8)
                        }
                        Text(text)
                            .moyeotaText(MoyeotaType.ButtonLg.hangulTrimmed)
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .buttonStyle(
            CtaButtonStyle(
                containerColor: containerColor,
                contentColor: MoyeotaColor.TextOnDark,
                disabledContainerColor: MoyeotaColor.SurfaceDisabled,
                disabledContentColor: MoyeotaColor.TextPlaceholder
            )
        )
        .disabled(!enabled || loading)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
    }
}

/// 주 CTA — **한 화면에 하나**(디자인 문서: 파랑은 화면마다 아껴 쓴다). 필수 조건 미충족 시 enabled=false,
/// 제출 중이면 loading=true (공통 규칙: 중복 제출 차단).
///
/// 비활성 색은 `MoyeotaColor.SurfaceDisabled`/`MoyeotaColor.TextPlaceholder` 다. 예전 값(SurfaceSoft/TextAsh)은
/// 회색 화면 위에서 대비가 1.01:1 이라 버튼 모양이 사라지고 흐린 글자만 떠 있었다(디자인 QA G5).
public struct PrimaryCtaButton: View {
    private let text: String
    private let onClick: () -> Void
    private let enabled: Bool
    private let loading: Bool
    private let leadingIcon: AnyView?

    public init(text: String, onClick: @escaping () -> Void, enabled: Bool = true, loading: Bool = false) {
        self.text = text
        self.onClick = onClick
        self.enabled = enabled
        self.loading = loading
        self.leadingIcon = nil
    }

    /// - Parameter leadingIcon: 글자 앞에 붙는 18 아이콘(23 「채팅으로 물어보기」의 말풍선). 장식이라 VoiceOver 는 글자만 읽는다
    public init<LeadingIcon: View>(
        text: String,
        onClick: @escaping () -> Void,
        enabled: Bool = true,
        loading: Bool = false,
        @ViewBuilder leadingIcon: () -> LeadingIcon
    ) {
        self.text = text
        self.onClick = onClick
        self.enabled = enabled
        self.loading = loading
        self.leadingIcon = AnyView(leadingIcon())
    }

    public var body: some View {
        LoadingCtaButton(
            text: text,
            onClick: onClick,
            enabled: enabled,
            loading: loading,
            containerColor: MoyeotaColor.Primary500,
            leadingIcon: leadingIcon
        )
    }
}

/// 되돌릴 수 없는 파괴적 동작의 주 CTA — 지금 쓰는 곳은 37 회원 탈퇴 하나다.
///
/// `PrimaryCtaButton` 과 모양·크기·중복 제출 차단 규칙이 같고 **색만 Danger** 다. 색을 바꾸는 이유는
/// 장식이 아니라 경고다: 같은 자리의 같은 파란 버튼이면 「저장」·「다음」과 구분되지 않는다.
///
/// 비활성 색은 `PrimaryCtaButton` 과 똑같이 둔다 — 못 누르는 버튼은 위험하지 않으므로
/// 빨간색을 유지하면 "눌리지 않는데 위험해 보이는" 상태가 된다.
///
/// `SafetyButton` 과 혼동하지 말 것. 그쪽은 긴급 신고(도움을 부르는 행동) 전용이고,
/// 이쪽은 사용자가 자기 것을 지우는 행동이다.
public struct DangerCtaButton: View {
    private let text: String
    private let onClick: () -> Void
    private let enabled: Bool
    private let loading: Bool

    public init(text: String, onClick: @escaping () -> Void, enabled: Bool = true, loading: Bool = false) {
        self.text = text
        self.onClick = onClick
        self.enabled = enabled
        self.loading = loading
    }

    public var body: some View {
        LoadingCtaButton(
            text: text,
            onClick: onClick,
            enabled: enabled,
            loading: loading,
            containerColor: MoyeotaColor.Danger500
        )
    }
}

public struct SecondaryButton: View {
    private let text: String
    private let onClick: () -> Void
    private let enabled: Bool

    public init(text: String, onClick: @escaping () -> Void, enabled: Bool = true) {
        self.text = text
        self.onClick = onClick
        self.enabled = enabled
    }

    public var body: some View {
        Button(action: onClick) {
            Text(text)
                .moyeotaText(MoyeotaType.ButtonLg.hangulTrimmed)
                .padding(.horizontal, 24)
        }
        .buttonStyle(
            CtaButtonStyle(
                containerColor: .clear,
                contentColor: MoyeotaColor.InkPrimary,
                disabledContainerColor: .clear,
                // 머티리얼 1.4.0 outlinedButtonColors 의 비활성 글자색: onSurfaceVariant 38%
                // (`OutlinedButtonTokens.DisabledLabelTextColor`, 바이트코드와 원본 스크린샷 #C0C3CC 로 확인)
                disabledContentColor: LightColorScheme.onSurfaceVariant.opacity(0.38),
                // Hairline(1.15:1)은 흰 바탕에서 테두리가 안 보여 글자만 떠 있었다 — 디자인 문서 button-secondary-light 의 ash-light
                border: MoyeotaColor.BorderStrong,
                disabledBorder: MoyeotaColor.Border
            )
        )
        .disabled(!enabled)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
    }
}

/// 옅은 파랑 알약 — **주 CTA 옆에 서는 두 번째 행동**(21 「채팅 열기」 등). 디자인 문서의 button-primary-soft.
///
/// 왜 두 번째 파란 솔리드가 아닌가: 한 화면에 솔리드 파랑이 둘이면 무엇이 주 행동인지 눈이 고르지 못한다.
/// 모양·높이는 `PrimaryCtaButton` 과 같게 둬서 나란히 놓였을 때 "같은 가족"으로 읽히게 한다.
public struct SoftButton: View {
    private let text: String
    private let onClick: () -> Void
    private let enabled: Bool
    private let height: CGFloat

    public init(text: String, onClick: @escaping () -> Void, enabled: Bool = true, height: CGFloat = 52) {
        self.text = text
        self.onClick = onClick
        self.enabled = enabled
        self.height = height
    }

    public var body: some View {
        Button(action: onClick) {
            Text(text)
                .moyeotaText(MoyeotaType.ButtonLg.hangulTrimmed)
                .padding(.horizontal, 24)
        }
        .buttonStyle(
            CtaButtonStyle(
                containerColor: MoyeotaColor.Primary50,
                contentColor: MoyeotaColor.Primary600,
                disabledContainerColor: MoyeotaColor.SurfaceDisabled,
                disabledContentColor: MoyeotaColor.TextPlaceholder
            )
        )
        .disabled(!enabled)
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

/// 바탕 없는 빨간 글자 알약 — 「그만 찾기」·「방 나가기」처럼 **되돌리기 어려운 이탈**(디자인 문서 button-danger,
/// 「요청 취소」). 누르면 늘 확인 다이얼로그가 먼저 뜨는 자리에 쓴다.
///
/// 왜 회색 상자가 아닌가: 예전 회색 r16 상자는 주 CTA(파란 알약)와 모양이 달라 "다른 앱의 버튼"처럼 보였고,
/// 회색은 위험을 말하지 못한다. 바탕을 비워 주 CTA 보다 한 단계 아래로 내리고, 색만 경고로 둔다.
/// 비활성은 `MoyeotaColor.TextPlaceholder` 글자 — 못 누르는 버튼은 위험하지 않다(`DangerCtaButton` 과 같은 방침).
public struct DangerTextButton: View {
    private let text: String
    private let onClick: () -> Void
    private let enabled: Bool

    public init(text: String, onClick: @escaping () -> Void, enabled: Bool = true) {
        self.text = text
        self.onClick = onClick
        self.enabled = enabled
    }

    public var body: some View {
        Button(action: onClick) {
            // 머티리얼 `TextButton` 의 안쪽 여백은 좌우 12 다.
            Text(text)
                .moyeotaText(MoyeotaType.ButtonMd.hangulTrimmed)
                .padding(.horizontal, 12)
        }
        .buttonStyle(
            CtaButtonStyle(
                containerColor: .clear,
                contentColor: MoyeotaColor.Danger500,
                disabledContainerColor: .clear,
                disabledContentColor: MoyeotaColor.TextPlaceholder
            )
        )
        .disabled(!enabled)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }
}

/// 목록 줄 안의 작은 행동(17 탐색 카드의 「합류」). 보이는 높이는 32 지만 **터치 영역은 48** 이다
/// (원본 `minimumInteractiveComponentSize`) — 예전 34 솔리드 파랑 버튼은 손가락에 작고, 줄마다 하나씩 있어
/// 화면에 파란 덩어리가 줄 수만큼 생겼다. 옅은 파랑이라 시트의 단 하나뿐인 솔리드 CTA 를 가리지 않는다.
///
/// 비활성(「마감」)은 바탕 없이 `MoyeotaColor.TextPlaceholder` 글자만 남긴다.
public struct CompactPillButton: View {
    private let text: String
    private let onClick: () -> Void
    private let enabled: Bool

    public init(text: String, onClick: @escaping () -> Void, enabled: Bool = true) {
        self.text = text
        self.onClick = onClick
        self.enabled = enabled
    }

    public var body: some View {
        Button(action: onClick) {
            Text(text)
                .moyeotaText(
                    MoyeotaType.ButtonMd.hangulTrimmed,
                    color: enabled ? MoyeotaColor.Primary600 : MoyeotaColor.TextPlaceholder
                )
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(enabled ? MoyeotaColor.Primary50 : Color.clear, in: MoyeotaShape.Pill)
                .frame(minWidth: 48, minHeight: 48)
                .contentShape(MoyeotaShape.Pill)
        }
        .buttonStyle(PressFeedbackStyle())
        .disabled(!enabled)
    }
}

// 비상 신고 전용 버튼 — Safety 색은 여기 외 사용 금지
public struct SafetyButton: View {
    private let text: String
    private let onClick: () -> Void

    public init(text: String, onClick: @escaping () -> Void) {
        self.text = text
        self.onClick = onClick
    }

    public var body: some View {
        Button(action: onClick) {
            Text(text)
                .moyeotaText(MoyeotaType.ButtonLg.hangulTrimmed)
                .padding(.horizontal, 24)
        }
        .buttonStyle(
            CtaButtonStyle(
                containerColor: MoyeotaColor.Safety500,
                contentColor: MoyeotaColor.TextOnDark,
                disabledContainerColor: MoyeotaColor.Safety500,
                disabledContentColor: MoyeotaColor.TextOnDark
            )
        )
        .frame(maxWidth: .infinity)
        .frame(height: 56)
    }
}

/// 머티리얼 3 `CircularProgressIndicator`(무한 회전형) 자리. 원본의 호 길이·회전 움직임을 옮겼다.
/// 색 기본값은 원본처럼 테마 primary 다 — 그래서 CTA 로딩 스피너도 버튼 글자색이 아니라 파란색이다.
public struct CircularProgressIndicator: View {
    private let size: CGFloat
    private let color: Color
    private let strokeWidth: CGFloat

    public init(size: CGFloat = 40, color: Color = MoyeotaColor.Primary500, strokeWidth: CGFloat = 4) {
        self.size = size
        self.color = color
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            let millis = timeline.date.timeIntervalSinceReferenceDate * 1000
            Canvas { context, canvasSize in
                let arc = indeterminateArc(millis: millis)
                let radius = (min(canvasSize.width, canvasSize.height) - strokeWidth) / 2
                // 사각 끝처리가 시작점 뒤로 두께 절반만큼 나오므로 그만큼 앞으로 민다(원본 drawIndeterminateCircularIndicator).
                // 원본 식의 지름은 실제 크기가 아니라 기본 지름 상수 40dp 다.
                let capOffset = (180 / Double.pi) * Double(strokeWidth / (40 / 2)) / 2
                var path = Path()
                path.addRelativeArc(
                    center: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
                    radius: radius,
                    startAngle: .degrees(arc.start + capOffset),
                    delta: .degrees(max(arc.sweep, 0.1))
                )
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .square))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 시각(ms) → 호의 시작 각도·길이(도). 머티리얼 3 `CircularProgressIndicator` 의 애니메이션 상수.
func indeterminateArc(millis: Double) -> (start: Double, sweep: Double) {
    let rotationDuration = 1332.0
    let rotationsPerCycle = 5.0
    let baseRotationAngle = 286.0
    let jumpRotationAngle = 290.0
    let rotationAngleOffset = 216.0
    let startAngleOffset = -90.0
    let headAndTailDuration = 666.0

    let cycle = rotationDuration * rotationsPerCycle
    // 원본은 정수 애니메이션이라 한 바퀴마다 계단으로 오른다(0…4).
    let currentRotation = floor(millis.truncatingRemainder(dividingBy: cycle) / rotationDuration)
    let baseRotation = millis.truncatingRemainder(dividingBy: rotationDuration) / rotationDuration * baseRotationAngle

    let phase = millis.truncatingRemainder(dividingBy: rotationDuration)
    let head = phase < headAndTailDuration
        ? fastOutSlowIn(phase / headAndTailDuration) * jumpRotationAngle
        : jumpRotationAngle
    let tail = phase < headAndTailDuration
        ? 0
        : fastOutSlowIn((phase - headAndTailDuration) / headAndTailDuration) * jumpRotationAngle

    let offset = startAngleOffset
        + (currentRotation * rotationAngleOffset).truncatingRemainder(dividingBy: 360)
        + baseRotation
    return (start: tail + offset, sweep: abs(head - tail))
}

/// `FastOutSlowInEasing` = cubic-bezier(0.4, 0, 0.2, 1).
func fastOutSlowIn(_ fraction: Double) -> Double {
    let x1 = 0.4, y1 = 0.0, x2 = 0.2, y2 = 1.0
    func bezier(_ a: Double, _ b: Double, _ t: Double) -> Double {
        3 * a * (1 - t) * (1 - t) * t + 3 * b * (1 - t) * t * t + t * t * t
    }
    var low = 0.0, high = 1.0
    for _ in 0..<24 {
        let mid = (low + high) / 2
        if bezier(x1, x2, mid) < fraction {
            low = mid
        } else {
            high = mid
        }
    }
    return bezier(y1, y2, (low + high) / 2)
}
