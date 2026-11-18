import Foundation
import MoyeotaDomain

// 40 택시비 정산 시작·수정 화면이 들고 있는 **입력 상태와 그 판정** — 전부 순수 함수다.
//
// ### 왜 떼어 내는가 ★
// 이 화면의 진짜 어려움은 그리기가 아니라 **언제 보낼 수 있는가**다. 서버는 틀린 요청을 400 하나로
// 답하고(`PAYMENTS_NOT_EQUAL_FARE`·`PAYMENT_TARGET_MISMATCH`), 그 실패는 **사용자가 금액을 다 채운
// 뒤에** 돌아온다. 즉 잠금 규칙이 한 칸이라도 틀리면 화면은 멀쩡해 보이는데 **제출만 영구히
// 실패하거나**, 반대로 **잠겨 있어야 할 버튼이 열려** 사용자가 400 을 스스로 만든다. 둘 다
// 스크린샷으로 구분되지 않는다. 그래서 규칙을 값으로 못 박는다(`FareSplitDraftStateTest`).
//
// ### 서버가 앱에 맡긴 일이 여기 있다
// Swagger 원문: 「1/N 로 미리 채우는 것은 앱이 한다」. 즉 **나누는 규칙의 소유자가 앱**이고, 서버는
// 검사만 한다. 그 규칙 자체는 `FareSplitPolicy.splitEvenly` 한 곳에 있으므로 이 파일은 **언제
// 그것을 다시 부르는가**만 정한다 — 나눗셈을 여기서 다시 쓰면 1원 처리가 두 곳으로 갈린다.

/// 택시비 입력의 자릿수 상한 — 9,999,999원.
let MAX_FARE_DIGITS = 7

/// 한 사람 부담 금액 입력의 자릿수 상한.
///
/// 상한이 **없으면 숫자가 넘친다.** 원본(Kotlin 32비트 `Int`)은 10자리를 받으면 `toIntOrNull()` 이 null 이 되고
/// (그건 0 으로 떨어진다), 9자리 넷을 더하면 합이 음수로 감겨 「합계가 택시비와 같다」가 **거짓으로 참이 되는**
/// 조합이 생겼다. iOS 의 `Int` 는 64비트지만 넘치면 크래시이므로 같은 상한을 둔다. 택시비 상한과 같은 자릿수다.
let MAX_AMOUNT_DIGITS = 7

/// 계좌번호 입력의 길이 상한. 서버 상한은 **숫자** 16자리인데(`FareSplitPolicy.ACCOUNT_MAX_DIGITS`)
/// 입력에는 하이픈·공백이 섞일 수 있어 그만큼 여유를 둔다(`3333-01-2345678` 식 표기).
let MAX_ACCOUNT_INPUT_LENGTH = 24

/// 시작인가 수정인가 — **문구와 1/N 자동 채우기 규칙이 갈린다**(`FareSplitDraftState.autoSplits`).
///
/// 이 파일의 다른 것들과 달리 `public` 이다. 내비게이션이 라우트에서 이 값을 만들어 공개 Route
/// (`FareSplitEditRoute`)에 넘기기 때문이다.
public enum FareSplitEditMode: Hashable, Sendable {
    case start
    case edit
}

/// 부담 금액을 적을 사람 한 명.
///
/// `publicId` 는 서버로 가는 식별자다. **빈 값은 여기 올라오지 않는다** — 빌더가 미리 막는다
/// (`startDraftGate`·`editDraftGate`). 빈 값을 섞으면 `amountInputs` 의 키가 겹쳐 두 사람이 한 칸을
/// 나눠 쓰고, 그 요청은 400 `PAYMENT_TARGET_MISMATCH` 다.
///
/// `isPayer` — 받는 사람(= 방장)인가. 1/N 의 **나머지 1원을 흡수하는 사람**이고
/// (`FareSplitPolicy.splitEvenly`) 화면에서 「받는 분」 배지가 붙는다.
public struct FareSplitRider: Hashable, Sendable {
    public var publicId: String
    public var nickname: String
    public var isPayer: Bool
    public var isMe: Bool

    init(publicId: String, nickname: String, isPayer: Bool, isMe: Bool) {
        self.publicId = publicId
        self.nickname = nickname
        self.isPayer = isPayer
        self.isMe = isMe
    }

