import Foundation
import MoyeotaDomain
import Testing
@testable import FeatureFareSplit

/// 「토스로 보내기」가 여는 것은 **`supertoss` 스킴 하나뿐**이다 (Android PR #106 리뷰 반영).
///
/// 딥링크는 서버가 준 문자열 그대로 연다. `UIApplication.open` 은 스킴을 가리지 않으므로 검사가 없으면
/// 「송금」 버튼이 서버 문자열 하나로 브라우저(`https`)·다른 앱(`intent:`)·전화(`tel:`)를 여는 버튼이 된다.
/// 열 수 없는 문자열이면 버튼 자체를 그리지 않는다 — 화면은 그때 복사 버튼만 남긴다.
@MainActor
@Suite struct TossDeeplinkTest {

    @Test("supertoss 스킴만 연다")
    func onlySupertoss() {
        #expect(tossDeeplinkURL("supertoss://send?amount=6233&accountNo=3333012345678") != nil)
        // 스킴은 대소문자를 가리지 않는다(RFC 3986).
        #expect(tossDeeplinkURL("SuperToss://send?amount=6233") != nil)
    }

    /// 서버는 은행 이름을 **한글 그대로** 쿼리에 싣는다. 그 문자열이 URL 로 읽히지 않으면 토스 버튼이 영영 뜨지 않는다.
    @Test("쿼리에 한글 은행 이름이 그대로 있어도 열 수 있다")
    func koreanQueryParses() throws {
        let url = try #require(tossDeeplinkURL("supertoss://send?amount=6233&bank=카카오뱅크&accountNo=3333012345678"))

        #expect(url.scheme == "supertoss")
    }

    @Test("다른 스킴이나 읽을 수 없는 문자열은 열지 않는다")
    func rejectsEverythingElse() {
        for deeplink in [
            "https://toss.im/send?amount=6233",
            "http://example.com",
            "intent://send#Intent;scheme=supertoss;package=viva.republica.toss;end",
            "tel:01012345678",
            "kakaotalk://send",
            "supertoss",
            "",
            "   ",
        ] {
            #expect(tossDeeplinkURL(deeplink) == nil, "\(deeplink)")
        }
    }

    /// 열 수 없는 딥링크로 버튼을 그리면 누를 때마다 「토스를 열지 못했어요」가 뜬다 — 처음부터 복사 버튼만 둔다.
    @Test("열 수 없는 딥링크면 토스 버튼을 그리지 않는다")
    func noButtonForForeignScheme() {
        let https = detail(role: .sender, myTransferStatus: .value(.notSent), tossDeeplink: "https://toss.im/send")
        let intent = detail(role: .sender, myTransferStatus: .value(.notSent), tossDeeplink: "intent://send#Intent;end")

        #expect(!showsTossButton(detail: https))
        #expect(!showsTossButton(detail: intent))
        // 같은 조건에 스킴만 맞으면 그린다 — 위 둘이 다른 이유로 꺼진 것이 아님을 보인다.
        let toss = detail(role: .sender, myTransferStatus: .value(.notSent), tossDeeplink: "supertoss://send?amount=6234")
        #expect(showsTossButton(detail: toss))
    }

    /// 화면이 버튼을 감추지만, 여는 함수도 한 번 더 막는다 — 실패는 화면이 「복사해서 보내 주세요」로 받는다.
    @Test("다른 스킴은 열기를 시도하지 않고 실패로 돌려준다")
    func openRefusesForeignScheme() async {
        #expect(await openTossTransfer(deeplink: "https://toss.im/send") == false)
        #expect(await openTossTransfer(deeplink: "") == false)
    }
}
