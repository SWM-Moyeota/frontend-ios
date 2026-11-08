import Testing
@testable import FeatureHome

/// 16 도착지 확인이 방 생성으로 넘기는 **조건의 목록**을 못 박는다.
///
/// 왜 테스트가 필요한가: 반경 칩을 되살려도 화면은 멀쩡히 돌고 서버는 200 을 준다
/// (서버가 모르는 키를 흘리므로). 즉 **고른 값이 버려지는 상태에 아무 증상이 없다.**
/// 그래서 목록을 여기서 고정한다 — 새 조건을 붙이려면 이 테스트를 함께 고쳐야 하고,
/// 그때 「서버가 그 값을 실제로 쓰는가」를 다시 묻게 된다.
///
/// ### 2026-11-06 — `departureAt` 이 늘었고, 그 질문에 답한 기록 ★
/// 서버가 **쓴다.** `POST /api/v1/matching/reservations` 의 `departureAt` 은 필수이고 방의 출발
/// 시각이 된다(`OpenReservationRequest`). 반경 칩과 다른 점이 여기다 — 반경은 서버가 받기만 하고
/// 버렸다(고정 500m).
///
/// 그리고 이 값은 **엔드포인트를 고른다**: nil 이면 `POST /matching/rooms`(실시간), 값이 있으면
/// 예약이다. 그래서 실시간 요청 본문은 예전 그대로이고, 그 사실은 짝 테스트가 지킨다 —
/// `NewParty` 에는 이 필드가 **없다.**
///
/// 짝이 되는 테스트는 data 쪽의 `PartyMappersTest.생성 요청 본문에는 좌표 라벨 정원만 실린다` 다
/// (요청 JSON 의 키 집합). 이쪽은 **화면이 들고 있는 조건**, 저쪽은 **전선에 실리는 본문**이다.
@Suite struct MatchConditionsTest {

    @Test("방 생성으로 넘기는 조건은 정원과 출발 시각뿐이다")
    func onlyCapacityAndDepartureAt() {
        let fields = Mirror(reflecting: MatchConditions(capacity: 3)).children.map(\.label)

        #expect(fields == ["capacity", "departureAt"])
    }
}
