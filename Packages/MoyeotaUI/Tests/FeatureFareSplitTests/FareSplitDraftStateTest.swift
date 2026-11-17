import Foundation
import MoyeotaDomain
import Testing
@testable import FeatureFareSplit

/// 정산 시작·수정 폼의 **1/N 채우기와 제출 잠금**.
///
/// 서버는 틀린 요청을 400 하나로 답하고(`PAYMENTS_NOT_EQUAL_FARE`·`PAYMENT_TARGET_MISMATCH`) 그
/// 답은 **입력을 다 끝낸 뒤에** 온다. 그래서 잠금 규칙이 틀리면 ① 멀쩡해 보이는데 제출만 영구히
/// 실패하거나 ② 잠겨야 할 버튼이 열려 사용자가 400 을 스스로 만든다. **둘 다 스크린샷으로 구분되지
/// 않는다.**
@Suite struct FareSplitDraftStateTest {

    private func ready(_ gate: FareSplitDraftGate) throws -> FareSplitDraftState {
        guard case .ready(let state) = gate else {
            Issue.record("폼이 열려야 한다: \(gate)")
            throw GateNotReady()
        }
        return state
    }

    private func blocked(_ gate: FareSplitDraftGate) throws -> (message: String, recoverable: Bool) {
        guard case .blocked(let message, let recoverable) = gate else {
            Issue.record("폼이 막혀야 한다")
            throw GateNotReady()
        }
        return (message, recoverable)
    }

    private struct GateNotReady: Error {}

    private func startState() throws -> FareSplitDraftState { try ready(startDraftGate(ride: ride())) }

    private func filled() throws -> FareSplitDraftState {
        try startState()
            .withFare(raw: "18700")
            .withBank(bank: .kakao)
            .withAccount(raw: "3333-01-2345678")
    }

    private func isBlocked(_ gate: FareSplitDraftGate) -> Bool {
        if case .blocked = gate { return true }
        return false
    }

    // ─────────────────── 열기 판정 ───────────────────

    @Test("끝난 방의 방장만 시작 폼을 연다")
    func hostOfFinishedRideOpensStart() {
        #expect(!isBlocked(startDraftGate(ride: ride())))
    }

    /// 「출발」을 누르면 풀리는 실패다 — **유일하게 사용자가 할 일이 있는** 쪽이다.
    @Test("아직 출발하지 않은 방은 되돌릴 수 있는 막힘이다")
    func notDepartedIsRecoverable() throws {
        let gate = try blocked(startDraftGate(ride: ride(status: .confirmed)))

        #expect(gate.recoverable)
        #expect(gate.message.contains("출발"))
    }

    /// 도착은 끝난 방에서 되돌릴 수 없다 — 「다시 시도」를 권하면 거짓이 된다.
    @Test("방장이 도착을 누르지 않았으면 영구히 정산할 수 없다고 말한다")
    func hostNotArrivedIsPermanent() throws {
        let noArrival = ride(members: [
            member(PAYER_ID, "방장", isMe: true, isHost: true, arrived: false),
            member(SENDER_A, "동승자A"),
        ])

        #expect(try !blocked(startDraftGate(ride: noArrival)).recoverable)
    }

    @Test("혼자 탔으면 나눌 상대가 없다고 말한다")
    func aloneCannotSplit() throws {
        let alone = ride(members: [member(PAYER_ID, "방장", isMe: true, isHost: true)])
        let gate = try blocked(startDraftGate(ride: alone))

        #expect(!gate.recoverable)
        #expect(gate.message.contains("혼자"))
    }

    @Test("방장이 아니면 시작 폼을 열지 않는다")
    func nonHostCannotStart() {
        let notHost = ride(members: [
            member(PAYER_ID, "방장", isHost: true),
            member(SENDER_A, "나", isMe: true),
        ])

        #expect(isBlocked(startDraftGate(ride: notHost)))
    }

