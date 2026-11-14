import Foundation
import MoyeotaDesignSystem
import PresentationCore
import SwiftUI

// 07 · 인증 코드 [S03]
//
// ⚠️ 현재 어떤 그래프에도 등록되어 있지 않다 (06 과 같은 이유 — 인증은 마이페이지로 이동 예정).
//
// (원래 배선) 진입: 06 인증 메일 보내기 / 뒤로 → 06 / 「인증하기」 → 09 본인 인증
// 「코드 다시 받기」 → 화면 유지, 타이머 4:31 리셋 / 「메일 주소 다시 입력하기」 → 06
private let CODE_LENGTH = 6
private let RESEND_COOLDOWN_SECONDS = 4 * 60 + 31 // 재발송 쿨다운 4:31
private let CODE_EXPIRY_SECONDS = 10 * 60 // 코드 유효시간 10분

public struct EmailCodeScreen: View {
    private let email: String
    private let onBack: () -> Void
    private let onVerified: (_ code: String) -> Void
    private let onEditEmail: () -> Void
    private let onResendCode: () -> Void

    @State private var code = ""
    @State private var errorText: String?
    @State private var submitting = false
    @State private var resendRemaining = RESEND_COOLDOWN_SECONDS
    @State private var expiryRemaining = CODE_EXPIRY_SECONDS
    @State private var timerKey = 0

    public init(
        email: String = "moyeota@pusan.ac.kr",
        onBack: @escaping () -> Void = {},
        onVerified: @escaping (_ code: String) -> Void = { _ in },
        onEditEmail: @escaping () -> Void = {},
        onResendCode: @escaping () -> Void = {}
    ) {
        self.email = email
        self.onBack = onBack
        self.onVerified = onVerified
        self.onEditEmail = onEditEmail
        self.onResendCode = onResendCode
    }

    private func resend() {
        code = ""
        errorText = nil
        submitting = false
        resendRemaining = RESEND_COOLDOWN_SECONDS
        expiryRemaining = CODE_EXPIRY_SECONDS
        timerKey += 1
        onResendCode()
    }

