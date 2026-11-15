import Combine
import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI
import UIKit

/// 말풍선 모서리 — 디자인 문서 chat-bubble 의 rounded.lg(20). 꼬리 쪽 한 모서리만 `BubbleTailRadius` 로
/// 좁혀 누가 한 말인지 방향을 남긴다.
private let BubbleRadius: CGFloat = 20
private let BubbleTailRadius: CGFloat = 6

/// 「바닥에 붙어 있다」고 보는 거리. 이 안에 있으면 새 메시지가 올 때 따라 내려가고, 그보다 위로
/// 올려 읽는 중이면 자동 스크롤을 하지 않는다.
///
/// 120pt 로 둔 근거: 말풍선 한 칸이 대략 44pt + 간격 16pt(= 60pt)라 **두 줄쯤**이다. 1pt 로 바닥을
/// 엄격히 요구하면 애니메이션이 1px 못 미친 순간이나 손가락이 살짝 스친 뒤에 따라가기가 끊긴다.
/// 반대로 더 넓게 잡으면 「마지막 몇 개를 다시 읽는 중」인 사람까지 끌어내린다.
private let AUTO_SCROLL_SLOP: CGFloat = 120

/// 입력창이 **받아 주는** 최대 글자 수 — 서버 한도(`MAX_CONTENT_LENGTH`, 1000자)보다 넉넉하다.
///
/// **한도와 역할이 다르다.** 여기서 한도대로 자르면 한도를 넘겨 볼 수가 없어 「넘었다」는 사실을
/// 말해 줄 기회 자체가 사라진다. 예전엔 그보다 더해서 **500자**에서 잘랐고(서버 한도의 절반),
/// 그 바람에 ViewModel 의 1000자 검사와 안내가 둘 다 도달 불가능한 죽은 코드였다 — 사용자는
/// 500자에서 **이유도 모르고 조용히** 막혔다.
///
/// 그래서 한도를 말하는 일은 `chatInputUi` 의 카운터가 맡고(입력하는 동안 계속 보인다), 이 값은
/// **붙여넣기 폭주만** 막는다 — 한 줄 입력창이 소설 한 편을 들고 있을 이유는 없다. 한도의 2배로
/// 둔 것도 그 때문이다: 넘긴 상태를 **보여 줄 수 있을 만큼** 넉넉하고, 수십만 자 붙여넣기는 막는다.
private let INPUT_HARD_LIMIT = 2_000

/// 글자 수 카운터가 **보이기 시작하는** 길이 — 한도(`MAX_CONTENT_LENGTH`)에서 이만큼 남은 지점.
///
/// 왜 「항상」이 아닌가: 평상시 채팅 한 줄은 수십 자다. 「12/1000자」가 늘 떠 있으면 이 화면에서
/// 가장 중요한 영역(말풍선)의 높이를 **상시로** 빼앗고, 아무 의미 없는 숫자가 글자마다 바뀌며
/// 눈에 들어온다. 이 코드베이스가 「후보 0건이면 섹션을 그리지 않는다」·「추정 실패면 칩을 감춘다」로
/// 일관되게 택한 쪽과 같은 판단이다.
///
/// 왜 「넘은 순간」도 아닌가: 1001자에서야 나타나면 **버튼이 잠기는 순간과 줄이 생기는 순간이
/// 같아진다.** 그러면 ① 경고가 아니라 사후 통보가 되고 ② 입력 바가 그 프레임에 한 줄만큼
/// 높아져서 **누르려던 전송 버튼이 위로 움직이며** 잠긴다. 한도보다 앞서 띄우면, 잠기는 순간에
/// 카운터는 **이미 화면에 있고** 색만 바뀐다 — 레이아웃은 그 순간 움직이지 않는다.
///
/// 100자인 근거: 한 줄 입력창에 더 칠 수 있는 분량(두세 문장)이라 「곧 한도」를 알아차리고 줄일
/// 시간이 되고, 900자까지 치는 메시지는 사실상 붙여넣기이므로 평상시 시야에는 영영 안 나타난다.
/// (0자에서 2000자를 **한 번에** 붙여넣으면 등장과 잠김이 같은 프레임이다 — 그 경우만은 피할 수
/// 없고, 그때도 빨간 「2000/1000자」가 왜 잠겼는지를 말한다.)
///
/// `internal` 인 이유는 하나뿐이다 — `ChatInputLimitTest` 가 **「카운터는 잠김보다 먼저 뜬다」**
/// (`COUNTER_VISIBLE_FROM < MAX_CONTENT_LENGTH`)를 이 상수로 못 박는다. 그 부등식이 깨지면 위의
/// ②(버튼이 움직이며 잠긴다)가 그대로 돌아온다. 화면 밖에서 쓰는 값은 아니다.
let COUNTER_VISIBLE_FROM = MAX_CONTENT_LENGTH - 100

/// 입력창 한 상태에서 **파생되는 것 전부** — 카운터 문구와 전송 가능 여부.
///
/// 둘을 **한 함수에서 함께** 뽑는 것이 요점이다: 길이를 두 번 재면 세는 기준이 갈리고, 그러면
/// 「999자인데 버튼이 잠김」·「넘었는데 버튼이 살아 있음」 같은 어긋남이 생긴다(실제로 과거에
/// 입력창 500자 컷과 ViewModel 1000자 검사가 갈려 안내가 죽은 코드였다).
///
/// - `counter`: 카운터 문구. **nil 이면 줄을 그리지 않는다**(`COUNTER_VISIBLE_FROM`)
/// - `overLimit`: 한도를 넘겼다 — 카운터를 강조하고 전송을 잠근 **그 이유**다
/// - `sendEnabled`: 전송 버튼 활성
struct ChatInputUi: Equatable, Sendable {
    let counter: String?
    let overLimit: Bool
    let sendEnabled: Bool
}

/// 입력창 상태 → `ChatInputUi`. **길이는 `trim()` 뒤에 센다.** 길이 단위는 원본·서버와 같은 UTF-16 칸이다.
///
/// 그게 `ChatRoomViewModel.send` 가 보는 기준이기 때문이다 — 그쪽은 `text.trim()` 한 값으로
/// 빈 문자열과 한도를 판정하고 그 값을 서버로 보낸다. 화면이 trim 전 길이를 세면 공백을 섞어 둔
/// 사용자에게 **「999자인데 버튼이 잠김」**(화면은 1002, 서버로 갈 값은 999)이 보인다.
///
/// 전송 잠금은 **카운터가 보이는 것에 대한 대가**로만 둔다: 버튼만 잠그면 예전 500자 컷 시절의
/// 「조용히 막힘」으로 반쯤 되돌아간다 — 누르지 않아도 이유가 보여야 한다. 그래서 잠금 조건
/// (`overLimit`)과 표시 조건이 같은 값에서 나오고, 넘긴 상태에서는 카운터가 **반드시** 보인다
/// (`COUNTER_VISIBLE_FROM` < `MAX_CONTENT_LENGTH` 이므로 자동으로 성립한다).
///
/// 넘겼을 때 숫자만 빨갛게 바꾸지 않고 「줄여야 보낼 수 있어요」를 붙이는 이유: 회색 전송 버튼과
/// 빨간 숫자 사이의 인과를 사용자가 **추측하지 않아도** 되게 한다. 색만으로 말하면 색을 구분하기
/// 어려운 사용자에게는 아무 말도 하지 않은 것과 같다.
///
/// `ChatRoomViewModel.send` 의 한도 검사는 **지우지 않는다** — 화면이 잠그더라도 ViewModel 은
/// 자기 입력을 자기가 검증해야 한다(서버도 같은 한도로 거절한다).
func chatInputUi(input: String, sending: Bool) -> ChatInputUi {
    let length = input.trim().utf16.count
    let overLimit = length > MAX_CONTENT_LENGTH
    let counter: String?
    if length < COUNTER_VISIBLE_FROM {
        counter = nil
    } else if overLimit {
        counter = "\(length)/\(MAX_CONTENT_LENGTH)자 — 줄여야 보낼 수 있어요"
    } else {
        counter = "\(length)/\(MAX_CONTENT_LENGTH)자"
    }
    return ChatInputUi(
        counter: counter,
        overLimit: overLimit,
        // 공백만 입력했을 때의 비활성은 그대로다 — trim 뒤 0자면 보낼 내용이 없다.
        sendEnabled: (1...MAX_CONTENT_LENGTH).contains(length) && !sending
    )
}

/// 채팅 메시지 표시 모델. 서버 도메인 모델(`ChatMessage`)은 Route 에서 이 형태로 옮긴다.
///
/// - `id`: 서버 메시지 id. 신고(`chatMessageId`)가 **이 값을 쓴다**. 아직 서버에서 되돌아오지
///   않은 내 말풍선(`PendingMessage`)은 `NO_SERVER_MESSAGE_ID` 라 신고 대상이
///   되지 않는다(`canReport`).
/// - `senderImageUrl`: 상대 말풍선 아바타에 그릴 사진. 메시지 응답에는 없고 참여자 조회로 세운
///   사전에서 온다(`chatMemberImageUrls`). 내 메시지는 아바타 자리가 없어 항상 nil 이고,
///   없으면 아바타가 회색 원으로 떨어진다.
public struct ChatUiMessage: Equatable, Sendable {
    public var text: String
    public var isMine: Bool
    public var senderName: String?
    public var timeLabel: String?
    public var meta: String? // 내 메시지 좌측 메타 (예: "읽음 2 · 6:41")
    public var senderImageUrl: String?
    public var id: Int64

    public init(
        text: String,
        isMine: Bool,
        senderName: String? = nil,
        timeLabel: String? = nil,
        meta: String? = nil,
        senderImageUrl: String? = nil,
        id: Int64 = NO_SERVER_MESSAGE_ID
    ) {
        self.text = text
        self.isMine = isMine
        self.senderName = senderName
        self.timeLabel = timeLabel
        self.meta = meta
        self.senderImageUrl = senderImageUrl
        self.id = id
    }
}

/// 「서버 id 를 아직(또는 끝내) 모른다」는 뜻의 `ChatUiMessage.id`.
///
/// 0 인 근거: 서버가 `chatMessageId` 를 `@Positive` 로 받아 0 을 **400 으로 거절한다**
/// (`ChatReportReason.MIN_MESSAGE_ID`). 즉 「신고에 쓸 수 없는 값」을 서버와 같은 기준으로 고른
/// 것이고, 음수 임시 id 를 쓰는 것보다 판정이 하나뿐이어서 어긋날 데가 없다.
public let NO_SERVER_MESSAGE_ID: Int64 = 0