    /// 빼고 보내도 400, 넣고 보내도 400 이다(둘 다 `PAYMENT_TARGET_MISMATCH`) — 열어 봐야 제출할 수
    /// 없는 폼이므로 열지 않는다.
    @Test("서버가 설명하지 못한 탑승자가 있으면 폼을 열지 않는다")
    func unidentifiedRiderBlocksStart() {
        let anonymous = ride(members: [
            member(PAYER_ID, "방장", isMe: true, isHost: true),
            member("", "탈퇴한 회원"),
            member(SENDER_B, "동승자B"),
        ])

        #expect(isBlocked(startDraftGate(ride: anonymous)))
    }

    /// 멤버 전원이 아니라 **도착을 누른 사람만** 대상이다 — 전원으로 채우면 400 이다.
    @Test("정산 대상은 도착을 누른 멤버뿐이다")
    func onlyArrivedMembers() throws {
        let mixed = ride(members: [
            member(PAYER_ID, "방장", isMe: true, isHost: true),
            member(SENDER_A, "동승자A", arrived: true),
            member(SENDER_B, "노쇼", arrived: false),
        ])
        let state = try ready(startDraftGate(ride: mixed))

        #expect(state.riders.map(\.publicId) == [PAYER_ID, SENDER_A])
    }

    // ─────────────────── 1/N 채우기 ───────────────────

    /// Swagger 원문: 「1/N 로 미리 채우는 것은 앱이 한다」 — 택시비를 적는 순간이 그 자리다.
    @Test("택시비를 적으면 1대N 로 미리 채워진다")
    func fareFillsEvenly() throws {
        let state = try startState().withFare(raw: "18700")

        #expect(state.amountInputs[PAYER_ID] == "6234")
        #expect(state.amountInputs[SENDER_A] == "6233")
        #expect(state.amountInputs[SENDER_B] == "6233")
        #expect(state.amountSum == 18_700)
        #expect(state.difference == 0)
    }

    /// 나머지 1원은 **받는 사람이 흡수한다** — 보내는 금액이 전원 같아져 분쟁할 거리가 없다.
    @Test("나누어떨어지지 않는 1원은 받는 사람이 부담하고 그 사실을 적는다")
    func remainderGoesToPayer() throws {
        let state = try startState().withFare(raw: "18700")
        let payer = try #require(state.amountInputs[PAYER_ID].flatMap { Int($0) })
        let sender = try #require(state.amountInputs[SENDER_A].flatMap { Int($0) })

        #expect(payer == 6_234)
        #expect(payer - sender == 1)
        #expect(evenSplitRemainderNotice(state: state) == "나누어떨어지지 않는 1원은 받는 분이 부담해요")
    }

    @Test("나누어떨어지면 나머지 안내를 하지 않는다")
    func noRemainderNotice() throws {
        #expect(evenSplitRemainderNotice(state: try startState().withFare(raw: "18000")) == nil)
    }

    /// 사용자가 금액을 손댄 뒤에 택시비를 고쳐도 **그 조정이 사라지지 않는다.** 사라지면 사용자는
    /// 자기가 지운 줄 모르고 저장하고, 그러면 다른 사람이 보는 금액이 바뀐다.
    @Test("금액을 손대면 택시비를 고쳐도 1대N 로 덮지 않는다")
    func manualAmountsSurviveFareChange() throws {
        let adjusted = try startState().withFare(raw: "18700").withAmount(publicId: SENDER_A, raw: "5000")
        let refared = adjusted.withFare(raw: "18000")

        #expect(refared.amountInputs[SENDER_A] == "5000")
        #expect(!refared.autoSplits)
    }

    @Test("손대기 전에는 택시비를 고칠 때마다 다시 채워진다")
    func untouchedRefills() throws {
        let state = try startState().withFare(raw: "18700").withFare(raw: "18000")

        #expect(state.amountInputs[PAYER_ID] == "6000")
        #expect(state.difference == 0)
    }

