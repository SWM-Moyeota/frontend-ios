@testable import FeatureExplore
import Foundation
import MoyeotaDomain
import Testing

/// 17 탐색의 **예약 찾기 규칙** — 무엇을 물어볼 수 있는가, 결과를 어떻게 말하는가.
///
/// 세 가지를 못 박는다.
/// 1. **도착지는 둘 다 또는 둘 다 아니다**(400 `INCOMPLETE_DESTINATION`) — 한쪽만 실어 보내는 길이
///    코드에 없어야 한다.
/// 2. **날짜 창**(오늘~7일 뒤, 한국 달력) — 벗어난 날짜로는 조회하지 않는다(400 `INVALID_SEARCH_DATE`).
///    탐색 탭은 오래 살아 있어서 자정을 넘기면 어제 고른 칩이 그대로 남는다.
/// 3. **모드마다 영역이 다르다**는 사실이 문구에 남아 있는가 — 「곧 출발」은 지도 범위, 「날짜로
///    찾기」는 내 위치 1km 다. 섞어 읽으면 사용자가 「저 동네 방이 왜 안 보이지」로 받아들인다.
struct ReservationFinderTest {
    /// KST 2026-11-09 (월) 13:00.
    private let now = Date(timeIntervalSince1970: 1_794_196_800) // 2026-11-09T04:00:00Z
    private let today = LocalDate(year: 2026, month: 11, dayOfMonth: 9)!
    private let bounds = MapBounds(swLat: 35.2, swLng: 129.0, neLat: 35.3, neLng: 129.1)

    private func member(_ index: Int) -> User {
        User(id: "u\(index)", nickname: "김OO", verifiedLabel: "학교 인증", rating: 0.0, rideCount: 0)
    }

    private func ride(
        id: String = "1",
        members: Int = 2,
        capacity: Int = 3,
        departureAt: String? = "2026-11-09T09:30:00Z"
    ) -> Ride {
        Ride(
            id: id,
            origin: "부산대 정문",
            destination: "서면역",
            departureLabel: "",
            capacity: capacity,
            members: (0..<members).map(member),
            farePerPerson: 0,
            totalFare: 0,
            status: .recruiting,
            departureAt: departureAt,
            isConfirmed: true,
            roomType: .reservation
        )
    }

    // ─────────────────────────── 도착지: 둘 다 또는 둘 다 아니다 ───────────────────────────

