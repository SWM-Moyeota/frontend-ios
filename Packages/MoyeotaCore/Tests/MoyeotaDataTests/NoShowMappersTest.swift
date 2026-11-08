import Foundation
import MoyeotaDomain
import Testing
@testable import MoyeotaData

// 운영과 같은 디코더(`MoyeotaJSON`)로 읽는다 — 서버가 필드를 추가해도 파싱이 깨지지 않아야 한다.
@Suite struct NoShowMappersTest {

    /// 백엔드 `MyNoShowListResponse(List<NoShowItem> noShows)` 모양 그대로.
    ///
    /// 본문은 서버 컨트롤러 테스트(`NoShowControllerUnitTest`)가 와이어로 못 박은 값과 같다 —
    /// 두 줄 중 하나는 이의를 안 낸 건(`objectionStatus: null`), 하나는 인정돼 무효가 된 건
    /// (`voided: true`, `ACCEPTED`)이다.
    @Test("노쇼 목록 JSON 을 실제 서버 shape 그대로 역직렬화한다")
    func decodesServerShape() throws {
        let body = """
            {"noShows":[
              {"partyId":7,"departure":"서울시청","destination":"강남역",
               "meetingAt":"2026-11-03T08:30:00Z","noShowAt":"2026-11-03T08:40:00Z",
               "voided":false,"objectionStatus":null},
              {"partyId":5,"departure":"성결대 정문","destination":"안양역",
               "meetingAt":"2026-11-01T08:30:00Z","noShowAt":"2026-11-01T08:45:00Z",
               "voided":true,"objectionStatus":"ACCEPTED"}
            ]}
            """

        let records = try decodeJSON(MyNoShowListResponse.self, body).noShows.map { $0.toDomain() }

        try #require(records.count == 2)
        #expect(records[0].partyId == 7)
        #expect(records[0].departure == "서울시청")
        #expect(records[0].destination == "강남역")
        // 시각은 **파싱하지 않고** 문자열 그대로 흐른다 — 사람이 읽을 모양은 화면이 만든다.
        #expect(records[0].meetingAt == "2026-11-03T08:30:00Z")
        #expect(records[0].noShowAt == "2026-11-03T08:40:00Z")
        #expect(!records[0].isVoided)
        #expect(records[0].objectionStatus == nil)

        #expect(records[1].partyId == 5)
        #expect(records[1].isVoided)
        #expect(records[1].objectionStatus == .accepted)
    }

    /// **엔벨로프 키가 `noShows` 다 — `list` 가 아니다.** 같은 매칭 도메인의 방 목록과 예약 목록은
    /// 둘 다 `list` 를 쓰므로 베껴 쓰기 쉬운 자리이고, 틀리면 디코더가 모르는 키를
    /// 흘려서 **에러 없이 항상 빈 목록**이 된다 — 화면은 「노쇼 기록이 없어요」라는 **틀린 좋은
    /// 소식**을 말하고, 제재당한 사용자는 근거를 영원히 못 본다.
    ///
    /// 그래서 「틀린 키가 먹히지 않음」까지 함께 못 박는다(`arrived`/`isArrived` 와 같은 수법).
    @Test("엔벨로프 키가 list 면 아무것도 읽히지 않는다 — 계약 키는 noShows 다")
    func listEnvelopeIsNotRead() throws {
        let wrongKey = #"{"list":[{"partyId":7,"departure":"서울시청","destination":"강남역","voided":false}]}"#

        let decoded = try decodeJSON(MyNoShowListResponse.self, wrongKey)

        #expect(decoded.noShows.isEmpty, "list 키가 noShows 로 읽혔다 — 두 엔벨로프가 섞였다")
    }

    /// **키 이름은 `voided` 다**(서버 record 컴포넌트 이름 그대로). 도메인 객체에는 `isVoided()` 가
    /// 있지만 그건 직렬화되지 않고, 와이어에는 `voided` 하나만 실린다.
    ///
    /// `isVoided` 로 적으면 디코더가 모르는 키로 흘려서 **조용히 늘 false** 가 되고, 무효로 돌려진
    /// 노쇼에 이의 신청 버튼이 다시 뜬다(눌러도 409 `NOT_NO_SHOW`). `arrived`/`isArrived`,
    /// `host`/`isHost` 와 **같은 함정**이라 여기서도 틀린 이름이 먹히지 않음을 값으로 막는다.
    @Test("isVoided 라는 키는 무효로 읽히지 않는다 — 계약 키는 voided 다")
    func isVoidedKeyIsNotRead() throws {
        let wrongName = """
            {"noShows":[{"partyId":7,"departure":"서울시청","destination":"강남역","isVoided":true}]}
            """

        let record = try decodeJSON(MyNoShowListResponse.self, wrongName).noShows.single().toDomain()

        #expect(!record.isVoided, "isVoided 키가 voided 로 읽혔다 — 계약 키가 바뀐 것이 아니면 버그다")

        // 맞는 이름은 당연히 읽혀야 한다(위 단정이 "그냥 늘 false" 라서 통과한 게 아님을 보인다).
        let right = #"{"noShows":[{"partyId":7,"voided":true}]}"#
        #expect(try decodeJSON(MyNoShowListResponse.self, right).noShows.single().toDomain().isVoided)
    }

