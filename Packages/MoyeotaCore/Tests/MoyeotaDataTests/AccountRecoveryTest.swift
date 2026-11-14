import Foundation
import MoyeotaDomain
import Testing
@testable import MoyeotaData

/// 아이디 찾기(Backend #314) · 비밀번호 재설정(Backend #331) 의 서버 계약.
///
/// 기준: 백엔드 `AuthController`(`/api/v1/auth/find-id/*`) · `PasswordResetController`
/// (`/api/v1/auth/password-reset/*`) · `UserErrorCode`.
/// 실측(2026-11-14, 운영): 빈 본문 `POST find-id/send` · `password-reset/send` → 400 `INVALID_REQUEST`.
@Suite struct AccountRecoveryTest {
    private func session() async -> SessionManager {
        let scope = CoroutineScope()
        let manager = SessionManager(storage: FakeTokenStorage(nil), scope: scope)
        await scope.join()
        return manager
    }

    private func repository(_ api: any AuthApi) async -> RemoteAuthRepository {
        let session = await session()
        let userApi = RecoveryUnusedUserApi.shared
        return RemoteAuthRepository(
            api: api,
            userApi: userApi,
            session: session,
            fcmTokenRegistrar: FcmTokenRegistrar(userApi: userApi, session: session),
            activePartyStorage: RecoveryEmptyPartyStorage()
        )
    }

    private func httpException(_ code: Int, _ body: String) -> HttpException {
        HttpException(Response<Void>.error(code, body))
    }

    // ── 경로 ──

    /// 다섯 경로 모두 `/api/v1/auth/` 하위여야 한다 — 그 프리픽스만 permitAll 이라 로그인 전에 부를 수 있다.
    @Test("아이디 찾기·비밀번호 재설정 경로는 auth 프리픽스 아래의 POST 다")
    func routes() {
        #expect(AuthApiRoute.sendFindLoginIdCode.route == .POST("api/v1/auth/find-id/send"))
        #expect(AuthApiRoute.findLoginId.route == .POST("api/v1/auth/find-id/verify"))
        #expect(AuthApiRoute.sendPasswordResetCode.route == .POST("api/v1/auth/password-reset/send"))
        #expect(AuthApiRoute.verifyPasswordResetCode.route == .POST("api/v1/auth/password-reset/verify"))
        #expect(AuthApiRoute.confirmPasswordReset.route == .POST("api/v1/auth/password-reset/confirm"))
    }

    // ── JSON 키 ──

