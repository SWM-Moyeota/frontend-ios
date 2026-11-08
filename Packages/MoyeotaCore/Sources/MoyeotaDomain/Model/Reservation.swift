/// 예약 방 생성 요청 — `POST /api/v1/matching/reservations`.
///
/// ### `NewParty` 와 따로 둔 이유 ★
/// 두 요청은 좌표 4개·이름 2개·정원까지 같고 **응답 record 도 같다**(`OpenPartyResponse`). 그래도
/// 합치지 않는 건 필드 하나가 아니라 **계약이 다르기** 때문이다:
///
/// | | 실시간(`NewParty`) | 예약(이 모델) |
/// |---|---|---|
/// | `capacity` | **1~3** (혼자 타는 방이 된다) | **2~3** — 혼자 타는 예약은 만들 수 없다 |
/// | 출발 시각 | 없다. 방장이 나중에 확정한다 | **필수** (`departureAt`) |
/// | 서버의 경로 추정 | 한다(실패하면 생성 실패) | **하지 않는다** — 요금·시간·경로가 빈 방이 생긴다 |
/// | 만든 직후 상태 | 미확정(`Ride.isConfirmed` false) | **처음부터 확정** |
///
/// `NewParty` 에 `departureAt: String?` 하나를 더해 겹쳐 쓰면 **정원 하한이 표현되지 않는다** —
/// 「시각이 있으면 2 이상」이라는 규칙이 타입 밖으로 새어 나가고, 그걸 모르는 호출부가 보낸 정원 1은
/// 400 이 된다. 모델이 둘이면 각 화면이 자기 하한만 알면 된다.
///
/// ### 서버 검증 규칙(위반 시 400) — 앱이 **다시 검사하지 않는다**
/// 정원 2~3, `now < departureAt <= now + 7일`, 좌표는 서비스 지역 안, 출발·도착이 다른 좌표.
/// 판정은 서버가 하고 앱은 **애초에 만들 수 없는 값을 못 만들게** 막는 쪽으로 책임을 진다(정원 칩은
/// 2·3 만, 피커는 지금~7일만) — `RideRepository.confirmMeeting` 이
/// 약속 시간에 대해 같은 방식을 쓴다. 두 벌 검사를 들면 서버가 범위를 바꿀 때 한쪽만 따라간다.
///
/// 생성자 id 는 없다 — 토큰이 정한다(`NewParty` 주석). 반경도 없다(서버 고정 500m).
public struct NewReservation: Hashable, Sendable {
    public var departureLat: Double
    public var departureLng: Double
    public var destinationLat: Double
    public var destinationLng: Double
    public var departure: String
    public var destination: String
    /// 정원(생성자 포함) **2~3**. 실시간 방의 1~3 과 **다르다** — 혼자 타는 예약은 뜻이 없어 서버가
    /// `@Min(2)` 로 막는다.
    ///
    /// 하한을 어긴 요청은 `INVALID_CAPACITY` 가 아니라 **400 `INVALID_REQUEST`** 로 떨어진다
    /// (Bean Validation 이 도메인보다 먼저 돈다) — 그 사정은
    /// `PartyOpenException.isInvalidCapacity` 에 적어 두었다.
    public var capacity: Int
    /// 출발 시각. **ISO-8601 순간(instant) 문자열**이어야 한다 — `"2026-11-13T08:00:00Z"` 처럼 `Z` 로
    /// 끝나거나 `+09:00` 오프셋이 붙어야 하고, `ISO8601DateFormatter` 의 기본 출력(UTC, `Z`)을 그대로
    /// 넣으면 맞다.
    ///
    /// **오프셋 없는 로컬 시각(`"2026-11-13T17:00:00"`)은 400 이다** — 서버 record 가 `Instant` 라
    /// 역직렬화에서 터지고, 그 400 은 `INVALID_DEPARTURE_TIME` 이 아니라 `INVALID_REQUEST` 다
    /// (`PartyOpenException` 의 어느 시각 사유도 참이 아니라 **일반 문구로만** 보인다).
    /// `RideRepository.confirmMeeting` 의 `departureAt` 과 **같은 함정**이고,
    /// 거기서 가장 찾기 어려운 실패로 꼽은 것이 이것이다.
    ///
    /// 범위는 **지금 뒤 ~ 7일 안**이고 양쪽이 모두 엄격하다(지금과 같은 시각도 거절된다).
    public var departureAt: String

    public init(
        departureLat: Double,
        departureLng: Double,
        destinationLat: Double,
        destinationLng: Double,
        departure: String,
        destination: String,
        capacity: Int,
        departureAt: String
    ) {
        self.departureLat = departureLat
        self.departureLng = departureLng
        self.destinationLat = destinationLat
        self.destinationLng = destinationLng
        self.departure = departure
        self.destination = destination
        self.capacity = capacity
        self.departureAt = departureAt
    }
}

