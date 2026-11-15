import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 소셜 로그인은 Google 만 제공한다(2026-11-15 제품 결정).
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
        GoogleLoginHost(repository: repository, onSignup: onSignup, onLoggedIn: onLoggedIn) { start in
            LoginScreen(onEmailStart: onEmailStart, onLogin: onLogin, onGoogle: start)
        }
    }
}

/// 「Google로 계속하기」 한 번의 동작과 진행 표시. 시작 화면(04)과 로그인 화면(04a)이 같은 동작을 쓴다.
/// 가입한 회원이면 `onLoggedIn`, 처음이면 `onSignup`. 계정 선택을 취소하면 안내 없이 그대로 남는다.
struct GoogleLoginHost<Content: View>: View {
    let repository: any AuthRepository
    let onSignup: (SocialSignup) -> Void
    let onLoggedIn: () -> Void
    @ViewBuilder let content: (_ start: @escaping () -> Void) -> Content
    @Environment(\.nativeSocialAuthentication) private var native
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        content({ authenticate() })
        .disabled(busy)
        .overlay { if busy { ProgressView("로그인 확인 중").padding().background(.regularMaterial) } }
        .alert("로그인 안내", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("확인") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
    private func authenticate() {
        guard !busy else { return }
        guard let native, let social = repository as? any SocialAuthRepository else {
            message = "로그인 기능을 사용할 수 없어요. 앱을 다시 열어 주세요"
            return
        }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                switch try await social.loginGoogle(idToken: native.google()) {
                case .signupRequired(let signup): onSignup(signup)
                case .loggedIn: onLoggedIn()
                }
            } catch is CancellationError {} catch { message = error.authUserMessage() }
        }
    }
}
