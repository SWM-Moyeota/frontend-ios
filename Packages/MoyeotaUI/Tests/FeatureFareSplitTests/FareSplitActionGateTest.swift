import Foundation
import MoyeotaDomain
import Testing
@testable import FeatureFareSplit

/// **어떤 버튼이 어떤 행에 달리는가** — 이 저장소에서 틀렸을 때 가장 비싼 판정이다.
///
/// 세 가지를 못 박는다.
/// 1. **「받았어요」와 「아직 안 들어왔어요」가 같은 조건에서 함께 열리지 않는다.** 둘 다 204 로
///    성공해 보이는데 한쪽은 되돌릴 수 없다 — 바꿔 달려 있으면 **아무도 알아채지 못한다.**
/// 2. **멱등이 아닌 하나만 더 좁다.** `markNotReceived` 는 SENT 에서만 되고(409 `TRANSFER_NOT_SENT`),
///    나머지 둘은 「이미 그 상태」여도 204 다.
/// 3. **서버가 식별하지 못한 행은 잠긴다.** 안 잠그면 404 가 영구히 나고, 그 한 행 때문에 정산이
///    COMPLETED 로 닫히지 않는다.
@Suite struct FareSplitActionGateTest {

    // ─────────────────── 받는 사람의 두 버튼 ───────────────────

    /// 상태표 전체를 한 테스트로 고정한다 — 가지 하나를 빠뜨리면 여기서 깨진다.
    @Test("송금 상태마다 누를 수 있는 버튼이 다르다")
    func buttonsPerTransferStatus() {
        let expected: [(TransferStatus, canConfirm: Bool, canRevert: Bool)] = [
            // 아직 안 보냄 — 현금으로 받았으면 바로 확인할 수 있다(서버가 허용한다).
            // 되돌릴 것은 없다: 「아직 안 들어왔어요」는 409 TRANSFER_NOT_SENT 다.
            (.notSent, true, false),
            // 보냈다고 알림 — 확인도 되돌리기도 **여기서만** 둘 다 된다.
            (.sent, true, true),
            // 받음 확인 — 되돌릴 길이 없다. 둘 다 잠긴다.
            (.confirmed, false, false),
        ]

        for (status, canConfirm, canRevert) in expected {
            let row = transfer(status: status)
            let actions = transferActionsOf(detail: detail(transfers: [row]), transfer: row)

            #expect(actions.canConfirm == canConfirm, "\(status) 의 「받았어요」")
            #expect(actions.canMarkNotReceived == canRevert, "\(status) 의 「아직 안 들어왔어요」")
        }
    }

    /// 되돌리기가 **열려 있는 상태는 SENT 하나뿐**이다. 이 단정을 따로 두는 이유: 위 표가
    /// 느슨해지는 방향으로 고쳐지는 것(NOT_SENT 에도 열어 주기)을 막는다 — 그 한 줄이 409 다.
    @Test("되돌리기는 보냈다고 알린 송금에만 열린다")
    func revertOnlyOnSent() {
        let opened = TransferStatus.allCases.filter { status in
            let row = transfer(status: status)
            return transferActionsOf(detail: detail(transfers: [row]), transfer: row).canMarkNotReceived
        }

        #expect(opened == [.sent])
    }

    /// 두 버튼의 **열림 조건 집합이 달라야** 한다 — 같으면 배선을 바꿔 달아도 화면이 똑같아 보인다.
    ///
    /// SENT 에서 둘이 **함께** 열리는 것은 맞다(그 상태에서만 확인도 되돌리기도 된다). 바꿔 단 것을
    /// 잡아 주는 상태는 NOT_SENT 다 — 거기서 확인은 열리고 되돌리기는 잠겨야 한다.
    @Test("두 버튼의 열림 조건 집합이 서로 다르다")
    func buttonsHaveDifferentOpenSets() {
        func openStates(_ pick: (TransferActions) -> Bool) -> [TransferStatus] {
            TransferStatus.allCases.filter { status in
                let row = transfer(status: status)
                return pick(transferActionsOf(detail: detail(transfers: [row]), transfer: row))
            }
        }

        let confirmOpen = openStates { $0.canConfirm }
        let revertOpen = openStates { $0.canMarkNotReceived }

        #expect(confirmOpen == [.notSent, .sent])
        #expect(revertOpen == [.sent])
        #expect(confirmOpen != revertOpen, "두 버튼의 조건이 같으면 바꿔 달아도 아무도 모른다")
    }