    /// 명시적으로 누르면 되살아난다 — 자동 채우기까지 함께 켜진다.
    @Test("똑같이 나누기를 누르면 조정을 덮고 자동 채우기가 되살아난다")
    func splitEvenlyRestores() throws {
        let state = try startState().withFare(raw: "18700").withAmount(publicId: SENDER_A, raw: "1").splitEvenly()

        #expect(state.amountInputs[SENDER_A] == "6233")
        #expect(state.autoSplits)
    }

    /// 사용자가 「2」를 넣을 수 있다 — 그때 터지지 않고 그대로 남는다(그 상태는 버튼이 잠긴다).
    @Test("택시비가 인원보다 적으면 나누지 않고 그대로 둔다")
    func fareBelowRiderCount() throws {
        let state = try startState().withFare(raw: "2")

        #expect(!state.canSplitEvenly())
        #expect(state.amountInputs.isEmpty)
        #expect(submitBlockOf(state: state.withBank(bank: .kb).withAccount(raw: "3333012345678")) == .amountEmpty)
    }

    // ─────────────────── 입력 정제 ───────────────────

    @Test("택시비 칸은 숫자만 받고 앞의 0 을 버린다")
    func fareSanitized() throws {
        #expect(try startState().withFare(raw: "1a8,700원").fareInput == "18700")
        #expect(try startState().withFare(raw: "0018700").fareInput == "18700")
        #expect(try startState().withFare(raw: "000").fareInput == "")
    }

    /// 자릿수 상한이 없으면 `Int` 가 넘쳐 합이 계산 중에 터진다(Swift 는 감기지 않고 **앱이 죽는다**) —
    /// 원본 Kotlin 은 음수로 감겨 「합계가 택시비와 같다」가 거짓으로 참이 되는 조합이 생겼다.
    @Test("금액 칸은 자릿수를 잘라 Int 가 넘치지 않게 한다")
    func digitsCapped() throws {
        #expect(try startState().withFare(raw: "99999999999999").fareInput.count == MAX_FARE_DIGITS)
        let state = try startState().withAmount(publicId: SENDER_A, raw: "99999999999999")
        let amount = try #require(state.amountInputs[SENDER_A])
        #expect(amount.count == MAX_AMOUNT_DIGITS)
        #expect(Int(amount) != nil)
    }

    /// 하이픈·공백은 **지우지 않는다** — 은행 앱이 복사해 주는 모양을 그대로 붙여넣게 하고, 떼는 일은
    /// 매퍼가 보내기 직전에 한다. 숫자 아닌 **다른** 문자는 애초에 받지 않는다(조용히 고친 계좌번호로
    /// 돈이 움직이면 되돌릴 수 없다).
    @Test("계좌번호 칸은 하이픈과 공백을 남기고 다른 문자는 받지 않는다")
    func accountSanitized() throws {
        #expect(try startState().withAccount(raw: "3333-01-2345678").accountInput == "3333-01-2345678")
        #expect(try startState().withAccount(raw: "3333 01 2345678").accountInput == "3333 01 2345678")
        #expect(try startState().withAccount(raw: "3333(국민)01 2345678").accountInput == "333301 2345678")
    }

    @Test("계좌번호가 자릿수를 못 맞추면 칸 아래에 이유를 적는다")
    func accountErrorBelowField() throws {
        #expect(accountErrorText(state: try startState()) == nil, "빈 칸을 틀렸다고 말하지 않는다")
        #expect(accountErrorText(state: try startState().withAccount(raw: "333301")) != nil)
        #expect(accountErrorText(state: try startState().withAccount(raw: "3333-01-2345678")) == nil)
    }

    // ─────────────────── 제출 잠금 ───────────────────

    @Test("택시비 은행 계좌 금액이 모두 맞으면 보낼 수 있다")
    func filledCanSubmit() throws {
        #expect(submitBlockOf(state: try filled()) == nil)
    }

