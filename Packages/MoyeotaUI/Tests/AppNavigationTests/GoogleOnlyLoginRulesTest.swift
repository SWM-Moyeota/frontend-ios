import Foundation
import Testing

/// 소셜 로그인은 Google 만 제공한다는 **제품 결정**(2026-11-15)을 못 박는다.
///
/// Apple 로그인 버튼·연결 버튼·안내 문구가 로그인 화면과 로그인 수단 화면에 다시 들어오면 실패한다.
/// 소스를 문자열로 읽는 테스트다 — 깨지면 정규식을 고치기 전에 **결정이 바뀌었는지** 먼저 확인하라.
@Suite struct GoogleOnlyLoginRulesTest {
    /// 로그인·가입 화면(`FeatureAuth`), 마이페이지(`FeatureMyPage`), SDK 주입 입구와 인증 오류 문구.
    private static let scopes = ["FeatureAuth", "FeatureMyPage"]
    private static let files = ["PresentationCore/SocialAuthentication.swift", "PresentationCore/AuthUserMessage.swift"]

    private func swiftSources() throws -> [(path: String, text: String)] {
        var paths = Self.files
        for scope in Self.scopes {
            let names = try FileManager.default.contentsOfDirectory(
                atPath: SourceTree.root.appendingPathComponent(scope).path)
            paths += names.filter { $0.hasSuffix(".swift") }.sorted().map { "\(scope)/\($0)" }
        }
        return try paths.map { path in
            (path, try #require(SourceTree.read(path), "소스 파일이 없다: \(path)"))
        }
    }

    @Test("로그인 화면과 로그인 수단 화면 소스에 Apple 진입점·문구가 없다")
    func noAppleEntryPoint() throws {
        let sources = try swiftSources()
        // 화면 파일이 실제로 검사 대상에 들어 있어야 「없다」가 뜻을 가진다.
        for required in [
            "FeatureAuth/LoginScreen.swift", "FeatureAuth/LoginFormScreen.swift", "FeatureAuth/SocialLoginRoute.swift",
            "FeatureMyPage/LoginMethodsScreen.swift",
        ] {
            #expect(sources.contains { $0.path == required }, "검사 대상에서 빠졌다: \(required)")
        }
        for (path, text) in sources {
            #expect(!SourceTree.contains("(?i)apple|애플", in: text), "Apple 로그인 흔적이 있다: \(path)")
        }
    }

    @Test("Google 진입점은 그대로 있다")
    func googleEntryPointsRemain() throws {
        let login = try #require(SourceTree.read("FeatureAuth/LoginScreen.swift"))
        #expect(login.contains("Button(\"구글로 회원가입하기\", action: onGoogle)"))
        let form = try #require(SourceTree.read("FeatureAuth/LoginFormScreen.swift"))
        #expect(form.contains("Button(\"Google로 로그인\", action: onSocialLogin)"))
        let route = try #require(SourceTree.read("FeatureAuth/SocialLoginRoute.swift"))
        #expect(route.contains("social.loginGoogle(idToken: native.google())"))
        let methods = try #require(SourceTree.read("FeatureMyPage/LoginMethodsScreen.swift"))
        #expect(methods.contains("Button(\"Google 연결\") { connectGoogle() }"))
        #expect(methods.contains("repository.linkGoogle(idToken: native.google(), verificationToken: token)"))
        // 연결 버튼은 Google 하나뿐이다 — provider 를 돌며 버튼을 만드는 구조로 되돌아가지 않는다.
        #expect(!methods.contains("SocialProvider.allCases"))
    }
}
