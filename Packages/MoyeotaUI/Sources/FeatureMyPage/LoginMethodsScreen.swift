import Foundation
import MoyeotaDesignSystem
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

/// 발송 버튼 문구 — 원본(Android #103 `LoginMethodsScreen`)과 같다. 잠긴 동안에는 남은 초를 붙인다 —
/// `smsCooldown` 안내 문구가 「버튼의 남은 시간」을 가리킨다.
func linkCodeSendTitle(remainingSeconds: Int) -> String {
    remainingSeconds > 0 ? "다시 받기 (\(remainingSeconds)초)" : "인증번호 받기"
}

/// 문자 인증 뒤 구글 계정을 연결할 수 있는 시간. 서버 연결 증표의 수명(5분)과 같다.
let LINK_VERIFICATION_TTL_SECONDS: TimeInterval = 300

/// 로그인 수단 관리 — 상태와 서버 호출. 원본 `LoginMethodsViewModel`(Android #103)과 같은 흐름이다:
/// 목록 조회 → (구글 미연결이면) 등록된 휴대폰 문자 인증 → 5분 안에 구글 계정 연결.
@MainActor
@Observable
final class LoginMethodsViewModel {
    private(set) var methods: LoginMethods?
    private(set) var loading = true
    private(set) var busy = false
    private(set) var codeSent = false
    private(set) var verified = false
    private(set) var error: String?
    private(set) var notice: String?
    var code = ""
    private(set) var cooldown = LinkCodeCooldown()

    @ObservationIgnored private let repository: any SocialAuthRepository
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var verificationToken: String?
    @ObservationIgnored private var verifiedAt: Date?

    init(repository: any SocialAuthRepository, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    func refresh() {
        guard !busy else { return }
        loading = true
        error = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                self.methods = try await self.repository.loginMethods()
            } catch is CancellationError {
                return
            } catch {
                self.error = loginMethodMessage(error)
            }
            self.loading = false
        }
    }

    func changeCode(_ value: String) {
        guard !busy else { return }
        code = String(value.filter(\.isNumber).prefix(6))
        error = nil
    }

    func sendCode() {
        guard cooldown.remainingSeconds(now: now()) == 0 else { return }
        action {
            try await self.repository.sendLinkCode()
            self.cooldown.onSent(now: self.now())
            self.verificationToken = nil
            self.codeSent = true
            self.code = ""
            self.verified = false
            self.notice = "등록된 휴대폰으로 인증번호를 보냈어요"
        }
    }

    func verifyCode() {
        guard AuthPolicy.isValidVerificationCode(value: code) else { return }
        let code = self.code
        action {
            self.verificationToken = try await self.repository.verifyLinkCode(code)
            self.verifiedAt = self.now()
            self.verified = true
            self.code = ""
            self.notice = "5분 안에 연결할 구글 계정을 선택해 주세요"
        }
    }

    /// 연결 인증이 지났으면 문자 인증부터 다시 하게 한다.
    func expireVerification() {
        guard verificationToken != nil, let verifiedAt, now().timeIntervalSince(verifiedAt) >= LINK_VERIFICATION_TTL_SECONDS else { return }
        verificationToken = nil
        verified = false
        codeSent = false
        notice = nil
        error = "연결 인증 시간이 지났어요. 문자 인증부터 다시 해 주세요"
    }

    /// 구글 SDK 가 준 idToken 으로 연결한다. 공급자 토큰은 호출 인자로만 존재하고 상태에는 넣지 않는다.
    func linkGoogle(idToken: String) async {
        guard !busy else { return }
        expireVerification()
        guard let token = verificationToken else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await repository.linkGoogle(idToken: idToken, verificationToken: token)
            verificationToken = nil
            verified = false
            codeSent = false
            notice = "구글 계정을 연결했어요"
            methods = try await repository.loginMethods()
        } catch is CancellationError {
        } catch {
            if (error as? AuthException)?.error == .socialVerificationExpired {
                verificationToken = nil
                verified = false
                codeSent = false
            }
            self.error = loginMethodMessage(error)
        }
    }

    func sdkFailed() { error = "구글 인증을 완료하지 못했어요. 다시 시도해 주세요" }

    private func action(_ block: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        notice = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            do {
                try await block()
            } catch is CancellationError {
            } catch {
                self.cooldown.onFailure(error, now: self.now())
                self.error = loginMethodMessage(error)
            }
        }
    }
}

/// 문자 하루 한도는 이 화면 말투로 따로 말한다 — 나머지는 공용 인증 문구다(원본 `loginMethodMessage`)
func loginMethodMessage(_ error: any Error) -> String {
    if (error as? AuthException)?.error == .smsDailyLimitExceeded {
        return "오늘 받을 수 있는 인증번호를 모두 썼어요. 내일 다시 시도해 주세요"
    }
    return error.authUserMessage()
}

