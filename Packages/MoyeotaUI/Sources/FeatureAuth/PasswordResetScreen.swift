import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 04c · 비밀번호 재설정 [신규, 2026-11]
///
/// 진입: 04a 로그인의 「비밀번호 재설정」 · 04b 아이디 찾기 결과의 「비밀번호 재설정」(아이디를 채워서 온다)
///
/// 두 단계다 (`/api/v1/auth/password-reset/send → verify → confirm`, 백엔드 #331).
/// 1. 아이디 + 휴대폰 번호로 인증번호를 받아 확인한다 → 일회용 재설정 토큰(10분)
/// 2. 새 비밀번호를 두 번 입력해 저장한다 → 04a 로 돌아가 새 비밀번호로 로그인
///
/// **「문자를 보냈어요」라고 말하지 않는다.** 서버는 아이디·번호가 가입 정보와 맞든 틀리든 같은 접수를 주고
/// (계정이 있는지를 흘리지 않으려는 설계다), 문자는 맞을 때만 나간다. 그래서 입력칸을 연 뒤
/// 「일치하면 도착한다」와 「안 오면 아이디·번호를 확인하라」를 같이 말한다 — 그 안내가 없으면
/// 아이디를 잘못 넣은 사람이 오지 않는 문자를 3분 동안 기다린다.
///
/// 재설정 토큰은 화면이 살아 있는 동안 메모리에만 있다 — 저장하지 않고, 화면을 나가면 사라진다.
public struct PasswordResetScreen: View {
    private let verify: PhoneVerifyState
    private let nowMillis: Int64
    private let submitting: Bool
    private let passwordError: String?
    private let confirmError: String?
    private let bannerMessage: String?
    private let onBack: () -> Void
    private let onLoginIdChange: (String) -> Void
    private let onPhoneDigitsChange: (String) -> Void
    private let onRequestCode: (_ phoneDigits: String, _ loginId: String) -> Void
    private let onCodeChange: (String) -> Void
    private let onSubmitCode: () -> Void
    private let onFindId: () -> Void
    private let onPasswordInputChange: () -> Void
    private let onConfirm: (_ loginId: String, _ newPassword: String, _ newPasswordConfirm: String) -> Void

    @State private var loginId: String
    @State private var phoneDigits = ""
    @State private var newPassword = ""
    @State private var newPasswordConfirm = ""
    @State private var passwordVisible = false

    /// - Parameter initialLoginId: 04b 에서 찾은 아이디. 비어 있으면 사용자가 직접 넣는다.
    public init(
        initialLoginId: String = "",
        verify: PhoneVerifyState = PhoneVerifyState(),
        nowMillis: Int64 = 0,
        submitting: Bool = false,
        passwordError: String? = nil,
        confirmError: String? = nil,
        bannerMessage: String? = nil,
        onBack: @escaping () -> Void = {},
        onLoginIdChange: @escaping (String) -> Void = { _ in },
        onPhoneDigitsChange: @escaping (String) -> Void = { _ in },
        onRequestCode: @escaping (_ phoneDigits: String, _ loginId: String) -> Void = { _, _ in },
        onCodeChange: @escaping (String) -> Void = { _ in },
        onSubmitCode: @escaping () -> Void = {},
        onFindId: @escaping () -> Void = {},
        onPasswordInputChange: @escaping () -> Void = {},
        onConfirm: @escaping (_ loginId: String, _ newPassword: String, _ newPasswordConfirm: String) -> Void = { _, _, _ in }
    ) {
        self.verify = verify
        self.nowMillis = nowMillis
        self.submitting = submitting
        self.passwordError = passwordError
        self.confirmError = confirmError
        self.bannerMessage = bannerMessage
        self.onBack = onBack
        self.onLoginIdChange = onLoginIdChange
        self.onPhoneDigitsChange = onPhoneDigitsChange
        self.onRequestCode = onRequestCode
        self.onCodeChange = onCodeChange
        self.onSubmitCode = onSubmitCode
        self.onFindId = onFindId
        self.onPasswordInputChange = onPasswordInputChange
        self.onConfirm = onConfirm
        _loginId = State(initialValue: initialLoginId)
    }

