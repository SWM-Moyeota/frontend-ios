import Foundation
import MoyeotaDomain
import Testing

@testable import MoyeotaData

@Suite struct SocialAuthContractTest {
    private func repository(_ server: StubServer) async throws -> (RemoteAuthRepository, SessionManager) {
        let scope = CoroutineScope()
        let session = SessionManager(storage: FakeTokenStorage(nil), scope: scope)
        await scope.join()
        let auth = RestAuthApi(rest: try server.rest())
        let user = RestUserApi(rest: try server.rest())
        return (
            RemoteAuthRepository(
                api: auth, userApi: user, session: session,
                fcmTokenRegistrar: FcmTokenRegistrar(userApi: user, session: session),
                activePartyStorage: SocialTestPartyStorage()), session
        )
    }
    @Test("가입 대기에서는 세션을 열지 않고 Apple의 누락된 이름과 비공개 이메일을 보존한다")
    func pendingSignup() async throws {
        let server = StubServer(
            body:
                #"{"status":"SIGNUP_REQUIRED","signupToken":"pending","email":"hidden@privaterelay.appleid.com","name":null}"#
        )
        let (repository, session) = try await repository(server)
        let result = try await repository.loginApple(
            credential: .init(identityToken: "identity", authorizationCode: "code", name: nil),
            challengeToken: "challenge")
        #expect(
            result
                == .signupRequired(.init(signupToken: "pending", email: "hidden@privaterelay.appleid.com", name: nil)))
        #expect(session.authState.value == .unauthenticated)
        #expect(server.requests.first?.path == "/api/v1/auth/login/apple")
        #expect(server.requests.first?.bodyString?.contains("challenge") == true)
        #expect(server.requests.first?.header("Authorization") == nil)
    }
    @Test("로그인 응답은 기존 세션 저장 경로로 사용자 식별자와 토큰을 저장한다")
    func loggedIn() async throws {
        let payload = Data(#"{"sub":"social-user"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let server = StubServer(
            body: "{\"status\":\"LOGIN\",\"accessToken\":\"header.\(payload).signature\",\"refreshToken\":\"refresh\"}")
        let (repository, session) = try await repository(server)
        #expect(try await repository.loginGoogle(idToken: "google") == .loggedIn)
        #expect(session.isLoggedIn)
    }
    @Test("깨진 로그인 성공 응답은 세션을 열지 않는다")
    func invalidLogin() async throws {
        let server = StubServer(body: #"{"status":"LOGIN","accessToken":"broken","refreshToken":"refresh"}"#)
        let (repository, session) = try await repository(server)
        await #expect(throws: AuthException.self) { try await repository.loginGoogle(idToken: "google") }
        #expect(!session.isLoggedIn)
    }
    @Test("로그인과 연결용 Apple challenge는 서로 다른 경로를 쓰고 서버 nonce를 그대로 읽는다")
    func challengePaths() async throws {
        let server = StubServer(body: #"{"challengeToken":"challenge","nonce":"server-nonce","expiresInSeconds":300}"#)
        let api = SocialAuthApi(auth: try server.rest(), user: try server.rest())
        #expect(try await api.challenge(linking: false).nonce == "server-nonce")
        #expect(try await api.challenge(linking: true).nonce == "server-nonce")
        #expect(
            server.requests.map(\.path) == [
                "/api/v1/auth/apple/challenge", "/api/v1/users/me/login-methods/apple/challenge",
            ])
        #expect(server.requests.allSatisfy { $0.body == nil })
    }
    @Test("소셜 전용 탈퇴는 본문 없이 요청한다")
    func deletionHasNoBody() async throws {
        let server = StubServer(status: 204)
        let api = SocialAuthApi(auth: try server.rest(), user: try server.rest())
        try await api.deleteAccount()
        #expect(server.requests.first?.method == "DELETE")
        #expect(server.requests.first?.body == nil)
    }
    @Test("가입 요청에는 아이디 비밀번호 이메일이 들어가지 않는다")
    func registrationFields() throws {
        let request = SocialRegistration(
            signupToken: "pending", verificationToken: "verified", phoneNumber: "010-1234-5678", nickname: "별명",
            name: "이름", birthDate: "2000-01-01T00:00:00Z", gender: "MALE")
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: String])
        #expect(object["phoneNumber"] == "01012345678")
        #expect(object["password"] == nil && object["loginId"] == nil && object["email"] == nil)
    }
    @Test("계정 연결은 인증 클라이언트만 사용하고 재인증 증표를 전달한다")
    func linkUsesAuthenticatedClient() async throws {
        let publicServer = StubServer(status: 500)
        let userServer = StubServer(status: 204)
        let api = SocialAuthApi(auth: try publicServer.rest(), user: try userServer.rest())
        try await api.sendCode()
        try await api.linkGoogle(.init(idToken: "google", verificationToken: "verified"))
        try await api.linkApple(
            .init(
                identityToken: "apple", authorizationCode: "code", challengeToken: "challenge",
                verificationToken: "verified"))
        #expect(publicServer.requests.isEmpty)
        #expect(
            userServer.requests.map(\.path) == [
                "/api/v1/users/me/login-methods/sms/send", "/api/v1/users/me/login-methods/google",
                "/api/v1/users/me/login-methods/apple",
            ])
        #expect(userServer.requests[0].body == nil)
        let body = try #require(userServer.requests[2].body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object["verificationToken"] == "verified")
        #expect(object["challengeToken"] == "challenge")
    }
    @Test("인증 로그는 요청과 응답의 공급자 토큰을 남기지 않는다")
    func logsAreRedacted() async throws {
        let lines = Locked<[String]>([])
        let interceptor = HttpLoggingInterceptor { line in lines.update { $0.append(line) } }
        var request = URLRequest(url: URL(string: "https://example.invalid/api/v1/auth/login/apple")!)
        request.httpMethod = "POST"
        request.httpBody = Data("secret-identity".utf8)
        request.setValue("Bearer secret-access", forHTTPHeaderField: "Authorization")
        _ = try await interceptor.intercept(
            chain: InterceptorChain(
                request: request,
                next: { request in
                    HttpRawResponse(request: request, code: 200, body: Data("secret-session".utf8))
                }))
        #expect(!lines.value.joined().contains("secret"))
    }
}

private struct SocialTestPartyStorage: ActivePartyStorage {
    func load() async throws -> RememberedParty? { nil }
    func save(party: RememberedParty) async throws {}
    func clear() async throws {}
}