/// 35 마이페이지 → 로그인 수단 관리. 원본 `LoginMethodsRoute`(Android #103) — 앱의 상단바·로딩·오류 화면을 쓴다.
///
/// 예전(iOS #50)에는 아이폰 기본 `Form`·`NavigationStack` 시트로 떠서 앱의 다른 화면과 모양이 달랐다.
///
/// - Parameter repository: 소셜 계정 저장소. nil 이면(소셜 기능을 주입하지 않은 호스트) 오류 화면만 그린다
/// - Parameter onPasswordReset: 「비밀번호 재설정」 → 04c
public struct LoginMethodsRoute: View {
    private let repository: (any SocialAuthRepository)?
    private let onBack: () -> Void
    private let onPasswordReset: () -> Void
    @Environment(\.nativeSocialAuthentication) private var native
    @State private var viewModel: LoginMethodsViewModel?
    @State private var sdkBusy = false

    public init(
        repository: (any SocialAuthRepository)?,
        onBack: @escaping () -> Void = {},
        onPasswordReset: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.onBack = onBack
        self.onPasswordReset = onPasswordReset
        if let repository {
            _viewModel = State(initialValue: LoginMethodsViewModel(repository: repository))
        }
    }

    public var body: some View {
        BackStateScaffold(title: "로그인 수단 관리", onBack: onBack) {
            if let viewModel {
                if viewModel.loading {
                    LoadingBox()
                } else if viewModel.methods == nil {
                    ErrorBox(message: viewModel.error ?? "로그인 수단을 불러오지 못했어요", onRetry: { viewModel.refresh() })
                } else {
                    LoginMethodsScreen(
                        viewModel: viewModel,
                        sdkBusy: sdkBusy,
                        onPasswordReset: onPasswordReset,
                        onGoogle: { connectGoogle(viewModel) }
                    )
                }
            } else {
                ErrorBox(message: "로그인 수단을 불러오지 못했어요", onRetry: onBack, actionLabel: "돌아가기")
            }
        }
        .task { viewModel?.refresh() }
    }

    private func connectGoogle(_ viewModel: LoginMethodsViewModel) {
        guard !sdkBusy, let native else { return }
        sdkBusy = true
        Task { @MainActor in
            defer { sdkBusy = false }
            let idToken: String
            do {
                idToken = try await native.google()
            } catch is CancellationError {
                return
            } catch {
                viewModel.sdkFailed()
                return
            }
            await viewModel.linkGoogle(idToken: idToken)
        }
    }
}

struct LoginMethodsScreen: View {
    let viewModel: LoginMethodsViewModel
    let sdkBusy: Bool
    let onPasswordReset: () -> Void
    let onGoogle: () -> Void

    var body: some View {
        if let methods = viewModel.methods {
            let busy = viewModel.busy || sdkBusy
            let googleActive = methods.methods.contains { $0.provider == .google && $0.status == "ACTIVE" }
            ScrollView {
                VStack(alignment: .leading, spacing: MoyeotaSpacing.Md) {
                    Text("연결된 로그인 수단")
                        .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    if methods.hasPassword {
                        Text("아이디와 비밀번호")
                            .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextBody)
                        SecondaryButton(text: "비밀번호 재설정", onClick: onPasswordReset, enabled: !busy)
                    }
                    ForEach(methods.methods, id: \.provider) { method in
                        Text("\(providerLabel(method.provider)) · \(method.status == "ACTIVE" ? "연결됨" : "재인증 필요")")
                            .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextBody)
                    }
                    if let error = viewModel.error { NoticeBanner(kind: .error, text: error) }
                    if let notice = viewModel.notice { NoticeBanner(kind: .info, text: notice) }
                    if !googleActive {
                        Text("등록된 휴대폰으로 본인을 확인한 뒤 구글 계정을 연결해요. 연결된 계정은 교체하거나 합칠 수 없어요.")
                            .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextBody)
                            .fixedSize(horizontal: false, vertical: true)
                        if !viewModel.verified {
                            // 남은 초를 1초마다 다시 그린다(서버 쿨다운 안내가 「버튼의 남은 시간」을 가리킨다)
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                let remaining = viewModel.cooldown.remainingSeconds(now: timeline.date)
                                SecondaryButton(
                                    text: linkCodeSendTitle(remainingSeconds: remaining),
                                    onClick: { viewModel.sendCode() },
                                    enabled: !busy && remaining == 0
                                )
                            }
                            if viewModel.codeSent {
                                MoyeotaTextField(
                                    value: viewModel.code,
                                    onValueChange: { viewModel.changeCode($0) },
                                    label: "인증번호",
                                    placeholder: "숫자 6자리",
                                    keyboardOptions: KeyboardOptions(keyboardType: .number),
                                    enabled: !busy
                                )
                                PrimaryCtaButton(
                                    text: "인증번호 확인",
                                    onClick: { viewModel.verifyCode() },
                                    enabled: !busy && AuthPolicy.isValidVerificationCode(value: viewModel.code)
                                )
                            }
                        } else {
                            PrimaryCtaButton(text: busy ? "연결 중…" : "Google 계정 연결", onClick: onGoogle, enabled: !busy)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // 5분이 지나면 연결 단계에서 문자 인증으로 되돌린다(원본은 1초 타이머가 같은 일을 한다)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                viewModel.expireVerification()
            }
        }
    }

    /// 연결 수단은 Google 하나다. 서버가 다른 provider 를 보내도 디코딩에서 걸러져 여기 오지 않는다.
    private func providerLabel(_ provider: SocialProvider) -> String {
        switch provider {
        case .google: return "Google"
        }
    }
}
