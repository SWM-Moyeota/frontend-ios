import Foundation

/// 방 합류 실패를 화면이 **복구할 수 있는 형태**로 좁힌 예외
/// (`RideRepository.joinParty` 전용).
///
/// 합류에만 따로 예외를 둔 이유는 실패의 **대가가 유독 크기** 때문이다. 서버는 멤버 추가를 먼저 커밋하고
/// 응답을 만드는데, 그 응답 처리에서 앱이 넘어지면 **그 계정은 어떤 방에도 못 들어간다** — 같은 방에
/// 다시 합류해도, 다른 방에 합류해도 409 로 막히고(아래 `isAlreadyJoined` 참고) 서버 자동 정리(만든 지 1일,
/// `CompletedPartySweeper`) 전까지 그대로다 — 합류로 둘 이상이 된 방이라 15분 모집 만료에도 닫히지 않는다.
/// 그래서 "이미 내가 그 방 멤버다"를 **성공으로 되돌릴 수 있는 신호**가 필요하다.
///
/// 분기 근거를 프로퍼티로 노출하는 건 `ChatException` 과 같은 이유다 — 서버 코드 문자열 비교가 화면으로
/// 새어 나가면 서버가 enum 이름을 바꿀 때 조용히 어긋난다.
public struct PartyJoinException: Throwable {
    /// 서버 `MatchingErrorCode` 이름(`ALREADY_JOINED_OTHER_PARTY` 등). 본문이 없거나 파싱 실패면 null.
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 null.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체가 없으면(네트워크 실패) null.
    public let httpStatus: Int?
    /// 응답을 받지 못한 실패(연결 거부·타임아웃·DNS). 사용자에게는 재시도를 안내한다.
    public let isNetwork: Bool
    /// **이미 내가 그 방 멤버였을 때** 저장소가 확인해 담아 주는 그 방의 현재 상태.
    ///
    /// 데이터 계층이 방 상세를 읽어 내 publicId 가 members 에 있는지 **확인한 뒤에만** 채운다 —
    /// 추측이 아니라 증거다. 채워져 있으면 화면은 이 실패를 성공처럼 다뤄도 된다
    /// (합류 성공과 똑같이 대기 화면으로 넘기면 된다). 그 밖에는 null.
    public let joinedStatus: PartyStatus?
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        isNetwork: Bool = false,
        joinedStatus: PartyStatus? = nil,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.isNetwork = isNetwork
        self.joinedStatus = joinedStatus
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "방에 합류하지 못했습니다." }

    /// **이미 내가 이 방의 멤버다** — 합류는 "실패"가 아니라 "이미 됨"이다.
    /// `joinedStatus` 가 그 방의 현재 상태이므로, 화면은 합류 성공과 같은 길로 보내면 된다.
    public var isAlreadyInThisParty: Bool { joinedStatus != nil }

    /// **다른 방에 진행 중이다** — 그 방을 먼저 정리(나가기·종료)해야 이 방에 들어갈 수 있다.
    ///
    /// 서버는 "이 방"과 "다른 방"을 **코드로 구분해 주지 않는다**(둘 다 `ALREADY_JOINED_OTHER_PARTY`).
    /// 가른 건 데이터 계층이다 — 방 상세에 내가 없을 때만 여기로 떨어진다.
    public var isAlreadyInAnotherParty: Bool { code == Self.ALREADY_JOINED_OTHER_PARTY && joinedStatus == nil }

    /// 어느 쪽이든 "이미 참여 중"이라 서버가 막은 것. 같은 요청을 다시 보내도 결과가 같다
    public var isAlreadyJoined: Bool { Self.isAlreadyJoinedCode(code: code) }

    /// 409 `PARTY_FULL` — 정원이 가득 찼다(내가 보던 목록이 낡았다).
    public var isPartyFull: Bool { code == "PARTY_FULL" }

    /// 409 `PARTY_CLOSED` — 모집이 끝난 방이다(이미 매칭·종료로 넘어갔다).
    public var isPartyClosed: Bool { code == "PARTY_CLOSED" }

    /// 404 `PARTY_NOT_FOUND` — 방이 사라졌다. 목록에서 빼야 한다.
    public var isPartyNotFound: Bool { code == "PARTY_NOT_FOUND" || (code == nil && httpStatus == 404) }

    /// 403 `NO_SHOW_RESTRICTED` — **노쇼로 이용이 제한된 상태다.** 기다리면 풀리지만,
    /// 「잠시 후 다시 시도」로 뭉개면 **몇 시간 뒤까지 같은 403** 이라 사용자는 영원히 재시도한다.
    ///
    /// 근거는 `PartyOpenException.isNoShowRestricted` 에 한 번만 적어 두었다(기한을 어디서 얻는지,
    /// 왜 추천 조회에는 이 사유가 없는지까지). 이쪽에서 특히 다른 점은 **합류 흐름의 다른 409 들과
    /// 섞이기 쉽다**는 것이다: `isAlreadyJoined`·`isPartyFull` 은 「이 방이 안 된다」이고 이 403 은
    /// 「**내가** 지금 아무 방에도 못 들어간다」다. 전자는 다른 방을 권하면 되지만 후자는 다른 방도
    /// 전부 막혀 있어, 목록으로 되돌려 보내면 누르는 족족 같은 403 이다.
    public var isNoShowRestricted: Bool { code == Self.NO_SHOW_RESTRICTED }

    /// 403 — 노쇼 제재 중. 서버 `PartyService.ensureNotRestricted` 가 합류의 **첫 검사**라
    /// 「정원이 찼나·닫혔나」보다 먼저 걸린다(즉 이 403 과 409 는 함께 오지 않는다).
    public static let NO_SHOW_RESTRICTED = "NO_SHOW_RESTRICTED"

    /// 서버가 **재합류에도 이 코드를 준다.** `PartyService.join` 이 `party.join()` 보다 먼저
    /// `existsOngoingByMemberId` 를 보고, 그 질의가 합류 대상 방을 제외하지 않기 때문이다 —
    /// 그래서 "이미 참여한 방"을 뜻하는 `ALREADY_JOINED_PARTY` 는 사실상 오지 않는다.
    public static let ALREADY_JOINED_OTHER_PARTY = "ALREADY_JOINED_OTHER_PARTY"

    /// 서버에는 있지만 합류 경로에서는 위 코드에 가려 사실상 오지 않는다 — 와도 같게 다룬다.
    public static let ALREADY_JOINED_PARTY = "ALREADY_JOINED_PARTY"

    /// 「이미 참여 중」을 뜻하는 409 인가 — 이때만 "혹시 그게 이 방인가"를 확인할 가치가 있다.
    ///
    /// 두 코드를 함께 보는 건 `ALREADY_JOINED_OTHER_PARTY` 의 사정 때문이다: 코드만으로는
    /// 이 방인지 다른 방인지 가릴 수 없어, 데이터 계층이 방 상세로 확인한다.
    /// 서버 코드 문자열을 아는 곳을 여기 하나로 묶어 둔다 — 데이터 계층이 같은 문자열을
    /// 또 들고 있으면 한쪽만 서버 변경을 따라간다.
    public static func isAlreadyJoinedCode(code: String?) -> Bool {
        code == ALREADY_JOINED_OTHER_PARTY || code == ALREADY_JOINED_PARTY
    }
}

