@testable import FeatureMatching
import MoyeotaDomain
import Testing

/// 약속 확정·출발지 도착·출발 **실패 안내** — 방을 다루는 실패 문구의 **전부**다.
///
/// 넷째였던 「합승 완료」(`FinishFailureMessageTest`)는 **파일째 사라졌다** — 서버가 `/finish` 를
/// 없앴다(`b16551b7`). 그 파일이 세운 규칙 둘(「403·409 에 재시도 안내를 붙이지 않는다」·「사유마다
/// 다른 말을 한다」)은 **여기 아래 세 액션에 그대로 살아 있다**(3·4번) — 규칙이 무효가 된 게 아니라
/// 적용 대상만 줄었다. 그 파일이 들던 사유 중 `NOT_PARTY_HOST` 는 **출발 쪽으로 옮겨 왔다**
/// (출발이 방장 전용이 됐다).
///
/// 네 가지를 못 박는다.
/// 1. **서버 코드로만 가른다.** HTTP 상태로 추측하지 않는다 — 확정은 403 이 두 가지 뜻
///    (`NOT_PARTY_HOST`/`NOT_PARTY_MEMBER`)이고 409 가 네 가지라, 상태로 고르면 반드시 절반은
///    틀린 말이 된다. 분기 근거는 도메인이 코드를 한 번 걸러 준 `is…` 프로퍼티이고, 이 파일은
///    **코드 문자열로 예외를 만들어** 넣는다 — `httpStatus` 는 넣지 않는다(보지 않으므로).
/// 2. **모르는 코드는 일반 문구로 떨어진다.** 서버가 `MatchingErrorCode` 를 늘려도 앱이 지어내지
///    않는다 — 모른다고 하는 편이 낫다.
/// 3. **403·409 에 「다시 시도」류를 붙이지 않는다.** 다시 눌러도 같은 답이다. 이 저장소는 거짓 문구
///    19건을 들어낸 이력이 있고(`ProductClaimsTest`), 재시도 안내가 그중 가장 위험한 종류다.
/// 4. **사유마다 다른 말을 한다.** 같은 문구가 두 갈래에 쓰이면 분기한 의미가 없다.
///
/// 코드 문자열의 근거는 백엔드 `MatchingErrorCode`(enum 이름이 그대로 `getCode()`)와 작업 지시에
/// 실린 엔드포인트별 에러 목록이다.
struct MeetingFailureMessageTest {
    /// 코드 하나로 예외를 만든다. `httpStatus` 는 **일부러 틀리게 두지 않는다** — 넣지 않는다.
    /// 이 세 문구 함수는 상태 코드를 **아예 보지 않으므로**(분기는 도메인의 `is…` 프로퍼티다)
    /// 값을 넣어도 결과가 달라지지 않고, 넣으면 「상태도 보는가」를 헷갈리게 만든다.
    private func confirm(_ code: String?) -> PartyConfirmException {
        PartyConfirmException(code: code, serverMessage: nil)
    }

    private func arrive(_ code: String?) -> PartyArriveException {
        PartyArriveException(code: code, serverMessage: nil)
    }

    private func depart(_ code: String?) -> PartyDepartException {
        PartyDepartException(code: code, serverMessage: nil)
    }

    // ─────────────────────── 약속 확정 ───────────────────────

    private let confirmGeneral = "약속 시간을 정하지 못했어요"

    private let confirmCodes: [String?] = [
        PartyConfirmException.INVALID_MEETING_TIME,
        PartyConfirmException.NOT_PARTY_HOST,
        PartyConfirmException.NOT_PARTY_MEMBER,
        PartyConfirmException.NOT_REALTIME_PARTY,
        PartyConfirmException.ALREADY_CONFIRMED,
        // `PARTY_NOT_RECRUITING` 이었다 — 서버가 단계 검사를 `validateOpen()` 하나로 묶으면서
        // 코드를 통일했다(`b16551b7`). 사용자 문구는 그대로다.
        PartyConfirmException.PARTY_CLOSED,
        PartyConfirmException.NOT_ENOUGH_MEMBERS,
        PartyConfirmException.PARTY_NOT_FOUND,
    ]

