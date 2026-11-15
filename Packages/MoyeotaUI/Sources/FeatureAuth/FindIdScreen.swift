import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 04b · 아이디 찾기 [신규, 2026-11]
///
/// 진입: 04a 로그인의 「아이디 찾기」
///
/// 가입한 휴대폰 번호로 문자 인증을 통과하면 **아이디 전체**를 보여 준다
/// (`POST /api/v1/auth/find-id/send` → `find-id/verify`, 백엔드 #314).
///
/// 한 화면이 두 모습을 갖는다 — 인증 전에는 번호·인증번호 입력, 인증 뒤에는 결과.
/// 결과를 별 화면으로 쌓지 않는 이유: 뒤로 가면 이미 소진된 인증번호 입력칸이 다시 보이고,
/// 아이디는 인증을 통과한 이 화면 안에서만 보여야 한다(스택에 남겨 두고 돌아올 값이 아니다).
///
/// 가입되지 않은 번호는 서버가 **발송 단계에서** 알려 준다(404 `USER114`) — 입력칸을 열지 않고 가입으로 보낸다.
public struct FindIdScreen: View {
    private let verify: PhoneVerifyState
    private let nowMillis: Int64
    private let notRegistered: Bool
    private let onBack: () -> Void
    private let onPhoneDigitsChange: (String) -> Void
    private let onRequestCode: (String) -> Void
    private let onCodeChange: (String) -> Void
    private let onSubmitCode: () -> Void
    private let onSignUp: () -> Void
    private let onLogin: (_ loginId: String) -> Void
    private let onResetPassword: (_ loginId: String) -> Void

    @State private var phoneDigits = ""

    public init(
        verify: PhoneVerifyState = PhoneVerifyState(),
        nowMillis: Int64 = 0,
        notRegistered: Bool = false,
        onBack: @escaping () -> Void = {},
        onPhoneDigitsChange: @escaping (String) -> Void = { _ in },
        onRequestCode: @escaping (String) -> Void = { _ in },
        onCodeChange: @escaping (String) -> Void = { _ in },
        onSubmitCode: @escaping () -> Void = {},
        onSignUp: @escaping () -> Void = {},
        onLogin: @escaping (_ loginId: String) -> Void = { _ in },
        onResetPassword: @escaping (_ loginId: String) -> Void = { _ in }
    ) {
        self.verify = verify
        self.nowMillis = nowMillis
        self.notRegistered = notRegistered
        self.onBack = onBack
        self.onPhoneDigitsChange = onPhoneDigitsChange
        self.onRequestCode = onRequestCode
        self.onCodeChange = onCodeChange
        self.onSubmitCode = onSubmitCode
        self.onSignUp = onSignUp
        self.onLogin = onLogin
        self.onResetPassword = onResetPassword
    }

    public var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            MoyeotaTopBar(title: "아이디 찾기", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if verify.stage == .verified {
                        found(loginId: verify.token)
                    } else {
                        form
                    }
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            NavigationBarSpacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
    }

    @ViewBuilder
    private var form: some View {
        Spacer().frame(height: 24)
        Text("가입한 휴대폰 번호로\n아이디를 찾아요")
            .moyeotaText(MoyeotaType.DisplayMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
        Spacer().frame(height: 12)
        Text("문자로 받은 인증번호를 확인하면 아이디를 알려 드려요")
            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)

        Spacer().frame(height: 32)
        MoyeotaTextField(
            value: phoneDigits,
            onValueChange: { new in
                phoneDigits = digitsOnly(new, maxDigits: 11)
                onPhoneDigitsChange(phoneDigits)
            },
            label: "휴대폰 번호",
            placeholder: "010-1234-5678",
            errorText: verify.phoneMessage,
            keyboardOptions: KeyboardOptions(keyboardType: .phone),
            visualTransformation: PhoneNumberTransformation.visualTransformation,
            // 문자를 보낸 번호를 고치면 인증번호가 무효가 된다 — 확인하는 동안만 잠근다
            enabled: !verify.verifying
        )

        if notRegistered {
            // 문구는 번호 입력란 아래(errorText)에 이미 떠 있다 — 여기서는 갈 길만 준다.
            // 다듬기(디자인 QA G12) 뒤 원본처럼 48 터치 링크 — 글자 시작을 입력란 왼쪽 선에 맞춘다
            TextLinkButton(text: "가입하러 가기", onClick: onSignUp, style: .ButtonSm)
                .offset(x: -8)
        }

        PhoneVerificationBlock(
            state: verify,
            nowMillis: nowMillis,
            phoneDigits: phoneDigits,
            onRequestCode: { onRequestCode(phoneDigits) },
            onCodeChange: onCodeChange,
            onSubmitCode: onSubmitCode,
            // 아래 둘은 가입 화면 전용 갈래다 — 이 화면에서는 그 상태(인증 완료 표시·이미 가입)에 닿지 않는다.
            onPhoneEditRequested: {},
            onGoToLogin: {}
        )
    }