    @Test("서버가 식별하지 못한 행은 두 버튼이 모두 잠기고 이유가 적힌다")
    func unidentifiedRowIsLocked() {
        let anonymous = transfer("", "탈퇴한 회원", status: .sent)
        let actions = transferActionsOf(detail: detail(transfers: [anonymous]), transfer: anonymous)

        #expect(!actions.canConfirm)
        #expect(!actions.canMarkNotReceived)
        // 잠긴 이유를 적지 않으면 「왜 이 사람만 못 누르지」에 답할 수 없다.
        #expect(actions.lockReason != nil)
    }

    @Test("이미 확인한 행은 되돌릴 수 없다고 말한다")
    func confirmedRowSaysIrreversible() throws {
        let done = transfer(status: .confirmed)
        let actions = transferActionsOf(detail: detail(transfers: [done]), transfer: done)

        #expect(try #require(actions.lockReason).contains("되돌릴 수 없"))
    }

    @Test("보내는 사람 화면에는 받는 사람의 버튼이 하나도 없다")
    func senderSeesNoPayerButtons() {
        let row = transfer(status: .sent)
        let actions = transferActionsOf(detail: detail(role: .sender, transfers: [row]), transfer: row)

        #expect(!actions.canConfirm)
        #expect(!actions.canMarkNotReceived)
        // 그릴 버튼이 없으므로 설명할 것도 없다 — 잠금 문구를 띄우면 보내는 사람이
        // 「내가 확인해야 하나」로 읽는다.
        #expect(actions.lockReason == nil)
    }

    @Test("닫힌 정산에서는 받는 사람도 아무것도 누를 수 없다")
    func closedFareSplitLocksPayer() {
        for status in [FareSplitStatus.completed, .expired] {
            let row = transfer(status: .sent)
            let actions = transferActionsOf(detail: detail(status: status, transfers: [row]), transfer: row)

            #expect(!actions.canConfirm, "\(status)")
            #expect(!actions.canMarkNotReceived, "\(status)")
        }
    }

    // ─────────────────── 마지막 한 건 ───────────────────

    @Test("나머지가 모두 확인됐으면 마지막 한 건이다")
    func lastOutstanding() {
        let last = transfer(SENDER_A, "동승자A", 6_233, status: .sent)
        let done = transfer(SENDER_B, "동승자B", 6_233, status: .confirmed)

        #expect(isLastOutstandingTransfer(detail: detail(transfers: [last, done]), transfer: last))
    }

    @Test("아직 확인 안 된 다른 행이 있으면 마지막이 아니다")
    func notLastWhenOthersOutstanding() {
        let a = transfer(SENDER_A, status: .sent)
        let b = transfer(SENDER_B, status: .notSent)

        #expect(!isLastOutstandingTransfer(detail: detail(transfers: [a, b]), transfer: a))
    }

    /// 마지막 한 건의 확인은 **정산 전체를 닫고 계좌번호를 지운다** — 그 사실을 다이얼로그가 말해야 한다.
    @Test("마지막 한 건의 확인 다이얼로그는 정산이 끝난다고 말한다")
    func lastConfirmDialogSaysItCloses() {
        let last = transfer(SENDER_A, status: .sent)
        let done = transfer(SENDER_B, status: .confirmed)
        let message = confirmReceivedDialogMessage(detail: detail(transfers: [last, done]), transfer: last)

        #expect(message.contains("정산이 끝나고"))
        #expect(message.contains("계좌번호가 지워져요"))
    }

    @Test("확인 다이얼로그는 언제나 되돌릴 수 없다고 말하고 금액과 이름을 적는다")
    func confirmDialogCopy() {
        let a = transfer(SENDER_A, "동승자A", 6_233, status: .sent)
        let b = transfer(SENDER_B, status: .notSent)
        let message = confirmReceivedDialogMessage(detail: detail(transfers: [a, b]), transfer: a)

        #expect(message.contains("되돌릴 수 없어요"))
        #expect(message.contains("동승자A"))
        #expect(message.contains("6,233원"))
        // 마지막이 아니므로 정산이 끝난다고 말하지 않는다 — 매번 말하면 경고가 닳는다.
        #expect(!message.contains("정산이 끝나고"))
    }

    /// 「취소」라고 적으면 방장이 **정산 자체를 지우는 버튼**으로 읽는다. 그 길은 서버에 없다.
    @Test("되돌리기 다이얼로그는 정산 취소라고 말하지 않는다")
    func revertDialogNeverSaysCancel() {
        let message = markNotReceivedDialogMessage(transfer: transfer(status: .sent))

        #expect(!message.contains("취소"))
        #expect(message.contains("되돌릴까요"))
    }

    // ─────────────────── 보내는 사람 단계 ───────────────────

