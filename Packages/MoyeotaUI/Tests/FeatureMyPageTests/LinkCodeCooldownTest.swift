import Foundation
import MoyeotaDomain
import PresentationCore
import Testing

@testable import FeatureMyPage

/// 로그인 수단 화면의 연결용 문자 재발송 잠금. 서버가 가입용·연결용 문자의 쿨다운(1분)을 함께 세므로
/// 가입 직후 들어오면 첫 발송부터 429 `USER202` 다 — 문구가 가리키는 「버튼의 남은 시간」이 실제로 있어야 한다.
@Suite struct LinkCodeCooldownTest {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("처음에는 잠겨 있지 않다")
    func initiallyUnlocked() {
        #expect(LinkCodeCooldown().remainingSeconds(now: now) == 0)
    }

    @Test("발송에 성공하면 쿨다운 동안 잠그고 남은 초를 센다")
    func locksAfterSend() {
        var cooldown = LinkCodeCooldown()
        cooldown.onSent(now: now)
        #expect(cooldown.remainingSeconds(now: now) == AuthPolicy.SMS_RESEND_COOLDOWN_SECONDS)
        #expect(cooldown.remainingSeconds(now: now.addingTimeInterval(18.2)) == 42)
        #expect(cooldown.remainingSeconds(now: now.addingTimeInterval(59.5)) == 1)
        #expect(cooldown.remainingSeconds(now: now.addingTimeInterval(60)) == 0)
        #expect(cooldown.remainingSeconds(now: now.addingTimeInterval(600)) == 0)
    }

    @Test("USER202 에 남은 시간이 없으면 쿨다운 최대치로 잠근다")
    func cooldownWithoutRetryAfter() {
        var cooldown = LinkCodeCooldown()
        cooldown.onFailure(AuthException(error: .smsCooldown), now: now)
        #expect(cooldown.remainingSeconds(now: now) == 60)
    }

    @Test("USER202 가 준 Retry-After 만큼만 잠근다")
    func cooldownUsesRetryAfter() {
        var cooldown = LinkCodeCooldown()
        cooldown.onFailure(AuthException(error: .smsCooldown, retryAfterSeconds: 23), now: now)
        #expect(cooldown.remainingSeconds(now: now) == 23)
        #expect(cooldown.remainingSeconds(now: now.addingTimeInterval(23)) == 0)
    }

    @Test("남은 시간을 모르는 USER202 는 이미 걸린 잠금을 줄이지 않는다")
    func unknownRetryAfterNeverShortens() {
        var cooldown = LinkCodeCooldown()
        cooldown.onFailure(AuthException(error: .smsCooldown, retryAfterSeconds: 300), now: now)
        cooldown.onFailure(AuthException(error: .smsCooldown), now: now)
        #expect(cooldown.remainingSeconds(now: now) == 300)
    }

    @Test("쿨다운이 아닌 실패는 버튼을 잠그지 않는다")
    func otherFailuresDoNotLock() {
        struct Unrelated: Error {}
        var cooldown = LinkCodeCooldown()
        for error in AuthError.allCases where error != .smsCooldown {
            cooldown.onFailure(AuthException(error: error, retryAfterSeconds: 30), now: now)
        }
        cooldown.onFailure(Unrelated(), now: now)
        #expect(cooldown.remainingSeconds(now: now) == 0)
    }

    @Test("잠긴 동안 발송 버튼에 남은 초가 보인다")
    func titleShowsRemainingSeconds() {
        #expect(linkCodeSendTitle(sent: false, remainingSeconds: 0) == "등록된 휴대폰으로 인증번호 받기")
        #expect(linkCodeSendTitle(sent: true, remainingSeconds: 0) == "인증번호 다시 받기")
        #expect(linkCodeSendTitle(sent: true, remainingSeconds: 42) == "인증번호 다시 받기 (42초)")
        // 가입 직후처럼 이 화면에서 한 번도 보내지 못한 채 429 를 받은 경우에도 남은 시간이 보여야 한다.
        #expect(linkCodeSendTitle(sent: false, remainingSeconds: 60) == "등록된 휴대폰으로 인증번호 받기 (60초)")
        // 안내 문구가 버튼의 남은 시간을 가리킨다 — 둘이 함께 있어야 말이 된다.
        #expect(authErrorMessage(error: .smsCooldown).contains("버튼의 남은 시간"))
    }
}
