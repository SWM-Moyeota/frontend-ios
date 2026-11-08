/// 내 **노쇼 기록과 이의 신청**만 다룬다 — `GET /api/v1/matching/no-shows` ·
/// `POST /api/v1/matching/rooms/{partyId}/no-show-objection`.
///
/// ### `RideRepository` 에 끼워 넣지 않은 이유
/// `RideRepository` 는 **진행 중인 방**을 다룬다(상세·생성·합류·나가기·확정·도착·출발). 노쇼는
/// 그 방들이 **이미 끝난 뒤에 남는 제재**이고, 여기서 하는 일은 방을 움직이는 게 아니라 제재의 근거를
/// 읽고 이의를 내는 것이다. 섞으면 그 인터페이스가 「방을 다루는 계약」에서 「방과 관련된 모든 것」으로
/// 번지는데, 그 선을 넘은 전례가 이미 한 번 정리된 바 있다(`RideRecordRepository` 의 분리).
/// 그리고 `/rooms/{partyId}/…` 경로는 **같은 가지인데 컨트롤러가 다르다**(서버
/// `NoShowController`) — 경로가 비슷하다는 것이 같은 계약이라는 뜻은 아니다.
///
/// ### `RideRecordRepository` 와도 다르다 ★
/// 가장 가까워 보이는 이웃이고, 그래서 가장 분명히 갈라 둬야 한다.
///
/// | | `RideRecordRepository` | 이 저장소 |
/// |---|---|---|
/// | 무엇의 기록인가 | **탄** 기록(서버가 `dropoffTime is not null` 로 거른다) | **타지 못한** 기록 |
/// | 페이징 | 커서 페이징(`cursor`·`size`, 1~50) | **없다.** 서버가 최신 `HISTORY_LIMIT`건으로 자른다 |
/// | 쓰기 | 없다(순수 조회) | **있다**(`submitObjection`) |
/// | 서버 출처 | `GET /users/me/parties` | `/matching/no-shows` + `/matching/rooms/…` |
///
/// 한 저장소로 묶으면 「내 기록」이라는 이름 아래 **탄 것과 안 탄 것**이 섞이고, 페이징이 있는 조회와
/// 없는 조회가 같은 인터페이스에 공존해 호출부가 매번 「이건 더 불러올 수 있나」를 되물어야 한다.
/// 그리고 쓰기 액션이 들어오면 「조회는 맨몸으로 던지고 액션만 전용 예외로 좁힌다」는 그쪽의 규칙이
/// 반쪽만 적용되는 상태가 된다.
///
/// ### 「지금 제한 중인가」는 이 저장소가 모른다 ★
/// 노쇼 **횟수와 제한 기한**은 프로필 쪽이다 — `UserProfileInfo.noShowCount`·
/// `UserProfileInfo.restrictedUntil`, 즉 `AuthRepository.getMyProfile` 이 주는 값이고
/// **다른 엔드포인트**다. 이쪽으로 끌어오지 않는 이유는
/// 서버가 그렇게 나눠 놓은 것을 앱이 합치면 두 번째 진실이 생기기 때문이다: 이 목록은 최대 20건이라
/// 비어 보여도 제한이 걸려 있을 수 있고, 반대로 기록이 있어도 24시간이 지났으면 자유다.
/// **제한 판정은 프로필 하나로만** 한다(`NoShowRecord` 주석의 세 가지 함정).
///
/// 즉 마이페이지의 제재 화면은 **두 저장소를 함께** 읽는다 — 프로필에서 「지금 상태」를, 여기서
/// 「왜 그렇게 됐나」와 「이의 신청」을.
public protocol NoShowRepository: Sendable {

    /// 내 노쇼 기록. **노쇼 시각 최신순, 최대 `HISTORY_LIMIT`건.**
    ///
    /// - **빈 목록은 정상이다**(노쇼가 없다). 서버가 404 가 아니라 `{"noShows":[]}` 를 준다.
    /// - **재정렬하지 말 것.** 받은 순서가 서버의 정렬이다(`noShowAt` 내림차순, 동시각은 방 id 내림차순).
    /// - **「더 보기」를 만들 수 없다.** 커서도 개수 파라미터도 없고, 서버가 20건에서 자른다 —
    ///   그보다 많은 노쇼가 있는 사용자는 **오래된 건을 볼 길이 없다**. 화면이 「최근 20건」이라고
    ///   말해 두는 쪽이 정확하다(「전체」라고 쓰면 거짓이 된다).
    /// - **무효가 된 건도 들어온다**(`NoShowRecord.isVoided` = true). 빼지 않는 것이 서버의 선택이고,
    ///   그 줄이 「이의가 받아들여졌다」는 유일한 증거다 — 걸러내면 사용자가 결과를 확인할 수 없다.
    ///
    /// 실패를 **전용 예외로 감싸지 않는다.** 이 조회의 서버 실패는 401 하나뿐이고(업무 에러 코드가
    /// 없다) 화면의 대응도 하나다(「기록을 불러오지 못했어요 · 다시 시도」) — 사유별 문구가 필요한
    /// 액션만 좁히는 것이 이 앱의 결이다(`RideRecordRepository.getMyRecords` 와 같은 판단).
    func getMyNoShows() async throws -> [NoShowRecord]

