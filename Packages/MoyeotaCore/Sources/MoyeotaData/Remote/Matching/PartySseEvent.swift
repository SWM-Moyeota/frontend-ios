import Foundation

/// 서버 이벤트 이름(`RedisPartyChangeNotifier` · `PartySseRegistry`). 이 문자열이 계약이다 —
/// **서버가 보내는 일곱 종을 전부 적어 둔다.** 모르는 이름은 조용히 건너뛰므로
/// (`parsePartySseFrame` 의 `default`), 하나를 빠뜨리면 그 변화가 화면에서 **아무 일도 안 일어남**으로만
/// 보인다 — 예전에 넷만 알던 앱이 약속 확정·도착을 영영 못 본 이유가 그것이다.
let EVENT_CONNECTED = "connected"
let EVENT_MEMBER_JOINED = "member-joined"
let EVENT_MEMBER_LEFT = "member-left"
let EVENT_RECRUITING_CLOSED = "recruiting-closed"
let EVENT_CONFIRMED = "confirmed"
let EVENT_MEMBER_ARRIVED = "member-arrived"
let EVENT_CLOSED = "closed"

/// SSE 프레임 하나를 **서버 shape 그대로** 담은 data 계층 이벤트.
///
/// 도메인 `PartyEvent` 와 따로 두는 이유는 하나다: `connected`·`member-joined` 의 도메인 변환에는
/// **"누가 나인지"를 판정할 세션 uuid** 가 필요한데, 그 값은 요청 시점에 읽어야 하고 단일 출처가
/// 저장소(`RemoteRideRepository`)에 있다. SSE 수신기에 세션을 들려 보내면 파싱이 세션에 묶여 테스트가
/// 어려워지므로, 수신기는 **파싱까지만** 하고 도메인 변환은 매퍼(`PartyMappers.toPartyEvent`)에 맡긴다.
public enum PartySseEvent: Equatable, Sendable {
    /// `connected` — data 가 방 상세 전체 JSON(`PartyDetailResult`)이다. 기존 상세 DTO 를 그대로 재사용한다
    case snapshot(detail: PartyDetailResponse)

    /// `member-joined` — `{"member": {...}, "status": "..."}`
    case memberJoined(payload: MemberJoinedPayload)

    /// `member-left` — `{"publicId": "..."|null, "status": "...", "hostPublicId": "..."|null}`.
    /// `hostPublicId` 는 **승계 후의 방장**이다(Backend #240) — `MemberLeftPayload` 참고.
    case memberLeft(payload: MemberLeftPayload)

    /// `recruiting-closed` — `{"status": "COMPLETED", "version": N}`
    case recruitingClosed(payload: RecruitingClosedPayload)

    /// `confirmed` — `{"status": "COMPLETED", "departureAt": "...", "version": N}`
    case confirmed(payload: PartyConfirmedPayload)

    /// `member-arrived` — `{"publicId": "...", "version": N}`.
    ///
    /// **형제들과 달리 payload DTO 를 그대로 품지 않는다.** 서버는 publicId 를 null 로 보낼 수 있지만
    /// (`MemberArrivedPayload`) 도착은 「누구의」 도착인지가 전부라서, 누군지 모르는 프레임은
    /// `parsePartySseFrame` 이 건너뛴다 — 여기까지 올라온 프레임은 publicId 가 **있다**는 뜻이다.
    /// 그 보장을 타입으로 들고 있어야 도메인(`PartyEvent.memberArrived`)의
    /// 논-널 publicId 로 `!` 없이 옮길 수 있다.
    case memberArrived(publicId: String, version: Int64? = nil)

    /// `closed` — data 는 `{status}` 라 실을 값이 없다(앱은 종결 신호로만 쓴다)
    case closed

    /// 서버 프레임이 아니라 **앱이 알아챈 끊김**. `PartyEventSource` 의 재연결 루프가 낸다
    case disconnected
}

/// 프레임 하나를 읽은 결과.
///
/// 파싱 실패를 예외로 올리지 않는 게 이 타입의 존재 이유다 — **한 프레임이 깨졌다고 스트림을 죽이면
/// 서버가 이벤트를 늘리거나 필드를 바꾼 순간 대기 화면이 통째로 멈춘다.** 건너뛴 이유는 로그로만 남긴다.
enum PartySseFrame: Equatable, Sendable {
    case received(event: PartySseEvent)

    /// 흘려보낼 프레임. `reason` 은 로그 경고에만 쓴다
    case skipped(reason: String)
}

