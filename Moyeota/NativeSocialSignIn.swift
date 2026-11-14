import AuthenticationServices
import GoogleSignIn
import MoyeotaDomain
import PresentationCore
import UIKit

@MainActor
final class NativeSocialSignIn: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    static let shared = NativeSocialSignIn()
    private override init() {
        super.init()
        // 인증 중 프로세스가 종료됐어도 다음 실행에 SDK 보관 자격증명을 지운다.
        GIDSignIn.sharedInstance.signOut()
    }
    private var continuation: CheckedContinuation<AppleCredential, any Error>?
    private var controller: ASAuthorizationController?
    private var anchor: UIWindow?
    var authentication: NativeSocialAuthentication {
        NativeSocialAuthentication(
            google: { try await Self.shared.google() }, apple: { try await Self.shared.apple(nonce: $0) })
    }
    private func presentation() throws -> (UIWindow, UIViewController) {
        guard
            let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow),
            var presenter = window.rootViewController
        else { throw AuthException(error: .unknown) }
        while let next = presenter.presentedViewController { presenter = next }
        return (window, presenter)
    }
    func google() async throws -> String {
        let (_, presenter) = try presentation()
        guard let client = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String, !client.isEmpty,
            let server = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String, !server.isEmpty
        else {
            throw AuthException(error: .unknown)
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: client, serverClientID: server)
        // 모여타 세션만 유지한다. SDK 자격증명과 계정 선택은 매 시도마다 정리한다.
        GIDSignIn.sharedInstance.signOut()
        defer { GIDSignIn.sharedInstance.signOut() }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let token = result.user.idToken?.tokenString, !token.isEmpty else {
                throw AuthException(error: .unknown)
            }
            return token
        } catch let error as NSError
            where error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue
        {
            throw CancellationError()
        }
    }
    func apple(nonce: String) async throws -> AppleCredential {
        guard continuation == nil else { throw CancellationError() }
        let (window, _) = try presentation()
        anchor = window
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        // 서버 challenge에 결합된 nonce를 변경하거나 다시 해시하지 않는다.
        request.nonce = nonce
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor! }
    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identity = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
            let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }),
            !identity.isEmpty, !code.isEmpty
        else {
            finish(.failure(AuthException(error: .unknown)))
            return
        }
        let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }.flatMap {
            $0.isEmpty ? nil : $0
        }
        finish(.success(AppleCredential(identityToken: identity, authorizationCode: code, name: name)))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(error))
        }
    }
    private func finish(_ result: Result<AppleCredential, any Error>) {
        let pending = continuation
        continuation = nil
        controller = nil
        anchor = nil
        pending?.resume(with: result)
    }
}