    @ViewBuilder
    private func found(loginId: String) -> some View {
        Spacer().frame(height: 24)
        Text("아이디를 찾았어요")
            .moyeotaText(MoyeotaType.DisplayMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
        Spacer().frame(height: 12)
        Text("가입할 때 만든 아이디예요")
            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)

        Spacer().frame(height: 32)
        VStack(alignment: .leading, spacing: 8) {
            Text("아이디")
                .moyeotaText(MoyeotaType.ButtonSm.hangulTrimmed, color: MoyeotaColor.TextMute)
            Text(loginId)
                .moyeotaText(MoyeotaType.HeadingXl, color: MoyeotaColor.InkPrimary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoyeotaColor.SurfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .circular))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .circular).strokeBorder(MoyeotaColor.Hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)

        Spacer().frame(height: 32)
        PrimaryCtaButton(text: "이 아이디로 로그인", onClick: { onLogin(loginId) })

        Spacer().frame(height: 4)
        HStack(alignment: .center, spacing: 0) {
            Text("비밀번호가 기억나지 않아요")
                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
            Spacer().frame(width: 4, height: 4)
            TextLinkButton(text: "비밀번호 재설정", onClick: { onResetPassword(loginId) })
        }
        .frame(maxWidth: .infinity)
    }
}

// 04b 아이디 찾기 — 문자 인증 두 API 의 진입점. 결과(아이디)는 화면 안에서 보여 주고, 다음 갈 곳만 밖으로 넘긴다.
public struct FindIdRoute: View {
    private let onBack: () -> Void
    private let onSignUp: () -> Void
    private let onLogin: (_ loginId: String) -> Void
    private let onResetPassword: (_ loginId: String) -> Void

    @HostedViewModel private var viewModel: RecoveryCodeViewModel

    public init(
        repository: any AuthRepository,
        onBack: @escaping () -> Void = {},
        onSignUp: @escaping () -> Void = {},
        onLogin: @escaping (_ loginId: String) -> Void = { _ in },
        onResetPassword: @escaping (_ loginId: String) -> Void = { _ in }
    ) {
        self.onBack = onBack
        self.onSignUp = onSignUp
        self.onLogin = onLogin
        self.onResetPassword = onResetPassword
        _viewModel = HostedViewModel(wrappedValue: RecoveryCodeViewModel(purpose: .findLoginId, repository: repository))
    }

    public var body: some View {
        FindIdScreen(
            verify: viewModel.state,
            nowMillis: viewModel.nowMillis,
            notRegistered: viewModel.requestIssue == .notRegistered,
            onBack: onBack,
            onPhoneDigitsChange: { viewModel.onPhoneDigitsChanged(phoneDigits: $0) },
            onRequestCode: { viewModel.requestCode(phoneDigits: $0) },
            onCodeChange: { viewModel.onCodeChanged(raw: $0) },
            onSubmitCode: { viewModel.verify() },
            onSignUp: onSignUp,
            onLogin: onLogin,
            onResetPassword: onResetPassword
        )
    }
}