/// SSE 프레임(이벤트 이름 + data 문자열) → `PartySseEvent`. **네트워크 없이 테스트할 수 있는 순수 함수다.**
///
/// `closed` 의 data 는 **읽지 않는다.** 지금 서버는 `{"status": "FINISHED"}` 를 보내지만 그 사이 배포는
/// `{partyId, status, version}` 이었고 더 옛 배포는 partyId 숫자 문자열("42")이었다 — 종결 신호로만 쓰는
/// 값이라 모양이 바뀌어도 상관없고, 역직렬화를 시도하면 그 숫자 문자열에서 실패한다.
/// 주석 프레임(`:ping`)은 `ServerSentEventReader` 가 삼켜 여기까지 오지 않는다.
func parsePartySseFrame(type: String?, data: String) -> PartySseFrame {
    switch type {
    case EVENT_CONNECTED:
        return decode(type: EVENT_CONNECTED) { .snapshot(detail: try decodeSseData(data)) }
    case EVENT_MEMBER_JOINED:
        return decode(type: EVENT_MEMBER_JOINED) { .memberJoined(payload: try decodeSseData(data)) }
    case EVENT_MEMBER_LEFT:
        return decode(type: EVENT_MEMBER_LEFT) { .memberLeft(payload: try decodeSseData(data)) }
    case EVENT_RECRUITING_CLOSED:
        return decode(type: EVENT_RECRUITING_CLOSED) { .recruitingClosed(payload: try decodeSseData(data)) }
    case EVENT_CONFIRMED:
        return decode(type: EVENT_CONFIRMED) { .confirmed(payload: try decodeSseData(data)) }
    case EVENT_MEMBER_ARRIVED:
        return parseMemberArrived(data: data)
    case EVENT_CLOSED:
        return .received(event: .closed)
    default:
        // 모르는 이벤트는 흘려보낸다 — 서버가 종류를 늘려도 앱이 멈추지 않는다
        return .skipped(reason: "모르는 이벤트 type=\(type ?? "null")")
    }
}

/// `member-arrived` 만 분기가 따로 있는 이유: **도착한 사람을 특정할 수 없는 프레임은 버린다.**
///
/// 서버는 유저 요약을 못 찾으면 publicId 를 null 로 싣고도 신호는 보낸다(`PartyService.arrive`).
/// 그 프레임으로는 멤버 목록의 누구의 도착도 켤 수 없고, 도착 이벤트에는 함께 올 상태값도 없어
/// **반영할 것이 하나도 없다**(`member-left` 는 그래도 `status` 가 있어 올려 보낼 값이 남는다).
///
/// 버리면 version 이 하나 비므로 **다음 프레임이 +2 로 보여** 화면이 상세를 다시 읽는다 — 서버 계약이
/// 이 경우에 지시하는 바로 그 동작이다(`PartySseController`: "publicId 가 null 이거나 목록에 없으면
/// 방 상세를 다시 받는다"). 즉 건너뛰기가 곧 재조회 신호다.
///
/// 빈 문자열도 null 과 같이 다룬다 — "모름"이 두 가지 모양이면 거르는 쪽이 하나를 놓친다
/// (`member-left` 의 publicId 와 같은 정책).
private func parseMemberArrived(data: String) -> PartySseFrame {
    do {
        let payload: MemberArrivedPayload = try decodeSseData(data)
        guard let publicId = payload.publicId?.takeIfNotBlank() else {
            return .skipped(
                reason: "\(EVENT_MEMBER_ARRIVED) 에 도착한 사람이 없다(publicId 없음) — 버린다. " +
                    "version 이 비어 다음 프레임이 상세 재조회를 부른다"
            )
        }
        return .received(event: .memberArrived(publicId: publicId, version: payload.version))
    } catch {
        return .skipped(reason: "\(EVENT_MEMBER_ARRIVED) 파싱 실패: \(error)")
    }
}

// 서버가 필드를 추가해도 깨지지 않게 한다 — NetworkModule 의 REST 디코더와 같은 정책.
private func decodeSseData<T: Decodable>(_ data: String) throws -> T {
    try MoyeotaJSON.decoder.decode(T.self, from: Data(data.utf8))
}

private func decode(type: String, _ block: () throws -> PartySseEvent) -> PartySseFrame {
    do {
        return .received(event: try block())
    } catch {
        return .skipped(reason: "\(type) 파싱 실패: \(error)")
    }
}
