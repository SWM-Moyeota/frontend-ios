import Foundation
import MoyeotaDomain
import Testing
@testable import FeatureFareSplit

/// 서버 실패 18종 → 사용자 문구.
///
/// ### 상태 코드로는 아무것도 갈리지 않는다 ★
/// 18종이 네 상태(400·403·404·409)에 몰려 있어 **한 상태 안에 할 일이 정반대인 것들**이 섞인다.
/// 문구를 뭉치면 사용자가 **기다려야 할 때 다시 누르고, 다시 누르면 될 때 포기한다.**
@Suite struct FareSplitFailureMessageTest {

    /// 정산을 시작할 수 없는 세 실패 — 같은 403/409 인데 **할 수 있는 일이 서로 다르다.**
    /// 세 문구가 같아지는 방향의 수정을 이 테스트가 막는다.
    @Test("정산을 시작할 수 없는 세 실패의 문구가 전부 다르다")
    func threeStartFailuresDiffer() {
        let notFinished = fareSplitFailureMessage(failure: failure("PARTY_NOT_FINISHED", httpStatus: 409), action: .start)
        let notARider = fareSplitFailureMessage(failure: failure("NOT_A_RIDER", httpStatus: 403), action: .start)
        let notEnough = fareSplitFailureMessage(failure: failure("NOT_ENOUGH_RIDERS", httpStatus: 409), action: .start)

        #expect(Set([notFinished, notARider, notEnough]).count == 3)
        // 유일하게 사용자가 할 일이 있는 쪽만 다음 행동을 알려 준다.
        #expect(notFinished.contains("「출발」"))
        // 되돌릴 길이 없는 둘은 「다시」·「도착을 눌러 주세요」를 권하지 않는다 — 방은 이미 끝났다.
        for message in [notARider, notEnough] {
            #expect(!message.contains("다시 시도"), "\(message)")
            #expect(!message.contains("도착을 눌러"), "\(message)")
            #expect(message.contains("정산할 수 없어요"), "\(message)")
        }
    }

    /// 처방이 정반대인 두 400 — 한쪽은 금액 칸, 한쪽은 재조회다. 뭉치면 고칠 수 있는 것을 못 고친다.
    @Test("합계 불일치와 대상 불일치를 가른다")
    func sumAndTargetMismatchDiffer() {
        let sum = fareSplitFailureMessage(failure: failure("PAYMENTS_NOT_EQUAL_FARE"), action: .start)
        let target = fareSplitFailureMessage(failure: failure("PAYMENT_TARGET_MISMATCH"), action: .start)

        #expect(sum != target)
        #expect(sum.contains("금액"))
        // 금액을 아무리 고쳐도 풀리지 않는다 — 방 상세를 다시 받아야 한다.
        #expect(target.contains("다시 불러와"))
    }

    /// ### 서버 원문 message 를 그대로 띄우지 않는다 ★
    /// 400 `INVALID_REQUEST` 의 message 는 Bean Validation 원문이라 「totalFare: …」처럼 **필드명을
    /// 그대로** 담는다. 그대로 띄우면 모르는 영어 이름이 뜨고 어느 칸을 고칠지도 알 수 없다.
    @Test("서버가 보낸 원문을 사용자에게 그대로 보여 주지 않는다")
    func neverShowsServerMessage() {
        let raw = "totalFare: 택시비는 1원 이상이어야 합니다"
        let codes: [String?] = [
            nil, "INVALID_REQUEST", "INVALID_ACCOUNT_NUMBER", "INVALID_PAYMENT",
            "PAYMENT_TARGET_MISMATCH", "PAYMENTS_NOT_EQUAL_FARE", "NOT_PARTY_HOST", "NOT_A_RIDER",
            "NOT_FARE_SPLIT_PARTICIPANT", "NOT_FARE_SPLIT_PAYER", "NOT_FARE_SPLIT_SENDER",
            "PARTY_NOT_FOUND", "FARE_SPLIT_NOT_FOUND", "FARE_SPLIT_TRANSFER_NOT_FOUND",
            "FARE_SPLIT_ALREADY_EXISTS", "PARTY_NOT_FINISHED", "NOT_ENOUGH_RIDERS",
            "FARE_SPLIT_CLOSED", "FARE_SPLIT_ALREADY_STARTED", "TRANSFER_NOT_SENT",
        ]

        for code in codes {
            for action in FareSplitAction.allCases {
                let message = fareSplitFailureMessage(failure: failure(code, serverMessage: raw), action: action)

                #expect(!message.contains("totalFare"), "\(code ?? "nil")/\(action) 가 서버 원문을 그대로 썼다")
                #expect(!message.isBlank, "\(code ?? "nil")/\(action) 의 문구가 비어 있다")
            }
        }
    }