    /// 🔴 **범위가 「1시간 안」에서 「5분 뒤 ~ 1시간」으로 바뀌었다** — 서버가 **하한을 새로 만들었다**.
    ///
    /// 옛 문구는 「약속 시간은 지금부터 1시간 안이어야 해요. **더 가까운 시간**으로 골라 주세요」였고,
    /// 그때는 어길 방향이 하나(상한 초과)였으므로 그 권유가 늘 맞았다. 하한이 생긴 뒤로 이 400 은
    /// **양쪽에서** 온다 — 다이얼로그를 **5분 넘게** 열어 두면 10분 프리셋이 하한 아래로 내려간다
    /// (캡처한 시각을 보내므로 시간이 지나도 값이 따라오지 않는다 — 그게 맞는 설계다).
    ///
    /// 그 경우에 「더 가까운 시간」을 권하면 **반대 방향으로 보내게 된다**: 더 가까운 것을 고르면
    /// 더 깊이 하한 아래다. 그래서 범위를 그대로 적고 **다시 고르게** 한다.
    @Test("약속 시간 범위를 벗어났으면 범위를 적고 다시 고르라고 말한다")
    func invalidMeetingTime() {
        let message = confirmFailureMessage(e: confirm(PartyConfirmException.INVALID_MEETING_TIME))

        #expect(message == "약속 시간은 지금부터 10분 ~ 1시간 뒤여야 해요. 다시 골라 주세요")
        #expect(message.contains("1시간"), "서버 상한을 숫자로 말해야 한다")
        #expect(message.contains("10분"), "하한도 말해야 한다 — 어기는 방향이 둘이다")
        // 🔴 한쪽 방향만 권하지 않는다 — 하한 아래에서 「더 가까운 시간」은 반대 방향이다
        #expect(!message.contains("더 가까운"), "한 방향만 권한다: \(message)")
    }

    /// 프리셋 안내와 거절 문구가 **같은 범위**를 말해야 한다 — 한쪽만 고치면 앱이 서버와 다른
    /// 약속을 하고, 사용자는 「10분부터라더니 왜 거절되지」를 묻게 된다.
    @Test("프리셋 안내와 거절 문구가 같은 범위를 말한다")
    func presetNoteMatchesRejection() {
        #expect(MEETING_PRESET_LIMIT_NOTE.contains("10분"), "\(MEETING_PRESET_LIMIT_NOTE)")
        #expect(MEETING_PRESET_LIMIT_NOTE.contains("1시간"), "\(MEETING_PRESET_LIMIT_NOTE)")
        #expect(MEETING_PRESET_MINUTES == [10, 20, 30, 45, 60])
    }

    /// 「방장만」으로 끝내면 사용자가 할 수 있는 일이 없다 — **누가 눌러야 하는지**가 핵심이다.
    /// 이름을 쓰지 않는 근거는 `departFailureMessage` 의 같은 403 과 같다: 내 스냅샷이 가리킨 방장이
    /// 서버 기준으로 더 이상 방장이 아니라는 뜻이라, 그 스냅샷으로 이름을 부르면 **틀린 사람에게
    /// 부탁하라고 말하게 된다.**
    @Test("방장만 약속을 정할 수 있다 - 누가 눌러야 하는지 말한다")
    func confirmNotHost() {
        let message = confirmFailureMessage(e: confirm(PartyConfirmException.NOT_PARTY_HOST))

        #expect(message == "방장만 약속 시간을 정할 수 있어요. 가장 먼저 참여한 분에게 부탁해 주세요")
        #expect(message.contains("가장 먼저 참여한"))
    }

    /// 같은 403 이지만 뜻이 다르다 — 멤버가 아닌 사람에게 방장을 찾으라고 하면 안 된다.
    @Test("확정 - 멤버가 아니다는 방장 안내로 뭉개지 않는다")
    func confirmNotMember() {
        let message = confirmFailureMessage(e: confirm(PartyConfirmException.NOT_PARTY_MEMBER))

        #expect(message == "이 방의 참여자가 아니에요. 홈에서 진행 중인 방을 확인해 주세요")
        #expect(!message.contains("방장"), "방장 안내와 섞이면 안 된다")
    }

