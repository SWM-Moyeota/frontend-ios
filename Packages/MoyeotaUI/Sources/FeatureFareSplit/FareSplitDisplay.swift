import Foundation
import MoyeotaDomain

// 39·40 택시비 정산의 **표시 규칙** — 무엇을 글자로 만들고, 어떤 버튼을 그리고, 무엇을 말하지 않는가.
//
// ### 왜 화면에서 떼어 내는가 ★
// 이 화면들의 판정은 **눈으로 확인할 수 없는 것들**이다. 「받았어요」가 NOT_SENT 행에도 떠야 하고
// 「아직 안 들어왔어요」는 SENT 행에만 떠야 한다는 차이는 스크린샷으로 구분되지 않는다 —
// 틀렸을 때 드러나는 모습은 **409 `TRANSFER_NOT_SENT`** 하나이고, 그것도 사용자가 누른 뒤에야 온다.
// 더 나쁜 쪽은 아예 드러나지 않는다: 두 버튼이 **바뀌어 달려 있으면 둘 다 204 로 성공해 보인다**
// (아래 `TransferActions` 참고). 그래서 판정은 SwiftUI 를 모르는 순수 함수로 빼고
// `FareSplitDisplayTest`·`FareSplitActionGateTest` 가 값으로 못 박는다.
//
// `MeetingFlow.swift`(21 약속 흐름)·`RideHistoryDisplay.swift`(34 기록 표기)와 같은 자리·같은 이유다.
// SwiftUI 를 모르는 파일로 둔다.
//
// ### 이 파일이 **하지 않는** 약속들
//
// | 하지 않는 말 | 왜 |
// |---|---|
// | 「이미 보냈습니다」 | 「보냈어요」·「받았어요」는 **멱등 204** 다 — 「이미 그 상태였다」와 「지금 바뀌었다」를 서버 응답으로 **구분할 수 없다**. 지어내면 틀릴 수 있다 |
// | 「1인당 N원」 | 금액은 1/N 이 아니다(백엔드 `fe6ba35a`). 방장이 사람마다 적은 값이라 **같은 방을 보는 두 사람이 다른 값을 본다** |
// | 「하루 지나면 사라져요」 | EXPIRED 스윕이 30분 cron 이라 실제 경계는 **1일 + 최대 30분**이다(`EXPIRY_NOTICE`) |
// | 서버 원문 message | 400 `INVALID_REQUEST` 의 message 는 `totalFare: …` 처럼 **필드명을 그대로** 담는다(`fareSplitFailureMessage`) |
// | 「입금됨」 | 서버가 아는 것은 **보내는 사람이 버튼을 눌렀다**는 사실뿐이다(`transferStatusLabel`) |

// ─────────────────────────── 색 톤 ───────────────────────────

/// 안내·배지의 **뜻**. 디자인 시스템의 `NoticeKind` 를 여기서 쓰지 않는 이유는 두 가지다.
///
/// 1. **이 파일은 SwiftUI 를 몰라야 한다.** `NoticeKind` 는 디자인시스템 모듈에 있어, import 하면 이 판정들이
///    화면 모듈의 사정(색·모양)과 한 덩어리가 된다(`MeetingFlow.swift`·`RideHistoryDisplay.swift` 와 같은 제약이다).
/// 2. **뜻과 색은 다른 층의 일이다.** 「기간 지남」이 주의색이어야 하는 근거는 도메인 쪽 사실이고
///    (COMPLETED 와 섞이면 안 된다), 그 주의색이 무슨 색인지는 디자인 시스템의 일이다.
///
/// 색으로 옮기는 자리는 화면 파일의 `noticeKindOf` 한 곳뿐이다.
enum FareSplitTone: Equatable, Sendable {
    /// 진행 중·중립.
    case info
    /// 아직 할 일이 남았다(아직 안 보냄 · 기간 지남).
    case warn
    /// 끝났다(받음 확인 · 정산 완료).
    case done
    /// 막혔다(계좌 소실 · 내 송금을 못 찾음 · 실패).
    case danger
}

// ─────────────────────────── 금액·이름 표기 ───────────────────────────

/// 금액 표기 — `%,d원`. 이 앱의 다른 요금 자리들과 **같은 모양**이다
/// (34 기록의 `wonLabel`, 14·15 의 예상 요금).
///
/// 이름에 `fare` 를 붙인 이유는 34 의 `wonLabel` 과 **다른 모듈의 같은 이름**이 되는 것을 피하려는
/// 것이다 — 두 모듈을 함께 보는 날 어느 쪽이 쓰였는지 읽는 사람이 알 수 없어진다.
///
/// 기기 로케일을 따르지 않는다 — 세 자리마다 쉼표를 직접 넣는다(34 `wonLabel` 과 같은 방식). 금액은 송금에
/// 그대로 옮겨 적는 숫자라 기기 설정에 따라 점·공백으로 끊기면 은행 앱에 옮길 때 헷갈린다.
func fareWonLabel(amount: Int) -> String {
    let digits = Array(String(amount.magnitude))
    var grouped = ""
    for (index, digit) in digits.enumerated() {
        if index > 0 && (digits.count - index) % 3 == 0 { grouped.append(",") }
        grouped.append(digit)
    }
    return "\(amount < 0 ? "-" : "")\(grouped)원"
}