extension ChatUiMessage {
    /// 이 말풍선에 **신고 길을 만들어도 되는가.**
    ///
    /// 두 조건 다 서버가 400 으로 거절하는 것을 미리 접는 것이다:
    /// - `!isMine` — 내 메시지를 신고하면 400 `CHAT_CANNOT_REPORT_SELF` 다. 애초에 길을 만들지 않는다.
    ///   길을 만들어 두면 사용자가 자기 말을 꾹 눌러 사유까지 고른 끝에 거절당한다.
    /// - `id >= MIN_MESSAGE_ID` — 서버 id 가 없는 말풍선(전송 확인 대기 중인 내 메시지)은
    ///   보낼 `chatMessageId` 가 없다. 0 을 보내면 400 `INVALID_REQUEST` 다.
    ///
    /// 둘째 조건은 첫째에 거의 포함되지만(id 가 없는 건 지금은 내 메시지뿐이다) **따로 본다** —
    /// 나중에 남의 말풍선을 서버 확인 전에 그리는 길이 생기면 첫째 조건만으로는 0 이 새어 나간다.
    func canReport() -> Bool {
        !isMine && id >= ChatReportReason.MIN_MESSAGE_ID
    }
}

/// 검색 바·결과 목록 상태. `results` 가 nil 이면 아직 묻지 않았다(검색어가 짧다) — 빈 목록(결과 없음)과 구분한다.
/// 기본값은 「닫힘」이다.
public struct ChatSearchUi: Equatable, Sendable {
    public var open: Bool
    public var query: String
    public var results: [ChatUiMessage]?
    public var loading: Bool
    public var loadingMore: Bool
    public var hasMore: Bool
    public var errorMessage: String?

    public init(
        open: Bool = false,
        query: String = "",
        results: [ChatUiMessage]? = nil,
        loading: Bool = false,
        loadingMore: Bool = false,
        hasMore: Bool = false,
        errorMessage: String? = nil
    ) {
        self.open = open
        self.query = query
        self.results = results
        self.loading = loading
        self.loadingMore = loadingMore
        self.hasMore = hasMore
        self.errorMessage = errorMessage
    }
}

/// 사유 시트에 그릴 줄 — **서버 enum 하나당 한 줄**이고 순서가 그대로 화면 순서다.
///
/// 문구를 enum 쪽(`ChatReportReason`)에 두지 않은 이유: 서버 enum 의 주석은 「욕설, 비방, 혐오
/// 표현」처럼 분류 설명이고, 사용자가 고르는 줄은 「괴롭힘이나 욕설이에요」처럼 자기 경험을
/// 고르는 말이다. 같은 자리에 두면 둘 중 하나가 다른 쪽에 끌려간다.
///
/// `internal` 인 이유는 하나뿐이다 — `MessageReportGuardTest` 가 **enum 값을 하나도 빠뜨리지
/// 않는지**를 이 목록으로 못 박는다. 서버가 사유를 늘렸을 때 고를 수 없는 사유가 생기면
/// 「그 밖의 이유예요」로 뭉개지는데, 그건 운영이 분류로 조치하는 설계를 무력화한다.
let chatReportReasonLabels: [(ChatReportReason, String)] = [
    (.abuse, "괴롭힘이나 욕설이에요"),
    (.spam, "광고나 도배예요"),
    (.fraud, "사기나 금전 요구예요"),
    (.sexual, "성적으로 불쾌해요"),
    (.etc, "그 밖의 이유예요"),
]

/// 신고 전송의 **결과 한 줄** — 시트를 닫을지와 배너 색을 함께 정한다.
///
/// - `accepted`: 서버가 접수했는가(201). 배너 색이 성공/실패로 갈린다.
/// - `retryable`: **같은 내용으로 다시 보내서 달라질 수 있는** 실패인가. 참이면 시트를
///   **열어 둔다** — 적어 둔 상세 수백 자를 연결이 한 번 끊긴 것 때문에 버리게 하지 않는다.
///   거짓이면(접수됨·이미 신고함·참여자 아님·메시지 없음) 닫는다. 「이미 신고한 메시지」를
///   재시도로 열어 두면 **사유를 바꿔도 영원히 같은 409** 라 사용자를 가둔다(실측).
public struct ChatReportOutcome: Equatable, Sendable {
    public var message: String
    public var accepted: Bool
    public var retryable: Bool

    public init(message: String, accepted: Bool, retryable: Bool = false) {
        self.message = message
        self.accepted = accepted
        self.retryable = retryable
    }
}

/// 상세 내용 입력창이 **받아 주는** 최대 글자 수 — 서버 한도의 2배.
///
/// 입력창 쪽과 같은 판단이다(`INPUT_HARD_LIMIT`): 한도대로 자르면 「넘었다」를 말해 줄 기회가
/// 사라지므로 한도는 카운터가 말하게 두고, 이 값은 붙여넣기 폭주만 막는다.
private let REPORT_DESCRIPTION_HARD_LIMIT = ChatReportReason.MAX_DESCRIPTION_LENGTH * 2

/// 상세 내용 카운터가 **보이기 시작하는** 길이. 한도보다 100자 앞서 나타난다 —
/// 「신고하기」가 잠기는 순간에 카운터가 **이미 화면에 있고 색만 바뀌게** 하기 위해서다
/// (`COUNTER_VISIBLE_FROM` 과 같은 근거).
let REPORT_COUNTER_VISIBLE_FROM = ChatReportReason.MAX_DESCRIPTION_LENGTH - 100

/// 사유 시트 한 상태에서 **파생되는 것 전부** — 카운터 문구와 전송 가능 여부.
/// `ChatInputUi` 와 같은 이유로 한 함수에서 함께 뽑는다(길이를 두 번 재면 기준이 갈린다).
struct ChatReportSubmitUi: Equatable, Sendable {
    let counter: String?
    let overLimit: Bool
    let submitEnabled: Bool
}

/// 「신고하기」를 **누를 수 있는가**와 그 이유를 함께 뽑는다.
///
/// 세 가지를 서버에 묻지 않고 여기서 접는다 — 전부 **누르기 전부터 알 수 있는** 거절이다:
/// - 사유를 안 골랐다 → 서버는 400 `INVALID_REQUEST`(「신고 사유는 필수입니다」)
/// - 「기타」인데 상세가 비었다(공백만 있어도 같다) → 400 `CHAT_REPORT_DESCRIPTION_REQUIRED`
/// - 상세가 `ChatReportReason.MAX_DESCRIPTION_LENGTH`자를 넘었다 → 400 `INVALID_REQUEST`
///
/// 잠그되 **이유를 먼저 보여 준다**: 사유를 고르기 전에는 카운터가 없고, 「기타」를 고르면
/// 입력창과 안내가 함께 나타나며, 한도에 가까워지면 카운터가 먼저 뜬다
/// (`REPORT_COUNTER_VISIBLE_FROM`). 이 화면의 입력창이 세운 규칙(`chatInputUi`)과 같다.
func chatReportSubmitUi(
    reason: ChatReportReason?,
    description: String,
    submitting: Bool = false
) -> ChatReportSubmitUi {
    let length = description.trim().utf16.count
    let max = ChatReportReason.MAX_DESCRIPTION_LENGTH
    let overLimit = length > max
    let needsDescription = reason?.requiresDescription == true
    // 상세가 필요 없고 아무것도 안 썼으면 줄을 그리지 않는다 — 의미 없는 「0/500자」가
    // 시트 높이를 상시로 빼앗는다.
    let counter: String?
    if overLimit {
        counter = "\(length)/\(max)자 — 줄여야 보낼 수 있어요"
    } else if length >= REPORT_COUNTER_VISIBLE_FROM {
        counter = "\(length)/\(max)자"
    } else {
        counter = nil
    }
    return ChatReportSubmitUi(
        counter: counter,
        overLimit: overLimit,
        submitEnabled: reason != nil
            && !overLimit
            && !submitting
            && (!needsDescription || length >= 1)
    )
}

/// 24 · 채팅 [S16] — 24a 메뉴 오버레이 포함
///
/// 이동(디스크립션):
/// - 뒤로 → 22 탑승 상세 (onBack)
/// - 「⋮」 → 24a 메뉴 열림 (내부 상태)
/// - 상단 「매칭 화면으로」 배너 탭 → 21 매칭 대기 (onOpenMatching — 진행 중인 방의 채팅방일 때만 보인다)
/// - 24a 「채팅방 알림 끄기/켜기」 → 24 (서버 음소거 토글 — onToggleMute, 부제에 「알림 꺼짐」)
/// - 24a 「채팅방 나가기」 → **항상 재확인 다이얼로그** → 14 홈 (onLeaveChat)
/// - **상대 말풍선 롱프레스** → 신고 액션 시트 → 사유 시트 → 24 (onReportMessage).
///   내 말풍선에는 길이 없다 — 서버가 본인 신고를 400 으로 거절한다(`ChatUiMessage.canReport`).
///   상단바 메뉴(24a)에 둘 수 없는 이유는 서버가 `chatMessageId` 를 필수로 받아 **대상 메시지를
///   반드시 지목해야** 하는데 거기서는 고를 길이 없기 때문이다.
/// - 하단탭 → 14/17/35 (onTabSelect)
/// - 헤더 검색 아이콘 → 상단이 검색 바로 바뀌고 본문이 결과 목록이 된다(onOpenSearch / onCloseSearch).
///   검색어 2자 이상부터 서버(GET …/messages/search)에 묻고, 결과는 최신순 · 「이전 결과 더 보기」로 페이징.
///   결과를 눌러 그 메시지로 점프하는 건 아직 없다 — 서버가 위치(오프셋)를 주지 않아 커서 페이징으로는
///   해당 메시지까지 몇 페이지를 더 받아야 하는지 모른다.
///
/// 유효값: 메시지 1~`MAX_CONTENT_LENGTH`자(서버 `SendMessageRequest @Size(max = 1000)` 와 같은 수),
/// 공백만 입력 시 전송 비활성. 한도를 넘으면 **입력은 막지 않고**(붙여넣기 폭주만 `INPUT_HARD_LIMIT`)
/// 입력창 위 카운터가 넘긴 사실을 말하고 전송 버튼을 잠근다(`chatInputUi`) — 잠금은 **이유가 이미
/// 보이는 것에 대한 대가**다. 예전에 500자로 잘라 버려 안내가 영영 안 보였고, 사용자는 왜 막혔는지
/// 알 수 없었다. ViewModel 의 한도 검사는 그래도 남는다(방어 — `ChatRoomViewModel.send`).
///
/// 방 제목·부제·메시지는 기본값이 없다 — 실제 진입(ChatRoute)은 서버 ChatRoom 의 출발지 → 목적지와
/// 조회한 메시지를 항상 넘긴다.
/// 「매칭 완료 · 시각」 시스템 칩은 없앴다 — 방 생성 시각이 모델에 없어 모든 방에 같은 고정 문구가 보였다.
/// 24b 「실시간 위치 공유」 시트와 「＋」 버튼도 없앴다. **API 가 없어서가 아니다** — 서버에는 REST 3개
/// (`POST`·`DELETE /api/v1/chat-rooms/{id}/location/sharing`, `POST /api/v1/chat-rooms/{id}/location`)
/// 와 STOMP 2개(`/chat-rooms/{id}/location`, 스냅샷 `/chat-rooms/{id}/location/sync`)가 다 있다.
/// 안 붙인 이유는 둘이고 둘 다 코드 밖에 있다. (1) 2026-10-08 에 이 기능을 걷으면서 개인정보
/// 처리방침·매너 서약에서 위치 수집 고지를 함께 줄였다 — 되살리려면 그 문구부터 되돌려야 한다.
/// (2) 서버의 REST 좌표 전송은 백그라운드용이라 스토어 심사(백그라운드 위치 용도 소명)를 요구한다.
/// 포그라운드만이면 권한 없이 가능하다.
public struct ChatScreen: View {
    private let roomTitle: String
    private let roomSubtitle: String
    private let messages: [ChatUiMessage]
    private let input: String
    private let sending: Bool
    private let errorMessage: String?
    private let onInputChange: (String) -> Void
    private let onSend: () -> Void
    private let onBack: () -> Void
    private let onOpenMatching: (() -> Void)?
    private let onLeaveChat: () -> Void
    private let onTabSelect: (MoyeotaTab) -> Void
    private let muted: Bool
    private let onToggleMute: () -> Void
    private let canLeave: Bool
    private let search: ChatSearchUi
    private let onOpenSearch: () -> Void
    private let onCloseSearch: () -> Void
    private let onSearchQueryChange: (String) -> Void
    private let onSearchRetry: () -> Void
    private let onSearchLoadMore: () -> Void
    private let reportSubmitting: Bool
    private let reportOutcome: ChatReportOutcome?
    private let onReportMessage: (Int64, ChatReportReason, String?) -> Void