    @Test("재설정 요청 본문의 키는 서버 record 필드와 같다")
    func requestKeys() throws {
        func keys(_ value: some Encodable) throws -> Set<String> {
            let data = try MoyeotaJSON.encoder.encode(value)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return Set(object.keys)
        }

        #expect(try keys(PasswordResetSendRequestDto(loginId: "a", phoneNumber: "b")) == ["loginId", "phoneNumber"])
        #expect(try keys(PasswordResetVerifyRequestDto(requestId: "a", code: "b")) == ["requestId", "code"])
        #expect(
            try keys(PasswordResetConfirmRequestDto(resetToken: "a", newPassword: "b", newPasswordConfirm: "c"))
                == ["resetToken", "newPassword", "newPasswordConfirm"]
        )
    }

    @Test("재설정 응답을 서버가 주는 모양 그대로 읽는다")
    func responseShapes() throws {
        let sent = try MoyeotaJSON.decoder.decode(
            PasswordResetSendResponse.self,
            from: Data(
                #"{"requestId":"abc","expiresIn":180,"resendAfter":60,"message":"입력한 정보가 가입 정보와 일치하면 인증번호가 발송됩니다."}"#
                    .utf8
            )
        )
        #expect(sent.requestId == "abc")
        #expect(sent.expiresIn == 180)
        #expect(sent.resendAfter == 60)

        // message 는 앱이 읽지 않는다 — 서버가 빼더라도 접수가 깨지면 안 된다.
        let withoutMessage = try MoyeotaJSON.decoder.decode(
            PasswordResetSendResponse.self,
            from: Data(#"{"requestId":"abc","expiresIn":180,"resendAfter":60}"#.utf8)
        )
        #expect(withoutMessage.message == nil)

        let verified = try MoyeotaJSON.decoder.decode(
            PasswordResetVerifyResponse.self,
            from: Data(#"{"resetToken":"tok","expiresIn":600}"#.utf8)
        )
        #expect(verified == PasswordResetVerifyResponse(resetToken: "tok", expiresIn: 600))

        let found = try MoyeotaJSON.decoder.decode(FindLoginIdResponse.self, from: Data(#"{"loginId":"moyeota"}"#.utf8))
        #expect(found.loginId == "moyeota")
    }

    // ── 아이디 찾기 ──

    @Test("아이디 찾기 발송은 하이픈을 뗀 번호로 나간다")
    func findIdSendNormalizes() async throws {
        let api = RecoveryFakeAuthApi()

        try await repository(api).sendFindLoginIdCode(phoneNumber: "010-1234-5678")

        #expect(api.findIdSendRequest.value == SmsSendRequestDto(phoneNumber: "01012345678"))
    }

    /// 가입 발송의 409 `USER104`(이미 가입)와 뜻이 정반대다 — 여기서는 **가입이 안 된** 번호를 끊는다.
    /// 404 라 코드를 놓치면 unknown(「잠시 후 다시」)으로 떨어져 같은 번호를 계속 넣어 보게 된다.
    @Test("아이디 찾기 발송 404 USER114 는 가입되지 않은 번호로 올라온다")
    func findIdSend404() async {
        let api = RecoveryFakeAuthApi(
            failure: httpException(404, #"{"code":"USER114","message":"가입되지 않은 사용자입니다."}"#)
        )
        let repository = await repository(api)

        let thrown = await #expect(throws: AuthException.self) {
            try await repository.sendFindLoginIdCode(phoneNumber: "01012345678")
        }

        #expect(thrown?.error == .phoneNotRegistered)
        #expect(thrown?.error != .unknown)
    }

    @Test("아이디 찾기 확인은 아이디 전체를 돌려주고 번호와 코드를 다듬어 싣는다")
    func findIdVerify() async throws {
        let api = RecoveryFakeAuthApi(loginId: "moyeota_test")

        let loginId = try await repository(api).findLoginId(phoneNumber: "010-1234-5678", code: " 123456 ")

        #expect(loginId == "moyeota_test")
        #expect(api.findIdVerifyRequest.value == SmsVerifyRequestDto(phoneNumber: "01012345678", code: "123456"))
    }

    @Test("아이디 찾기 응답에 아이디가 없으면 실패로 끊는다")
    func findIdVerifyWithoutLoginId() async {
        let repository = await repository(RecoveryFakeAuthApi(loginId: ""))

        let thrown = await #expect(throws: AuthException.self) {
            try await repository.findLoginId(phoneNumber: "01012345678", code: "123456")
        }

        #expect(thrown?.error == .unknown)
    }

    @Test("아이디 찾기 확인 실패는 가입 인증과 같은 코드로 갈린다")
    func findIdVerifyFailures() async {
        let cases: [(Int, String, AuthError)] = [
            (400, "USER204", .smsCodeExpired),
            (400, "USER205", .smsCodeMismatch),
            (429, "USER206", .smsTooManyAttempts),
        ]
        for (status, code, expected) in cases {
            let repository = await repository(
                RecoveryFakeAuthApi(failure: httpException(status, #"{"code":"\#(code)","message":"m"}"#))
            )
            let thrown = await #expect(throws: AuthException.self) {
                try await repository.findLoginId(phoneNumber: "01012345678", code: "123456")
            }
            #expect(thrown?.error == expected)
        }
    }

    // ── 비밀번호 재설정 ──

    @Test("재설정 요청은 아이디와 정규화한 번호를 싣고 접수 결과를 초 단위로 넘긴다")
    func resetSend() async throws {
        let api = RecoveryFakeAuthApi()

        let ticket = try await repository(api).requestPasswordReset(loginId: " moyeota ", phoneNumber: "010-1234-5678")

        #expect(api.resetSendRequest.value == PasswordResetSendRequestDto(loginId: "moyeota", phoneNumber: "01012345678"))
        #expect(ticket == PasswordResetTicket(requestId: REQUEST_ID, expiresInSeconds: 180, resendAfterSeconds: 60))
    }

    /// 0 이하를 그대로 넘기면 화면이 입력칸을 열자마자 「만료됐어요」를 그린다.
    @Test("재설정 접수의 시간 값이 0 이하면 정책 상수로 메운다")
    func resetSendFillsMissingTimes() async throws {
        let api = RecoveryFakeAuthApi(sendResponse: PasswordResetSendResponse(requestId: REQUEST_ID, expiresIn: 0, resendAfter: 0))

        let ticket = try await repository(api).requestPasswordReset(loginId: "moyeota", phoneNumber: "01012345678")

        #expect(ticket.expiresInSeconds == AuthPolicy.SMS_CODE_TTL_SECONDS)
        #expect(ticket.resendAfterSeconds == AuthPolicy.SMS_RESEND_COOLDOWN_SECONDS)
    }

    @Test("재설정 접수 응답에 접수번호가 없으면 실패로 끊는다")
    func resetSendWithoutRequestId() async {
        let api = RecoveryFakeAuthApi(sendResponse: PasswordResetSendResponse(requestId: "", expiresIn: 180, resendAfter: 60))
        let repository = await repository(api)

        let thrown = await #expect(throws: AuthException.self) {
            try await repository.requestPasswordReset(loginId: "moyeota", phoneNumber: "01012345678")
        }

        #expect(thrown?.error == .unknown)
    }

    @Test("재설정 확인은 접수번호와 코드를 싣고 토큰을 돌려준다")
    func resetVerify() async throws {
        let api = RecoveryFakeAuthApi()

        let token = try await repository(api).verifyPasswordResetCode(requestId: REQUEST_ID, code: " 123456 ")

        #expect(token == RESET_TOKEN)
        #expect(api.resetVerifyRequest.value == PasswordResetVerifyRequestDto(requestId: REQUEST_ID, code: "123456"))
    }

    /// 비밀번호를 다듬으면 사용자가 정한 값과 저장된 값이 달라진다 — 로그인은 입력을 그대로 보낸다.
    @Test("새 비밀번호는 다듬지 않고 그대로 싣는다")
    func resetConfirmKeepsPassword() async throws {
        let api = RecoveryFakeAuthApi()

        try await repository(api).confirmPasswordReset(
            resetToken: RESET_TOKEN,
            newPassword: " Passw0rd! ",
            newPasswordConfirm: " Passw0rd! "
        )

        #expect(
            api.resetConfirmRequest.value == PasswordResetConfirmRequestDto(
                resetToken: RESET_TOKEN,
                newPassword: " Passw0rd! ",
                newPasswordConfirm: " Passw0rd! "
            )
        )
    }

    /// 400 이 다섯이라 상태 코드 폴백(`invalidRequest`)으로는 하나도 갈리지 않는다 — 화면 대응이 전부 다르다.
    @Test("재설정 오류 코드는 하나씩 제 사유로 올라온다")
    func resetErrorCodes() {
        let cases: [(Int, String, AuthError)] = [
            (400, "USER301", .passwordResetCodeRejected),
            (400, "USER302", .passwordResetTokenInvalid),
            (400, "USER303", .passwordConfirmMismatch),
            (400, "USER304", .passwordPolicyViolation),
            (400, "USER305", .samePassword),
            (429, "USER306", .passwordResetRateLimited),
            (503, "USER307", .smsUnavailable),
        ]
        for (status, code, expected) in cases {
            let exception = httpException(status, #"{"code":"\#(code)","message":"m"}"#).toAuthException()
            #expect(exception.error == expected, "\(code)")
        }
    }

    /// 사유는 없어도 남은 초는 온다 — 화면이 「곧 풀린다」와 「한참 걸린다」를 가르는 유일한 근거다.
    @Test("429 의 Retry-After 를 초로 읽어 올린다")
    func retryAfterHeader() {
        func exception(_ header: [String: String]) -> AuthException {
            HttpException(
                Response<Void>.error(429, bytes: Data(#"{"code":"USER306","message":"m"}"#.utf8), headers: header)
            ).toAuthException()
        }

        #expect(exception(["Retry-After": "42"]).retryAfterSeconds == 42)
        #expect(exception(["retry-after": " 7 "]).retryAfterSeconds == 7, "헤더 이름은 대소문자를 가리지 않는다")
        #expect(exception([:]).retryAfterSeconds == nil)
        #expect(exception(["Retry-After": "0"]).retryAfterSeconds == nil)
        #expect(exception(["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"]).retryAfterSeconds == nil)
    }

    /// IP 제한은 필터가 직접 본문을 쓴다(`PasswordResetRequestFilter`) — 컨트롤러를 거치지 않아도 같은 모양이다.
    @Test("재설정 요청 429 는 제한으로 올라온다")
    func resetSend429() async {
        let api = RecoveryFakeAuthApi(
            failure: httpException(429, #"{"code":"USER306","message":"잠시 후 다시 시도해 주세요."}"#)
        )
        let repository = await repository(api)

        let thrown = await #expect(throws: AuthException.self) {
            try await repository.requestPasswordReset(loginId: "moyeota", phoneNumber: "01012345678")
        }

        #expect(thrown?.error == .passwordResetRateLimited)
    }
}

private let REQUEST_ID = String(repeating: "r", count: 43)
private let RESET_TOKEN = String(repeating: "t", count: 43)

private final class RecoveryFakeAuthApi: AuthApi {
    private let failure: (any Error)?
    private let loginId: String
    private let sendResponse: PasswordResetSendResponse

    let findIdSendRequest = Locked<SmsSendRequestDto?>(nil)
    let findIdVerifyRequest = Locked<SmsVerifyRequestDto?>(nil)
    let resetSendRequest = Locked<PasswordResetSendRequestDto?>(nil)
    let resetVerifyRequest = Locked<PasswordResetVerifyRequestDto?>(nil)
    let resetConfirmRequest = Locked<PasswordResetConfirmRequestDto?>(nil)

    init(
        failure: (any Error)? = nil,
        loginId: String = "moyeota",
        sendResponse: PasswordResetSendResponse = PasswordResetSendResponse(
            requestId: REQUEST_ID,
            expiresIn: 180,
            resendAfter: 60,
            message: "입력한 정보가 가입 정보와 일치하면 인증번호가 발송됩니다."
        )
    ) {
        self.failure = failure
        self.loginId = loginId
        self.sendResponse = sendResponse
    }

    func sendFindLoginIdCode(request: SmsSendRequestDto) async throws {
        findIdSendRequest.value = request
        if let failure { throw failure }
    }

    func findLoginId(request: SmsVerifyRequestDto) async throws -> FindLoginIdResponse {
        findIdVerifyRequest.value = request
        if let failure { throw failure }
        return FindLoginIdResponse(loginId: loginId)
    }

    func sendPasswordResetCode(request: PasswordResetSendRequestDto) async throws -> PasswordResetSendResponse {
        resetSendRequest.value = request
        if let failure { throw failure }
        return sendResponse
    }

    func verifyPasswordResetCode(request: PasswordResetVerifyRequestDto) async throws -> PasswordResetVerifyResponse {
        resetVerifyRequest.value = request
        if let failure { throw failure }
        return PasswordResetVerifyResponse(resetToken: RESET_TOKEN, expiresIn: 600)
    }

    func confirmPasswordReset(request: PasswordResetConfirmRequestDto) async throws {
        resetConfirmRequest.value = request
        if let failure { throw failure }
    }

    // 아래는 이 테스트가 건드리지 않는 경로다.
    func sendSmsCode(request: SmsSendRequestDto) async throws { throw unused() }
    func verifySmsCode(request: SmsVerifyRequestDto) async throws -> SmsVerifyResponse { throw unused() }
    func register(request: RegisterRequestDto) async throws -> RegisterResponse { throw unused() }
    func login(request: LoginRequestDto) async throws -> TokenResponse { throw unused() }
    func reissue(request: RefreshTokenRequestDto) async throws -> Response<TokenResponse> { throw unused() }
    func logout(request: RefreshTokenRequestDto) async throws { throw unused() }
    func checkNickname(request: NicknameCheckRequestDto) async throws -> NicknameCheckResponse { throw unused() }
    func checkPhone(request: PhoneCheckRequestDto) async throws -> PhoneCheckResponse { throw unused() }

    private func unused() -> IllegalStateException { IllegalStateException("이 테스트가 부르지 않는 경로") }
}

private struct RecoveryEmptyPartyStorage: ActivePartyStorage {
    func load() async throws -> RememberedParty? { nil }
    func save(party: RememberedParty) async throws {}
    func clear() async throws {}
}

/// 아이디 찾기·재설정은 로그인 전 흐름이라 Bearer 가 붙는 `UserApi` 를 한 번도 부르지 않는다.
private struct RecoveryUnusedUserApi: UserApi {
    static let shared = RecoveryUnusedUserApi()

    func getMyProfile() async throws -> UserProfileResponse { throw unused() }
    func updateProfile(request: UpdateProfileRequest) async throws { throw unused() }
    func getProfileImages() async throws -> [ProfileImageResponse] { throw unused() }
    func resetProfileImage() async throws { throw unused() }
    func registerFcmToken(request: FcmTokenRequest) async throws { throw unused() }
    func deleteFcmToken() async throws { throw unused() }
    func deleteAccount(request: AccountDeletionRequest) async throws { throw unused() }
    func getMyRideRecords(cursor: Int64?, size: Int) async throws -> RideRecordPageResponse { throw unused() }

    private func unused() -> IllegalStateException { IllegalStateException("로그인 전 흐름은 UserApi 를 부르지 않는다") }
}