    /// 서버는 실시간 방만 받는다(409 `NOT_REALTIME_PARTY`). 예약 방이 **대신 무엇을 하는지는 앱이
    /// 모르므로** 말하지 않는다 — 서버가 말한 사실(실시간 방에서만 된다)까지가 전부다.
    @Test("실시간 방이 아니면 서버가 말한 조건만 적는다")
    func confirmNotRealtime() {
        let message = confirmFailureMessage(e: confirm(PartyConfirmException.NOT_REALTIME_PARTY))

        #expect(message == "실시간으로 모인 방에서만 약속 시간을 정할 수 있어요")
        // 예약 방이 어떤 흐름인지 앱은 모른다 — 지어내지 않는다
        #expect(!message.contains("예약"), "\(message)")
    }

    /// 404 와 409 를 **갈라 둔다** — 「사라진 방」과 「끝난 방」은 다른 사실이고, 할 일만 같다.
    @Test("이미 정해진 방 · 끝난 방 · 2명 미만 · 사라진 방")
    func confirmOtherReasons() {
        func message(_ code: String) -> String { confirmFailureMessage(e: confirm(code)) }

        #expect(message(PartyConfirmException.ALREADY_CONFIRMED) == "이미 약속 시간이 정해진 방이에요")
        #expect(message(PartyConfirmException.PARTY_CLOSED) == "이미 끝난 방이에요. 홈으로 돌아가 주세요")
        #expect(message(PartyConfirmException.NOT_ENOUGH_MEMBERS) == "2명 이상 모여야 약속 시간을 정할 수 있어요")
        #expect(message(PartyConfirmException.PARTY_NOT_FOUND) == "이미 사라진 방이에요. 홈으로 돌아가 주세요")
    }

    @Test("확정 - 모르는 코드는 일반 문구로 떨어진다")
    func confirmUnknownCode() {
        #expect(confirmFailureMessage(e: confirm("MEETING_SOMETHING_NEW")) == confirmGeneral)
        #expect(confirmFailureMessage(e: confirm(nil)) == confirmGeneral)
        // 다른 액션의 코드가 섞여 와도 지어내지 않는다
        #expect(confirmFailureMessage(e: confirm(PartyDepartException.NOT_ARRIVED)) == confirmGeneral)
    }

    @Test("확정 - 사유마다 다른 말을 한다")
    func confirmDistinct() {
        let messages = (confirmCodes + [nil]).map { confirmFailureMessage(e: confirm($0)) }
        #expect(Set(messages).count == messages.count)
    }

    // ─────────────────────── 출발지 도착 ───────────────────────

    private let arriveGeneral = "도착을 알리지 못했어요"

    private let arriveCodes: [String?] = [
        PartyArriveException.TOO_FAR_FROM_DEPARTURE,
        PartyArriveException.OUT_OF_SERVICE_AREA,
        PartyArriveException.NOT_PARTY_MEMBER,
        PartyArriveException.PARTY_CLOSED,
        PartyArriveException.PARTY_NOT_CONFIRMED,
        PartyArriveException.ARRIVAL_NOT_OPEN,
        PartyArriveException.PARTY_NOT_FOUND,
    ]

    /// ★ **이 가지가 도착 문구의 존재 이유다.** 앱은 거리를 재지 않는다(재면 서버와 다른 두 번째
    /// 진실이 생긴다 — `canArriveAtDeparture` 주석). 그래서 「멀다」는 사실을 사용자에게 말해 줄 수
    /// 있는 자리가 **여기 하나뿐**이고, 숫자가 없으면 10m 를 더 가야 하는지 300m 를 더 가야 하는지
    /// 알 수 없다. 그 숫자는 앱이 고른 값이 아니라 **서버가 PostGIS 로 재는 값**이다.
    @Test("출발지에서 멀면 서버가 재는 거리를 숫자로 말한다")
    func tooFarFromDeparture() {
        let message = arriveFailureMessage(e: arrive(PartyArriveException.TOO_FAR_FROM_DEPARTURE), roomType: .realtime)

        #expect(message == "출발지에서 100m 안에 있어야 도착을 알릴 수 있어요. 출발지로 더 가까이 가 주세요")
        #expect(message.contains("100m"), "서버가 재는 거리를 말해야 한다")
        #expect(message.contains("가까이"), "무엇을 해야 하는지 말해야 한다")
    }

