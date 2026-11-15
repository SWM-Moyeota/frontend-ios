import Foundation
import MoyeotaDomain
import Observation
import PresentationCore

/// 17 탐색의 **예약 방 조회** — 「곧 출발」(`/reservations/soon`)과 「날짜로 찾기」
/// (`/reservations/search`)를 한 뷰모델이 받는다.
///
/// 두 엔드포인트를 갈라 두지 않은 이유: 화면에서 **동시에 보이지 않는다**(모드가 하나다). 한 조회 칸에
/// 두면 모드를 바꾸는 순간 앞 조회를 **끊으므로**(`ExploreRefreshCycle`), 늦게 끝난 「곧 출발」 응답이
/// 「날짜로 찾기」 목록을 덮어쓰는 일이 구조적으로 불가능해진다 — 두 뷰모델이면 그 경쟁을
/// 화면에서 손으로 막아야 한다. 요청 모양의 차이는 `ReservationQuery` 가 들고 있다.
///
/// ### 두 모드 모두 15초마다 다시 읽는다 ★ (2026-11, 오너 UX 피드백으로 두 번 바뀜)
/// 처음에는 두 모드 모두 **폴링하지 않았다**(「예약은 출발 시각이 바뀌지 않는다」). 다음에 「곧 출발」이
/// 실시간 목록과 같은 주기를 얻었다 — 30분 안에 출발하는 방이라 실시간만큼 빨리 낡는다. 지금은 「날짜로
/// 찾기」도 같다: 출발 시각은 그대로여도 **자리는 차고 빈다**. 세 탭이 같은 카운트다운 버튼·같은 「낡음」
/// 규칙을 갖는다(`ExploreRefresh.swift` 의 표).
///
/// 다시 읽는 때와 카운트다운에 주는 영향은 `ExploreRefreshCycle` 의 표 그대로다 — **모드·날짜·도착지를 바꾸면**
/// 즉시(새 목록), **지도를 움직이면** 디바운스 뒤(「곧 출발」의 범위), **화면에 돌아오면** 즉시, 새로고침
/// 버튼·「다시 시도」(`refreshNow`·`retry`), 그리고 15초마다. 숫자를 15로 되돌리는 것은 버튼과 화면 복귀뿐이다.
///
/// ### 같은 목록을 다시 읽을 때는 덮지 않고, 새 목록은 비워 둔다
/// 무엇이 **같은 목록**인지는 `sameListAs` 가 정한다 — 「곧 출발」은 지도 범위가 달라도, 「날짜로 찾기」는
/// 내 위치가 조금 달라도 같은 목록이다(날짜·도착지·모드가 목록을 정한다).
/// - **같은 목록**(주기·버튼·복귀·지도 이동): 보던 목록을 그대로 두고 그 위에 결과를 덮는다. 실패해도
///   목록을 남기고, 연속 `STALE_NOTICE_FAILURES` 회부터 「최신 정보를 받지 못했어요」를 켠다
///   (`UiState.success` 의 stale — 실시간과 같은 규칙·같은 숫자)
/// - **새 목록**(날짜·도착지·모드): `UiState.loading` — 화면은 목록 자리를 **비워 두고**(앞 날짜의 줄을 남기지
///   않는다) 헤더에 개수를 적지 않는다. 가운데 스피너도 없다 — 새로고침 버튼의 도는 고리가 유일한 로딩 표시다
///
/// 원본은 실시간 뷰모델과 같은 모양이다(상태 하나 + 시계). 같은 요청은 `request` 가 무시하므로 같은 입력으로 다시
/// 읽는 길은 `retry`·`refreshNow` 다.
@MainActor
@Observable
public final class ReservationFinderViewModel {

    public enum UiState: Equatable, Sendable {
        /// **조회할 수 없다** — 실시간 모드이거나, 지도 범위·내 좌표·날짜 중 하나가 없다
        /// (`reservationQueryOrNull` 의 표). 화면은 이 상태에서 **실패를 말하지 않는다**:
        /// 아직 물어보지도 않았다.
        case idle

        /// **새 목록을 아직 읽지 못했다**(날짜·도착지·모드를 바꿈, 첫 조회, 실패 뒤 「다시 시도」). 화면은 목록
        /// 자리를 비워 두고 헤더에 개수를 적지 않는다 — 앞 목록의 줄을 남기면 다른 날짜의 방에 「합류」하게 된다.
        case loading

