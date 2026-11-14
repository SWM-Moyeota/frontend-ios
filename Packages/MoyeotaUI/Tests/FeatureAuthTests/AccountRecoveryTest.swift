import Foundation
import MoyeotaDomain
import PresentationCore
import Testing
@testable import FeatureAuth

// 원본에 없는 테스트 — 04b 아이디 찾기 · 04c 비밀번호 재설정은 iOS 가 먼저 붙인 화면이다.
// 발송·확인·저장 흐름과 실패 해석을 뷰 없이 확인한다.

private final class FakeRecoveryRepository: UnsupportedAuthRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    let sendGate = Gate()
    var holdsSend = false
    var sendFailure: (any Error)?
    var verifyFailure: (any Error)?
    var confirmFailure: (any Error)?
    var ticket = PasswordResetTicket(requestId: "req-1", expiresInSeconds: 180, resendAfterSeconds: 60)

    var calls: [String] {
        lock.withLock { log }
    }

    private func record(_ call: String) {
        lock.withLock { log.append(call) }
    }

    override func sendFindLoginIdCode(phoneNumber: String) async throws {
        record("find-send \(phoneNumber)")
        if holdsSend { await sendGate.wait() }
        if let sendFailure { throw sendFailure }
    }

    override func findLoginId(phoneNumber: String, code: String) async throws -> String {
        record("find-verify \(phoneNumber) \(code)")
        if let verifyFailure { throw verifyFailure }
        return "moyeota_test"
    }

    override func requestPasswordReset(loginId: String, phoneNumber: String) async throws -> PasswordResetTicket {
        record("reset-send \(loginId) \(phoneNumber)")
        if holdsSend { await sendGate.wait() }
        if let sendFailure { throw sendFailure }
        return ticket
    }

    override func verifyPasswordResetCode(requestId: String, code: String) async throws -> String {
        record("reset-verify \(requestId) \(code)")
        if let verifyFailure { throw verifyFailure }
        return "reset-token"
    }

    override func confirmPasswordReset(
        resetToken: String,
        newPassword: String,
        newPasswordConfirm: String
    ) async throws {
        record("reset-confirm \(resetToken) \(newPassword) \(newPasswordConfirm)")
        if let confirmFailure { throw confirmFailure }
    }
}

@MainActor
@Suite struct RecoveryCodeViewModelTest {
    private let PHONE = "01012345678"
    private let clock = VirtualClock()

    private func make(_ purpose: RecoveryPurpose, _ repository: FakeRecoveryRepository) -> RecoveryCodeViewModel {
        let clock = self.clock
        return RecoveryCodeViewModel(
            purpose: purpose,
            repository: repository,
            sleep: { try await clock.sleep($0) },
            currentTimeMillis: { clock.currentMillis }
        )
    }

    // ── 04b 아이디 찾기 ──

    @Test("아이디 찾기는 번호로 발송하고 6자리를 채우면 스스로 확인해 아이디를 얻는다")
    func findIdHappyPath() async {
        let repository = FakeRecoveryRepository()
        let viewModel = make(.findLoginId, repository)

        viewModel.requestCode(phoneDigits: PHONE)
        #expect(viewModel.state.requesting, "태스크 시작을 기다리지 않고 켜져야 두 번 눌리지 않는다")
        await clock.settle()
        #expect(viewModel.state.stage == .codeSent)
        #expect(viewModel.state.codeRemainingSeconds(nowMillis: viewModel.nowMillis) == AuthPolicy.SMS_CODE_TTL_SECONDS)

        viewModel.onCodeChanged(raw: "123456")
        await clock.settle()

        #expect(viewModel.state.stage == .verified)
        #expect(viewModel.state.token == "moyeota_test")
        #expect(repository.calls == ["find-send 01012345678", "find-verify 01012345678 123456"])
    }