    /// 같은 코드라도 **어떤 요청이 실패했는지**에 따라 할 말이 다른 가지가 있다(모르는 코드).
    @Test("모르는 코드는 요청마다 다른 일반 문구로 떨어진다")
    func unknownCodePerAction() {
        let messages = FareSplitAction.allCases.map { action in
            fareSplitFailureMessage(failure: failure("MYSTERY_CODE", httpStatus: 500), action: action)
        }

        #expect(Set(messages).count == FareSplitAction.allCases.count)
    }

    /// 네트워크 실패는 **유일하게 「다시」가 뜻이 있는** 실패다.
    @Test("응답을 받지 못한 실패만 다시 시도를 권한다")
    func networkSuggestsRetry() {
        let network = fareSplitFailureMessage(failure: failure(nil, httpStatus: nil, isNetwork: true), action: .load)

        #expect(network.contains("다시 시도"))
    }

    @Test("토큰이 만료되면 로그인을 안내한다")
    func unauthorizedSuggestsLogin() {
        let expired = fareSplitFailureMessage(failure: failure(nil, httpStatus: 401), action: .load)

        #expect(expired.contains("로그인"))
    }

    /// 다시 눌러도 같은 답인 실패들에 「다시 시도」를 적지 않는다 — 없는 길을 권하면 그게 거짓이다.
    @Test("되돌릴 수 없는 실패에 다시 시도를 권하지 않는다")
    func noRetryForPermanentFailures() {
        for code in ["NOT_A_RIDER", "NOT_ENOUGH_RIDERS", "FARE_SPLIT_CLOSED", "FARE_SPLIT_ALREADY_STARTED", "NOT_PARTY_HOST"] {
            let message = fareSplitFailureMessage(failure: failure(code, httpStatus: 409), action: .start)

            #expect(!message.contains("다시 시도"), "\(code)")
        }
    }

    /// 「되돌리기는 SENT 에서만」을 문구로도 말한다. 화면이 버튼을 잠그지만
    /// (`transferActionsOf`) 상세가 낡으면 이 409 가 남는다.
    @Test("되돌리기 실패는 어떤 송금에서만 되는지 말한다")
    func transferNotSentCopy() {
        let message = fareSplitFailureMessage(failure: failure("TRANSFER_NOT_SENT", httpStatus: 409), action: .markNotReceived)

        #expect(message.contains("「보냈어요」 상태인 송금만"))
    }

    // ─────────────────── 재조회 판정 ───────────────────

    /// 문구만 띄우고 끝내면 안 되는 실패들 — 전부 **들고 있는 상세가 서버와 어긋났다**는 뜻이다.
    /// 어긋난 화면 위에서 다음 동작을 하면 같은 실패가 되풀이되거나, 이미 지워진 계좌번호를
    /// 유효한 것처럼 보여 준다.
    @Test("상세가 낡았다는 신호에는 재조회가 따라온다")
    func staleSignalsReload() {
        for code in [
            "FARE_SPLIT_ALREADY_STARTED",
            "FARE_SPLIT_CLOSED",
            "NOT_FARE_SPLIT_PAYER",
            "NOT_FARE_SPLIT_SENDER",
            "FARE_SPLIT_TRANSFER_NOT_FOUND",
            "TRANSFER_NOT_SENT",
            "PAYMENT_TARGET_MISMATCH",
        ] {
            #expect(needsReloadAfter(failure: failure(code, httpStatus: 409)), "\(code)")
        }
    }

    @Test("입력 실수와 네트워크 실패는 재조회 대상이 아니다")
    func inputMistakesDoNotReload() {
        for code in ["INVALID_ACCOUNT_NUMBER", "PAYMENTS_NOT_EQUAL_FARE", "INVALID_REQUEST"] {
            #expect(!needsReloadAfter(failure: failure(code)), "\(code)")
        }
        #expect(!needsReloadAfter(failure: failure(nil, httpStatus: nil, isNetwork: true)))
    }
}