        /// 서버가 준 순서 그대로의 목록. **재정렬하지 않는다** — 도착지를 보낸 검색은
        /// `destinationNearby == true` 가 먼저이고 그 안에서 출발 시각 순이다. 앱이 다시 정렬하면
        /// 그 두 단계 규칙을 베껴야 하고, 서버가 규칙을 바꾸면 목록이 서버와 다른 순서가 된다.
        ///
        /// 빈 목록은 **성공**이다(그 날 그 범위에 예약이 없을 뿐) — 실패와 다른 문구를 쓴다.
        ///
        /// `stale` 은 이 목록의 갱신이 **연속으로** 실패했다는 뜻이다 — 목록은 그대로 두고 화면이
        /// 비차단 표시만 올린다(실시간 `ExploreViewModel.UiState.success` 의 stale 과 같다).
        case success(items: [ReservationCardUi], stale: Bool = false)

        /// 조회 자체가 실패했다(네트워크·5xx·모르는 400). 「예약이 없다」와 **다른 상태**다 —
        /// 둘을 합치면 장애가 「그 날은 예약이 없네」로 위장되고 사용자는 날짜만 계속 바꾼다
        /// (16 추천의 `nearbyLoadFailed` 와 같은 근거).
        ///
        /// 400 은 사실상 앱 버그다(날짜 창·도착지 둘다/아니다·지도 범위를 전부 순수 함수가 막는다)
        /// — 그래서 사유별 문구를 두지 않고 한 문구 + 「다시 시도」로 받는다.
        case failed
    }

    public private(set) var uiState = UiState.idle

    /// 예약 모드의 **카운트다운 새로고침 버튼**이 그릴 것(`ExploreRefresh.swift`). 실시간 모드에서는 화면이
    /// 실시간 뷰모델의 버튼을 그리므로 이 값을 읽지 않는다. 원본 이름은 `refresh` 다(`ExploreViewModel.refreshUi` 와 같은 이름으로 맞췄다).
    public private(set) var refreshUi = ExploreRefreshUi(refreshing: true)

    @ObservationIgnored private let repository: any RideRepository
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    /// 지금 물어볼 조회 — 화면이 마지막으로 올린 것(`request`).
    @ObservationIgnored private var query: ReservationQuery?

    /// 마지막 성공 뒤 연속 실패 횟수 — 무엇이 부른 조회든 같이 센다(`STALE_NOTICE_FAILURES`). 새 목록은 성공해야
    /// 줄이 생기고 그 성공이 0 으로 돌리므로, 앞 목록의 실패가 새 목록의 「낡음」으로 번지지 않는다.
    @ObservationIgnored private var failures = 0

    /// 갱신 시계와 조회 칸(`ExploreRefresh.swift`). **보이고 물어볼 것이 있는 동안만** 돈다 — 실시간 모드(요청 nil)나
    /// 가려진 동안에는 카운트다운도 돌지 않는다. 뷰모델이 해제되면 함께 해제되며 태스크가 모두 끊긴다.
    // 원본은 생성자에서 `viewModelScope` 와 `::load` 를 넘긴다. Swift 는 저장 프로퍼티가 다 채워지기 전에 self 를
    // 잡을 수 없어 처음 쓸 때 만든다.
    @ObservationIgnored private lazy var cycle = ExploreRefreshCycle<ReservationQuery>(
        sleep: sleep,
        load: { [weak self] query in await self?.load(query) },
        onUi: { [weak self] ui in self?.setRefresh(ui) }
    )

    public convenience init(repository: any RideRepository) {
        self.init(repository: repository, sleep: { try await Task.sleep(for: $0) })
    }

    init(
        repository: any RideRepository,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.repository = repository
        self.sleep = sleep
    }

    /// 조회할 요청을 올린다. **nil 이면 비운다**(모드가 실시간으로 돌아갔거나 입력이 빠졌다) —
    /// 그때 목록을 들고 있으면 실시간 화면에 예약 카드가 한 프레임 남는다.
    ///
    /// 같은 요청으로 다시 부르는 것은 공짜다(원본도 같은 요청은 무시한다) — 화면이 다시 그려질 때마다 불려도
    /// 서버를 두 번 때리지 않는다. 언제 읽는지는 `reservationLoadTiming` 이 정하고, **카운트다운은 건드리지 않는다**.
    ///
    /// 돌려주는 태스크(지금 나간 조회)는 테스트가 끝을 기다리는 용도다. 화면은 쓰지 않는다. 가려져 있거나
    /// 지금 읽지 않으면(디바운스·다음 자동 갱신) nil 이다.
    // `internal` 인 이유: `ReservationQuery` 는 모듈 안의 조회 계약이라 internal 이고, 공개 멤버가 그
    // 타입을 받으면 「public 메서드가 internal 타입을 쓴다」로 컴파일이 막힌다. 부르는 곳은 같은
    // 모듈의 `ExploreRoute` 하나다.
    @discardableResult
    func request(_ query: ReservationQuery?) -> Task<Void, Never>? {
        if query == self.query { return nil }
        let previous = self.query
        self.query = query
        guard let query else {
            setState(.idle)
            return cycle.update(nil, timing: .now)
        }
        if previous.map({ !$0.sameListAs(query) }) ?? true {
            // 새 목록 — 앞 목록의 줄을 남기지 않는다(다른 날짜의 방이다)
            setState(.loading)
        }
        return cycle.update(
            query,
            timing: reservationLoadTiming(
                previous: previous,
                next: query,
                listShown: isShowingList,
                fetching: cycle.isFetching
            )
        )
    }