/// 「합승 완료」 실패를 화면이 **사유별로 안내할 수 있는 형태**로 좁힌 예외
/// (`RideRepository.finishParty` 전용).
///
/// 따로 둔 이유는 이 액션의 **403 이 두 가지 뜻**을 갖는데 **HTTP 상태로는 갈리지 않기** 때문이다 —
/// `NOT_PARTY_MEMBER`(이 방 멤버가 아니다)와 `NOT_PARTY_HOST`(멤버이지만 방장이 아니다)다. 예전에는
/// 둘이 「합승을 완료하지 못했어요」 하나로 떨어져서, **방장이 아니라서 막힌 사람이 다음에 뭘 해야
/// 하는지 알 수 없었다** — 같은 버튼을 다시 눌러도 같은 403 이다.
///
/// 그래서 **상태 코드로는 폴백하지 않는다.** 403 을 「방장만 할 수 있어요」로 뭉개면 방 멤버가 아닌
/// 사람에게 방장을 찾으라고 말하게 된다. 코드를 모르면 `code` 는 null 이고 화면은 **일반 문구**로
/// 떨어진다 — 서버가 코드를 늘려도 앱이 틀린 말을 하지 않는다.
///
/// 409 는 지금 `PARTY_NOT_COMPLETED` 하나뿐이다. `DRIVER_ALREADY_ASSIGNED` 도 있었지만 서버가
/// 기사·배차와 함께 **에러 코드째 지웠다**(서버 `MatchingErrorCode` 에 없다) — 올 수 없는 코드를
/// 받아 두면 화면이 영원히 안 쓰는 분기를 들고 있게 된다.
///
/// 분기 근거를 프로퍼티로 노출하는 건 `PartyJoinException` 과 같은 이유다 — 서버 코드 문자열 비교가
/// 화면으로 새어 나가면 서버가 enum 이름을 바꿀 때 조용히 어긋난다.
public struct PartyFinishException: Throwable {
    /// 서버 `MatchingErrorCode` 이름(`NOT_PARTY_HOST` 등). 본문이 없거나 파싱 실패면 null.
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 null.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체가 없으면(네트워크 실패) null. 문구 분기에는 쓰지 않는다 — 위 주석 참고.
    public let httpStatus: Int?
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "합승을 완료하지 못했습니다." }

    /// 403 `NOT_PARTY_HOST` — **방장만** 완료할 수 있다(Backend #237).
    ///
    /// 방장은 서버가 저장하는 값이 아니라 **지금 멤버 중 가장 먼저 합류한 사람**이다
    /// (`Party.hostId()` = `min(joinedAt, memberId)`). 그래서 방장이 나가면 다음으로 이른 멤버에게
    /// 자동 승계된다.
    ///
    /// 그 승계는 **SSE 변경분에 실려 온다**(`member-left` 의 `hostPublicId` = 이벤트를 반영한 뒤의
    /// 방장). 그래도 이 403 은 **남는다** — 그 신호는 한 번뿐이고 재발행되지 않아(SSE at-most-once),
    /// 프레임이 유실되거나 순서가 역전되면 내 스냅샷이 낡은 채로 버튼을 보여 줄 수 있다. 화면은
    /// **누가 눌러야 하는지**를 말해 줘야 하고, 그 순간에는 방장이 누구인지 확신할 수 없으므로
    /// 이름이 아니라 **조건**으로 말한다.
    public var isNotHost: Bool { code == Self.NOT_PARTY_HOST }

    /// 403 `NOT_PARTY_MEMBER` — 이 방의 멤버가 아니다. `isNotHost` 와 **같은 403 이지만 뜻이 다르다**.
    public var isNotMember: Bool { code == Self.NOT_PARTY_MEMBER }

    /// 409 `PARTY_NOT_COMPLETED` — 정원이 아직 다 차지 않았다(서버는 COMPLETED 방만 닫아 준다).
    public var isNotCompleted: Bool { code == Self.PARTY_NOT_COMPLETED }

    /// 409 `USE_DEPART_FOR_CONFIRMED_PARTY` — **약속이 정해진 방**이다. 이 경로로는 끝낼 수 없고
    /// 「출발」(`POST /rooms/{id}/depart`)만 받는다. 노쇼 기록이 거기서 생기므로 서버가 길을 하나로 묶었다.
    ///
    /// 화면이 확정된 방에서 이 버튼을 **숨기는데도** 남겨 두는 이유는 `isNotHost` 와 같다 — 확정
    /// 사실은 SSE 로 오고, 그 프레임을 놓치면 낡은 스냅샷으로 버튼을 보여 줄 수 있다. 그 틈에 눌린
    /// 것을 받아 **다음에 눌러야 할 버튼 이름**을 말해 준다.
    public var isUseDepartForConfirmedParty: Bool { code == Self.USE_DEPART_FOR_CONFIRMED_PARTY }

    /// 404 `PARTY_NOT_FOUND` — 방이 사라졌다.
    public var isPartyNotFound: Bool { code == Self.PARTY_NOT_FOUND }

    /// 서버 `MatchingErrorCode` 중 **이 엔드포인트가 실제로 던지는** 코드만 둔다. 문자열을 아는 곳을
    /// 여기 하나로 묶어 데이터 계층과 화면이 각자 들고 있지 않게 한다.
    public static let NOT_PARTY_MEMBER = "NOT_PARTY_MEMBER"
    public static let NOT_PARTY_HOST = "NOT_PARTY_HOST"
    public static let PARTY_NOT_COMPLETED = "PARTY_NOT_COMPLETED"
    public static let USE_DEPART_FOR_CONFIRMED_PARTY = "USE_DEPART_FOR_CONFIRMED_PARTY"
    public static let PARTY_NOT_FOUND = "PARTY_NOT_FOUND"
}

/// 「걸어서 가까운 방」 추천 조회가 실패했다(`POST /matching/rooms/realtime`).
///
/// **빈 목록은 여기로 오지 않는다** — 후보가 없는 건 정상이고 성공이다. 이 예외는 조회 자체가
/// 안 된 경우뿐이다.
///
/// **`NO_SHOW_RESTRICTED` 사유는 여기 없다 — 빠진 게 아니다.** 서버가 그 403 을 던지는 자리는
/// `PartyService.ensureNotRestricted` 한 곳이고 호출처는 `open`·`reserve`·`join` 셋뿐이라, 이
/// 추천 조회(`PartyService.realtimeMatch`)는 **검사를 거치지 않는다**. 즉 제재당한 사용자도 후보를
/// 둘러볼 수 있고, 합류를 누르는 순간에만 막힌다(`PartyJoinException.isNoShowRestricted`).
/// 여기에 사유를 더하면 서버가 허용하는 탐색을 앱이 임의로 막는 분기가 생긴다
/// (근거 전문은 `PartyOpenException.isNoShowRestricted`).
///
/// 반대로 **409 `PARTY_TIME_CONFLICT` 는 여기도 온다** — `realtimeMatch` 가 지금을 기준으로
/// `PartyConflictRule.check` 를 부르므로, 지금 전후 2시간 안에 내 다른 예약이 있으면 거절된다.
/// 이 예외에는 그 프로퍼티가 없어 원본처럼 화면의 `candidatesFailure` 가 `.failed`(재시도)로 옮긴다.
public struct RealtimeMatchException: Throwable {
    /// 서버 `MatchingErrorCode` 이름. 본문이 없거나 파싱 실패면 null.
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 null.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체가 없으면(네트워크 실패) null.
    public let httpStatus: Int?
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "추천을 가져오지 못했습니다." }

    /// 502 `ROUTE_SEARCH_FAILED` — 서버가 도보 경로 엔진(OSRM)에 닿지 못했다.
    ///
    /// **이게 평소에는 숨는다.** 300m 안에 후보가 한 건도 없으면 서버가 OSRM 을 아예 호출하지 않고
    /// 빈 배열을 돌려주기 때문이다. 즉 엔진이 죽어 있어도 눌러 보면 정상으로 보이다가, **후보가
    /// 처음 잡히는 순간** — 기능이 처음 쓸모 있어지는 그때 — 502 가 터진다. 화면은 이걸 사용자
    /// 잘못처럼 말하지 말고 방 만들기로 흘려야 한다.
    public var isRouteUnavailable: Bool { code == "ROUTE_SEARCH_FAILED" || httpStatus == 502 }

    /// 409 `ALREADY_JOINED_OTHER_PARTY` — 이미 진행 중인 방이 있다.
    ///
    /// 그 사람은 새 방을 만들 수도, 다른 방에 합류할 수도 없다. 추천을 보여 줄 이유가 없으므로
    /// 화면은 **섹션 자체를 숨긴다**(에러 문구를 띄우지 않는다).
    public var isAlreadyInParty: Bool { code == PartyJoinException.ALREADY_JOINED_OTHER_PARTY }

    /// 400 `OUT_OF_SERVICE_AREA` — 좌표가 서비스 지역(위 33~39 / 경 124~132) 밖이다.
    ///
    /// **요청 필드명을 먼저 의심할 것.** 서버 요청 record 가 전부 primitive double 이라 필드가
    /// 빠지면 0.0 이 들어가고, (0,0) 은 서비스 지역 밖이라 같은 400 으로 떨어진다. 요청 쪽 이름은
    /// `destLat`/`destLng` 이고 응답 쪽만 `destinationLat`/`destinationLng` 이다.
    public var isOutOfServiceArea: Bool { code == "OUT_OF_SERVICE_AREA" }
}

