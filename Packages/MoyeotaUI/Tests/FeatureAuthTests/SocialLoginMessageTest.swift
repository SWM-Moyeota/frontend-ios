import Foundation
import MoyeotaDomain
import PresentationCore
import Testing

@testable import FeatureAuth

/// 소셜 로그인(Google) 실패 문구. `SocialLoginRoute` 는 `authUserMessage()` 를 그대로 보여 준다.
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
        #expect(failure.authUserMessage() == unavailable)
    }

    @Test("Google 로그인의 거절 문구는 그대로다")
    func googleRejectionUnchanged() {
        let message = AuthException(error: .socialRejected).authUserMessage()
        #expect(message == authErrorMessage(error: .socialRejected))
        #expect(!message.contains("이메일"))
    }

    /// 앱은 Google 로그인만 제공한다(2026-11-15). 서버 코드 매핑은 남아 있어도 문구가 Apple 을 말하면 안 된다.
    @Test("어떤 인증 오류 문구에도 Apple 이 나오지 않는다")
    func noMessageMentionsApple() {
        for error in AuthError.allCases {
            let message = authErrorMessage(error: error)
            #expect(!message.localizedCaseInsensitiveContains("apple") && !message.contains("애플"), "\(error)")
        }
    }
}