    /// 화면이 보이기 시작했다 — 지금 조회를 즉시 한 번 읽고(덮지 않고) 카운트다운을 15부터 새로 센다.
    ///
    /// 이미 보이는 상태면 아무것도 하지 않는다(원본 `StateFlow` 가 같은 값을 흘리지 않는 것과 같다).
    @discardableResult
    public func onScreenStart() -> Task<Void, Never>? {
        cycle.setVisible(true)
    }

    /// 화면이 가려졌다 — 조회·카운트다운을 멈춘다. 보던 목록은 그대로 둔다.
    public func onScreenStop() {
        cycle.setVisible(false)
    }

    /// 「다시 시도」 — 같은 요청을 한 번 더. 실패 화면에서 누른다. 실패 문구를 비우고(버튼이 돈다) 읽는다.
    /// 카운트다운은 그대로다.
    @discardableResult
    public func retry() -> Task<Void, Never>? {
        guard cycle.isRunning else { return nil }
        if uiState == .failed { setState(.loading) }
        return cycle.retry()
    }

    /// 예약 모드의 **새로고침 버튼** — 즉시 다시 읽고 15부터 다시 센다. 보던 목록은 덮지 않는다.
    /// 조회가 나가 있는 동안 들어온 탭은 버린다(실시간 `ExploreViewModel.refreshNow` 와 같다).
    @discardableResult
    public func refreshNow() -> Task<Void, Never>? {
        cycle.refreshNow()
    }

    /// 조회 하나를 읽어 화면에 반영한다 — 무엇이 불렀든(자동 갱신·지도 이동·버튼·복귀·새 목록) 같은 길이다.
    ///
    /// 실패 처리는 **보여 줄 목록이 있느냐**로 갈린다: 없으면 `UiState.failed`(실패를 말한다), 있으면
    /// 목록을 남기고 연속 실패를 센다(`staleAfterPollFailures`). 실시간 목록과 같은 판단이다. 보여 주는
    /// 목록은 늘 이 조회와 **같은 목록**이다 — 새 목록은 `request` 가 먼저 `loading` 으로 비우고 앞 조회를 끊는다.
    private func load(_ query: ReservationQuery) async {
        let items: [ReservationCardUi]?
        do {
            items = try await Self.fetch(query, repository: repository)
        } catch {
            // 끊긴 요청은 상태를 쓰지 않는다 — 새 입력이 곧 덮는다. 태스크가 살아 있는데 온
            // `URLError(.cancelled)` 는 원본 OkHttp `IOException` 처럼 조회 실패다.
            if Task.isCancelled { return }
            items = nil
        }
        // 코루틴은 취소되면 재개 자리에서 예외를 던지지만 Swift 는 끝난 호출의 값을 그대로 돌려준다.
        // 여기서 끊지 않으면 앞 모드·앞 날짜의 늦은 응답이 지금 목록을 덮는다.
        if Task.isCancelled { return }
        if let items {
            failures = 0
            setState(.success(items: items))
            return
        }
        failures += 1
        if case .success(let shown, let stale) = uiState {
            // 목록은 남기고 「낡음」만 켠다 — 지금 보이는 목록을 실패 문구로 갈아엎지 않는다
            if staleAfterPollFailures(consecutiveFailures: failures) && !stale {
                setState(.success(items: shown, stale: true))
            }
        } else {
            // 보여 줄 목록이 없다 — 「없다」가 아니라 **못 물어봤다**를 말한다
            setState(.failed)
        }
    }

    /// 지금 목록을 보여 주고 있는가 — 지도 이동을 디바운스할지 가른다(`reservationLoadTiming`).
    private var isShowingList: Bool {
        if case .success = uiState { return true }
        return false
    }