    /// 세 상태 문자열이 하나씩 짝으로 옮겨진다.
    @Test("이의 상태 세 값을 그대로 매핑한다")
    func mapsThreeStatuses() {
        #expect(toObjectionStatus(status: "PENDING") == .pending)
        #expect(toObjectionStatus(status: "ACCEPTED") == .accepted)
        #expect(toObjectionStatus(status: "REJECTED") == .rejected)
    }

    /// ### 이 테스트가 이 파일에서 가장 중요하다 ★
    /// 모르는 문자열은 **nil** 이어야 한다 — `ObjectionStatus.pending` 으로 떨어뜨리면 화면이
    /// 「심사 중이에요, 결과를 기다려 주세요」라고 **없는 사실을 단정**하고, 그 줄에서 이의 신청
    /// 버튼이 사라지므로(노출 조건이 `objectionStatus == nil`) 사용자는 다시 낼 길을 잃는다.
    ///
    /// 이 앱의 다른 문자열 변환들(`partyStatusToRideStatus` → recruiting,
    /// `toRoomType` → realtime)은 모르는 값을 **값으로** 떨어뜨리므로, 그 패턴을 베끼면 정확히
    /// 위의 실패가 된다. 그래서 방향을 값으로 못 박는다.
    @Test("모르는 상태 문자열은 PENDING 이 아니라 null 이다")
    func unknownStatusIsNil() {
        #expect(toObjectionStatus(status: "UNDER_REVIEW") == nil, "서버가 새 상태를 추가하면 null 이어야 한다")
        #expect(toObjectionStatus(status: "WITHDRAWN") == nil)
        // 대소문자·앞뒤 공백 외의 변형도 모르는 값이다 — 추측해서 맞추지 않는다.
        #expect(toObjectionStatus(status: "pending") == nil)
        #expect(toObjectionStatus(status: "Accepted") == nil)
    }

    /// nil·빈 문자열·공백은 모두 「안 냈다」 한 가지 모양이다.
    @Test("상태가 없거나 공백이면 안 낸 것으로 읽는다")
    func blankStatusIsNil() {
        #expect(toObjectionStatus(status: nil) == nil)
        #expect(toObjectionStatus(status: "") == nil)
        #expect(toObjectionStatus(status: "   ") == nil)
    }

    /// 앞뒤 공백이 섞여 와도 상태는 읽는다 — 「모르는 값」과 「공백이 붙은 아는 값」은 다르다.
    @Test("앞뒤 공백이 붙은 상태도 읽는다")
    func paddedStatusIsRead() {
        #expect(toObjectionStatus(status: " PENDING ") == .pending)
    }

    /// 모르는 상태가 섞여도 **그 줄만** 상태를 잃고 나머지는 멀쩡해야 한다.
    /// DTO 필드를 `Decodable` enum 으로 선언했다면 여기서 **역직렬화가 터져** 목록 전체가
    /// 날아간다 — 서버가 상태를 하나 추가하는 날 노쇼 화면이 통째로 죽는다는 뜻이다.
    @Test("모르는 상태가 섞여도 목록 전체가 날아가지 않는다")
    func unknownStatusKeepsList() throws {
        let body = """
            {"noShows":[
              {"partyId":7,"voided":false,"objectionStatus":"UNDER_REVIEW"},
              {"partyId":5,"voided":false,"objectionStatus":"PENDING"}
            ]}
            """

        let records = try decodeJSON(MyNoShowListResponse.self, body).noShows.map { $0.toDomain() }

        try #require(records.count == 2)
        #expect(records[0].objectionStatus == nil)
        #expect(records[1].objectionStatus == .pending)
    }

