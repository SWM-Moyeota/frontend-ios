import MoyeotaDomain
import PresentationCore
import SwiftUI

public struct LoginMethodsScreen: View {
    let repository: any SocialAuthRepository
    @Environment(\.nativeSocialAuthentication) private var native
    @Environment(\.dismiss) private var dismiss
    @State private var methods: LoginMethods?
    @State private var code = ""
    @State private var sent = false
    @State private var verificationToken: String?
    @State private var verifiedAt: Date?
    @State private var busy = false
    @State private var message: String?
    public init(repository: any SocialAuthRepository) { self.repository = repository }
    public var body: some View {
        NavigationStack {
            Form {
                if let methods {
                    Section("현재 로그인 수단") {
                        if methods.hasPassword { Text("아이디 · 비밀번호") }
                        ForEach(methods.methods, id: \.provider) { method in
                            Text("\(label(method.provider)) · \(method.status == "ACTIVE" ? "연결됨" : "재인증 필요")")
                        }
                    }
                    Section("로그인 수단 추가") {
                        Text("계정에 등록된 휴대폰으로 본인 확인 후 연결해요. 다른 계정의 기록은 합쳐지지 않아요.")
                        Button(sent ? "인증번호 다시 받기" : "등록된 휴대폰으로 인증번호 받기") {
                            run {
                                try await repository.sendLinkCode()
                                sent = true
                                verificationToken = nil
                                code = ""
                            }
                        }
                        if sent && verificationToken == nil {
                            TextField("문자 인증번호 6자리", text: $code).keyboardType(.numberPad)
                            Button("인증번호 확인") {
                                run {
                                    verificationToken = try await repository.verifyLinkCode(code)
                                    verifiedAt = Date()
                                    code = ""
                                }
                            }.disabled(code.count != 6)
                        }
                        if verificationToken != nil {
                            ForEach(SocialProvider.allCases, id: \.self) { provider in
                                if !methods.methods.contains(where: { $0.provider == provider && $0.status == "ACTIVE" }
                                ) {
                                    Button("\(label(provider)) 연결") { connect(provider) }
                                }
                            }
                        }
                    }
                } else {
                    Button("로그인 수단 다시 불러오기") { refresh() }
                }
                if busy { ProgressView() }
                if let message { Text(message).foregroundStyle(.red) }
            }
            .disabled(busy)
            .navigationTitle("로그인 수단")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("새로고침") { refresh() }.disabled(busy) }
            }
        }
        .task { refresh() }
    }
    private func label(_ provider: SocialProvider) -> String { provider == .google ? "Google" : "Apple" }
    private func refresh() { run { methods = try await repository.loginMethods() } }
    private func connect(_ provider: SocialProvider) {
        guard let native, let token = verificationToken, let verifiedAt else { return }
        guard Date().timeIntervalSince(verifiedAt) < 300 else {
            verificationToken = nil
            message = "인증 시간이 지났어요. 문자를 다시 받아 주세요"
            return
        }
        run {
            if provider == .google {
                try await repository.linkGoogle(idToken: native.google(), verificationToken: token)
            } else {
                let challenge = try await repository.appleChallenge(linking: true)
                try await repository.linkApple(
                    credential: native.apple(challenge.nonce), challengeToken: challenge.challengeToken,
                    verificationToken: token)
            }
            verificationToken = nil
            sent = false
            methods = try await repository.loginMethods()
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        message = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch is CancellationError {} catch {
                if (error as? AuthException)?.error == .socialVerificationExpired {
                    verificationToken = nil
                    sent = false
                }
                message = error.authUserMessage()
            }
        }
    }
}