    /// 표시 이름. 비어 있으면 자리값을 쓴다(`MemberDisplay.displayNickname` 과 같은 규칙).
    public var displayName: String {
        nickname.isBlank ? WithdrawnMemberNames.NO_SUMMARY : nickname
    }
}

/// 입력 상태 하나. **원시 문자열을 들고 있고 숫자로 바꾸는 일은 묻는 자리에서 한다** —
/// `DigitGroupVisualTransformation` 의 교훈과 같은 이유다: 표시용으로 가공한 값을 상태로 들고 있으면
/// 입력 한 글자가 길이 2를 움직여 커서가 어긋난다.
///
/// `public` 인 이유는 `FareSplitEditMode` 와 같다 — 공개 화면(`FareSplitEditScreen`)의 파라미터 타입이다.
/// 만들고 고치는 길은 전부 `internal` 이다(빌더 둘과 `with…` 함수) — 모듈 밖에서 이 값을 조립할 수는 없다.
public struct FareSplitDraftState: Hashable, Sendable {
    public internal(set) var mode: FareSplitEditMode
    public internal(set) var riders: [FareSplitRider]
    public internal(set) var fareInput: String
    public internal(set) var bankCode: String?
    /// 서버가 알려 준 은행 이름. **모르는 은행 코드의 정산을 고칠 때** 쓰인다 — `Bank` 에 없는 코드면
    /// `Bank.ofCodeOrNull` 이 nil 이라 이름을 만들 수 없는데, 그 코드를 그대로 되돌려 보내야 금액만 고칠 수
    /// 있다(`FareSplitDraft.bankCode` 주석).
    public internal(set) var bankDisplayName: String?
    public internal(set) var accountInput: String
    /// publicId → 숫자만. **없는 키는 「아직 안 적었다」**이고 `"0"` 과 다르다
    /// (앞은 버튼만 잠그고, 뒤는 「1원 이상이어야 해요」를 말한다).
    public internal(set) var amountInputs: [String: String]
    /// 택시비가 바뀔 때 금액을 **1/N 로 다시 채울 것인가.**
    public internal(set) var autoSplits: Bool

    init(
        mode: FareSplitEditMode,
        riders: [FareSplitRider],
        fareInput: String = "",
        bankCode: String? = nil,
        bankDisplayName: String? = nil,
        accountInput: String = "",
        amountInputs: [String: String] = [:],
        autoSplits: Bool = true
    ) {
        self.mode = mode
        self.riders = riders
        self.fareInput = fareInput
        self.bankCode = bankCode
        self.bankDisplayName = bankDisplayName
        self.accountInput = accountInput
        self.amountInputs = amountInputs
        self.autoSplits = autoSplits
    }

    /// 받는 사람의 publicId. 빌더가 반드시 한 명을 세워 주므로 비어 있지 않다.
    var payerPublicId: String { riders.first { $0.isPayer }?.publicId ?? "" }

    /// 택시비(원). 비었거나 넘치면 0 이다 — 0 은 `FareSplitPolicy.MIN_TOTAL_FARE` 미달이라 버튼이 잠긴다.
    var totalFare: Int { Int(fareInput) ?? 0 }

    /// 적어 둔 부담 금액의 합(원). **아직 안 적은 칸은 0** 으로 센다.
    var amountSum: Int {
        riders.reduce(0) { $0 + (amountInputs[$1.publicId].flatMap { Int($0) } ?? 0) }
    }

    /// `택시비 − 합계`. **양수면 모자라고 음수면 넘친다.**
    ///
    /// 절댓값만 들고 다니지 않는 이유: 사용자가 할 일이 정반대다(더 적거나 덜 적는다).
    var difference: Int { totalFare - amountSum }

    /// 선택한 은행의 표시 이름. 아직 안 골랐으면 nil.
    var bankLabel: String? {
        guard let code = bankCode else { return nil }
        if let name = bankDisplayName, !name.isBlank { return name }
        return Bank.ofCodeOrNull(code: code)?.displayName ?? code
    }
}

