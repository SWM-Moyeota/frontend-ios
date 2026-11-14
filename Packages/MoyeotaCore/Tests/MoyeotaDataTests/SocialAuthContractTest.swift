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
    @Test("가입 대기에서는 세션을 열지 않고 누락된 이름과 이메일을 그대로 보존한다")
    func pendingSignup() async throws {
        let server = StubServer(
            body: #"{"status":"SIGNUP_REQUIRED","signupToken":"pending","email":"user@example.com","name":null}"#
        )
        let (repository, session) = try await repository(server)
        let result = try await repository.loginGoogle(idToken: "google-id-token")
        #expect(result == .signupRequired(.init(signupToken: "pending", email: "user@example.com", name: nil)))
        #expect(session.authState.value == .unauthenticated)
        #expect(server.requests.first?.path == "/api/v1/auth/login/google")
        #expect(server.requests.first?.bodyString?.contains("google-id-token") == true)
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
        #expect(publicServer.requests.isEmpty)
        #expect(
            userServer.requests.map(\.path) == [
                "/api/v1/users/me/login-methods/sms/send", "/api/v1/users/me/login-methods/google",
            ])
        #expect(userServer.requests[0].body == nil)
        let body = try #require(userServer.requests[1].body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object["verificationToken"] == "verified")
    }
    @Test("인증 로그는 요청과 응답의 공급자 토큰을 남기지 않는다")
    func logsAreRedacted() async throws {
        let lines = Locked<[String]>([])
        let interceptor = HttpLoggingInterceptor { line in lines.update { $0.append(line) } }
        var request = URLRequest(url: URL(string: "https://example.invalid/api/v1/auth/login/google")!)
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

    // ── 서버 계약 고정: 경로·메서드·본문 필드명 ──

    private func jsonObject(_ request: RecordedRequest) throws -> [String: String] {
        let body = try #require(request.body)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    }
    private func sessionTokens() -> String {
        let payload = Data(#"{"sub":"social-user"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "\"accessToken\":\"header.\(payload).signature\",\"refreshToken\":\"refresh\""
    }
    private func httpException(_ code: Int, _ body: String) -> HttpException {
        HttpException(Response<Void>.error(code, body))
    }

    @Test("Google 로그인은 /auth/login/google 에 idToken 하나만 POST 한다")
    func googleLoginRequest() async throws {
        let server = StubServer(body: "{\"status\":\"LOGIN\",\(sessionTokens())}")
        let (repository, _) = try await repository(server)
        _ = try await repository.loginGoogle(idToken: "google-id-token")
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/auth/login/google")
        #expect(try jsonObject(request) == ["idToken": "google-id-token"])
    }
    @Test("소셜 가입은 /auth/social/register 에 POST 한다")
    func socialRegisterRequest() async throws {
        let server = StubServer(body: "{\(sessionTokens())}")
        let (repository, session) = try await repository(server)
        try await repository.registerSocial(
            SocialRegistration(
                signupToken: "pending", verificationToken: "verified", phoneNumber: "010-1234-5678", nickname: "별명",
                name: "이름", birthDate: "2000-01-01T00:00:00Z", gender: "MALE"))
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/auth/social/register")
        #expect(try jsonObject(request)["signupToken"] == "pending")
        #expect(session.isLoggedIn)
    }
    @Test("로그인 수단 조회는 GET /users/me/login-methods 이고 REVOKED 수단도 읽는다")
    func loginMethodsRequest() async throws {
        let server = StubServer(
            body:
                #"{"hasPassword":true,"methods":[{"provider":"GOOGLE","status":"ACTIVE"},{"provider":"APPLE","status":"REVOKED"}]}"#
        )
        let api = SocialAuthApi(auth: try StubServer(status: 500).rest(), user: try server.rest())
        let methods = try await api.methods()
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/api/v1/users/me/login-methods")
        #expect(request.body == nil)
        #expect(methods.hasPassword)
        // 앱은 Google 만 제공한다. APPLE 항목은 모르는 provider 로 걸러지고 응답 전체는 그대로 읽힌다.
        #expect(methods.methods.map(\.provider) == [.google])
        #expect(methods.methods.map(\.status) == ["ACTIVE"])
    }
    /// 이 응답 하나로 로그인 수단 화면과 탈퇴 화면(`hasPassword`)이 모두 열린다.
    /// 모르는 수단 하나 때문에 전체 디코딩이 실패하면 탈퇴 화면에도 들어갈 수 없다.
    @Test("모르는 provider 는 건너뛰고 hasPassword 와 아는 수단은 그대로 읽는다")
    func unknownProviderIsSkipped() throws {
        let methods = try JSONDecoder().decode(
            LoginMethods.self,
            from: Data(
                #"{"hasPassword":false,"methods":[{"provider":"KAKAO","status":"ACTIVE"},{"provider":"APPLE","status":"ACTIVE"},{"provider":"GOOGLE","status":"REVOKED"}]}"#
                    .utf8))
        #expect(!methods.hasPassword)
        #expect(methods.methods.map(\.provider) == [.google])
        #expect(methods.methods.map(\.status) == ["REVOKED"])
        // APPLE 하나만 와도 화면이 열려야 한다 — 빈 목록으로 읽고 실패하지 않는다.
        let appleOnly = try JSONDecoder().decode(
            LoginMethods.self,
            from: Data(#"{"hasPassword":false,"methods":[{"provider":"APPLE","status":"ACTIVE"}]}"#.utf8))
        #expect(!appleOnly.hasPassword && appleOnly.methods.isEmpty)
        // 건너뛰는 것은 모르는 provider 뿐이다 — 형식이 깨진 응답까지 삼키지 않는다.
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                LoginMethods.self, from: Data(#"{"hasPassword":true,"methods":[{"provider":"GOOGLE"}]}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LoginMethods.self, from: Data(#"{"methods":[]}"#.utf8))
        }
    }
    @Test("연결용 문자 확인은 /users/me/login-methods/sms/verify 에 code 하나만 POST 한다")
    func linkCodeVerifyRequest() async throws {
        let server = StubServer(body: #"{"verificationToken":"verified"}"#)
        let api = SocialAuthApi(auth: try StubServer(status: 500).rest(), user: try server.rest())
        #expect(try await api.verifyCode("123456").verificationToken == "verified")
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/users/me/login-methods/sms/verify")
        #expect(try jsonObject(request) == ["code": "123456"])
    }
    @Test("연결 요청은 모두 POST 이고 Google 연결 본문은 idToken 과 verificationToken 이다")
    func linkRequests() async throws {
        let server = StubServer(status: 204)
        let api = SocialAuthApi(auth: try StubServer(status: 500).rest(), user: try server.rest())
        try await api.sendCode()
        try await api.linkGoogle(.init(idToken: "google", verificationToken: "verified"))
        #expect(server.requests.map(\.method) == ["POST", "POST"])
        #expect(try jsonObject(server.requests[1]) == ["idToken": "google", "verificationToken": "verified"])
    }

    // ── 서버 계약 고정: 오류 코드 ──

    /// 상태 코드만으로는 갈리지 않는다 — 401 이 넷(401·402·406·407)이고 화면의 대응이 서로 다르다.
    @Test("USER401~USER407 은 서로 다른 사유로 갈린다")
    func socialErrorCodes() {
        let cases: [(Int, String, AuthError)] = [
            (401, "USER401", .socialRejected), (401, "USER402", .socialSignupExpired),
            (409, "USER403", .socialAlreadyRegistered), (503, "USER404", .socialUnavailable),
            (409, "USER405", .socialLinkConflict), (401, "USER406", .socialVerificationExpired),
            (401, "USER407", .socialChallengeInvalid),
        ]
        for (status, code, expected) in cases {
            let failure = httpException(status, "{\"code\":\"\(code)\",\"message\":\"서버 문구\"}").toAuthException()
            #expect(failure.error == expected, "\(code)")
            #expect(failure.serverMessage == "서버 문구", "\(code)")
        }
        #expect(Set(cases.map(\.2)).count == cases.count)
    }
    /// 공급자·인증 저장소의 일시 장애(503)다. 「인증을 확인하지 못했다」로 합치면 사용자가 로그인만 반복한다.
    @Test("USER404 일시 장애는 저장소를 거쳐도 인증 거절과 구분된다")
    func socialUnavailable() async throws {
        let server = StubServer(
            status: 503, body: #"{"code":"USER404","message":"지금은 로그인을 진행할 수 없습니다. 잠시 후 다시 시도해 주세요."}"#)
        let (repository, session) = try await repository(server)
        let failure = await #expect(throws: AuthException.self) { try await repository.loginGoogle(idToken: "google") }
        #expect(failure?.error == .socialUnavailable)
        #expect(!session.isLoggedIn)
    }
}

private struct SocialTestPartyStorage: ActivePartyStorage {
    func load() async throws -> RememberedParty? { nil }
    func save(party: RememberedParty) async throws {}
    func clear() async throws {}
}