    /// 폼의 위에서 아래 순서로 **다음에 할 일 하나**를 가리킨다.
    @Test("잠금 사유는 폼 순서대로 하나만 알려 준다")
    func blockInFormOrder() throws {
        let empty = try startState()
        #expect(submitBlockOf(state: empty) == .fareEmpty)

        let fared = empty.withFare(raw: "18700")
        #expect(submitBlockOf(state: fared) == .bankNotSelected)

        let banked = fared.withBank(bank: .kakao)
        #expect(submitBlockOf(state: banked) == .accountEmpty)

        let shortAccount = banked.withAccount(raw: "3333")
        #expect(submitBlockOf(state: shortAccount) == .accountInvalid)

        #expect(submitBlockOf(state: banked.withAccount(raw: "3333012345678")) == nil)
    }

    @Test("합이 택시비와 다르면 보낼 수 없다")
    func sumMismatchBlocks() throws {
        #expect(submitBlockOf(state: try filled().withAmount(publicId: SENDER_A, raw: "1")) == .sumNotEqualFare)
    }

    @Test("비어 있는 금액 칸이 하나라도 있으면 보낼 수 없다")
    func emptyAmountBlocks() throws {
        #expect(submitBlockOf(state: try filled().withAmount(publicId: SENDER_B, raw: "")) == .amountEmpty)
    }

    /// 0원을 적은 것과 **아직 안 적은 것**은 다르다 — 앞은 「1원 이상」을 말하고 뒤는 버튼만 잠근다.
    @Test("0 원을 적으면 1원 이상이라고 말한다")
    func zeroAmount() throws {
        // "0" 은 앞의 0 을 버려 빈 칸이 되므로, 1원 이상 미달을 만들려면 합을 어긋나게 둔다.
        #expect(submitBlockOf(state: try filled().withAmount(publicId: SENDER_A, raw: "0")) == .amountEmpty)
    }

    /// 화면을 열자마자 빨간 띠가 떠 있으면 사용자는 아무 잘못도 없이 오류 화면을 본다.
    @Test("아직 안 적은 칸에는 경고 문구를 띄우지 않는다")
    func noWarningForUntouched() {
        for block in [FareSplitSubmitBlock.fareEmpty, .bankNotSelected, .accountEmpty, .amountEmpty] {
            #expect(submitBlockMessage(block: block) == nil, "\(block)")
        }
        #expect(submitBlockMessage(block: nil) == nil)
    }

    /// 합계 어긋남은 금액 칸 **바로 아래 합계 줄**이 실시간으로 말한다 — 두 군데서 말하지 않는다.
    @Test("합계 어긋남은 아래 경고가 아니라 합계 줄이 말한다")
    func sumMismatchSpokenBySumLine() throws {
        #expect(submitBlockMessage(block: .sumNotEqualFare) == nil)
        #expect(differenceNotice(state: try filled().withAmount(publicId: SENDER_A, raw: "1")) != nil)
    }

    @Test("적었는데 틀린 경우에는 문구를 띄운다")
    func wrongInputsHaveCopy() {
        #expect(submitBlockMessage(block: .accountInvalid) != nil)
        #expect(submitBlockMessage(block: .fareBelowMinimum) != nil)
        #expect(submitBlockMessage(block: .targetMismatch) != nil)
    }

    // ─────────────────── 합계 표시 ───────────────────

    @Test("합계 줄은 합과 택시비를 나란히 보여 준다")
    func sumLineCopy() throws {
        #expect(sumLabel(state: try filled()) == "합계 18,700원 / 택시비 18,700원")
    }