extension FareSplitDraftState: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 적는 중인 계좌번호를 로그·디버그 출력에 남기지 않는다(`FareSplitRedaction`).
    public var description: String {
        "FareSplitDraftState(mode: \(mode), riders: \(riders.count), fareInput: \(fareInput), "
            + "bankCode: \(bankCode ?? "nil"), accountInput: \(FareSplitRedaction.account(accountInput)), "
            + "autoSplits: \(autoSplits))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "mode": mode,
                "riders": riders,
                "fareInput": fareInput,
                "bankCode": bankCode as Any,
                "bankDisplayName": bankDisplayName as Any,
                "accountInput": FareSplitRedaction.account(accountInput),
                "amountInputs": amountInputs,
                "autoSplits": autoSplits,
            ],
            displayStyle: .struct
        )
    }
}

// ─────────────────────────── 빌더 ───────────────────────────

/// 시작·수정 화면을 **열 수 있는가**의 답.
///
/// 빈 폼을 띄우고 제출할 때 막는 방식을 쓰지 않는다 — 방장이 금액을 다 채운 뒤에 「이 방은 정산할 수
/// 없어요」를 받는 것이 가장 나쁘다. 그래서 열기 전에 묻고, 막혔으면 **왜 막혔는지와 할 수 있는
/// 일**을 그 자리에 적는다.
enum FareSplitDraftGate: Equatable, Sendable {
    case ready(FareSplitDraftState)

    /// 열 수 없다. `recoverable` 이 false 면 **이 방은 영구히 정산할 수 없다** — 화면이
    /// 「다시 시도」를 권하지 않아야 하는 경우다(도착은 끝난 방에서 되돌릴 수 없다).
    case blocked(message: String, recoverable: Bool)
}

/// 끝난 방 + 방장 + 탑승자 2명 이상일 때만 시작 폼을 연다 — **서버 `create` 의 세 조건 그대로**다.
///
/// ### 세 조건을 미리 보는 이유와 **보지 못하는 것** ★
/// 서버가 최종 판정이다. 앱이 미리 보는 이유는 **열 수 없는 화면을 열지 않기** 위한 것이고,
/// 세 실패의 처방이 서로 다르기 때문이다(`fareSplitFailureMessage` 의 표). 다만 앱이 모르는
/// 조건이 하나 있다 — **이미 정산이 있는가**(409 `FARE_SPLIT_ALREADY_EXISTS`). 그건 GET 으로만
/// 알 수 있고, 그 경로는 상세 화면이 먼저 밟는다(`FareSplitDetailRoute`).
///
/// ### 금액을 미리 채우지 않는다
/// `Ride.estimatedFare` 가 있지만 그건 **앱의 예상 요금**이고, 이 칸이 묻는 것은 **실제로 낸
/// 택시비**다. 예상값을 넣어 두면 그대로 제출될 수 있고, 그러면 사람마다 부담 금액이 실제와 다른
/// 장부가 만들어진다 — 앱이 지어낸 숫자로 돈이 움직이는 것이 이 화면에서 가장 나쁜 실패다.
/// 예상 요금은 **힌트 문구로만** 보여 준다(`estimatedFareHint`).
func startDraftGate(ride: Ride) -> FareSplitDraftGate {
    if ride.status != .completed {
        return .blocked(
            message: "아직 끝나지 않은 방이에요. 「출발」을 눌러 동승을 끝낸 뒤 정산할 수 있어요",
            recoverable: true
        )
    }
    if !ride.isHostedByMe {
        return .blocked(message: "방장만 정산을 시작할 수 있어요", recoverable: false)
    }

    let riders = ride.fareSplitRiders
    guard let me = riders.first(where: \.isMe) else {
        return .blocked(
            message: "출발지 도착을 누르지 않아 이 방의 탑승자가 아니에요. 이 방은 정산할 수 없어요",
            recoverable: false
        )
    }

    if riders.count < FareSplitPolicy.MIN_RIDERS {
        return .blocked(
            message: "함께 탄 사람이 혼자예요. 나눌 상대가 없어 이 방은 정산할 수 없어요",
            recoverable: false
        )
    }
    // 서버 riderIds 에는 들어 있는데 앱이 지목할 수 없는 멤버다 — 빼고 보내도 400,
    // 넣고 보내도 400 이라(둘 다 PAYMENT_TARGET_MISMATCH) 열어 봐야 제출할 수 없는 폼이 된다.
    if riders.contains(where: { $0.id.isEmpty }) {
        return .blocked(
            message: "서버가 설명하지 못한 탑승자가 있어 정산을 시작할 수 없어요. 잠시 뒤 다시 시도해 주세요",
            recoverable: true
        )
    }

    return .ready(
        FareSplitDraftState(
            mode: .start,
            riders: riders.map { member in
                FareSplitRider(
                    publicId: member.id,
                    nickname: member.nickname,
                    isPayer: member.id == me.id,
                    isMe: member.isMe
                )
            },
            // 택시비를 적는 순간 1/N 로 채워진다 — 그게 Swagger 가 앱에 맡긴 「미리 채우기」다.
            autoSplits: true
        )
    )
}

