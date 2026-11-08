/// 내 노쇼 한 건 — `GET /api/v1/matching/no-shows` 의 한 항목.
///
/// 노쇼는 앱이 **만들 수도 있고 당할 수도 있는** 유일한 제재다. 만드는 쪽은
/// `RideRepository.departParty` 다 — 누군가 「출발」을 누르는 순간
/// 그때까지 도착을 누르지 않은 멤버가 전부 여기 한 줄로 남는다. 이 모델은 **당한 쪽**이 그걸
/// 들여다보는 창이고, 지금까지 앱에는 그 창이 없었다(제재당한 사용자는 방 만들기·합류가 막히는데
/// 왜인지 알 수 없었다).
///
/// ### 「지금 제한 중인가」는 여기서 알 수 없다 ★
/// 이 목록은 **과거 기록**이다. 「지금 막혀 있는가 · 언제까지인가」는 프로필
/// (`UserProfileInfo.noShowCount` · `UserProfileInfo.restrictedUntil`)이 말해 주고, 둘은
/// **다른 엔드포인트**다(`GET /api/v1/local/users/info`). 한쪽만 읽고 다른 쪽을 셈하려 들면 어긋난다:
///
/// - 기록이 **있어도** 제한은 풀려 있을 수 있다(약속 시간부터 24시간이 지났다).
/// - 기록이 **비어 보여도** 제한이 걸려 있을 수 있다(이 목록은 최대 20건이다).
/// - `isVoided` 된 줄은 횟수에도 제한에도 **잡히지 않는다**.
///
/// 그러니 화면의 분기는 「`UserProfileInfo.restrictedUntil` 이 있는가」로 하고, 이 목록은
/// **설명과 이의 신청의 대상**으로만 쓴다.
///
/// ### 시각은 문자열이다
/// 서버가 주는 ISO-8601 문자열을 그대로 들고 있는다 — `RideRecord`·`ChatMessage` 와 같은 관례이고
/// 이유도 같다(도메인에 파싱을 두면 data 와 domain 이 각자 파싱을 들고 어긋난다). 사람이 읽을
/// 모양으로 바꾸는 일은 화면이 한다. 파싱 실패는 화면이 「날짜 칸을 비운다」로 처리한다.
public struct NoShowRecord: Hashable, Sendable {
    /// 노쇼가 찍힌 방. **이의 신청의 대상이 이 값이다**
    /// (`NoShowRepository.submitObjection`) — 노쇼 자체에는 식별자가
    /// 없고 서버도 「방 + 나」로 한 건을 가리킨다. 그래서 같은 방에 이의는 **한 번뿐**이다.
    public var partyId: Int64
    /// 그 방의 출발지 이름. 서버가 주지 않으면 빈 문자열(매퍼가 접는다) — 화면이 null 을 또 확인하지 않게.
    public var departure: String
    public var destination: String
    /// 그 방의 약속 시간(ISO-8601). **이용 제한을 여기서부터 센다** — 노쇼가 찍힌 시각(`noShowAt`)이
    /// 아니다. 둘을 섞으면 화면이 「언제까지 막히는가」를 몇 분~몇 시간 틀리게 말한다.
    ///
    /// 다만 제한의 끝을 **앱이 계산하지 말 것**: 서버가 `UserProfileInfo.restrictedUntil` 로 직접 준다.
    /// 여러 건이 겹칠 때의 합산 규칙은 서버 것이고, 앱이 같은 식을 다시 세우면 서버가 규칙을 바꿀 때
    /// 한쪽만 따라간다.
    public var meetingAt: String?
    /// 노쇼로 찍힌 시각(ISO-8601). 누군가 「출발」을 누른 때, 또는 아무도 오지 않은 방을 서버가
    /// 자동 정리한 때다. 목록의 **정렬 기준**(최신순)이라 사실상 항상 있다.
    public var noShowAt: String?
    /// 운영자가 이의를 받아들여 **무효로 돌렸는가**. true 면 이 줄은 노쇼로 치지 않는다 —
    /// 탑승 기록·횟수에 다시 잡히고, 그 때문에 걸려 있던 제한도 풀린다.
    ///
    /// **`objectionStatus` 와 같은 값이 아니다.** 상태는 「심사가 어디까지 왔나」이고 이쪽은
    /// 「결과가 반영됐나」다. 서버가 상태를 ACCEPTED 로 바꾸고 무효 처리까지 하지만, 둘을 하나로
    /// 접으면 운영자가 상태만 바꾼 중간 상태를 표현할 수 없다.
    public var isVoided: Bool
    /// 이의 신청의 심사 상태. **null 이면 아직 내지 않았다.**
    ///
    /// 이의 신청 버튼은 **`objectionStatus == nil && !isVoided` 인 줄에만** 보여 준다(서버 Swagger
    /// 지시). 그 밖의 줄에서 누르면 409 `ALREADY_OBJECTED` 또는 `NOT_NO_SHOW` 다
    /// (`NoShowObjectionException`).
    ///
    /// 모르는 문자열도 null 이다 — `ObjectionStatus.pending` 으로 떨어뜨리지 **않는다**.
    /// 그 이유는 `ObjectionStatus` 주석에 적어 두었다.
    public var objectionStatus: ObjectionStatus?