    /// 가입 흐름의 「이미 가입된 번호」와 정반대다 — 입력칸을 열지 않고 가입으로 보낼 수 있어야 한다.
    @Test("가입되지 않은 번호는 입력칸을 열지 않고 가입 길을 켠다")
    func findIdNotRegistered() async {
        let repository = FakeRecoveryRepository()
        repository.sendFailure = AuthException(error: .phoneNotRegistered)
        let viewModel = make(.findLoginId, repository)

        viewModel.requestCode(phoneDigits: PHONE)
        await clock.settle()

        #expect(viewModel.state.stage == .idle)
        #expect(!viewModel.state.requesting)
        #expect(viewModel.state.phoneMessage == authErrorMessage(error: .phoneNotRegistered))
        #expect(viewModel.requestIssue == .notRegistered)

        // 번호를 고치면 그 안내는 남의 번호 이야기가 된다.
        viewModel.onPhoneDigitsChanged(phoneDigits: "01099998888")
        #expect(viewModel.requestIssue == nil)
        #expect(viewModel.state == PhoneVerifyState())
    }

    @Test("하루 한도 문구는 다른 번호로 가입하라고 하지 않는다")
    func findIdDailyLimitCopy() async {
        let repository = FakeRecoveryRepository()
        repository.sendFailure = AuthException(error: .smsDailyLimitExceeded)
        let viewModel = make(.findLoginId, repository)

        viewModel.requestCode(phoneDigits: PHONE)
        await clock.settle()

        #expect(viewModel.state.dailyLimitReached)
        #expect(viewModel.state.phoneMessage?.contains("가입") == false)
        #expect(viewModel.state.phoneMessage?.contains("내일") == true)
    }

    @Test("틀린 인증번호는 입력칸만 비우고 다시 받는다")
    func findIdMismatch() async {
        let repository = FakeRecoveryRepository()
        repository.verifyFailure = AuthException(error: .smsCodeMismatch)
        let viewModel = make(.findLoginId, repository)

        viewModel.requestCode(phoneDigits: PHONE)
        await clock.settle()
        viewModel.onCodeChanged(raw: "000000")
        await clock.settle()

        #expect(viewModel.state.stage == .codeSent)
        #expect(viewModel.state.code.isEmpty)
        #expect(viewModel.state.codeMessage == authErrorMessage(error: .smsCodeMismatch))
        #expect(viewModel.state.codeRemainingSeconds(nowMillis: viewModel.nowMillis) > 0, "입력칸은 열려 있어야 한다")
    }

    @Test("요청이 날아간 사이 번호를 고치면 늦게 온 응답을 버린다")
    func staleSendDropped() async {
        let repository = FakeRecoveryRepository()
        repository.holdsSend = true
        let viewModel = make(.findLoginId, repository)

        viewModel.requestCode(phoneDigits: PHONE)
        await clock.settle()
        viewModel.onPhoneDigitsChanged(phoneDigits: "0109999888")
        repository.sendGate.open()
        await clock.settle()

        #expect(viewModel.state == PhoneVerifyState())
        #expect(clock.pendingCount == 0, "버린 응답으로 틱을 시작하지 않는다")
    }

    // ── 04c 비밀번호 재설정 ──

    @Test("재설정은 아이디와 번호로 요청하고 접수번호로 확인해 토큰을 얻는다")
    func resetHappyPath() async {
        let repository = FakeRecoveryRepository()
        let viewModel = make(.resetPassword, repository)

        viewModel.requestCode(phoneDigits: PHONE, loginId: "moyeota")
        await clock.settle()
        #expect(viewModel.state.stage == .codeSent)

        viewModel.onCodeChanged(raw: "123456")
        await clock.settle()

        #expect(viewModel.state.stage == .verified)
        #expect(viewModel.state.token == "reset-token")
        #expect(repository.calls == ["reset-send moyeota 01012345678", "reset-verify req-1 123456"])
    }

    @Test("유효 시간과 재요청 간격은 서버가 준 값을 쓴다")
    func resetUsesServerWindow() async {
        let repository = FakeRecoveryRepository()
        repository.ticket = PasswordResetTicket(requestId: "req-1", expiresInSeconds: 90, resendAfterSeconds: 30)
        let viewModel = make(.resetPassword, repository)

        viewModel.requestCode(phoneDigits: PHONE, loginId: "moyeota")
        await clock.settle()

        #expect(viewModel.state.codeRemainingSeconds(nowMillis: viewModel.nowMillis) == 90)
        #expect(viewModel.state.resendRemainingSeconds(nowMillis: viewModel.nowMillis) == 30)
    }

