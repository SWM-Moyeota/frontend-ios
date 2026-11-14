import Foundation
import MoyeotaDomain
import Observation
import PresentationCore

// 04b 아이디 찾기 · 04c 비밀번호 재설정이 함께 쓰는 「번호로 인증번호 받기 → 6자리 확인」 흐름.
//
// 백엔드 #314·#331 이 2026-11-14 운영에 올라온 뒤 iOS 가 먼저 붙였고, 원본이 같은 날 따라왔다
// (Android frontend #100). 상태 전이는 가입 문자 인증의 `PhoneVerifyState` 를 그대로 쓴다:
// 카운트다운·재발송·만료·시도 초과의 규칙이 같고, 같은 규칙을 두 벌 두면 한쪽만 고쳐진다.
//
// 가입 인증(`PhoneVerifyViewModel`)과 갈리는 점은 셋이다.
// 1. **선확인이 없다.** 가입은 「이미 가입된 번호」를 미리 막지만, 여기서는 가입된 번호가 정상이다.
// 2. **확인 열쇠가 다르다.** 아이디 찾기는 번호로, 재설정은 서버가 준 접수번호로 확인한다.
// 3. **결과물이 다르다.** 아이디 찾기는 아이디를, 재설정은 일회용 토큰을 `PhoneVerifyState.token` 에 담는다.

/// 인증으로 무엇을 얻으려는가. 부르는 API 와 실패 해석이 여기서 갈린다.
enum RecoveryPurpose: Equatable, Sendable {
    /// 04b — `find-id/send` · `find-id/verify`. 결과는 아이디 전체.
    case findLoginId

    /// 04c — `password-reset/send` · `password-reset/verify`. 결과는 재설정 토큰.
    case resetPassword
}

/// 발송 실패 뒤 화면이 따로 길을 내줘야 하는 경우.
enum RecoveryRequestIssue: Equatable, Sendable {
    /// 가입되지 않은 번호(아이디 찾기 전용) — 「가입하기」로 보낸다.
    case notRegistered
}

/// 아이디 찾기에서는 「다른 번호로 가입」이 답이 아니다 — 가입 화면용 문구의 꼬리만 뗀다.
func recoveryErrorMessage(error: AuthError, fallback: String) -> String {
    switch error {
    case .smsDailyLimitExceeded:
        "오늘 받을 수 있는 인증번호를 모두 썼어요(하루 \(AuthPolicy.SMS_DAILY_LIMIT)번). 내일 다시 시도해 주세요"
    default:
        fallback
    }
}

/// 재설정의 실패 코드를 `PhoneVerifyState` 가 아는 전이로 옮긴다 — 화면 대응이 같은 것끼리 짝짓는다.
///
/// - 발송 429 `USER306`: 서버가 문자 쿨다운을 가입 인증과 같은 칸에 세므로 대부분 「1분 안에 또 눌렀다」다.
///   남은 초(`Retry-After`)는 전송 계층이 올려 주지 않아 쿨다운 최대치로 보수적으로 잡는다.
/// - 확인 400 `USER301`: 접수가 살아 있어 다시 넣을 수 있다 → 불일치와 같은 전이(입력칸만 비운다).
/// - 확인 429 `USER306`: 5번을 넘겼다 → 시도 초과와 같은 전이(입력칸을 닫고 재발송으로 보낸다).
func recoveryTransitionError(error: AuthError, verifying: Bool) -> AuthError {
    switch error {
    case .passwordResetRateLimited: verifying ? .smsTooManyAttempts : .smsCooldown
    case .passwordResetCodeRejected: .smsCodeMismatch
    default: error
    }
}

/// 재설정 요청 제한(429 `USER306`)을 화면이 어떻게 받을지. 서버는 사유 없이 남은 초만 준다.
enum RecoveryRateLimit: Equatable, Sendable {
    /// 곧 풀린다 — 재요청 버튼을 그 초만큼 카운트다운으로 잠근다.
    case shortWait(seconds: Int, message: String)

    /// 한참 걸린다(하루 문자 횟수·계정당 시간당 제한) — 초를 세는 건 의미가 없어 버튼을 잠그고 대략의 시간만 말한다.
    case longWait(message: String)
}