/// 기존 정산을 **고치는** 폼. 방 상세가 필요 없다 — 탑승자 전원이 이미 상세 안에 있다
/// (받는 사람 + `transfers`).
///
/// ### 1/N 자동 채우기를 **켜지 않는다** ★
/// 여기 들어 있는 금액은 방장이 **손으로 적은 값**일 수 있다(서버는 1/N 을 강제하지 않는다).
/// 자동 채우기를 켜 두면 택시비 한 글자를 고치는 순간 그 조정이 **통째로 사라진다** — 사용자는
/// 자기가 지운 줄 모르고 저장하고, 그러면 다른 사람이 보는 금액이 바뀐다.
/// 「똑같이 나누기」 버튼은 그대로 있으므로 원하면 **명시적으로** 다시 나눌 수 있다(`splitEvenly`).
///
/// ### 계좌번호는 되살릴 수 없다
/// 서버는 상세에 계좌번호를 **OPEN 일 때만** 싣고, 그 값을 프리필한다. 닫힌 정산은 애초에 고칠 수
/// 없으므로(`FareSplitDetail.canEdit`) 이 빌더가 열리지 않는다.
func editDraftGate(detail: FareSplitDetail) -> FareSplitDraftGate {
    if let reason = editBlockReason(detail: detail) {
        return .blocked(message: reason, recoverable: false)
    }
    if !detail.isPayer {
        return .blocked(message: "받는 분만 정산을 고칠 수 있어요", recoverable: false)
    }
    if !detail.payer.isIdentified || detail.transfers.contains(where: { !$0.isConfirmable }) {
        return .blocked(message: "서버가 설명하지 못한 탑승자가 있어 금액을 고칠 수 없어요", recoverable: true)
    }

    var riders = [FareSplitRider(publicId: detail.payer.publicId, nickname: detail.payer.nickname, isPayer: true, isMe: true)]
    riders += detail.transfers.map {
        FareSplitRider(publicId: $0.senderPublicId, nickname: $0.nickname, isPayer: false, isMe: false)
    }

    var amounts = [detail.payer.publicId: String(detail.myAmount)]
    for transfer in detail.transfers {
        amounts[transfer.senderPublicId] = String(transfer.amount)
    }

    return .ready(
        FareSplitDraftState(
            mode: .edit,
            riders: riders,
            fareInput: String(detail.totalFare),
            // 서버가 준 코드를 **그대로** 되돌려 보낸다 — 앱이 모르는 은행이어도 고칠 수 있게.
            bankCode: detail.bank.code,
            bankDisplayName: detail.bank.displayName,
            accountInput: detail.accountNumber ?? "",
            amountInputs: amounts,
            autoSplits: false
        )
    )
}

/// 「앱이 예상했던 요금」 힌트. 없으면 nil — 모르는 숫자를 지어내지 않는다.
func estimatedFareHint(ride: Ride) -> String? {
    guard let estimate = ride.estimatedFare, estimate > 0 else { return nil }
    return "앱이 예상한 요금은 \(fareWonLabel(amount: estimate))이었어요"
}

// ─────────────────────────── 입력 반영 ───────────────────────────

/// 숫자만 남기고 앞의 0 을 버린 뒤 자릿수를 자른다 — 상한의 근거는 `MAX_FARE_DIGITS`·`MAX_AMOUNT_DIGITS` 에 있다.
///
/// 숫자는 **ASCII `0`~`9` 만**이다(원본 `it in '0'..'9'`) — 전각·아랍 숫자를 받으면 `Int(…)` 가 읽지 못해
/// 칸에는 보이는데 합계에는 0 으로 들어간다.
private func digitsOnly(_ raw: String, maxLength: Int) -> String {
    let digits = raw.unicodeScalars.filter { ("0"..."9").contains($0) }
    let trimmed = digits.drop { $0 == "0" }
    var result = String.UnicodeScalarView()
    result.append(contentsOf: trimmed.prefix(maxLength))
    return String(result)
}