    /// 접수는 「아이디 + 번호」 한 쌍에 묶여 있다 — 옛 아이디로 받은 인증번호로 확인하면 바뀌는 건 옛 아이디의 비밀번호다.
    @Test("인증번호를 받은 뒤 아이디를 고치면 인증을 버린다")
    func resetLoginIdChangeInvalidates() async {
        let repository = FakeRecoveryRepository()
        let viewModel = make(.resetPassword, repository)

        viewModel.requestCode(phoneDigits: PHONE, loginId: "moyeota")
        await clock.settle()
        #expect(viewModel.state.stage == .codeSent)

        viewModel.onLoginIdChanged(loginId: "moyeota")
        #expect(viewModel.state.stage == .codeSent, "같은 아이디는 건드리지 않는다")

        viewModel.onLoginIdChanged(loginId: "moyeota2")
        #expect(viewModel.state == PhoneVerifyState())

        viewModel.onCodeChanged(raw: "123456")
        await clock.settle()
        #expect(!repository.calls.contains { $0.hasPrefix("reset-verify") })
    }

    @Test("재설정 요청 제한은 재요청 버튼을 쿨다운으로 잠근다")
    func resetSendRateLimited() async {
        let repository = FakeRecoveryRepository()
        repository.sendFailure = AuthException(error: .passwordResetRateLimited)
        let viewModel = make(.resetPassword, repository)

        viewModel.requestCode(phoneDigits: PHONE, loginId: "moyeota")
        await clock.settle()

        #expect(viewModel.state.stage == .idle)
        #expect(viewModel.state.phoneMessage == authErrorMessage(error: .passwordResetRateLimited))
        #expect(
            viewModel.state.resendRemainingSeconds(nowMillis: viewModel.nowMillis)
                == AuthPolicy.SMS_RESEND_COOLDOWN_SECONDS
        )
        #expect(!viewModel.state.canRequestCode(phoneDigits: PHONE, nowMillis: viewModel.nowMillis))
    }

    /// 접수가 살아 있어 5번까지 다시 넣을 수 있다 — 입력칸을 닫으면 안 된다.
    @Test("재설정 인증번호 400 은 입력칸을 비우고 다시 받는다")
    func resetVerifyRejected() async {
        let repository = FakeRecoveryRepository()
        repository.verifyFailure = AuthException(error: .passwordResetCodeRejected)
        let viewModel = make(.resetPassword, repository)

        viewModel.requestCode(phoneDigits: PHONE, loginId: "moyeota")
        await clock.settle()
        viewModel.onCodeChanged(raw: "000000")
        await clock.settle()

        #expect(viewModel.state.stage == .codeSent)
        #expect(viewModel.state.code.isEmpty)
        #expect(viewModel.state.codeMessage == authErrorMessage(error: .passwordResetCodeRejected))
        #expect(viewModel.state.codeRemainingSeconds(nowMillis: viewModel.nowMillis) > 0)
    }

    @Test("재설정 인증번호를 5번 넘기면 입력칸을 닫고 재요청으로 보낸다")
    func resetVerifyLimited() async {
        let repository = FakeRecoveryRepository()
        repository.verifyFailure = AuthException(error: .passwordResetRateLimited)
        let viewModel = make(.resetPassword, repository)

        viewModel.requestCode(phoneDigits: PHONE, loginId: "moyeota")
        await clock.settle()
        viewModel.onCodeChanged(raw: "000000")
        await clock.settle()

        #expect(viewModel.state.codeRemainingSeconds(nowMillis: viewModel.nowMillis) == 0)
        #expect(viewModel.state.codeMessage == authErrorMessage(error: .passwordResetRateLimited))
    }

    @Test("되돌리기는 인증을 버리고 사유를 번호 칸에 남긴다")
    func restartKeepsMessage() async {
        let repository = FakeRecoveryRepository()
        let viewModel = make(.resetPassword, repository)
        viewModel.requestCode(phoneDigits: PHONE, loginId: "moyeota")
        await clock.settle()
        viewModel.onCodeChanged(raw: "123456")
        await clock.settle()
        #expect(viewModel.state.stage == .verified)

        viewModel.restart(message: "다시 인증해 주세요")

        #expect(viewModel.state == PhoneVerifyState(phoneMessage: "다시 인증해 주세요"))
    }
}

