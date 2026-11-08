import MoyeotaDomain

/// 노쇼 기록 조회 + 이의 신청만 읽고 쓰는 저장소.
///
/// ### 세션을 받지 않는다
/// 다른 저장소들이 `UserSession` 을 받는 이유는 조회가 아니라 **번역**
/// 이었다 — 서버가 「누가 나인지」를 표시해 주지 않아 매퍼가 `publicId == currentUserUuid` 로
/// 「나」를 만들어야 했다(`RemoteRideRepository`·`RemoteRideRecordRepository`). 이 두 호출에는 그
/// 번역이 **없다**: 응답에 멤버가 없고, 애초에 **전부 내 것**이다(주체는 Bearer 토큰이 정한다).
/// 받아 두면 쓰지 않는 의존이 생기고, 「세션이 필요하다」가 이 계층의 기본값처럼 보이게 된다.
///
/// ### `MatchingApi` 를 쓴다 — 전용 인터페이스를 만들지 않았다
/// 두 경로가 `/api/v1/matching/` 아래이고(`MatchingApi` 주석에 적은 대로
/// 서버 컨트롤러는 다르지만 프리픽스 합산 결과가 같다), 인증 클라이언트도 같다. 새 API
/// 인터페이스를 만들면 `NetworkModule`·`AppContainer` 를 함께 고쳐야 하는데 그 대가로 얻는 게 없다.
public final class RemoteNoShowRepository: NoShowRepository {
    private let api: any MatchingApi

    public init(api: any MatchingApi) {
        self.api = api
    }

    /// **실패를 감싸지 않는다.** 이 조회의 서버 실패는 401 하나뿐이고(업무 에러 코드가 없다) 화면의
    /// 대응도 하나다 — `RemoteRideRecordRepository.getMyRecords` 와 같은 판단이고, 사유별 문구가
    /// 필요한 액션만 전용 예외로 번역하는 것이 이 계층의 결이다.
    ///
    /// `do`/`catch` 를 두지 않는 것 자체가 취소 보존 장치다 — 감싸는 순간
    /// 일반 `catch` 가 취소까지 에러로 바꿔 화면 이탈이 에러 문구로 보이게 된다.
    ///
    /// **재정렬도, 걸러내기도 하지 않는다.** 받은 순서가 서버의 정렬(노쇼 시각 내림차순)이고,
    /// 무효가 된 건도 그대로 올린다 — 그 줄이 「이의가 받아들여졌다」는 유일한 증거라 걸러내면
    /// 사용자가 결과를 확인할 길이 없다(`NoShowRepository.getMyNoShows` 주석).
    public func getMyNoShows() async throws -> [NoShowRecord] {
        try await api.getMyNoShows().noShows.map { $0.toDomain() }
    }

    /// 이의 신청. 실패는 전부 `NoShowObjectionException` 으로 좁힌다 —
    /// **409 가 두 가지 뜻**이라 화면이 상태 코드만으로는 안내 문구를 가를 수 없다(그 예외 주석의 표).
    ///
    /// ### `reason` 을 다듬어 보낸다 — 그런데 **검사하지는 않는다** ★
    /// 앞뒤 공백만 뗀다. 서버가 `strip()` 하는 것과 **같은 처리**인데, 서버는 그걸 Bean Validation 을
    /// 통과한 **뒤에** 하므로 공백으로 패딩된 501자는 다듬으면 500자 이하여도 400 이다. 여기서 먼저
    /// 다듬으면 그 400 이 사라진다 — 사용자 입장에서 **같은 글인데 결과가 다른** 상황을 없애는 것이다.
    ///
    /// 반대로 **빈 값·길이 초과를 여기서 끊지는 않는다.** 그 판정을 들면 서버가 상한을 바꿀 때
    /// 앱만 뒤처지고(`confirmMeeting` 이 약속 시간을 검사하지 않는 것과 같은 이유), 무엇보다
    /// 「앱이 막은 실패」와 「서버가 막은 실패」가 같은 예외로 섞여 원인을 가릴 수 없게 된다.
    /// 화면이 입력란에서 막는 쪽으로 책임을 진다
    /// (`NoShowObjectionException.MAX_REASON_LENGTH` 를
    /// 입력란의 상한으로 함께 쓴다).
    ///
    /// **복구 조회도, 되돌림도 없다.** 서버가 검사를 먼저 하고 저장하므로 실패했으면 들어간 이의가
    /// 없고, 409 `ALREADY_OBJECTED` 를 성공으로 접지 않는 이유는 그 프로퍼티 주석에 있다.
    /// 성공했을 때 화면이 할 일은 `getMyNoShows` 재조회다 — 201 에 본문이 없어 상태를 알 길이 없다.
    public func submitObjection(partyId: Int64, reason: String) async throws {
        let request = NoShowObjectionRequestDto(reason: reason.trim())
        do {
            try await api.submitNoShowObjection(partyId: partyId, request: request)
        } catch where isCancellation(throwable: error) {
            // 취소는 되던져 화면 이탈이 에러로 보이지 않게 한다.
            throw error
        } catch {
            // 에러 본문은 한 번 읽어 들고 넘긴다.
            throw noShowObjectionException(failure: error, error: error.readApiError())
        }
    }
}