extension FareSplitDraftState {
    /// 택시비를 고친다. `autoSplits` 가 켜져 있으면 **금액을 1/N 로 다시 채운다.**
    ///
    /// | 상황 | 택시비를 고치면 |
    /// |---|---|
    /// | 시작 폼, 아직 금액을 손대지 않았다 | 전원 금액이 **다시 1/N** 로 채워진다 |
    /// | 금액을 한 칸이라도 손댔다 | 금액은 **그대로**. 합계가 어긋난 것을 화면이 알려 준다 |
    /// | 수정 폼 | 금액은 **그대로**(`editDraftGate` — 서버에 있던 조정을 지우지 않는다) |
    ///
    /// 나눌 수 없는 택시비(인원보다 적은 금액)에서는 다시 채우지 **않는다** — `FareSplitPolicy.splitEvenly`
    /// 가 던지는 자리이고, 그건 화면 버그를 잡는 장치이지 사용자 입력을 거르는 수단이 아니다.
    func withFare(raw: String) -> FareSplitDraftState {
        var next = self
        next.fareInput = digitsOnly(raw, maxLength: MAX_FARE_DIGITS)
        return next.autoSplits ? next.splitEvenlyOrSame() : next
    }

    /// 한 사람의 금액을 고친다 — **이 순간부터 1/N 자동 채우기가 멈춘다.**
    ///
    /// 멈추지 않으면 택시비를 한 글자 고칠 때마다 사용자가 방금 조정한 금액이 사라진다.
    /// 「똑같이 나누기」를 다시 누르면 자동 채우기도 함께 되살아난다(`splitEvenly`).
    func withAmount(publicId: String, raw: String) -> FareSplitDraftState {
        let digits = digitsOnly(raw, maxLength: MAX_AMOUNT_DIGITS)
        var next = self
        if digits.isEmpty {
            next.amountInputs.removeValue(forKey: publicId)
        } else {
            next.amountInputs[publicId] = digits
        }
        next.autoSplits = false
        return next
    }

    /// 은행을 고른다. 목록에서 고른 경우이므로 **표시 이름도 함께** 바꾼다 — 안 바꾸면 수정 폼에서
    /// 서버가 준 옛 이름이 새 코드 옆에 남는다.
    func withBank(bank: Bank) -> FareSplitDraftState {
        var next = self
        next.bankCode = bank.code
        next.bankDisplayName = bank.displayName
        return next
    }

    /// 계좌번호를 고친다. **하이픈·공백을 지우지 않는다** — 은행 앱이 복사해 주는 모양(`3333-01-2345678`)을
    /// 그대로 붙여넣게 하고, 떼어 내는 일은 매퍼가 보내기 직전에 한다(`FareSplitPolicy.normalizeAccountNumber`).
    ///
    /// 숫자·하이픈·공백이 **아닌** 문자는 받지 않는다. 지우는 것과 다르다: 조용히 지우면
    /// 「3333.01.2345678」이 통과해 **사용자가 확인하지 않은 계좌번호**가 만들어지고, 송금은 앱이 아니라
    /// 사용자가 하므로 그 틀림은 되돌릴 수 없다(그 근거는 `normalizeAccountNumber` 주석에 있다).
    /// 그래서 받지 않고, 틀린 값이 남아 있으면 버튼을 잠근 채 이유를 말한다(`accountErrorText`).
    func withAccount(raw: String) -> FareSplitDraftState {
        let kept = raw.unicodeScalars.filter { ("0"..."9").contains($0) || $0 == "-" || $0 == " " }
        var input = String.UnicodeScalarView()
        input.append(contentsOf: kept.prefix(MAX_ACCOUNT_INPUT_LENGTH))
        var next = self
        next.accountInput = String(input)
        return next
    }