/// 방 **생성** 실패를 화면이 **사유별로 안내할 수 있는 형태**로 좁힌 예외 —
/// `RideRepository.createParty`(실시간)와 `RideRepository.createReservation`(예약) **둘 다**
/// 이 예외로 올라온다.
///
/// ### 두 액션을 한 예외에 둔 이유 — PR #82 가 셋을 가른 것과 반대 선택 ★
/// `PartyConfirmException` 주석은 「겹치는 코드가 액션마다 다른 문장을 요구하면 예외를 갈라라」고
/// 적고 있고, 여기에도 그런 코드가 하나 있다: `INVALID_CAPACITY` 가 실시간에서는 **1~3**,
/// 예약에서는 **2~3** 을 뜻한다(서버 `OpenPartyRequest.@Min(1)` vs `OpenReservationRequest.@Min(2)`).
///
/// 그래도 가르지 않는 근거는 그 주석이 든 **실패 모양이 여기서는 성립하지 않는다**는 것이다.
/// 거기서 문제였던 건 「어느 버튼을 눌렀는지가 타입에서 사라지고, 화면이 그걸 자기 쪽 **플래그**로
/// 다시 들고 있어야 한다」는 점이었다 — 확정·도착·출발은 **한 화면에서 서로 다른 때에** 눌리므로
/// 그 플래그가 낡을 수 있다. 반면 실시간/예약은 **어느 엔드포인트로 보낼지를 고른 그 값**
/// (출발 시각이 있는가)이 곧 분기 근거다. 같은 함수 안의 지역 값이라 어긋날 길이 없다.
///
/// 반대로 가르면 서버가 **같은 record 로 응답하는 두 액션**(`OpenPartyResponse`)에 예외가 둘이 되고,
/// 겹치는 여섯 코드(`ALREADY_JOINED_OTHER_PARTY`·`SAME_DEPARTURE_DESTINATION`·`OUT_OF_SERVICE_AREA`·
/// `INVALID_CAPACITY`·`NO_SHOW_RESTRICTED`·`PARTY_TIME_CONFLICT`)의 프로퍼티가 두 벌이 된다 — 한쪽만
/// 서버 변경을 따라갈 자리를 여섯 개 만드는 셈이다.
///
/// **그래서 `isInvalidCapacity` 만은 호출부가 「무엇을 만들려 했는지」를 알아야 문장이 완성된다.**
/// 그 자리는 presentation 이 모드별 문구 함수를 갈라 두는 쪽으로 해결한다(실시간 「1~3명」,
/// 예약 「2~3명」) — 그 한 곳만 갈리고 나머지는 공유한다.
///
/// 생성만 오래 예외가 없었다. 합류는 `PartyJoinException` 으로 6갈래, 완료는 `PartyFinishException` 으로
/// 5갈래인데 생성은 **모든 실패가 「잠시 후 다시 시도해 주세요」 하나**였다. 그게 특히 나쁜 까닭은 이
/// 엔드포인트의 실패가 **기다려서 풀리는 것과 사용자가 고쳐야 하는 것으로 갈리기** 때문이다:
///
/// | 사유 | 서버 코드(HTTP) | 기다리면 풀리나 |
/// |---|---|---|
/// | 이미 참여 중인 방이 있다 | `ALREADY_JOINED_OTHER_PARTY` (409) | **아니다.** 그 방을 먼저 정리해야 한다 |
/// | 출발지와 도착지가 같다 | `SAME_DEPARTURE_DESTINATION` (400) | **아니다.** 핀을 옮겨야 한다 |
/// | 서비스 지역 밖 좌표 | `OUT_OF_SERVICE_AREA` (400) | **아니다.** 다른 곳을 골라야 한다 |
/// | 정원이 1~3 이 아니다 | `INVALID_CAPACITY` (400) | **아니다.** 앱이 잘못 보냈다 |
/// | 경로 엔진 장애·경로 없음 | `ROUTE_SEARCH_FAILED` (502) · `INVALID_ROUTE_ESTIMATE`·`ROUTE_NOT_FOUND` (400) | 장애면 그렇다 |
/// | 노쇼로 이용이 제한됐다 | `NO_SHOW_RESTRICTED` (403) | **기다리면 풀린다** — 다만 몇 시간 단위다 |
/// | 기준 시각 2시간 안에 내 다른 예약이 있다 | `PARTY_TIME_CONFLICT` (409) | **아니다.** 예약은 다른 시간을 골라야 하고, 실시간은 그 예약 시간대를 벗어나야 한다 |
///
/// `PARTY_TIME_CONFLICT` 의 기준 시각은 실시간 생성이 **지금**, 예약이 **출발 시각**이다 — 그 전후
/// 2시간 안에 내 다른 예약이 있으면 둘 다 거절된다(`PartyService.open`·`PartyOpener.open`·
/// `PartyOpener.reserve` → `PartyConflictRule.check`).
///
/// **예약 생성에만 오는 하나**(실시간에는 오지 않는다):
///
/// | 사유 | 서버 코드(HTTP) | 기다리면 풀리나 |
/// |---|---|---|
/// | 출발 시각이 지금~7일 밖이다 | `INVALID_DEPARTURE_TIME` (400) | **아니다.** 시간을 다시 골라야 한다 |
///
/// 반대로 **경로 세 코드는 예약에 오지 않는다** — 서버가 예약 방의 경로를 추정하지 않기 때문이다
/// (`Party.reserve` 가 요금·시간·경로를 null 로 박는다). 즉 `isRouteUnavailable` 은 실시간에서만 참이 된다.
///
/// **409 가 이 예외를 만든 직접적인 이유다.** 서버 `PartyService.open` 은
/// `ensureNotRestricted` → `PartyConflictRule.check` 로 시작하고, 그 첫 검사 `checkNotInRealtime` 이
/// **진행 중인 실시간 방**에 내가 들어 있으면 409 `ALREADY_JOINED_OTHER_PARTY` 를 던진다
/// (`existsOngoingRealtimeByMemberId` — REALTIME 이고 CANCELED·FINISHED 가 아닌 방). 그 방은 금방 닫히지
/// 않는다 — 아무도 합류하지 않은 ACTIVE 방은 1분마다 도는 `PartyRecruitingSweeper` 가 만든 지 **15분**이
/// 지나야 CANCELED 로 닫고(`Party.expireRecruiting`), 둘 이상 모인 방은 그때 COMPLETED 가 되어 「출발」하거나
/// 1시간마다 도는 `CompletedPartySweeper` 가 만든 지 **1일** 뒤에 닫을 때까지(`Party.autoClose`) 남는다.
/// 그동안 그 방이 이 계정의 생성·합류를 계속 막는다. 그 사이 빠져나갈 길은 홈 배너 → 21(확정 전
/// 「그만 찾기」·「방 나가기」, 확정 뒤 「출발」)인데, 그 배너는 `ActivePartyRepository.resolve()` 가 방을
/// 찾아야 뜬다 — 그래서 화면은 이 409 를 받으면 **문구로 안내하는 동시에 진행 중 방 조회를 되살려야**
/// 한다. 그 둘 다 「잠시 후 다시 시도」 아래에서는 할 수 없다.
///
/// 분기 근거를 프로퍼티로 노출하는 건 `PartyJoinException`·`PartyFinishException` 과 같은 이유다 —
/// 서버 코드 문자열 비교가 화면으로 새어 나가면 서버가 enum 이름을 바꿀 때 조용히 어긋난다.
/// 그리고 **상태 코드로 폴백하지 않는다**(400 이 네 가지, 502 가 한 가지다): 코드를 모르면 `code` 는
/// null 이고 화면은 **일반 문구**로 떨어진다. 서버가 코드를 늘려도 앱이 틀린 말을 하지 않는다.
public struct PartyOpenException: Throwable {
    /// 서버 `MatchingErrorCode` 이름(`SAME_DEPARTURE_DESTINATION` 등). 본문이 없거나 파싱 실패면 null.
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 null.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체가 없으면(네트워크 실패) null. 문구 분기에는 `isRouteUnavailable` 만 쓴다.
    public let httpStatus: Int?
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "방을 만들지 못했습니다." }

    /// 409 — **이미 참여 중인 방이 있다.** 그 방을 정리하지 않으면 새 방도, 다른 방 합류도 막힌다.
    ///
    /// 합류와 달리 「이 방인가」를 가릴 필요가 없다 — 만들려는 방은 아직 없으므로 **언제나 다른 방**이다.
    /// 그래서 `PartyJoinException.isAlreadyInThisParty` 같은 복구 분기가 없고, 대신 화면은 진행 중 방
    /// 조회를 되살려 홈 배너로 돌아갈 길을 만들어야 한다(위 주석).
    ///
    /// 두 코드를 함께 보는 건 `PartyJoinException.isAlreadyJoinedCode` 와 같은 이유다 — 서버 코드 문자열을
    /// 아는 곳을 늘리지 않는다.
    public var isAlreadyInAnotherParty: Bool { PartyJoinException.isAlreadyJoinedCode(code: code) }

    /// 400 `SAME_DEPARTURE_DESTINATION` — 출발지와 도착지가 **같은 좌표**다(서버 `Party.open` 첫 검사).
    ///
    /// 15 목적지 화면의 50m 검사를 통과한 뒤에도 생긴다: 16 의 핀 조정은 그 검사를 **다시 거치지 않으므로**
    /// 두 핀을 겹쳐 놓으면 그대로 여기로 떨어진다. 사용자가 **고쳐야 하는** 실패라 「잠시 후 다시」로
    /// 안내하면 영원히 같은 400 을 맞는다.
    public var isSameDepartureDestination: Bool { code == Self.SAME_DEPARTURE_DESTINATION }

    /// 400 `OUT_OF_SERVICE_AREA` — 좌표가 서비스 지역(위 33~39 / 경 124~132) 밖이다.
    /// `RealtimeMatchException.isOutOfServiceArea` 와 같은 코드이고, **요청 필드명을 먼저 의심할 것**도 같다.
    public var isOutOfServiceArea: Bool { code == Self.OUT_OF_SERVICE_AREA }

    /// 400 `INVALID_CAPACITY` — 정원이 허용 범위 밖이다.
    /// 16 모달의 칩이 범위 안뿐이고 앱이 한 번 더 접으므로 **앱 버그일 때만** 온다 —
    /// 그래도 「잠시 후 다시」로 뭉개지 않는다: 기다려서 풀리지 않는다.
    ///
    /// ### 범위가 **액션마다 다르다** — 이 프로퍼티만으로는 문장을 만들 수 없다 ★
    /// 실시간은 **1~3**(서버 `Capacity` record), 예약은 **2~3**(`OpenReservationRequest.@Min(2)`).
    /// 그래서 「정원은 1~3명이에요」를 공통 문구로 쓰면 **예약에서 400 을 맞은 사람에게 고를 수 없는
    /// 1 을 고르라고** 말하게 된다. 호출부는 자기가 어느 액션을 불렀는지로 문구를 갈라야 한다
    /// (그 책임 분배의 근거는 이 타입 주석의 「두 액션을 한 예외에 둔 이유」에 있다).
    ///
    /// ### 예약의 하한 위반은 **이 코드로 오지 않는다**
    /// 서버 예약 요청은 Bean Validation 이 먼저 돌아(`@Min(2)`) 정원 1 은 도메인 `Capacity`
    /// (1~3 허용)까지 가지도 못하고 **400 `INVALID_REQUEST`** 로 떨어진다 — 실측으로 확인된
    /// 동작이고, 서버 Swagger 가 `INVALID_CAPACITY` 만 적어 둔 탓에 「코드로 분기하면 된다」고
    /// 믿기 쉬운 자리다.
    ///
    /// **그렇다고 `INVALID_REQUEST` 를 이 프로퍼티에 넣지는 않는다.** 그 코드는 좌표·이름·시각 누락과
    /// 본문 파싱 실패까지 뜻하는 **범용 코드**라, 넣으면 실시간 쪽에서 본문이 깨진 실패에까지
    /// 「인원을 다시 고르세요」라고 말하게 된다. 즉 예약의 정원 1 은 **사유를 알 수 없는 400** 으로
    /// 떨어지는 것이 맞고, 화면이 칩을 2·3 으로 묶어 애초에 못 만들게 하는 쪽으로 책임을 진다.
    public var isInvalidCapacity: Bool { code == Self.INVALID_CAPACITY }

    /// 409 `PARTY_TIME_CONFLICT` — 기준 시각 전후 **2시간** 안에 내 다른 예약이 있다
    /// (서버 `PartyConflictRule.CONFLICT_WINDOW`). 예약은 출발 시각이 기준이고, **실시간 생성에도
    /// 온다** — `PartyService.open`·`PartyOpener.open` 도 지금을 기준으로 `PartyConflictRule.check` 를
    /// 부른다. 다만 실시간 문구 표(`openFailureMessage`)에는 이 갈래가 없어 원본처럼 일반 문구로
    /// 떨어진다 — 사유를 말하는 것은 예약 쪽 표(`reservationOpenFailureMessage`)뿐이다.
    ///
    /// `isAlreadyInAnotherParty` 와 **다른 사유다.** 저쪽은 「지금 진행 중인 방이 있다」라 그 방을
    /// 정리해야 하고, 이쪽은 「그 시간대가 이미 찼다」라 **시간을 옮기면 된다** — 예약은 여러 건을
    /// 가질 수 있기 때문이다. 둘을 뭉개면 아무 방에도 들어가 있지 않은 사용자에게 「진행 중인 방을
    /// 먼저 정리하세요」라고 말하게 되고, 그 사람이 정리할 방은 **없다**(홈 배너도 뜨지 않는다).
    ///
    /// 그래서 이 사유는 `isAlreadyInAnotherParty` 와 달리 **진행 중 방 조회를 되살릴 필요가 없다.**
    public var isPartyTimeConflict: Bool { code == Self.PARTY_TIME_CONFLICT }

    /// 400 `INVALID_DEPARTURE_TIME` — **예약 전용.** 출발 시각이 **지금 뒤 ~ 7일 안**이 아니다
    /// (서버 `Party.MAX_RESERVATION_AHEAD`). 양쪽이 모두 엄격해서 **지금과 같은 시각도 거절된다.**
    ///
    /// 화면이 날짜·시각 피커를 그 범위로 가두면 평소에는 오지 않는다. 그래도 사유를 남기는 이유는
    /// `PartyConfirmException.isInvalidMeetingTime` 과 같다 — **경계에 붙은 선택**이 머뭇거리는
    /// 사이 서버 `now` 가 밀리면서 거절될 수 있다(7일 뒤 같은 시각을 골랐을 때, 또는 가장 가까운
    /// 시각을 골라 두고 확인을 늦게 눌렀을 때).
    ///
    /// 모양이 틀린 경우(오프셋 없는 로컬 시각)는 **이 코드가 아니다** — 역직렬화에서 터져
    /// `INVALID_REQUEST` 이고, 어느 사유도 참이 아니라 화면에 일반 문구로만 보인다. 그게 이 액션에서
    /// 원인을 찾기 가장 어려운 실패다(`NewReservation.departureAt`).
    public var isInvalidDepartureTime: Bool { code == Self.INVALID_DEPARTURE_TIME }

    /// 경로를 받지 못했다 — 서버가 방을 만들기 **전에** 경로를 추정하므로(`routeService.estimate`)
    /// 그 단계의 실패가 곧 생성 실패다.
    ///
    /// 세 코드를 한 갈래로 묶는다. 502 `ROUTE_SEARCH_FAILED`(엔진 장애)와 400
    /// `INVALID_ROUTE_ESTIMATE`·`ROUTE_NOT_FOUND`(받아온 추정이 쓸 수 없다/경로가 없다)는 원인이 다르지만
    /// **사용자가 할 수 있는 일이 같다** — 잠시 뒤 다시 시도하거나 핀을 조금 옮기는 것뿐이다.
    /// 502 를 상태 코드로도 받는 건 `RealtimeMatchException.isRouteUnavailable` 과 같은 선례다
    /// (게이트웨이가 본문 없이 502 만 돌려주는 경우).
    public var isRouteUnavailable: Bool {
        code == Self.ROUTE_SEARCH_FAILED ||
            code == Self.INVALID_ROUTE_ESTIMATE ||
            code == Self.ROUTE_NOT_FOUND ||
            httpStatus == 502
    }

    /// 403 `NO_SHOW_RESTRICTED` — **노쇼로 이용이 제한된 상태다.** 이 사유의 설명은 여기 한 번만
    /// 적어 둔다(`PartyJoinException.isNoShowRestricted` 가 이 주석을 가리킨다).
    ///
    /// ### 이 403 은 「기다리면 풀리는」 유일한 생성 실패이고, 그래서 가장 위험하다 ★
    /// 위 표의 다른 사유는 전부 「사용자가 고쳐야 하거나 장애」다. 이것만 **시간이 지나면 저절로
    /// 풀린다** — 그래서 「잠시 후 다시 시도해 주세요」가 **문법적으로는 맞는데 실질적으로는
    /// 거짓**인 유일한 자리다: 제한은 노쇼 1건당 **24시간**이고 여러 건이면 쌓인다(서버
    /// `NoShowSanction.RESTRICTION_PER_COUNT`). 「잠시」를 믿은 사용자는 몇 시간 동안 같은 403 을
    /// 맞으며 버튼을 누른다.
    ///
    /// ### 기한은 이 예외가 모른다 — 프로필을 함께 읽어야 한다 ★
    /// 서버 본문은 `{"code":"NO_SHOW_RESTRICTED","message":"노쇼로 이용이 제한된 상태입니다."}`
    /// 뿐이다. **끝나는 시각이 없다.** 그 답은 `GET /api/v1/local/users/info` 의
    /// `UserProfileInfo.restrictedUntil` 하나뿐이므로, 화면은 이 사유를 받으면
    /// `AuthRepository.getMyProfile` 을 **이어서 호출해** 문장을 완성해야 한다
    /// (「노쇼로 오늘 18:30까지 방을 만들 수 없어요」). 그 조회가 실패하면 기한 없이 사유만
    /// 말하면 된다 — 기한을 **지어내지 말 것**(24시간 × 횟수를 앱이 다시 세면 서버가 규칙을 바꿀 때
    /// 틀린 시각을 단정한다).
    ///
    /// ### 「왜 제한됐나」로 데려갈 곳이 있다
    /// `NoShowRecord` 목록(`GET /matching/no-shows`)이 그 근거이고, 억울하면 거기서 이의를 낸다
    /// (`NoShowRepository`). 이 403 의 안내는 그 화면으로 가는 길을 함께 주는 쪽이 맞다 —
    /// 사유만 말하고 끝내면 사용자가 할 수 있는 일이 기다리는 것뿐이 된다.
    ///
    /// ### 추천 조회에는 이 사유가 없다 — 「없는데 왜 없지」를 의심하지 말 것
    /// 서버에서 이 403 을 던지는 자리는 `PartyService.ensureNotRestricted` **한 곳**이고 호출처는
    /// `open`·`reserve`·`join` **셋뿐**이다. 「걸어서 가까운 방」 추천(`POST /matching/rooms/realtime`)은
    /// 그 검사를 **거치지 않으므로** `RealtimeMatchException` 에는 이 사유가 없다 — 빠진 게 아니라
    /// 서버가 막지 않는 것이다. 제재당한 사용자도 후보를 둘러볼 수 있고, 합류를 누르는 순간
    /// `PartyJoinException.isNoShowRestricted` 로 막힌다. 거기에 사유를 추가하면 **서버가 허용하는
    /// 탐색을 앱이 임의로 막는** 분기가 생긴다.
    public var isNoShowRestricted: Bool { code == Self.NO_SHOW_RESTRICTED }

    /// 서버 `MatchingErrorCode` 중 **이 두 엔드포인트가 실제로 던지는** 코드만 둔다
    /// (`PartyService.open` → `ensureNotRestricted` → `PartyConflictRule.check` → `routeService.estimate` →
    /// `PartyOpener.open`(재검사) → `Party.open` → `Capacity`/`Location`, 그리고 `PartyService.reserve` →
    /// `ensureNotRestricted` → `PartyConflictRule.check` → `Party.reserve`).
    /// 「이미 참여 중」 두 코드는 `PartyJoinException` 이 이미 들고 있으므로 여기서 또 적지 않는다.
    ///
    /// **`INVALID_REQUEST` 는 일부러 없다.** 예약 정원 1 이 그 코드로 떨어지지만 그건 범용 코드라
    /// 「무엇이 틀렸는지」를 말해 주지 않는다 — 상수를 두면 그걸 사유로 쓰게 되고, 그 순간 좌표 누락·
    /// 본문 파싱 실패까지 「인원을 다시 고르세요」가 된다(`isInvalidCapacity` 의 마지막 단락).
    public static let SAME_DEPARTURE_DESTINATION = "SAME_DEPARTURE_DESTINATION"
    public static let OUT_OF_SERVICE_AREA = "OUT_OF_SERVICE_AREA"
    public static let INVALID_CAPACITY = "INVALID_CAPACITY"
    public static let INVALID_ROUTE_ESTIMATE = "INVALID_ROUTE_ESTIMATE"
    public static let ROUTE_NOT_FOUND = "ROUTE_NOT_FOUND"
    public static let ROUTE_SEARCH_FAILED = "ROUTE_SEARCH_FAILED"

    /// 409 — 실시간·예약 생성 둘 다. 기준 시각 ±2시간 안에 내 다른 예약이 있다(`isPartyTimeConflict`).
    public static let PARTY_TIME_CONFLICT = "PARTY_TIME_CONFLICT"

    /// 400 — 예약 전용. 출발 시각이 지금 뒤 ~ 7일 안이 아니다(`isInvalidDepartureTime`).
    public static let INVALID_DEPARTURE_TIME = "INVALID_DEPARTURE_TIME"

    /// 403 — 노쇼 제재 중. 서버 `open`·`reserve` 양쪽의 **첫 검사**라(`ensureNotRestricted` 가
    /// 경로 추정·시간 검증보다 앞이다) 경로 조회조차 돌지 않는다 — 즉 이 403 과 502 는
    /// 함께 오지 않는다.
    ///
    /// `PartyJoinException.NO_SHOW_RESTRICTED` 가 **같은 문자열을 따로 선언한다.**
    /// 「이 엔드포인트가 던지는 코드 목록」이 각 예외에서 혼자 읽혀야 한다는 이 파일의 규칙을
    /// 따른 것이다(`PartyArriveException` 의 상수 주석) — `NOT_PARTY_MEMBER`·
    /// `PARTY_NOT_FOUND` 가 이미 네 예외에 흩어져 있는 것과 같은 선택이고, 둘을 한 상수로 묶으면
    /// 두 액션 중 하나가 서버에서 검사를 잃어도 목록이 그대로 남는다.
    public static let NO_SHOW_RESTRICTED = "NO_SHOW_RESTRICTED"
}