extension FareSplitParticipant {
    /// 정산에 등장하는 사람의 표시 이름.
    ///
    /// 서버가 요약을 못 찾으면 닉네임 자리가 `WithdrawnMemberNames.NO_SUMMARY` 로 와 있고, 탈퇴한
    /// 사용자는 서버가 `WithdrawnMemberNames.SERVER_DELETED` 를 직접 넣는다 — **둘을 하나로 접지 않는
    /// 것**은 `MemberDisplay` 와 같은 관례지만, 이 화면이 둘을 가르는 자리는 **이름이 아니라 버튼**이다
    /// (`FareSplitTransfer.isConfirmable`). 그래서 표시 이름은 「비어 있으면 자리값」까지만 본다.
    var displayName: String {
        nickname.isBlank ? WithdrawnMemberNames.NO_SUMMARY : nickname
    }
}

extension FareSplitTransfer {
    /// 보내는 사람의 표시 이름. `FareSplitParticipant.displayName` 과 같은 규칙이다.
    var displayName: String {
        nickname.isBlank ? WithdrawnMemberNames.NO_SUMMARY : nickname
    }
}

/// 받는 사람(PAYER)에게만 보이는 **입금자명 대조 거리** — 「홍*동」.
///
/// 쓰임이 하나뿐이고 그 쓰임이 화면에서 읽혀야 한다: 받는 사람이 **은행 앱 입금 내역의 이름과
/// 맞춰 보는 것**이다(`DEPOSITOR_HINT_PURPOSE`). 닉네임만 있으면 「서면가자」가 입금 내역에
/// 뜨지 않으므로 누가 보낸 돈인지 확인할 길이 없다.
///
/// 보내는 사람 화면에서는 **늘 nil** 이고 그게 정상이다 — 서버가 `isPayer(viewer)` 일 때만 채운다.
/// nil 을 「실명이 없는 사용자」로 읽지 말 것.
func depositorHintOrNull(transfer: FareSplitTransfer) -> String? {
    guard let name = transfer.maskedRealName, !name.isBlank else { return nil }
    return "입금자명 \(name)"
}

/// 입금자명 칸이 **무엇에 쓰이는지** 한 번만 적는다 — 행마다 되풀이하면 목록이 설명문이 된다.
let DEPOSITOR_HINT_PURPOSE = "입금자명은 은행 앱 입금 내역과 맞춰 보기 위한 거예요"

/// 홈 배너 한 줄의 경로 표기 — `출발 → 도착`. **둘 다 없으면 nil 이고, 그때는 줄을 그리지 않는다.**
///
/// 서버는 방을 못 찾으면 둘을 **함께** null 로 준다(방이 지워진 뒤에도 정산은 남는다). 그때
/// 「경로 정보 없음」 같은 자리값을 넣지 않는 이유: 사용자가 보내야 할 돈은 그대로 있고, 그 줄에
/// 필요한 것은 금액과 받는 사람이다 — 모르는 것을 모른다고 적는 줄을 하나 더 두면 **배너가
/// 「뭔가 잘못됐다」로 읽힌다**(34 기록의 `routeLabel` 과 같은 판단).
func myFareSplitRouteLabel(item: MyFareSplit) -> String? {
    let from = item.departure.flatMap { $0.isBlank ? nil : $0 }
    let to = item.destination.flatMap { $0.isBlank ? nil : $0 }

    switch (from, to) {
    case let (from?, to?): return "\(from) → \(to)"
    case let (from?, nil): return from
    case let (nil, to?): return to
    case (nil, nil): return nil
    }
}

// ─────────────────────────── 상태 표기 ───────────────────────────

/// 배지 하나 — 글자와 색을 **함께** 정한다(한쪽만 고치면 초록색 「기간 지남」이 생긴다).
struct FareSplitBadge: Equatable, Sendable {
    var tone: FareSplitTone
    var label: String
}

/// 정산 전체의 상태 배지.
///
/// ### COMPLETED 와 EXPIRED 를 「닫힘」 하나로 접지 않는다 ★
/// 앞은 **돈이 다 건너갔다**는 뜻이고 뒤는 **아무도 보내지 않은 채로 시간이 다 됐을 수도 있다**는
/// 뜻이다(`FareSplitStatus` 주석). 같은 문구·같은 색으로 뭉개면 만료된 정산을 본 사람이 「정산이
/// 끝났다」로 읽고 **자기 몫을 영영 보내지 않는다** — 서버에 정산을 다시 시작하는 길은 없다
/// (방마다 정산은 하나뿐이다).
///
/// 그래서 EXPIRED 는 초록(success)이 아니라 **주의(waiting)** 다. 빨강(error)도 쓰지 않는다 —
/// 오류가 아니라 **시간이 다 된 상태**이고, 빨강은 「불러오지 못했어요」류와 섞인다.
func fareSplitBadge(status: FareSplitStatus) -> FareSplitBadge {
    switch status {
    case .open: FareSplitBadge(tone: .info, label: "정산 중")
    case .completed: FareSplitBadge(tone: .done, label: "정산 완료")
    case .expired: FareSplitBadge(tone: .warn, label: "기간 지남")
    }
}