    @State private var menuOpen = false // 24a
    @State private var leaveConfirmOpen = false

    // ── 메시지 신고 ───────────────────────────────────────────────────────────
    // 시트 상태는 **화면이 들고 있다** — 24a 메뉴·나가기 다이얼로그와 같은 자리다(이 파일의
    // 기존 규칙). ViewModel 로 올려야 하는 것은 전송과 그 결과뿐이라, 고른 사유와 적던 상세가
    // 오갈 필요가 없다. 호출부 시그니처도 콜백 하나로 끝난다.
    /// 꾹 누른 메시지 — nil 이면 액션 시트도 안 열렸다
    @State private var reportTarget: ChatUiMessage?
    /// 액션 시트(「이 메시지 신고하기」)를 지나 사유 시트까지 왔는가
    @State private var reasonPickerOpen = false
    @State private var reportReason: ChatReportReason?
    @State private var reportDescription = ""
    /// **지금 시트에서** 「신고하기」를 눌렀는가. 직전 결과(`reportOutcome`)는 다음 신고까지 남아
    /// 있으므로 이 플래그가 없으면, 실패한 뒤 **다른 메시지**를 꾹 눌렀을 때 앞 실패 문구가 새
    /// 시트 안에 그대로 떠서 방금 누른 것의 답으로 읽힌다.
    @State private var reportSubmitted = false

    @State private var imeVisible = false

    // 메시지 리스트는 **바닥에 붙어 있는 동안만** 마지막 대화로 따라간다(새 메시지·키보드 등장 모두).
    @State private var scrollTracker: ChatScrollTracker
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    /// - Parameters:
    ///   - followsBottomOnOpen: 첫 내용에서 바닥으로 내려가는가. 독립 목적지(21 의 「채팅 열기」)는 false 다 — `ChatScrollTracker` 주석.
    ///   - onOpenMatching: 이 방의 파티가 아직 진행 중일 때 매칭 단계 화면으로 되돌아가는 길. **nil 이면 그리지 않는다** —
    ///     끝난 방의 채팅에서 「매칭 화면으로」를 눌러 봐야 갈 곳이 없다.
    ///     21 에서 「채팅 열기」로 들어온 사용자에게는 뒤로가기가 이미 복귀 경로지만,
    ///     채팅 **탭 목록**에서 들어온 사용자에게는 이 버튼이 유일한 길이다.
    ///   - muted: 이 방의 푸시 알림 음소거 여부(서버 값). 24a 메뉴의 「알림 끄기/켜기」와 부제의 「알림 꺼짐」이 따른다
    ///   - canLeave: 24a 「채팅방 나가기」를 보여 줄지. 진행 중인 내 방의 채팅방이면 false(되돌아올 길이 없다)
    ///   - reportSubmitting: 신고를 보내는 중 — 사유 시트의 「신고하기」를 잠근다(같은 신고를 두 번 보내지 않는다)
    ///   - reportOutcome: 직전 신고의 결과. nil 이면 아직 없다 — ViewModel 이 전송을 시작할 때 **반드시 nil 로
    ///     되돌린다.** 같은 결과가 연달아 오면(같은 메시지를 또 신고 → 같은 409) 값이 안 바뀌어
    ///     시트를 닫는 효과가 발화하지 않는다.
    ///   - onReportMessage: 신고 전송(메시지 id, 사유, 상세). 상세는 비어 있으면 nil 로 접어서 넘긴다 — 서버가 공백을 「기타」에서 거절한다.
    ///     「누가」는 서버가 메시지에서 찾으므로 메시지 id 하나로 끝난다.
    public init(
        roomTitle: String,
        roomSubtitle: String,
        messages: [ChatUiMessage],
        input: String = "",
        sending: Bool = false,
        errorMessage: String? = nil,
        onInputChange: @escaping (String) -> Void = { _ in },
        onSend: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {},
        onOpenMatching: (() -> Void)? = nil,
        onLeaveChat: @escaping () -> Void = {},
        onTabSelect: @escaping (MoyeotaTab) -> Void = { _ in },
        muted: Bool = false,
        onToggleMute: @escaping () -> Void = {},
        canLeave: Bool = true,
        search: ChatSearchUi = ChatSearchUi(),
        onOpenSearch: @escaping () -> Void = {},
        onCloseSearch: @escaping () -> Void = {},
        onSearchQueryChange: @escaping (String) -> Void = { _ in },
        onSearchRetry: @escaping () -> Void = {},
        onSearchLoadMore: @escaping () -> Void = {},
        reportSubmitting: Bool = false,
        reportOutcome: ChatReportOutcome? = nil,
        onReportMessage: @escaping (Int64, ChatReportReason, String?) -> Void = { _, _, _ in },
        followsBottomOnOpen: Bool = true
    ) {
        _scrollTracker = State(initialValue: ChatScrollTracker(followsBottomOnOpen: followsBottomOnOpen))
        self.roomTitle = roomTitle
        self.roomSubtitle = roomSubtitle
        self.messages = messages
        self.input = input
        self.sending = sending
        self.errorMessage = errorMessage
        self.onInputChange = onInputChange
        self.onSend = onSend
        self.onBack = onBack
        self.onOpenMatching = onOpenMatching
        self.onLeaveChat = onLeaveChat
        self.onTabSelect = onTabSelect
        self.muted = muted
        self.onToggleMute = onToggleMute
        self.canLeave = canLeave
        self.search = search
        self.onOpenSearch = onOpenSearch
        self.onCloseSearch = onCloseSearch
        self.onSearchQueryChange = onSearchQueryChange
        self.onSearchRetry = onSearchRetry
        self.onSearchLoadMore = onSearchLoadMore
        self.reportSubmitting = reportSubmitting
        self.reportOutcome = reportOutcome
        self.onReportMessage = onReportMessage
    }

    private func closeReport() {
        reportTarget = nil
        reasonPickerOpen = false
        reportReason = nil
        reportDescription = ""
        reportSubmitted = false
    }

    private func openReport(_ target: ChatUiMessage) {
        closeReport()
        reportTarget = target
    }

    /// 자동 스크롤을 다시 판단할 계기. 원본 `LaunchedEffect(messages.size, imeVisible, listScroll.maxValue)` 의 키다.
    private struct AutoScrollKey: Equatable {
        let messageCount: Int
        let imeVisible: Bool
        let maxScroll: CGFloat
    }

