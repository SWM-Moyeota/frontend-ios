import MoyeotaDomain
import PresentationCore
import Testing

@testable import FeatureAuth

@Suite struct SocialLoginMessageTest {
    /// 서버 원문은 「지금은 로그인을 진행할 수 없습니다. 잠시 후 다시 시도해 주세요.」(503 `USER404`)다.
    /// 인증 거절 문구로 합치면 사용자가 고칠 수 없는 장애에 로그인만 반복한다.
    @Test("일시 장애는 인증 거절과 다른 말로 기다리라고 안내한다")
    func unavailableAsksToWait() {
        let unavailable = authErrorMessage(error: .socialUnavailable)
        #expect(unavailable.contains("잠시 후 다시 시도해 주세요"))
        #expect(unavailable != authErrorMessage(error: .socialRejected))
        #expect(!unavailable.contains("확인하지 못했어요"))
        let failure = AuthException(error: .socialUnavailable, serverMessage: "지금은 로그인을 진행할 수 없습니다. 잠시 후 다시 시도해 주세요.")
        for provider in SocialProvider.allCases {
            #expect(socialLoginFailureMessage(error: failure, provider: provider) == unavailable)
        }
    }

    /// 서버는 이메일을 공유하지 않은 신규 Apple 계정을 `USER401` 로 거절한다.
    /// 같은 코드에 토큰 위조·만료도 있어 단정하지 않고 가능성으로만 말한다.
    @Test("Apple 로그인이 거절되면 기존 문구에 이메일 공유 가능성을 덧붙인다")
    func appleRejectionHintsEmail() {
        let base = authErrorMessage(error: .socialRejected)
        let message = socialLoginFailureMessage(error: AuthException(error: .socialRejected), provider: .apple)
        #expect(message.hasPrefix(base))
        #expect(message.contains("Apple") && message.contains("이메일 공유"))
        #expect(message.contains("수 있어요"))
    }

    @Test("Google 로그인의 거절 문구는 그대로다")
    func googleRejectionUnchanged() {
        let message = socialLoginFailureMessage(error: AuthException(error: .socialRejected), provider: .google)
        #expect(message == authErrorMessage(error: .socialRejected))
        #expect(!message.contains("이메일"))
    }

    @Test("Apple 경로라도 거절이 아닌 실패에는 이메일 안내를 붙이지 않는다")
    func appleOtherFailuresUnchanged() {
        struct Unrelated: Error {}
        for error in AuthError.allCases where error != .socialRejected {
            let failure = AuthException(error: error)
            #expect(socialLoginFailureMessage(error: failure, provider: .apple) == failure.authUserMessage(), "\(error)")
        }
        #expect(socialLoginFailureMessage(error: Unrelated(), provider: .apple) == Unrelated().authUserMessage())
    }
}