    /// 「똑같이 나누기」 — `FareSplitPolicy.splitEvenly` 를 그대로 부르고 자동 채우기를 **되살린다.**
    ///
    /// 나머지 1원은 **받는 사람이 흡수한다**(근거는 그 함수의 표에 있다) — 보내는 금액이 전원 같아져
    /// 「왜 나만 1원 더 내나」가 생기지 않는다. 그 사실은 화면이 한 줄로 알려 준다
    /// (`evenSplitRemainderNotice`).
    func splitEvenly() -> FareSplitDraftState {
        var next = splitEvenlyOrSame()
        next.autoSplits = true
        return next
    }

    /// 나눌 수 없으면 **그대로 돌려준다** — 던지지 않는다(사용자가 「2」를 넣을 수 있다).
    private func splitEvenlyOrSame() -> FareSplitDraftState {
        guard canSplitEvenly(),
              let shares = try? FareSplitPolicy.splitEvenly(
                  totalFare: totalFare,
                  payerPublicId: payerPublicId,
                  riderPublicIds: riders.map(\.publicId)
              )
        else { return self }

        var next = self
        next.amountInputs = Dictionary(uniqueKeysWithValues: shares.map { ($0.riderPublicId, String($0.amount)) })
        return next
    }

    /// 「똑같이 나누기」를 **누를 수 있는가** — 택시비가 인원보다 적으면 누구를 0원으로 만들 수밖에 없다.
    func canSplitEvenly() -> Bool {
        FareSplitPolicy.canSplitEvenly(totalFare: totalFare, riderCount: riders.count)
    }

    /// 지금 적힌 값으로 만든 부담 금액 목록. **아직 안 적은 칸은 0** 이다(그 상태로는 버튼이 잠긴다).
    func sharesOf() -> [FareShare] {
        riders.map { rider in
            FareShare(riderPublicId: rider.publicId, amount: amountInputs[rider.publicId].flatMap { Int($0) } ?? 0)
        }
    }

    /// 서버로 보낼 값. **`submitBlockOf` 가 nil 일 때만 부른다** — 은행을 고르지 않았으면 nil 이다
    /// (원본은 그 경우 던진다. 화면 버그를 잡는 장치라는 뜻은 같고, iOS 는 호출부가 nil 을 보고 보내지 않는다).
    ///
    /// 계좌번호를 여기서 정규화하지 않는다 — 매퍼가 보내기 직전에 한다
    /// (`FareSplitDraft.accountNumber` 주석). 두 곳에서 하면 한쪽이 바뀔 때 조용히 갈린다.
    func toDraft() -> FareSplitDraft? {
        guard let bankCode else { return nil }
        return FareSplitDraft(totalFare: totalFare, bankCode: bankCode, accountNumber: accountInput, shares: sharesOf())
    }
}

/// 1/N 의 나머지를 누가 내는지 한 줄. 나누어떨어지면 nil 이다 — 할 말이 없다.
///
/// 이 줄이 있어야 하는 이유: 1/N 을 눌렀는데 받는 사람의 금액만 1~2원 다른 것이 **버그로 보인다.**
/// 「1인당 N원」이라고 단정하지 않는 이 화면에서, 다른 이유로 다른 금액이 섞이는 것을 미리 설명한다.
func evenSplitRemainderNotice(state: FareSplitDraftState) -> String? {
    guard state.canSplitEvenly() else { return nil }
    let remainder = state.totalFare % state.riders.count
    if remainder == 0 { return nil }
    return "나누어떨어지지 않는 \(remainder)원은 받는 분이 부담해요"
}

// ─────────────────────────── 제출 잠금 ───────────────────────────

/// CTA 를 잠근 **하나의** 이유. 여럿을 한꺼번에 띄우지 않는다 — 사용자가 **다음에 할 일 하나**만
/// 알면 되고, 다섯 줄짜리 오류 목록은 읽히지 않는다.
///
/// 값을 뭉치지 않는 이유는 `FareSplitDraftProblem` 과 같다: 할 일이 서로 다르다. 합이 안 맞는 것은
/// 금액 칸을 고치면 되고, 대상이 어긋난 것은 금액을 아무리 고쳐도 풀리지 않는다.
enum FareSplitSubmitBlock: CaseIterable, Equatable, Sendable {
    /// 택시비를 아직 적지 않았다. **문구 없음** — 적기 전에 꾸짖지 않는다.
    case fareEmpty
    case fareBelowMinimum
    /// 은행을 아직 고르지 않았다. 문구 없음.
    case bankNotSelected
    /// 계좌번호를 아직 적지 않았다. 문구 없음.
    case accountEmpty
    case accountInvalid
    /// 아직 비어 있는 금액 칸이 있다. 문구 없음.
    case amountEmpty
    case shareBelowMinimum
    case sumNotEqualFare
    case notEnoughRiders
    case riderNotIdentified
    case targetMismatch
}

