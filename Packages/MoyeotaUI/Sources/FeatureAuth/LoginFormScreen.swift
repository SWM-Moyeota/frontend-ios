import MoyeotaDesignSystem
import MoyeotaDomain
import SwiftUI

/// 아이디 입력값을 받는 규칙. 아이디는 영소문자·숫자·_ 만 가능하다 (`AuthPolicy.LOGIN_ID_PATTERN`).
/// 대문자를 눌러도 조용히 소문자로 받아 "규칙에 맞는데 왜 안 되지" 를 없앤다.
func loginIdInput(raw: String) -> String {
    var kept = String.UnicodeScalarView()
    kept.append(contentsOf: raw.unicodeScalars.filter { !$0.isKotlinWhitespace })
    return String(kept).lowercased()
}

/// 04a · 아이디로 로그인 [신규]
///
/// 진입: 04 시작 화면의 「이미 계정이 있어요 · 로그인」 · 세션 만료 · 로그아웃 직후
///
/// 백엔드에 소셜 로그인이 없어 04 에도 카카오 버튼은 없다.
/// 실제 로그인 자격증명(loginId/password)은 이 화면에서만 받는다.
///
/// 입력 값은 다른 인증 화면들과 같은 방식으로 화면이 직접 들고 있는다
/// — 뷰모델은 제출 결과(진행 중 · 에러 · 성공)만 관리한다.
public struct LoginFormScreen: View {
    private let onBack: () -> Void
    private let onSubmit: (_ loginId: String, _ password: String) -> Void
    private let onSignUp: () -> Void
    private let onSocialLogin: (() -> Void)?
    private let onFindId: () -> Void
    private let onResetPassword: () -> Void
    private let prefillLoginId: String?
    private let submitting: Bool
    private let errorMessage: String?
    private let noticeMessage: String?

    @State private var loginId = ""
    @State private var password = ""
    @State private var passwordVisible = false

    /// - Parameter errorMessage: 로그인 실패 사유 (LOGIN_FAILED 등) — 필드 아래 인라인 표시
    /// - Parameter noticeMessage: 세션 만료처럼 "왜 이 화면으로 돌아왔는지" 알려야 할 때의 안내 문구
    /// - Parameter prefillLoginId: 04b 에서 찾았거나 04c 에서 비밀번호를 바꾼 아이디 — 돌아왔을 때 아이디 칸을 채운다
    public init(
        onBack: @escaping () -> Void = {},
        onSubmit: @escaping (_ loginId: String, _ password: String) -> Void = { _, _ in },
        onSignUp: @escaping () -> Void = {},
        onSocialLogin: (() -> Void)? = nil,
        onFindId: @escaping () -> Void = {},
        onResetPassword: @escaping () -> Void = {},
        prefillLoginId: String? = nil,
        submitting: Bool = false,
        errorMessage: String? = nil,
        noticeMessage: String? = nil
    ) {
        self.onBack = onBack
        self.onSubmit = onSubmit
        self.onSignUp = onSignUp
        self.onSocialLogin = onSocialLogin
        self.onFindId = onFindId
        self.onResetPassword = onResetPassword
        self.prefillLoginId = prefillLoginId
        self.submitting = submitting
        self.errorMessage = errorMessage
        self.noticeMessage = noticeMessage
    }