/// 방 **나가기** 실패를 화면이 **사유별로 안내할 수 있는 형태**로 좁힌 예외
/// (`RideRepository.leaveParty` 전용).
///
/// **403 `NOT_PARTY_MEMBER` 는 이 예외로 오지 않는다 — 데이터 계층이 그걸 성공으로 되돌린다.**
/// 그게 이 예외를 만든 이유다. 서버 `Party.leave` 의 검사 순서가 「멤버인가 → 모집 중인가」인데,
/// 204 응답이 유실되면(터널·타임아웃) 앱은 실패로 끝나고 **다시 누르면 403** 이다. 두 실패가 같은
/// 문구로 떨어지면 **이미 나간 사람이 영구 실패 화면에 갇힌다** — 로컬 기억과 홈 배너는 그 방을 계속
/// 들고 있으니 화면상 나는 아직 그 방에 있다. 합류가 409 를 성공으로 되돌리는 것
/// (`PartyJoinException.isAlreadyInThisParty`)과 **대칭**인 처방이다.
///
/// 그래서 화면까지 올라오는 실패는 둘뿐이다:
///
/// | 사유 | 서버 코드(HTTP) | 사용자가 할 일 |
/// |---|---|---|
/// | 모집 중이 아니다 | `PARTY_NOT_RECRUITING` (409) | 매칭이 시작돼 나갈 수 없다 — 기다린다 |
/// | 방이 없다 | `PARTY_NOT_FOUND` (404) | 홈으로 돌아간다(이미 닫힌 방이다) |
/// | 그 밖·네트워크 | 코드 없음 | 다시 시도한다 |
public struct PartyLeaveException: Throwable {
    /// 서버 `MatchingErrorCode` 이름(`PARTY_NOT_RECRUITING` 등). 본문이 없거나 파싱 실패면 null.
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 null.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체가 없으면(네트워크 실패) null.
    public let httpStatus: Int?
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "방에서 나가지 못했습니다." }

    /// 409 `PARTY_NOT_RECRUITING` — 모집 단계를 벗어난 방이다(기사 매칭이 시작됐다).
    ///
    /// 화면은 이 단계에서 나가기 버튼을 이미 비활성으로 바꾸지만(21 의 `canLeaveParty`), 전이를
    /// 알아채기까지 한 주기가 비어 그 틈에 눌릴 수 있다 — 그때 「나가지 못했어요」가 아니라 **왜**
    /// 못 나가는지 말해 줘야 한다.
    public var isNotRecruiting: Bool { code == Self.PARTY_NOT_RECRUITING }

    /// 409 `CANNOT_LEAVE_CONFIRMED_PARTY` — **약속이 정해진 방은 아무도 나갈 수 없다.**
    ///
    /// 예약 방은 합류 순간부터 확정이라 **처음부터 끝까지** 이 답이 온다. 실시간 방은 방장이 약속
    /// 시간을 확정한 뒤부터다. 끝내는 길은 「출발」 하나뿐이고, 가지 않으면 노쇼로 남는다.
    ///
    /// 화면이 확정된 방에서 나가기를 **이미 막는데도**(21 의 `canLeaveParty`) 남겨 두는 이유는
    /// `isNotRecruiting` 과 같다 — 확정 사실은 SSE 로 오므로 그 프레임을 놓치면 낡은 스냅샷으로
    /// 버튼을 열어 둘 수 있고, 그 틈에 눌린 것을 받는다.
    ///
    /// `isNotRecruiting` 과 **뜻이 다르다**: 그쪽은 이미 끝난 방이고 이쪽은 **아직 살아 있는데
    /// 약속에 묶인 방**이다. 사용자가 할 일도 다르다 — 앞은 홈으로, 뒤는 약속 장소로.
    public var isCannotLeaveConfirmed: Bool { code == Self.CANNOT_LEAVE_CONFIRMED_PARTY }

    /// 404 `PARTY_NOT_FOUND` — 방이 사라졌다. 나갈 방이 없으므로 홈으로 보내면 된다.
    public var isPartyNotFound: Bool { code == Self.PARTY_NOT_FOUND || (code == nil && httpStatus == 404) }

    /// 403 — 이 방의 멤버가 아니다 = **이미 나갔다**.
    ///
    /// 이 상수를 읽는 곳은 **데이터 계층 하나**다(`RemoteRideRepository.leaveParty` 가 성공으로
    /// 되돌린다). 화면이 이 코드를 보게 되면 그건 되돌림이 빠졌다는 뜻이다 — 위 주석 참고.
    public static let NOT_PARTY_MEMBER = "NOT_PARTY_MEMBER"
    public static let PARTY_NOT_RECRUITING = "PARTY_NOT_RECRUITING"
    public static let CANNOT_LEAVE_CONFIRMED_PARTY = "CANNOT_LEAVE_CONFIRMED_PARTY"
    public static let PARTY_NOT_FOUND = "PARTY_NOT_FOUND"
}

