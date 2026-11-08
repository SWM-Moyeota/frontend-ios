import MoyeotaDomain

extension ReservationItemDto {
    /// 예약 방 한 건 → `Ride`. 목록·곧 출발·검색이 **같은 매퍼를 쓴다**(DTO 가 하나인 이유와 같다 —
    /// `ReservationListResponse` 주석).
    ///
    /// ### 예약용 도메인 모델을 만들지 않는다
    /// 예약 방도 방이다 — 참여·나가기·상세·SSE 가 전부 기존 방 API 그대로이고, 경로·요금이 비어 있는
    /// 것은 `Ride` 의 기존 nullable 필드가 이미 표현한다. 새 모델을 만들면 같은 방이 화면에 따라 다른
    /// 타입으로 흐르고, 합류 버튼부터 상세 조회까지 전부 두 벌이 된다.
    ///
    /// ### `Ride.roomType` 을 **엔드포인트로 단정한다** ★
    /// 서버 응답 항목에는 `roomType` 필드가 **없다**(생성 응답에만 있다). 그래서 `toRoomType` 을 거칠
    /// 값 자체가 없는데, 그 함수는 nil 을 설계상 `RoomType.realtime` 으로 떨어뜨린다 — 즉
    /// `roomType: toRoomType(roomType: nil)` 로 적으면 **예약 방 전체가 실시간 방으로 읽힌다.** 그러면 화면이
    /// 「약속 시간 정하기」를 띄우고 누르면 서버가 409 `NOT_REALTIME_PARTY` 로 막는다.
    ///
    /// 여기서는 고정값이 **추측이 아니라 증거**다: 세 엔드포인트가 모두 예약만 돌려준다
    /// (서버 쿼리가 `room_type = 'RESERVED'` 로 못 박혀 있다). 「모르는 값은 realtime」이라는
    /// `toRoomType` 의 규칙과 충돌하지 않는다 — 그 규칙은 **서버가 말해 줬는데 모르는 문자열일 때**의
    /// 이야기이고, 여기는 서버가 말해 줄 필요가 없는 자리다.
    ///
    /// ### `Ride.isConfirmed` 도 늘 true 다
    /// 예약 방은 만들 때 출발 시각을 정하므로 처음부터 확정이다(서버 `Party.isConfirmed()` =
    /// `isReservation() || departureAt != null` — 두 항이 모두 참이다). 상세 매퍼가 쓰는 폴백
    /// (`departureAt != nil`)과 같은 답을 내지만 **그 식을 쓰지 않는다**: 서버가 `departureAt` 을
    /// 빠뜨린 응답에서 식은 false 가 되는데, 예약 방이 미확정이 되는 그 결과는 어느 경우에도 틀리다.
    ///
    /// ⚠️ 확정의 대가를 화면이 알아야 한다: 확정된 방은 **나갈 수 없다**(409
    /// `CANNOT_LEAVE_CONFIRMED_PARTY`). 예약 카드·상세에 「그만 찾기」를 띄우면 누를 수 없는 버튼이 된다.
    ///
    /// ### 나머지는 방 목록 매퍼와 같은 규약
    /// 인원은 자리 표시용 멤버로 채우고 **모르면(nil) 빈 목록으로 남긴다** — 0 으로 접으면 카드가
    /// 「0/3명」이라는 없는 상태를 그린다(`PartyListResponse.PartyItem.toRide` 와 같은 근거). 요금은 서버가 추정하지
    /// 않아 0 이고, `Ride.estimatedFare`·`Ride.routePolyline` 은 nil 이다 — **공짜라서가 아니다.**
    /// 상태 문자열은 `partyStatusToRideStatus` 로 옮긴다(서버가 늘 `ACTIVE` 를 주지만 표를 한 벌로 둔다).
    /// `Ride.departureLabel` 은 빈 문자열이다 — 사람이 읽을 모양으로 바꾸는 일은 화면이 한다.
    public func toRide() -> Ride {
        Ride(
            id: String(partyId),
            origin: departure,
            destination: destination,
            departureLabel: "",
            capacity: capacity,
            members: currentMembers.map(reservationPlaceholderMembers(count:)) ?? [],
            farePerPerson: 0,
            totalFare: 0,
            status: partyStatusToRideStatus(status: status),
            originLat: departureLat,
            originLng: departureLng,
            // 방 목록과 달리 **도착 좌표도 온다** — 지도에 경로를 그릴 수 있다(실시간 후보와 같다).
            destinationLat: destinationLat,
            destinationLng: destinationLng,
            departureAt: departureAt,
            // 둘 다 서버 필드가 아니라 **엔드포인트가 주는 사실**이다 — 위 주석 참고.
            isConfirmed: true,
            roomType: .reservation
        )
    }