    /// 「모자라다」와 「많다」를 가르는 이유는 **할 일이 정반대**라서다.
    @Test("차액은 모자람과 넘침을 갈라 금액으로 말한다")
    func differenceCopy() throws {
        let short = try #require(differenceNotice(state: try filled().withAmount(publicId: SENDER_A, raw: "1")))
        #expect(short.label == "택시비보다 6,232원 모자라요")
        #expect(short.tone == .warn)

        let over = try #require(differenceNotice(state: try filled().withAmount(publicId: SENDER_A, raw: "9999")))
        #expect(over.label == "택시비보다 3,766원 많아요")

        #expect(try #require(differenceNotice(state: try filled())).tone == .done)
    }

    @Test("택시비를 적기 전에는 차액을 말하지 않는다")
    func noDifferenceBeforeFare() throws {
        #expect(differenceNotice(state: try startState()) == nil)
    }

    // ─────────────────── 보낼 값 ───────────────────

    @Test("보낼 값은 사용자가 적은 원문 계좌번호를 그대로 담는다")
    func draftKeepsRawAccount() throws {
        let draft = try #require(try filled().toDraft())

        #expect(draft.totalFare == 18_700)
        #expect(draft.bankCode == Bank.kakao.code)
        // 정규화는 매퍼가 보내기 직전에 한다 — 두 곳에서 하면 한쪽이 바뀔 때 조용히 갈린다.
        #expect(draft.accountNumber == "3333-01-2345678")
        #expect(draft.shares.count == 3)
        #expect(draft.shares.reduce(0) { $0 + $1.amount } == 18_700)
    }

    /// iOS: 원본은 은행 코드를 `orEmpty()` 로 빈 문자열을 채워 보낸다(잠금이 막아 주므로 닿지 않는 경로).
    /// 여기서는 **보낼 값을 만들지 않는다** — 빈 은행 코드가 서버로 가는 길을 타입으로 닫는다.
    @Test("은행을 고르지 않았으면 보낼 값을 만들지 않는다")
    func noDraftWithoutBank() throws {
        let noBank = try startState().withFare(raw: "18700").withAccount(raw: "3333012345678")

        #expect(noBank.toDraft() == nil)
    }

    // ─────────────────── 수정 폼 ───────────────────

    @Test("수정 폼은 방 상세 없이 기존 정산만으로 채워진다")
    func editFormFromDetailOnly() throws {
        let state = try ready(editDraftGate(detail: detail()))

        #expect(state.mode == .edit)
        #expect(state.fareInput == "18700")
        #expect(state.accountInput == "3333012345678")
        #expect(state.riders.map(\.publicId) == [PAYER_ID, SENDER_A, SENDER_B])
        #expect(state.amountInputs[PAYER_ID] == "6234")
        #expect(state.amountInputs[SENDER_A] == "6233")
        #expect(submitBlockOf(state: state) == nil)
    }

    /// 서버에 있던 금액은 방장이 **손으로 적은 값**일 수 있다. 자동 채우기를 켜 두면 택시비 한 글자를
    /// 고치는 순간 그 조정이 통째로 사라진다.
    @Test("수정 폼은 1대N 자동 채우기를 켜지 않는다")
    func editFormNoAutoSplit() throws {
        let state = try ready(editDraftGate(detail: detail()))
        let refared = state.withFare(raw: "20000")

        #expect(!state.autoSplits)
        #expect(refared.amountInputs[PAYER_ID] == "6234")
        #expect(submitBlockOf(state: refared) == .sumNotEqualFare)
    }

    /// 서버가 23번째 은행을 추가하면 그 코드는 앱의 enum 에 없다. 그래도 **코드를 그대로 되돌려
    /// 보내야** 금액만 고칠 수 있다 — enum 으로 좁히면 그 정산은 영구히 못 고친다.
    @Test("모르는 은행 코드의 정산도 고칠 수 있다")
    func unknownBankEditable() throws {
        let unknownBank = detail(bank: FareSplitBank(code: "NEW_BANK", displayName: "새로생긴은행", known: nil))
        let state = try ready(editDraftGate(detail: unknownBank))

        #expect(state.bankCode == "NEW_BANK")
        // 보여 줄 이름의 출처는 서버다 — 앱이 모르는 코드여도 화면은 정상으로 보인다.
        #expect(state.bankLabel == "새로생긴은행")
        #expect(state.toDraft()?.bankCode == "NEW_BANK")
    }