    /// `MutableStateFlow` 처럼 같은 값은 내보내지 않는다 — 주기 결과가 그대로일 때 화면을 다시 그리지 않는다.
    private func setState(_ next: UiState) {
        if uiState != next { uiState = next }
    }

    private func setRefresh(_ next: ExploreRefreshUi) {
        if refreshUi != next { refreshUi = next }
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

extension ReservationQuery {
    /// 두 조회가 **같은 목록**을 읽는가 — 같으면 다시 읽는 동안 보던 목록을 그대로 두고, 다르면 목록 자리를 비운다.
    ///
    /// | 조회 | 같은 목록의 조건 | 달라도 되는 것 |
    /// |---|---|---|
    /// | 「곧 출발」 | 둘 다 「곧 출발」 | 지도 범위 — 지도를 옮겨도 같은 「지도에 보이는 범위의 30분 안」 목록이다(실시간이 지도 이동에 목록을 남기는 것과 같다) |
    /// | 「날짜로 찾기」 | 날짜·도착지가 같다 | 내 위치 — GPS 가 몇 m 흔들려도 「내 위치에서 1km」라는 같은 목록이다 |
    ///
    /// 모드가 다르면 늘 다른 목록이다(영역이 다르다 — `ReservationFinder.swift` 의 1급 사실 표).
    func sameListAs(_ other: ReservationQuery) -> Bool {
        switch (self, other) {
        case (.soon, .soon):
            true
        case let (.byDate(_, _, date, destination), .byDate(_, _, otherDate, otherDestination)):
            date == otherDate && destination == otherDestination
        default:
            false
        }
    }
}

/// 예약 조회가 바뀌었을 때 **언제 읽는가** — 카운트다운은 어느 쪽이든 건드리지 않는다.
///
/// 위에서부터 읽는다.
///
/// | 바뀐 것 | 언제 | 이유 |
/// |---|---|---|
/// | 처음이거나 다른 목록(`sameListAs`: 모드·날짜·도착지) | `now` | 사용자가 방금 고른 것이다 — 기다리면 고른 게 먹지 않은 것처럼 보인다 |
/// | 「날짜로 찾기」의 내 위치 (목록 유무와 상관없이) | `nextTick` | 위치는 1초마다 몇 m 씩 흔들린다. 그때마다 읽으면 1km 검색이 1초마다 나간다 — 다음 자동 갱신(길어야 15초)이 새 위치로 읽는다 |
/// | 「곧 출발」의 지도 범위 · 목록이 보이는 중 | `debounced` | 팬·줌 연타의 중간 범위마다 서버를 때리지 않는다(실시간과 같은 디바운스) |
/// | 「곧 출발」의 지도 범위 · 보여 줄 목록이 없다 | `now` | 늦출 이득이 없다 |
///
/// ### 목록이 없을 때(실패 화면)도 「날짜로 찾기」의 위치 변화는 다음 갱신에 맡기는 이유 (원본 리뷰 반영 3차, PR #99)
/// 2차에서 실패 화면은 새 위치를 디바운스 뒤에 바로 읽게 했었다. 그런데 내 위치는 **1초마다** 바뀌어서, 망이 **빨리
/// 실패하는** 때(오프라인 등)에는 실패 → 빈 자리 → 다음 위치 → 다시 조회가 15초 주기와 상관없이 약 1초마다 되풀이됐다.
/// 그래서 목록 유무와 상관없이 다음 자동 갱신(길어야 15초)에 맡긴다. 실패 화면에서 바로 다시 읽고 싶으면 사용자가
/// 「다시 시도」나 새로고침 버튼을 누른다 — 그 길은 그대로 바로 읽는다.
///
/// - Parameters:
///   - listShown: 지금 이 목록을 보여 주고 있는가(`ReservationFinderViewModel.UiState.success`)
///   - fetching: 조회가 나가 있는가(`ExploreRefreshCycle.isFetching`). 지금 규칙은 보지 않는다 — 2차 규칙의 흔적이고,
///     호출부와 테스트가 같은 모양으로 남아 있어 다시 갈래가 필요할 때 쓰도록 둔다
func reservationLoadTiming(
    previous: ReservationQuery?,
    next: ReservationQuery,
    listShown: Bool,
    fetching: Bool
) -> ExploreLoadTiming {
    guard let previous, previous.sameListAs(next) else { return .now }
    if case .byDate = next { return .nextTick }
    return listShown ? .debounced : .now
}
