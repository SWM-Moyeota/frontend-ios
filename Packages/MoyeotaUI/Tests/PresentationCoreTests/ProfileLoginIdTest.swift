import Testing
@testable import PresentationCore

/// 36 프로필 수정의 「아이디」 행을 **언제 숨기는가** — `profileLoginIdOrNull`.
///
/// 화면에는 「행이 있다/없다」 두 모양뿐인데, 그 판정이 틀리면 둘 중 하나가 거짓말이 된다:
/// 로컬 로그인이 없는 계정에 빈 「아이디」 행이 보이면 「아이디가 지워졌다」로 읽히고, 로딩 중에
/// 행이 스쳐 보이면 값이 비어 있다. 그래서 숨기는 조건을 순수 함수로 빼 여기서 고정한다.
@Suite struct ProfileLoginIdTest {
    @Test("로컬 로그인 계정이면 아이디를 보여 준다")
    func showsLoginId() {
        #expect(profileLoginIdOrNull(state: .resolved(name: "성윤", loginId: "hong123")) == "hong123")
    }

    @Test("서버가 null 을 주면 행을 숨긴다")
    func hidesWhenServerSendsNull() {
        // 로컬 로그인이 없는 계정(소셜 전용 등) — Backend PR #330 계약
        #expect(profileLoginIdOrNull(state: .resolved(name: "성윤", loginId: nil)) == nil)
        // 기본값도 같다 — 조회 실패·구버전 서버는 loginId 를 채우지 않는다
        #expect(profileLoginIdOrNull(state: .resolved(name: "성윤")) == nil)
    }

    @Test("공백뿐인 아이디는 행을 숨긴다")
    func hidesBlank() {
        #expect(profileLoginIdOrNull(state: .resolved(name: "성윤", loginId: "")) == nil)
        #expect(profileLoginIdOrNull(state: .resolved(name: "성윤", loginId: "   ")) == nil)
    }

    @Test("조회가 끝나기 전에는 행을 숨긴다")
    func hidesWhileLoading() {
        // 로딩 중에 빈 행이 스쳐 보이지 않게 한다(이름·사진의 Loading 처리와 같은 이유)
        #expect(profileLoginIdOrNull(state: .loading) == nil)
    }

    @Test("앞뒤 공백은 떼고 보여 준다")
    func trimsSurroundingSpaces() {
        #expect(profileLoginIdOrNull(state: .resolved(name: nil, loginId: " hong123 ")) == "hong123")
    }
}
