import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 소셜 로그인 실패 문구. Apple 경로의 `socialRejected`(`USER401`)에만 이메일 공유 안내를 덧붙인다.
///
/// 서버는 이메일을 공유하지 않은 **신규** Apple 계정을 `USER401` 로 거절한다. 일반 문구만 보이면
/// 같은 실패를 반복하게 된다. 다만 같은 코드에 토큰 위조·만료도 들어 있어 원인을 단정하지 않는다.
/// Google 경로와 그 밖의 오류는 공통 문구 그대로다.
func socialLoginFailureMessage(error: any Error, provider: SocialProvider) -> String {
    let message = error.authUserMessage()
    guard provider == .apple, (error as? AuthException)?.error == .socialRejected else { return message }
    return "\(message). Apple 로그인에서 이메일 공유가 필요할 수 있어요"
}

/// 소셜 로그인은 Google 과 Apple 이다. Apple 은 App Store 심사 지침 4.8 때문에 **iOS 에만** 있다 —
/// 외부 로그인(Google)을 주는 앱은 이름·이메일만 받는 로그인(Sign in with Apple)도 같이 줘야 한다(2026-11-15 오너 결정).
public struct SocialLoginRoute: View {
    let repository: any AuthRepository
    let onLoggedIn: () -> Void
    let onSignup: (SocialSignup) -> Void
    let onEmailStart: () -> Void
    let onLogin: () -> Void
    public init(
        repository: any AuthRepository, onSignup: @escaping (SocialSignup) -> Void, onLoggedIn: @escaping () -> Void,
        onEmailStart: @escaping () -> Void, onLogin: @escaping () -> Void
    ) {
        self.onLoggedIn = onLoggedIn
        self.repository = repository
        self.onSignup = onSignup
        self.onEmailStart = onEmailStart
        self.onLogin = onLogin
    }
    public var body: some View {
        SocialLoginHost(repository: repository, onSignup: onSignup, onLoggedIn: onLoggedIn) { start in
            LoginScreen(
                onEmailStart: onEmailStart,
                onLogin: onLogin,
                onGoogle: { start(.google) },
                onApple: { start(.apple) }
            )
        }
    }
}

/// 「Google로 계속하기」·「Apple로 계속하기」 한 번의 동작과 진행 표시. 시작 화면(04)과 로그인 화면(04a)이 같은 동작을 쓴다.
/// 가입한 회원이면 `onLoggedIn`, 처음이면 `onSignup`. 계정 선택을 취소하면 안내 없이 그대로 남는다.
struct SocialLoginHost<Content: View>: View {
    let repository: any AuthRepository
    let onSignup: (SocialSignup) -> Void
    let onLoggedIn: () -> Void
    @ViewBuilder let content: (_ start: @escaping (SocialProvider) -> Void) -> Content
    @Environment(\.nativeSocialAuthentication) private var native
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        content({ authenticate($0) })
        .disabled(busy)
        .overlay { if busy { ProgressView("로그인 확인 중").padding().background(.regularMaterial) } }
        .alert("로그인 안내", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("확인") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
    private func authenticate(_ provider: SocialProvider) {
        guard !busy else { return }
        guard let native, let social = repository as? any SocialAuthRepository else {
            message = "로그인 기능을 사용할 수 없어요. 앱을 다시 열어 주세요"
            return
        }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let result: SocialLoginResult
                switch provider {
                case .google:
                    result = try await social.loginGoogle(idToken: native.google())
                case .apple:
                    // 서버가 준 일회성 nonce 를 그대로 Apple 요청에 싣는다 — 서버가 identityToken 의 nonce 와 대조한다
                    let challenge = try await social.appleChallenge(linking: false)
                    result = try await social.loginApple(
                        credential: native.apple(challenge.nonce), challengeToken: challenge.challengeToken)
                }
                switch result {
                case .signupRequired(let signup): onSignup(signup)
                case .loggedIn: onLoggedIn()
                }
            } catch is CancellationError {} catch { message = socialLoginFailureMessage(error: error, provider: provider) }
        }
    }
}