    @Test("누가 보냈다고 누른 정산은 수정 폼이 열리지 않는다")
    func startedCannotEdit() throws {
        let started = detail(transfers: [transfer(SENDER_A, status: .sent)])

        #expect(try !blocked(editDraftGate(detail: started)).recoverable)
    }

    @Test("보내는 사람은 수정 폼을 열 수 없다")
    func senderCannotEdit() {
        #expect(isBlocked(editDraftGate(detail: detail(role: .sender))))
    }

    @Test("닫힌 정산은 수정 폼을 열 수 없다")
    func closedCannotEdit() {
        #expect(isBlocked(editDraftGate(detail: detail(status: .expired))))
    }

    @Test("서버가 식별하지 못한 보내는 사람이 있으면 수정 폼을 열지 않는다")
    func unidentifiedSenderBlocksEdit() {
        let anonymous = detail(transfers: [transfer(""), transfer(SENDER_B)])

        #expect(isBlocked(editDraftGate(detail: anonymous)))
    }

    // ─────────────────── 문구 ───────────────────

    /// 앱의 **예상 요금**을 칸에 미리 넣지 않는다 — 그대로 제출될 수 있고, 그러면 앱이 지어낸 숫자로
    /// 돈이 움직인다. 힌트로만 보여 준다.
    @Test("예상 요금은 힌트로만 보여 주고 칸에 넣지 않는다")
    func estimateIsHintOnly() throws {
        let withEstimate = ride(estimatedFare: 10_800)
        let state = try ready(startDraftGate(ride: withEstimate))

        #expect(state.fareInput == "")
        #expect(estimatedFareHint(ride: withEstimate) == "앱이 예상한 요금은 10,800원이었어요")
        #expect(estimatedFareHint(ride: ride()) == nil)
        #expect(estimatedFareHint(ride: ride(estimatedFare: 0)) == nil)
    }

    @Test("시작과 수정의 제목과 CTA 가 다르다")
    func titlesAndCtas() {
        #expect(editTitle(mode: .start) == "택시비 정산")
        #expect(editTitle(mode: .edit) == "정산 고치기")
        #expect(editCtaLabel(mode: .start).contains("시작"))
        #expect(editCtaLabel(mode: .edit).contains("저장"))
    }

    /// 누른 뒤에 알면 늦은 두 사실 — 알림이 간다, 그리고 취소할 길이 없다.
    @Test("시작 전에 알림과 취소 불가를 미리 말한다")
    func startNoticeUpfront() {
        #expect(START_IRREVERSIBLE_NOTICE.contains("송금 요청이 가요"))
        #expect(START_IRREVERSIBLE_NOTICE.contains("취소하는 길은 없"))
    }

    // ─────────────────── 로그에 계좌번호가 남지 않는다 (iOS) ───────────────────

    /// 폼 상태를 `print`·`dump`·디버거로 찍어도 **적은 계좌번호 전체가 나오지 않는다** — 끝 네 자리만.
    /// 금액·인원은 그대로 보인다(디버깅에 쓸 값까지 가리면 그 문자열은 쓸모가 없다).
    @Test("폼 상태를 문자열로 찍어도 계좌번호 전체가 나오지 않는다")
    func draftStateRedactsAccount() throws {
        let state = try filled()
        var dumped = ""
        dump(state, to: &dumped)

        for printed in [String(describing: state), String(reflecting: state), "\(state)", dumped] {
            #expect(!printed.contains("3333-01-2345678"))
            #expect(!printed.contains("3333012345678"))
            #expect(!printed.contains("01-2345678"))
            #expect(printed.contains("5678"))
        }
    }
}
