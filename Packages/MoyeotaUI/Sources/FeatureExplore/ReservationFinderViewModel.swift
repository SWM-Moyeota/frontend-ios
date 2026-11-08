import Foundation
import MoyeotaDomain
import Observation
import PresentationCore

/// 17 탐색의 **예약 방 조회** — 「곧 출발」(`/reservations/soon`)과 「날짜로 찾기」
/// (`/reservations/search`)를 한 뷰모델이 받는다.
///
/// 두 엔드포인트를 갈라 두지 않은 이유: 화면에서 **동시에 보이지 않는다**(모드가 하나다). 한 흐름에
/// 두면 모드를 바꾸는 순간 앞 조회를 **취소**하므로(`run`), 늦게 끝난 「곧 출발」 응답이
/// 「날짜로 찾기」 목록을 덮어쓰는 일이 구조적으로 불가능해진다 — 두 뷰모델이면 그 경쟁을
/// 화면에서 손으로 막아야 한다. 요청 모양의 차이는 `ReservationQuery` 가 들고 있다.
///
/// ### 폴링하지 않는다 ★ 실시간 목록과 가장 다른 점
/// `ExploreViewModel` 은 4초마다 다시 읽는다 — 실시간 방은 **지금 이 순간** 차고 비는 것이 전부라
/// 낡은 목록이 곧 「사라진 방의 합류」 버튼이 된다(`STALE_NOTICE_FAILURES` 의 근거). 예약은 그렇지
/// 않다: 사용자가 보는 값은 **몇 시에 출발하는가**이고 그건 바뀌지 않는다. 인원이 차는 일은 일어나지만
/// 그때의 대가는 합류 확인(20)에서 받는 409 `PARTY_FULL` 한 번이고(`joinGate` 가 이미 그 길을 안다),
/// 7일 치 목록을 4초마다 다시 읽는 비용과 바꿀 만하지 않다.
///
/// 다시 읽는 때는 셋이다: **모드·날짜·도착지를 바꿀 때**(새 `ReservationQuery`), **지도를 움직일 때**
/// (「곧 출발」의 범위가 바뀐다), 그리고 **화면에 돌아올 때**(`retry` — `ExploreRoute` 가 부른다).
/// 마지막 하나가 「탭을 다녀오면 최신이다」를 지킨다.
///
/// `NearbyCandidatesViewModel` 과 같은 모양이다(단발 조회 + 재시도 입력 하나). 그쪽의 주의도 그대로
/// 적용된다 — 같은 요청은 `request` 가 무시하므로 같은 입력으로 다시 조회하려면 `retry` 라는 두 번째
/// 입구가 필요하다.
///
/// 원본은 요청·재시도 두 `StateFlow` 를 `combine` 해 `flatMapLatest` 로 받는다. 여기서는 그 둘을
/// 메서드 두 개로 받고, 새 입력마다 앞 태스크를 끊고 새로 띄운다(`run`) — 「마지막 요청만 살아 있다」는
/// 같은 성질을 손으로 지킨다.
@MainActor
@Observable
public final class ReservationFinderViewModel {

    public enum UiState: Equatable, Sendable {
        /// **조회할 수 없다** — 실시간 모드이거나, 지도 범위·내 좌표·날짜 중 하나가 없다
        /// (`reservationQueryOrNull` 의 표). 화면은 이 상태에서 **실패를 말하지 않는다**:
        /// 아직 물어보지도 않았다.
        case idle
        case loading

        /// 서버가 준 순서 그대로의 목록. **재정렬하지 않는다** — 도착지를 보낸 검색은
        /// `destinationNearby == true` 가 먼저이고 그 안에서 출발 시각 순이다. 앱이 다시 정렬하면
        /// 그 두 단계 규칙을 베껴야 하고, 서버가 규칙을 바꾸면 목록이 서버와 다른 순서가 된다.
        ///
        /// 빈 목록은 **성공**이다(그 날 그 범위에 예약이 없을 뿐) — 실패와 다른 문구를 쓴다.
        case success(items: [ReservationCardUi])

        /// 조회 자체가 실패했다(네트워크·5xx·모르는 400). 「예약이 없다」와 **다른 상태**다 —
        /// 둘을 합치면 장애가 「그 날은 예약이 없네」로 위장되고 사용자는 날짜만 계속 바꾼다
        /// (16 추천의 `nearbyLoadFailed` 와 같은 근거).
        ///
        /// 400 은 사실상 앱 버그다(날짜 창·도착지 둘다/아니다·지도 범위를 전부 순수 함수가 막는다)
        /// — 그래서 사유별 문구를 두지 않고 한 문구 + 「다시 시도」로 받는다.
        case failed
    }

