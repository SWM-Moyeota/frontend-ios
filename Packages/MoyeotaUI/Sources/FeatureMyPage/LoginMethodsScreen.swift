import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 연결용 인증번호 재발송 잠금. 서버는 가입용·연결용 문자의 쿨다운(1분)을 함께 세므로
/// 이 화면에서 처음 누른 발송도 429 `USER202` 일 수 있다 — 성공과 그 실패 양쪽에서 잠근다.
struct LinkCodeCooldown: Equatable {
    private(set) var resendAllowedAt: Date?

    /// 발송 성공 — 서버 쿨다운만큼 잠근다.
    mutating func onSent(now: Date) {
        resendAllowedAt = now.addingTimeInterval(TimeInterval(AuthPolicy.SMS_RESEND_COOLDOWN_SECONDS))
    }

    /// `smsCooldown` 일 때만 잠근다. 서버가 남은 초(`Retry-After`)를 주면 그 값을 쓰고, 없으면 최대치로
    /// 보수적으로 잡는다 — 짧게 잡으면 또 눌러 또 429 를 받는다(가입 화면 `PhoneVerifyState` 와 같은 기준).
    mutating func onFailure(_ error: any Error, now: Date) {
        guard let failure = error as? AuthException, failure.error == .smsCooldown else { return }
        if let seconds = failure.retryAfterSeconds {
            resendAllowedAt = now.addingTimeInterval(TimeInterval(seconds))
        } else {
            let fallback = now.addingTimeInterval(TimeInterval(AuthPolicy.SMS_RESEND_COOLDOWN_SECONDS))
            resendAllowedAt = max(resendAllowedAt ?? fallback, fallback)
        }
    }

    /// 남은 초(올림). 잠겨 있지 않으면 0.
    func remainingSeconds(now: Date) -> Int {
        guard let resendAllowedAt else { return 0 }
        return max(0, Int(resendAllowedAt.timeIntervalSince(now).rounded(.up)))
    }
}

/// 발송 버튼 문구. 잠긴 동안에는 남은 초를 붙인다 — `smsCooldown` 안내 문구가 「버튼의 남은 시간」을 가리킨다.
func linkCodeSendTitle(sent: Bool, remainingSeconds: Int) -> String {
    let title = sent ? "인증번호 다시 받기" : "등록된 휴대폰으로 인증번호 받기"
    return remainingSeconds > 0 ? "\(title) (\(remainingSeconds)초)" : title
}

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
    @State private var cooldown = LinkCodeCooldown()
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
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            let remaining = cooldown.remainingSeconds(now: timeline.date)
                            Button(linkCodeSendTitle(sent: sent, remainingSeconds: remaining)) {
                                run {
                                    try await repository.sendLinkCode()
                                    cooldown.onSent(now: Date())
                                    sent = true
                                    verificationToken = nil
                                    code = ""
                                }
                            }
                            .disabled(remaining > 0)
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
                cooldown.onFailure(error, now: Date())
                message = error.authUserMessage()
            }
        }
    }
}