    /// 판정의 입력은 **서버가 직접 준** `myTransferStatus` 다 — 세션 uuid 로 `transfers` 에서 내 행을
    /// 찾던 방식(Backend PR #328 이전)은 서버가 나를 설명하지 못한 응답에서 답을 못 냈다.
    @Test("보낼 단계는 서버가 준 내 송금 상태로 갈린다")
    func senderStageFollowsServer() {
        func sender(_ status: TransferStatus?, _ fareSplitStatus: FareSplitStatus = .open) -> FareSplitDetail {
            detail(status: fareSplitStatus, role: .sender, myTransferStatus: .value(status))
        }

        #expect(senderStageOf(detail: sender(.notSent)) == .sendReady)
        #expect(senderStageOf(detail: sender(.sent)) == .sentWaiting)
        #expect(senderStageOf(detail: sender(.confirmed)) == .confirmed)
        #expect(senderStageOf(detail: sender(.notSent, .completed)) == .closed)
    }

    /// 받는 사람이 탈퇴하면 서버가 **OPEN 인 정산의 계좌번호만** 지운다 — 상태는 그대로다.
    /// 「계좌가 없으면 끝난 정산」으로 읽으면 아직 보낼 돈이 남은 사람에게 「정산이 끝났어요」가 뜬다.
    @Test("진행 중인데 계좌가 사라지면 계좌 소실 단계다")
    func lostAccountStage() throws {
        let lost = detail(role: .sender, myTransferStatus: .value(.notSent), accountNumber: nil)

        #expect(senderStageOf(detail: lost) == .accountLost)
        // 다시 받아도 계좌는 돌아오지 않는다 — 재시도를 권하지 말고 채팅으로 보낸다.
        #expect(try #require(senderStageNotice(stage: .accountLost)).contains("채팅"))
        #expect(showsChatFallback(detail: lost))
    }

    /// 이미 보낸 사람에게 「계좌를 물어봐 주세요」는 **이미 끝난 일을 다시 하라는 말**이다.
    @Test("계좌가 사라져도 이미 보낸 송금은 보냈다고 알린 단계로 남는다")
    func lostAccountAfterSending() {
        let lost = detail(role: .sender, myTransferStatus: .value(.sent), accountNumber: nil)

        #expect(senderStageOf(detail: lost) == .sentWaiting)
    }

    /// 서버가 상태를 늘렸거나 옛 배포가 그 필드를 싣지 않으면 nil 로 온다(매퍼가 둘을 같게 떨어뜨린다).
    /// `.sendReady` 로 떨어뜨리지 않는 것이 핵심 — 모르는 상태에 버튼을 열면 이미 보낸 사람이 또 보낸다.
    @Test("서버가 내 송금 상태를 말해 주지 않으면 보낼 단계로 떨어지지 않는다")
    func unknownMyTransfer() {
        let unknown = detail(role: .sender, myTransferStatus: .value(nil))

        #expect(senderStageOf(detail: unknown) == .unknownMyTransfer)
        #expect(!showsMarkSentButton(detail: unknown))
    }

    /// 멀쩡한 정산에 「채팅으로 물어보기」를 두면 **할 일이 흐려진다.**
    @Test("앱 안에 길이 남아 있으면 채팅으로 보내지 않는다")
    func chatFallbackOnlyWhenStuck() {
        #expect(!showsChatFallback(detail: detail(role: .sender)))
        #expect(!showsChatFallback(detail: detail(status: .completed, accountNumber: nil)))
        // 기간이 지난 정산은 앱 안에서 할 수 있는 일이 없다 — 돈이 안 건너갔을 수도 있다.
        #expect(showsChatFallback(detail: detail(status: .expired, accountNumber: nil)))
    }

    // ─────────────────── 토스·보냈어요 버튼 ───────────────────

    /// 서버가 딥링크를 주지 않으면 **만들어 끼우지 않는다** — 규격도 은행 표기도 서버 것이다.
    @Test("토스 버튼은 서버가 딥링크를 줬을 때만 그린다")
    func tossButtonOnlyWithServerDeeplink() {
        var ready = detail(
            role: .sender,
            myTransferStatus: .value(.notSent),
            tossDeeplink: "supertoss://send?amount=6233&bank=카카오뱅크&accountNo=3333012345678"
        )
        #expect(showsTossButton(detail: ready))

        var noLink = ready
        noLink.tossDeeplink = nil
        #expect(!showsTossButton(detail: noLink))
        noLink.tossDeeplink = ""
        #expect(!showsTossButton(detail: noLink))
        // 이미 보낸 사람에게 송금 버튼을 남기지 않는다(딥링크가 남아 있어도).
        ready.myTransferStatus = .sent
        #expect(!showsTossButton(detail: ready))
    }

