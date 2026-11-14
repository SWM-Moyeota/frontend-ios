import MoyeotaDesignSystem
import SwiftUI

// 원본 `core/designsystem/component/Dialogs.kt`. 디자인시스템이 아니라 여기 있는 이유: 원본 대화상자는 뒤로가기를 받아 닫히는데,
// iOS 에서 그 자리(`moyeotaBackHandler` — 시스템 스와이프 뒤로가기를 막고 닫기로 돌린다)가 이 모듈에 있다.
// 디자인시스템은 이 모듈을 import 할 수 없다. 기능 모듈은 둘 다 import 하므로 부르는 쪽에서는 차이가 없다.

/// 앱의 **단 하나뿐인 확인 다이얼로그** (디자인 QA G11, 2026-11).
///
/// 예전엔 제목이 17 Bold·16 SemiBold 로 갈리고, 채팅방 「나가기」는 손으로 그린 다이얼로그에 **파란** 확인
/// 버튼을 달았다 — 되돌릴 수 없는 이탈에 주 행동 색을 쓴 것이다(디자인 문서: 파괴적 UI 에 primary 금지).
///
/// - 제목 `MoyeotaType.HeadingMd`, 본문 `MoyeotaType.BodySm` `MoyeotaColor.TextBody`, 흰 바탕, 모서리 20
/// - 확인 버튼은 `destructive` 면 빨강, 아니면 진한 파랑. 취소는 `MoyeotaColor.TextMute`
/// - 바깥을 누르거나 뒤로 가기(스와이프)를 하면 `onDismiss` — 취소와 같다
///
/// `onConfirm` 을 부르기 **전에** 다이얼로그를 닫는 것은 호출부의 몫이다(상태를 호출부가 갖는다).
///
/// 원본 `AlertDialog` 는 제 창을 띄우지만 iOS 에는 그 자리가 없어 **화면 전체를 덮는 오버레이**다. 호출부는 화면 뿌리의
/// `.overlay { if 보임 { MoyeotaConfirmDialog(…) } }` 에 둔다. 치수는 머티리얼 3 `AlertDialog` 값이다: 안쪽 여백 24,
/// 제목 아래 16, 본문 아래 24, 버튼 사이 8, 폭 최소 280 · 최대 320(원본 렌더에서 잰 대화상자 창 폭), 자리는 시스템 바를 뺀
/// 영역의 가운데. 버튼은 원본처럼 **취소 → 확인** 순서로 오른쪽에 붙는다.
///
/// - Parameters:
///   - body: 없으면 제목만 묻는다
///   - dismissText: 없으면 취소 버튼을 그리지 않는다(바깥 누름으로만 닫힌다)
public struct MoyeotaConfirmDialog: View {
    private let title: String
    private let confirmText: String
    private let onConfirm: () -> Void
    private let onDismiss: () -> Void
    private let bodyText: String?
    private let dismissText: String?
    private let destructive: Bool

    public init(
        title: String,
        confirmText: String,
        onConfirm: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        body: String? = nil,
        dismissText: String? = "취소",
        destructive: Bool = false
    ) {
        self.title = title
        self.confirmText = confirmText
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        self.bodyText = body
        self.dismissText = dismissText
        self.destructive = destructive
    }

    public var body: some View {
        ZStack {
            // 안드로이드 대화상자 창의 기본 어둡기(0.6)다. 앱의 `Scrim` 토큰(40%)은 시트용이라 쓰지 않는다.
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            // 원본 대화상자 창은 시스템 바를 뺀 영역의 가운데에 놓인다. 이 오버레이는 화면 전체라 두 바의 높이를 직접 뺀다.
            VStack(spacing: 0) {
                StatusBarSpacer()
                card.frame(maxHeight: .infinity)
                NavigationBarSpacer()
            }
        }
        .moyeotaBackHandler { onDismiss() }
    }