/// 상태를 **설명하는** 한 줄. OPEN 은 nil 이다 — 진행 중인 정산에는 설명할 것이 없고, 할 일은
/// 버튼이 말한다.
///
/// EXPIRED 문구가 「정산이 끝났어요」가 **아닌** 이유는 `fareSplitBadge` 에 적어 두었다. 그 대신
/// 할 수 있는 일을 가리킨다 — 돈을 옮기는 길은 앱 밖에 있으므로(앱은 돈을 옮기지 않는다)
/// **채팅**이 유일하게 남은 수단이다.
func fareSplitStatusNotice(status: FareSplitStatus) -> String? {
    switch status {
    case .open: nil
    case .completed: "모두 받았다고 확인돼 정산이 끝났어요. 계좌번호는 서버에서 지워졌어요"
    case .expired: "시작한 지 하루가 넘어 닫힌 정산이에요. 아직 주고받지 못한 돈이 있다면 채팅으로 이야기해 주세요"
    }
}

/// 진행 중인 정산의 발 밑에 한 번 적는 만료 안내.
///
/// ### 「하루 지나면 사라져요」라고 적으면 **지킬 수 없는 약속**이 된다 ★
/// 서버가 만료를 재는 기준은 1일(`FareSplit.EXPIRES_AFTER`)인데 그걸 **실제로 닫는 일은 30분마다
/// 도는 스윕**이다. 즉 실제 경계는 「1일 + 최대 30분」이고, 24시간 1분이 지난 정산이 아직 열려
/// 있는 것도, 24시간 29분에 갑자기 닫히는 것도 모두 정상이다. 분 단위 카운트다운을 띄우면 **둘 중
/// 어느 모습도 화면과 맞지 않는다.**
///
/// 그래서 숫자를 「하루」까지만 말하고, **정리 시점이 늦을 수 있다**는 사실을 함께 적는다 —
/// 사용자가 할 수 있는 일(미루지 않는 것)은 그 둘만 알아도 충분하다.
let EXPIRY_NOTICE = "정산은 시작한 지 하루가 지나면 닫혀요. 정리 시점은 조금 늦을 수 있으니 마지막까지 미루지 말아 주세요"

/// 앱이 **하지 않는 일**을 적는다 — 송금 버튼이 돈을 옮긴다고 읽히면 안 된다(서버 Tag 원문과 같은 사실).
let APP_DOES_NOT_MOVE_MONEY = "모여타는 돈을 옮기지 않아요. 송금은 토스·은행 앱에서 직접 해 주세요"

/// 송금 한 건의 상태 배지.
///
/// ### SENT 를 「입금됨」이라고 적지 않는다 ★
/// 서버가 아는 것은 **보내는 사람이 버튼을 눌렀다**는 사실뿐이다(`sentAt` 기록이 전부). 실제 입금을
/// 확인한 사람은 아무도 없고, 확인하는 주체는 그 다음 단계의 받는 사람이다. 「입금됨」으로 적으면
/// 받는 사람이 **자기 은행 앱을 보지 않고** 「받았어요」를 누르게 되고, 그 확인은 되돌릴 수 없다.
func transferStatusLabel(status: TransferStatus) -> FareSplitBadge {
    switch status {
    case .notSent: FareSplitBadge(tone: .warn, label: "아직 안 보냄")
    case .sent: FareSplitBadge(tone: .info, label: "보냈다고 알림")
    case .confirmed: FareSplitBadge(tone: .done, label: "받음 확인")
    }
}

// ─────────────────────────── 받는 사람(PAYER) ───────────────────────────

/// 받는 사람 화면 머리의 숫자들. **「1인당」이 없는 것이 이 타입의 요점이다** —
/// 금액은 사람마다 다를 수 있어 하나의 수로 접을 수 없다.
struct PayerSummary: Equatable, Sendable {
    var totalFare: Int
    var myAmount: Int
    /// 보내는 사람들이 보낼 금액의 합. `FareSplitDetail.totalFare` 와 다르다(내 부담 몫이 빠져 있다).
    var toReceive: Int
    /// 그중 **아직 확인하지 않은** 금액. CONFIRMED 가 아닌 행을 모두 센다 —
    /// SENT 도 포함이다(눌렀다는 사실이 입금을 뜻하지 않는다).
    var outstanding: Int
    var confirmedCount: Int
    var transferCount: Int
}

/// 받는 사람 화면의 요약. 전부 `FareSplitDetail` 안의 값에서 나온다 — 화면이 다시 더하지 않는다.
func payerSummaryOf(detail: FareSplitDetail) -> PayerSummary {
    PayerSummary(
        totalFare: detail.totalFare,
        myAmount: detail.myAmount,
        toReceive: detail.transfers.reduce(0) { $0 + $1.amount },
        outstanding: detail.transfers.filter { $0.status != .confirmed }.reduce(0) { $0 + $1.amount },
        confirmedCount: detail.transfers.filter { $0.status == .confirmed }.count,
        transferCount: detail.transfers.count
    )
}

/// 「3명 중 1명 확인」. 보낼 사람이 없는 정산은 서버가 만들지 않으므로(`MIN_RIDERS`) 0 분모는 없다.
func confirmedProgressLabel(summary: PayerSummary) -> String {
    "\(summary.transferCount)명 중 \(summary.confirmedCount)명 확인"
}