/// 남은 시간으로 제한의 종류를 가른다.
///
/// 문자 쿨다운은 60초이고 IP 당 제한도 60초 창이라, **60초 이하면 「방금 요청했다」** 로 본다. 실제로 가장 흔한
/// 경우는 04b 에서 아이디를 찾자마자 같은 번호로 04c 를 여는 것이다 — 두 기능이 같은 문자 대기 칸을 쓴다.
/// 그보다 길면 하루 횟수(최대 24시간)나 계정당 제한(최대 1시간)이다.
/// 서버가 값을 주지 않았으면 쿨다운 최대치로 보수적으로 잡는다.
func recoveryRateLimit(retryAfterSeconds: Int?) -> RecoveryRateLimit {
    guard let seconds = retryAfterSeconds else {
        return .shortWait(
            seconds: AuthPolicy.SMS_RESEND_COOLDOWN_SECONDS,
            message: authErrorMessage(error: .passwordResetRateLimited)
        )
    }
    if seconds <= AuthPolicy.SMS_RESEND_COOLDOWN_SECONDS {
        return .shortWait(
            seconds: seconds,
            message: "방금 이 번호로 인증번호를 요청했어요. 버튼의 남은 시간이 끝나면 다시 받아 주세요"
        )
    }
    let minutes = (seconds + 59) / 60
    let wait = minutes < 60 ? "약 \(minutes)분" : "약 \((minutes + 59) / 60)시간"
    return .longWait(message: "인증번호 요청이 너무 많았어요. \(wait) 뒤에 다시 시도해 주세요")
}

private let RECOVERY_TICK_INTERVAL_MS = 500

@MainActor
@Observable
final class RecoveryCodeViewModel {
    private(set) var state = PhoneVerifyState()

    /// 카운트다운 표시에 쓰는 현재 시각. 틱이 돌 때만 갱신된다.
    private(set) var nowMillis: Int64

    private(set) var requestIssue: RecoveryRequestIssue?

    @ObservationIgnored private let purpose: RecoveryPurpose
    @ObservationIgnored private let repository: any AuthRepository
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let currentTimeMillis: @Sendable () -> Int64
    @ObservationIgnored private let scope = ViewModelScope()
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// 재설정에서 인증번호를 요청한 아이디. 번호와 함께 「이 응답이 지금 입력의 것인가」를 가른다.
    @ObservationIgnored private var boundLoginId = ""

    /// 재설정 접수번호. 확인 요청의 열쇠라 화면에 내보내지 않는다.
    @ObservationIgnored private var requestId = ""

    init(
        purpose: RecoveryPurpose,
        repository: any AuthRepository,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        currentTimeMillis: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.purpose = purpose
        self.repository = repository
        self.sleep = sleep
        self.currentTimeMillis = currentTimeMillis
        self.nowMillis = currentTimeMillis()
    }

    private func updateState(_ transform: (PhoneVerifyState) -> PhoneVerifyState) {
        let next = transform(state)
        if next != state { state = next }
    }

    /// 번호가 바뀌면 진행 중인 인증을 버린다 — 인증번호는 번호에 묶여 있다.
    func onPhoneDigitsChanged(phoneDigits: String) {
        let before = state
        updateState { $0.onPhoneDigitsChanged(phoneDigits: phoneDigits) }
        if state != before { forgetRequest() }
    }

    /// 재설정에서 아이디가 바뀌면 진행 중인 인증을 버린다 — 서버 접수는 「아이디 + 번호」 한 쌍에 묶여 있어
    /// 옛 아이디로 받은 인증번호로 새 아이디의 비밀번호를 바꿀 수는 없다(바뀌는 건 옛 아이디다).
    func onLoginIdChanged(loginId: String) {
        if state.stage == .idle && !state.requesting && state.boundPhone.isEmpty { return }
        if loginId == boundLoginId { return }
        updateState { _ in PhoneVerifyState() }
        forgetRequest()
    }

    /// 인증을 통째로 버리고 처음으로 되돌린다. 재설정 토큰이 만료됐을 때 안내와 함께 부른다.
    func restart(message: String? = nil) {
        updateState { $0.invalidated(message: message) }
        forgetRequest()
    }

    private func forgetRequest() {
        requestIssue = nil
        requestId = ""
        boundLoginId = ""
    }

