import Foundation
import MoyeotaDomain
import Testing
@testable import MoyeotaData

// 운영과 같은 디코더(`MoyeotaJSON`)로 읽는다 — 서버가 필드를 추가해도 파싱이 깨지지 않아야 한다.
// DTO 의 **직렬화 계약**(JSON 키 이름·순서)은 `fieldNames(CodingKeys)` 로 읽는다 — `PartyMappersTest` 와
// 같은 수법이다.
@Suite struct ReservationMappersTest {

    /// 백엔드 `ReservationListResponse(List<ReservationItem> list)` 모양 그대로.
    /// 항목 11필드 중 `destinationNearby` 만 **없다**(그건 검색 응답에만 붙는다).
    ///
    /// **엔벨로프 키가 `list` 다** — 노쇼 목록만 `noShows` 이므로 두 쪽을 베껴 쓰지 않도록
    /// 양쪽 테스트가 각자 키를 못 박는다.
    @Test("예약 목록 JSON 을 실제 서버 shape 그대로 역직렬화한다")
    func decodesServerShape() throws {
        let body = """
            {"list":[{"partyId":12,"departure":"강남역","destination":"판교역","currentMembers":2,
             "capacity":3,"status":"ACTIVE","departureLat":37.4979,"departureLng":127.0276,
             "destinationLat":37.3948,"destinationLng":127.1112,"departureAt":"2026-11-13T08:00:00Z"}]}
            """

        let ride = try decodeJSON(ReservationListResponse.self, body).list.single().toRide()

        #expect(ride.id == "12")
        #expect(ride.origin == "강남역")
        #expect(ride.destination == "판교역")
        #expect(ride.capacity == 3)
        #expect(ride.members.count == 2)
        #expect(ride.status == .recruiting)
        #expect(isClose(37.4979, ride.originLat, 1e-9))
        #expect(isClose(127.0276, ride.originLng, 1e-9))
        // 방 목록과 달리 **도착 좌표도 온다** — 지도에 경로를 그릴 수 있다.
        #expect(isClose(37.3948, ride.destinationLat, 1e-9))
        #expect(isClose(127.1112, ride.destinationLng, 1e-9))
        #expect(ride.departureAt == "2026-11-13T08:00:00Z")
    }

    /// ### 이 테스트가 이 파일에서 가장 중요하다 ★
    /// 서버 **응답 항목에는 `roomType` 필드가 없다**(생성 응답에만 있다). 그래서 매퍼는 그 값을
    /// 엔드포인트로 **단정한다** — 여기서 `toRoomType(roomType: nil)` 을 쓰면 그 함수는 설계상
    /// `RoomType.realtime` 을 돌려주므로 **예약 방 전체가 실시간 방으로 읽힌다.** 그러면 화면이
    /// 「약속 시간 정하기」를 띄우고, 누르면 서버가 409 `NOT_REALTIME_PARTY` 로 막는다.
    ///
    /// `Ride.isConfirmed` 도 같다 — 예약은 만들 때 출발 시각을 정하므로
    /// 처음부터 확정이다. 확정의 대가는 **나갈 수 없다**는 것(409 `CANNOT_LEAVE_CONFIRMED_PARTY`)이라,
    /// 이 값이 false 로 새면 화면이 누를 수 없는 「그만 찾기」를 띄운다.
    @Test("예약 항목은 roomType 이 없어도 예약 방이고 처음부터 확정이다")
    func reservationWithoutRoomType() throws {
        // 서버가 실제로 주는 모양 — roomType 키가 없다.
        let body = #"{"list":[{"partyId":12,"status":"ACTIVE","departureAt":"2026-11-13T08:00:00Z"}]}"#

        // DTO 에 그 필드를 만들지 **않았다**는 것까지 못 박는다. 만들면 늘 nil 이 들어오고,
        // 그 nil 을 toRoomType 에 넘기는 실수로 이어진다(그 함수는 nil 을 realtime 으로 읽는다).
        let fields = fieldNames(ReservationItemDto.CodingKeys.self)
        #expect(!fields.contains("roomType"), "ReservationItemDto 에 roomType 필드가 생겼다 — 서버는 그 키를 보내지 않는다")
        // 반대로 화면이 읽는 값들은 그대로 있어야 한다.
        #expect(Set(fields).isSuperset(of: ["partyId", "departureAt", "destinationNearby"]))

        let ride = try decodeJSON(ReservationListResponse.self, body).list.single().toRide()
        #expect(ride.roomType == .reservation)
        #expect(ride.isConfirmed, "예약 방은 처음부터 확정이다 — 「그만 찾기」를 띄우면 안 된다")
    }