/// 송금 한 행에서 **누를 수 있는 것** — 이 파일에서 가장 조심한 판정이다.
///
/// ### 두 버튼을 바꿔 달면 **둘 다 성공해 보인다** ★★
/// 「받았어요」(`confirmReceived`)와 「아직 안 들어왔어요」(`markNotReceived`)는 둘 다 204 다.
/// 그런데 뜻이 정반대이고 **한쪽은 되돌릴 수 없다**:
///
/// | 누른 것 | 서버가 하는 일 | 되돌릴 수 있나 |
/// |---|---|---|
/// | 받았어요 | → CONFIRMED. **마지막 한 건이면 정산을 COMPLETED 로 닫고 계좌번호를 지운다** | **없다** |
/// | 아직 안 들어왔어요 | SENT → NOT_SENT (`sentAt` 삭제) | 보내는 사람이 다시 누르면 된다 |
///
/// 즉 되돌리려던 송금을 확인으로 닫으면 복구 경로가 **하나도** 없다. 그래서 이 판정은 화면 안의
/// 조건식이 아니라 테스트가 못 박는 함수로 둔다.
///
/// ### 세 가지 잠금이 서로 다른 이유에서 나온다
///
/// | 잠그는 행 | 근거 | 잠그지 않으면 |
/// |---|---|---|
/// | `isConfirmable == false`(publicId 가 빈 행) | 서버가 그 멤버를 식별하지 못했다 | 404 `FARE_SPLIT_TRANSFER_NOT_FOUND` 가 **영구히** 나고, 그 한 행 때문에 정산이 COMPLETED 로 닫히지 않는다 |
/// | CONFIRMED 행의 두 버튼 | 확인은 되돌릴 수 없고, 「아직 안 들어왔어요」는 409 `TRANSFER_NOT_SENT` 다 | 되돌릴 수 있다는 **거짓 희망**을 준다 |
/// | NOT_SENT 행의 「아직 안 들어왔어요」 | **멱등이 아닌 유일한 동작**이다 — SENT 에서만 된다 | 409 `TRANSFER_NOT_SENT`. 「두 번 눌러도 괜찮다」가 성립하지 않는다 |
///
/// **NOT_SENT 행의 「받았어요」는 열어 둔다** — 서버가 명시적으로 허용한다(현금으로 받은 경우).
/// 「SENT 를 거치지 않은 CONFIRMED」를 이상 상태로 보면 안 된다(`TransferStatus` 주석).
struct TransferActions: Equatable, Sendable {
    /// 「받았어요」를 누를 수 있는가.
    var canConfirm: Bool
    /// 「아직 안 들어왔어요」를 **그릴** 수 있는가. 비활성 버튼을 두지 않고 아예 그리지 않는다 —
    /// 비활성이어도 그 자리에 있으면 눌릴 자리로 읽힌다.
    var canMarkNotReceived: Bool
    /// 잠근 이유. **버튼을 그리지 않는 경우에는 nil** 이다(설명할 버튼이 없다).
    /// 값이 있는 경우는 「행은 보이는데 누를 수 없다」 하나뿐이다.
    var lockReason: String?
}

/// 받는 사람도 아니거나 닫힌 정산 — 버튼이 **한 개도** 없다.
private let NoTransferActions = TransferActions(canConfirm: false, canMarkNotReceived: false, lockReason: nil)

/// 위 표를 그대로 옮긴 판정. 위에서부터 읽는다 — 앞의 가지가 뒤를 가린다.
func transferActionsOf(detail: FareSplitDetail, transfer: FareSplitTransfer) -> TransferActions {
    // 역할·상태가 아니라면 버튼 자리가 통째로 없다. 서버도 403·409 로 막는다.
    if !detail.isPayer || !detail.isOpen { return NoTransferActions }
    // 부를 수 있는 id 가 없다 — 지어내면 404 다. 이 행만 왜 못 누르는지 적어 준다.
    if !transfer.isConfirmable {
        return TransferActions(
            canConfirm: false,
            canMarkNotReceived: false,
            lockReason: "서버가 이 분을 확인하지 못해 여기서 처리할 수 없어요. 채팅으로 이야기해 주세요"
        )
    }
    switch transfer.status {
    case .confirmed:
        return TransferActions(
            canConfirm: false,
            canMarkNotReceived: false,
            lockReason: "이미 받았다고 확인한 송금이에요. 확인은 되돌릴 수 없어요"
        )
    // SENT — 되돌리기가 **되는 유일한 상태**다.
    case .sent:
        return TransferActions(canConfirm: true, canMarkNotReceived: true, lockReason: nil)
    // NOT_SENT — 현금으로 받았으면 바로 확인할 수 있다. 되돌릴 것은 없다.
    case .notSent:
        return TransferActions(canConfirm: true, canMarkNotReceived: false, lockReason: nil)
    }
}

/// 이 송금을 확인하면 **정산이 닫히는가** — 나머지가 모두 CONFIRMED 다.
///
/// 확인 다이얼로그가 이 사실을 말해야 한다: 마지막 한 건의 「받았어요」는 한 사람의 상태를 바꾸는
/// 것이 아니라 **정산 전체를 끝내고 계좌번호를 지우는** 동작이다. 미리 말하지 않으면 사용자는
/// 같은 버튼을 세 번 누르는 동안 **마지막 한 번만 뜻이 달랐다는 것**을 모른 채 지나간다.
func isLastOutstandingTransfer(detail: FareSplitDetail, transfer: FareSplitTransfer) -> Bool {
    detail.transfers
        .filter { $0.senderPublicId != transfer.senderPublicId }
        .allSatisfy { $0.status == .confirmed }
}

