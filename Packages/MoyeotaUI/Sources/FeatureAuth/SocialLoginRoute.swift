import MoyeotaDomain
import PresentationCore
import SwiftUI

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
            } catch is CancellationError {} catch { message = error.authUserMessage() }
        }
    }
}
