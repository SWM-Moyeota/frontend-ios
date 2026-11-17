/// 정산 한 건의 상태 — 서버 `FareSplitStatus` 의 세 값과 1:1 이다.
///
/// 세 값이 화면에 주는 뜻이 다르다:
///
/// | 값 | 서버가 그렇게 둔 조건 | 화면이 할 수 있는 일 |
/// |---|---|---|
/// | `open` | 시작한 뒤 아직 안 닫힘 | 전부 — 보냈어요·받았어요·수정. **계좌번호가 있는 유일한 상태**다 |
/// | `completed` | 모든 송금이 CONFIRMED | 없다. 서버가 계좌번호를 **지웠다**(`FareSplit.close`) |
/// | `expired` | 시작한 지 **1일** 지남(`FareSplit.EXPIRES_AFTER`) | 없다. 계좌번호도 지워졌다 |
///
/// `completed` 와 `expired` 를 「닫힘」 하나로 접지 않는다 — 앞은 **돈이 다 건너갔다**는 뜻이고
/// 뒤는 **아무도 보내지 않은 채로 시간이 다 됐을 수도 있다**는 뜻이다. 둘을 같은 문구로 뭉개면
/// 만료된 정산을 본 사람이 「정산이 끝났다」로 읽고 자기 몫을 영영 보내지 않는다
/// (서버에 정산을 다시 시작하는 길은 없다 — 방마다 정산은 하나뿐이다).
///
/// 모르는 문자열은 `open` 으로 떨어진다 — 근거는 `FareSplitMappers` 의 `toFareSplitStatus` 에 적어 두었다.
/// raw value 는 Kotlin `enum.name` 자리일 뿐이다 — 서버 문자열을 `init(rawValue:)` 로 읽지 말 것
/// (그러면 모르는 값이 nil 이 되어 위 떨어뜨림 규칙이 매퍼 밖으로 샌다).
public enum FareSplitStatus: String, CaseIterable, Sendable {
    case open = "OPEN"
    case completed = "COMPLETED"
    case expired = "EXPIRED"

    /// Kotlin `enum.name` — 원본 상수 이름 그대로.
    public var name: String { rawValue }
}

/// 이 정산에서 **내** 역할 — 서버 `FareSplitRole` 과 1:1 이고 **토큰 기준**이다.
///
/// **같은 방의 두 사람이 같은 응답을 받지 않는다.** 서버는 `myRole`·`myAmount` 를 보는 사람에 맞춰
/// 계산하고(`FareSplitDetail.myAmount`), `FareSplitTransfer.maskedRealName` 과
/// `FareSplitDetail.tossDeeplink` 도 역할에 따라 실었다 뺀다. 그래서 한 사람이 받은 상세를
/// 다른 사람의 화면 상태로 재사용하면 안 된다(캐시를 방 단위로 두지 말고 **사람+방** 단위로 둘 것).
///
/// 모르는 문자열은 `sender` 로 떨어진다 — 근거는 `FareSplitMappers` 의 `toFareSplitRole` 에 적어 두었다.
public enum FareSplitRole: String, CaseIterable, Sendable {
    /// 택시비를 다 내고 **받는** 사람(= 방장). 수정·받았어요·못 받았어요를 할 수 있다.
    case payer = "PAYER"

    /// 자기 몫을 **보내는** 사람. 보냈어요 하나만 할 수 있다.
    case sender = "SENDER"

    /// Kotlin `enum.name` — 원본 상수 이름 그대로.
    public var name: String { rawValue }
}

/// 송금 한 건의 상태 — 서버 `TransferStatus` 와 1:1. 서버는 이 값을 저장하지 않고
/// `sentAt`·`confirmedAt` 두 시각에서 **셈해서** 내려 준다(`TransferStatus.of`).
///
/// ```
/// NOT_SENT ──보내는 사람이 「보냈어요」──▶ SENT ──받는 사람이 「받았어요」──▶ CONFIRMED
///     ▲                                    │
///     └────받는 사람이 「못 받았어요」────────┘
/// ```
///
/// **`sent` 를 건너뛸 수 있다.** 받는 사람은 `notSent` 인 송금도 바로 확인할 수 있다(현금으로 받은
/// 경우 — 서버 주석). 그래서 화면은 「SENT 를 거치지 않은 CONFIRMED」를 이상 상태로 보면 안 된다.
///
/// 모르는 문자열은 `notSent` 로 떨어진다 — 근거는 `FareSplitMappers` 의 `toTransferStatus` 에 적어 두었다.
/// `name` 은 서버 전송 값이기도 하다 — 내 정산 목록의 `status` 쿼리가 이 이름을 그대로 싣는다.
public enum TransferStatus: String, CaseIterable, Sendable {
    case notSent = "NOT_SENT"
    case sent = "SENT"
    case confirmed = "CONFIRMED"

    /// Kotlin `enum.name` — 원본 상수 이름 그대로. 서버 전송 값이다.
    public var name: String { rawValue }
}

/// 받을 계좌의 은행 — **은행 선택 목록을 앱이 들고 있어야 해서** 도메인에 둔다(서버에 은행 목록
/// 조회 API 가 없다). 서버 `Bank` 22종과 이름·순서가 같다.
///
/// ### 이 enum 은 「고르는 쪽」 전용이다 — 「받는 쪽」은 `FareSplitBank` 다
/// 서버는 받은 정산의 은행을 `bank: {code, name}` 으로 **이름까지 함께** 준다. 즉 **보여 줄 이름의
/// 출처는 서버**이고, 이 enum 의 `displayName` 은 사용자가 아직 고르지 않은 은행을 **목록에 그릴 때**만
/// 쓰인다. 그래서 서버가 23번째 은행을 추가해도 그 정산의 상세는 **정상으로 보인다** — 이름이 응답에
/// 실려 오기 때문이다. 못 하는 일은 「새 은행을 목록에서 고르는 것」 하나뿐이고, 그건 앱을 업데이트하면
/// 풀린다.
///
/// ### 모르는 코드를 무엇으로 읽나 — 틀렸을 때의 대가가 비대칭이다
///
/// | 모르는 코드를 … | 아는 은행을 틀리게 읽으면 | 모르는 은행을 틀리게 읽으면 |
/// |---|---|---|
/// | **거절(파싱 예외)** | — | 정산 상세가 **통째로 안 열린다**. 계좌번호·금액·송금 목록을 전부 못 보고, 앱 업데이트 전까지 그 방의 정산은 영구히 닫힌다 |
/// | **아무 은행으로 떨어뜨림**(예: `kb`) | — | 화면이 **틀린 은행 이름**을 띄운다. 사용자가 그 이름을 믿고 엉뚱한 은행으로 송금하면 **되돌릴 수 없다**(앱이 옮긴 돈이 아니라 사용자가 직접 옮긴 돈이다) |
/// | **코드 그대로 + 서버 이름 표시**(지금) | — | 선택 목록에만 없다. 읽기는 전부 정상이고, 기존 정산을 고쳐도 코드가 그대로 돌아간다(`FareSplitDraft.bankCode`) |
///
/// 셋째가 **되돌릴 수 없는 실패를 하나도 들여오지 않는** 유일한 선택이다. 그래서 이 enum 은
/// 「알아보면 채워지는 부가 정보」(`FareSplitBank.known`)이고, 모르는 코드는 버리지 않는다.
public enum Bank: String, CaseIterable, Sendable {
    case kb = "KB"
    case shinhan = "SHINHAN"
    case woori = "WOORI"
    case hana = "HANA"
    case nh = "NH"
    case ibk = "IBK"
    case kakao = "KAKAO"
    case toss = "TOSS"
    case kBank = "K_BANK"
    case sc = "SC"
    case citi = "CITI"
    case post = "POST"
    case saemaul = "SAEMAUL"
    case suhyup = "SUHYUP"
    case busan = "BUSAN"
    case daegu = "DAEGU"
    case gwangju = "GWANGJU"
    case jeonbuk = "JEONBUK"
    case gyeongnam = "GYEONGNAM"
    case jeju = "JEJU"
    case shinhyup = "SHINHYUP"
    case kdb = "KDB"