/// 「받았어요」 확인 다이얼로그 본문. **되돌릴 수 없다**를 늘 말하고, 마지막 한 건이면 그 사실을 더한다.
///
/// 금액과 이름을 함께 넣는 이유: 목록에서 옆 행을 누른 실수를 여기서 잡을 수 있는 마지막 자리다.
func confirmReceivedDialogMessage(detail: FareSplitDetail, transfer: FareSplitTransfer) -> String {
    let head = "\(transfer.displayName)님이 보낸 \(fareWonLabel(amount: transfer.amount))을 받았다고 확인할까요? 확인은 되돌릴 수 없어요"

    if isLastOutstandingTransfer(detail: detail, transfer: transfer) {
        return "\(head)\n\n마지막 한 건이에요. 확인하면 정산이 끝나고 계좌번호가 지워져요"
    }
    return head
}

/// 「아직 안 들어왔어요」 확인 다이얼로그 본문.
///
/// **「취소」라고 적지 않는다** — 되돌리는 것은 보내는 사람의 「보냈어요」 표시 하나이고, 정산 자체를
/// 취소하는 길은 서버에 없다(Swagger 원문: 「정산 취소는 없다」). 「취소」로 적으면 방장이 잘못 만든
/// 정산을 지우는 버튼으로 읽는다.
func markNotReceivedDialogMessage(transfer: FareSplitTransfer) -> String {
    "\(transfer.displayName)님의 「보냈어요」 표시를 되돌릴까요? 아직 안 보낸 상태로 돌아가요"
}

/// **지금 고칠 수 없는 이유** — 고칠 수 있으면 nil 이다.
///
/// 버튼을 숨기고 끝내지 않는 이유: 방장은 금액을 잘못 넣었다는 것을 알고 이 화면에 왔는데, 고치는
/// 길이 아무 말 없이 사라져 있으면 **정산을 취소하려고 한다**(그 길은 없다). 그래서 왜 못 고치는지와
/// 대신 할 수 있는 일을 그 자리에 적는다.
///
/// 받는 사람이 아닐 때 nil 인 것은 「고칠 수 있다」가 아니라 **설명할 자리가 없다**는 뜻이다 —
/// 보내는 사람 화면에는 수정 영역이 통째로 없다.
func editBlockReason(detail: FareSplitDetail) -> String? {
    if detail.canEdit { return nil }
    if !detail.isPayer { return nil }
    if !detail.isOpen { return "닫힌 정산은 고칠 수 없어요" }
    return "누군가 「보냈어요」를 눌러 더 이상 고칠 수 없어요. 정산을 취소하는 길은 없으니, "
        + "금액이 잘못됐다면 채팅으로 이야기한 뒤 「받았어요」로 정리해 주세요"
}

// ─────────────────────────── 보내는 사람(SENDER) ───────────────────────────

/// 보내는 사람 화면이 지금 **어느 단계**인가.
///
/// 불리언 여럿으로 흩지 않는 이유는 `MeetingStage` 와 같다: 「열려 있고 · 계좌가 있고 · 내 송금이 아직
/// NOT_SENT 다」 같은 조합을 화면이 매번 다시 세우면 **조합 하나를 빠뜨려도 컴파일이 통과한다.** enum 하나로
/// 모으면 `switch` 가 빠진 가지를 잡아 준다.
///
/// 판정의 입력은 서버가 직접 준 `FareSplitDetail.myTransferStatus` 다 — 예전에는 세션 uuid 로
/// `transfers` 에서 내 행을 찾아야 했고(Backend PR #328 이전), 서버가 나를 설명하지 못한 응답에서는
/// 「내가 보냈는지」를 **알 길이 없었다.**
enum SenderStage: CaseIterable, Equatable, Sendable {
    /// 보낼 수 있다 — 토스 버튼(딥링크가 있을 때)·복사 버튼·「보냈어요」가 모두 이 단계의 것이다.
    case sendReady

    /// 내가 「보냈어요」를 눌렀다. 받는 사람의 확인을 기다린다 — **누를 것이 없다.**
    ///
    /// 버튼을 남겨 두지 않는 이유(서버는 다시 눌러도 204 다): 눌러도 화면이 그대로라 사용자가
    /// 「안 눌렸나」 싶어 또 누르고, **같은 화면이 반복된다.** 보낸 뒤에는 버튼이 아니라 상태를 보여 준다.
    case sentWaiting

    /// 받는 사람이 확인했다. 더 할 일이 없다.
    case confirmed

    /// 진행 중인데 **보낼 계좌가 없다** — 받는 사람이 탈퇴해 서버가 계좌번호를 지웠다
    /// (`FareSplitDetail.hasLostAccount`).
    ///
    /// 「불러오기 실패」가 아니다. 다시 받아도 계좌는 돌아오지 않으므로 **재시도를 권하지 않는다.**
    /// 그래도 「보냈어요」는 남는다 — 채팅으로 계좌를 받아 앱 밖에서 이미 보낼 수 있고, 서버도
    /// 계좌와 무관하게 받아 준다(`FareSplitDetail.canMarkSent` 가 이 단계에서 true 다).
    case accountLost

    /// 정산이 닫혔다(COMPLETED·EXPIRED). 상태 문구가 그 차이를 말한다(`fareSplitStatusNotice`).
    case closed