/// **나는 이 방의 멤버가 아니다** — 방 변화 신호 구독(SSE)이 403 `NOT_PARTY_MEMBER` 로 거절됐다
/// (`RideRepository.observePartyEvents`).
///
/// 이 예외가 **멤버십을 알려 주는 유일한 창구**다. `GET /matching/rooms/{partyId}`(방 상세)에는 참여자
/// 검사가 **없어** 멤버가 아니어도 조회가 계속 성공하기 때문이다 — 서버가 403 을 말해 주는 자리는
/// `PartySseController` 뿐이고, 그쪽은 그 403 을 `@ApiResponse` 로 계약 문서화해 두었다.
///
/// ### 왜 「스트림 종료」와 갈라야 하는가 ★
/// 예전에는 이 403 이 그 밖의 종결(방 닫힘·404)과 **똑같이** 「스트림이 끝났다」로 뭉개졌다. 그러면
/// 21 대기 화면은 다시 붙지 않는 대신 6초마다 방 상세를 **영원히** 폴링하면서, **내가 들어 있지 않은
/// 방**을 「같이 탈 사람을 찾고 있어요」로 보여 준다. 인원 문구까지 자기모순을 말하고(내가 없으니
/// 「나 외 N명」이 전체 인원과 같아진다), 거기서 「그만 찾기」를 누르면 다시 403 이라 **벗어날 길이 없다.**
///
/// 그래서 신호를 **흐름의 정상 종료가 아니라 예외**로 올린다 — 「끝났다」와 「내가 있을 방이 아니다」는
/// 호출부가 할 일이 다르고(폴백 폴링 / 화면 떠나기), 정상 종료로는 그 둘을 구분할 자리가 없다.
///
/// 전파 경로에서 **흐름이 재연결을 멈춘다**: 403 은 다시 붙어 봐야 같은 답이다.
public struct PartyMembershipLostException: Throwable {
    /// 어느 방이었는지. 로그·디버깅용이고 화면 분기에는 쓰지 않는다
    public let partyId: Int64?
    public let cause: (any Error)?