    /// 목록에 그릴 이름 — 서버 `Bank.displayName` 과 같은 값이다(토스 전용 표기 `tossName` 이 아니다).
    public var displayName: String {
        switch self {
        case .kb: "KB국민은행"
        case .shinhan: "신한은행"
        case .woori: "우리은행"
        case .hana: "하나은행"
        case .nh: "NH농협은행"
        case .ibk: "IBK기업은행"
        case .kakao: "카카오뱅크"
        case .toss: "토스뱅크"
        case .kBank: "케이뱅크"
        case .sc: "SC제일은행"
        case .citi: "한국씨티은행"
        case .post: "우체국"
        case .saemaul: "새마을금고"
        case .suhyup: "Sh수협은행"
        case .busan: "부산은행"
        case .daegu: "iM뱅크(대구은행)"
        case .gwangju: "광주은행"
        case .jeonbuk: "전북은행"
        case .gyeongnam: "경남은행"
        case .jeju: "제주은행"
        case .shinhyup: "신협"
        case .kdb: "KDB산업은행"
        }
    }

    /// 서버에 보낼 코드. **서버 enum 이름과 같은 값**이다 — 서버가 `Bank` enum 을 그대로 역직렬화하므로
    /// (`FareSplitRequest.bankCode` 가 `Bank` 타입이다) 이름이 어긋나면 400 `INVALID_REQUEST` 다.
    ///
    /// 프로퍼티로 따로 두는 이유는 **보내는 쪽이 raw value 를 직접 읽지 않게** 하는 것이다. 보내는 자리가
    /// 「코드를 보낸다」고 이름으로 말해야, 「표시 이름을 보내는」 실수(`displayName` 과 나란히 자동 완성된다)가
    /// 리뷰에서 눈에 띈다.
    public var code: String { rawValue }

    /// 코드 문자열 → 아는 은행. 모르면 nil 이다 — nil 을 아무 은행으로 메우지 말 것(위 표).
    public static func ofCodeOrNull(code: String?) -> Bank? {
        code.flatMap { raw in allCases.first { $0.rawValue == raw } }
    }
}

/// 받을 계좌의 은행 — 서버가 준 `bank: {code, name}` 을 그대로 들고 있는다.
///
/// `displayName` 이 **보여 줄 이름의 단일 출처**다. `known` 이 nil 이어도(서버가 추가한 새 은행)
/// 이름은 서버가 알려 줬으므로 화면은 그대로 쓰면 된다.
public struct FareSplitBank: Hashable, Sendable {
    /// 서버 `Bank` enum 이름. 정산을 고칠 때 **이 값을 그대로 돌려보낸다**(`FareSplitDraft.bankCode`).
    public var code: String
    /// 서버가 준 사람이 읽을 이름(「카카오뱅크」). 서버가 비워 보냈으면 `known` 의 이름으로, 그마저 없으면
    /// `code` 로 떨어진다 — 빈 문자열이면 서버가 은행을 설명하지 못한 것이다.
    public var displayName: String
    /// 22종 중 알아본 은행. **모르는 코드면 nil** 이고, 그건 「서버가 은행을 추가했다」는 뜻이다(오류가
    /// 아니다). 선택 목록의 현재 선택을 표시할 때만 읽는다.
    public var known: Bank?

    public init(code: String, displayName: String, known: Bank?) {
        self.code = code
        self.displayName = displayName
        self.known = known
    }
}

/// 정산에 등장하는 사람 한 명(받는 사람). 서버 `FareSplitDetailResponse.FareSplitPayer` 와 짝이다.
///
/// 서버가 `MemberSummary` 를 못 찾으면 publicId·nickname 을 **함께** null 로 내린다
/// (`payer == null ? null : ...`). 그때 `publicId` 는 **빈 문자열**(`User.id` 와 같은 관례)이고
/// `nickname` 은 `WithdrawnMemberNames.NO_SUMMARY` 다(`PartyMappers` 의 `toUser` 와 같은 문자열을 쓴다 —
/// 두 곳이 갈리면 「사람 이름이 아닌 것」을 거르는 화면 쪽 검사가 한쪽을 못 걸러
/// 「탈퇴한 회원님께 보내세요」가 된다).
///
/// 설명이 있는지는 `isIdentified` **하나로만** 묻는다 — 닉네임 문자열로 판정하지 말 것
/// (서버가 직접 넣는 `WithdrawnMemberNames.SERVER_DELETED` 는 **publicId 가 살아 있다**).
public struct FareSplitParticipant: Hashable, Sendable {
    public var publicId: String
    public var nickname: String

    public init(publicId: String, nickname: String) {
        self.publicId = publicId
        self.nickname = nickname
    }

    /// 서버가 이 사람을 설명해 줬는가. false 면 프로필로 넘길 수 없다(갈 대상이 없다).
    public var isIdentified: Bool { !publicId.isEmpty }
}

