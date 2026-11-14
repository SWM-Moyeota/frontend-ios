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

public struct SocialLoginRoute: View {
    let repository: any AuthRepository
    let onLoggedIn: () -> Void
    let onSignup: (SocialSignup) -> Void
    let onEmailStart: () -> Void
    let onLogin: () -> Void
    @Environment(\.nativeSocialAuthentication) private var native
    @State private var busy = false
    @State private var message: String?
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
        LoginScreen(
            onEmailStart: onEmailStart, onLogin: onLogin,
            onGoogle: { authenticate(.google) }, onApple: { authenticate(.apple) }
        )
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
                if provider == .google {
                    result = try await social.loginGoogle(idToken: native.google())
                } else {
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