    /// ### 「보냈어요」의 조건은 `canMarkSent` 하나다 ★
    /// 「진행 중 · 내가 보내는 사람 · 아직 안 보냄」을 화면이 다시 조립하면 **받는 사람의 nil 을
    /// 「아직 안 보냈다」로 읽는 실수**가 끼어들고, 그 버튼은 403 `NOT_FARE_SPLIT_SENDER` 다.
    @Test("보냈어요 버튼은 받는 사람에게 뜨지 않는다")
    func markSentNeverForPayer() {
        // 받는 사람의 myTransferStatus 는 서버가 일부러 nil 로 준다.
        #expect(!showsMarkSentButton(detail: detail(role: .payer)))
        #expect(showsMarkSentButton(detail: detail(role: .sender)))
    }

    /// 보낸 뒤에는 버튼이 아니라 **상태**를 보여 준다. 서버는 다시 눌러도 204 지만, 버튼이 남아 있으면
    /// 사용자가 「안 눌렸나」 싶어 또 누르고 같은 화면이 반복된다.
    @Test("이미 보냈거나 확인됐으면 버튼 대신 상태를 보여 준다")
    func stateInsteadOfButtonAfterSending() {
        for status in [TransferStatus.sent, .confirmed] {
            let sent = detail(role: .sender, myTransferStatus: .value(status))

            #expect(!showsMarkSentButton(detail: sent), "\(status)")
            #expect(senderStageNotice(stage: senderStageOf(detail: sent)) != nil, "\(status)")
        }
    }

    /// 계좌가 사라진 단계에도 「보냈어요」는 남는다 — 채팅으로 계좌를 받아 **앱 밖에서 이미 보낼 수
    /// 있고**, 버튼을 거두면 그 사실을 알릴 길이 없어 4시간마다 재요청 알림이 계속 간다.
    @Test("계좌가 사라져도 보냈다고 알릴 수 있다")
    func markSentSurvivesLostAccount() {
        let lost = detail(role: .sender, myTransferStatus: .value(.notSent), accountNumber: nil)

        #expect(showsMarkSentButton(detail: lost))
    }

    @Test("닫힌 정산에서는 보냈다고 알릴 수 없다")
    func noMarkSentWhenClosed() {
        for status in [FareSplitStatus.completed, .expired] {
            let closed = detail(status: status, role: .sender, myTransferStatus: .value(.notSent))

            #expect(!showsMarkSentButton(detail: closed), "\(status)")
        }
    }

    /// 보내는 사람은 자기 「보냈어요」를 되돌릴 수 없다(`markNotReceived` 는 PAYER 전용이다) —
    /// 그 사실을 누르기 전에 말한다.
    @Test("보냈어요 확인은 금액과 되돌릴 수 없음을 말한다")
    func markSentDialogCopy() {
        let message = markSentDialogMessage(detail: detail(role: .sender, myAmount: 6_233))

        #expect(message.contains("6,233원"))
        #expect(message.contains("받는 분만 할 수 있어요"))
        // 「이미 보냈습니다」류를 지어내지 않는다 — 본문 없는 204 로는 알 수 없는 사실이다.
        #expect(!message.contains("이미"))
    }

    // ─────────────────── 수정 가능 여부 ───────────────────

    @Test("전원이 아직 안 보냈으면 받는 사람은 고칠 수 있다")
    func payerCanEditWhenNobodySent() {
        #expect(editBlockReason(detail: detail()) == nil)
    }

    /// 「정산 취소는 없다」(서버 원문)를 그 자리에 적는다 — 없으면 방장이 취소할 길을 찾는다.
    @Test("누가 보냈다고 누르면 왜 못 고치는지와 대신 할 일을 적는다")
    func editBlockedAfterSomeoneSent() throws {
        let started = detail(transfers: [transfer(SENDER_A, status: .sent)])
        let reason = try #require(editBlockReason(detail: started))

        #expect(reason.contains("더 이상 고칠 수 없어요"))
        #expect(reason.contains("취소하는 길은 없"))
    }

    @Test("닫힌 정산은 고칠 수 없다고만 말한다")
    func closedFareSplitCannotBeEdited() {
        #expect(editBlockReason(detail: detail(status: .completed)) == "닫힌 정산은 고칠 수 없어요")
    }

    /// 보내는 사람 화면에는 수정 영역이 통째로 없다 — 설명할 자리가 없다는 뜻의 nil 이다.
    @Test("보내는 사람에게는 수정 안내를 적지 않는다")
    func noEditCopyForSender() {
        #expect(editBlockReason(detail: detail(role: .sender)) == nil)
    }
}