/// **보낼 수 있는가** — nil 이면 보낼 수 있다.
///
/// 폼의 위에서 아래 순서로 본다(택시비 → 은행 → 계좌 → 금액). 그 순서가 사용자가 칸을 채우는
/// 순서이고, 「다음에 할 일」을 가리키려면 **아직 안 지난 칸**을 먼저 말해야 한다.
///
/// 금액 쪽 판정은 `FareSplitPolicy.problemOf` 에 그대로 넘긴다 — 서버가 400 으로 거절할 이유를
/// 아는 곳은 거기 하나다. 여기서 다시 세우면 두 판정이 갈려 **버튼은 열리는데 서버가 막는** 조합이
/// 생긴다.
func submitBlockOf(state: FareSplitDraftState) -> FareSplitSubmitBlock? {
    if state.fareInput.isEmpty { return .fareEmpty }
    if state.totalFare < FareSplitPolicy.MIN_TOTAL_FARE { return .fareBelowMinimum }
    if state.bankCode?.isBlank ?? true { return .bankNotSelected }
    if state.accountInput.isBlank { return .accountEmpty }
    if !FareSplitPolicy.isAccountNumberValid(raw: state.accountInput) { return .accountInvalid }
    if state.riders.contains(where: { state.amountInputs[$0.publicId]?.isEmpty ?? true }) { return .amountEmpty }

    switch FareSplitPolicy.problemOf(
        totalFare: state.totalFare,
        riderPublicIds: state.riders.map(\.publicId),
        shares: state.sharesOf()
    ) {
    case nil: return nil
    case .fareBelowMinimum: return .fareBelowMinimum
    case .notEnoughRiders: return .notEnoughRiders
    // 빌더가 먼저 막는 경우다(`startDraftGate`). 그래도 남겨 두는 것은 방어다 —
    // 빌더를 지나쳐 들어오는 길이 생기면 버튼이 **열린 채** 400 으로만 끝난다.
    case .riderNotIdentified: return .riderNotIdentified
    case .targetMismatch: return .targetMismatch
    case .shareBelowMinimum: return .shareBelowMinimum
    case .sumNotEqualFare: return .sumNotEqualFare
    }
}

/// 잠금 사유를 **화면 아래 경고로 띄울 때**의 문구. nil 이면 아무것도 띄우지 않는다.
///
/// ### 「아직 안 적었다」에는 문구가 없다 ★
/// 화면을 열자마자 「택시비를 적어 주세요」·「은행을 골라 주세요」가 빨간 띠로 떠 있으면, 사용자는
/// 아무 잘못도 하지 않았는데 오류 화면을 본다. 빈 칸은 **버튼이 잠겨 있는 것으로 충분히** 말한다.
/// 문구가 필요한 것은 **적었는데 틀린** 경우다.
///
/// `sumNotEqualFare` 가 nil 인 것도 비슷하지만 이유가 다르다 — 그 차이는 금액 칸 바로 아래 **합계 줄**이
/// 실시간으로 말하고 있어(`sumLabel`·`differenceNotice`) 같은 말을 두 군데서 하면 어느 쪽을 고쳐야 하는지 흐려진다.
func submitBlockMessage(block: FareSplitSubmitBlock?) -> String? {
    switch block {
    case nil, .fareEmpty, .bankNotSelected, .accountEmpty, .amountEmpty, .sumNotEqualFare: nil
    case .fareBelowMinimum: "택시비는 1원 이상이어야 해요"
    case .accountInvalid: "계좌번호는 숫자 10~16자리여야 해요"
    case .shareBelowMinimum: "한 사람당 1원 이상이어야 해요"
    case .notEnoughRiders: "함께 탄 사람이 혼자예요. 나눌 상대가 없어 정산할 수 없어요"
    case .riderNotIdentified: "서버가 설명하지 못한 탑승자가 있어 보낼 수 없어요"
    case .targetMismatch: "정산 대상이 어긋났어요. 탑승 정보를 다시 불러와 주세요"
    }
}