    public var body: some View {
        // 서버 왕복 전에 거를 수 있는 것만 막는다 — 최종 판정은 서버 몫이라
        // 형식 오류를 필드 에러로 단정하지 않고 CTA 활성 조건으로만 쓴다.
        let canSubmit = !loginId.isBlank && !password.isBlank && !submitting

        VStack(spacing: 0) {
            StatusBarSpacer()
            MoyeotaTopBar(title: "로그인", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 24)
                    Text("다시 만나 반가워요")
                        .moyeotaText(MoyeotaType.DisplayMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    Spacer().frame(height: 10)
                    Text("가입할 때 만든 아이디로 로그인해요")
                        .moyeotaText(MoyeotaType.BodySm.copy(fontSize: 14).hangulTrimmed, color: MoyeotaColor.TextMute)

                    if let noticeMessage {
                        Spacer().frame(height: 20)
                        NoticeBanner(kind: .info, text: noticeMessage)
                    }

                    Spacer().frame(height: 28)
                    MoyeotaTextField(
                        value: loginId,
                        onValueChange: { new in loginId = loginIdInput(raw: new) },
                        label: "아이디",
                        placeholder: "moyeota",
                        keyboardOptions: KeyboardOptions(keyboardType: .ascii, imeAction: .next),
                        enabled: !submitting
                    )

                    Spacer().frame(height: 20)
                    MoyeotaTextField(
                        value: password,
                        onValueChange: { password = $0 },
                        label: "비밀번호",
                        placeholder: "비밀번호를 입력해 주세요",
                        keyboardOptions: KeyboardOptions(keyboardType: .password, imeAction: .done),
                        visualTransformation: passwordVisible ? .None : PasswordVisualTransformation(),
                        enabled: !submitting
                    ) {
                        Button {
                            passwordVisible.toggle()
                        } label: {
                            Text(passwordVisible ? "숨기기" : "보기")
                                .moyeotaText(
                                    MoyeotaType.CaptionMd.copy(fontWeight: .bold).hangulTrimmed,
                                    color: MoyeotaColor.TextMute
                                )
                        }
                        .buttonStyle(NoIndicationButtonStyle())
                    }

                    // 실패 사유는 화면을 갈아엎지 않고 입력 바로 아래에 남긴다 — 고칠 곳이 위에 있기 때문
                    if let errorMessage {
                        Spacer().frame(height: 16)
                        NoticeBanner(kind: .error, text: errorMessage)
                    }

                    Spacer().frame(height: 28)
                    PrimaryCtaButton(
                        text: "로그인",
                        onClick: { onSubmit(loginId.trim(), password) },
                        enabled: canSubmit,
                        loading: submitting
                    )

                    if let onSocialLogin {
                        Button("Google · Apple로 로그인", action: onSocialLogin).padding(.top, 18)
                    }
                    // 로그인이 막힌 사람이 찾는 자리다 — 버튼 바로 아래, 가입 유도보다 위에 둔다.
                    // 이 줄은 iOS 가 먼저 붙였고 원본이 따라왔다(백엔드 #314·#331, Android frontend #100).
                    Spacer().frame(height: 18)
                    HStack(alignment: .center, spacing: 0) {
                        recoveryLink("아이디 찾기", action: onFindId)
                        Rectangle()
                            .fill(MoyeotaColor.Hairline)
                            .frame(width: 1, height: 12)
                            .padding(.horizontal, 14)
                        recoveryLink("비밀번호 재설정", action: onResetPassword)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer().frame(height: 18)
                    HStack(alignment: .center, spacing: 0) {
                        Text("아직 계정이 없어요")
                            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                        Spacer().frame(width: 12, height: 12)
                        Button(action: onSignUp) {
                            Text("가입하기")
                                .moyeotaText(
                                    MoyeotaType.BodySm.copy(fontWeight: .bold).hangulTrimmed,
                                    color: MoyeotaColor.Primary500
                                )
                        }
                        .buttonStyle(NoIndicationButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    Spacer().frame(height: 28)
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
        .background(MoyeotaColor.SurfaceSoft)
        // 원본 `remember` 는 화면이 컴포지션에서 빠지면 사라진다. `@State` 는 스택에 있는 동안 남으므로 직접 비운다.
        .onDisappear {
            loginId = ""
            password = ""
            passwordVisible = false
        }
        // 04b·04c 에서 돌아올 때마다 다시 채운다 — 위의 비우기가 화면을 가릴 때 아이디도 지우기 때문이다.
        .onAppear {
            if let prefillLoginId, !prefillLoginId.isEmpty { loginId = prefillLoginId }
        }
    }

    private func recoveryLink(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .moyeotaText(MoyeotaType.BodySm.copy(fontWeight: .medium).hangulTrimmed, color: MoyeotaColor.TextMute)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoIndicationButtonStyle())
        .disabled(submitting)
    }
}

extension LoginFormScreen {
    /// 테스트가 「보기」를 켠 상태를 만드는 입구. 창에 올린 화면이라도 코드로는 SwiftUI 버튼을 누를 수 없다.
    func seeded(passwordVisible: Bool) -> Self {
        var copy = self
        copy._passwordVisible = State(initialValue: passwordVisible)
        return copy
    }
}