    /// **서버가 내 송금 상태를 말해 주지 않았다** — `FareSplitDetail.myTransferStatus` 가 nil 이다.
    ///
    /// 보내는 사람에게 이 값이 nil 로 오는 경우는 둘이다: ① 서버가 상태를 늘려 앱이 모르는 문자열을
    /// 보냈다 ② 옛 배포가 그 필드를 싣지 않고 세션 uuid 폴백도 내 행을 찾지 못했다(매퍼가 둘 다 nil 로
    /// 떨어뜨린다 — `toTransferStatusOrNull`).
    ///
    /// `sendReady` 로 떨어뜨리지 **않는** 것이 핵심이다. 모르는 상태에 버튼을 열어 두면 이미 보낸
    /// 사람이 또 보내거나, 반대로 확인된 송금에 「보냈어요」가 떠 **같은 화면이 반복된다.**
    case unknownMyTransfer
}

/// 보내는 사람 단계 판정. **받는 사람 상세로 부르지 않는다** — 호출부가 `FareSplitDetail.isPayer` 로
/// 먼저 갈린다(받는 사람의 `myTransferStatus` 는 서버가 **일부러** 비우므로 여기서는
/// `SenderStage.unknownMyTransfer` 로 보인다).
///
/// | 조건 | 결과 |
/// |---|---|
/// | 닫혔다 | `closed` |
/// | `myTransferStatus` 가 CONFIRMED | `confirmed` |
/// | SENT | `sentWaiting` |
/// | NOT_SENT · 계좌가 사라졌다 | `accountLost` |
/// | NOT_SENT | `sendReady` |
/// | nil | `unknownMyTransfer` |
///
/// ### 계좌 소실을 **상태보다 나중에** 보는 이유 ★
/// 받는 사람이 탈퇴하면 서버는 계좌번호만 지우고 **상태는 OPEN 그대로** 둔다. 그때 이미 보냈거나
/// 확인된 내 송금은 **아무 영향을 받지 않는다** — 돈은 이미 건너갔다. 계좌 소실을 먼저 보면 그런
/// 사람에게 「계좌를 물어봐 주세요」를 띄우게 되고, 그건 이미 끝난 일을 다시 하라는 말이다.
func senderStageOf(detail: FareSplitDetail) -> SenderStage {
    if !detail.isOpen { return .closed }

    switch detail.myTransferStatus {
    case .confirmed: return .confirmed
    case .sent: return .sentWaiting
    case .notSent: return detail.hasLostAccount ? .accountLost : .sendReady
    case nil: return .unknownMyTransfer
    }
}

/// 단계마다의 안내 한 줄. `sendReady` 는 nil 이다 — 그 단계에서 할 말은 버튼이 한다.
///
/// `closed` 가 nil 인 것도 같은 이유다: 닫힌 정산의 설명은 상태 문구(`fareSplitStatusNotice`)가
/// **COMPLETED 와 EXPIRED 를 갈라서** 하고, 여기서 또 적으면 두 줄이 같은 말을 하거나 서로 다른 말을 한다.
func senderStageNotice(stage: SenderStage) -> String? {
    switch stage {
    case .sendReady: nil
    case .sentWaiting: "보냈다고 알렸어요. 받는 분이 확인하면 정산이 끝나요"
    case .confirmed: "받는 분이 받았다고 확인했어요. 더 보낼 돈이 없어요"
    case .accountLost: "받는 분의 계좌를 더 이상 확인할 수 없어요. 다시 불러와도 나오지 않으니 채팅으로 계좌를 물어봐 주세요"
    case .closed: nil
    case .unknownMyTransfer: "내 송금 상태를 확인하지 못했어요. 다시 불러와 주세요"
    }
}

/// 안내 줄의 톤. 기다리는 쪽은 중립, 끝난 쪽은 `FareSplitTone.done`, 막힌 쪽은 `FareSplitTone.danger` 다.
func senderStageTone(stage: SenderStage) -> FareSplitTone {
    switch stage {
    case .sendReady, .sentWaiting, .closed: .info
    case .confirmed: .done
    case .accountLost, .unknownMyTransfer: .danger
    }
}

/// 「보냈어요」 버튼을 그리는가 — **`FareSplitDetail.canMarkSent` 하나가 조건이다.**
///
/// ### 세 조건을 화면이 따로 세우지 않는다 ★
/// 「진행 중 · 내가 보내는 사람 · 아직 안 보냄」을 화면이 다시 조립하면 **받는 사람의
/// `myTransferStatus == nil` 을 「아직 안 보냈다」로 읽는 실수**가 끼어든다. 그 버튼은 방장 화면에
/// 떠서 403 `NOT_FARE_SPLIT_SENDER` 로만 끝난다. 그래서 판정은 도메인 한 곳에 있다.
///
/// `SenderStage` 로 묻지 않는 것도 같은 이유다 — 단계는 **문구를 고르는** 축이고, 버튼의 권한은
/// 서버가 보는 조건이다. 두 축이 어긋날 수 있는 자리를 만들지 않는다. 결과적으로 이 값은
/// `sendReady` 와 `accountLost` 에서 true 다(계좌가 없어도 보냈다고 알릴 수 있는 근거는 그 단계 주석에 있다).
func showsMarkSentButton(detail: FareSplitDetail) -> Bool {
    detail.canMarkSent
}