    /// 검색 결과 한 건 → `ReservationSearchResult`. `toRide` 에 `destinationNearby` 하나를 얹는다.
    ///
    /// 그 값만 `Ride` 밖에 두는 이유는 **방의 성질이 아니기** 때문이다(같은 방이 검색어에 따라 true 도
    /// null 도 된다) — 근거 전문은 `ReservationSearchResult` 주석에 있다.
    ///
    /// **nil 을 false 로 접지 않는다.** 「도착지가 멀다」와 「물어보지 않았다」는 다른 사실이고,
    /// 접으면 도착지 없는 검색 결과 전체에 「도착지가 멀어요」 배지가 붙는다.
    public func toReservationSearchResult() -> ReservationSearchResult {
        ReservationSearchResult(ride: toRide(), destinationNearby: destinationNearby)
    }
}

/// 멤버 식별자가 없는 예약 목록에서 인원 수만큼 자리 표시용 멤버를 만든다.
///
/// `PartyMappers` 의 `placeholderMembers` 와 **같은 모양이고 일부러 따로 둔다** — 그쪽이 `private`
/// 이고 파일 소유가 갈려 있어서다(다른 작업과 동시에 고치는 중). 두 함수가 어긋나면 같은 방이
/// 목록과 검색에서 다른 인원으로 보이므로, 나중에 한곳으로 모으는 쪽이 낫다.
///
/// 닉네임·프로필을 **그리면 안 된다**(서버가 누가 들었는지 주지 않는다) — 개수만 믿는다.
private func reservationPlaceholderMembers(count: Int) -> [User] {
    (0..<max(count, 0)).map { index in
        User(id: "m\(index)", nickname: "멤버 \(index + 1)", verifiedLabel: "", rating: 0.0, rideCount: 0)
    }
}

extension NewReservation {
    /// 예약 생성 요청 본문. 실리는 것은 **좌표·이름·정원·출발 시각**이다.
    ///
    /// 생성자 id 도 반경도 없다 — `NewParty.toRequestDto` 와 같은 이유다(토큰이 정하고, 서버가 고정값을
    /// 쓴다). `NewReservation.departureAt` 은 **검사하지 않고 그대로 싣는다**: 모양(ISO-8601 instant)과
    /// 범위(지금~7일)의 판정은 서버가 하고, 앱이 같은 검사를 두 벌 들면 서버가 범위를 바꿀 때 한쪽만
    /// 따라간다(`confirmMeeting` 과 같은 정책). 정원도 범위로 접지 않는다 — 2~3 밖의 값이 가면
    /// 400 이 나야 **앱 버그가 드러난다.**
    ///
    /// ⚠️ 도착 좌표의 필드명이 `destinationLat`/`destinationLng` 다 — 검색 쿼리의 `destLat`/`destLng` 와
    /// 다르다(`OpenReservationRequestDto` 주석의 표).
    public func toRequestDto() -> OpenReservationRequestDto {
        OpenReservationRequestDto(
            departureLat: departureLat,
            departureLng: departureLng,
            destinationLat: destinationLat,
            destinationLng: destinationLng,
            departure: departure,
            destination: destination,
            capacity: capacity,
            departureAt: departureAt
        )
    }
}
