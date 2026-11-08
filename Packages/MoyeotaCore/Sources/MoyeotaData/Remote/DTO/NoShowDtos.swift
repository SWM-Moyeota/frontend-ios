/// `GET /api/v1/matching/no-shows` 의 200 응답. 백엔드 `MyNoShowListResponse(List<NoShowItem> noShows)`
/// 와 필드 1:1 (`matching/noshow/dto/MyNoShowListResponse.java`).
///
/// **엔벨로프 키가 `noShows` 다 — `list` 가 아니다.** 같은 매칭 도메인의 방 목록
/// (`PartyListResponse`)과 예약 목록(`ReservationListResponse`)은 둘 다 `list` 를 쓰는데 이 하나만
/// 다르다(서버 record 가 그렇게 선언돼 있다). 베껴 쓰면 디코더가 모르는 키를 조용히
/// 흘려 **항상 빈 목록**이 되고, 화면은 「노쇼 기록이 없어요」라는 **틀린 좋은 소식**을 말한다 —
/// 에러가 아니라서 알아챌 길이 없다. `NoShowMappersTest` 가 키 이름을 값으로 못 박는다.
///
/// 빈 배열은 **정상**이다(`{"noShows":[]}`) — 노쇼가 없으면 404 가 아니라 200 + 빈 배열이다.
/// 기본값을 둔 것은 그 때문이 아니라 키가 빠진 응답(구버전·프록시)에서 목록 전체가 날아가지 않게
/// 하기 위한 것이다.
public struct MyNoShowListResponse: Decodable, Equatable, Sendable {
    public var noShows: [NoShowItemDto]

    public init(noShows: [NoShowItemDto] = []) {
        self.noShows = noShows
    }

    private enum CodingKeys: String, CodingKey {
        case noShows
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noShows = try c.decodeOrDefault(.noShows, default: [])
    }
}

/// 내 노쇼 한 건. 백엔드 record
/// `NoShowItem(Long partyId, String departure, String destination, Instant meetingAt, Instant noShowAt,
/// boolean voided, String objectionStatus)` 와 필드 1:1.
///
/// ### `voided` — **`isVoided` 가 아니다** ★
/// 서버 record 컴포넌트 이름이 `voided` 이므로 접근자는 `voided()` 이고, Jackson 의 `is` 접두사
/// 처리가 끼어들 자리가 없다(`@JsonProperty` 도 없다). 도메인 객체 쪽에는 `isVoided()` 가 있지만
/// 그건 직렬화되지 않고 매퍼가 호출해 `voided` 컴포넌트에 넣는 값이다 — 실제 와이어 키는
/// **`voided` 하나뿐**이고 서버 컨트롤러 테스트가 `$.noShows[0].voided` 로 못 박고 있다.
///
/// 여기서 `isVoided` 로 적으면 디코더가 모르는 키로 흘려서 **조용히 늘 false** 가 되고, 무효로
/// 돌려진 노쇼에 이의 신청 버튼이 다시 뜬다(눌러도 409 `NOT_NO_SHOW`). 방 상세의
/// `arrived`/`isArrived`, 멤버의 `host`/`isHost` 와 **같은 함정**이라 테스트가 틀린 이름이 먹히지
/// 않음을 함께 확인한다.
///
/// ### 왜 `voided` 는 non-null `Bool = false` 인가
/// 서버 record 가 **원시 `boolean`** 이라 명시적 null 이 올 수 없고, 키는 Jackson 기본 설정
/// (`@JsonInclude` 가 레포 전체에 없다)으로 **항상 실린다**. 기본값 false 는 구버전·프록시 대비이고
/// 방향도 안전한 쪽이다 — 「모른다」를 무효로 읽으면 이의 신청 버튼이 사라져 억울한 사용자가 낼 길을
/// 잃는다(false 쪽 오답은 서버가 409 로 막아 복구된다).
///
/// ### 시각 두 개
/// `Instant` 이고 Spring 기본 설정이 ISO-8601 문자열로 직렬화한다(레포에 Jackson 커스터마이징이
/// 없다) — **그래서 `String?` 으로 받는다.** ⚠️ 컬럼이 `timestamp(6)` 이라 실제 값에 소수점 아래
/// 6자리가 붙을 수 있다(`2026-11-03T08:30:00.123456Z`). 문자열로 들고 있는 이 계층은 영향이 없지만
/// **화면이 파싱할 때 고정 패턴(`yyyy-MM-dd'T'HH:mm:ss'Z'`)을 쓰면 터진다** — 소수 초 유무를 모두
/// 받는 파서를 쓸 것. 도메인까지 문자열로 흐르는 이유는
/// `NoShowRecord` 주석에 있다.
///
/// `meetingAt` 은 서버 쿼리가 방의 `departureAt` 을 그대로 집어 오는데 그 컬럼이 nullable 이다
/// (확정 전 실시간 방). 실제로는 **노쇼가 약속이 정해진 방에서만 나오므로** 비어 올 수 없지만
/// (서버 주석이 명시한다) nullable 로 받는다 — 비용이 0 이고, non-null 이면 그 한 줄이 목록 전체의
/// 파싱을 터뜨린다. `noShowAt` 은 쿼리의 `where` 조건이라(`m.noShowAt is not null`) 더더욱 늘 있다.
public struct NoShowItemDto: Decodable, Equatable, Sendable {
    public var partyId: Int64
    public var departure: String
    public var destination: String
    public var meetingAt: String?
    public var noShowAt: String?
    /// 서버 record 컴포넌트 이름 그대로. **`isVoided` 가 아니다** — 위 주석 참고.
    public var voided: Bool
    /// 심사 상태 문자열(`PENDING`·`ACCEPTED`·`REJECTED`) 또는 **null = 안 냈다**.
    ///
    /// 와이어 타입이 **String** 이다 — 서버 DTO 가 enum 이 아니라 `status.name()` 결과를 담는다.
    /// 그래서 이 계층도 String 으로 받고, 모르는 값을 **버리는 판정은 매퍼가 한다**
    /// (`Decodable` enum 으로 선언하면 모르는 값이 **파싱 예외**가 되어 목록 전체가 날아간다 —
    /// 서버가 상태를 하나 추가하는 날 노쇼 화면이 통째로 죽는다).
    public var objectionStatus: String?