/// 보내는 사람 한 명의 송금 — 서버 `FareSplitDetailResponse.FareSplitTransferItem` 과 짝이다.
/// 목록 순서는 **방 합류 순**이고(서버가 `joinOrder` 로 정렬해 내려 준다) 앱이 다시 정렬하지 않는다.
///
/// **받는 사람(PAYER)의 행은 여기 없다.** 서버가 `senderTransfers()` 로 뺀다. 그래서 목록 크기는
/// 탑승자 수 - 1 이고, 받는 사람의 부담 금액은 `FareSplitDetail.myAmount` 로만 보인다
/// (받는 사람이 자기 화면을 볼 때).
public struct FareSplitTransfer: Hashable, Sendable {
    /// 보내는 사람의 publicId — 「받았어요」·「못 받았어요」의 **경로 변수**다
    /// (`FareSplitRepository.confirmReceived`).
    ///
    /// **빈 문자열일 수 있다**(서버가 유저 요약을 못 찾은 경우). 그러면 그 행은 **확인할 수 없다** —
    /// 부를 수 있는 id 가 없고, 지어내면 404 `FARE_SPLIT_TRANSFER_NOT_FOUND` 다. 화면은
    /// `isConfirmable` 로 버튼을 잠가야 한다. 잠그지 않으면 「받았어요」가 영구히 실패하는 행이
    /// 생기고, **그 행 하나 때문에 정산이 COMPLETED 로 닫히지 않는다**(서버는 전원 CONFIRMED 를 본다).
    public var senderPublicId: String
    /// 보내는 사람 닉네임. 서버가 설명하지 못하면 `WithdrawnMemberNames.NO_SUMMARY` 이고, 탈퇴한
    /// 사용자면 서버가 `WithdrawnMemberNames.SERVER_DELETED` 를 직접 넣는다 — **두 경우를 하나로
    /// 접지 말 것**(`FareSplitParticipant` 와 같은 관례. 뒤쪽은 `senderPublicId` 가 살아 있어
    /// 「받았어요」를 부를 수 있다).
    public var nickname: String
    /// 이 사람이 보낼 금액(원).
    public var amount: Int
    public var status: TransferStatus
    /// 「보냈어요」를 누른 시각(ISO-8601 문자열 그대로). 아직 안 눌렀으면 nil.
    public var sentAt: String?
    /// 받는 사람이 확인한 시각(ISO-8601 문자열 그대로). 아직 확인 전이면 nil.
    public var confirmedAt: String?
    /// 가린 실명(「홍*동」) — **받는 사람(PAYER)이 볼 때만 있다.** 보내는 사람에게는 **늘 nil** 이다
    /// (서버가 `isPayer(viewer)` 일 때만 채운다).
    ///
    /// 쓰임은 하나다: 받는 사람이 **은행 앱 입금자명과 대조**하는 것. 그래서 nil 을
    /// 「실명이 없는 사용자」로 읽지 말 것 — 보내는 사람 화면에서는 nil 이 정상이고,
    /// 그 화면에는 이 값을 쓸 자리가 아예 없다.
    public var maskedRealName: String?

    public init(
        senderPublicId: String,
        nickname: String,
        amount: Int,
        status: TransferStatus,
        sentAt: String?,
        confirmedAt: String?,
        maskedRealName: String?
    ) {
        self.senderPublicId = senderPublicId
        self.nickname = nickname
        self.amount = amount
        self.status = status
        self.sentAt = sentAt
        self.confirmedAt = confirmedAt
        self.maskedRealName = maskedRealName
    }

    /// 「받았어요」·「못 받았어요」를 **부를 수 있는 행인가**. `senderPublicId` 가 비어 있으면 false 다.
    /// 역할·상태 판정은 들어 있지 않다 — 그건 `FareSplitDetail` 쪽 일이다.
    public var isConfirmable: Bool { !senderPublicId.isEmpty }
}

/// 정산 상세 — 7개 엔드포인트 중 **셋(시작·조회·수정)이 모두 이 모양**을 준다.
///
/// ### 보는 사람에 따라 내용이 다르다
/// `myRole`·`myAmount`·`tossDeeplink`·`FareSplitTransfer.maskedRealName` 이 **토큰 기준**이다
/// (`FareSplitRole` 참고). 한 사람의 상세를 다른 사람 화면에 재사용하면 안 된다.
///
/// ### nil 세 자리가 화면에 주는 뜻 — 전부 「오류」가 아니다
///
/// | 자리 | nil 인 조건 | 화면이 할 일 |
/// |---|---|---|
/// | `accountNumber` | 정산이 닫혔다(COMPLETED·EXPIRED) **또는 받는 사람이 탈퇴했다**(아래) | 계좌 영역을 숨긴다. 「불러오지 못했어요」가 아니다 |
/// | `tossDeeplink` | 내가 PAYER 거나, 정산이 닫혔거나, 계좌번호가 사라졌다 | 토스 버튼을 **띄우지 않는다**(만들어 끼우지도 말 것) |
/// | `FareSplitTransfer.maskedRealName` | 내가 SENDER 다 | 입금자명 대조 칸이 없는 화면이다 |
///
/// ### **`isOpen` 이 true 라도 `accountNumber` 가 nil 일 수 있다**
/// 받는 사람이 탈퇴하면 서버가 **그 즉시** 열린 정산의 계좌번호를 지운다
/// (`FareSplitUserDeletionListener` → `forgetPayerAccounts`) — **상태는 OPEN 그대로**다. 그래서
/// 「OPEN 이면 보낼 계좌가 있다」로 코드를 짜면 그 방에서 강제 언래핑이 터지거나, 반대로 「계좌가
/// 없으면 끝난 정산」으로 읽어 **아직 보낼 돈이 남은 사람에게 「정산이 끝났어요」를 보여 준다**
/// (서버는 그 송금을 계속 NOT_SENT 로 세고 4시간마다 재요청 알림을 보낸다). 두 사실을 따로 본다.
///
/// ### 내 송금 상태는 **`myTransferStatus` 로 직접 온다**
/// 한동안 오지 않았다. 그때는 보내는 사람이 「내가 이미 보냈다고 눌렀나」를 알려면 `transfers` 에서
/// 자기 publicId 로 자기 행을 찾아야 했고(`transferOf`), 서버가 그 사람을 설명하지 못한 응답에서는
/// **알 길이 없었다.** Backend PR #328 이 그 구멍을 메웠다.
///
/// `transferOf` 는 남아 있다 — **받는 사람 화면이 보내는 사람별 행을 다루는 데 쓴다**(「받았어요」를
/// 누를 대상을 고르는 자리). 「내 상태」를 묻는 데 쓰지 마라.
public struct FareSplitDetail: Hashable, Sendable {
    /// 방 id. **이후 모든 호출의 경로 변수**다(받았어요·보냈어요·수정 전부 `rooms/{partyId}` 아래다).
    /// 서버가 말해 주지 않으면 매퍼가 **요청에 쓴 partyId** 로 채운다 — 0 으로 접으면 다음 호출이
    /// 엉뚱한 방으로 간다(`FareSplitMappers` 의 `toFareSplitDetail`).
    public var partyId: Int64
    public var status: FareSplitStatus
    /// 실제로 낸 택시비(원). `transfers` 의 금액과 `myAmount` 를 합치면 이 값이 된다.
    public var totalFare: Int
    /// 택시비를 다 내고 받는 사람(= 방장).
    public var payer: FareSplitParticipant
    public var myRole: FareSplitRole
    /// 내 부담 금액(원). SENDER 면 **내가 보낼 금액**, PAYER 면 **내가 부담한 몫**이다 — 뜻이 다르다.
    public var myAmount: Int
    /// 내 송금 상태. **`FareSplitRole.sender` 일 때만 있고 `FareSplitRole.payer` 는 nil** 이다 —
    /// 받는 사람은 보낼 것이 없다(서버 `FareSplit.transferStatusOf` 가 빈 값을 준다).
    ///
    /// ⚠️ **nil 을 `TransferStatus.notSent` 로 접지 마라.** 받는 사람의 nil 을 「아직 안 보냈다」로
    /// 읽으면 방장 화면에 「보냈어요」가 뜨고, 누르면 403 `NOT_FARE_SPLIT_SENDER` 다.
    /// 「보냈어요」 버튼의 조건은 `canMarkSent` 하나로 묶어 두었다.
    public var myTransferStatus: TransferStatus?
    public var bank: FareSplitBank
    /// 받을 계좌번호(숫자만). **OPEN 일 때만 있다** — 위 표 참고.
    public var accountNumber: String?
    /// 토스 송금 딥링크(`supertoss://send?amount=&bank=&accountNo=`) — **서버가 만들어 준다.**
    /// SENDER + OPEN 일 때만 있다.
    ///
    /// **앱이 조립하지 마라.** 규격이 서버 쪽에 있고(`TossDeeplink`), 은행 이름도 토스 전용 표기
    /// (`tossName`: 「KB국민」)라 `Bank.displayName` 과 다르다 — 앱이 베끼면 두 표기가 갈린다.
    ///
    /// **열리지 않는 것을 전제한 값이다.** 서버 주석 원문: 「비공식 규격이라 열리지 않을 수 있어
    /// 계좌·금액 복사 버튼을 함께 둔다」. 그래서 이 모델은 같은 사실을 **딥링크와 복사 거리
    /// 두 경로로** 들고 있다(`manualTransfer`) — 딥링크가 실패했을 때 화면이 서버를 다시 부르지
    /// 않고 손으로 옮길 수 있어야 한다.
    public var tossDeeplink: String?
    /// 보내는 사람별 송금, **방 합류 순**. 받는 사람의 행은 빠져 있다(`FareSplitTransfer`).
    public var transfers: [FareSplitTransfer]
    /// 정산을 시작한 시각(ISO-8601 문자열 그대로). 서버가 말해 주지 않으면 nil.
    public var createdAt: String?
    /// 닫힌 시각(ISO-8601 문자열 그대로). `FareSplitStatus.open` 이면 nil.
    public var closedAt: String?