    /// 생성 응답과 **방 id 키 이름이 다르다**: 이쪽은 `partyId`, `OpenPartyResponse` 는 `id`,
    /// 실시간 후보 요약은 또 `id` 다. 매퍼를 베낄 때 가장 먼저 어긋나는 자리이고, 틀리면 기본값 0 이
    /// 되어 카드가 탭해도 갈 곳이 없는 방을 그린다.
    @Test("예약 항목의 방 id 키는 partyId 다")
    func partyIdKey() {
        let fields = fieldNames(ReservationItemDto.CodingKeys.self)

        #expect(fields.contains("partyId"), "예약 항목의 방 id 는 partyId 다")
        #expect(!fields.contains("id"), "id 로 바뀌면 방 id 가 늘 0 이 된다 — 그건 생성 응답 쪽 이름이다")
    }

    /// 출발 시각이 빠진 응답에서도 **확정은 true 로 남아야 한다.**
    ///
    /// 상세 매퍼는 `confirmed` 가 없을 때 `departureAt != nil` 로 셈하는데(서버와 같은 식), 그
    /// 폴백을 여기 베끼면 서버가 `departureAt` 을 빠뜨린 응답에서 **예약 방이 미확정이 된다** —
    /// 어느 경우에도 틀린 결과다. 엔드포인트가 증거이므로 식을 쓰지 않는다.
    @Test("출발 시각이 없어도 예약 방은 확정 상태로 읽는다")
    func confirmedWithoutDepartureAt() throws {
        let ride = try decodeJSON(ReservationListResponse.self, #"{"list":[{"partyId":12}]}"#)
            .list.single().toRide()

        #expect(ride.departureAt == nil)
        #expect(ride.isConfirmed)
        #expect(ride.roomType == .reservation)
    }

    /// 검색 응답에만 `destinationNearby` 가 붙고, **true 가 먼저** 온다(서버 정렬) —
    /// 앱은 재정렬하지 않으므로 받은 순서가 그대로다.
    @Test("검색 응답의 destinationNearby 가 도메인까지 흐르고 순서가 유지된다")
    func destinationNearbyFlowsInOrder() throws {
        let body = """
            {"list":[
              {"partyId":12,"departure":"강남역","destination":"판교역","currentMembers":1,"capacity":3,
               "status":"ACTIVE","departureAt":"2026-11-13T09:00:00Z","destinationNearby":true},
              {"partyId":13,"departure":"강남역","destination":"야탑역","currentMembers":2,"capacity":3,
               "status":"ACTIVE","departureAt":"2026-11-13T08:00:00Z","destinationNearby":false}
            ]}
            """

        let results = try decodeJSON(ReservationListResponse.self, body)
            .list.map { $0.toReservationSearchResult() }

        #expect(results.map(\.destinationNearby) == [true, false])
        // 재정렬하지 않는다 — 출발 시각이 늦은 12번이 먼저인 것이 서버의 2단계 정렬이다.
        #expect(results.map(\.ride.id) == ["12", "13"])
    }

    /// ### nil 은 false 가 아니라 「물어보지 않았다」다 ★
    /// 키가 **아예 없는** 응답(목록·곧 출발)과 키는 있고 값이 null 인 응답(도착지 없는 검색)이
    /// 둘 다 nil 로 모여야 한다. false 로 접으면 도착지 없는 검색 결과 **전체**에
    /// 「도착지가 멀어요」 배지가 붙는다 — 묻지 않은 것에 답하는 꼴이다.
    @Test("도착지를 안 보낸 검색과 목록은 destinationNearby 가 null 이다")
    func destinationNearbyNil() throws {
        let explicitNull = #"{"list":[{"partyId":12,"destinationNearby":null}]}"#
        let keyAbsent = #"{"list":[{"partyId":12}]}"#

        #expect(
            try decodeJSON(ReservationListResponse.self, explicitNull)
                .list.single().toReservationSearchResult().destinationNearby == nil
        )
        #expect(
            try decodeJSON(ReservationListResponse.self, keyAbsent)
                .list.single().toReservationSearchResult().destinationNearby == nil
        )
    }

    /// 인원을 **모르면(nil) 멤버를 지어내지 않는다** — 0 으로 접으면 카드가 「0/3명」이라는
    /// 없는 상태를 그린다(방 목록·실시간 후보 매퍼와 같은 규약: 빈 목록 = 모른다).
    @Test("인원 수가 없으면 멤버를 지어내지 않는다")
    func unknownHeadcountKeepsMembersEmpty() throws {
        let body = #"{"list":[{"partyId":12,"capacity":3,"status":"ACTIVE"}]}"#

        let ride = try decodeJSON(ReservationListResponse.self, body).list.single().toRide()

        #expect(ride.members.isEmpty, "인원을 모르는데 자리 표시용 멤버를 만들었다")
        #expect(ride.capacity == 3)
    }

    /// **요금이 0 인 것은 공짜라서가 아니다** — 서버가 예약 방의 경로를 추정하지 않아 값 자체가 없다.
    /// 상세를 읽어도 없으므로, 화면은 1인당 요금 줄을 **그리지 않아야** 한다.
    @Test("예약 항목에는 요금과 경로가 없다")
    func noFareNoRoute() throws {
        let ride = try decodeJSON(ReservationListResponse.self, #"{"list":[{"partyId":12,"capacity":3}]}"#)
            .list.single().toRide()

        #expect(ride.farePerPerson == 0)
        #expect(ride.totalFare == 0)
        #expect(ride.estimatedFare == nil)
        #expect(ride.estimatedMinutes == nil)
        #expect(ride.routePolyline == nil)
    }

    /// 상태 문자열은 방 목록·상세와 **같은 표**를 쓴다. 서버 쿼리가 `status = 'ACTIVE'` 로 못 박혀
    /// 있어 실제로는 늘 모집 중이지만, 고정값으로 두면 서버가 필터를 넓힐 때 이 목록만 뒤처진다.
    @Test("상태 변환은 방 목록과 같은 표를 쓴다")
    func statusTable() throws {
        func statusOf(_ raw: String) throws -> RideStatus {
            try decodeJSON(ReservationListResponse.self, #"{"list":[{"partyId":1,"status":"\#(raw)"}]}"#)
                .list.single().toRide().status
        }

        #expect(try statusOf("ACTIVE") == .recruiting)
        #expect(try statusOf("COMPLETED") == .matched)
        #expect(try statusOf("FINISHED") == .completed)
        #expect(try statusOf("CANCELED") == .canceled)
    }

    /// 좌표가 빠져도 매핑이 깨지지 않는다(전 필드 기본값 + nullable).
    @Test("좌표가 빠져도 예약 매핑이 깨지지 않는다")
    func missingCoordinates() throws {
        let ride = try decodeJSON(ReservationListResponse.self, #"{"list":[{"partyId":12}]}"#)
            .list.single().toRide()

        #expect(ride.originLat == nil)
        #expect(ride.destinationLng == nil)
        #expect(ride.id == "12")
    }

    /// 빈 목록·키 없는 응답 모두 정상이다(그 날 그 범위에 예약이 없을 뿐이다).
    @Test("빈 예약 목록도 정상 파싱된다")
    func emptyList() throws {
        #expect(try decodeJSON(ReservationListResponse.self, #"{"list":[]}"#).list.isEmpty)
        #expect(try decodeJSON(ReservationListResponse.self, "{}").list.isEmpty)
    }

    @Test("모르는 필드가 늘어나도 예약 파싱이 깨지지 않는다")
    func unknownFields() throws {
        // DTO 가 가진 필드를 쓰면 "모르는 필드"가 아니게 되므로 없는 이름을 쓴다.
        let body = #"{"list":[{"partyId":12,"roomType":"RESERVED","hostNickname":"성윤"}],"total":1}"#

        #expect(try decodeJSON(ReservationListResponse.self, body).list.single().toRide().id == "12")
    }

    /// ### 생성 요청 본문의 필드명이 이 PR 에서 가장 틀리기 쉽다 ★
    /// 도착지가 **`destinationLat`/`destinationLng`** 다 — 실시간 후보 본문(`destLat`/`destLng`)과
    /// 예약 **검색** 쿼리(`depLat`·`depLng`·`destLat`·`destLng`)와 **셋이 전부 다르다.**
    /// 여기서 줄인 이름을 쓰면 서버 record 의 `@NotNull` 위반으로 400 `INVALID_REQUEST` 다.
    ///
    /// 그리고 **싣는 것은 여덟 개뿐**이다 — 생성자 id 도, 반경도 없다(`NewParty.toRequestDto` 와 같다).
    @Test("예약 생성 요청 본문에는 좌표 이름 정원 출발시각만 실린다")
    func requestBodyKeys() throws {
        let request = NewReservation(
            departureLat: 37.4979,
            departureLng: 127.0276,
            destinationLat: 37.3948,
            destinationLng: 127.1112,
            departure: "강남역",
            destination: "판교역",
            capacity: 3,
            departureAt: "2026-11-13T08:00:00Z"
        ).toRequestDto()

        #expect(
            request == OpenReservationRequestDto(
                departureLat: 37.4979,
                departureLng: 127.0276,
                destinationLat: 37.3948,
                destinationLng: 127.1112,
                departure: "강남역",
                destination: "판교역",
                capacity: 3,
                departureAt: "2026-11-13T08:00:00Z"
            )
        )

        // 직렬화된 키 이름까지 못 박는다 — DTO 필드명을 고치면 여기서 먼저 걸린다.
        let keys = Set(try parseJSONObject(try encodeJSON(request)).keys)
        #expect(
            keys == [
                "departureLat", "departureLng", "destinationLat", "destinationLng",
                "departure", "destination", "capacity", "departureAt",
            ]
        )
        // 줄인 이름이 새어 들어오면 서버가 @NotNull 위반으로 400 을 준다.
        #expect(!keys.contains("destLat"), "도착지 키가 destLat 으로 줄었다 — 예약 생성 본문은 전체 이름이다")
        #expect(!keys.contains("depLat"), "출발지 키가 depLat 으로 줄었다 — 그건 검색 쿼리 쪽 이름이다")
        // 서버가 버리는 값을 되살리지 않는다.
        #expect(!keys.contains("creatorId"), "생성자 id 가 본문에 실렸다 — 생성자는 토큰이 정한다")
        #expect(!keys.contains("departureRadius"), "반경이 본문에 실렸다 — 서버가 고정값(500m)을 쓴다")
    }

    /// 앱이 **정원을 접지 않는다**(범위로 끌어올리지 않는다). 2~3 밖의 값이 그대로 나가야 400 이 떨어져
    /// **앱 버그가 드러난다** — 조용히 고치면 화면이 잘못된 정원을 보낸 사실이 영원히 숨는다.
    /// 출발 시각도 같다: 모양·범위 검사는 서버 몫이다.
    @Test("앱이 정원과 출발 시각을 고치지 않고 그대로 싣는다")
    func sendsCapacityAndTimeVerbatim() {
        let request = NewReservation(
            departureLat: 1.0, departureLng: 2.0, destinationLat: 3.0, destinationLng: 4.0,
            departure: "A", destination: "B",
            // 서버가 거절할 값. 앱이 2 로 끌어올리면 안 된다.
            capacity: 1,
            // 오프셋 없는 로컬 시각 — 서버가 400 을 줘야 한다.
            departureAt: "2026-11-13T17:00:00"
        ).toRequestDto()

        #expect(request.capacity == 1)
        #expect(request.departureAt == "2026-11-13T17:00:00")
    }
}