/// 계좌번호 칸 **아래**에 붙는 오류. 아직 적지 않았으면 nil 이다(빈 칸을 틀렸다고 말하지 않는다).
///
/// 서버가 400 `INVALID_ACCOUNT_NUMBER` 로 답하는 것과 **같은 판정**이라
/// (`FareSplitPolicy.isAccountNumberValid` 가 서버 `AccountNumber` 와 같은 규칙이다) 이 문구가
/// 떠 있는 동안 제출은 반드시 거절된다 — 즉 이 칸은 「서버가 받아 줄 것인가」의 정확한 예측이다.
func accountErrorText(state: FareSplitDraftState) -> String? {
    if state.accountInput.isBlank { return nil }
    if FareSplitPolicy.isAccountNumberValid(raw: state.accountInput) { return nil }
    return "숫자 10~16자리로 적어 주세요"
}

// ─────────────────────────── 합계 표시 ───────────────────────────

/// 「합계 18,700원 / 택시비 18,700원」 — 두 수를 **나란히** 보여 준다(한쪽만 보여 주면 비교할 수 없다).
func sumLabel(state: FareSplitDraftState) -> String {
    "합계 \(fareWonLabel(amount: state.amountSum)) / 택시비 \(fareWonLabel(amount: state.totalFare))"
}

/// 합계가 택시비와 **얼마나 어긋났는가**를 실시간으로 말하는 줄. 톤까지 함께 정한다.
///
/// ### 이 줄이 서버 400 을 대신한다 ★
/// 서버는 합이 다르면 400 `PAYMENTS_NOT_EQUAL_FARE` **하나로만** 답한다 — 얼마나 어긋났는지,
/// 어느 칸을 고쳐야 하는지 알려 주지 않고, 그 답은 **입력을 다 끝낸 뒤에** 온다. 그래서 차액을
/// 금액으로, 입력하는 동안 말한다. 「모자라다」와 「많다」를 가르는 이유는 할 일이 정반대라서다.
///
/// 택시비를 아직 적지 않았으면 nil 이다 — 0원과의 차이를 말할 자리가 아니다.
func differenceNotice(state: FareSplitDraftState) -> FareSplitBadge? {
    if state.fareInput.isEmpty { return nil }
    let diff = state.difference

    if diff == 0 { return FareSplitBadge(tone: .done, label: "합계가 택시비와 같아요") }
    if diff > 0 { return FareSplitBadge(tone: .warn, label: "택시비보다 \(fareWonLabel(amount: diff)) 모자라요") }
    return FareSplitBadge(tone: .warn, label: "택시비보다 \(fareWonLabel(amount: -diff)) 많아요")
}

// ─────────────────────────── 문구 ───────────────────────────

/// 화면 제목. 시작과 수정이 **다른 일**이라 글자도 다르다.
func editTitle(mode: FareSplitEditMode) -> String {
    switch mode {
    case .start: "택시비 정산"
    case .edit: "정산 고치기"
    }
}

/// CTA 글자. 「저장」이 아니라 「시작」인 쪽은 **보내는 사람 전원에게 알림이 간다**(서버 Swagger).
func editCtaLabel(mode: FareSplitEditMode) -> String {
    switch mode {
    case .start: "정산 시작하고 알리기"
    case .edit: "수정 저장하기"
    }
}

/// 시작 CTA 를 누르기 전에 한 번 말해 주는 사실 — **되돌릴 수 없는 쪽**이다.
///
/// 「정산 취소는 없다」(Swagger 원문)와 「보내는 사람 전원에게 알림이 간다」는 둘 다 누른 뒤에 알면
/// 늦다. 수정 모드에서는 띄우지 않는다(이미 있는 정산을 고치는 것이고, 알림은 다시 가지 않는다).
let START_IRREVERSIBLE_NOTICE =
    "시작하면 함께 탄 분들에게 송금 요청이 가요. 정산을 취소하는 길은 없고, 금액은 아무도 보내기 전까지만 고칠 수 있어요"