@MainActor
@Suite struct PasswordResetConfirmViewModelTest {
    private let clock = VirtualClock()

    @Test("저장에 성공하면 completed 가 켜지고 값을 그대로 보낸다")
    func success() async {
        let repository = FakeRecoveryRepository()
        let viewModel = PasswordResetConfirmViewModel(repository: repository)

        viewModel.confirm(resetToken: "tok", newPassword: "Passw0rd!", newPasswordConfirm: "Passw0rd!")
        #expect(viewModel.uiState.submitting)
        await clock.settle()

        #expect(viewModel.uiState.completed)
        #expect(!viewModel.uiState.submitting)
        #expect(repository.calls == ["reset-confirm tok Passw0rd! Passw0rd!"])
    }

    @Test("실패는 고칠 곳에 따라 다른 자리에 뜬다")
    func failuresRouted() async {
        func state(after error: AuthError) async -> PasswordResetConfirmViewModel.UiState {
            let repository = FakeRecoveryRepository()
            repository.confirmFailure = AuthException(error: error)
            let viewModel = PasswordResetConfirmViewModel(repository: repository)
            viewModel.confirm(resetToken: "tok", newPassword: "Passw0rd!", newPasswordConfirm: "Passw0rd!")
            await clock.settle()
            return viewModel.uiState
        }

        let same = await state(after: .samePassword)
        #expect(same.passwordError == authErrorMessage(error: .samePassword))
        #expect(same.bannerMessage == nil && !same.submitting && !same.completed)

        let policy = await state(after: .passwordPolicyViolation)
        #expect(policy.passwordError == authErrorMessage(error: .passwordPolicyViolation))

        let mismatch = await state(after: .passwordConfirmMismatch)
        #expect(mismatch.confirmError == authErrorMessage(error: .passwordConfirmMismatch))

        // 토큰 무효는 입력을 고쳐서 풀리지 않는다 — 인증으로 되돌리라는 신호만 싣는다.
        let token = await state(after: .passwordResetTokenInvalid)
        #expect(token.reverifyMessage == authErrorMessage(error: .passwordResetTokenInvalid))
        #expect(token.passwordError == nil && token.bannerMessage == nil)

        let network = await state(after: .network)
        #expect(network.bannerMessage == authErrorMessage(error: .network))
    }

    @Test("입력을 고치면 서버 오류 문구를 지운다")
    func inputClearsErrors() async {
        let repository = FakeRecoveryRepository()
        repository.confirmFailure = AuthException(error: .samePassword)
        let viewModel = PasswordResetConfirmViewModel(repository: repository)
        viewModel.confirm(resetToken: "tok", newPassword: "Passw0rd!", newPasswordConfirm: "Passw0rd!")
        await clock.settle()
        #expect(viewModel.uiState.passwordError != nil)

        viewModel.onInputChanged()

        #expect(viewModel.uiState == PasswordResetConfirmViewModel.UiState())
    }
}

@Suite struct RecoveryTransitionTest {
    @Test("재설정 실패 코드는 화면 대응이 같은 전이로 옮긴다")
    func transitionMapping() {
        #expect(recoveryTransitionError(error: .passwordResetRateLimited, verifying: false) == .smsCooldown)
        #expect(recoveryTransitionError(error: .passwordResetRateLimited, verifying: true) == .smsTooManyAttempts)
        #expect(recoveryTransitionError(error: .passwordResetCodeRejected, verifying: true) == .smsCodeMismatch)
        #expect(recoveryTransitionError(error: .network, verifying: true) == .network)
    }
}
