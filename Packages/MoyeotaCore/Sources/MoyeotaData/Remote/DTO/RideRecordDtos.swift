/// `GET /api/v1/users/me/parties` 의 기본 조회 개수. 서버 기본값과 같은 20 이다.
///
/// 서버가 받는 범위는 **1~50** 이고 밖이면 400 `INVALID_PAGE_SIZE` 다
/// (실측 2026-11-01, 로컬 `:8080`: `size=0` → 400, `size=51` → 400, `size=50` → 200).
/// 이 상수를 0 이나 100 으로 바꾸면 목록이 통째로 비고, 화면은 「기록이 없어요」를 그린다
/// — 에러와 빈 목록이 사용자에게 같은 모양이 되므로 원인을 쫓을 단서가 사라진다.
public let RIDE_RECORD_PAGE_SIZE = 20

/// `GET /api/v1/users/me/parties` 한 페이지. 서버 `RideRecordResponse`.
///
/// **이름이 함정이다.** 경로가 `parties` 라 「내 방 목록」처럼 읽히지만 서버 태그는 「탑승 기록」이고
/// **하차까지 끝난 탑승만** 나온다(서버 `RideRecordJpaRepository` 의 `dropoffTime is not null`).
/// 진행 중인 방은 절대 들어오지 않는다 — 실측(2026-11-01, 로컬 `:8080`): 내가 유일 멤버인
/// `status=MATCHING` 방을 하나 들고 이 엔드포인트를 불러도 `{"rides":[],"nextCursor":null,"hasNext":false}`
/// 였다. 그래서 이것으로 `ActivePartyRepository` 의 로컬 기억을
/// **대체할 수 없다.** 그 공백은 서버에 `GET /matching/rooms/me` 가 생겨야 메워진다.
///
/// 탈퇴 경고를 이걸로 미리 막으려 해도 안 된다 — 409 `USER110` 의 판정식은 서버
/// `existsOngoingByMemberId`(진행 중 상태 = ACTIVE·COMPLETED. 기사·배차 상태 셋은 서버 enum 에서
/// 삭제됐다)인데 이 응답은 그중 아무것도 주지 않는다. 「막을 방이 없다」고 잘못 판정해 그대로 409 를 맞고, 사용자는
/// 앱이 확인했다고 믿는다 — 지금보다 나빠진다.
public struct RideRecordPageResponse: Decodable, Equatable, Sendable {
    public var rides: [RideRecordResponse]
    /// 다음 페이지 커서(= 이 페이지 마지막 `partyId`). **`hasNext` 가 false 면 항상 null** 이다
    /// (서버 `RideRecordService` 가 `hasNext ? page.getLast().getMatchId() : null` 로 만든다).
    ///
    /// 실측 두 응답: `size=1` 1페이지 → `nextCursor=69, hasNext=true`,
    /// `cursor=69` 2페이지 → `nextCursor=null, hasNext=false`.
    public var nextCursor: Int64?
    /// 더 받을 페이지가 있는가. **이 값만 보고 다음 페이지를 부른다.**
    ///
    /// false 인데도 부르면 `cursor` 없이 **첫 페이지를 다시 받아** 목록이 무한히 중복된다.
    /// 반대로 진행 중인 방 id 를 커서로 넣으면 400 `INVALID_CURSOR` 다(실측: 하차 전 방 `cursor=54`).
    public var hasNext: Bool

    public init(rides: [RideRecordResponse] = [], nextCursor: Int64? = nil, hasNext: Bool = false) {
        self.rides = rides
        self.nextCursor = nextCursor
        self.hasNext = hasNext
    }

    private enum CodingKeys: String, CodingKey {
        case rides, nextCursor, hasNext
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rides = try c.decodeOrDefault(.rides, default: [])
        nextCursor = try c.decodeIfPresent(Int64.self, forKey: .nextCursor)
        hasNext = try c.decodeOrDefault(.hasNext, default: false)
    }
}