    public init(partyId: Int64? = nil, cause: (any Error)? = nil) {
        self.partyId = partyId
        self.cause = cause
    }

    public var message: String? { "이 방의 참여자가 아닙니다. (partyId=\(partyId.map { String($0) } ?? "null"))" }
}

/// 「약속 시간 확정」 실패를 화면이 **사유별로 안내할 수 있는 형태**로 좁힌 예외
/// (`RideRepository.confirmMeeting` 전용).
///
/// ### 왜 액션마다 예외를 따로 두는가 — 셋을 하나로 묶지 않은 이유 ★
/// 확정·도착·출발은 한 화면(21)에서 이어지는 한 흐름이라 예외 하나로 묶고 싶어진다. 묶으면 안 되는
/// 이유는 **같은 서버 코드가 액션에 따라 다른 문장을 요구하기** 때문이다:
///
/// | 서버 코드 | 확정에서의 뜻 | 도착에서의 뜻 | 출발에서의 뜻 |
/// |---|---|---|---|
/// | `MEETING_NOT_STARTED` | (오지 않는다) | (오지 않는다 — 도착 창은 `ARRIVAL_NOT_OPEN` 이다) | 약속 시간이 지나야 출발할 수 있어요 |
/// | `NOT_ENOUGH_MEMBERS` | 2명 이상이어야 약속을 정할 수 있어요 | (오지 않는다) | 2명 이상이어야 출발할 수 있어요 |
/// | `NOT_PARTY_MEMBER` | 방에서 나가진 상태예요 | 〃 | 〃 |
///
/// 예외가 하나면 **어느 버튼을 눌렀는지**가 타입에서 사라지고, 화면은 그걸 자기 쪽 플래그로 다시
/// 들고 있어야 한다 — 그 플래그가 어긋나는 순간 사용자는 누르지도 않은 동작의 안내를 받는다.
/// `PartyFinishException` 이 "403 이 두 가지 뜻인데 HTTP 상태로는 안 갈린다"로 생긴 것과 같은 형태의
/// 문제이고, 여기서는 **코드 하나가 두 가지 뜻인데 액션으로만 갈린다.**
///
/// 나머지 모양은 `PartyFinishException` 과 같다. **상태 코드로 폴백하지 않는다**(403 이 두 가지,
/// 409 가 네 가지다) — 코드를 모르면 `code` 는 null 이고 화면은 **일반 문구**로 떨어진다. 서버가
/// 코드를 늘려도 앱이 틀린 말을 하지 않는다. 분기 근거를 프로퍼티로 노출하는 것도 같은 이유다 —
/// 서버 코드 문자열 비교가 화면으로 새어 나가면 서버가 enum 이름을 바꿀 때 조용히 어긋난다.
///
/// 서버의 검사 순서는 `Party.confirm` 그대로다: 멤버 → 방장 → 실시간 방 → 이미 확정 → 모집 중 →
/// 인원 2명 → 시간. **앞의 검사가 걸리면 뒤 사유는 알 수 없다** — 화면이 "그리고 또…"를 붙이면 안 된다.
public struct PartyConfirmException: Throwable {
    /// 서버 `MatchingErrorCode` 이름(`ALREADY_CONFIRMED` 등). 본문이 없거나 파싱 실패면 null.
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 null.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체가 없으면(네트워크 실패) null. 문구 분기에는 쓰지 않는다 — 위 주석 참고.
    public let httpStatus: Int?
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "약속 시간을 정하지 못했습니다." }

    /// 403 `NOT_PARTY_HOST` — **방장만** 약속 시간을 정할 수 있다.
    ///
    /// `PartyFinishException.isNotHost` 와 같은 사정이다: 방장은 저장값이 아니라 **지금 멤버 중 가장
    /// 먼저 합류한 사람**이고 승계가 SSE 한 번으로만 전해지므로, 버튼을 가려도 내 스냅샷이 낡으면
    /// 이 403 이 남는다. 화면은 이름이 아니라 **조건**으로 말해야 한다.
    public var isNotHost: Bool { code == Self.NOT_PARTY_HOST }

    /// 403 `NOT_PARTY_MEMBER` — 이 방의 멤버가 아니다. `isNotHost` 와 **같은 403 이지만 뜻이 다르다**.
    public var isNotMember: Bool { code == Self.NOT_PARTY_MEMBER }

    /// 409 `NOT_REALTIME_PARTY` — 예약 방이다. 예약 방은 만들 때 출발 시각을 정했으므로 **다시 정할 수
    /// 없다**(`RoomType.reservation`).
    ///
    /// 화면이 `Ride.roomType` 으로 버튼을 먼저 가리면 거의 오지 않지만, 목록·추천에서 넘어온 방은
    /// 그 값이 기본값(`RoomType.realtime`)이라 상세를 읽기 전에는 구분이 없다 — 그 틈에 눌리면 여기로 온다.
    public var isNotRealtimeParty: Bool { code == Self.NOT_REALTIME_PARTY }

    /// 409 `ALREADY_CONFIRMED` — 이미 확정된 방이다. **실패가 아니라 "이미 됨"에 가깝다** —
    /// 다른 기기에서 눌렀거나 204 응답이 유실된 뒤 다시 누른 경우가 대부분이다.
    ///
    /// 그래도 저장소가 성공으로 되돌리지 **않는다**: 나가기의 403 과 달리(`PartyLeaveException`)
    /// 이 코드는 "**누가 언제로** 정했는지"를 말해 주지 않아, 성공으로 접으면 화면이 약속 시간을 모르는
    /// 채 확정 화면으로 넘어간다. 화면은 이 사유를 받고 **상세를 다시 읽어** 시간을 채워야 한다.
    public var isAlreadyConfirmed: Bool { code == Self.ALREADY_CONFIRMED }

    /// 409 `PARTY_NOT_RECRUITING` — 모집 단계를 벗어난 방이다(이미 닫혔다).
    public var isNotRecruiting: Bool { code == Self.PARTY_NOT_RECRUITING }

    /// 409 `NOT_ENOUGH_MEMBERS` — 혼자 있는 방이다. 서버는 2명 이상인 방만 확정해 준다.
    public var isNotEnoughMembers: Bool { code == Self.NOT_ENOUGH_MEMBERS }

    /// 400 `INVALID_MEETING_TIME` — 약속 시간이 **지금부터 1시간 안**이 아니다(서버 `MAX_CONFIRM_AHEAD`,
    /// 과거 쪽으로는 1분의 시계 오차만 봐준다).
    ///
    /// **화면이 프리셋(10·20·30·45·60분 후)으로만 시간을 고르게 하는 이유가 이것이다** — 자유 입력은
    /// 사용자가 만들 수 있는 400 이 되고, 그 400 은 "다시 시도"로 풀리지 않는다. 그래도 사유를 남겨
    /// 두는 건 **60분 프리셋이 경계에 붙어 있기** 때문이다: 고르고 누르기까지 1초만 지나도 서버 쪽
    /// `now` 가 밀려 거절될 수 있다.
    public var isInvalidMeetingTime: Bool { code == Self.INVALID_MEETING_TIME }

    /// 404 `PARTY_NOT_FOUND` — 방이 사라졌다.
    public var isPartyNotFound: Bool { code == Self.PARTY_NOT_FOUND }

    /// 서버 `MatchingErrorCode` 중 **이 엔드포인트가 실제로 던지는** 코드만 둔다
    /// (`PartyService.confirm` → `Party.confirm` 의 검사 순서 그대로).
    public static let NOT_PARTY_MEMBER = "NOT_PARTY_MEMBER"
    public static let NOT_PARTY_HOST = "NOT_PARTY_HOST"
    public static let NOT_REALTIME_PARTY = "NOT_REALTIME_PARTY"
    public static let ALREADY_CONFIRMED = "ALREADY_CONFIRMED"
    public static let PARTY_NOT_RECRUITING = "PARTY_NOT_RECRUITING"
    public static let NOT_ENOUGH_MEMBERS = "NOT_ENOUGH_MEMBERS"
    public static let INVALID_MEETING_TIME = "INVALID_MEETING_TIME"
    public static let PARTY_NOT_FOUND = "PARTY_NOT_FOUND"
}