    public init(
        partyId: Int64 = 0,
        departure: String = "",
        destination: String = "",
        meetingAt: String? = nil,
        noShowAt: String? = nil,
        voided: Bool = false,
        objectionStatus: String? = nil
    ) {
        self.partyId = partyId
        self.departure = departure
        self.destination = destination
        self.meetingAt = meetingAt
        self.noShowAt = noShowAt
        self.voided = voided
        self.objectionStatus = objectionStatus
    }

    private enum CodingKeys: String, CodingKey {
        case partyId, departure, destination, meetingAt, noShowAt, voided, objectionStatus
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        partyId = try c.decodeOrDefault(.partyId, default: 0)
        departure = try c.decodeOrDefault(.departure, default: "")
        destination = try c.decodeOrDefault(.destination, default: "")
        meetingAt = try c.decodeIfPresent(String.self, forKey: .meetingAt)
        noShowAt = try c.decodeIfPresent(String.self, forKey: .noShowAt)
        voided = try c.decodeOrDefault(.voided, default: false)
        objectionStatus = try c.decodeIfPresent(String.self, forKey: .objectionStatus)
    }
}

/// `POST /api/v1/matching/rooms/{partyId}/no-show-objection` 의 요청 본문.
/// 백엔드 `NoShowObjectionRequest(@NotBlank @Size(max = 500) String reason)` 와 필드 1:1.
///
/// **필드가 하나뿐이고 식별자가 없다.** 어느 노쇼에 대한 이의인지는 경로의 `partyId` 와 Bearer 토큰이
/// 함께 정한다 — 노쇼 자체에는 식별자가 없고 서버도 「방 + 나」로 한 건을 가리킨다.
///
/// **성공은 201 이고 본문이 없다**(`Location` 헤더도 없다). 이 도메인의 다른 액션들이 전부 204 거나
/// 200 인데 이것만 201 이라, 「본문이 올 것」으로 보고 반환 타입을 붙이면 디코더가 빈 본문에서
/// 터진다 — API 선언은 반환값을 두지 않는다(`MatchingApi.submitNoShowObjection`).
///
/// 글자 수 검증은 **앞뒤 공백을 떼기 전에** 돈다. 즉 공백으로 패딩된 501자는 다듬으면 500자 이하여도
/// 400 `INVALID_REQUEST` 다(서버가 `strip()` 하는 건 검증을 통과한 뒤다). 그래서 저장소가 보내기 전에
/// 다듬는다(`RemoteNoShowRepository.submitObjection`) — 서버와 똑같이
/// 다듬는 것이지 **검사를 대신하는 게 아니다**(빈 값·초과 판정은 서버가 한다).
public struct NoShowObjectionRequestDto: Codable, Equatable, Sendable {
    public var reason: String

    public init(reason: String) {
        self.reason = reason
    }
}
