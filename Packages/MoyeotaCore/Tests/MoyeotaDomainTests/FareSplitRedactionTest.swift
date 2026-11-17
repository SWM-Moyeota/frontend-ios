import Foundation
import Testing
@testable import MoyeotaDomain

/// (iOS 전용, Android PR #106 리뷰 반영) **계좌번호·딥링크가 로그·디버그 출력으로 새지 않는다.**
///
/// 서버는 계좌번호를 암호화해 저장하고 정산이 끝나면 지운다. 앱이 모델을 `print`·`dump`·`String(reflecting:)`
/// 한 줄로 흘리면 그 보호가 무의미해진다 — 지금은 그런 출력이 없지만, 나중에 디버깅하려고 넣는 한 줄을 막는 것은
/// 이 가림뿐이다. 그래서 네 가지 출력 경로를 전부 본다.
@Suite struct FareSplitRedactionTest {
    private let account = "3333012345678"
    private let deeplink = "supertoss://send?amount=6233&bank=%EC%B9%B4%EC%B9%B4%EC%98%A4&accountNo=3333012345678"

    private func detail() -> FareSplitDetail {
        FareSplitDetail(
            partyId: 42,
            status: .open,
            totalFare: 18_700,
            payer: FareSplitParticipant(publicId: "p", nickname: "방장"),
            myRole: .sender,
            myAmount: 6_233,
            myTransferStatus: .notSent,
            bank: FareSplitBank(code: "KAKAO", displayName: "카카오뱅크", known: .kakao),
            accountNumber: account,
            tossDeeplink: deeplink,
            transfers: [],
            createdAt: nil,
            closedAt: nil
        )
    }

    /// 한 값의 네 출력 경로 — `print`·`debugPrint`·`dump`·문자열 보간.
    private func outputs(_ value: Any) -> [String] {
        var dumped = ""
        dump(value, to: &dumped)
        return [String(describing: value), String(reflecting: value), dumped, "\(value)"]
    }

    @Test("계좌는 끝 4자리만 딥링크는 스킴만 남긴다")
    func redactionShapes() {
        #expect(FareSplitRedaction.account("3333012345678") == "****5678")
        #expect(FareSplitRedaction.account("1234") == "****", "짧은 값의 끝 4자리는 값 전체다")
        #expect(FareSplitRedaction.account(nil) == "nil")
        #expect(FareSplitRedaction.deeplink(deeplink) == "supertoss://…")
        #expect(FareSplitRedaction.deeplink("no-scheme") == "…")
        #expect(FareSplitRedaction.deeplink(nil) == "nil")
    }

    @Test("정산 상세를 어떻게 출력해도 계좌번호와 딥링크가 나오지 않는다")
    func detailNeverPrintsSecrets() {
        for text in outputs(detail()) {
            #expect(!text.contains(account), "계좌번호가 샜다: \(text)")
            #expect(!text.contains("accountNo="), "딥링크 쿼리가 샜다: \(text)")
            #expect(text.contains("****5678"), "가린 값이 없으면 어느 계좌인지 대조할 수 없다: \(text)")
        }
    }

    /// 실패에 담긴 기존 정산(`FareSplitException.existing`)도 같은 출력 경로를 탄다.
    @Test("실패에 담긴 정산도 계좌번호를 내보내지 않는다")
    func exceptionNeverPrintsSecrets() {
        let failure = FareSplitException(code: "FARE_SPLIT_ALREADY_EXISTS", serverMessage: nil, existing: detail())

        for text in outputs(failure) {
            #expect(!text.contains(account), "계좌번호가 샜다: \(text)")
        }
    }

    @Test("복사 거리와 초안도 계좌번호를 가린다")
    func manualTransferAndDraftNeverPrintSecrets() throws {
        let manual = try #require(detail().manualTransfer)
        let draft = FareSplitDraft(totalFare: 18_700, bankCode: "KAKAO", accountNumber: account, shares: [])

        for text in outputs(manual) + outputs(draft) {
            #expect(!text.contains(account), "계좌번호가 샜다: \(text)")
        }
    }
}
