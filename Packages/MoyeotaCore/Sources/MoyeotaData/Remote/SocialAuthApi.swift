import MoyeotaDomain

struct SocialLoginResponse: Decodable {
    let status: String
    let accessToken: String?
    let refreshToken: String?
    let signupToken: String?
    let email: String?
    let name: String?
}
struct GoogleCredentialRequest: Encodable {
    let idToken: String
    var verificationToken: String? = nil
}
struct AppleCredentialRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let challengeToken: String
    var name: String? = nil
    var verificationToken: String? = nil
}
struct LinkCodeRequest: Encodable { let code: String }

/// 공개 인증 클라이언트와 Bearer 클라이언트를 분리해 재발급 재귀를 방지한다.
struct SocialAuthApi: Sendable {
    let auth: RestClient
    let user: RestClient
    func google(_ request: GoogleCredentialRequest) async throws -> SocialLoginResponse {
        try await auth.call(.POST("api/v1/auth/login/google"), body: request)
    }
    func apple(_ request: AppleCredentialRequest) async throws -> SocialLoginResponse {
        try await auth.call(.POST("api/v1/auth/login/apple"), body: request)
    }
    func challenge(linking: Bool) async throws -> AppleChallenge {
        try await (linking ? user : auth).call(
            .POST(linking ? "api/v1/users/me/login-methods/apple/challenge" : "api/v1/auth/apple/challenge"))
    }
    func register(_ request: SocialRegistration) async throws -> TokenResponse {
        try await auth.call(.POST("api/v1/auth/social/register"), body: request)
    }
    func methods() async throws -> LoginMethods { try await user.call(.GET("api/v1/users/me/login-methods")) }
    func sendCode() async throws { try await user.callUnit(.POST("api/v1/users/me/login-methods/sms/send")) }
    func verifyCode(_ code: String) async throws -> SmsVerifyResponse {
        try await user.call(.POST("api/v1/users/me/login-methods/sms/verify"), body: LinkCodeRequest(code: code))
    }
    func linkGoogle(_ request: GoogleCredentialRequest) async throws {
        try await user.callUnit(.POST("api/v1/users/me/login-methods/google"), body: request)
    }
    func linkApple(_ request: AppleCredentialRequest) async throws {
        try await user.callUnit(.POST("api/v1/users/me/login-methods/apple"), body: request)
    }
    func deleteAccount() async throws { try await user.callUnit(.DELETE("api/v1/users/me")) }
}