    /// 🔴 ★ **그 숫자가 방 종류로 갈린다** — 실시간 100m · 예약 400m(서버 `Party` 의 두 상수).
    ///
    /// 오래 「100m」 하나로 박혀 있었다. 서버가 예약 방의 반경을 400m 로 넓혔다(`b16551b7`) —
    /// 예약 방의 출발지는 **장소 검색 결과의 중심점**이고 확정으로 옮길 수도 없어서(409
    /// `NOT_REALTIME_PARTY`) 역 중심점에서 100m 를 요구하면 그 역에 서 있는 사람이 도착을 알릴 수 없다.
    ///
    /// 틀렸을 때 드러나지 않는 종류의 거짓이라 값으로 못 박는다: 서버는 받아 주는데 앱이
    /// 「100m 안에 있어야 한다」고 적으면, 사용자는 **이미 통과하는 위치에서 더 걸어간다.**
    @Test("도착 반경 숫자는 방 종류로 갈린다")
    func arrivalRadiusByRoomType() {
        let realtime = arriveFailureMessage(e: arrive(PartyArriveException.TOO_FAR_FROM_DEPARTURE), roomType: .realtime)
        let reservation = arriveFailureMessage(
            e: arrive(PartyArriveException.TOO_FAR_FROM_DEPARTURE),
            roomType: .reservation
        )

        #expect(realtime.contains("100m"), "\(realtime)")
        #expect(reservation.contains("400m"), "\(reservation)")
        #expect(arrivalRadiusMeters(roomType: .realtime) == 100)
        #expect(arrivalRadiusMeters(roomType: .reservation) == 400)
        // 권한 안내도 같은 숫자를 말해야 한다 — 한쪽만 고치면 두 자리가 다른 약속을 한다.
        #expect(arriveNeedsPermissionNotice(roomType: .realtime).contains("100m"))
        #expect(arriveNeedsPermissionNotice(roomType: .reservation).contains("400m"))
    }