    public var body: some View {
        // 카운터와 전송 가능 여부를 **한 곳에서** 뽑는다(`chatInputUi`) — 두 곳에서 길이를 세면
        // 기준이 갈려 「999자인데 버튼이 잠김」이 생긴다. 잠그기 전에 이유를 먼저 보여 준다는 규칙도
        // 그 함수 주석에 있다.
        let inputUi = chatInputUi(input: input, sending: sending)
        ZStack {
            // 키보드가 올라온 만큼 화면을 줄인다 — SwiftUI 의 기본 키보드 회피(원본 `imePadding`).
            VStack(spacing: 0) {
                header
                // 검색 중에는 배너·대화·입력 바 대신 결과 목록만. 닫으면 원래 화면으로 돌아온다.
                //
                // 대화 쪽은 트리에서 빼지 않고 가려 둔다. 원본은 스크롤 상태를 화면 수준(`rememberScrollState`)에 두어
                // 검색을 열고 닫아도 읽던 자리가 남는다. `ScrollView` 는 트리에서 빠지면 위치를 잃고, 닫을 때 맨 위에서
                // 새로 시작해 읽던 자리를 놓치거나 바닥까지 내려오는 스크롤이 보인다. 입력 바까지 함께 남기는 이유는
                // 빠졌다 돌아오면 목록 높이가 달라져 바닥에 있던 사람의 위치가 어긋나기 때문이다.
                ZStack {
                    conversation(inputUi: inputUi)
                        .opacity(search.open ? 0 : 1)
                        .allowsHitTesting(!search.open)
                        .accessibilityHidden(search.open)
                    if search.open {
                        SearchResults(search: search, onRetry: onSearchRetry, onLoadMore: onSearchLoadMore)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 24는 하단탭 노출 화면 (공통 규칙). 다만 키보드가 올라오면 숨긴다 —
                // 키보드 바로 위에 탭바가 얹히면 대화가 보이는 높이만 그만큼 줄어든다.
                if !imeVisible {
                    MoyeotaBottomBar(selected: .chat, onSelect: onTabSelect)
                }
            }

            // 채팅방 나가기 재확인 다이얼로그 — 나가기를 누르면 **항상** 거친다(되돌릴 수 없다).
            //
            // 공용 확인 다이얼로그를 쓰고 **확인을 빨강**으로 둔다(디자인 QA R3·G11). 예전엔 손으로 그린
            // 다이얼로그에 파란 「나가기」를 달았다 — 되돌릴 수 없는 이탈에 주 행동 색을 쓴 것이다.
            //
            // 본문은 「되돌릴 수 없다」를 먼저 적는다 — 이 다이얼로그가 있는 이유다. 서버가 나간 참여자를
            // 되살리지 못하고(chat_room_user 복합키에 leftAt 만 찍힌다) 앱에도 다시 들어가는 화면이 없다.
            if leaveConfirmOpen {
                MoyeotaConfirmDialog(
                    title: "채팅방을 나갈까요?",
                    confirmText: "나가기",
                    onConfirm: {
                        leaveConfirmOpen = false
                        onLeaveChat() // → 14 홈
                    },
                    onDismiss: { leaveConfirmOpen = false },
                    body: "한 번 나가면 이 대화로 다시 들어올 수 없어요.\n"
                        + "채팅방 나가기는 탑승 이탈과 별개라 진행 중인 탑승은 유지돼요.",
                    dismissText: "취소",
                    destructive: true
                )
                // 원본 대화상자는 제 창이라 입력 바의 키보드 회피(`imePadding`)를 받지 않는다 — 키보드와 무관하게 가운데다.
                .ignoresSafeArea(.keyboard)
            }

            // 신고 액션 시트 — 꾹 누른 말풍선 하나에 대한 동작 목록. 지금은 한 줄뿐이지만 24a 메뉴와
            // 같은 모양으로 둔 이유는 다음 줄(예: 메시지 복사)이 들어올 자리이기 때문이다.
            if reportTarget != nil, !reasonPickerOpen {
                MessageActionSheet(
                    onReport: { reasonPickerOpen = true },
                    onDismiss: { closeReport() }
                )
            }

            // 사유 선택 시트 — Scrim + 다이얼로그 모서리(20) 카드.
            if let target = reportTarget, reasonPickerOpen {
                ReportReasonSheet(
                    quotedText: target.text,
                    reason: reportReason,
                    description: reportDescription,
                    submitting: reportSubmitting,
                    // 이 시트에서 보낸 것의 답만 시트 안에 적는다(`reportSubmitted`).
                    failureMessage: (reportOutcome?.retryable == true && reportSubmitted) ? reportOutcome?.message : nil,
                    onReasonSelect: { picked in
                        reportReason = picked
                        // 「기타」가 아닌 사유로 바꾸면 적어 둔 상세를 버린다 — 그 사유에서는 상세가
                        // 화면에 보이지 않는데 몰래 함께 전송되면 사용자가 쓴 줄 모르는 글이 신고에 붙는다.
                        if !picked.requiresDescription { reportDescription = "" }
                    },
                    onDescriptionChange: { typed in
                        // 자르지 않고 받아 두되 붙여넣기 폭주만 막는다 — 한도는 카운터가 말한다.
                        if typed.utf16.count <= REPORT_DESCRIPTION_HARD_LIMIT { reportDescription = typed }
                    },
                    onSubmit: { picked in
                        reportSubmitted = true
                        // 공백만 적은 상세는 **없는 것과 같다** — 서버가 「기타」에서 isBlank 를
                        // 400 으로 거절하므로 전송 버튼이 이미 잠겨 있고, 그 밖의 사유에서는
                        // 빈 문자열을 실어 보낼 이유가 없다.
                        let trimmed = reportDescription.trim()
                        onReportMessage(target.id, picked, trimmed.isBlank ? nil : trimmed)
                    },
                    onDismiss: { closeReport() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 흰 바탕(디자인 QA R1·G2). 예전 회색 바탕은 흰 상대 말풍선을 그림자로 띄워야 보였다 — 바탕을 희게 두고
        // 상대 말풍선을 옅은 회색 면으로 칠하면 그림자 없이 구분된다(디자인 문서 chat-bubble-partner).
        .background(MoyeotaColor.SurfaceCanvas.ignoresSafeArea())
        // 결과가 오면 **다시 보내서 달라질 실패가 아닌 한** 시트를 닫는다. 「이미 신고한 메시지」를
        // 열어 두면 사유를 바꿔도 영원히 같은 409 라(실측) 사용자가 빠져나갈 수 없다.
        .onChange(of: reportOutcome, initial: true) { _, outcome in
            if let outcome, !outcome.retryable { closeReport() }
        }
        // 검색 중 뒤로가기는 방을 나가는 게 아니라 검색을 닫는다 — 카카오톡·기본 메시지 앱과 같은 기대
        .moyeotaBackHandler(enabled: search.open) { onCloseSearch() }
        // 신고 시트가 열려 있으면 뒤로가기가 그걸 먼저 닫는다. 없으면 꾹 눌러 시트를 띄운 사용자가
        // 뒤로가기로 **방을 떠나 버린다** — 바깥을 탭하는 길만 두면 시트가 화면을 덮은 상태에서
        // 유일하게 익숙한 탈출구가 방 이탈로 이어진다.
        .moyeotaBackHandler(enabled: reportTarget != nil) { closeReport() }
        // 원본 `remember` 는 화면이 컴포지션에서 빠지면 사라진다. `@State` 는 스택에 있는 동안 남으므로 직접 비운다 — 메뉴·확인창이
        // 닫히고 적던 신고 상세도 버려진다. 「바닥에 붙어 있는가」는 비우지 않는다: 원본도 돌아오면 저장된 스크롤 위치로 다시 재서 같은 값이 된다.
        .onDisappear {
            menuOpen = false
            leaveConfirmOpen = false
            closeReport()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            imeVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            imeVisible = false
        }
    }

    /// 테스트가 확인창이 열린 상태를 만드는 입구. 창에 올린 화면이라도 코드로는 SwiftUI 버튼을 누를 수 없다.
    func seeded(leaveConfirmOpen: Bool) -> Self {
        var copy = self
        copy._leaveConfirmOpen = State(initialValue: leaveConfirmOpen)
        return copy
    }

    /// 배너 + 대화 + 입력 바 — 검색 중에는 가려지는 쪽.
    private func conversation(inputUi: ChatInputUi) -> some View {
        VStack(spacing: 0) {
            // 「매칭 화면으로」 — 진행 중인 방의 채팅방에서만 뜬다
            if let onOpenMatching {
                matchingBanner(onOpenMatching: onOpenMatching)
            }
            // 메시지 리스트 + (24a/24b 오버레이 영역)
            ZStack(alignment: .topTrailing) {
                messageList
                if menuOpen {
                    menuOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 입력 바 — 검색 중엔 숨긴다(결과 목록 위에서 전송할 일이 없고, 키보드는 검색 바가 쓴다)
            inputBar(inputUi: inputUi)
        }
    }

    // ─── 헤더 ────────────────────────────────────────────────────────────────

    // 헤더 (흰 배경). 검색을 열면 제목 줄이 통째로 검색 바로 바뀐다 — 제목 아래에 한 줄 더 얹는
    // 것보다 대화가 보이는 높이를 안 뺏고, 「지금 검색 중」이 분명하다.
    private var header: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            if search.open {
                SearchHeader(query: search.query, onQueryChange: onSearchQueryChange, onClose: onCloseSearch)
            } else {
                // 다른 하위 화면과 같은 공용 앱바(디자인 QA R2·G7) — 가운데 제목 + 부제, 48 아이콘 버튼 둘.
                // 예전엔 22 뒤로가기·28 상자 친 검색 아이콘·맨 점 셋이 눌림 표시 없이 붙어 있었다.
                // 부제가 경로(역지오코딩된 전체 주소)로 길어질 수 있어 앱바가 한 줄 말줄임한다.
                MoyeotaTopBar(
                    title: roomTitle,
                    onBack: onBack,
                    subtitle: muted ? "\(roomSubtitle) · 알림 꺼짐" : roomSubtitle,
                    // 오른쪽 아이콘 버튼 둘(48 × 2 + 끝 여백 4)을 피해 제목을 가운데에 둔다
                    titleInset: 104,
                    actionsEndPadding: MoyeotaSpacing.Xxs
                ) {
                    ChatIconButton(label: "대화 내용 검색", action: onOpenSearch) {
                        SearchIcon()
                    }
                    ChatIconButton(label: "채팅방 메뉴", action: { menuOpen = true }) {
                        MoreVerticalIcon()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
    }

    // 바탕은 옅은 회색(디자인 QA R3) — 옅은 파랑 띠는 입력 바의 파란 전송 버튼과 강조를 다퉜다.
    // 화살표 글자(→) 대신 그린 꺾쇠를 쓴다(G10). 띠 전체가 누르는 자리라 높이를 48 로 채운다.
    private func matchingBanner(onOpenMatching: @escaping () -> Void) -> some View {
        Button(action: onOpenMatching) {
            HStack(alignment: .center, spacing: 0) {
                // 왼쪽 문구만 줄어든다 — 좁은 폰에서 오른쪽 링크가 밀려 잘리지 않게
                Text("진행 중인 탑승이 있어요")
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextBody)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: MoyeotaSpacing.Xs)
                Text("매칭 화면으로")
                    .moyeotaText(MoyeotaType.BodySm.copy(fontWeight: .semibold).hangulTrimmed, color: MoyeotaColor.Primary600)
                    .lineLimit(1)
                    .fixedSize()
                ChevronIcon(size: MoyeotaIconSize.Sm, tint: MoyeotaColor.Primary600)
            }
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(MoyeotaColor.SurfaceSoft)
        }
        .buttonStyle(PressOverlayStyle(shape: Rectangle()))
    }

    // ─── 메시지 리스트 ───────────────────────────────────────────────────────

    private var messageList: some View {
        let maxScroll = max(contentHeight - viewportHeight, 0)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            // 신고 길은 **신고할 수 있는 말풍선에만** 붙는다(`ChatUiMessage.canReport`) —
                            // 내 말풍선이나 서버 id 가 없는 말풍선에 붙이면 서버 400 을 왕복해 받는다.
                            MessageRow(
                                message: message,
                                onRequestReport: message.canReport() ? { openReport($0) } : nil
                            )
                            if index != messages.count - 1 {
                                Spacer().frame(height: 16)
                            }
                        }
                    }
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    .padding(.vertical, MoyeotaSpacing.Md)
                    Color.clear
                        .frame(height: 0)
                        .id(ChatListBottomAnchor)
                }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: ChatScrollMetrics.self) { geometry in
                    let frame = geometry.frame(in: .named(ChatListCoordinateSpace))
                    return ChatScrollMetrics(top: frame.minY, bottom: frame.maxY)
                } action: { metrics in
                    scrollTracker.scrolled(to: metrics)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .coordinateSpace(.named(ChatListCoordinateSpace))
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.never)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                viewportHeight = height
                scrollTracker.viewportHeight = height
            }
            // 지난 대화를 올려 읽는 중이면 가만히 둔다 — 읽던 자리를 바닥으로 끌어내리면 자리를 잃는다.
            // (`maxScroll` 이 키에 있어 레이아웃이 바뀔 때마다 재발화하므로, 가드가 없으면
            //  새 메시지뿐 아니라 **아무 레이아웃 변화에도** 바닥으로 끌려갔다.)
            .onChange(
                of: AutoScrollKey(messageCount: messages.count, imeVisible: imeVisible, maxScroll: maxScroll),
                initial: true
            ) {
                guard scrollTracker.shouldFollow(maxScroll: viewportHeight > 0 ? maxScroll : 0) else { return }
                // 가려진 동안과 검색을 막 닫은 순간에는 애니메이션 없이 맞춘다(`followWithoutAnimation` 주석).
                if search.open || scrollTracker.followWithoutAnimation {
                    proxy.scrollTo(ChatListBottomAnchor, anchor: .bottom)
                } else {
                    withAnimation {
                        proxy.scrollTo(ChatListBottomAnchor, anchor: .bottom)
                    }
                }
            }
            .onChange(of: search.open) { _, open in
                if !open { scrollTracker.searchClosed() }
            }
        }
    }

    // ─── 24a 메뉴 ────────────────────────────────────────────────────────────

    // 24a · 메뉴 오버레이 — 배경 탭 → 24
    //
    // 닫는 탭은 뒤에 깐 뷰가 아니라 **부모**에 건다. 원본도 부모 `Box` 의 `clickable` 이라 안내 줄·구분선처럼
    // 입력을 받지 않는 카드 안쪽을 눌러도 닫힌다. 메뉴 항목은 자기 버튼이 먼저 받는다.
    private var menuOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            VStack(spacing: 0) {
                Button {
                    onToggleMute()
                    menuOpen = false
                } label: {
                    menuRowLabel(
                        // 서버 음소거 토글 — 눌러서 끄고, 다시 눌러 켠다(예전엔 끄기만 있는 로컬 상태였다)
                        muted ? "채팅방 알림 켜기" : "채팅방 알림 끄기"
                    )
                }
                .buttonStyle(PressOverlayStyle(shape: Rectangle()))
                if canLeave {
                    HorizontalDivider(color: MoyeotaColor.Hairline)
                        .padding(.horizontal, MoyeotaSpacing.Md)
                    Button {
                        menuOpen = false
                        // **언제나** 재확인을 받는다 — 나가기는 어느 방에서든 되돌릴 수 없다.
                        // 서버가 나간 참여자를 되살리지 못하고(leaveConfirm 다이얼로그 본문),
                        // 앱에 재합류를 부르는 화면도 없다. 예전에는 「진행 중 탑승이 있을 때만」
                        // 물었는데 그 플래그가 상수 false 로 고정돼 있어 **한 번도 묻지 않았고**,
                        // 다이얼로그 자체가 도달 불가능한 죽은 코드였다(실기 QA).
                        leaveConfirmOpen = true
                    } label: {
                        menuRowLabel("채팅방 나가기")
                    }
                    .buttonStyle(PressOverlayStyle(shape: Rectangle()))
                }
                HorizontalDivider(color: MoyeotaColor.Hairline)
                    .padding(.horizontal, MoyeotaSpacing.Md)
                // 신고를 **여기서 실행할 수는 없다** — 서버가 `chatMessageId` 를 필수로 받아
                // 어떤 메시지인지 정해지지 않으면 보낼 수 없다. 그렇다고 입구를 롱프레스
                // 하나로 두면 **안전 기능인데 아무도 못 찾는다**(눌러도 시각 반응이 없어
                // 우연히 발견될 여지도 없다). 실행은 못 해도 **안내는 여기 둘 수 있다.**
                Text(verbatim: "신고는 메시지를 꾹 눌러요".characterWrapped)
                    .accessibilityLabel("신고는 메시지를 꾹 눌러요")
                    .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                    .padding(.horizontal, MoyeotaSpacing.Md)
                    .padding(.vertical, MoyeotaSpacing.Sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 164)
            .background(MoyeotaColor.SurfaceCanvas)
            .clipShape(MoyeotaShape.Card)
            // 진짜 겹침(드롭다운)이라 그림자를 남긴다 — 다이얼로그와 같은 Modal 높이 하나(G4).
            // 메뉴 버튼 바로 아래(앱바 밑 4)에 연다.
            .modalShadow(MoyeotaShape.Card)
            .padding(.top, MoyeotaSpacing.Xxs)
            .padding(.trailing, MoyeotaSpacing.ScreenGutter)
        }
        .contentShape(Rectangle())
        .onTapGesture { menuOpen = false }
    }

    private func menuRowLabel(_ text: String) -> some View {
        Text(text)
            .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
            .padding(.horizontal, MoyeotaSpacing.Md)
            .padding(.vertical, MoyeotaSpacing.Sm)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
    }

    // ─── 입력 바 ─────────────────────────────────────────────────────────────

    private func inputBar(inputUi: ChatInputUi) -> some View {
        VStack(spacing: 0) {
            HorizontalDivider(color: MoyeotaColor.Hairline)
            // 신고 결과 — 전송 실패 안내와 **같은 자리**다. 시트가 닫히면서 결과가 보여야
            // 하므로 시트 안이 아니라 여기에 둔다.
            //
            // 시트가 열려 있는 동안에는 감춘다: 지난 결과를 덮어쓰지 않고 들고 있기 때문에
            // (다음 신고를 보낼 때 ViewModel 이 비운다) 새 신고를 적는 중에 **앞 신고의
            // 문구가 남아 보이면** 방금 누른 것의 답으로 읽힌다.
            if let reportOutcome, reportTarget == nil {
                NoticeBanner(kind: reportOutcome.accepted ? .success : .error, text: reportOutcome.message)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    .padding(.vertical, MoyeotaSpacing.Xs)
            }
            // 전송·수신 실패 안내 — 입력한 내용은 지우지 않는다
            if let errorMessage {
                NoticeBanner(kind: .error, text: errorMessage)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    .padding(.vertical, MoyeotaSpacing.Xs)
            }
            // 글자 수 — **입력창 바로 위**. 한도에 가까워지면 나타나고, 넘기면 강조된다
            // (`chatInputUi`). 넘긴 상태에서 전송 버튼이 잠기는데, 그 이유가 **누르지 않아도**
            // 이 자리에 있어야 한다는 것이 이 줄의 존재 이유다.
            //
            // 자리를 여기로 둔 근거: 입력 바 안이라 말풍선 목록이 그만큼 줄고,
            // 나타날 때 입력 pill 과 전송 버튼이 한 줄 높이만큼 **위로** 올라간다. 그 움직임은
            // 한도보다 100자 앞서(= 잠기기 전에) 한 번만 일어나므로, 버튼이 잠기는 순간에는
            // 레이아웃이 움직이지 않는다(`COUNTER_VISIBLE_FROM`).
            // 말풍선 위에 띄우는(overlay) 안은 버렸다 — 마지막 메시지를 가린다.
            if let counter = inputUi.counter {
                Text(counter)
                    // 넘긴 상태는 **실제로 막힌** 상태라 경고색이 맞다(16 의 1인 안내와 반대 —
                    // 그쪽은 정상 선택이라 회색이다). 넘기기 전 예고는 보조 문구색 그대로 둔다.
                    .moyeotaText(
                        MoyeotaType.CaptionMd.tabularNums()
                            .copy(fontWeight: inputUi.overLimit ? .semibold : .medium)
                            .hangulTrimmed,
                        color: inputUi.overLimit ? MoyeotaColor.Danger500 : MoyeotaColor.TextMute
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    .padding(.top, MoyeotaSpacing.Xs)
            }
            HStack(alignment: .center, spacing: 0) {
                ZStack(alignment: .leading) {
                    BasicTextField(
                        value: input,
                        // 서버 한도는 1000자(`MAX_CONTENT_LENGTH`)지만 여기서 자르지 않는다 —
                        // 넘긴 사실은 위 카운터가 말한다(`INPUT_HARD_LIMIT` 주석). 여기서 막는
                        // 것은 붙여넣기 폭주(2000자)뿐이고, 그 값은 그대로 둔다.
                        onValueChange: { if $0.utf16.count <= INPUT_HARD_LIMIT { onInputChange($0) } },
                        textStyle: MoyeotaType.BodyMd.copy(color: MoyeotaColor.InkPrimary),
                        singleLine: true
                    )
                    if input.isEmpty {
                        Text("메시지 보내기")
                            .moyeotaText(.BodyMd, color: MoyeotaColor.TextPlaceholder)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, MoyeotaSpacing.Md)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(MoyeotaColor.SurfaceSoft, in: MoyeotaShape.Pill)
                Spacer().frame(width: MoyeotaSpacing.Xs)
                // 전송 — 공백만 입력·한도 초과·전송 중이면 비활성(`chatInputUi`).
                // 한도 초과로 잠긴 경우의 **이유는 바로 위 카운터**가 들고 있다.
                // 비활성은 다른 버튼과 같은 SurfaceDisabled + 흐린 화살표(G5) — 예전 회색 원 위 흰 화살표는
                // 대비가 낮아 화살표가 거의 사라졌다.
                Button(action: onSend) {
                    SendArrowIcon(tint: inputUi.sendEnabled ? MoyeotaColor.TextOnDark : MoyeotaColor.TextPlaceholder)
                        .frame(width: 48, height: 48)
                        .background(inputUi.sendEnabled ? MoyeotaColor.Primary500 : MoyeotaColor.SurfaceDisabled, in: Circle())
                }
                .buttonStyle(PressOverlayStyle(shape: Circle()))
                .disabled(!inputUi.sendEnabled)
                .accessibilityLabel("메시지 보내기")
            }
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            .padding(.vertical, MoyeotaSpacing.Sm)
        }
        .frame(maxWidth: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
    }
}

/// 앱바의 48 아이콘 버튼(머티리얼 `IconButton` 자리) — 24 아이콘을 가운데 두고 누르면 흐려진다.
/// VoiceOver 이름은 버튼이 갖는다(아이콘은 장식이다).
private struct ChatIconButton<Icon: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(PressFeedbackStyle())
        .accessibilityLabel(label)
    }
}

// ─── 스크롤 위치 추적 ────────────────────────────────────────────────────────

private let ChatListCoordinateSpace = "chat-message-list"
private let ChatListBottomAnchor = "chat-message-list-bottom"

/// 뷰포트 기준 메시지 내용의 위·아래 끝.
struct ChatScrollMetrics: Equatable, Sendable {
    let top: CGFloat
    let bottom: CGFloat
}

/// 「바닥에 붙어 있는가」 — 자동 스크롤의 유일한 조건.
///
/// 판정 시점이 중요하다. 새 메시지가 붙거나 키보드가 올라오는 **그 순간**에는 스크롤 끝이 먼저 늘고
/// 위치는 아직 그대로라 거리가 벌어져 있다 — 그때의 거리로 재면 바닥에 있던 사람도 「올려 읽는 중」이
/// 된다(키보드를 올릴 때마다 바닥을 놓친다). 그래서 **스크롤이 멈춘 시점**의 위치만 근거로 삼는다.
///
/// iOS 17 에는 원본 `isScrollInProgress` 에 해당하는 값이 없다(`onScrollPhaseChange` 는 iOS 18). 그래서
/// 내용 위쪽 끝의 움직임으로 스크롤을 알아채고, 움직임이 `SETTLE_MS` 동안 멎으면 멈춘 것으로 본다.
/// 위쪽 끝이 그대로인 변화(내용 추가·키보드)는 스크롤이 아니므로 판정하지 않는다.
/// 매 프레임 바뀌는 값이라 화면 상태가 아니라 이 객체에 둔다 — 스크롤마다 본문을 다시 그리지 않는다.
@MainActor
final class ChatScrollTracker {
    private static let SETTLE_MS = 150

    /// 검색을 닫은 뒤 레이아웃이 자리 잡는 데 넉넉한 시간(키보드가 내려가는 약 0.25초 포함).
    private static let SEARCH_CLOSE_SETTLE_MS = 500

    private(set) var stickToBottom = true
    var viewportHeight: CGFloat = 0

    /// 독립 목적지의 첫 내용을 아직 기다리는가.
    ///
    /// 원본의 독립 목적지(`ChatRoomDestinationRoute`)는 넘치는 대화를 **맨 위에** 둔 채 시작하고, 전송해도 따라 내려가지 않는다.
    /// 21 → 「채팅 열기」를 원본에서 3번, 메시지·방 조회를 2.5초 늦춰 2번 더 돌려 모두 맨 위였고, 탭 목록에서 같은 방을 열면 바닥이었다.
    /// 첫 바닥 이동이 끝나기 전에 판정이 「멀다」로 굳는 것으로 읽히지만(소스로 추정) 원인을 돌려 확인하지는 않았다.
    /// 그래서 관찰한 결과만 옮긴다: 첫 내용이 슬롭보다 넘치면 움직이지 않고 따라가기를 끈다. 사용자가 바닥 근처로 내려가 멈추면 평소대로 다시 켜진다.
    private var awaitingFirstContent: Bool

    private var latest: ChatScrollMetrics?
    private var settleTask: Task<Void, Never>?
    private var searchClosedAt: ContinuousClock.Instant?

    /// 바닥 따라가기를 애니메이션 없이 할 때인가.
    ///
    /// 가려 둔 목록은 검색 중에 높이가 달랐다가(키보드·하단탭) 닫을 때 돌아온다. 그 차이를 애니메이션으로
    /// 메우면 바닥에 있던 사람에게 닫을 때마다 대화가 미끄러져 보인다. 원본은 검색 중에 목록이 없어 움직임이 없다.
    var followWithoutAnimation: Bool {
        guard let searchClosedAt else { return false }
        return searchClosedAt.duration(to: .now) < .milliseconds(Self.SEARCH_CLOSE_SETTLE_MS)
    }

    func searchClosed() {
        searchClosedAt = .now
    }

    init(followsBottomOnOpen: Bool = true) {
        awaitingFirstContent = !followsBottomOnOpen
    }

    deinit {
        settleTask?.cancel()
    }

    /// 바닥 따라가기 조건. 스크롤할 거리가 생기기 전에는 첫 내용을 기다린다.
    func shouldFollow(maxScroll: CGFloat) -> Bool {
        if awaitingFirstContent {
            guard maxScroll > 0 else { return false }
            awaitingFirstContent = false
            stickToBottom = maxScroll <= AUTO_SCROLL_SLOP
        }
        return stickToBottom
    }

    func scrolled(to metrics: ChatScrollMetrics) {
        let moved = latest.map { $0.top != metrics.top } ?? false
        latest = metrics
        guard moved else { return }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.SETTLE_MS))
            if Task.isCancelled { return }
            guard let self, let latest = self.latest else { return }
            self.stickToBottom = latest.bottom - self.viewportHeight <= AUTO_SCROLL_SLOP
        }
    }
}