    func requestCode(phoneDigits: String, loginId: String = "") {
        let now = currentTimeMillis()
        if !state.canRequestCode(phoneDigits: phoneDigits, nowMillis: now) { return }
        let phone = AuthPolicy.normalizePhoneNumber(value: phoneDigits)
        updateState { $0.onRequestStart(phone: phone) }
        requestIssue = nil
        boundLoginId = loginId
        let repository = self.repository
        let purpose = self.purpose
        scope.launch { [weak self] in
            do {
                let ticket: PasswordResetTicket?
                switch purpose {
                case .findLoginId:
                    try await repository.sendFindLoginIdCode(phoneNumber: phone)
                    ticket = nil
                case .resetPassword:
                    ticket = try await repository.requestPasswordReset(loginId: loginId, phoneNumber: phone)
                }
                guard let self else { return }
                // 요청이 날아간 사이 번호나 아이디를 고쳤으면 이 응답은 남의 것이다 — 버린다.
                if !self.owns(phone: phone, loginId: loginId) { return }
                let sentAt = self.currentTimeMillis()
                self.requestId = ticket?.requestId ?? ""
                self.updateState {
                    var next = $0.onCodeSent(nowMillis: sentAt)
                    // 재설정은 서버가 유효 시간·재요청 간격을 직접 알려 준다 — 정책 상수보다 그 값을 믿는다.
                    if let ticket {
                        next.codeExpiresAt = sentAt + Int64(ticket.expiresInSeconds) * 1000
                        next.resendAllowedAt = sentAt + Int64(ticket.resendAfterSeconds) * 1000
                    }
                    return next
                }
            } catch {
                guard let failure = authFailureOnLiveTask(error: error) else { return }
                guard let self else { return }
                if !self.owns(phone: phone, loginId: loginId) { return }
                let kind = failure.recoveryAuthError()
                let failedAt = self.currentTimeMillis()
                self.requestIssue = kind == .phoneNotRegistered ? .notRegistered : nil
                if kind == .passwordResetRateLimited {
                    // 사유는 없어도 남은 시간은 온다 — 그 값으로 「곧 풀린다」와 「한참 걸린다」를 가른다.
                    let retryAfter = (failure as? AuthException)?.retryAfterSeconds
                    switch recoveryRateLimit(retryAfterSeconds: retryAfter) {
                    case let .shortWait(seconds, message):
                        self.updateState {
                            var next = $0.onRequestFailure(error: .smsCooldown, message: message, nowMillis: failedAt)
                            // 전이는 쿨다운 최대치(60초)로 잡는다 — 서버가 준 실제 남은 시간으로 고쳐 쓴다.
                            next.resendAllowedAt = failedAt + Int64(seconds) * 1000
                            return next
                        }
                    case let .longWait(message):
                        // 하루 한도와 같은 전이: 버튼을 잠그고 카운트다운을 걸지 않는다. 번호를 고치면 풀린다.
                        self.updateState {
                            $0.onRequestFailure(error: .smsDailyLimitExceeded, message: message, nowMillis: failedAt)
                        }
                    }
                } else {
                    self.updateState {
                        $0.onRequestFailure(
                            error: recoveryTransitionError(error: kind, verifying: false),
                            message: recoveryErrorMessage(error: kind, fallback: failure.authUserMessage()),
                            nowMillis: failedAt
                        )
                    }
                }
            }
            self?.startTicker()
        }
    }

    private func owns(phone: String, loginId: String) -> Bool {
        state.boundPhone == phone && boundLoginId == loginId
    }

    func onCodeChanged(raw: String) {
        updateState { $0.onCodeChanged(raw: raw) }
        if AuthPolicy.isValidVerificationCode(value: state.code) { verify() }
    }