/// 탑승 기록 한 건. 서버 `RideRecordItem`.
///
/// **`status` 필드가 없다** — 기록은 전부 하차 완료라 상태 개념이 없다. 방 상세
/// (`PartyDetailResponse`)를 베껴 `status` 를 넣으면 디코더가 모르는 키를 흘리는 탓에
/// 조용히 기본값이 되어 화면이 **모든 기록에 같은 상태 칩**을 그린다. `capacity`·좌표·`route`·
/// `version` 도 같은 이유로 여기 없다.
///
/// `totalFare`·`farePerPerson` 은 그 방의 **택시비 정산**에서 온다 — 정산이 없거나 내가 정산의
/// 당사자가 아니면 **둘 다 null** 이다(서버가 함께 채우거나 함께 비운다). **0 으로 접지 마라** —
/// 화면이 「0원」을 그리면 거짓말이다.
///
/// **`dropoffTime` 은 없다** — 서버가 하차 시각을 지우고 승차 시각(`pickupTime`) 하나로
/// 바로잡았다(`135df701`). 승차 시각은 방장이 출발을 누른 시각이고, 자동 정리된 방은 약속 시각이다.
/// 키를 남겨 두면 늘 nil 이 되어 날짜를 그리던 화면이 조용히 빈칸이 된다.
public struct RideRecordResponse: Decodable, Equatable, Sendable {
    public var partyId: Int64
    public var departure: String?
    public var destination: String?
    public var pickupTime: String?
    public var totalFare: Int?
    /// 내 부담 금액 — 보내는 사람은 받는 사람이 정한 **내가 보낼 금액**, 받는 사람은 택시비에서 다른
    /// 사람들이 보낼 금액을 뺀 금액. 1/N 이 아니라서 **같은 방을 보는 두 사람이 다른 값을 받는다.**
    ///
    /// **앱이 다시 계산하지 마라.** 방장이 사람마다 적은 금액이 뭉개지고, 앱의 `farePerPersonWon`
    /// (14·15 가 쓰는 예상 요금 계산)은 10원 단위로 맞추므로 실제 금액과도 어긋난다.
    public var farePerPerson: Int?
    /// 함께 탄 인원(나 포함). 정원(`capacity`)이 아니다 — 서버가 정원을 주지 않아 「2/3명」은 못 만든다.
    public var currentMembers: Int
    public var members: [RideRecordMemberResponse]

    public init(
        partyId: Int64 = 0,
        departure: String? = nil,
        destination: String? = nil,
        pickupTime: String? = nil,
        totalFare: Int? = nil,
        farePerPerson: Int? = nil,
        currentMembers: Int = 0,
        members: [RideRecordMemberResponse] = []
    ) {
        self.partyId = partyId
        self.departure = departure
        self.destination = destination
        self.pickupTime = pickupTime
        self.totalFare = totalFare
        self.farePerPerson = farePerPerson
        self.currentMembers = currentMembers
        self.members = members
    }

    private enum CodingKeys: String, CodingKey {
        case partyId, departure, destination, pickupTime, totalFare, farePerPerson, currentMembers, members
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        partyId = try c.decodeOrDefault(.partyId, default: 0)
        departure = try c.decodeIfPresent(String.self, forKey: .departure)
        destination = try c.decodeIfPresent(String.self, forKey: .destination)
        pickupTime = try c.decodeIfPresent(String.self, forKey: .pickupTime)
        totalFare = try c.decodeIfPresent(Int.self, forKey: .totalFare)
        farePerPerson = try c.decodeIfPresent(Int.self, forKey: .farePerPerson)
        currentMembers = try c.decodeOrDefault(.currentMembers, default: 0)
        members = try c.decodeOrDefault(.members, default: [])
    }
}

/// 함께 탄 사람. 서버 `RideRecordMember` — **필드가 셋뿐이다.** 방 상세의 `MemberInfo` 와 달리
/// `host`·`rideCount`·`badgeId` 가 없다. 그래서 기록 화면에는 「방장」 표시를 그릴 수 없고,
/// 「이게 나인가」도 서버가 말해 주지 않아 `publicId` 비교로 앱이 직접 만든다.
///
/// 탈퇴한 동승자는 `publicId` 는 그대로, `nickname` 이 `"탈퇴한 사용자"`(서버가 직접 넣는 값),
/// `imageUrl` 이 기본 이미지 주소로 온다. 사용자 요약 자체가 없으면 **셋 다 null** 이다.
public struct RideRecordMemberResponse: Decodable, Equatable, Sendable {
    public var publicId: String?
    public var nickname: String?
    public var imageUrl: String?

    public init(publicId: String? = nil, nickname: String? = nil, imageUrl: String? = nil) {
        self.publicId = publicId
        self.nickname = nickname
        self.imageUrl = imageUrl
    }
}
