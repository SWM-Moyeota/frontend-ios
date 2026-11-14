import Foundation

public enum SocialProvider: String, Codable, CaseIterable, Sendable {
    case google = "GOOGLE"
    case apple = "APPLE"
}
public struct AppleChallenge: Codable, Equatable, Sendable {
    public let challengeToken: String
    public let nonce: String
    public let expiresInSeconds: Int
}
public struct AppleCredential: Sendable {
    public let identityToken: String
    public let authorizationCode: String
    public let name: String?
    public init(identityToken: String, authorizationCode: String, name: String?) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.name = name
    }
}
/// 가입 대기표는 메모리에만 보관한다. 이메일은 표시용이며 가입 요청에 다시 보내지 않는다.
public struct SocialSignup: Equatable, Sendable {
    public let signupToken: String
    public let email: String?
    public let name: String?
    public init(signupToken: String, email: String?, name: String?) {
        self.signupToken = signupToken
        self.email = email
        self.name = name
    }
}
public enum SocialLoginResult: Equatable, Sendable {
    case loggedIn
    case signupRequired(SocialSignup)
}
public struct LoginMethods: Codable, Equatable, Sendable {
    public struct Method: Codable, Equatable, Sendable {
        public let provider: SocialProvider
        public let status: String
    }
    public let hasPassword: Bool
    public let methods: [Method]
}
public struct SocialRegistration: Encodable, Sendable {
    public let signupToken: String
    public let verificationToken: String
    public let phoneNumber: String
    public let nickname: String
    public let name: String
    public let birthDate: String
    public let gender: String
    public init(
        signupToken: String, verificationToken: String, phoneNumber: String, nickname: String, name: String,
        birthDate: String, gender: String
    ) {
        self.signupToken = signupToken
        self.verificationToken = verificationToken
        self.phoneNumber = AuthPolicy.normalizePhoneNumber(value: phoneNumber)
        self.nickname = nickname
        self.name = name
        self.birthDate = birthDate
        self.gender = gender
    }
}
public protocol SocialAuthRepository: Sendable {
    func loginGoogle(idToken: String) async throws -> SocialLoginResult
    func appleChallenge(linking: Bool) async throws -> AppleChallenge
    func loginApple(credential: AppleCredential, challengeToken: String) async throws -> SocialLoginResult
    func registerSocial(_ registration: SocialRegistration) async throws
    func loginMethods() async throws -> LoginMethods
    func sendLinkCode() async throws
    func verifyLinkCode(_ code: String) async throws -> String
    func linkGoogle(idToken: String, verificationToken: String) async throws
    func linkApple(credential: AppleCredential, challengeToken: String, verificationToken: String) async throws
    func deleteSocialAccount() async throws
}
