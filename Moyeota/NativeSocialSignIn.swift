import GoogleSignIn
import MoyeotaDomain
import PresentationCore
import UIKit

@MainActor
final class NativeSocialSignIn {
    static let shared = NativeSocialSignIn()
    private init() {
        // 인증 중 프로세스가 종료됐어도 다음 실행에 SDK 보관 자격증명을 지운다.
        GIDSignIn.sharedInstance.signOut()
    }
    var authentication: NativeSocialAuthentication {
        NativeSocialAuthentication(google: { try await Self.shared.google() })
    }
    private func topPresenter() throws -> UIViewController {
        guard
            let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow),
            var presenter = window.rootViewController
        else { throw AuthException(error: .unknown) }
        while let next = presenter.presentedViewController { presenter = next }
        return presenter
    }
    func google() async throws -> String {
        let presenter = try topPresenter()
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
}