/// **토스 버튼을 그리는가** — 보낼 수 있고 서버가 딥링크를 줬을 때만.
///
/// ### 딥링크를 앱이 조립하지 않는다 ★
/// 규격이 서버 쪽에 있고(`TossDeeplink`) 은행 이름도 토스 전용 표기(`tossName`: 「KB국민」)라
/// `Bank.displayName` 과 다르다 — 앱이 베끼면 두 표기가 갈려 **엉뚱한 은행으로 송금 화면이 열린다.**
/// 그래서 nil 이면 **만들어 끼우지 않고 버튼을 띄우지 않는다.** 그때도 사용자는 복사 버튼으로 손으로
/// 옮길 수 있다(`ManualTransfer`).
///
/// 서버는 SENDER + OPEN 에만 딥링크를 싣지만 그 사실에 의존하지 않는다 — `FareSplitDetail.canMarkSent`
/// 를 함께 보므로 이미 보낸 사람에게 송금 버튼이 남지 않는다.
///
/// (iOS) **`supertoss` 스킴이 아니면 그리지 않는다**(`tossDeeplinkURL`). 서버가 준 문자열을 그대로 여는
/// 자리라, 스킴을 보지 않으면 `https`·`tel` 같은 다른 링크가 「토스로 보내기」 버튼 뒤에 숨는다.
func showsTossButton(detail: FareSplitDetail) -> Bool {
    guard detail.canMarkSent, let deeplink = detail.tossDeeplink else { return false }
    return tossDeeplinkURL(deeplink) != nil
}

/// **앱 안에 남은 길이 없어 채팅으로 보내야 하는가.**
///
/// 두 경우뿐이다: 보낼 계좌가 사라졌거나(`FareSplitDetail.hasLostAccount`) 기간이 지나 닫혔다.
/// 멀쩡한 정산에 「채팅으로 물어보기」를 두면 **할 일이 흐려진다** — 그 화면에서 해야 할 일은
/// 보내거나 확인하는 것이고, 채팅은 그 둘이 불가능해졌을 때의 마지막 수단이다.
func showsChatFallback(detail: FareSplitDetail) -> Bool {
    detail.hasLostAccount || detail.status == .expired
}

/// 「보냈어요」 확인 다이얼로그 본문 — **이 동작은 보내는 사람이 되돌릴 수 없다.**
///
/// 멱등이고 되돌리기도 있는 동작에 왜 확인을 두는가: 되돌릴 수 있는 사람이 **받는 사람뿐**이다
/// (`markNotReceived` 는 PAYER 전용이다). 잘못 누른 사람은 받는 사람에게 부탁하는 수밖에 없고,
/// 그 사이 받는 사람은 입금되지 않은 돈을 확인하라는 알림을 받는다.
///
/// 금액을 적는 이유는 `confirmReceivedDialogMessage` 와 같다 — 숫자를 한 번 더 보여 주는 것이
/// 오탭을 잡는 마지막 자리다.
func markSentDialogMessage(detail: FareSplitDetail) -> String {
    "토스·은행 앱에서 \(fareWonLabel(amount: detail.myAmount))을 보냈나요? 보냈다고 알리면 받는 분이 입금을 확인해요. "
        + "되돌리는 것은 받는 분만 할 수 있어요"
}

/// 토스가 **열리지 않았을 때** 띄우는 안내.
///
/// 서버 주석 원문이 이 문구의 근거다: 「비공식 규격이라 열리지 않을 수 있어 계좌·금액 복사 버튼을
/// 함께 둔다」. 그래서 실패를 「오류」로 말하지 않고 **바로 아래에 이미 있는 길**을 가리킨다 —
/// 복사 버튼은 선택이 아니라 이 실패의 짝이다.
let TOSS_OPEN_FAILED_NOTICE = "토스를 열지 못했어요. 아래 계좌번호와 금액을 복사해 은행 앱에서 보내 주세요"

// 진입 판정(`canOpenFareSplit`·`fareSplitEntryLabel`)은 `PresentationCore` 에 있다 — 22 탑승 상세
// (FeatureMatching)도 같은 판정을 쓰는데 기능 모듈끼리는 서로 import 하지 않는다.

// ─────────────────────────── 실패 문구 ───────────────────────────

/// 어떤 요청이 실패했는가 — 같은 서버 코드라도 **사용자가 할 일이 다르다**.
enum FareSplitAction: CaseIterable, Equatable, Sendable {
    case load
    case start
    case edit
    case markSent
    case confirmReceived
    case markNotReceived
    case myList
}

/// 사유를 가릴 수 없을 때의 문구 — 네트워크 실패와 **모르는 코드**가 여기로 떨어진다.
func fareSplitGenericFailure(action: FareSplitAction) -> String {
    switch action {
    case .load: "택시비 정산을 불러오지 못했어요"
    case .start: "정산을 시작하지 못했어요"
    case .edit: "정산을 고치지 못했어요"
    case .markSent: "보냈다고 알리지 못했어요"
    case .confirmReceived: "받았다고 확인하지 못했어요"
    case .markNotReceived: "「보냈어요」 표시를 되돌리지 못했어요"
    case .myList: "보낼 택시비를 불러오지 못했어요"
    }
}