    public var body: some View {
        let semiBoldBodySm = MoyeotaType.BodySm.copy(fontWeight: .semibold)
        VStack(spacing: 0) {
            StatusBarSpacer()
            MoyeotaTopBar(title: "", onBack: onBack) {
                Text("1 / 5")
                    .moyeotaText(.BodySm, color: MoyeotaColor.TextMute)
            }
            EmailCodeProgressBar(progress: 1.0 / 5.0)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 24)
                    Text("메일로 보낸 6자리를\n입력해 주세요")
                        .moyeotaText(.DisplayMd, color: MoyeotaColor.InkPrimary)
                    Spacer().frame(height: 12)
                    Text(verbatim: "\(email) 로 보냈어요")
                        .moyeotaText(.BodySm, color: MoyeotaColor.TextMute)
                    Spacer().frame(height: 32)

                    EmailCodeInput(
                        code: code,
                        isError: errorText != nil,
                        enabled: !submitting && expiryRemaining > 0,
                        onCodeChange: { new in
                            // 유효값 검증: 숫자 6자리만 입력, 문자·공백 무시
                            code = digitsOnly(new, maxDigits: CODE_LENGTH)
                            errorText = nil
                        }
                    )

                    if let errorText {
                        Spacer().frame(height: 8)
                        Button(action: resend) {
                            Text(errorText)
                                .moyeotaText(semiBoldBodySm, color: MoyeotaColor.Danger500)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressFeedbackStyle())
                    }

                    Spacer().frame(height: 8)
                    HStack(alignment: .center, spacing: 0) {
                        Text(verbatim: "남은 시간 \(formatSeconds(total: resendRemaining))")
                            // 초가 바뀔 때마다 글자 폭이 흔들리지 않게 숫자 폭을 고정한다
                            .moyeotaText(semiBoldBodySm.tabularNums(), color: MoyeotaColor.Waiting600)
                        Spacer(minLength: 0)
                        // 글자 오른쪽 끝을 화면 여백에 맞춘다(TextLinkButton 의 안쪽 8 만큼 바깥으로)
                        TextLinkButton(
                            text: "코드 다시 받기",
                            onClick: resend,
                            style: semiBoldBodySm
                        )
                        .offset(x: 8)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer().frame(height: 16)

                    helpCard
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                PrimaryCtaButton(
                    text: "인증하기",
                    onClick: {
                        submitting = true
                        onVerified(code)
                    },
                    enabled: code.utf16.count == CODE_LENGTH,
                    loading: submitting
                )
                Spacer().frame(height: 12)
                Text("코드는 10분 뒤에 만료돼요")
                    .moyeotaText(.CaptionMd, color: MoyeotaColor.TextMute)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            NavigationBarSpacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
        .task(id: timerKey) {
            while resendRemaining > 0 || expiryRemaining > 0 {
                do {
                    try await Task.sleep(for: .milliseconds(1_000))
                } catch {
                    return
                }
                if resendRemaining > 0 { resendRemaining -= 1 }
                if expiryRemaining > 0 {
                    expiryRemaining -= 1
                    if expiryRemaining == 0 {
                        // 만료 → 「코드가 만료됐어요 · 다시 받기」, 입력값 초기화
                        code = ""
                        errorText = "코드가 만료됐어요 · 다시 받기"
                    }
                }
            }
        }
        // 유효값 검증: 6자리 입력 완료 시 자동 제출
        .task(id: code) {
            if code.utf16.count == CODE_LENGTH && !submitting {
                submitting = true
                onVerified(code)
            }
        }
        // 원본 `remember` 는 화면이 컴포지션에서 빠지면 사라진다. `@State` 는 스택에 있는 동안 남으므로 직접 비운다.
        // 카운트다운도 함께 처음 값으로 돌린다 — 가려진 동안 태스크가 멈춰, 두면 지난 시간이 빠지지 않은 값으로 이어 간다.
        // `timerKey` 만 두는 이유: 돌아오면 `.task` 가 어차피 새로 돌고, 키를 바꾸면 가려진 동안 태스크가 시작될 수 있다.
        .onDisappear {
            code = ""
            errorText = nil
            submitting = false
            resendRemaining = RESEND_COOLDOWN_SECONDS
            expiryRemaining = CODE_EXPIRY_SECONDS
        }
    }

    // 흰 화면 위라 그림자 대신 Border 선으로 묶음을 나눈다(디자인 QA G4)
    private var helpCard: some View {
        let shape = MoyeotaShape.Card
        return VStack(spacing: 0) {
            // 스팸함 안내 — 동작 없음
            EmailCodeHelpRow(
                title: "스팸함을 확인해 주세요",
                subtitle: "메일이 스팸으로 분류될 수 있어요",
                onClick: nil
            )
            HorizontalDivider(color: MoyeotaColor.Hairline)
                .padding(.horizontal, 16)
            // 「메일 주소 다시 입력하기」 → 06
            EmailCodeHelpRow(
                title: "메일 주소 다시 입력하기",
                subtitle: "\(email) 이 맞나요?",
                onClick: onEditEmail
            )
        }
        .frame(maxWidth: .infinity)
        // 마지막 행의 눌림 표시가 둥근 모서리 밖으로 나가지 않게 자른다(원본 `clip`)
        .clipShape(shape)
        .overlay { shape.strokeBorder(MoyeotaColor.Border, lineWidth: 1) }
    }
}

extension EmailCodeScreen {
    /// 테스트가 만료된 상태를 만드는 입구. 실제 시계로 10분을 기다릴 수 없다.
    func seeded(expiryRemaining: Int) -> Self {
        var copy = self
        copy._expiryRemaining = State(initialValue: expiryRemaining)
        return copy
    }
}

// 와이어프레임의 박스형 코드 입력 — BasicTextField + 박스 렌더링
private struct EmailCodeInput: View {
    let code: String
    let isError: Bool
    let enabled: Bool
    let onCodeChange: (String) -> Void

    @State private var focus = FocusRequester()