    private var card: some View {
        ConfirmDialogContentLayout(minWidth: ConfirmDialogMinWidth - 48, maxWidth: ConfirmDialogContentMaxWidth) {
            Text(title)
                .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 16)
            if let bodyText {
                ConfirmDialogBodyText(text: bodyText)
                    .padding(.bottom, 24)
            }
            HStack(spacing: 8) {
                if let dismissText {
                    ConfirmDialogTextButton(text: dismissText, color: MoyeotaColor.TextMute, onClick: onDismiss)
                }
                ConfirmDialogTextButton(
                    text: confirmText,
                    color: destructive ? MoyeotaColor.Danger500 : MoyeotaColor.Primary600,
                    onClick: onConfirm
                )
            }
        }
        .padding(24)
        .background(MoyeotaColor.SurfaceCanvas, in: MoyeotaShape.Dialog)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
    }
}

/// 대화상자 폭의 하한(머티리얼 3 `DialogMinWidth`).
private let ConfirmDialogMinWidth: CGFloat = 280

/// 대화상자 내용의 최대 폭(320 − 좌우 여백 24 둘).
private let ConfirmDialogContentMaxWidth: CGFloat = 320 - 48

/// 접힐 수 있는 본문. **어절 단위로** 꺾고(그냥 `Text` — iOS 한글 줄바꿈은 어절 우선이다), 접히면 폭 상한을 다 쓴다.
///
/// 예전엔 원본의 글자 단위 줄바꿈을 따라 `softWrappedLines` 로 줄을 직접 나눠 「없/어요」·「1/명은」처럼 어절 한가운데서
/// 꺾였다(QA M5). 원본도 어절 단위(`KoreanBodyText`)로 바꿨다. 접혔는지는 여전히 `softWrappedLines` 로 잰다 —
/// 한 줄에 다 들어가는지는 꺾는 단위와 상관없이 같다.
private struct ConfirmDialogBodyText: View {
    let text: String

    var body: some View {
        let style = MoyeotaType.BodySm.hangulTrimmed
        let wrapped = style.softWrappedLines(text, width: ConfirmDialogContentMaxWidth).wrapped
        Text(text)
            .moyeotaText(style, color: MoyeotaColor.TextBody)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: wrapped ? ConfirmDialogContentMaxWidth : nil, alignment: .leading)
    }
}

/// 머티리얼 `TextButton` 자리 — 글자 좌우 12·위아래 8, 최소 58×40, 터치 영역 높이 48. 눌리면 알약 안을 글자색 10% 로 덮는다.
private struct ConfirmDialogTextButton: View {
    let text: String
    let color: Color
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Text(text)
                .moyeotaText(MoyeotaType.ButtonMd.hangulTrimmed, color: color)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 58, minHeight: 40)
        }
        .buttonStyle(ConfirmDialogTextButtonStyle(color: color))
    }
}

private struct ConfirmDialogTextButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    Capsule(style: .circular).fill(color.opacity(0.1))
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
    }
}

/// 제목·본문은 왼쪽, 마지막(버튼 줄)은 오른쪽에 붙인다.
///
/// 폭이 **가장 넓은 내용**으로 정해지는 것이 원본과 같은 점이다 — `frame(maxWidth: .infinity)` 로 오른쪽에
/// 붙이면 대화상자가 화면 폭까지 늘어난다. 폭은 줄바꿈 전 너비로 정한다(접힌 뒤의 너비로 정하면 문구마다 폭이 달라진다).
private struct ConfirmDialogContentLayout: Layout {
    let minWidth: CGFloat
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = childProposal(proposal)
        let widest = subviews.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: nil)).width }.max() ?? 0
        let width = min(max(widest, minWidth), limit.width ?? maxWidth)
        let children = ProposedViewSize(width: width, height: nil)
        return CGSize(
            width: width,
            height: subviews.map { $0.sizeThatFits(children).height }.reduce(0, +)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let limit = childProposal(ProposedViewSize(width: bounds.width, height: nil))
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(limit)
            let isLast = index == subviews.count - 1
            let x = isLast ? bounds.maxX - size.width : bounds.minX
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: limit)
            y += size.height
        }
    }

    private func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? maxWidth, maxWidth), height: nil)
    }
}