    /// **이의 신청.** `POST /api/v1/matching/rooms/{partyId}/no-show-objection` (201, 본문 없음).
    ///
    /// ### 언제 부를 수 있는가 — 화면이 먼저 가린다
    /// 서버 지시대로 **`NoShowRecord.objectionStatus` 가 null 이고 `NoShowRecord.isVoided` 가 false 인
    /// 줄에만** 버튼을 보여 준다. 그 밖에서 부르면 409(`ALREADY_OBJECTED`·`NOT_NO_SHOW`)이고, 그건
    /// 실패가 아니라 **목록이 낡았다는 신호**다.
    ///
    /// ### `reason`
    /// 다듬은 뒤 **1~500자**(`NoShowObjectionException.MAX_REASON_LENGTH`). 저장소가 보내기 전에
    /// 앞뒤 공백을 떼는데, 그건 서버 검증이 **다듬기 전 문자열**에 걸리기 때문이다 — 공백으로 패딩된
    /// 501자는 다듬으면 500자 이하여도 400 이다. 빈 값·초과 **판정은 하지 않는다**(서버 몫) —
    /// 화면이 입력란에서 막는 쪽으로 책임을 진다.
    ///
    /// ### 성공 뒤 — **목록을 다시 읽어야 한다** ★
    /// 201 에 **본문이 없다.** 즉 접수된 이의의 상태를 응답에서 알 길이 없으므로, 성공 자리에서
    /// `getMyNoShows` 를 다시 읽어 그 줄의 `NoShowRecord.objectionStatus` 를
    /// `ObjectionStatus.pending` 으로 채워야 한다. 안 읽으면 그 줄에 버튼이
    /// 그대로 남고(노출 조건이 `objectionStatus == nil` 이다) 다시 누르면 409 다.
    ///
    /// 화면이 상태를 손으로 pending 으로 바꿔치는 것도 가능하지만 **권하지 않는다** — 그 순간부터
    /// 화면이 들고 있는 목록이 서버와 다른 근거로 만들어진 값을 섞어 들게 되고, 다음 조회에서 조용히
    /// 덮인다. 되돌릴 수 없는 액션의 결과는 서버에서 다시 받는 쪽이 안전하다.
    ///
    /// **제한이 바로 풀리지는 않는다.** 이의는 운영자가 심사하므로 접수(201) 시점에
    /// `UserProfileInfo.restrictedUntil` 은 **그대로다** — 화면이 「제한이
    /// 풀렸어요」라고 말하면 거짓이다. 인정되면 그때 제한이 풀리고, 앱은 다음 프로필 조회에서 안다.
    ///
    /// 실패는 모두 `NoShowObjectionException` 으로 올라온다
    /// (400 `INVALID_REQUEST` / 403 `NOT_PARTY_MEMBER` / 404 `PARTY_NOT_FOUND` /
    /// 409 `NOT_NO_SHOW`·`ALREADY_OBJECTED` / 네트워크). **409 가 두 가지 뜻**이라 화면은 상태 코드가
    /// 아니라 그 예외의 프로퍼티로 분기한다 — 사유마다 다음 행동이 다르고, 근거는 그 주석의 표에 있다.
    func submitObjection(partyId: Int64, reason: String) async throws
}

/// Kotlin `NoShowRepository.Companion` 의 자리. Swift 프로토콜은 메타타입에서 정적 멤버를 꺼낼 수 없어
/// (`NoShowRepository.HISTORY_LIMIT` 가 안 된다) 값을 여기 둔다. 구현 타입에서는 `Self.HISTORY_LIMIT` 로도 읽는다.
public enum NoShowRepositoryDefaults {
    /// 서버가 돌려주는 최대 건수(서버 `NoShowObjectionService.HISTORY_LIMIT`).
    ///
    /// **요청에 싣는 값이 아니다** — 쿼리 파라미터가 없어 앱이 바꿀 수 없다. 화면이 「최근 N건」
    /// 문구를 만들 때 쓰는 값이고, 서버가 상한을 바꾸면 **여기만 고친다**(그러면 문구가 따라온다).
    public static let HISTORY_LIMIT = 20
}

extension NoShowRepository {
    public static var HISTORY_LIMIT: Int { NoShowRepositoryDefaults.HISTORY_LIMIT }
}