    public private(set) var uiState = UiState.idle

    @ObservationIgnored private let repository: any RideRepository
    @ObservationIgnored private let scope = ViewModelScope()
    @ObservationIgnored private var query: ReservationQuery?
    @ObservationIgnored private var job: Task<Void, Never>?

    public init(repository: any RideRepository) {
        self.repository = repository
    }

    /// 조회할 요청을 올린다. **nil 이면 비운다**(모드가 실시간으로 돌아갔거나 입력이 빠졌다) —
    /// 그때 목록을 들고 있으면 실시간 화면에 예약 카드가 한 프레임 남는다.
    ///
    /// 같은 요청으로 다시 부르는 것은 공짜다(원본 `StateFlow` 가 같은 값을 흘리지 않는 것과 같다) —
    /// 화면이 다시 그려질 때마다 불려도 서버를 두 번 때리지 않는다.
    ///
    /// 돌려주는 태스크는 테스트가 끝을 기다리는 용도다. 화면은 쓰지 않는다.
    // `internal` 인 이유: `ReservationQuery` 는 모듈 안의 조회 계약이라 internal 이고, 공개 멤버가 그
    // 타입을 받으면 「public 메서드가 internal 타입을 쓴다」로 컴파일이 막힌다. 부르는 곳은 같은
    // 모듈의 `ExploreRoute` 하나다.
    @discardableResult
    func request(_ query: ReservationQuery?) -> Task<Void, Never>? {
        if query == self.query { return nil }
        self.query = query
        return run()
    }

    /// 같은 요청을 한 번 더 — 「다시 시도」와 **화면 복귀**가 함께 쓴다.
    ///
    /// 복귀에 쓰는 것이 폴링을 대신한다: 예약 목록은 초 단위로 바뀌지 않지만 몇 분 전 목록을 그대로
    /// 보여 주면 이미 꽉 찬 방의 「합류」를 누르게 된다. 돌아올 때 한 번이면 그 창이 닫힌다.
    @discardableResult
    public func retry() -> Task<Void, Never>? {
        run()
    }

    /// 지금 요청으로 새로 조회한다 — 앞 조회는 **끊는다**(원본 `flatMapLatest` 자리).
    private func run() -> Task<Void, Never>? {
        job?.cancel()
        job = nil
        guard let query else {
            uiState = .idle
            return nil
        }
        uiState = .loading
        let repository = self.repository
        let task = scope.launch { [weak self] in
            do {
                let items = try await Self.fetch(query, repository: repository)
                // 코루틴은 취소되면 재개 자리에서 예외를 던지지만 Swift 는 끝난 호출의 값을 그대로 돌려준다.
                // 여기서 끊지 않으면 앞 모드·앞 날짜의 늦은 응답이 지금 목록을 덮는다.
                try Task.checkCancellation()
                self?.uiState = .success(items: items)
            } catch {
                // 끊긴 요청은 상태를 쓰지 않는다 — 새 요청이 곧 덮는다. 태스크가 살아 있는데 온
                // `URLError(.cancelled)` 는 원본 OkHttp `IOException` 처럼 조회 실패다.
                if Task.isCancelled { return }
                self?.uiState = .failed
            }
        }
        job = task
        return task
    }

    private static func fetch(
        _ query: ReservationQuery,
        repository: any RideRepository
    ) async throws -> [ReservationCardUi] {
        switch query {
        case .soon(let bounds):
            // 가시 영역보다 넓게 묻는다 — 실시간 목록과 **같은 이유·같은 함수**다(`MapBounds.expanded`):
            // 경계에 걸친 방이 카메라가 조금 움직일 때마다 빠졌다 들어오며 마커가 깜빡인다.
            let area = bounds.expanded()
            return try await repository.getReservationsSoon(
                swLat: area.swLat,
                swLng: area.swLng,
                neLat: area.neLat,
                neLng: area.neLng
            )
            .map { ReservationCardUi(ride: $0) }

        case .byDate(let departureLat, let departureLng, let date, let destination):
            // 도착지는 **둘 다 또는 둘 다 아니다** — 도메인 `ReservationDestination` 이 그 상태만
            // 담으므로 여기서 한쪽만 보내는 길이 **타입에 없다**(400 `INCOMPLETE_DESTINATION`).
            return try await repository.searchReservations(
                departureLat: departureLat,
                departureLng: departureLng,
                date: date,
                destination: destination
            )
            .map { ReservationCardUi(ride: $0.ride, destinationNearby: $0.destinationNearby) }
        }
    }
}