    @Test("도착지는 둘 다 있을 때만 실어 보낸다")
    func destinationNeedsBothCoordinates() {
        #expect(
            reservationDestinationOrNull(latitude: 35.16, longitude: 129.06)
                == ReservationDestination(latitude: 35.16, longitude: 129.06)
        )
        #expect(reservationDestinationOrNull(latitude: nil, longitude: 129.06) == nil, "경도만 있으면 400 INCOMPLETE_DESTINATION")
        #expect(reservationDestinationOrNull(latitude: 35.16, longitude: nil) == nil, "위도만 있으면 같은 400")
        #expect(reservationDestinationOrNull(latitude: nil, longitude: nil) == nil)
    }

    /// (0, 0) 은 **값이 빠졌을 때의 기본값**이다 — 서버 요청 record 가 primitive `double` 이라
    /// 필드가 빠지면 0.0 이 들어가고, 그 좌표는 서비스 지역 밖이라 사유가 「서비스 지역 밖」으로
    /// 보인다(좌표가 아니라 지역을 의심하게 되는 함정).
    @Test("0,0 과 유한하지 않은 좌표는 보내지 않는다")
    func zeroAndNonFiniteAreDropped() {
        #expect(reservationDestinationOrNull(latitude: 0.0, longitude: 0.0) == nil)
        #expect(reservationDestinationOrNull(latitude: .nan, longitude: 129.0) == nil)
        #expect(reservationDestinationOrNull(latitude: 35.1, longitude: .infinity) == nil)
        // 0 이 한쪽만이면 실제 좌표일 수 있다(적도·본초자오선) — 막지 않는다
        #expect(
            reservationDestinationOrNull(latitude: 0.0, longitude: 129.0)
                == ReservationDestination(latitude: 0.0, longitude: 129.0)
        )
    }

    // ─────────────────────────── 어떤 조회를 할 수 있는가 ───────────────────────────

    @Test("실시간 모드에서는 예약 조회를 하지 않는다")
    func realtimeHasNoReservationQuery() {
        #expect(
            reservationQueryOrNull(
                mode: .realtime,
                bounds: bounds,
                myLatitude: 35.23,
                myLongitude: 129.08,
                date: today,
                destination: nil,
                now: now
            ) == nil
        )
    }

    @Test("곧 출발은 지도 범위만 있으면 된다")
    func soonNeedsOnlyBounds() {
        let query = reservationQueryOrNull(
            mode: .soon,
            bounds: bounds,
            myLatitude: nil,
            myLongitude: nil,
            date: nil,
            destination: nil,
            now: now
        )

        #expect(query == .soon(bounds: bounds))
    }

    /// 지도가 아직 범위를 알려주지 않았거나 **두 모서리가 같은 점**이면 묻지 않는다.
    ///
    /// 0 폭 뷰포트는 실제로 400 `INVALID_MAP_BOUNDS` 다.
    @Test("지도 범위가 없거나 0 폭이면 곧 출발을 조회하지 않는다")
    func missingOrZeroWidthBoundsSkipSoon() {
        let zeroWidth = MapBounds(swLat: 35.2, swLng: 129.0, neLat: 35.2, neLng: 129.0)

        for badBounds in [nil, zeroWidth] {
            #expect(
                reservationQueryOrNull(
                    mode: .soon,
                    bounds: badBounds,
                    myLatitude: 35.23,
                    myLongitude: 129.08,
                    date: today,
                    destination: nil,
                    now: now
                ) == nil,
                "조회할 수 없는 범위로 물었다: \(String(describing: badBounds))"
            )
        }
        #expect(bounds.isQueryable)
        #expect(!zeroWidth.isQueryable)
    }

    @Test("날짜 검색은 내 좌표와 날짜를 싣고 날짜는 yyyy-MM-dd 다")
    func byDateCarriesCoordinatesAndDate() {
        let query = reservationQueryOrNull(
            mode: .byDate,
            bounds: bounds,
            myLatitude: 35.23,
            myLongitude: 129.08,
            date: today.plusDays(2),
            destination: ReservationDestination(latitude: 35.16, longitude: 129.06),
            now: now
        )

        #expect(
            query == .byDate(
                departureLat: 35.23,
                departureLng: 129.08,
                date: "2026-11-11",
                destination: ReservationDestination(latitude: 35.16, longitude: 129.06)
            )
        )
    }

    /// ★ **1km 의 중심을 지도 중심으로 대신하지 않는다.** 화면이 「내 위치에서 1km」라고 적는데
    /// 지도를 옮겨 둔 사람에게 그 말이 거짓이 된다 — 좌표가 없으면 조회하지 않고 기다린다고 말한다.
    @Test("내 좌표가 없으면 날짜 검색을 하지 않는다")
    func byDateNeedsMyCoordinates() {
        #expect(
            reservationQueryOrNull(
                mode: .byDate,
                bounds: bounds,
                myLatitude: nil,
                myLongitude: nil,
                date: today,
                destination: nil,
                now: now
            ) == nil
        )
    }

    /// ★ **자정을 넘긴 탐색 탭.** 어제 고른 칩이 그대로 남아 있으면 그 날짜는 창을 벗어나
    /// 400 `INVALID_SEARCH_DATE` 다 — 조회를 하지 않는 쪽이 맞다(화면이 날짜를 다시 고르게 한다).
    @Test("창을 벗어난 날짜로는 조회하지 않는다")
    func outOfWindowDateSkipsQuery() {
        for outOfWindow in [today.minusDays(1), today.plusDays(8)] {
            #expect(
                reservationQueryOrNull(
                    mode: .byDate,
                    bounds: bounds,
                    myLatitude: 35.23,
                    myLongitude: 129.08,
                    date: outOfWindow,
                    destination: nil,
                    now: now
                ) == nil,
                "창 밖 날짜로 조회했다: \(outOfWindow)"
            )
        }
        // 경계는 포함이다 — 오늘과 7일 뒤는 조회한다
        for inWindow in [today, today.plusDays(7)] {
            let query = reservationQueryOrNull(
                mode: .byDate,
                bounds: bounds,
                myLatitude: 35.23,
                myLongitude: 129.08,
                date: inWindow,
                destination: nil,
                now: now
            )
            var isByDate = false
            if case .byDate = query { isByDate = true }
            #expect(isByDate, "창 안 날짜를 막았다: \(inWindow)")
        }
    }

    // ─────────────────────────── 카드·마커 표기 ───────────────────────────

    /// 서버는 UTC 로 내려준다 — 문자열을 자르면 KST 오후 6:30 이 오전 9:30 으로 보인다.
    @Test("출발 시각은 한국 시간으로 적고 오늘 내일을 이름으로 부른다")
    func departureLabelInKoreanTime() {
        #expect(reservationDepartureLabel(departureAt: "2026-11-09T09:30:00Z", now: now) == "오늘 오후 6:30")
        #expect(reservationDepartureLabel(departureAt: "2026-11-10T00:00:00Z", now: now) == "내일 오전 9:00")
        #expect(reservationDepartureLabel(departureAt: "2026-11-15T11:00:00Z", now: now) == "11월 15일 (일) 오후 8:00")
    }

    /// 읽을 수 없으면 **줄을 그리지 않는다** — 「시간 미정」 같은 자리값은 확정된 방을 미정으로 보여 준다.
    @Test("읽을 수 없는 출발 시각은 null 이다")
    func unreadableDepartureIsNil() {
        #expect(reservationDepartureLabel(departureAt: nil, now: now) == nil)
        #expect(reservationDepartureLabel(departureAt: "", now: now) == nil)
        #expect(reservationDepartureLabel(departureAt: "   ", now: now) == nil)
        // 오프셋 없는 로컬 시각은 순간이 아니다 — 추측해서 KST 로 읽지 않는다
        #expect(reservationDepartureLabel(departureAt: "2026-11-09T18:30:00", now: now) == nil)
    }

    @Test("예약 마커 캡션은 시각과 인원을 함께 적는다")
    func markerCaptionHasTimeAndHeadcount() {
        #expect(
            reservationMarkerCaption(departureAt: "2026-11-09T09:30:00Z", joined: 2, capacity: 3, now: now)
                == "오늘 오후 6:30 · 2/3명"
        )
        // 인원을 모르면(0) 지어내지 않고 정원만 — `headcountLabel` 의 규칙을 그대로 따른다
        #expect(
            reservationMarkerCaption(departureAt: "2026-11-09T09:30:00Z", joined: 0, capacity: 3, now: now)
                == "오늘 오후 6:30 · 최대 3명"
        )
    }

    /// **빈 문자열 계약** — 둘 다 모르면 호출부가 캡션을 아예 달지 않는다(`ExploreMarker`).
    @Test("시각도 인원도 모르면 캡션이 비어 있다")
    func markerCaptionEmptyWhenNothingKnown() {
        #expect(reservationMarkerCaption(departureAt: nil, joined: 0, capacity: 0, now: now) == "")
        // 한쪽만 알면 그 한쪽만 적는다(구분자가 혼자 남지 않는다)
        #expect(reservationMarkerCaption(departureAt: nil, joined: 0, capacity: 3, now: now) == "최대 3명")
        #expect(
            reservationMarkerCaption(departureAt: "2026-11-09T09:30:00Z", joined: 0, capacity: 0, now: now)
                == "오늘 오후 6:30"
        )
    }

    /// 「도착지도 1km 안」은 **서버가 true 라고 말했을 때만**이다. false 에 「도착지가 멀어요」를
    /// 쓰지 않는 이유: 1.1km 인지 20km 인지 모른다(모르는 것을 단정하지 않는다).
    @Test("도착지 배지는 true 일 때만 붙는다")
    func nearbyBadgeOnlyWhenTrue() {
        #expect(destinationNearbyBadge(destinationNearby: true) == "도착지도 1km 안")
        #expect(destinationNearbyBadge(destinationNearby: false) == nil)
        #expect(destinationNearbyBadge(destinationNearby: nil) == nil, "도착지를 안 보낸 검색·곧 출발은 null 이다")
    }

    // ─────────────────────────── 제목·안내 문구 ───────────────────────────

    /// **실시간 문구는 한 글자도 바뀌지 않았다** — 이 작업은 모드를 더한 것이다.
    @Test("실시간 제목은 예전과 같다")
    func realtimeTitlesUnchanged() {
        #expect(explorePeekTitle(mode: .realtime, count: 3, dateLabel: nil) == "주변 동승 3개 모집 중")
        #expect(exploreListTitle(mode: .realtime, count: 3, dateLabel: nil) == "주변 동승 3개 · 가까운 순")
        #expect(exploreAreaNote(mode: .realtime, destinationSent: false) == nil, "실시간에는 없던 줄을 더하지 않는다")
    }

    /// ★ **모르는 정렬을 적지 않는다.** 도착지를 보낸 검색은 「도착지 가까운 방이 먼저」라
    /// 「출발 시간 순」이 거짓이 되고, 「곧 출발」은 서버가 순서를 약속하지 않았다.
    @Test("정렬은 서버가 보장하는 것만 적는다")
    func titleStatesOnlyGuaranteedOrder() {
        #expect(
            exploreListTitle(mode: .byDate, count: 2, dateLabel: "오늘", destinationSent: false)
                == "오늘 출발 2개 · 출발 시간 순"
        )
        let withDestination = exploreListTitle(mode: .byDate, count: 2, dateLabel: "오늘", destinationSent: true)
        #expect(withDestination == "오늘 출발 2개")
        #expect(!withDestination.contains("출발 시간 순"), "도착지를 보내면 출발 시간 순이 아니다")

        let soon = exploreListTitle(mode: .soon, count: 2, dateLabel: nil)
        #expect(soon == "곧 출발 2개")
        #expect(!soon.contains("순"), "서버가 약속하지 않은 순서를 적지 않는다")
    }

    /// ★ 두 모드가 **다른 영역**을 본다는 사실이 화면에 남아 있어야 한다.
    @Test("영역 안내는 모드마다 기준을 말한다")
    func areaNoteStatesCriteria() {
        let soon = exploreAreaNote(mode: .soon, destinationSent: false) ?? ""
        #expect(soon.contains("지도"), "\(soon)")
        #expect(soon.contains("30분"), "\(soon)")

        let byDate = exploreAreaNote(mode: .byDate, destinationSent: false) ?? ""
        #expect(byDate.contains("내 위치"), "\(byDate)")
        #expect(byDate.contains("1km"), "\(byDate)")
        // 1km 는 서버 고정값이라 「범위를 넓혀 보세요」로 안내할 수 없다
        #expect(!byDate.contains("넓"), "\(byDate)")

        let withDestination = exploreAreaNote(mode: .byDate, destinationSent: true) ?? ""
        #expect(withDestination.contains("먼저"), "\(withDestination)")
    }

    @Test("빈 목록 문구는 모드에 맞는 다음 행동을 말한다")
    func emptyCopyStatesNextAction() {
        let (soonTitle, soonSubtitle) = reservationEmptyCopy(mode: .soon, dateLabel: nil)
        #expect(soonTitle == "30분 안에 출발하는 예약이 없어요")
        #expect(soonSubtitle.contains("지도"), "\(soonSubtitle)")

        // 「내일에 출발하는」처럼 조사를 붙이지 않는다 — 날짜 문구가 이름일 때 어긋난다
        let (dateTitle, dateSubtitle) = reservationEmptyCopy(mode: .byDate, dateLabel: "내일")
        #expect(dateTitle == "내일 출발 예약이 없어요")
        #expect(dateSubtitle.contains("다른 날짜"), "\(dateSubtitle)")
    }

    /// ★ 0건이 **「없다」는 뜻이 아닐 때**가 있다 — 접힘 요약은 개수만 보므로 이 판정이 없으면
    /// 조회 실패·좌표 대기를 「예약이 없어요」로 말한다(장애를 사실로 바꿔 말하는 자리).
    @Test("실패와 대기 중에는 없다고 말하지 않는다")
    func statusTitleBeforeEmptyCopy() {
        #expect(reservationStatusTitle(loading: true, locating: true, failed: false) == RESERVATION_LOCATING_TEXT)
        #expect(reservationStatusTitle(loading: true, locating: false, failed: false) == RESERVATION_LOADING_TEXT)
        #expect(reservationStatusTitle(loading: false, locating: false, failed: true) == RESERVATION_LOAD_FAILED_TEXT)
        // 조회가 끝나고 실패도 아니면 0건은 **사실**이다 — 그때만 「없어요」를 쓴다
        #expect(reservationStatusTitle(loading: false, locating: false, failed: false) == nil)
    }

    /// 걸러내기 전의 목록에 내 방이 있었으면 「예약이 없어요」는 **거짓말**이다.
    @Test("내 방을 빼서 비었으면 그렇게 말한다")
    func emptyBecauseMyPartyHidden() {
        let (title, _) = reservationEmptyCopy(mode: .byDate, dateLabel: "오늘", myPartyHidden: true)

        #expect(title == "지금은 내 방뿐이에요")
    }

    // ─────────────────────────── 내 방 걸러내기 ───────────────────────────

    /// 내가 만든 예약 방은 검색 결과에 **그대로 들어온다** — 남의 방과 같은 「합류」 카드로 보이면
    /// 그 버튼이 거짓이다(20 이 409 `ALREADY_JOINED` 로 돌려보낸다).
    @Test("내 방은 예약 목록에서 빠진다")
    func myPartyIsRemovedFromFeed() {
        let items = [
            ReservationCardUi(ride: ride(id: "11")),
            ReservationCardUi(ride: ride(id: "22")),
        ]

        let feed = reservationFeed(items: items, myPartyId: "22")

        #expect(feed.items.map(\.ride.id) == ["11"])
        #expect(feed.myPartyHidden)
    }

    /// id 는 **숫자로 먼저** 본다 — 목록 `partyId` 와 상세 `id` 의 문자열 모양이 어긋날 수 있다.
    @Test("id 문자열 모양이 달라도 같은 방으로 본다")
    func idShapeMismatchStillMatches() {
        let feed = reservationFeed(items: [ReservationCardUi(ride: ride(id: "22"))], myPartyId: "022")

        #expect(feed.items.isEmpty)
        #expect(feed.myPartyHidden)
    }

    @Test("진행 중인 방이 없으면 아무것도 빼지 않는다")
    func noActivePartyKeepsAll() {
        let items = [ReservationCardUi(ride: ride(id: "11"))]

        for myPartyId in [nil, "", "   "] as [String?] {
            let feed = reservationFeed(items: items, myPartyId: myPartyId)
            #expect(feed.items == items)
            #expect(!feed.myPartyHidden)
        }
    }

    // ───────────────── 「＋ 새 동승 방 만들기」가 어떤 모달을 여는가 ─────────────────

    /// 못 박는 것 둘을 한 표로 본다.
    ///
    /// 1. **예약 탭에서 만들면 시간 정하기로 열린다.** 예약 방을 찾다가 없어서 만들러 가는 사람인데
    ///    「지금 출발」로 열리면, 화면이 방금까지 한 일을 잊은 꼴이고 사용자는 모달에서 「시간
    ///    정하기」를 한 번 더 눌러야 한다. 그 한 번을 없앤다.
    /// 2. **실시간 탭은 지금까지와 같다.** 이 변경이 기존 흐름을 건드리지 않는다는 쪽이 더 중요하다.
    ///
    /// 표로 적은 이유: 모드가 늘면 **첫 단언에서 걸린다**(`allCases` 와 표의 키가 어긋난다). 컴파일은
    /// `switch` 가 빠진 가지를 잡아 이미 막아 주지만, 그건 「분기를 적었는가」까지다 — 어느 쪽으로 적었는지는
    /// 이 표가 지킨다.
    @Test("탭마다 여는 모달이 정해져 있다")
    func createOpensScheduledPerTab() {
        let expected: [ExploreMode: Bool] = [
            .realtime: false,
            .soon: true,
            .byDate: true,
        ]

        #expect(Set(ExploreMode.allCases) == Set(expected.keys), "새 탭이 생겼는데 이 표에 없다")
        for (mode, scheduled) in expected {
            #expect(createOpensScheduled(mode: mode) == scheduled, "\(mode)")
        }
    }
}