    public init(
        partyId: Int64,
        status: FareSplitStatus,
        totalFare: Int,
        payer: FareSplitParticipant,
        myRole: FareSplitRole,
        myAmount: Int,
        myTransferStatus: TransferStatus?,
        bank: FareSplitBank,
        accountNumber: String?,
        tossDeeplink: String?,
        transfers: [FareSplitTransfer],
        createdAt: String?,
        closedAt: String?
    ) {
        self.partyId = partyId
        self.status = status
        self.totalFare = totalFare
        self.payer = payer
        self.myRole = myRole
        self.myAmount = myAmount
        self.myTransferStatus = myTransferStatus
        self.bank = bank
        self.accountNumber = accountNumber
        self.tossDeeplink = tossDeeplink
        self.transfers = transfers
        self.createdAt = createdAt
        self.closedAt = closedAt
    }

    /// 진행 중인가. **계좌번호·딥링크·모든 동작이 이 값에 묶여 있다**(닫히면 서버가 409 로 막는다).
    public var isOpen: Bool { status == .open }

    /// 내가 받는 사람인가. 수정·받았어요·못 받았어요가 여기에 묶인다.
    public var isPayer: Bool { myRole == .payer }

    /// 내가 보내는 사람인가. 보냈어요가 여기에 묶인다.
    public var isSender: Bool { myRole == .sender }

    /// **지금 고칠 수 있는가** — 서버 `FareSplit.validateNotStarted` 와 같은 조건이다
    /// (받는 사람 + 진행 중 + 보내는 사람 **전원이 아직 NOT_SENT**).
    ///
    /// 앱이 미리 보는 이유는 **고칠 수 없는 버튼을 띄우지 않기 위해서**다. 누른 뒤 409
    /// `FARE_SPLIT_ALREADY_STARTED` 를 받으면, 사용자는 금액을 다 고쳐 넣은 뒤에 그게 버려지는 것을
    /// 본다. 다만 **서버가 최종 판정**이다 — 내가 상세를 받은 뒤 누군가 「보냈어요」를 누를 수 있으므로
    /// 이 값이 true 라도 409 는 여전히 올 수 있고, 그때는 상세를 다시 받아 화면을 고친다.
    public var canEdit: Bool {
        isPayer && isOpen && transfers.allSatisfy { $0.status == .notSent }
    }

    /// 토스가 열리지 않았을 때 **손으로 옮길 거리**. 계좌번호가 있을 때만(= OPEN) 채워진다.
    ///
    /// 보내는 사람 화면의 복사 버튼이 읽는 값이고, 받는 사람 화면에서는 「내가 적어 둔 계좌가 맞나」를
    /// 확인하는 데 쓴다 — 그래서 `myRole` 로 가리지 않는다. 금액은 `myAmount` 라
    /// **받는 사람에게는 자기 부담 몫**이 들어간다는 점만 주의할 것(보낼 금액이 아니다).
    public var manualTransfer: ManualTransfer? {
        accountNumber.map { ManualTransfer(bankDisplayName: bank.displayName, accountNumber: $0, amount: myAmount) }
    }

    /// **보낼 곳이 사라진 진행 중 정산인가** — 진행 중인데 계좌번호가 없다.
    ///
    /// 받는 사람이 탈퇴하면 서버가 열린 정산의 계좌번호만 지운다(이 타입 주석 참고). 그때
    /// 보내는 사람 화면은 「끝난 정산」도 「불러오기 실패」도 아니고 **「보낼 계좌가 없어졌다」**다 —
    /// 다시 받아도 계좌는 돌아오지 않으므로 재시도를 권하지 말고, 채팅으로 물어보게 안내한다.
    public var hasLostAccount: Bool { isOpen && accountNumber == nil }

    /// 「보냈어요」를 누를 수 있는가 — 진행 중이고 · 내가 보내는 사람이고 · **아직 안 보냈다.**
    ///
    /// 세 조건을 한 자리에 묶는 이유: 화면이 따로 세우면 `myTransferStatus` 가 nil 인 받는 사람을
    /// 「아직 안 보냈다」로 읽는 실수가 끼어든다. 그 버튼은 403 `NOT_FARE_SPLIT_SENDER` 로만 끝난다.
    ///
    /// 이미 `TransferStatus.sent` 면 **false 다.** 서버는 다시 눌러도 204 로 받아 주지만(멱등),
    /// 버튼을 열어 두면 사용자가 「안 눌렸나」 싶어 다시 누르고 **같은 화면이 반복**된다 — 보낸 뒤에는
    /// 버튼이 아니라 「보냈다고 알렸어요」라는 **상태**를 보여 주는 쪽이 맞다.
    public var canMarkSent: Bool {
        isOpen && myRole == .sender && myTransferStatus == .notSent
    }

