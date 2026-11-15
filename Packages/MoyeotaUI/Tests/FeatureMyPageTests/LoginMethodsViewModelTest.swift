@testable import FeatureMyPage
import Foundation
import MoyeotaDomain
import Testing

// 로그인 수단 관리 — 원본 `LoginMethodsViewModel`(Android #103)과 같은 흐름인지 본다:
// 목록 조회 → 등록된 휴대폰 문자 인증 → 5분 안에 구글 계정 연결.

private struct Unrelated: Error {}

private func methods(google: String? = nil, apple: String? = nil, hasPassword: Bool = true) -> LoginMethods {
    let items = [google.map { #"{"provider":"GOOGLE","status":"\#($0)"}"# }, apple.map { #"{"provider":"APPLE","status":"\#($0)"}"# }]
    let list = "[" + items.compactMap { $0 }.joined(separator: ",") + "]"
    let json = #"{"hasPassword":\#(hasPassword),"methods":\#(list)}"#
    return try! JSONDecoder().decode(LoginMethods.self, from: Data(json.utf8))
}

private final class FakeSocialRepository: SocialAuthRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _current = methods()
    private var _linked: [(idToken: String, verificationToken: String)] = []
    var sendFailure: (any Error)?
    var linkFailure: (any Error)?
    private var _appleLinks: [(nonce: String?, challengeToken: String, verificationToken: String)] = []
    var appleLinks: [(nonce: String?, challengeToken: String, verificationToken: String)] { lock.withLock { _appleLinks } }

    var linked: [(idToken: String, verificationToken: String)] { lock.withLock { _linked } }

    func loginGoogle(idToken: String) async throws -> SocialLoginResult { throw Unrelated() }
    func registerSocial(_ registration: SocialRegistration) async throws { throw Unrelated() }
    func loginMethods() async throws -> LoginMethods { lock.withLock { _current } }
    func sendLinkCode() async throws { if let sendFailure { throw sendFailure } }
    func verifyLinkCode(_ code: String) async throws -> String { "proof-\(code)" }
    func linkGoogle(idToken: String, verificationToken: String) async throws {
        if let linkFailure { throw linkFailure }
        lock.withLock {
            _linked.append((idToken, verificationToken))
            _current = methods(google: "ACTIVE")
        }
    }
    func deleteSocialAccount() async throws { throw Unrelated() }
    func appleChallenge(linking: Bool) async throws -> AppleChallenge {
        try JSONDecoder().decode(
            AppleChallenge.self,
            from: Data(#"{"challengeToken":"challenge-1","nonce":"nonce-1","expiresInSeconds":300}"#.utf8)
        )
    }
    func loginApple(credential: AppleCredential, challengeToken: String) async throws -> SocialLoginResult { throw Unrelated() }
    func linkApple(credential: AppleCredential, challengeToken: String, verificationToken: String) async throws {
        lock.withLock {
            _appleLinks.append((credential.name, challengeToken, verificationToken))
            _current = methods(apple: "ACTIVE")
        }
    }
}

/// 테스트가 움직이는 시계
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

@MainActor
@Suite struct LoginMethodsViewModelTest {
    private let repository = FakeSocialRepository()
    private let clock = Clock()

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func loaded() async -> LoginMethodsViewModel {
        let clock = self.clock
        let viewModel = LoginMethodsViewModel(repository: repository, now: { clock.now })
        viewModel.refresh()
        #expect(await eventually { !viewModel.loading && viewModel.methods != nil })
        return viewModel
    }

    @Test("인증번호를 보내면 입력칸이 열리고 1분 동안 다시 보내지 못한다")
    func sendOpensCodeAndLocks() async {
        let viewModel = await loaded()

        viewModel.sendCode()

        #expect(await eventually { viewModel.codeSent && !viewModel.busy })
        #expect(viewModel.notice == "등록된 휴대폰으로 인증번호를 보냈어요")
        #expect(viewModel.cooldown.remainingSeconds(now: clock.now) == AuthPolicy.SMS_RESEND_COOLDOWN_SECONDS)
    }

    @Test("가입 직후처럼 첫 발송이 쿨다운(429)이면 서버가 준 시간만큼 잠근다")
    func cooldownFailureLocks() async {
        repository.sendFailure = AuthException(error: .smsCooldown, retryAfterSeconds: 23)
        let viewModel = await loaded()

        viewModel.sendCode()

        #expect(await eventually { viewModel.error != nil && !viewModel.busy })
        #expect(viewModel.cooldown.remainingSeconds(now: clock.now) == 23)
        #expect(!viewModel.codeSent)
    }

    @Test("하루 한도는 이 화면 말투로 알린다")
    func dailyLimitMessage() async {
        repository.sendFailure = AuthException(error: .smsDailyLimitExceeded)
        let viewModel = await loaded()

        viewModel.sendCode()

        #expect(await eventually { viewModel.error == "오늘 받을 수 있는 인증번호를 모두 썼어요. 내일 다시 시도해 주세요" })
    }

    @Test("인증하면 구글 연결 단계가 되고, 연결하면 목록이 연결됨으로 바뀐다")
    func verifyThenLink() async {
        let viewModel = await loaded()
        viewModel.sendCode()
        #expect(await eventually { viewModel.codeSent && !viewModel.busy })

        viewModel.changeCode("12a3456")
        #expect(viewModel.code == "123456")
        viewModel.verifyCode()
        #expect(await eventually { viewModel.verified && !viewModel.busy })
        #expect(viewModel.notice == "5분 안에 연결할 계정을 선택해 주세요")

        await viewModel.linkGoogle(idToken: "google-id-token")

        #expect(repository.linked.map(\.verificationToken) == ["proof-123456"])
        #expect(viewModel.notice == "구글 계정을 연결했어요")
        #expect(viewModel.methods?.methods.first?.status == "ACTIVE")
        #expect(!viewModel.verified)
    }

    @Test("인증하고 5분이 지나면 문자 인증부터 다시 하게 한다")
    func verificationExpires() async {
        let viewModel = await loaded()
        viewModel.sendCode()
        #expect(await eventually { viewModel.codeSent && !viewModel.busy })
        viewModel.changeCode("123456")
        viewModel.verifyCode()
        #expect(await eventually { viewModel.verified && !viewModel.busy })

        clock.advance(LINK_VERIFICATION_TTL_SECONDS)
        await viewModel.linkGoogle(idToken: "google-id-token")

        #expect(repository.linked.isEmpty)
        #expect(!viewModel.verified)
        #expect(!viewModel.codeSent)
        #expect(viewModel.error == "연결 인증 시간이 지났어요. 문자 인증부터 다시 해 주세요")
    }

    @Test("서버가 연결 인증 만료를 답하면 문자 인증으로 되돌린다")
    func serverExpiryResets() async {
        repository.linkFailure = AuthException(error: .socialVerificationExpired)
        let viewModel = await loaded()
        viewModel.sendCode()
        #expect(await eventually { viewModel.codeSent && !viewModel.busy })
        viewModel.changeCode("123456")
        viewModel.verifyCode()
        #expect(await eventually { viewModel.verified && !viewModel.busy })

        await viewModel.linkGoogle(idToken: "google-id-token")

        #expect(!viewModel.verified)
        #expect(!viewModel.codeSent)
        #expect(viewModel.error != nil)
    }

    @Test("애플 연결은 서버가 준 nonce 로 Apple 인증창을 열고 연결 증표·challenge 를 함께 보낸다")
    func linkApple() async {
        let viewModel = await loaded()
        viewModel.sendCode()
        #expect(await eventually { viewModel.codeSent && !viewModel.busy })
        viewModel.changeCode("123456")
        viewModel.verifyCode()
        #expect(await eventually { viewModel.verified && !viewModel.busy })

        var askedNonce: String?
        await viewModel.linkApple(authorize: { nonce in
            askedNonce = nonce
            return AppleCredential(identityToken: "id", authorizationCode: "code", name: nil)
        })

        #expect(askedNonce == "nonce-1")
        #expect(repository.appleLinks.map(\.challengeToken) == ["challenge-1"])
        #expect(repository.appleLinks.map(\.verificationToken) == ["proof-123456"])
        #expect(viewModel.notice == "애플 계정을 연결했어요")
        #expect(viewModel.methods?.methods.contains { $0.provider == .apple && $0.status == "ACTIVE" } == true)
    }

    @Test("Apple 인증창을 닫으면 안내 없이 연결 단계에 그대로 남는다")
    func appleCancelIsSilent() async {
        let viewModel = await loaded()
        viewModel.sendCode()
        #expect(await eventually { viewModel.codeSent && !viewModel.busy })
        viewModel.changeCode("123456")
        viewModel.verifyCode()
        #expect(await eventually { viewModel.verified && !viewModel.busy })

        await viewModel.linkApple(authorize: { _ in throw CancellationError() })

        #expect(viewModel.error == nil)
        #expect(viewModel.verified)
        #expect(repository.appleLinks.isEmpty)
    }
}