    public init(
        partyId: Int64,
        departure: String,
        destination: String,
        meetingAt: String?,
        noShowAt: String?,
        isVoided: Bool,
        objectionStatus: ObjectionStatus?
    ) {
        self.partyId = partyId
        self.departure = departure
        self.destination = destination
        self.meetingAt = meetingAt
        self.noShowAt = noShowAt
        self.isVoided = isVoided
        self.objectionStatus = objectionStatus
    }
}

/// 이의 신청 심사 상태. 서버 문자열 `PENDING`·`ACCEPTED`·`REJECTED` 와 1:1이다.
///
/// `RoomType` 처럼 **String raw value 를 두지 않는다.** 두면 `init(rawValue:)` 로 서버 문자열을 읽고
/// 싶어지는데, 그건 모르는 값에서 nil 이 아니라 **판정을 매퍼 밖으로 흘리는** 길이다 — 서버 문자열과의
/// 짝은 매퍼 하나(`toObjectionStatus`)에서만 맞춘다(공백 처리·모르는 값의 방향이 거기 있다).
///
/// ### 모르는 값을 `pending` 으로 떨어뜨리지 말 것 ★
/// 이 enum 은 이 앱의 **다른 매퍼들과 반대 방향**으로 기운다. 데이터 계층의 `partyStatusToRideStatus`
/// 는 모르는 상태를 `RideStatus.recruiting` 으로, `toRoomType` 은 모르는 종류를 `RoomType.realtime`
/// 으로 떨어뜨린다 — 그쪽은 **모르면 화면이 열리는 쪽**이 안전하기 때문이다.
///
/// 여기서는 그 대가가 뒤집힌다. 모르는 값을 `pending` 으로 읽으면 화면은
/// 「심사 중이에요, 결과를 기다려 주세요」라고 **없는 사실을 단정**한다. 기각된 사람에게도, 아직
/// 시작도 안 한 사람에게도 같은 말을 하고, 사용자는 그 말을 믿고 **기다린다** — 이의 신청 버튼이
/// 그 줄에서 사라지므로 다시 낼 길도 없다(위 `NoShowRecord.objectionStatus` 의 노출 규칙).
/// null(= 모른다)로 두면 화면은 상태 줄을 **비우고**, 버튼 노출은 `objectionStatus == nil` 이라
/// 「한 번 더 낼 수 있다」로 떨어진다. 그 오답은 서버가 409 `ALREADY_OBJECTED` 로 **복구해 준다.**
///
/// | 모르는 값을 무엇으로 읽나 | 틀렸을 때 |
/// |---|---|
/// | null | 상태가 안 보이고 버튼이 한 번 더 뜬다 → 눌러도 서버가 409 로 막는다(**복구됨**) |
/// | `pending` | 기각·미신청을 「심사 중」으로 단정하고 **다시 낼 길을 닫는다**(복구 불가) |
///
/// 즉 안전한 방향은 「모른다를 모른다로 두는 것」이다.
public enum ObjectionStatus: Hashable, CaseIterable, Sendable {
    /// 접수됐고 운영자 심사를 기다린다.
    case pending

    /// 받아들여졌다. 그 노쇼는 무효가 되고(`NoShowRecord.isVoided`) 걸려 있던 제한이 풀린다.
    case accepted

    /// 기각됐다. 같은 방에 **다시 낼 수 없다**(409 `ALREADY_OBJECTED`).
    case rejected
}