    /// publicId 로 송금 한 건을 찾는다 — **받는 사람 화면이 보내는 사람별 행을 다루는 자리**다
    /// (「받았어요」·「못 받았어요」를 누를 대상을 고른다).
    ///
    /// ⚠️ **「내 송금 상태」를 묻는 데 쓰지 마라** — 그건 `myTransferStatus` 가 직접 준다.
    /// 이 함수로 찾으면 서버가 그 사람을 설명하지 못한 행(`senderPublicId` 가 빈 값)에서 nil 이 되어
    /// 「안 보냈다」와 「모른다」가 같은 모양이 된다.
    ///
    /// 받는 사람 자신에게는 늘 nil 이다(자기 행은 `transfers` 에서 빠져 있다) — 그게 정상이다.
    public func transferOf(publicId: String) -> FareSplitTransfer? {
        transfers.first { !$0.senderPublicId.isEmpty && $0.senderPublicId == publicId }
    }
}

/// 토스 딥링크가 열리지 않았을 때 손으로 옮길 거리 — **복사 버튼 세 개의 원본**이다.
///
/// 딥링크와 같은 사실을 **평문으로 한 번 더** 들고 있는 이유: 딥링크는 열어 보기 전까지 열릴지 알 수
/// 없고(비공식 규격), 실패한 뒤에 계좌번호를 구하려고 서버를 다시 부르면 그 사이 정산이 닫혀
/// `accountNumber` 가 nil 로 올 수 있다. 화면에 이미 떠 있던 계좌번호가 **버튼을 누른 뒤에 사라지는**
/// 것이 최악이라, 복사 거리는 상세를 받은 순간 함께 확정해 둔다.
public struct ManualTransfer: Hashable, Sendable {
    public var bankDisplayName: String
    /// 숫자만. 하이픈을 끼워 보여 주는 것은 화면의 자유지만 **복사되는 값은 숫자만**이어야 한다 —
    /// 은행 앱 붙여넣기 칸이 하이픈을 거절하는 경우가 있다.
    public var accountNumber: String
    public var amount: Int

    public init(bankDisplayName: String, accountNumber: String, amount: Int) {
        self.bankDisplayName = bankDisplayName
        self.accountNumber = accountNumber
        self.amount = amount
    }
}

/// 한 사람이 부담할 금액 — 서버 `FareSplitRequest.Payment` 와 짝이다.
public struct FareShare: Hashable, Sendable {
    /// 탑승자의 publicId. 서버가 이것으로 내부 id 를 찾으므로 틀리면
    /// 400 `PAYMENT_TARGET_MISMATCH` 다(없는 사람을 보냈을 때도 같은 코드다).
    public var riderPublicId: String
    /// 부담 금액(원). **1원 이상 정수**여야 한다(`FareSplitPolicy.MIN_SHARE`).
    public var amount: Int

    public init(riderPublicId: String, amount: Int) {
        self.riderPublicId = riderPublicId
        self.amount = amount
    }
}

/// 정산을 시작하거나 고칠 때 서버로 보낼 내용 — 시작(POST)과 수정(PATCH)이 **같은 모양**을 쓴다
/// (서버도 `FareSplitRequest` 하나다). 수정은 일부가 아니라 **전부** 다시 보낸다.
public struct FareSplitDraft: Hashable, Sendable {
    /// 실제로 낸 택시비(원). 1원 이상.
    public var totalFare: Int
    /// 은행 코드. 사용자가 목록에서 골랐으면 `Bank.code` 이고, **기존 정산을 고칠 때는
    /// `FareSplitBank.code` 를 그대로 되돌려 보낸다.**
    ///
    /// `Bank` 가 아니라 문자열인 이유가 그 둘째 경우다 — 서버가 23번째 은행을 추가하면 그 코드는
    /// 앱의 enum 에 없고(`FareSplitBank.known` 이 nil), 타입을 enum 으로 좁히면 **그 정산은 고칠 수
    /// 없어진다**(수정은 은행도 필수 필드다). 코드를 문자열로 들고 다니면 모르는 은행의 정산도
    /// 금액만 고쳐 그대로 되돌릴 수 있다.
    public var bankCode: String
    /// 받을 계좌번호. **사용자가 입력한 원문 그대로 담아도 된다** —
    /// 하이픈·공백 제거는 매퍼가 `FareSplitPolicy.normalizeAccountNumber` 로 한다
    /// (`FareSplitMappers` 의 `toRequestDto`). 화면이 잊어도 정규화된 값이 나가게 하려는 배치다.
    ///
    /// 보내기 전 판정은 `FareSplitPolicy.isAccountNumberValid` 로 한다 — 어기면 400
    /// `INVALID_ACCOUNT_NUMBER` 이고, 그 실패는 **금액을 다 채운 뒤에** 돌아온다.
    public var accountNumber: String
    /// 탑승자마다 부담 금액. **받는 사람(방장)을 포함한 탑승자 전원이 정확히 한 번씩** 있어야 하고
    /// 합이 `totalFare` 와 같아야 한다. 1/N 로 미리 채우는 일은 **앱의 책임**이다
    /// (`FareSplitPolicy.splitEvenly`).
    public var shares: [FareShare]

    public init(totalFare: Int, bankCode: String, accountNumber: String, shares: [FareShare]) {
        self.totalFare = totalFare
        self.bankCode = bankCode
        self.accountNumber = accountNumber
        self.shares = shares
    }
}

/// 홈 배너(「아직 보내지 않은 택시비」)의 한 줄 — 서버 `MyFareSplitListResponse.MyFareSplitItem` 과 짝.
///
/// 상세와 달리 **내가 보내는 사람인 정산만** 온다(받는 사람으로 시작한 정산은 나오지 않는다).
/// `status` 는 **내 송금 상태**이고, 조회할 때 고른 상태와 같다 — 서버가 그 값으로 걸러 주기 때문이다.
///
/// `partyId` 로 상세를 연다(`FareSplitRepository.getFareSplit`).
/// 그래서 **partyId 없는 줄은 매퍼가 버린다** — 눌러도 열 수 없는 줄이기 때문이다.
public struct MyFareSplit: Hashable, Sendable {
    public var partyId: Int64
    /// 출발지 이름. 서버가 방을 못 찾으면 nil 이다(방이 지워진 뒤에도 정산은 남는다).
    public var departure: String?
    /// 도착지 이름. `departure` 와 **함께** nil 이 된다(서버가 둘을 같은 조회로 채운다).
    public var destination: String?
    /// 받는 사람(= 그 방 방장).
    public var payer: FareSplitParticipant
    /// 내가 보낼 금액(원).
    public var myAmount: Int
    /// 내 송금 상태. 조회에 쓴 `TransferStatus` 와 같다.
    public var status: TransferStatus
    /// 정산을 시작한 시각(ISO-8601 문자열 그대로). 목록은 **이 값 최신순**으로 서버가 정렬해 준다.
    public var createdAt: String?