/// 말풍선 안쪽 글자 폭. 원본 `widthIn(max = 260.dp)` 에서 좌우 여백 16 씩을 뺀 값이다.
let BubbleTextMaxWidth: CGFloat = 228

/// 말풍선 글자 — 원본 `style = MoyeotaType.BodyMd`(디자인 문서 chat-bubble). 토큰이라 한글 글자 상자(`hangulTrimmed`)를 쓴다.
let BubbleTextType = MoyeotaType.BodyMd.hangulTrimmed

/// 원본 `Text` 의 말풍선 안 줄바꿈. 줄은 `softWrappedLines` 가 나누고, 한 번이라도 꺾였으면 원본처럼 최대 폭을 다 쓴다
/// (Compose `Text` 폭은 줄바꿈 없는 폭과 최대 폭 중 작은 값이다). iOS `Text` 에 맡기면 줄 끝이 달라지고 가장 긴 줄에 맞게 줄어든다.
private struct BubbleText: View {
    let text: String
    let color: Color

    var body: some View {
        let wrap = BubbleTextType.softWrappedLines(text, width: BubbleTextMaxWidth)
        Text(verbatim: wrap.text)
            .accessibilityLabel(text)
            .moyeotaText(BubbleTextType, color: color)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: wrap.wrapped ? BubbleTextMaxWidth : nil, alignment: .leading)
    }
}