/// 서버 실패 → 사용자 문구.
///
/// ### 상태 코드로는 아무것도 갈리지 않는다 ★
/// 18종이 네 상태에 몰려 있어 **한 상태 안에 할 일이 정반대인 것들**이 섞인다
/// (`FareSplitException` 주석의 표). 특히 정산을 시작할 수 없는 세 실패:
///
/// | 코드 | 사용자가 할 수 있는 일 |
/// |---|---|
/// | `PARTY_NOT_FINISHED`(409) | **있다** — 「출발」을 누른 뒤 다시 시작한다 |
/// | `NOT_A_RIDER`(403) | **없다.** 도착은 끝난 방에서 되돌릴 수 없다 |
/// | `NOT_ENOUGH_RIDERS`(409) | **없다.** 혼자 탔으면 나눌 상대가 없다 |
///
/// 뭉치면 사용자가 **기다려야 할 때 다시 누르고, 다시 누르면 될 때 포기한다.**
///
/// ### 서버 message 를 그대로 쓰지 않는다 ★
/// 400 `INVALID_REQUEST` 의 message 는 Bean Validation 원문이라 「totalFare: 택시비는 1원
/// 이상이어야 합니다」처럼 **필드명을 그대로 담는다**. 그대로 띄우면 사용자가 모르는 영어 이름이
/// 화면에 나오고, 어느 칸을 고쳐야 하는지도 알 수 없다(`ChatException.isInvalidRequest` 와 같은 관례).
///
/// 「다시 시도」류를 한 줄도 적지 않는 가지들이 있다 — 다시 눌러도 같은 답인 실패들이다.
func fareSplitFailureMessage(failure e: FareSplitException, action: FareSplitAction) -> String {
    // 응답조차 받지 못했다 — 유일하게 「다시」가 뜻이 있는 실패다.
    if e.isNetwork { return "네트워크 연결을 확인하고 다시 시도해 주세요" }
    if e.isUnauthorized { return "로그인이 만료됐어요. 다시 로그인해 주세요" }

    // ── 정산을 시작할 수 없는 셋 — 처방이 서로 다르다 ──
    if e.isPartyNotFinished { return "아직 출발하지 않은 방이에요. 「출발」을 누른 뒤 정산을 시작할 수 있어요" }
    if e.isNotARider { return "출발지 도착을 누르지 않아 이 방의 탑승자가 아니에요. 이 방은 정산할 수 없어요" }
    if e.isNotEnoughRiders { return "함께 탄 사람이 없어 나눌 수 없어요. 이 방은 정산할 수 없어요" }
    if e.isNotPartyHost { return "방장만 정산을 시작할 수 있어요" }

    // ── 입력 — 어느 칸을 고쳐야 하는지 가리킨다 ──
    if e.isInvalidAccountNumber { return "계좌번호를 다시 확인해 주세요. 숫자 10~16자리여야 해요" }
    if e.isPaymentsNotEqualFare { return "부담 금액의 합이 택시비와 달라요. 금액을 다시 맞춰 주세요" }
    // 금액을 아무리 고쳐도 풀리지 않는다 — 정산 대상 자체가 어긋났다.
    if e.isPaymentTargetMismatch { return "정산 대상이 서버와 달라요. 탑승 정보를 다시 불러와 주세요" }
    if e.isInvalidPayment { return "부담 금액은 한 사람당 1원 이상이어야 해요" }
    // ★ 서버 message 를 쓰지 않는다 — 필드명이 그대로 담겨 온다.
    if e.isInvalidRequest { return "입력한 값을 다시 확인해 주세요" }

    // ── 상태·역할 — 들고 있는 상세가 낡았다는 신호다(`needsReloadAfter`) ──
    if e.isAlreadyStarted { return "누군가 「보냈어요」를 눌러 더 이상 고칠 수 없어요" }
    if e.isClosed { return "이미 닫힌 정산이에요" }
    if e.isTransferNotSent { return "「보냈어요」 상태인 송금만 되돌릴 수 있어요" }
    if e.isNotPayer { return "받는 분만 할 수 있는 일이에요" }
    if e.isNotSender { return "보내는 분만 할 수 있는 일이에요" }
    if e.isNotParticipant { return "이 택시비 정산의 당사자가 아니에요" }
    if e.isTransferNotFound { return "정산 정보가 달라졌어요. 다시 불러온 내용을 확인해 주세요" }
    if e.isFareSplitNotFound { return "이 방에는 택시비 정산이 없어요" }
    if e.isPartyNotFound { return "이미 사라진 방이에요" }

    return fareSplitGenericFailure(action: action)
}

/// 이 실패 뒤에 **상세를 다시 받아야 하는가.**
///
/// 문구만 띄우고 끝내면 안 되는 실패들이 있다 — 전부 「내가 들고 있는 상세가 서버와 어긋났다」는
/// 뜻이기 때문이다. 어긋난 화면 위에 다음 동작을 하게 두면 같은 실패가 되풀이되거나(낡은 publicId)
/// 이미 지워진 계좌번호를 유효한 것처럼 보여 준다(닫힌 정산).
///
/// `FareSplitException.isAlreadyStarted` 는 재조회하되 **입력값을 버리지 않는다** — 사용자가 금액을
/// 다 채운 뒤에 오는 실패라, 화면을 닫으면 그 입력이 사라진다(`FareSplitEditRoute`).
func needsReloadAfter(failure e: FareSplitException) -> Bool {
    e.isAlreadyStarted || e.isClosed || e.isNotPayer || e.isNotSender
        || e.isTransferNotFound || e.isTransferNotSent || e.isPaymentTargetMismatch
}