    @Test("도착 - 서비스 지역 · 멤버 아님 · 닫힌 방 · 확정 전 · 창 안 열림 · 사라진 방")
    func arriveOtherReasons() {
        func message(_ code: String) -> String { arriveFailureMessage(e: arrive(code), roomType: .realtime) }

        #expect(message(PartyArriveException.OUT_OF_SERVICE_AREA) == "서비스 지역을 벗어난 위치예요")
        #expect(
            message(PartyArriveException.NOT_PARTY_MEMBER)
                == "이 방의 참여자가 아니에요. 홈에서 진행 중인 방을 확인해 주세요"
        )
        #expect(message(PartyArriveException.PARTY_CLOSED) == "이미 끝난 방이에요. 홈으로 돌아가 주세요")
        #expect(message(PartyArriveException.PARTY_NOT_CONFIRMED) == "아직 약속 시간이 정해지지 않았어요")
        #expect(message(PartyArriveException.ARRIVAL_NOT_OPEN) == "약속 10분 전부터 도착을 알릴 수 있어요")
        #expect(message(PartyArriveException.PARTY_NOT_FOUND) == "이미 사라진 방이에요. 홈으로 돌아가 주세요")
    }

    /// 화면 안내와 서버 거절이 **같은 숫자**를 말해야 한다 — 한쪽만 고치면 앱이 서버와 다른 약속을 한다.
    @Test("도착 창 안내와 거절 문구가 같은 숫자를 말한다")
    func arrivalWindowSameNumber() {
        #expect(ARRIVE_NOT_OPEN_NOTICE.contains("10분"))
        #expect(arriveFailureMessage(e: arrive(PartyArriveException.ARRIVAL_NOT_OPEN), roomType: .realtime).contains("10분"))
        #expect(ARRIVAL_OPENS_MINUTES_BEFORE == 10)
    }

    @Test("도착 - 모르는 코드는 일반 문구로 떨어진다")
    func arriveUnknownCode() {
        #expect(arriveFailureMessage(e: arrive("ARRIVE_SOMETHING_NEW"), roomType: .realtime) == arriveGeneral)
        #expect(arriveFailureMessage(e: arrive(nil), roomType: .realtime) == arriveGeneral)
        #expect(arriveFailureMessage(e: arrive(PartyConfirmException.NOT_PARTY_HOST), roomType: .realtime) == arriveGeneral)
    }

    @Test("도착 - 사유마다 다른 말을 한다")
    func arriveDistinct() {
        let messages = (arriveCodes + [nil]).map { arriveFailureMessage(e: arrive($0), roomType: .realtime) }
        #expect(Set(messages).count == messages.count)
    }

    // ─────────────────────── 출발 ───────────────────────

    private let departGeneral = "출발하지 못했어요"

    private let departCodes: [String?] = [
        PartyDepartException.NOT_ARRIVED,
        // `b16551b7` 에서 **새로 생긴 사유** — 출발이 방장 전용이 됐다. 옛
        // `FinishFailureMessageTest` 가 들고 있던 그 403 이 이쪽으로 옮겨 온 것이다.
        PartyDepartException.NOT_PARTY_HOST,
        PartyDepartException.MEETING_NOT_STARTED,
        PartyDepartException.NOT_ENOUGH_MEMBERS,
        PartyDepartException.PARTY_NOT_CONFIRMED,
        PartyDepartException.PARTY_CLOSED,
        PartyDepartException.NOT_PARTY_MEMBER,
        PartyDepartException.PARTY_NOT_FOUND,
    ]

    /// `NOT_ARRIVED` 가 **다음 행동을 알려 주는 유일한 가지**다 — 그 사람은 바로 위의
    /// 「출발지 도착했어요」를 누르면 된다. 버튼 이름을 그대로 적는 이유: 「도착을 알려야 한다」만
    /// 적으면 어디를 눌러야 하는지 찾아야 한다.
    @Test("도착하지 않았으면 눌러야 할 버튼 이름을 말한다")
    func departNotArrived() {
        let message = departFailureMessage(e: depart(PartyDepartException.NOT_ARRIVED))

        #expect(message == "먼저 「출발지 도착했어요」를 눌러야 출발할 수 있어요")
        #expect(message.contains("출발지 도착했어요"), "화면에 있는 버튼 이름이어야 한다")
    }

    /// 🔴 **방장만 출발할 수 있다** — `b16551b7` 에서 생긴 사유다. 「방장만」으로 끝내면 사용자가 할 수
    /// 있는 일이 없으므로 **누가 눌러야 하는지**까지 말한다.
    ///
    /// **이름을 쓰지 않는다**: 이 403 은 내 스냅샷이 가리킨 방장이 서버 기준으로 더 이상 방장이
    /// 아니라는 뜻이라, 그 스냅샷으로 이름을 부르면 **틀린 사람에게 부탁하라고** 말하게 된다.
    /// 버튼이 보이는 사람에게 이름으로 안내하는 자리는 `departHostNotice` 쪽이다
    /// (`WaitingHostNoticeTest` 가 두 자리가 같은 근거를 쓰는지 본다).
    @Test("방장만 출발할 수 있다 - 누가 눌러야 하는지 말하고 이름은 쓰지 않는다")
    func departNotHost() {
        let message = departFailureMessage(e: depart(PartyDepartException.NOT_PARTY_HOST))

        #expect(message == "방장만 출발할 수 있어요. 가장 먼저 참여한 분에게 부탁해 주세요")
        #expect(message.contains("가장 먼저 참여한"))
    }

    @Test("출발 - 닫힌 방 · 확정 전 · 2명 미만 · 약속 시간 전 · 멤버 아님 · 사라진 방")
    func departOtherReasons() {
        func message(_ code: String) -> String { departFailureMessage(e: depart(code)) }

        #expect(message(PartyDepartException.PARTY_CLOSED) == "이미 끝난 방이에요. 홈으로 돌아가 주세요")
        #expect(message(PartyDepartException.PARTY_NOT_CONFIRMED) == "아직 약속 시간이 정해지지 않았어요")
        #expect(message(PartyDepartException.NOT_ENOUGH_MEMBERS) == "2명 이상 모여야 출발할 수 있어요")
        #expect(message(PartyDepartException.MEETING_NOT_STARTED) == "약속 시간이 지나야 출발할 수 있어요")
        #expect(
            message(PartyDepartException.NOT_PARTY_MEMBER)
                == "이 방의 참여자가 아니에요. 홈에서 진행 중인 방을 확인해 주세요"
        )
        #expect(message(PartyDepartException.PARTY_NOT_FOUND) == "이미 사라진 방이에요. 홈으로 돌아가 주세요")
    }

    @Test("출발 - 모르는 코드는 일반 문구로 떨어진다")
    func departUnknownCode() {
        #expect(departFailureMessage(e: depart("DEPART_SOMETHING_NEW")) == departGeneral)
        #expect(departFailureMessage(e: depart(nil)) == departGeneral)
        #expect(departFailureMessage(e: depart(PartyArriveException.TOO_FAR_FROM_DEPARTURE)) == departGeneral)
    }

    @Test("출발 - 사유마다 다른 말을 한다")
    func departDistinct() {
        let messages = (departCodes + [nil]).map { departFailureMessage(e: depart($0)) }
        #expect(Set(messages).count == messages.count)
    }

    // ─────────────────────── 공통 금지 ───────────────────────

    private var allFailureMessages: [String] {
        (confirmCodes + [nil]).map { confirmFailureMessage(e: confirm($0)) }
            + (arriveCodes + [nil]).map { arriveFailureMessage(e: arrive($0), roomType: .realtime) }
            + (departCodes + [nil]).map { departFailureMessage(e: depart($0)) }
    }

    /// ★ **지키지 못할 약속을 넣지 않는다.** `FinishFailureMessageTest`(「합승 완료」와 함께 사라졌다)가
    /// 세운 금지를 세 액션에 그대로 적용한다 — 403·409 는 다시 눌러도 같은 답이고, 400 도 같은 자리에서 다시 누르면 같은
    /// 400 이다(사용자가 할 일은 재시도가 아니라 **이동**이거나 **다른 선택**이다).
    ///
    /// 세 문구 세트를 한 덩어리로 훑으므로 어느 액션에 재시도 안내가 섞여 들어와도 걸린다.
    @Test("다시 누르면 된다고 약속하지 않는다")
    func noRetryPromise() {
        for forbidden in ["잠시 후", "다시 시도", "다시 눌러", "재시도"] {
            for message in allFailureMessages {
                #expect(!message.contains(forbidden), "지키지 못할 약속이다: \(message)")
            }
        }
    }

    /// **없는 기능을 말하지 않는다.** 서버가 하는 일은 좌표를 받아 거리를 재고 방을 닫는 것뿐이다 —
    /// 알림을 보내거나, 가까워지면 자동으로 알려 주거나, 도착을 되돌려 주지 않는다.
    @Test("서버가 하지 않는 일을 약속하지 않는다")
    func noFeatureClaims() {
        for forbidden in ["자동으로", "알림을 보내", "알려 드려요", "취소할 수 있어요", "되돌릴 수 있어요"] {
            for message in allUserFacingCopy {
                #expect(!message.contains(forbidden), "없는 기능을 약속한다: \(message)")
            }
        }
    }

    /// 🔴 ★ **사라진 기능을 말하지 않는다** — 이 테스트가 이번 변경에서 새로 생긴 그물이다.
    ///
    /// 서버가 **노쇼 기능을 통째로 지웠고**(`b16551b7`, V37 이 테이블까지 떨어뜨린다) **「합승 완료」
    /// 경로(`/finish`)도 없앴다.** 그 둘을 말하는 문구가 이 화면에 여럿 있었다 — 확정 안내 두 줄,
    /// 출발 확인 다이얼로그, 나가기 실패 문구. 전부 **겁을 주거나 없는 버튼을 누르라고** 하는 거짓이고,
    /// 거짓인지를 화면만 봐서는 알 수 없다(서버가 거절하는 것도 아니고 그냥 거짓말이다).
    ///
    /// 금지어로 훑는 이유: 한 줄을 고쳐도 다음 사람이 옛 문구를 다시 들여올 수 있고, 그때 이 그물이
    /// 잡아 준다.
    @Test("서버에서 사라진 기능을 말하지 않는다")
    func noRemovedFeatureClaims() {
        for gone in ["노쇼", "합승 완료", "제재"] {
            for message in allUserFacingCopy {
                #expect(!message.contains(gone), "서버에 없는 기능을 말한다: \(message)")
            }
        }
    }

    /// 🔴 ★ **확정 안내가 「나갈 수 없다」고 말하지 않는다** — 이 테스트가 **정반대로 뒤집힌 자리**다.
    ///
    /// 예전 이름은 「확정 안내는 나갈 수 없게 된다는 것을 말한다」였고, 「확정이 되돌릴 수 없다는
    /// 사실을 버튼 앞과 다이얼로그가 둘 다 말해야 한다」가 근거였다. **서버가 그 규칙을 버렸다**
    /// (`b16551b7`: 「확정 방에서도 나갈 수 있고」).
    ///
    /// 뒤집힌 쪽을 못 박는 이유: 그 한 문장이 **사용자를 못 나가는 방에 묶인 것으로 믿게 만든다.**
    /// 서버가 허용하는 일을 앱이 말로 막는 셈이고, 그 거짓은 사용자가 나가기 버튼을 누르지 않는 쪽으로
    /// 이어져 **아무도 바로잡아 주지 않는다**(버튼의 거짓은 눌렀을 때 서버가 바로잡는다).
    ///
    /// 지금 사용자를 묶는 것은 **도착**이고, 그 말은 도착 버튼 앞에 있다(`ARRIVE_LOCKS_IN_NOTICE`).
    @Test("확정 안내는 나갈 수 없다고 말하지 않는다 - 묶는 것은 도착이다")
    func confirmCopyDoesNotSayNoLeaving() {
        for message in [MEETING_CONFIRM_HELP, MEETING_CONFIRM_DIALOG_BODY] {
            #expect(!message.contains("나갈 수 없"), "확정이 나가기를 막는다고 말한다: \(message)")
            #expect(message.contains("모집이 끝나"), "모집이 끝난다는 사실은 그대로다: \(message)")
        }
        // 묶는다는 말은 **도착 버튼 앞**에 있어야 한다 — 그 자리가 비면 누른 뒤에 알게 된다.
        #expect(ARRIVE_LOCKS_IN_NOTICE.contains("나갈 수 없"), "\(ARRIVE_LOCKS_IN_NOTICE)")
    }

    /// ★ 못 박는 것: **어떻게 끝내는지를 확정 전에 말한다 — 10분의 창까지.**
    ///
    /// 「확정하면 모집이 끝난다」만 말하면 사용자는 **그래서 어떻게 끝내는지**를 모른다. 약속이 깨져
    /// 아무도 출발지에 가지 않으면 방이 열린 채 남고, 그동안 서버가 다른 방 합류·방 만들기·예약까지
    /// 전부 막는다(`ALREADY_JOINED_OTHER_PARTY`). 스스로 풀 방법이 없으므로 **들어가기 전에 말하는
    /// 것이 유일한 방어**다.
    ///
    /// 「안 갔을 때의 대가(노쇼)」를 요구하던 줄은 **도착·출발 쪽으로 옮겼다** — 노쇼가 사라졌고
    /// 대가의 성격이 「제재」에서 「탑승 기록·정산에서 빠짐」으로 바뀌어, 그 말은 숫자를 아는
    /// `departConfirmMessage` 자리가 맞다(아래 테스트).
    ///
    /// **10분의 창**(도착은 10분 전부터, 출발은 약속 시각 뒤부터)을 확정 전에 말하는 이유: 그 두 문이
    /// 다른 시각에 열린다는 것을 모르면 「도착은 눌렀는데 출발이 안 되는」 구간이 고장으로 읽힌다.
    @Test("확정 안내는 끝내는 방법과 10분의 창을 말한다")
    func confirmCopySaysHowToEnd() {
        for message in [MEETING_CONFIRM_HELP, MEETING_CONFIRM_DIALOG_BODY] {
            #expect(message.contains("출발"), "끝내는 방법을 말하지 않는다: \(message)")
            #expect(message.contains("10분"), "도착 창이 언제 열리는지 말하지 않는다: \(message)")
        }
    }

    /// 🔴 ★ **출발 확인은 「노쇼로 기록된다」가 아니라 「탑승 기록·정산에서 빠진다」고 말한다.**
    ///
    /// 옛 문구: 「아직 도착하지 않은 2명은 **노쇼로 기록돼요** — 약속 시간부터 노쇼 횟수 × 24시간 동안
    /// 방·예약을 만들거나 참여할 수 없어요」. 그 제재는 **존재하지 않는 일**이 됐다(V37) — 남겨 두면
    /// 겁을 주고 그 겁이 거짓이다.
    ///
    /// **대가가 사라진 건 아니다**: 서버는 「도착을 누른 멤버 = 탑승자」로 세므로(`Party.riderIds`)
    /// 미도착자는 탑승 기록·탑승 횟수·택시비 정산에서 함께 빠진다. 그래서 **겁주지 않고 사실만**
    /// 적는다 — 처벌조가 아니라 「빠져요」로.
    ///
    /// 0명일 때 그 문장을 **아예 빼는** 것도 함께 못 박는다: 아무도 빠지지 않는데 빠진다고 말하면
    /// 다음에 정말 미도착자가 있을 때 같은 문구가 무게를 잃는다.
    @Test("출발 확인은 빠지는 것을 숫자로 말하고 겁주지 않는다")
    func departConfirmSaysWhatIsLost() {
        let withMissing = departConfirmMessage(notArrivedCount: 2)

        #expect(withMissing.contains("2명"), "\(withMissing)")
        #expect(withMissing.contains("탑승 기록"), "무엇에서 빠지는지 말해야 한다: \(withMissing)")
        #expect(withMissing.contains("정산"), "정산에서 빠지는 것이 실제 대가다: \(withMissing)")
        #expect(!withMissing.contains("노쇼"), "사라진 제재로 겁을 준다: \(withMissing)")
        #expect(!withMissing.contains("24시간"), "사라진 제재로 겁을 준다: \(withMissing)")

        let allArrived = departConfirmMessage(notArrivedCount: 0)
        #expect(!allArrived.contains("빠져요"), "아무도 빠지지 않는데 빠진다고 말한다: \(allArrived)")
        #expect(allArrived.contains("모두 도착"), "\(allArrived)")
    }

    /// 🔴 **도착 뒤 안내가 방장 여부로 갈린다** — 출발이 방장 전용이 됐기 때문이다.
    ///
    /// 예전 `ARRIVED_WAITING_NOTICE` 는 한 문장이었고 「약속 시간이 되면 출발할 수 있어요」라고 했다.
    /// 비방장에게 그건 **지킬 수 없는 약속**이다: 약속 시간이 지나도 그 사람 화면에는 버튼이 생기지
    /// 않고(`MeetingStage.departByHost`), 그때 「왜 나만 안 되지」에 답할 자리를 미리 잃는다.
    @Test("도착 뒤 안내는 방장에게만 출발할 수 있다고 말한다")
    func arrivedWaitingNoticeByRole() {
        let host = arrivedWaitingNotice(isHost: true)
        let member = arrivedWaitingNotice(isHost: false)

        #expect(host.contains("「출발」"), "\(host)")
        #expect(member.contains("방장"), "비방장에게 누가 누르는지 말해야 한다: \(member)")
        #expect(!member.contains("출발할 수 있"), "비방장에게 지킬 수 없는 약속을 한다: \(member)")
        // 둘 다 「도착했다고 알렸다」는 한 일을 먼저 말한다 — 누른 결과가 보이지 않으면 또 누른다.
        for notice in [host, member] {
            #expect(notice.contains("도착했다고 알렸어요"), "\(notice)")
        }
    }

    /// 사용자가 보는 문구를 **한 덩어리로** 훑는다 — 어느 자리에 거짓이 섞여도 위 그물들이 잡는다.
    private var allUserFacingCopy: [String] {
        (confirmCodes + [nil]).map { confirmFailureMessage(e: confirm($0)) }
            + (arriveCodes + [nil]).flatMap { code in
                RoomType.allCases.map { arriveFailureMessage(e: arrive(code), roomType: $0) }
            }
            + (departCodes + [nil]).map { departFailureMessage(e: depart($0)) }
            + RoomType.allCases.map { arriveNeedsPermissionNotice(roomType: $0) }
            + [
                ARRIVE_NOT_OPEN_NOTICE,
                ARRIVE_LOCKS_IN_NOTICE,
                arrivedWaitingNotice(isHost: true),
                arrivedWaitingNotice(isHost: false),
                DEPART_NEEDS_ARRIVAL_NOTICE,
                departHostNotice(hostNickname: "부산가자"),
                departHostNotice(hostNickname: nil),
                MEETING_CONFIRM_HELP,
                MEETING_CONFIRM_DIALOG_BODY,
                MEETING_PRESET_LIMIT_NOTE,
                departConfirmMessage(notArrivedCount: 2),
                departConfirmMessage(notArrivedCount: 0),
                CONFIRM_PLACE_UNKNOWN_MESSAGE,
            ]
    }
}