/// `Modifier.widthIn(max = …)` 자리. SwiftUI `.frame(maxWidth:)` 는 제안받은 폭까지 **늘어나** 말풍선이
/// 글자 길이와 상관없이 최대 폭이 된다. 이 레이아웃은 내용 크기를 그대로 쓰고 폭만 제한한다.
private struct WidthAtMost: Layout {
    let maxWidth: CGFloat

    private func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? maxWidth, maxWidth), height: proposal.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(childProposal(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: childProposal(proposal))
    }
}

// ─── 신고 시트 ───────────────────────────────────────────────────────────────

/// 메시지 하나에 대한 동작 시트 — 모양은 24a 메뉴 오버레이를 그대로 베꼈다
/// (전면 + 배경 탭 닫기 + 다이얼로그 모서리 + Modal 그림자. Scrim 은 확인 다이얼로그 쪽을 따랐다 —
/// 24a 와 달리 이건 「무엇을 눌렀는지」가 중요해서 뒤를 가려 대상이 분명해야 한다).
/// **새 디자인을 만들지 않았다**:
/// 이 앱에는 `ModalBottomSheet` 선례가 한 건도 없고(디자인시스템에 시트 컴포넌트가 없다),
/// 메시지 단위 동작 UI 자체가 이게 처음이라 기준을 하나 더 만들면 둘 다 흔들린다.
///
/// 24a 와 달리 **아래쪽에 붙인다** — 꾹 누른 손가락이 화면 가운데~아래에 있어서, 오른쪽 위에
/// 열리는 24a 자리로 두면 눈과 손이 둘 다 움직여야 한다.
private struct MessageActionSheet: View {
    let onReport: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            MoyeotaColor.Scrim
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            // 시트 안을 눌러도 닫히지 않는다 — 카드의 배경이 터치를 받아 뒤의 Scrim 까지 닿지 않는다
            VStack(spacing: 0) {
                Button(action: onReport) {
                    Text("이 메시지 신고하기")
                        .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        .padding(.horizontal, MoyeotaSpacing.Md)
                        .padding(.vertical, MoyeotaSpacing.Md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PressOverlayStyle(shape: Rectangle()))
                HorizontalDivider(color: MoyeotaColor.Hairline)
                    .padding(.horizontal, MoyeotaSpacing.Md)
                Button(action: onDismiss) {
                    Text("취소")
                        .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextBody)
                        .padding(.horizontal, MoyeotaSpacing.Md)
                        .padding(.vertical, MoyeotaSpacing.Md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PressOverlayStyle(shape: Rectangle()))
            }
            .background(MoyeotaColor.SurfaceCanvas)
            .clipShape(MoyeotaShape.Dialog)
            .modalShadow(MoyeotaShape.Dialog)
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            .padding(.vertical, MoyeotaSpacing.Lg)
        }
        // 원본은 이 시트에 `imePadding` 을 두지 않았다 — 창 아래쪽에 붙는다.
        .ignoresSafeArea(.keyboard)
    }
}