/// 「출발지 도착」 실패를 화면이 **사유별로 안내할 수 있는 형태**로 좁힌 예외
/// (`RideRepository.arriveAtDeparture` 전용).
///
/// 출발(`PartyDepartException`)과 **코드가 네 개 겹치는데도 따로 두는** 이유는
/// `PartyConfirmException` 의 표에 적어 두었다 — 겹치는 코드가 액션마다 다른 문장을 요구한다.
///
/// ### 이 액션의 실패는 「고치면 되는 것」과 「기다리면 되는 것」으로 갈린다
///
/// | 사유 | 서버 코드(HTTP) | 사용자가 할 일 |
/// |---|---|---|
/// | 출발지에서 멀다 | `TOO_FAR_FROM_DEPARTURE` (400) | **100m 안까지 걸어간다** — 기다려도 풀리지 않는다 |
/// | 도착 창이 안 열렸다 | `ARRIVAL_NOT_OPEN` (409) | **기다린다** — 약속 10분 전이 되면 저절로 풀린다 |
/// | 약속이 안 정해졌다 | `PARTY_NOT_CONFIRMED` (409) | 방장이 시간을 정할 때까지 기다린다 |
/// | 방이 닫혔다 | `PARTY_CLOSED` (409) | 홈으로 돌아간다 |
///
/// 두 번째와 첫 번째를 한 문구로 뭉개면 **약속 시간 전에 도착한 사람에게 "더 가까이 가세요"** 라고
/// 말하게 된다 — 그 사람은 이미 출발지에 서 있다.
///
/// ### 도착은 약속 시간 **10분 전**부터 열린다
/// 서버 `Party.arrive` 의 검사는
/// `if(now.isBefore(departureAt.minus(ARRIVAL_OPENS_BEFORE))) throw ARRIVAL_NOT_OPEN` 이고
/// `ARRIVAL_OPENS_BEFORE = Duration.ofMinutes(10)` 이다(백엔드 PR #307, 2026-11-05 — 그 전에는
/// 약속 시간 정각부터였다). 그래서 **창이 안 열린 실패는 `isArrivalNotOpen`** 이고,
/// `MEETING_NOT_STARTED` 는 **도착이 아니라 출발**의 코드다(`PartyDepartException.isMeetingNotStarted`).
///
/// 둘을 섞으면 화면이 틀린 시각을 말한다 — 도착은 10분 전, 출발은 약속 시간 뒤다.
/// 서버 검사 순서는 멤버 → 방 열림 → **이미 도착했으면 여기서 204** → 도착 창 → 거리다.
///
/// 멱등이라는 점도 중요하다: 이미 도착한 사람이 다시 눌러도 서버는 204 를 준다(시각 유지, SSE 없음).
/// 그래서 "도착을 두 번 눌렀다"는 실패는 **존재하지 않는다**.
public struct PartyArriveException: Throwable {
    /// 서버 `MatchingErrorCode` 이름(`TOO_FAR_FROM_DEPARTURE` 등). 본문이 없거나 파싱 실패면 null.
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 null.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체가 없으면(네트워크 실패) null. 문구 분기에는 쓰지 않는다.
    public let httpStatus: Int?
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "도착을 확인하지 못했습니다." }

    /// 400 `TOO_FAR_FROM_DEPARTURE` — 방 출발지에서 **100m 밖**이다(서버가 PostGIS `ST_DWithin` 으로 잰다).
    ///
    /// 앱이 보낸 좌표가 기준이므로 **실내·지하에서의 측위 오차**가 그대로 이 실패가 된다. 화면은
    /// "더 가까이 가 주세요"와 함께 **다시 시도**를 열어 두어야 한다 — 위치가 잡히면 풀린다.
    public var isTooFarFromDeparture: Bool { code == Self.TOO_FAR_FROM_DEPARTURE }

    /// 400 `OUT_OF_SERVICE_AREA` — 보낸 좌표가 서비스 지역(위 33~39 / 경 124~132) 밖이다.
    ///
    /// **요청 필드명·측위 실패를 먼저 의심할 것.** 서버 `ArriveRequest` 는 `latitude`/`longitude` 이고,
    /// 둘 중 하나가 빠지면 400 `INVALID_REQUEST` 다. (0,0) 이 실려 가면 여기로 떨어진다 —
    /// 측위 실패를 0.0 으로 채워 보내는 코드가 있으면 사용자에게는 "서비스 지역이 아니에요"로 보인다.
    public var isOutOfServiceArea: Bool { code == Self.OUT_OF_SERVICE_AREA }

    /// 403 `NOT_PARTY_MEMBER` — 이 방의 멤버가 아니다.
    public var isNotMember: Bool { code == Self.NOT_PARTY_MEMBER }

    /// 409 `PARTY_CLOSED` — 이미 끝났거나 취소된 방이다(ACTIVE·COMPLETED 가 아니다).
    public var isPartyClosed: Bool { code == Self.PARTY_CLOSED }

    /// 409 `PARTY_NOT_CONFIRMED` — 약속 시간이 아직 정해지지 않았다. 방장이 정할 때까지 도착을 받지 않는다.
    public var isNotConfirmed: Bool { code == Self.PARTY_NOT_CONFIRMED }

    /// 409 `ARRIVAL_NOT_OPEN` — **도착 창이 아직 안 열렸다**(약속 시간 10분 전보다 이르다).
    /// 기다리면 풀리는 유일한 사유다. 출발의 `MEETING_NOT_STARTED` 와 **경계가 다르다** —
    /// 도착은 약속 10분 전, 출발은 약속 시간 뒤다.
    public var isArrivalNotOpen: Bool { code == Self.ARRIVAL_NOT_OPEN }

    /// 404 `PARTY_NOT_FOUND` — 방이 사라졌다.
    public var isPartyNotFound: Bool { code == Self.PARTY_NOT_FOUND }

    /// 서버 `MatchingErrorCode` 중 **이 엔드포인트가 실제로 던지는** 코드만 둔다
    /// (`PartyService.arrive` → `Location` 검증 → `Party.arrive` → `ensureAttendanceOpen`).
    /// 출발과 겹치는 네 개를 `PartyDepartException` 이 또 선언하는 건 **일부러**다 —
    /// 「이 엔드포인트가 던지는 코드 목록」이 각 예외에서 혼자 읽혀야 한다(`PartyFinishException` ·
    /// `PartyLeaveException` 이 `NOT_PARTY_MEMBER` 를 각자 들고 있는 것과 같다).
    public static let TOO_FAR_FROM_DEPARTURE = "TOO_FAR_FROM_DEPARTURE"
    public static let OUT_OF_SERVICE_AREA = "OUT_OF_SERVICE_AREA"
    public static let NOT_PARTY_MEMBER = "NOT_PARTY_MEMBER"
    public static let PARTY_CLOSED = "PARTY_CLOSED"
    public static let PARTY_NOT_CONFIRMED = "PARTY_NOT_CONFIRMED"
    public static let ARRIVAL_NOT_OPEN = "ARRIVAL_NOT_OPEN"
    public static let PARTY_NOT_FOUND = "PARTY_NOT_FOUND"
}