    var body: some View {
        let digits = Array(code.unicodeScalars)
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<CODE_LENGTH, id: \.self) { index in
                    let filled = index < digits.count
                    let active = index == digits.count && enabled
                    let shape = MoyeotaShape.Card
                    // 칸 하나하나가 입력칸이다 — 그림자 대신 MoyeotaTextField 와 같은 테두리 규칙(쉬는 칸 BorderStrong)
                    let borderColor: Color = if isError {
                        MoyeotaColor.Danger500
                    } else if active {
                        MoyeotaColor.Primary500
                    } else {
                        MoyeotaColor.BorderStrong
                    }
                    ZStack {
                        if filled {
                            Text(verbatim: String(digits[index]))
                                .moyeotaText(.DisplayMd, color: MoyeotaColor.InkPrimary)
                        } else if active {
                            MoyeotaShape.Pill
                                .fill(MoyeotaColor.Primary500)
                                .frame(width: 2, height: 28)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(MoyeotaColor.SurfaceCanvas, in: shape)
                    .overlay { shape.strokeBorder(borderColor, lineWidth: isError || active ? 1.5 : 1) }
                }
            }
            // 실제 입력 필드는 투명하게 겹쳐 키 입력만 받는다. 투명한 뷰는 터치를 받지 못해 위에 탭 영역을 얹는다.
            BasicTextField(
                value: code,
                onValueChange: onCodeChange,
                keyboardOptions: KeyboardOptions(keyboardType: .numberPassword),
                singleLine: true,
                enabled: enabled,
                focusRequester: focus
            )
            .opacity(0)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { focus.requestFocus() }
                // 투명도 0 인 입력 칸은 VoiceOver 에 닿지 않는다 — 이 탭 영역이 입력 칸을 대신해 읽히고 포커스를 부른다.
                .accessibilityElement()
                .accessibilityLabel("인증 코드")
                .accessibilityValue(code)
                .accessibilityAction { focus.requestFocus() }
                .disabled(!enabled)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EmailCodeHelpRow: View {
    let title: String
    let subtitle: String
    let onClick: (() -> Void)?

    var body: some View {
        if let onClick {
            Button(action: onClick) { content }
                .buttonStyle(PressOverlayStyle(shape: Rectangle()))
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 0) {
            EmailCodeMailIcon()
            Spacer().frame(width: 12, height: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .moyeotaText(.BodyStrong, color: MoyeotaColor.InkPrimary)
                Spacer().frame(height: 4)
                Text(subtitle)
                    .moyeotaText(.BodySm, color: MoyeotaColor.TextMute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 누를 수 있는 줄에만 꺾쇠를 둔다 — 안내뿐인 줄(스팸함)에 꺾쇠가 있으면 눌러도 아무 일 없는 버튼이 된다
            if onClick != nil { ChevronIcon() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

private struct EmailCodeProgressBar: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                MoyeotaShape.Small.fill(MoyeotaColor.Hairline)
                MoyeotaShape.Small
                    .fill(MoyeotaColor.Primary500)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 16)
    }
}

private struct EmailCodeMailIcon: View {
    var body: some View {
        Canvas { context, size in
            let stroke = IconStrokeWidth * (MoyeotaIconSize.Md / MoyeotaIconSize.Lg)
            let color = MoyeotaColor.TextMute
            let top = size.height * 0.18
            let bottom = size.height * 0.82
            context.stroke(
                Path(
                    roundedRect: CGRect(x: 0, y: top, width: size.width, height: bottom - top),
                    cornerRadius: 2,
                    style: .circular
                ),
                with: .color(color),
                style: StrokeStyle(lineWidth: stroke)
            )
            let line = StrokeStyle(lineWidth: stroke, lineCap: .round)
            var left = Path()
            left.move(to: CGPoint(x: size.width * 0.08, y: top + stroke))
            left.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.55))
            context.stroke(left, with: .color(color), style: line)
            var right = Path()
            right.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.55))
            right.addLine(to: CGPoint(x: size.width * 0.92, y: top + stroke))
            context.stroke(right, with: .color(color), style: line)
        }
        .frame(width: MoyeotaIconSize.Md, height: MoyeotaIconSize.Md)
    }
}

func formatSeconds(total: Int) -> String {
    String(format: "%d:%02d", total / 60, total % 60)
}