    public init(
        partyId: Int64,
        departure: String?,
        destination: String?,
        payer: FareSplitParticipant,
        myAmount: Int,
        status: TransferStatus,
        createdAt: String?
    ) {
        self.partyId = partyId
        self.departure = departure
        self.destination = destination
        self.payer = payer
        self.myAmount = myAmount
        self.status = status
        self.createdAt = createdAt
    }
}

/// 1/N 미리 채우기와 계좌번호 정규화 — **서버가 앱에 맡긴 두 가지**를 담은 순수 함수 묶음.
///
/// 서버 Swagger 원문: 「1/N 로 미리 채우는 것은 앱이 한다」. 즉 서버는 금액을 **검사만** 한다
/// (틀리면 400 `PAYMENT_TARGET_MISMATCH`·`PAYMENTS_NOT_EQUAL_FARE`). 나누는 규칙이 앱에 있으므로,
/// 그 규칙이 화면마다 다르면 **같은 택시비·같은 인원인데 사람마다 다른 금액**이 뜬다. 그래서
/// 규칙은 이 한 곳에만 둔다.
public enum FareSplitPolicy {

    /// 정산을 시작할 수 있는 최소 탑승자 수(받는 사람 포함). 미달이면 409 `NOT_ENOUGH_RIDERS`.
    public static let MIN_RIDERS = 2

    /// 한 사람 부담 금액의 최소값(원). 미달이면 400(서버 `FarePayment` 가 `amount <= 0` 을 거절한다).
    public static let MIN_SHARE = 1

    /// 택시비의 최소값(원). 미달이면 400 `INVALID_REQUEST`(서버 `@Positive`).
    public static let MIN_TOTAL_FARE = 1

    /// 계좌번호 자릿수 하한 — 서버 `AccountNumber.MIN_DIGITS`.
    public static let ACCOUNT_MIN_DIGITS = 10

    /// 계좌번호 자릿수 상한 — 서버 `AccountNumber.MAX_DIGITS`.
    public static let ACCOUNT_MAX_DIGITS = 16

    /// 1/N 로 나눌 수 있는가 — `splitEvenly` 를 부르기 전에 묻는다.
    ///
    /// 나눌 수 없는 경우는 **인원이 모자라거나**(< `MIN_RIDERS`) **택시비가 인원보다 적을 때**다.
    /// 뒤쪽이 핵심인데, 전원이 1원 이상이어야 하므로 3명에 2원은 어떻게 쪼개도 누군가 0원이 된다
    /// (서버가 400 으로 막는다). 실제 택시 기본요금에서는 일어나지 않지만 **사용자가 금액을 직접
    /// 입력하므로** 「2」를 넣을 수 있다 — 그때 앱이 터지지 않고 「택시비를 다시 확인해 주세요」로
    /// 끝내게 하는 것이 이 함수다.
    public static func canSplitEvenly(totalFare: Int, riderCount: Int) -> Bool {
        riderCount >= MIN_RIDERS && totalFare >= riderCount * MIN_SHARE
    }

    /// 택시비를 탑승자 수로 나눠 `FareShare` 목록을 만든다 — **1원 단위까지 결정론적**이다.
    ///
    /// ### 나누어떨어지지 않는 1원을 누가 내나 — **받는 사람(방장)이 흡수한다**
    ///
    /// ```
    /// 18,700원 / 3명  →  몫 6,233원, 나머지 1원
    ///   방장(받는 사람)  6,234원   ← 나머지를 전부 가져간다
    ///   보내는 사람 A    6,233원
    ///   보내는 사람 B    6,233원
    ///                   합 18,700원 = totalFare
    /// ```
    ///
    /// 이렇게 정한 근거는 셋이다.
    ///
    /// | 왜 | 설명 |
    /// |---|---|
    /// | **결정론** | 방장은 정산마다 **정확히 한 명**이다. 「목록 앞쪽부터 1원씩」으로 정하면 그 「앞쪽」이 서버의 방 합류 순에 묶이는데, 앱이 멤버 목록을 어디서 받았는지(상세·SSE·목록)에 따라 순서가 달라질 수 있다 — 같은 입력에 다른 결과가 나온다. 방장 기준은 **입력 순서와 무관**하다 |
    /// | **보내는 금액이 전원 같다** | 1원을 보내는 사람 중 한 명에게 얹으면 「왜 나만 1원 더 내나」를 설명할 수 없다. 받는 사람이 흡수하면 **요청받는 금액이 전원 동일**해져 분쟁할 거리가 없다 |
    /// | **틀렸을 때의 대가** | 받는 사람은 이미 전액을 낸 사람이고 1원을 더 부담해도 받을 돈이 1원 줄 뿐이다. 반대로 보내는 사람에게 얹으면 **요청 금액이 올라간다** — 돈을 더 달라고 하는 쪽이 덜 달라고 하는 쪽보다 나쁘다 |
    ///
    /// 나머지는 최대 `탑승자 수 - 1` 원이라(정수 나눗셈) 방장이 흡수하는 금액은 많아도 몇 원이다.
    ///
    /// - Parameters:
    ///   - payerPublicId: 받는 사람(방장)의 publicId. `riderPublicIds` 안에 있어야 한다 —
    ///     방장이 탑승자가 아니면 서버가 403 `NOT_A_RIDER` 로 정산 자체를 막는다.
    ///   - riderPublicIds: **탑승자 전원**(방장 포함, 서버 `riderIds`). 방 멤버 전원이 아니다 —
    ///     출발지 도착을 누른 사람만이다(`Ride.fareSplitRiders`).
    /// - Returns: `riderPublicIds` 와 **같은 순서**의 목록. 순서는 서버가 보지 않지만(집합으로 검사한다)
    ///   화면이 그대로 그릴 수 있게 보존한다.
    /// - Throws: `IllegalArgumentException` — 탑승자가 모자라거나 중복·빈 id 가 섞였거나 택시비가 인원보다
    ///   적을 때(Kotlin `require` 의 자리). 부르기 전에 `canSplitEvenly` 로 묻는다 — 이 예외는 **화면의
    ///   버그**를 잡는 장치이고 사용자 입력을 거르는 수단이 아니다.
    public static func splitEvenly(totalFare: Int, payerPublicId: String, riderPublicIds: [String]) throws -> [FareShare] {
        guard riderPublicIds.count >= MIN_RIDERS else {
            throw IllegalArgumentException("탑승자가 \(riderPublicIds.count)명이라 나눌 수 없다(최소 \(MIN_RIDERS) 명)")
        }
        guard !riderPublicIds.contains(where: \.isEmpty) else {
            throw IllegalArgumentException("publicId 가 빈 탑승자가 있다 — 서버가 설명하지 못한 멤버는 정산 대상으로 지목할 수 없다")
        }
        guard Set(riderPublicIds).count == riderPublicIds.count else {
            throw IllegalArgumentException("탑승자 publicId 가 중복됐다 — 서버가 400 PAYMENT_TARGET_MISMATCH 로 막는다")
        }
        guard riderPublicIds.contains(payerPublicId) else {
            throw IllegalArgumentException("받는 사람이 탑승자 목록에 없다 — 서버가 403 NOT_A_RIDER 로 막는다")
        }
        guard canSplitEvenly(totalFare: totalFare, riderCount: riderPublicIds.count) else {
            throw IllegalArgumentException("택시비 \(totalFare)원을 \(riderPublicIds.count)명이 1원 이상씩 나눌 수 없다")
        }

        let base = totalFare / riderPublicIds.count
        let remainder = totalFare - base * riderPublicIds.count

        return riderPublicIds.map { riderId in
            FareShare(riderPublicId: riderId, amount: riderId == payerPublicId ? base + remainder : base)
        }
    }