    public var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            MoyeotaTopBar(title: "비밀번호 재설정", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if verify.stage == .verified {
                        newPasswordForm
                    } else {
                        verifyForm
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
        // 인증이 풀리면(토큰 만료로 되돌림) 적어 둔 새 비밀번호를 남기지 않는다.
        .onChange(of: verify.stage) { _, stage in
            if stage != .verified {
                newPassword = ""
                newPasswordConfirm = ""
                passwordVisible = false
            }
        }
    }

    // ── 1단계: 아이디 + 휴대폰 인증 ──

    @ViewBuilder
    private var verifyForm: some View {
        // 형식이 틀린 아이디는 서버가 접수 전에 400 으로 끊는다 — 버튼을 잠가 그 왕복을 없앤다.
        let loginIdReady = AuthPolicy.isValidLoginId(value: loginId)

        Spacer().frame(height: 24)
        Text("비밀번호를 새로 만들어요")
            .moyeotaText(MoyeotaType.DisplayMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
        Spacer().frame(height: 12)
        Text("아이디와 가입한 휴대폰 번호를 확인할게요")
            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)

        Spacer().frame(height: 32)
        MoyeotaTextField(
            value: loginId,
            onValueChange: { new in
                loginId = loginIdInput(raw: new)
                onLoginIdChange(loginId)
            },
            label: "아이디",
            placeholder: "moyeota",
            keyboardOptions: KeyboardOptions(keyboardType: .ascii, imeAction: .next),
            enabled: !verify.verifying
        )
        // 48 터치 링크(디자인 QA G12)라 원본처럼 입력란에 바로 붙이고 아래 간격을 줄인다
        HStack(alignment: .center, spacing: 0) {
            Text("아이디가 기억나지 않아요")
                .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
            Spacer().frame(width: 2, height: 2)
            TextLinkButton(text: "아이디 찾기", onClick: onFindId, style: .ButtonSm)
        }

        Spacer().frame(height: 8)
        MoyeotaTextField(
            value: phoneDigits,
            onValueChange: { new in
                phoneDigits = digitsOnly(new, maxDigits: 11)
                onPhoneDigitsChange(phoneDigits)
            },
            label: "휴대폰 번호",
            placeholder: "010-1234-5678",
            errorText: verify.phoneMessage,
            helperText: verify.stage == .idle ? "가입할 때 쓴 번호를 입력해 주세요" : nil,
            keyboardOptions: KeyboardOptions(keyboardType: .phone),
            visualTransformation: PhoneNumberTransformation.visualTransformation,
            enabled: !verify.verifying
        )

        if verify.stage == .codeSent {
            Spacer().frame(height: 16)
            NoticeBanner(
                kind: .info,
                text: "아이디와 번호가 가입 정보와 일치하면 인증번호가 문자로 도착해요. 1~2분이 지나도 오지 않으면 아이디와 번호를 다시 확인해 주세요"
            )
        }

        PhoneVerificationBlock(
            state: verify,
            nowMillis: nowMillis,
            // 아이디가 비었거나 형식이 틀리면 번호가 멀쩡해도 요청을 열지 않는다
            phoneDigits: loginIdReady ? phoneDigits : "",
            onRequestCode: { onRequestCode(phoneDigits, loginId) },
            onCodeChange: onCodeChange,
            onSubmitCode: onSubmitCode,
            onPhoneEditRequested: {},
            onGoToLogin: {}
        )
    }

    // ── 2단계: 새 비밀번호 ──

    @ViewBuilder
    private var newPasswordForm: some View {
        // 서버 규칙(`PasswordPolicy`)과 같은 검사를 먼저 한다 — 최종 판정은 서버다.
        let localPasswordError: String? = !newPassword.isEmpty && !AuthPolicy.isValidPassword(value: newPassword)
            ? "영문·숫자·특수문자를 모두 넣어 8자 이상으로 만들어 주세요" : nil
        let localConfirmError: String? = !newPasswordConfirm.isEmpty && newPasswordConfirm != newPassword
            ? "새 비밀번호와 같게 입력해 주세요" : nil
        let canSubmit = !submitting &&
            AuthPolicy.isValidPassword(value: newPassword) &&
            newPasswordConfirm == newPassword

        Spacer().frame(height: 24)
        Text("새 비밀번호를 정해 주세요")
            .moyeotaText(MoyeotaType.DisplayMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
        Spacer().frame(height: 12)
        Text("휴대폰 인증이 끝났어요. 10분 안에 새 비밀번호를 저장해 주세요")
            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)

        Spacer().frame(height: 32)
        MoyeotaTextField(
            value: newPassword,
            onValueChange: { new in
                newPassword = takeUtf16(new, AuthPolicy.PASSWORD_MAX_LENGTH)
                onPasswordInputChange()
            },
            label: "새 비밀번호",
            placeholder: "영문·숫자·특수문자 조합 8자 이상",
            // 앱 판정(고칠 곳이 더 구체적이다)을 서버 응답 문구보다 앞세운다
            errorText: localPasswordError ?? passwordError,
            keyboardOptions: KeyboardOptions(keyboardType: .password, imeAction: .next),
            visualTransformation: passwordVisible ? .None : PasswordVisualTransformation(),
            enabled: !submitting
        ) {
            // 04a 와 같은 48 터치 토글(디자인 QA G12). 글자 끝은 필드 안쪽 여백에 맞춘다
            TextLinkButton(
                text: passwordVisible ? "숨기기" : "보기",
                onClick: { passwordVisible.toggle() },
                color: MoyeotaColor.TextMute,
                style: .ButtonSm
            )
            .offset(x: 8)
        }

        Spacer().frame(height: 20)
        MoyeotaTextField(
            value: newPasswordConfirm,
            onValueChange: { new in
                newPasswordConfirm = takeUtf16(new, AuthPolicy.PASSWORD_MAX_LENGTH)
                onPasswordInputChange()
            },
            label: "새 비밀번호 확인",
            placeholder: "한 번 더 입력해 주세요",
            errorText: localConfirmError ?? confirmError,
            keyboardOptions: KeyboardOptions(keyboardType: .password, imeAction: .done),
            visualTransformation: passwordVisible ? .None : PasswordVisualTransformation(),
            enabled: !submitting
        )

        if let bannerMessage {
            Spacer().frame(height: 16)
            NoticeBanner(kind: .error, text: bannerMessage)
        }

        Spacer().frame(height: 32)
        PrimaryCtaButton(
            text: "비밀번호 변경",
            onClick: { onConfirm(loginId, newPassword, newPasswordConfirm) },
            enabled: canSubmit,
            loading: submitting
        )
        Spacer().frame(height: 14)
        Text("변경하면 다른 기기에서는 로그아웃돼요")
            .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
            .frame(maxWidth: .infinity)
    }
}

// 04c 비밀번호 재설정 — 재설정 세 API 의 진입점. 성공하면 아이디를 실어 onCompleted 로 04a 에 넘긴다.
public struct PasswordResetRoute: View {
    private let initialLoginId: String
    private let onBack: () -> Void
    private let onFindId: () -> Void
    private let onCompleted: (_ loginId: String) -> Void