    /// 빈 배열은 **정상 응답**이다(노쇼가 없으면 서버가 404 가 아니라 `{"noShows":[]}` 를 준다).
    /// 예외로 바꾸면 기록이 없는 사용자에게 제재 화면이 에러로 보인다.
    @Test("빈 노쇼 목록도 정상 파싱된다")
    func emptyList() throws {
        #expect(try decodeJSON(MyNoShowListResponse.self, #"{"noShows":[]}"#).noShows.isEmpty)
        // 키 자체가 없는 응답(구버전·프록시)도 빈 목록으로 떨어진다.
        #expect(try decodeJSON(MyNoShowListResponse.self, "{}").noShows.isEmpty)
    }

    /// 시각 둘이 null 이어도 파싱이 살아야 한다. `meetingAt` 은 서버 쿼리가 방의 nullable 컬럼
    /// (`departureAt`)을 집어 오는 값이고, 실제로는 노쇼가 약속이 정해진 방에서만 나오므로 비어 올 수
    /// 없지만 — non-null 로 선언하면 **그 한 줄이 목록 전체의 파싱을 터뜨린다.** 비용 0 의 방어다.
    @Test("시각이 null 이어도 파싱되고 나머지 필드가 살아 있다")
    func nullTimes() throws {
        let body = """
            {"noShows":[{"partyId":7,"departure":"서울시청","destination":"강남역",
             "meetingAt":null,"noShowAt":null,"voided":false,"objectionStatus":null}]}
            """

        let record = try decodeJSON(MyNoShowListResponse.self, body).noShows.single().toDomain()

        #expect(record.meetingAt == nil)
        #expect(record.noShowAt == nil)
        #expect(record.partyId == 7)
    }

    /// 이름이 빠지면 도메인에서는 **빈 문자열**이다(nil 이 아니다) — 화면이 nil 을 또 확인하지
    /// 않게 하는 `RideRecordMappers` 와 같은 관례이고, `NoShowRecordsDisplay` 의 경로 문구가
    /// 공백 여부로만 분기하는 근거다.
    @Test("이름이 빠지면 빈 문자열로 접는다")
    func missingNamesFoldToEmpty() {
        let record = NoShowItemDto(partyId: 7).toDomain()

        #expect(record.departure == "")
        #expect(record.destination == "")
    }

    /// ⚠️ 소수점 아래가 붙은 시각(`timestamp(6)` 컬럼이라 가능하다)도 **문자열 그대로** 흘러야 한다.
    /// 이 계층이 파싱하지 않는 것이 그 대비다 — 화면은 소수 초 유무를 모두 받는 파서로 읽는다.
    @Test("마이크로초가 붙은 시각도 그대로 흐른다")
    func microsecondsFlowVerbatim() throws {
        let body = """
            {"noShows":[{"partyId":7,"meetingAt":"2026-11-03T08:30:00.123456Z",
             "noShowAt":"2026-11-03T08:40:00.654321Z","voided":false}]}
            """

        let record = try decodeJSON(MyNoShowListResponse.self, body).noShows.single().toDomain()

        #expect(record.meetingAt == "2026-11-03T08:30:00.123456Z")
        #expect(record.noShowAt == "2026-11-03T08:40:00.654321Z")
    }

    /// 서버가 필드를 늘려도 파싱이 살아야 한다. DTO 가 가진 필드를 쓰면
    /// "모르는 필드"가 아니게 되어 아무것도 검사하지 않는 테스트가 되므로 **없는 이름**을 쓴다.
    @Test("모르는 필드가 늘어나도 파싱이 깨지지 않는다")
    func unknownFields() throws {
        let body = """
            {"noShows":[{"partyId":7,"voided":false,"noShowId":42,"reviewerNote":"x"}],"total":1}
            """

        #expect(try decodeJSON(MyNoShowListResponse.self, body).noShows.single().toDomain().partyId == 7)
    }

    /// **항목을 버리지 않는다.** 실시간 후보 매퍼는 방 id 가 없는 항목을 버리는데(탭해도 갈 곳이
    /// 없다) 여기서는 남긴다 — 이 줄의 쓸모는 탭이 아니라 **제재의 근거를 보여 주는 것**이고,
    /// 제재당한 사용자에게 설명을 빼먹는 쪽이 훨씬 나쁘다. 이의 신청 버튼만 못 누르게 하면 된다.
    @Test("방 id 가 없는 항목도 버리지 않는다")
    func keepsItemWithoutPartyId() throws {
        let body = #"{"noShows":[{"departure":"서울시청","destination":"강남역","voided":false}]}"#

        let records = try decodeJSON(MyNoShowListResponse.self, body).noShows.map { $0.toDomain() }

        #expect(records.count == 1)
        #expect(try records.single().partyId == 0)
        #expect(try records.single().departure == "서울시청")
    }
}
