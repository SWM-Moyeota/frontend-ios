import MoyeotaDomain

/// 서버 `objectionStatus` 문자열 → 도메인 `ObjectionStatus`. **모르는 값과 null 은 모두 null 이다.**
///
/// ### 이 앱의 다른 문자열 변환과 **반대 방향**으로 기운다 ★
/// `partyStatusToRideStatus` 는 모르는 상태를 `RideStatus.recruiting` 으로,
/// `toRoomType` 은 모르는 종류를 `RoomType.realtime` 으로 떨어뜨린다 —
/// 그쪽은 「모르면 화면이 열리는 쪽」이 안전하기 때문이다. 여기서 같은 식으로 `ObjectionStatus.pending`
/// 을 고르면 **없는 사실을 단정**한다(「심사 중이에요」). 대가의 비대칭은
/// `ObjectionStatus` 주석의 표에 적어 두었다 — 요약하면 null 쪽 오답은 서버 409 가 복구해 주고,
/// pending 쪽 오답은 사용자가 다시 낼 길을 닫는다.
///
/// ### raw value 도, `Decodable` enum 도 쓰지 않는다
/// raw value 로 읽으면(Kotlin `enumValueOf` 자리) 서버 문자열과 케이스 이름이 묶여 판정이 이 함수
/// 밖으로 새고, DTO 필드를 `Decodable` enum 으로 선언하면 모르는 값이 **역직렬화 단계에서** 예외가
/// 된다(한 줄이 목록 전체를 날린다) — 서버가 상태를 하나 추가하는 날 노쇼 화면이 통째로 죽는다.
/// 그래서 와이어는 String 으로 받고, 판정을 여기서 `partyStatusToRideStatus` 와 **같은 모양의
/// `switch`** 로 한다(`default` 의 방향만 반대다).
///
/// 빈 문자열·공백도 null 이다 — 화면이 「안 냈다」를 한 가지 모양(null)으로만 보게 한다
/// (`PartyMappers` 가 `publicId`·`departureAt` 의 빈 문자열을 접는 것과 같은 정책).
func toObjectionStatus(status: String?) -> ObjectionStatus? {
    switch status?.trim() {
    case "PENDING": return .pending
    case "ACCEPTED": return .accepted
    case "REJECTED": return .rejected
    // nil · 빈 문자열 · 서버가 나중에 추가한 값. **pending 으로 떨어뜨리지 말 것** — 위 주석.
    default: return nil
    }
}

extension NoShowItemDto {
    /// `NoShowItem` → `NoShowRecord`.
    ///
    /// 옮기면서 하는 일은 셋뿐이다: 이름의 null 을 빈 문자열로 접고(화면이 null 을 또 확인하지 않게 —
    /// `RideRecordMappers` 와 같은 관례), `voided` 를 도메인 이름 `NoShowRecord.isVoided` 로 옮기고,
    /// 상태 문자열을 `toObjectionStatus` 로 좁힌다.
    ///
    /// **시각은 손대지 않는다.** 서버가 준 ISO-8601 문자열을 그대로 흘린다 — 파싱을 여기서 하면
    /// data 와 presentation 이 같은 변환을 각자 들게 되고, 소수점 아래 6자리가 붙은 값
    /// (`timestamp(6)` 컬럼이라 가능하다)에서 한쪽만 깨진다. 근거 전문은 `NoShowRecord` 주석.
    ///
    /// **항목을 버리지 않는다.** 실시간 후보 매퍼는 방 id 가 없는 항목을 버리는데(탭해도 갈 곳이 없다)
    /// 여기서는 `partyId` 가 0 이어도 남긴다 — 이 줄의 쓸모는 **탭이 아니라 「제재의 근거를 보여 주는
    /// 것」**이고, 제재당한 사용자에게 설명을 빼먹는 쪽이 훨씬 나쁘다. 이의 신청 버튼만 못 누르게 하면
    /// 되고, 그 판정은 화면이 `partyId > 0` 으로 한다.
    public func toDomain() -> NoShowRecord {
        NoShowRecord(
            partyId: partyId,
            departure: departure,
            destination: destination,
            meetingAt: meetingAt,
            noShowAt: noShowAt,
            isVoided: voided,
            objectionStatus: toObjectionStatus(status: objectionStatus)
        )
    }
}

/// 이의 신청 실패 → `NoShowObjectionException`. presentation 이 HTTP 를 알 필요가 없게 하는 경계다.
///
/// 모양은 `PartyMappers` 의 `partyConfirmException` 계열과 같다 — `error` 는 이미 읽어 둔 본문
/// (`readApiError`)이고(**본문은 한 번만 읽는다**), 응답을 못 받은 실패와 모르는 코드는 둘 다
/// code = null 로 떨어져 화면이 일반 문구를 쓴다.
///
/// `isNetwork` 같은 구분은 두지 않는다: 이 액션은 그 두 경우의 **대응이 같다**(다시 시도).
/// 쓰지 않을 구분을 노출하면 나중에 네트워크 실패에 「이미 이의를 냈어요」가 붙는 식으로 어긋난다.
///
/// **성공으로 되돌리는 코드는 없다.** 409 `ALREADY_OBJECTED` 가 가장 가깝지만 되돌리지 않는 이유는
/// `NoShowObjectionException.isAlreadyObjected` 에 적어 두었다 — 그 코드는 「어떤 상태인가」를
/// 말해 주지 않아 성공으로 접으면 기각된 이의에도 「접수됐어요」를 말하게 된다.
func noShowObjectionException(
    failure: any Error,
    error: ApiErrorDto?
) -> NoShowObjectionException {
    if let failure = failure as? NoShowObjectionException { return failure }

    if let http = failure as? HttpException {
        return NoShowObjectionException(
            code: error?.code,
            serverMessage: error?.message,
            httpStatus: http.code(),
            cause: failure
        )
    }

    return NoShowObjectionException(code: nil, serverMessage: nil, cause: failure)
}