/// 「출발」 실패를 화면이 **사유별로 안내할 수 있는 형태**로 좁힌 예외
/// (`RideRepository.departParty` 전용).
///
/// **이 액션은 되돌릴 수 없다.** 성공하면 방이 그 자리에서 끝나고(FINISHED), 그 순간 도착하지 않은
/// 멤버가 전부 **노쇼로 기록된다**(노쇼 횟수 × 24시간 이용 제한, 약속 시간부터 센다). 앱에는 그걸
/// 취소하는 길이 없다 — 이의 신청은 서버 쪽 별도 경로다. 그래서 화면은 누르기 전에 확인을 받아야 하고,
/// 실패했을 때 **왜** 못 했는지도 정확히 말해야 한다("다시 시도"는 아무것도 바꾸지 않는다).
///
/// 방장 전용이 **아니다** — 도착한 멤버면 누구나 누를 수 있다(`NOT_PARTY_HOST` 가 이 목록에 없는 이유다).
/// 겹치는 코드를 도착(`PartyArriveException`)과 따로 두는 근거는 `PartyConfirmException` 의 표에 있다.
///
/// | 사유 | 서버 코드(HTTP) | 사용자가 할 일 |
/// |---|---|---|
/// | 내가 아직 도착을 안 눌렀다 | `NOT_ARRIVED` (409) | **먼저 「출발지 도착했어요」를 누른다** |
/// | 약속 시간 전이다 | `MEETING_NOT_STARTED` (409) | 기다린다 |
/// | 혼자 남았다 | `NOT_ENOUGH_MEMBERS` (409) | 혼자서는 출발할 수 없다 |
/// | 약속이 안 정해졌다 / 방이 닫혔다 | `PARTY_NOT_CONFIRMED` · `PARTY_CLOSED` (409) | 화면을 다시 읽는다 |
public struct PartyDepartException: Throwable {
    /// 서버 `MatchingErrorCode` 이름(`NOT_ARRIVED` 등). 본문이 없거나 파싱 실패면 null.
    public let code: String?
    /// 서버가 준 한국어 원문 message. 없으면 null.
    public let serverMessage: String?
    /// HTTP 상태 코드. 응답 자체가 없으면(네트워크 실패) null. 문구 분기에는 쓰지 않는다.
    public let httpStatus: Int?
    public let cause: (any Error)?

    public init(
        code: String?,
        serverMessage: String?,
        httpStatus: Int? = nil,
        cause: (any Error)? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.httpStatus = httpStatus
        self.cause = cause
    }

    public var message: String? { serverMessage ?? code ?? "출발하지 못했습니다." }

    /// 409 `NOT_ARRIVED` — **내가 출발지 도착을 누르지 않았다.** 도착한 사람만 방을 끝낼 수 있다.
    ///
    /// 화면이 「출발」을 내 `User.hasArrived` 로 가리므로 평소에는 오지 않지만, 그 값이 낡으면
    /// (SSE `member-arrived` 를 놓쳤거나 다른 기기에서 눌렀을 때) 틈이 생긴다 — 그때 "다시 시도"가
    /// 아니라 **「출발지 도착했어요」를 먼저 누르라**고 말해야 한다.
    public var isNotArrived: Bool { code == Self.NOT_ARRIVED }

    /// 409 `MEETING_NOT_STARTED` — **약속 시간 전**이다. 출발은 약속 시간 **뒤**에만 된다
    /// (도착은 약속 10분 전부터라 경계가 다르다 — 도착 쪽 시간 코드는 `ARRIVAL_NOT_OPEN` 이고,
    /// 이 코드는 출발에서만 온다).
    public var isMeetingNotStarted: Bool { code == Self.MEETING_NOT_STARTED }

    /// 409 `NOT_ENOUGH_MEMBERS` — 멤버가 2명 미만이다. 혼자 남은 방은 출발할 수 없다.
    public var isNotEnoughMembers: Bool { code == Self.NOT_ENOUGH_MEMBERS }

    /// 409 `PARTY_NOT_CONFIRMED` — 약속 시간이 정해지지 않은 방이다. 확정 전 방은 「합승 완료」로 끝낸다.
    public var isNotConfirmed: Bool { code == Self.PARTY_NOT_CONFIRMED }

    /// 409 `PARTY_CLOSED` — 이미 끝났거나 취소된 방이다.
    ///
    /// **다른 멤버가 먼저 출발을 눌렀을 때 오는 사유이기도 하다** — 그때 방은 이미 FINISHED 이고
    /// 내 할 일은 없다. 화면은 이 사유를 실패가 아니라 **종료**로 보여 주는 쪽이 맞다(SSE `closed` 가
    /// 같은 사실을 들고 오고, 둘 중 먼저 오는 쪽이 화면을 닫는다).
    public var isPartyClosed: Bool { code == Self.PARTY_CLOSED }

    /// 403 `NOT_PARTY_MEMBER` — 이 방의 멤버가 아니다.
    public var isNotMember: Bool { code == Self.NOT_PARTY_MEMBER }

    /// 404 `PARTY_NOT_FOUND` — 방이 사라졌다.
    public var isPartyNotFound: Bool { code == Self.PARTY_NOT_FOUND }

    /// 서버 `MatchingErrorCode` 중 **이 엔드포인트가 실제로 던지는** 코드만 둔다
    /// (`PartyService.depart` → `Party.depart` → `ensureAttendanceOpen`).
    /// `NOT_PARTY_HOST` 는 **없다** — 출발은 방장 전용이 아니다(위 주석).
    public static let NOT_ARRIVED = "NOT_ARRIVED"
    public static let MEETING_NOT_STARTED = "MEETING_NOT_STARTED"
    public static let NOT_ENOUGH_MEMBERS = "NOT_ENOUGH_MEMBERS"
    public static let PARTY_NOT_CONFIRMED = "PARTY_NOT_CONFIRMED"
    public static let PARTY_CLOSED = "PARTY_CLOSED"
    public static let NOT_PARTY_MEMBER = "NOT_PARTY_MEMBER"
    public static let PARTY_NOT_FOUND = "PARTY_NOT_FOUND"
}
