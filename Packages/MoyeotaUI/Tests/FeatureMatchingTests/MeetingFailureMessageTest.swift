@testable import FeatureMatching
import MoyeotaDomain
import Testing

/// 약속 확정·출발지 도착·출발 **실패 안내** — `FinishFailureMessageTest` 와 같은 자리·같은 규칙이다.
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
        PartyConfirmException.PARTY_NOT_RECRUITING,
        PartyConfirmException.NOT_ENOUGH_MEMBERS,
        PartyConfirmException.PARTY_NOT_FOUND,
    ]

    /// 프리셋이 이 400 을 **사용자의 실수에서 지우지만 없애지는 못한다** — 기기 시계가 서버보다
    /// 앞서 있으면 60분 프리셋이 서버 기준 1시간을 넘을 수 있다. 그때 할 수 있는 일은 **더 가까운
    /// 프리셋을 고르는 것**이므로, 이 가지에만 행동을 권한다(실제로 통과한다).
    @Test("1시간을 벗어났으면 더 가까운 시간을 고르라고 말한다")
    func invalidMeetingTime() {
        let message = confirmFailureMessage(e: confirm(PartyConfirmException.INVALID_MEETING_TIME))

        #expect(message == "약속 시간은 지금부터 1시간 안이어야 해요. 더 가까운 시간으로 골라 주세요")
        #expect(message.contains("1시간"), "서버 한도를 숫자로 말해야 한다")
    }

    /// 「방장만」으로 끝내면 사용자가 할 수 있는 일이 없다 — **누가 눌러야 하는지**가 핵심이다.
    /// 이름을 쓰지 않는 근거는 `finishFailureMessage` 와 같다: 이 403 은 내 스냅샷이 가리킨 방장이
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
        #expect(message(PartyConfirmException.PARTY_NOT_RECRUITING) == "이미 끝난 방이에요. 홈으로 돌아가 주세요")
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
    /// 있는 자리가 **여기 하나뿐**이고, 숫자(100m)가 없으면 10m 를 더 가야 하는지 300m 를 더 가야
    /// 하는지 알 수 없다. 그 100m 는 앱이 고른 값이 아니라 **서버가 PostGIS 로 재는 값**이다.
    @Test("출발지에서 멀면 서버가 재는 거리를 숫자로 말한다")
    func tooFarFromDeparture() {
        let message = arriveFailureMessage(e: arrive(PartyArriveException.TOO_FAR_FROM_DEPARTURE))

        #expect(message == "출발지에서 100m 안에 있어야 도착을 알릴 수 있어요. 출발지로 더 가까이 가 주세요")
        #expect(message.contains("100m"), "서버가 재는 거리를 말해야 한다")
        #expect(message.contains("가까이"), "무엇을 해야 하는지 말해야 한다")
    }

    @Test("도착 - 서비스 지역 · 멤버 아님 · 닫힌 방 · 확정 전 · 창 안 열림 · 사라진 방")
    func arriveOtherReasons() {
        func message(_ code: String) -> String { arriveFailureMessage(e: arrive(code)) }

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
        #expect(arriveFailureMessage(e: arrive(PartyArriveException.ARRIVAL_NOT_OPEN)).contains("10분"))
        #expect(ARRIVAL_OPENS_MINUTES_BEFORE == 10)
    }

    @Test("도착 - 모르는 코드는 일반 문구로 떨어진다")
    func arriveUnknownCode() {
        #expect(arriveFailureMessage(e: arrive("ARRIVE_SOMETHING_NEW")) == arriveGeneral)
        #expect(arriveFailureMessage(e: arrive(nil)) == arriveGeneral)
        #expect(arriveFailureMessage(e: arrive(PartyConfirmException.NOT_PARTY_HOST)) == arriveGeneral)
    }

    @Test("도착 - 사유마다 다른 말을 한다")
    func arriveDistinct() {
        let messages = (arriveCodes + [nil]).map { arriveFailureMessage(e: arrive($0)) }
        #expect(Set(messages).count == messages.count)
    }

    // ─────────────────────── 출발 ───────────────────────

    private let departGeneral = "출발하지 못했어요"

    private let departCodes: [String?] = [
        PartyDepartException.NOT_ARRIVED,
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
            + (arriveCodes + [nil]).map { arriveFailureMessage(e: arrive($0)) }
            + (departCodes + [nil]).map { departFailureMessage(e: depart($0)) }
    }

    /// ★ **지키지 못할 약속을 넣지 않는다.** `FinishFailureMessageTest` 가 세운 금지를 세 액션에
    /// 그대로 적용한다 — 403·409 는 다시 눌러도 같은 답이고, 400 도 같은 자리에서 다시 누르면 같은
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
    /// 알림을 보내거나, 가까워지면 자동으로 알려 주거나, 노쇼를 되돌려 주지 않는다.
    @Test("서버가 하지 않는 일을 약속하지 않는다")
    func noFeatureClaims() {
        let all = allFailureMessages + [
            ARRIVE_NOT_OPEN_NOTICE,
            ARRIVED_WAITING_NOTICE,
            DEPART_NEEDS_ARRIVAL_NOTICE,
            ARRIVE_NEEDS_PERMISSION_NOTICE,
            MEETING_CONFIRM_HELP,
            MEETING_CONFIRM_DIALOG_BODY,
            MEETING_PRESET_LIMIT_NOTE,
            departConfirmMessage(notArrivedCount: 2),
            departConfirmMessage(notArrivedCount: 0),
        ]

        for forbidden in ["자동으로", "알림을 보내", "알려 드려요", "취소할 수 있어요", "되돌릴 수 있어요"] {
            for message in all {
                #expect(!message.contains(forbidden), "없는 기능을 약속한다: \(message)")
            }
        }
    }

    /// 확정이 **되돌릴 수 없다는 사실**을 버튼 앞과 다이얼로그가 **둘 다** 말해야 한다.
    /// 다이얼로그에서만 말하면 프리셋을 누르기 전에는 모르고, 설명에서만 말하면 접힌 시트에서 놓친다.
    @Test("확정 안내는 나갈 수 없게 된다는 것을 말한다")
    func confirmCopySaysNoLeaving() {
        for message in [MEETING_CONFIRM_HELP, MEETING_CONFIRM_DIALOG_BODY] {
            #expect(message.contains("나갈 수 없"), "\(message)")
            #expect(message.contains("모집이 끝나"), "\(message)")
        }
    }

    /// ★ 못 박는 것: **어떻게 끝내는지와 안 갔을 때의 대가를 확정 전에 말한다.**
    ///
    /// 「나갈 수 없다」만 말하면 사용자는 못 나가는 것까지만 알고 **그래서 어떻게 끝내는지**를 모른다.
    /// 약속이 깨져 아무도 출발지에 가지 않으면 방이 열린 채 남고, 그동안 서버가 다른 방 합류·방
    /// 만들기·예약까지 전부 막는다(`ALREADY_JOINED_OTHER_PARTY`). 스스로 풀 방법이 없으므로
    /// **들어가기 전에 말하는 것이 유일한 방어**다.
    @Test("확정 안내는 끝내는 방법과 노쇼 대가를 말한다")
    func confirmCopySaysHowToEnd() {
        for message in [MEETING_CONFIRM_HELP, MEETING_CONFIRM_DIALOG_BODY] {
            #expect(message.contains("출발"), "끝내는 방법을 말하지 않는다: \(message)")
            #expect(message.contains("노쇼"), "안 갔을 때의 대가를 말하지 않는다: \(message)")
        }
    }
}