/// 예약 방 검색 결과 한 건 — `GET /api/v1/matching/reservations/search`.
///
/// ### 왜 `Ride` 를 감싸는가 — 예약용 도메인 모델을 만들지 않는 이유 ★
/// 예약 방도 **방이다**: 참여·나가기·상세·SSE 가 전부 기존 방 API 그대로이고(서버 Swagger 가
/// 못 박았다) 앱에는 `Ride`·`RoomType` 이 이미 있다. 그래서 목록 항목 자체는 `Ride` 로 옮긴다 —
/// 경로·요금이 비어 있다는 사실은 `Ride` 의 기존 nullable 필드가 이미 표현한다.
///
/// 감싸는 건 `destinationNearby` **하나 때문**이고, 그 값은 **방의 성질이 아니다** — 내가 보낸
/// 도착지 좌표에 대한 답이라 같은 방이 검색어에 따라 true 도 null 도 된다. `Ride` 에 태우면 두
/// 화면이 같은 방을 서로 다른 값으로 들게 되고, `Ride` 끼리의 `==` 비교(주기 조회가 「바뀌었나」를
/// 보는 수단)가 검색 조건 때문에 달라진다. `PartyDetail.version` 을 `Ride` 밖에 둔 것과 **같은
/// 판단**이고, 모양은 `MatchCandidate` 의 선례를 그대로 따른다(그쪽의 `walkSeconds` 도 내 좌표에
/// 달린 값이다).
///
/// **받은 순서가 계약이다.** 서버가 「도착지도 가까운 방 먼저, 그 안에서 출발 시각 순」으로 정렬해
/// 준다 — 앱에서 다시 정렬하면 그 의도가 사라진다.
public struct ReservationSearchResult: Hashable, Sendable {
    /// 방의 뼈대만 채운 `Ride` — id·출발·도착·좌표·정원·인원·출발 시각이다.
    ///
    /// **`Ride.roomType` 은 `RoomType.reservation` 이고 `Ride.isConfirmed` 는 true 다.** 서버 응답
    /// 항목에는 `roomType` 필드가 **아예 없지만**, 이 엔드포인트가 예약만 돌려주므로 매퍼가 단정한다
    /// (근거는 매퍼 주석). 그래서 이 방에는 「약속 시간 정하기」를 띄우면 안 된다.
    ///
    /// **요금은 0 이다** — 서버가 예약 방의 경로를 추정하지 않아 애초에 값이 없다(공짜라서가 아니다).
    /// `MatchCandidate.ride` 와 같은 제약이고, 1인당 요금이 필요하면 상세를 읽어야 한다.
    public var ride: Ride
    /// 이 방의 **도착지도 내 도착지 1km 안인가**. 서버 `destinationNearby`.
    ///
    /// **null 은 false 가 아니라 「물어보지 않았다」다** — 도착지 좌표를 안 보낸 검색이었다는 뜻이고,
    /// 그때는 서버가 출발 시각 순으로만 정렬한다. 화면은 null 에 「도착지가 멀어요」 같은 배지를
    /// 붙이면 안 된다(묻지 않은 것에 답하는 꼴이다). 두 상태를 한 Boolean 으로 접으면 그 구분이 사라져
    /// 도착지 없는 검색 결과 전체에 틀린 배지가 붙는다.
    ///
    /// 이 앱의 다른 Boolean 들과 달리 **`is` 접두사를 붙이지 않는다**(`Ride.isConfirmed`·
    /// `User.isHost`·`NoShowRecord.isVoided` 와 다른 점이다). 접두사는 「참인가 거짓인가」를 묻는
    /// 말인데 이 값은 **셋 중 하나**라, `isDestinationNearby == nil` 이 「가까운지 아닌지가 null 이다」
    /// 라는 읽히지 않는 문장이 된다. 서버 필드명과 같은 이름을 쓰는 이점도 있다 — 이 레포가
    /// `arrived`/`isArrived`, `host`/`isHost` 로 호되게 배운 자리다.
    public var destinationNearby: Bool?

    public init(ride: Ride, destinationNearby: Bool?) {
        self.ride = ride
        self.destinationNearby = destinationNearby
    }
}

/// 예약 검색의 **선택 조건**인 도착지 좌표.
///
/// ### 왜 Double 두 개가 아니라 한 값인가 ★
/// 서버는 `destLat`·`destLng` 를 **둘 다 받거나 둘 다 빼야** 하고, 하나만 오면 400
/// `INCOMPLETE_DESTINATION` 이다(`(destLat == null) != (destLng == null)` 검사). 저장소 파라미터를
/// `Double?` 두 개로 두면 그 400 을 **타입으로 막을 수 없고**, 하필 호출부가 가장 흔히 하는 실수가
/// 「위도만 채워 넣기」다.
///
/// 한 값으로 묶으면 「둘 다」와 「둘 다 아님」만 표현 가능해져 그 실패가 **코드에서 사라진다.**
/// 이 앱의 다른 좌표 파라미터들(`getPartiesWithin` 의 네 Double 등)은 **전부 필수**라 같은 문제가
/// 없어 평평하게 두었다 — 묶는 이유는 좌표라서가 아니라 **선택이기 때문**이다.
public struct ReservationDestination: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
