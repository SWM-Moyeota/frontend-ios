import MoyeotaDomain
import PresentationCore
import Testing

@testable import FeatureAuth

@Suite struct SocialSignupTest {
    @Test("소셜 가입은 아이디 비밀번호 이메일 없이 프로필과 문자 인증만 제출한다")
    func socialDraft() throws {
        var draft = SignupDraft(
            nickname: "별명", name: "홍길동", phoneNumber: "01012345678", birthDate: try LocalDate.of(2000, 1, 1),
            gender: .female, verificationToken: "verified")
        draft.socialSignup = SocialSignup(signupToken: "pending", email: nil, name: nil)
        let registration = try #require(draft.toSocialRegistration())
        #expect(registration.signupToken == "pending")
        #expect(registration.birthDate == "2000-01-01T00:00:00Z")
        #expect(draft.toNewUser() == nil)
    }
    @Test("이름이 오지 않은 소셜 계정도 사용자가 이름을 입력해야 가입할 수 있다")
    func missingName() throws {
        var draft = SignupDraft(
            nickname: "별명", phoneNumber: "01012345678", birthDate: try LocalDate.of(2000, 1, 1), gender: .male,
            verificationToken: "verified")
        draft.socialSignup = SocialSignup(signupToken: "pending", email: "user@example.com", name: nil)
        #expect(draft.toSocialRegistration() == nil)
        draft.name = "홍길동"
        #expect(draft.toSocialRegistration() != nil)
        draft.verificationToken = ""
        #expect(draft.toSocialRegistration() == nil)
    }
}