/// 사유 선택 시트. 모양은 **공용 확인 다이얼로그**(Scrim + 20 모서리 카드)에 맞췄다.
///
/// 색에 대한 판단: 빨강(`MoyeotaColor` 의 Danger/Safety 계열)을
/// **쓰지 않는다.** 이 앱에서 빨강 신고 요소는 27 긴급 신고(112 통화)로 가는 길이고
/// `SafetyButton` 은 주석이 「긴급 신고 전용, 다른 곳 사용 금지」로 못 박았다. 메시지 신고는
/// 112 를 부르는 일이 아니라서 같은 색을 쓰면 두 신고가 구분되지 않는다 — 평상시 색으로 두고
/// 확인 버튼만 Primary 로 강조한다.
///
/// - `quotedText`: 신고 대상 말풍선의 글. **무엇을 신고하는지 보여 주지 않으면** 꾹 누른 것이
///   맞는 메시지인지 확인할 길이 없다(목록이 그동안 새 메시지로 밀려 있을 수 있다).
/// - `failureMessage`: 다시 보내서 달라질 수 있는 실패만 들어온다 — 시트를 열어 둔 이유를 적는다.
struct ReportReasonSheet: View {
    let quotedText: String
    let reason: ChatReportReason?
    let description: String
    let submitting: Bool
    let failureMessage: String?
    let onReasonSelect: (ChatReportReason) -> Void
    let onDescriptionChange: (String) -> Void
    let onSubmit: (ChatReportReason) -> Void
    let onDismiss: () -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ZStack {
            MoyeotaColor.Scrim
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            // 사유 5줄 + 입력창 + 버튼이 작은 폰에서 화면을 넘긴다 — 스크롤을 둔다.
            // `ScrollView` 는 남는 높이를 다 차지하므로 내용 높이까지만 쓰게 묶는다(원본은 내용만큼이고 넘칠 때만 스크롤된다).
            //
            // 「기타」를 고르면 입력창이 열려 키보드가 올라온다 — 키보드 회피가 없으면 시트가
            // 화면 가운데에 그대로 있어 **「신고하기」 버튼이 키보드 뒤로 숨는다**(쓴 글을
            // 보낼 수가 없다). 이 시트만 `ignoresSafeArea(.keyboard)` 를 걸지 않는 이유다.
            ScrollView {
                sheetContent
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            // 원본 `verticalScroll` 은 키보드를 건드리지 않는다 — 「신고하기」까지 내리는 동안에도 계속 쓸 수 있다.
            .scrollDismissesKeyboard(.never)
            .frame(maxHeight: contentHeight)
            .background(MoyeotaColor.SurfaceCanvas)
            .clipShape(MoyeotaShape.Dialog)
            .modalShadow(MoyeotaShape.Dialog)
            .padding(.horizontal, MoyeotaSpacing.Lg)
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        let submit = chatReportSubmitUi(reason: reason, description: description, submitting: submitting)
        VStack(alignment: .leading, spacing: 0) {
            Text("신고 사유를 알려 주세요")
                .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
            Spacer().frame(height: 8)
            // 홑낫표로 인용한다 — 공통 규칙(인용값은 「」)
            Text(verbatim: "「\(quotedText)」".characterWrapped)
                .accessibilityLabel("「\(quotedText)」")
                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextBody)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer().frame(height: 16)

            // 사유는 **하나만** 고른다 — 보조기술에도 「선택됨」을 함께 알려 준다(10 프로필 만들기의 성별 칩과 같은 레시피).
            VStack(spacing: 0) {
                ForEach(Array(chatReportReasonLabels.enumerated()), id: \.offset) { index, entry in
                    reasonRow(value: entry.0, label: entry.1)
                    if index != chatReportReasonLabels.count - 1 {
                        HorizontalDivider(color: MoyeotaColor.Hairline)
                    }
                }
            }

            // 「기타」만 상세가 필수다 — 고르기 전에는 입력창을 그리지 않는다. 늘 띄워 두면
            // 「안 써도 되는 칸」이 시트를 길게 만들고, 쓰면 보내지는지도 알 수 없다.
            if reason?.requiresDescription == true {
                Spacer().frame(height: 16)
                // 디자인시스템의 `MoyeotaTextField` 를 쓰지 않았다 — 그 컴포넌트는 입력 박스를
                // **52pt 고정 높이**로 그려서 여러 줄을 쓰면 글이 잘려 보인다(500자를 받는 칸이다).
                // 그래서 이 파일이 이미 두 번 한 것(검색 바·메시지 입력 pill)과 같은 모양으로
                // 직접 그린다. 새 스타일을 만든 게 아니라 같은 pill 을 **높이만** 늘린 것이다.
                ZStack(alignment: .topLeading) {
                    BasicTextField(
                        value: description,
                        onValueChange: onDescriptionChange,
                        textStyle: MoyeotaType.BodyMd.copy(color: MoyeotaColor.InkPrimary),
                        // 여러 줄로 받는다 — 상황을 적는 칸이라 한 줄로 가로 스크롤되면 쓴 글을
                        // 다시 읽을 수가 없다.
                        singleLine: false
                    )
                    if description.isEmpty {
                        Text("어떤 점이 문제였는지 알려 주세요")
                            .moyeotaText(.BodyMd, color: MoyeotaColor.TextPlaceholder)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, MoyeotaSpacing.Md)
                .padding(.vertical, MoyeotaSpacing.Sm)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .background(MoyeotaColor.SurfaceSoft, in: MoyeotaShape.Card)
                if let counter = submit.counter {
                    Spacer().frame(height: MoyeotaSpacing.Xxs)
                    Text(counter)
                        .moyeotaText(
                            MoyeotaType.CaptionMd.tabularNums().hangulTrimmed,
                            color: submit.overLimit ? MoyeotaColor.Danger600 : MoyeotaColor.TextMute
                        )
                }
            }

            if let failureMessage {
                Spacer().frame(height: 12)
                NoticeBanner(kind: .error, text: failureMessage)
            }

            Spacer().frame(height: MoyeotaSpacing.Lg)
            // 앱의 CTA 한 가족(G5) — 손으로 그린 44 r12 상자 둘 대신 공용 알약 버튼을 나란히 둔다.
            // 잠긴 「신고하기」는 공용 비활성 색(SurfaceDisabled)으로 말한다 — 눌리지 않는 이유는 위 카운터나
            // 안 고른 사유 줄에 이미 보인다.
            HStack(spacing: MoyeotaSpacing.Xs) {
                SecondaryButton(text: "취소", onClick: onDismiss)
                    .frame(maxWidth: .infinity)
                PrimaryCtaButton(
                    text: submitting ? "보내는 중" : "신고하기",
                    onClick: { if let reason { onSubmit(reason) } },
                    enabled: submit.submitEnabled
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func reasonRow(value: ChatReportReason, label: String) -> some View {
        let selected = reason == value
        return Button {
            onReasonSelect(value)
        } label: {
            HStack(alignment: .center, spacing: 0) {
                // ★ **색만으로 선택을 표시하지 않는다.** 이 앱에는 색 하나로만 가르는 자리가
                // 한 곳도 없다 — 항상 (도형 또는 채움) + (굵기 또는 그림자)가 함께 바뀐다.
                // 색약 사용자에게 글자 색·굵기 차이만 남으면 무엇을 골랐는지 알 수 없다.
                ReportReasonMark(selected: selected)
                Spacer().frame(width: 12)
                Text(label)
                    .moyeotaText(
                        MoyeotaType.BodyMd.copy(fontWeight: selected ? .semibold : .regular).hangulTrimmed,
                        color: selected ? MoyeotaColor.Primary600 : MoyeotaColor.InkPrimary
                    )
            }
            // 되돌릴 수 없는 신고의 입력이라 터치 타깃을 48pt 로 채운다
            .padding(.vertical, MoyeotaSpacing.Sm)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        }
        .buttonStyle(PressOverlayStyle(shape: Rectangle()))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 신고 사유의 선택 표시 — **도형**이다.
///
/// 글자 색·굵기만 바꾸면 색약 사용자에게 무엇을 골랐는지 남지 않는다. 이 앱에는 색 하나로만
/// 선택을 가르는 자리가 한 곳도 없고(10 성별 칩·36 사진 격자·14 즐겨찾기 모두 도형이 함께 바뀐다),
/// 되돌릴 수 없는 신고의 입력이 그 규칙을 처음 어기는 자리가 되면 안 된다.
private struct ReportReasonMark: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(selected ? MoyeotaColor.Primary500 : MoyeotaColor.SurfaceCanvas)
            if selected {
                Circle()
                    .fill(MoyeotaColor.SurfaceCanvas)
                    .frame(width: 8, height: 8)
            } else {
                // 빈 원의 테두리는 BorderStrong — Hairline(1.15:1)으로는 고를 수 있는 원이 보이지 않았다
                Circle().strokeBorder(MoyeotaColor.BorderStrong, lineWidth: 1.5)
            }
        }
        .frame(width: 20, height: 20)
    }
}

// ─── 말풍선 ──────────────────────────────────────────────────────────────────

/// `onRequestReport`: 상대 말풍선을 **꾹 눌렀을 때** 신고 액션 시트를 띄우는 길.
/// nil 이면 롱프레스를 아예 달지 않는다 — 내 말풍선에는 절대 nil 로 들어온다
/// (`ChatUiMessage.canReport`). 내 말풍선 분기에서는 쓰지도 않는다.
private struct MessageRow: View {
    let message: ChatUiMessage
    var onRequestReport: ((ChatUiMessage) -> Void)?

    var body: some View {
        if message.isMine {
            HStack(alignment: .bottom, spacing: 0) {
                Spacer(minLength: 0)
                if let meta = message.meta {
                    Text(meta)
                        .moyeotaText(MoyeotaType.CaptionSm.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .fixedSize()
                    Spacer().frame(width: MoyeotaSpacing.Xs)
                }
                // 내 말풍선 — Primary500 / 흰 글씨 (토큰 chat-bubble-mine)
                WidthAtMost(maxWidth: 260) {
                    BubbleText(text: message.text, color: MoyeotaColor.TextOnDark)
                        .padding(.horizontal, MoyeotaSpacing.Md)
                        .padding(.vertical, MoyeotaSpacing.Xs)
                }
                .background(
                    MoyeotaColor.Primary500,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: BubbleRadius,
                        bottomLeadingRadius: BubbleRadius,
                        bottomTrailingRadius: BubbleTailRadius,
                        topTrailingRadius: BubbleRadius,
                        style: .circular
                    )
                )
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .top, spacing: 0) {
                // 이름은 바로 아래에 따로 적으므로 아바타에는 사진만 준다 — 못 받았으면 회색 원이다.
                AvatarCircle(size: 32, imageUrl: message.senderImageUrl)
                Spacer().frame(width: MoyeotaSpacing.Xs)
                VStack(alignment: .leading, spacing: 0) {
                    Text(message.senderName ?? "")
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                    Spacer().frame(height: MoyeotaSpacing.Xxs)
                    HStack(alignment: .bottom, spacing: 0) {
                        peerBubble
                        if let timeLabel = message.timeLabel {
                            Spacer().frame(width: MoyeotaSpacing.Xxs)
                            Text(timeLabel)
                                .moyeotaText(MoyeotaType.CaptionSm.hangulTrimmed, color: MoyeotaColor.TextMute)
                                .fixedSize()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // 상대 말풍선 — 옅은 회색 면, **그림자 없음**(토큰 chat-bubble-partner, 디자인 QA R1).
    // 예전엔 흰 카드 + 그림자였다 — 대화 목록의 말풍선마다 그림자가 붙어 화면 전체가 떠 보였다.
    @ViewBuilder
    private var peerBubble: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: BubbleRadius,
            bottomLeadingRadius: BubbleTailRadius,
            bottomTrailingRadius: BubbleRadius,
            topTrailingRadius: BubbleRadius,
            style: .circular
        )
        let bubble = WidthAtMost(maxWidth: 260) {
            BubbleText(text: message.text, color: MoyeotaColor.InkPrimary)
                .padding(.horizontal, MoyeotaSpacing.Md)
                .padding(.vertical, MoyeotaSpacing.Xs)
        }
        .background(MoyeotaColor.SurfaceSoft, in: shape)

        if let onRequestReport {
            // 롱프레스는 말풍선 **전체**에 건다 — 안쪽 여백이 눌리지 않는 띠가 되면
            // 「글자 위를 정확히 눌러야 열린다」가 된다.
            // 짧은 탭은 아무 일도 하지 않는다(빈 동작): 이 앱에 메시지 탭 동작이 없고, 눌림 표시도
            // 없다 — 누를 때마다 번지면 말풍선이 버튼처럼 보여 「탭하면 뭔가 있다」는 거짓 신호를 준다.
            // 빈 탭을 함께 다는 이유는 하나 더 있다: 없으면 롱프레스가 `ScrollView` 의 드래그를 가로챈다.
            bubble
                .contentShape(shape)
                .onTapGesture {}
                // Compose 롱프레스 기본 판정 시간(400ms)
                .onLongPressGesture(minimumDuration: 0.4) { onRequestReport(message) }
                .accessibilityAction(named: "이 메시지 신고하기") { onRequestReport(message) }
        } else {
            bubble
        }
    }
}

// ─── 검색 ────────────────────────────────────────────────────────────────────

/// 검색 모드 헤더 — 뒤로가기(닫기) · 입력 · 지우기. 열리자마자 포커스를 잡아 키보드를 올린다.
/// 검색은 입력하는 동안 자동으로 나가므로(ViewModel 디바운스) 자판의 「검색」 버튼은 키보드만 내린다.
private struct SearchHeader: View {
    let query: String
    let onQueryChange: (String) -> Void
    let onClose: () -> Void

    @State private var focus = FocusRequester()

    // 앱바와 같은 56 줄 · 48 뒤로가기(G12). 예전엔 22 화살표가 눌림 표시 없이 눌렸다.
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ChatIconButton(label: "검색 닫기", action: onClose) {
                BackArrowIcon()
            }
            Spacer().frame(width: MoyeotaSpacing.Xxs)
            ZStack(alignment: .leading) {
                BasicTextField(
                    value: query,
                    onValueChange: { if $0.utf16.count <= 100 { onQueryChange($0) } }, // 서버 한도 1000자 — 검색어로는 100자면 넉넉하다
                    textStyle: MoyeotaType.BodyMd.copy(color: MoyeotaColor.InkPrimary),
                    keyboardOptions: KeyboardOptions(imeAction: .search),
                    keyboardActions: KeyboardActions(onSearch: { focus.freeFocus() }),
                    singleLine: true,
                    focusRequester: focus
                )
                if query.isEmpty {
                    Text("대화 내용 검색")
                        .moyeotaText(.BodyMd, color: MoyeotaColor.TextPlaceholder)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, MoyeotaSpacing.Md)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(MoyeotaColor.SurfaceSoft, in: MoyeotaShape.Pill)
            if !query.isEmpty {
                Spacer().frame(width: MoyeotaSpacing.Xxs)
                // 48 터치 + 눌림 표시(G12) — 글자 크기대로만 눌리던 링크
                TextLinkButton(text: "지우기", onClick: { onQueryChange("") })
            }
        }
        .padding(.leading, MoyeotaSpacing.Xxs)
        .padding(.trailing, MoyeotaSpacing.ScreenGutter)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .task { focus.requestFocus() }
    }
}

/// 결과 목록. 네 가지 상태를 문구로 구분한다 — 안 물어봄(짧은 검색어) / 찾는 중 / 없음 / 실패.
/// 결과는 서버 순서 그대로(최신 → 과거). 말풍선이 아니라 한 줄 카드다 — 누가·언제·무엇을 한눈에 훑는 용도라
/// 대화 레이아웃(좌우 정렬)을 그대로 쓰면 오히려 읽기 어렵다.
private struct SearchResults: View {
    let search: ChatSearchUi
    let onRetry: () -> Void
    let onLoadMore: () -> Void

    var body: some View {
        let results = search.results
        let keyword = search.query.trim()
        ZStack {
            if let errorMessage = search.errorMessage, results?.isEmpty ?? true {
                ErrorBox(message: errorMessage, onRetry: onRetry)
            } else if search.loading, results == nil {
                LoadingBox()
            } else if keyword.utf16.count < SEARCH_MIN_LENGTH {
                SearchHint(text: "검색어를 \(SEARCH_MIN_LENGTH)글자 이상 입력해 주세요")
            } else if let results, results.isEmpty {
                SearchHint(text: "「\(keyword)」에 맞는 메시지가 없어요")
            } else if let results {
                resultList(results: results, keyword: keyword)
            }
        }
    }

    private func resultList(results: [ChatUiMessage], keyword: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 문자열로 넘긴다 — `SectionLabel` 은 받은 글을 그대로 그린다(구분 기호 없이, `searchResultCountLabel` 주석)
                SectionLabel(text: searchResultCountLabel(count: results.count, hasMore: search.hasMore))
                // 흰 바탕 위 줄 목록 — 흰 카드를 줄마다 띄우지 않고 얇은 선으로 나눈다(C1 의 채팅 목록과 같은 방침)
                ForEach(Array(results.enumerated()), id: \.offset) { index, message in
                    if index > 0 { HorizontalDivider(color: MoyeotaColor.Hairline) }
                    SearchResultRow(message: message, keyword: keyword)
                }
                if let errorMessage = search.errorMessage {
                    NoticeBanner(kind: .error, text: errorMessage)
                        .padding(.vertical, MoyeotaSpacing.Xs)
                }
                if search.hasMore {
                    TextLinkButton(
                        text: search.loadingMore ? "불러오는 중…" : "이전 결과 더 보기",
                        onClick: onLoadMore,
                        enabled: !search.loadingMore
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            .padding(.vertical, MoyeotaSpacing.Sm)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // 원본 `verticalScroll` 은 키보드를 건드리지 않는다. 내려가면 하단탭이 다시 나타나 드래그 중에 레이아웃이 밀린다.
        .scrollDismissesKeyboard(.never)
    }
}

/// 결과 수 표기. `Text` 에 문자열 리터럴로 숫자를 끼우면 로케일 구분 기호가 붙어(「1,000개」) 원본 문구와 달라진다 —
/// 여기서 만든 문자열을 그대로(`String` 으로) 넘겨 그린다.
func searchResultCountLabel(count: Int, hasMore: Bool) -> String {
    "검색 결과 \(count)개\(hasMore ? " 이상" : "")"
}

private struct SearchHint: View {
    let text: String

    var body: some View {
        Text(text)
            .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextMute)
            .padding(MoyeotaSpacing.Lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SearchResultRow: View {
    let message: ChatUiMessage
    let keyword: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text(message.isMine ? "나" : (message.senderName ?? "동승자"))
                    .moyeotaText(
                        MoyeotaType.CaptionMd.copy(fontWeight: .semibold).hangulTrimmed,
                        color: message.isMine ? MoyeotaColor.Primary600 : MoyeotaColor.TextBody
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let timeLabel = message.timeLabel {
                    Text(timeLabel)
                        .moyeotaText(MoyeotaType.CaptionSm.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .fixedSize()
                }
            }
            Spacer().frame(height: MoyeotaSpacing.Xxs)
            Text(highlightKeyword(text: message.text, keyword: keyword))
                .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding(.vertical, MoyeotaSpacing.Sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 본문에서 검색어와 겹치는 구간 전부를 세미볼드·파랗게(Bold 는 버튼·디스플레이 전용 — G3). 대소문자를 가리지 않는다(서버 LIKE 도 그렇다)
func highlightKeyword(text: String, keyword: String) -> AttributedString {
    var attributed = AttributedString(text)
    let units = text.utf16
    for range in keywordRanges(text: text, keyword: keyword) {
        let start = units.index(units.startIndex, offsetBy: range.lowerBound)
        let end = units.index(units.startIndex, offsetBy: range.upperBound + 1)
        guard let lower = AttributedString.Index(start, within: attributed),
              let upper = AttributedString.Index(end, within: attributed)
        else { continue }
        attributed[lower..<upper].foregroundColor = MoyeotaColor.Primary600
        // 본문(`BodyMd`) 크기 그대로 굵기만 올린다
        attributed[lower..<upper].font = MoyeotaType.BodyMd.copy(fontWeight: .semibold).font
    }
    return attributed
}

/// `text` 안에서 `keyword` 가 나오는 모든 구간(UTF-16 칸, 양 끝 포함 — 원본 `IntRange`).
/// 겹치지 않게 앞에서부터 찾는다. 빈 검색어면 없음
func keywordRanges(text: String, keyword: String) -> [ClosedRange<Int>] {
    let haystack = Array(text.utf16)
    let needle = Array(keyword.utf16)
    if needle.isEmpty { return [] }
    var ranges: [ClosedRange<Int>] = []
    var from = 0
    while from + needle.count <= haystack.count {
        let matches = (0..<needle.count).allSatisfy { equalsIgnoringCase(haystack[from + $0], needle[$0]) }
        if matches {
            ranges.append(from...(from + needle.count - 1))
            from += needle.count
        } else {
            from += 1
        }
    }
    return ranges
}

/// `String.regionMatches(ignoreCase = true)` 의 한 칸 비교 — 대문자로 맞춰 보고, 안 되면 소문자로 한 번 더 본다.
private func equalsIgnoringCase(_ a: UInt16, _ b: UInt16) -> Bool {
    if a == b { return true }
    let upperA = simpleCase(a) { $0.properties.uppercaseMapping }
    let upperB = simpleCase(b) { $0.properties.uppercaseMapping }
    if upperA == upperB { return true }
    return simpleCase(upperA) { $0.properties.lowercaseMapping } == simpleCase(upperB) { $0.properties.lowercaseMapping }
}

/// 자바 `Character.toUpperCase(char)` 처럼 한 칸으로 매핑되는 경우만 바꾼다(`ß` → `SS` 같은 확장은 그대로 둔다).
private func simpleCase(_ unit: UInt16, _ mapping: (Unicode.Scalar) -> String) -> UInt16 {
    guard let scalar = Unicode.Scalar(unit) else { return unit }
    let mapped = Array(mapping(scalar).utf16)
    return mapped.count == 1 ? mapped[0] : unit
}

// ─── 아이콘 (Canvas 직접 드로잉) ─────────────────────────────────────────────

/// 전송 화살표(위쪽) — 공용 아이콘 세트에 같은 모양이 없어 여기 남긴다. 24 격자 · 선 굵기는 공용
/// 아이콘과 같은 `IconStrokeWidth`(G10). VoiceOver 이름은 감싸는 버튼이 준다.
private struct SendArrowIcon: View {
    var tint: Color = MoyeotaColor.TextOnDark

    var body: some View {
        let tint = tint
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.8))
            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.2))
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.2))
            path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.45))
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.2))
            path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.45))
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: IconStrokeWidth, lineCap: .round))
        }
        .frame(width: MoyeotaIconSize.Lg, height: MoyeotaIconSize.Lg)
        .accessibilityHidden(true)
    }
}