    func verify() {
        let current = state
        if !current.canSubmitCode(nowMillis: currentTimeMillis()) { return }
        let phone = current.boundPhone
        let code = current.code
        let loginId = boundLoginId
        let requestId = self.requestId
        updateState { $0.onVerifyStart() }
        let repository = self.repository
        let purpose = self.purpose
        scope.launch { [weak self] in
            do {
                let result: String
                switch purpose {
                case .findLoginId:
                    result = try await repository.findLoginId(phoneNumber: phone, code: code)
                case .resetPassword:
                    result = try await repository.verifyPasswordResetCode(requestId: requestId, code: code)
                }
                guard let self else { return }
                if !self.owns(phone: phone, loginId: loginId) { return }
                self.updateState { $0.onVerified(verificationToken: result) }
            } catch {
                guard let failure = authFailureOnLiveTask(error: error) else { return }
                guard let self else { return }
                if !self.owns(phone: phone, loginId: loginId) { return }
                let kind = failure.recoveryAuthError()
                self.updateState {
                    $0.onVerifyFailure(
                        error: recoveryTransitionError(error: kind, verifying: true),
                        message: recoveryErrorMessage(error: kind, fallback: failure.authUserMessage())
                    )
                }
            }
        }
    }

    private func startTicker() {
        if ticker != nil { return }
        if !tick() { return }
        let sleep = self.sleep
        ticker = scope.launch { [weak self] in
            // 대기 동안 뷰모델을 붙잡지 않는다 — 그래야 해제되고, 해제가 이 루프를 취소한다.
            repeat {
                do {
                    try await sleep(.milliseconds(RECOVERY_TICK_INTERVAL_MS))
                } catch {
                    return
                }
            } while self?.tick() == true
        }
    }

    private func tick() -> Bool {
        let now = currentTimeMillis()
        nowMillis = now
        if state.codeRemainingSeconds(nowMillis: now) == 0 {
            updateState { $0.onCodeExpired(message: authErrorMessage(error: .smsCodeExpired)) }
        }
        if state.hasRunningCountdown(nowMillis: currentTimeMillis()) { return true }
        ticker = nil
        return false
    }
}

private extension Error {
    func recoveryAuthError() -> AuthError {
        (self as? AuthException)?.error ?? .unknown
    }
}

/// 04c 의 마지막 단계 — 새 비밀번호 저장. 제출 결과만 관리하고 입력값은 화면이 든다(04a 와 같은 분담).
@MainActor
@Observable
final class PasswordResetConfirmViewModel {
    struct UiState: Equatable, Sendable {
        var submitting = false
        /// 새 비밀번호 입력란 아래에 그릴 오류(규칙 위반·지금 비밀번호와 같음).
        var passwordError: String?
        /// 확인 입력란 아래에 그릴 오류.
        var confirmError: String?
        /// 입력란에 붙일 수 없는 실패(네트워크 등).
        var bannerMessage: String?
        /// 토큰이 무효다 — 화면이 인증 단계로 되돌린다. 문구를 싣고 온다.
        var reverifyMessage: String?
        var completed = false
    }

    private(set) var uiState = UiState()

    @ObservationIgnored private let repository: any AuthRepository
    @ObservationIgnored private let scope = ViewModelScope()

    init(repository: any AuthRepository) {
        self.repository = repository
    }

    /// 입력을 고치면 그 입력란의 서버 오류는 낡은 말이 된다.
    func onInputChanged() {
        if uiState.passwordError == nil && uiState.confirmError == nil && uiState.bannerMessage == nil { return }
        uiState.passwordError = nil
        uiState.confirmError = nil
        uiState.bannerMessage = nil
    }

    /// 화면이 인증 단계로 되돌린 뒤 부른다 — 같은 문구로 두 번 되돌리지 않게 한다.
    func onReverifyHandled() {
        uiState.reverifyMessage = nil
    }

    func confirm(resetToken: String, newPassword: String, newPasswordConfirm: String) {
        if uiState.submitting || uiState.completed { return }
        uiState = UiState(submitting: true)
        let repository = self.repository
        scope.launch { [weak self] in
            do {
                try await repository.confirmPasswordReset(
                    resetToken: resetToken,
                    newPassword: newPassword,
                    newPasswordConfirm: newPasswordConfirm
                )
                guard let self else { return }
                self.uiState = UiState(completed: true)
            } catch {
                guard let failure = authFailureOnLiveTask(error: error) else { return }
                guard let self else { return }
                let message = failure.authUserMessage()
                var next = UiState()
                switch (failure as? AuthException)?.error {
                case .samePassword, .passwordPolicyViolation: next.passwordError = message
                case .passwordConfirmMismatch: next.confirmError = message
                case .passwordResetTokenInvalid: next.reverifyMessage = message
                default: next.bannerMessage = message
                }
                self.uiState = next
            }
        }
    }
}