    @HostedViewModel private var codeViewModel: RecoveryCodeViewModel
    @HostedViewModel private var confirmViewModel: PasswordResetConfirmViewModel

    /// 저장에 쓴 아이디 — 성공 뒤 04a 의 아이디 칸을 채워 준다.
    @State private var submittedLoginId = ""

    public init(
        repository: any AuthRepository,
        initialLoginId: String = "",
        onBack: @escaping () -> Void = {},
        onFindId: @escaping () -> Void = {},
        onCompleted: @escaping (_ loginId: String) -> Void = { _ in }
    ) {
        self.initialLoginId = initialLoginId
        self.onBack = onBack
        self.onFindId = onFindId
        self.onCompleted = onCompleted
        _codeViewModel = HostedViewModel(
            wrappedValue: RecoveryCodeViewModel(purpose: .resetPassword, repository: repository)
        )
        _confirmViewModel = HostedViewModel(wrappedValue: PasswordResetConfirmViewModel(repository: repository))
    }

    public var body: some View {
        let confirm = confirmViewModel.uiState
        PasswordResetScreen(
            initialLoginId: initialLoginId,
            verify: codeViewModel.state,
            nowMillis: codeViewModel.nowMillis,
            submitting: confirm.submitting,
            passwordError: confirm.passwordError,
            confirmError: confirm.confirmError,
            bannerMessage: confirm.bannerMessage,
            onBack: onBack,
            onLoginIdChange: { codeViewModel.onLoginIdChanged(loginId: $0) },
            onPhoneDigitsChange: { codeViewModel.onPhoneDigitsChanged(phoneDigits: $0) },
            onRequestCode: { phoneDigits, loginId in
                codeViewModel.requestCode(phoneDigits: phoneDigits, loginId: loginId)
            },
            onCodeChange: { codeViewModel.onCodeChanged(raw: $0) },
            onSubmitCode: { codeViewModel.verify() },
            onFindId: onFindId,
            onPasswordInputChange: { confirmViewModel.onInputChanged() },
            onConfirm: { loginId, newPassword, newPasswordConfirm in
                submittedLoginId = loginId
                confirmViewModel.confirm(
                    resetToken: codeViewModel.state.token,
                    newPassword: newPassword,
                    newPasswordConfirm: newPasswordConfirm
                )
            }
        )
        .task(id: confirm.completed) {
            if confirm.completed { onCompleted(submittedLoginId) }
        }
        // 토큰이 무효다(만료·이미 사용) — 새 비밀번호를 고쳐도 풀리지 않으니 인증 단계로 되돌린다.
        .task(id: confirm.reverifyMessage) {
            if let message = confirm.reverifyMessage {
                codeViewModel.restart(message: message)
                confirmViewModel.onReverifyHandled()
            }
        }
    }
}