    /// 사용자가 넣은 계좌번호에서 **하이픈과 공백만** 떼어 낸다 — 서버 `AccountNumber.of` 와 같은 규칙이다.
    ///
    /// ### 숫자 아닌 문자를 전부 지우지 않는 이유
    /// 그렇게 하면 「3333.01.2345678」·「3333012345678(국민)」 같은 입력이 **조용히 통과**한다. 돈이
    /// 건너가는 자리에서 앱이 사용자가 확인하지 않은 문자열을 만들어 내는 것은, 틀렸다고 말해 주는
    /// 것보다 나쁘다 — 송금은 앱이 아니라 사용자가 직접 하므로 **앱이 고친 값이 틀려도 되돌릴 수 없다.**
    /// 하이픈·공백만 떼는 것은 그 둘이 **은행 앱이 복사해 주는 모양**이라 사용자가 의도해 넣은 문자가
    /// 아니기 때문이다(「3333-01-2345678」).
    ///
    /// 서버와 **같은 규칙**이라 `isAccountNumberValid` 가 「서버가 받아 줄 것인가」의 정확한 예측이 된다.
    /// 더 관대하게 만들면 그 예측이 한쪽으로만 맞는 반쪽짜리가 된다.
    ///
    /// 공백 판정은 원본(Kotlin `Char.isWhitespace`)과 같은 `isKotlinWhitespace` 다 — Swift 기본 판정은
    /// 범위가 달라(`KotlinText` 주석) 같은 입력이 두 앱에서 다르게 정규화된다.
    public static func normalizeAccountNumber(raw: String) -> String {
        var normalized = String.UnicodeScalarView()
        normalized.append(contentsOf: raw.unicodeScalars.filter { !($0 == "-" || $0.isKotlinWhitespace) })
        return String(normalized)
    }

    /// 서버가 받아 줄 계좌번호인가 — `normalizeAccountNumber` 를 거친 뒤 **숫자
    /// `ACCOUNT_MIN_DIGITS`~`ACCOUNT_MAX_DIGITS` 자리**인지 본다(서버 `AccountNumber` 와 같은 판정).
    ///
    /// 화면은 이 값으로 전송 버튼을 잠근다. 잠그지 않으면 400 `INVALID_ACCOUNT_NUMBER` 가
    /// **금액을 다 채운 뒤에** 돌아온다 — 사용자가 어느 칸이 틀렸는지 알 수 없는 실패다.
    ///
    /// 숫자는 **ASCII `0`~`9` 만**이다(서버 `\d`, 원본 `it in '0'..'9'`) — 전각·아랍 숫자는 서버가 거절한다.
    public static func isAccountNumberValid(raw: String) -> Bool {
        let digits = normalizeAccountNumber(raw: raw)

        return (ACCOUNT_MIN_DIGITS...ACCOUNT_MAX_DIGITS).contains(digits.utf16.count)
            && digits.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }

    /// 보내기 전에 **서버가 400 으로 거절할 이유**를 찾는다. 없으면 nil 이다.
    ///
    /// 1/N 그대로 보낼 때는 `splitEvenly` 가 이미 맞는 값을 만들므로 이 함수가 늘 nil 을 준다.
    /// 쓸모가 있는 쪽은 **수정 화면**이다 — 받는 사람이 금액을 손으로 고치면 합이 어긋나기 쉽고,
    /// 그 실패(400 `PAYMENTS_NOT_EQUAL_FARE`)는 입력을 다 끝낸 뒤에야 온다.
    ///
    /// 계좌번호는 보지 않는다 — 그건 `isAccountNumberValid` 가 따로 본다(틀린 칸을 가리키는 쪽이
    /// 한 덩어리 에러보다 낫다).
    public static func problemOf(totalFare: Int, riderPublicIds: [String], shares: [FareShare]) -> FareSplitDraftProblem? {
        if totalFare < MIN_TOTAL_FARE { return .fareBelowMinimum }
        if riderPublicIds.count < MIN_RIDERS { return .notEnoughRiders }
        if riderPublicIds.contains(where: \.isEmpty) { return .riderNotIdentified }
        if shares.count != riderPublicIds.count { return .targetMismatch }
        if Set(shares.map(\.riderPublicId)) != Set(riderPublicIds) { return .targetMismatch }
        if shares.contains(where: { $0.amount < MIN_SHARE }) { return .shareBelowMinimum }
        // 원본은 32비트 Int 를 Long 으로 넓혀 더한다(`sumOf { it.amount.toLong() }`). 여기 Int 는 64비트지만
        // Swift 는 넘치면 트랩(크래시)이라, 손으로 넣은 터무니없는 금액이 앱을 죽이지 않게 넘침을 「합이 다르다」로 본다.
        let (sum, overflow) = shares.reduce((0, false)) { partial, share in
            let (next, didOverflow) = partial.0.addingReportingOverflow(share.amount)
            return (next, partial.1 || didOverflow)
        }
        if overflow || sum != totalFare { return .sumNotEqualFare }
        return nil
    }
}

/// 보내기 전에 앱이 **스스로 잡을 수 있는** 거절 사유 — 서버 400 과 1:1 로 맞춰 두었다.
///
/// | 값 | 막지 않으면 오는 서버 응답 |
/// |---|---|
/// | `fareBelowMinimum` | 400 `INVALID_REQUEST`(「택시비는 1원 이상이어야 합니다」) |
/// | `notEnoughRiders` | 409 `NOT_ENOUGH_RIDERS` |
/// | `riderNotIdentified` | 400 `PAYMENT_TARGET_MISMATCH` — 지목할 publicId 가 없는 멤버가 있다 |
/// | `targetMismatch` | 400 `PAYMENT_TARGET_MISMATCH` |
/// | `shareBelowMinimum` | 400 `INVALID_REQUEST`(서버 `FarePayment` 가 0원 이하를 거절한다) |
/// | `sumNotEqualFare` | 400 `PAYMENTS_NOT_EQUAL_FARE` |
///
/// 값을 **뭉치지 않는다** — 사용자가 할 일이 다르다. 합이 안 맞는 것은 금액 칸을 고치면 되고,
/// 탑승자가 어긋난 것은 금액을 아무리 고쳐도 풀리지 않는다(방 상세를 다시 받아야 한다).
public enum FareSplitDraftProblem: String, CaseIterable, Sendable {
    case fareBelowMinimum = "FARE_BELOW_MINIMUM"
    case notEnoughRiders = "NOT_ENOUGH_RIDERS"
    case riderNotIdentified = "RIDER_NOT_IDENTIFIED"
    case targetMismatch = "TARGET_MISMATCH"
    case shareBelowMinimum = "SHARE_BELOW_MINIMUM"
    case sumNotEqualFare = "SUM_NOT_EQUAL_FARE"

    /// Kotlin `enum.name` — 원본 상수 이름 그대로.
    public var name: String { rawValue }
}

extension Ride {
    /// 정산 대상 — **출발지 도착을 누른 멤버**다. 서버 `PartyRiders.riderIds`(「탑승자 - 출발지 도착을
    /// 누른 멤버, 합류 순」)와 같은 집합을 앱에서 구하는 단일 창구다.
    ///
    /// ### 방 멤버 전원으로 채우면 반드시 틀린다
    /// 약속이 확정된 방에서 **도착을 누르지 않은 사람은 탑승자가 아니다**(서버 `riderIds` 에 들지 않는다). 그 사람을
    /// `payments` 에 넣으면 400 `PAYMENT_TARGET_MISMATCH` 이고, 반대로 도착한 사람을 빼도 같은 코드다 —
    /// **어느 쪽으로 틀려도 응답이 같아서** 원인이 가려진다. 그래서 집합을 세는 식을 화면마다 두지 않는다.
    ///
    /// 돌려주는 순서는 `Ride.members` 순서 그대로다. 서버는 `payments` 를 집합으로 검사하므로 순서는
    /// 보지 않지만(`FareSplitPolicy.splitEvenly` 참고), 화면이 목록을 그릴 때 방 화면과 같은 순서로
    /// 보이는 쪽이 낫다.
    ///
    /// **publicId 가 빈 멤버도 그대로 들어 있다**(서버가 설명하지 못한 멤버). 거르지 않는 이유는 그 멤버가
    /// 서버의 `riderIds` 에는 **들어 있기** 때문이다 — 조용히 빼면 탑승자가 하나 모자란 요청이 되어 같은
    /// 400 을 받는다. 그 경우는 정산을 시작할 수 없는 상태이고,
    /// `FareSplitPolicy.problemOf` 가 `FareSplitDraftProblem.riderNotIdentified` 로 알려 준다.
    public var fareSplitRiders: [User] {
        members.filter(\.hasArrived)
    }
}

/// 계좌번호·송금 딥링크를 **로그·디버그 출력에 남기지 않기** 위한 가림.
///
/// 서버는 계좌번호를 암호화해 저장하고 정산이 끝나면 지운다. 앱이 `print(detail)`·`dump`·디버거의 `po` 한 줄로
/// 그 값을 콘솔·기기 로그·크래시 리포트에 흘리면 서버가 지키는 보호가 무의미해진다(원본 `FareSplitActions.kt` 의
/// 「로그를 한 줄도 남기지 않는다」). 지금은 그런 출력이 한 줄도 없지만, 나중에 누가 디버깅하려고 넣는 순간을 막는
/// 장치가 「쓰지 말 것」이라는 주석뿐이면 약하다. 그래서 이 값을 든 타입은 `description`·`debugDescription`·
/// `customMirror` 를 직접 정해 **계좌는 끝 4자리만, 딥링크는 스킴만** 남긴다 — 어느 정산의 어느 계좌인지
/// 대조하는 데는 그걸로 충분하다.
///
/// 딥링크를 통째로 가리는 이유: 쿼리에 `amount`·`bank`·`accountNo` 가 그대로 들어 있다(`supertoss://send?…`).
public enum FareSplitRedaction {
    /// `****5678`. 4자리 이하면 전부 가린다 — 짧은 값의 「끝 4자리」는 값 전체다. nil 이면 `nil`.
    public static func account(_ value: String?) -> String {
        guard let value else { return "nil" }
        guard value.count > 4 else { return "****" }
        return "****" + value.suffix(4)
    }

    /// `supertoss://…` 처럼 **스킴만** 남긴다. 스킴을 읽을 수 없으면 `…` 뿐이다. nil 이면 `nil`.
    public static func deeplink(_ value: String?) -> String {
        guard let value else { return "nil" }
        guard let schemeEnd = value.range(of: "://") else { return "…" }
        return String(value[..<schemeEnd.upperBound]) + "…"
    }
}

extension FareSplitDetail: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 계좌번호·딥링크를 가린다(`FareSplitRedaction`). 나머지는 화면이 이미 보여 주는 값이라 그대로 둔다.
    public var description: String {
        "FareSplitDetail(partyId: \(partyId), status: \(status), myRole: \(myRole), totalFare: \(totalFare), "
            + "myAmount: \(myAmount), myTransferStatus: \(myTransferStatus.map { "\($0)" } ?? "nil"), "
            + "bank: \(bank.code), accountNumber: \(FareSplitRedaction.account(accountNumber)), "
            + "tossDeeplink: \(FareSplitRedaction.deeplink(tossDeeplink)), transfers: \(transfers.count))"
    }

    public var debugDescription: String { description }

    /// `dump`·디버거가 필드를 하나씩 펼칠 때도 가린 값이 보이게 한다.
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "partyId": partyId,
                "status": status,
                "totalFare": totalFare,
                "payer": payer,
                "myRole": myRole,
                "myAmount": myAmount,
                "myTransferStatus": myTransferStatus as Any,
                "bank": bank,
                "accountNumber": FareSplitRedaction.account(accountNumber),
                "tossDeeplink": FareSplitRedaction.deeplink(tossDeeplink),
                "transfers": transfers,
                "createdAt": createdAt as Any,
                "closedAt": closedAt as Any,
            ],
            displayStyle: .struct
        )
    }
}

extension ManualTransfer: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 복사 거리의 계좌번호를 가린다(`FareSplitRedaction`).
    public var description: String {
        "ManualTransfer(bankDisplayName: \(bankDisplayName), "
            + "accountNumber: \(FareSplitRedaction.account(accountNumber)), amount: \(amount))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "bankDisplayName": bankDisplayName,
                "accountNumber": FareSplitRedaction.account(accountNumber),
                "amount": amount,
            ],
            displayStyle: .struct
        )
    }
}

extension FareSplitDraft: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 사용자가 적은 계좌번호를 가린다(`FareSplitRedaction`).
    public var description: String {
        "FareSplitDraft(totalFare: \(totalFare), bankCode: \(bankCode), "
            + "accountNumber: \(FareSplitRedaction.account(accountNumber)), shares: \(shares.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "totalFare": totalFare,
                "bankCode": bankCode,
                "accountNumber": FareSplitRedaction.account(accountNumber),
                "shares": shares,
            ],
            displayStyle: .struct
        )
    }
}
