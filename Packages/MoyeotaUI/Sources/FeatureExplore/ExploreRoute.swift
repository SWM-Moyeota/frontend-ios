import Foundation
import MoyeotaDesignSystem
import MoyeotaDomain
import Observation
import PresentationCore
import SwiftUI

// 같은 범위 재조회 주기(`NEARBY_POLL_INTERVAL_MS`, 15초)·카운트다운·지도 디바운스(`BOUNDS_DEBOUNCE_MS`)와 그
// 시계(`ExploreRefreshCycle`)는 `ExploreRefresh.swift` 에 있다 — 예약 조회(`ReservationFinderViewModel`)가 같은
// 규칙으로 돌아야 해서 한 곳으로 옮겼다.
//
// **이 주기는 화면이 보이는 동안에만 돈다**(`ExploreViewModel.onScreenStart`). 탐색은 하단탭이라
// 다른 화면이 위에 올라와도 뷰모델이 살아 있어서, 게이트가 없으면 21 매칭 대기·채팅에
// 머무는 내내 범위 조회가 나갔다(QA D-1: 4초 주기 시절 21 체류 135초에 34회).

/// 몇 번 연속으로 갱신에 실패하면 「최신 정보를 받지 못했어요」를 띄우는가 (`staleAfterPollFailures`).
///
/// ### 무엇을 세는가 — 카운트다운을 지도와 떼어 낸 뒤(2026-11, 오너 UX 피드백 2차)
/// **보여 주는 목록을 다시 읽으려다 실패한 횟수**를, 무엇이 그 조회를 불렀는지와 상관없이 마지막 성공부터 센다
/// — 자동 갱신(0 에 닿음)·지도 이동(디바운스 뒤 조회)·새로고침 버튼·「다시 시도」·화면 복귀가 모두 같은
/// 카운터에 들어간다. **성공 한 번**이 0 으로 돌린다. 끊긴 조회(가려짐·더 새 입력)는 세지 않는다 — 세면 지도를
/// 두 번 움직인 것만으로 경고가 뜬다. 「곧 출발」·「날짜로 찾기」에서 **다른 목록**(날짜·도착지·모드)으로
/// 바뀌면 그 목록은 성공해야 줄이 생기고, 그 성공이 카운터를 0 으로 돌린다 — 앞 목록의 실패가 새 목록의
/// 「낡음」으로 번지지 않는다(그 전의 실패는 「불러오지 못했어요」다).
///
/// 예전에는 패스(범위 하나)마다 새로 셌다. 지도를 움직이면 패스가 바뀌었으니 「지도 이동 실패」는 셀 자리가
/// 없었다. 지금은 지도 이동이 패스를 열지 않으므로 끊어 셀 경계가 없고, **지도 이동 실패가 오히려 가장 분명한
/// 낡음**이다 — 실패하면 화면의 목록은 지금 보는 동네의 것이 아니다. 화면 복귀로도 0 이 되지 않는다:
/// 가려진 동안 목록은 더 오래됐을 뿐 새로워지지 않았다.
///
/// ### 왜 2회인가 — 같은 두 조건을 다시 맞춘다
/// | 조건 | 4초 × 3 = 12초(예전) | 2회 · 15초 시계 |
/// |---|---|---|
/// | 한 번의 끊김으로는 알리지 않는다 | ✓ | ✓ — 두 번의 **서로 다른** 시도가 실패해야 한다 |
/// | 지하철 역 사이 터널(보통 1~2분)보다 짧다 — **진짜 끊김은 반드시 드러난다** | ✓ | ✓ — 보이는 동안 자동 갱신이 15초마다 반드시 한 번 읽으므로 첫 실패부터 **길어야 30초** |
///
/// 지도 이동은 그 사이에 시도를 **더할** 뿐이라 알림을 앞당길 수는 있어도 늦추지 않는다(위 30초가 상한이다).
/// 1회로 두면 터널·엘리베이터처럼 금방 복구되는 끊김마다 경고가 깜빡이고, 그러면 사용자가 곧 무시하게 된다.
/// 3회(45초)는 「탭했을 때 이미 틀린 목록일 수 있다」를 너무 오래 숨긴다 — 방이 차고 비는 주기가 분 단위라
/// 45초면 목록의 상당 부분이 바뀌어 있다. 반대로 상한이 **아예 없으면**(고치기 전의 동작) 실패가 조용히 버려져
/// 낡은 마커가 **영구히** 남고, 사용자는 이미 사라진 방의 「합류」를 눌러 20 에서야 「사라진 방이에요」를 본다.
///
/// 이미 켜진 「낡음」 표시는 조회가 한 번 성공해야 꺼진다.
let STALE_NOTICE_FAILURES = 2

@MainActor
@Observable
public final class ExploreViewModel {
    public enum UiState: Equatable, Sendable {
        /// 아직 한 번도 읽지 못했다(첫 조회·에러 화면의 「다시 시도」). 화면은 지도와 빈 목록을 그리고
        /// 새로고침 버튼의 도는 고리만으로 기다리게 한다 — 가운데 스피너를 두지 않는다(버튼이 없는 위치 권한 거부
        /// 경로는 목록 맨 위의 작은 스피너, `showListLoadingFallback`).
        case loading

        /// 그릴 목록 하나. `stale` 은 「보여 주고는 있지만 갱신이 연속 실패했다」는 뜻이다
        /// (`STALE_NOTICE_FAILURES`) — 목록을 **치우지 않고** 화면이 비차단 표시만 올린다.
        /// 조회가 한 번이라도 성공하면 그 결과로 교체되므로 자동으로 false 로 돌아온다.
        case success(parties: [Ride], stale: Bool = false)
        case error(message: String)
    }

    public private(set) var uiState: UiState = .loading

    /// 지도 오른쪽 아래 **카운트다운 새로고침 버튼**이 그릴 것(`ExploreRefresh.swift`). 조회가 나가 있으면
    /// `ExploreRefreshUi.refreshing`, 아니면 다음 자동 갱신까지 남은 초다.
    ///
    /// 첫 조회 전에는 「조회 중」으로 시작한다 — 화면이 열리자마자 즉시 1회 읽기 때문이다.
    ///
    /// 원본 이름은 `refresh` 다(`StateFlow`). Kotlin 은 같은 이름의 프로퍼티와 함수(「다시 시도」 `refresh()`)를
    /// 함께 둘 수 있지만 Swift 는 막아서 `refreshUi` 로 적는다.
    public private(set) var refreshUi = ExploreRefreshUi(refreshing: true)

    @ObservationIgnored private let repository: any RideRepository
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    /// 마지막으로 받은 지도 범위 — 이 뷰모델의 조회 입력 전부다.
    @ObservationIgnored private var bounds: MapBounds?

    /// 마지막 성공 뒤 연속 실패 횟수 — 무엇이 부른 조회든 같이 센다(`STALE_NOTICE_FAILURES`).
    @ObservationIgnored private var failures = 0

    /// 갱신 시계와 조회 칸(`ExploreRefresh.swift`). **화면이 보이는 동안만** 돈다 — 가시성은 `onScreenStart`·
    /// `onScreenStop` 으로 받는다.
    ///
    /// 탭 뷰모델은 다른 화면이 위에 올라와도 살아 있고, `ViewModelScope` 는 화면이 보이는지 보지 않는다.
    /// 그래서 신호 없이는 21 매칭 대기·채팅에 머무는 동안에도 범위 조회가 계속 나간다 — 「평상시 네트워크 0」을
    /// 그 루프가 상쇄했다(QA D-1). 가려지는 순간 카운트다운·나가 있던 조회가 함께 끊기고, 다시 보이면 마지막
    /// 범위로 **즉시 1회** 읽은 뒤 15부터 센다. 뷰모델이 해제되면 함께 해제되며 태스크가 모두 끊긴다.
    // 원본은 생성자에서 `viewModelScope` 와 `::load` 를 넘긴다. Swift 는 저장 프로퍼티가 다 채워지기 전에 self 를
    // 잡을 수 없어 처음 쓸 때 만든다.
    @ObservationIgnored private lazy var cycle = ExploreRefreshCycle<MapBounds>(
        sleep: sleep,
        load: { [weak self] bounds in await self?.load(bounds) },
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

    /// 화면이 보이기 시작했다 — **즉시 1회 조회**하고 카운트다운을 15부터 새로 센다.
    ///
    /// 탭 복귀·앱 복귀·위에 있던 화면의 pop 이 모두 이 길로 온다(`lifecycleEffect`).
    /// 숨어 있던 동안 보던 목록은 그대로 두고 그 위에 새 결과를 덮으므로 로딩으로 깜빡이지 않는다(`load`).
    /// 첫 조회가 실패해 에러 화면이던 경우도 여기서 함께 복구된다.
    public func onScreenStart() {
        cycle.setVisible(true)
    }

    /// 화면이 가려졌다(탭 이동·다른 화면 진입·앱 백그라운드) — 주기 조회를 멈춘다.
    ///
    /// 들고 있던 목록·지도 카메라는 건드리지 않는다. 돌아올 때 그 목록을 그대로 보여주고
    /// 새로 읽은 결과로 덮는 게 맞기 때문이다.
    public func onScreenStop() {
        cycle.setVisible(false)
    }

    /// 지도에 보이는 영역이 바뀌었다(카메라 idle). 첫 진입 시에는 기준점 범위로 한 번 호출한다.
    ///
    /// 새 범위는 곧바로 읽되(`nearbyLoadTiming` — 목록이 있으면 `BOUNDS_DEBOUNCE_MS` 뒤) **카운트다운은 건드리지
    /// 않는다** — 지도를 조금씩 옮겨 보는 동안에도 숫자는 끝까지 내려가고, 0 에서 그때의 범위로 다시 읽는다.
    ///
    /// 지도 마커와 시트 목록은 **여기서 받아온 하나의 목록**에서 나온다 — 화면 밖 방이
    /// 리스트에만 남아 있는 상태를 만들지 않는다.
    public func onVisibleBoundsChange(_ bounds: MapBounds) {
        if self.bounds == bounds { return } // idle 이 같은 범위로 다시 와도 재조회하지 않는다
        self.bounds = bounds
        cycle.update(bounds, timing: nearbyLoadTiming(listShown: hasParties()))
    }

    /// 지도가 범위를 알려주기 전의 **기준 범위** — 아직 어떤 범위도 받지 못했을 때만 쓴다.
    ///
    /// Route 의 진입 이펙트는 탭을 다녀오면 **다시 실행된다**. 그때도 기준 범위를 밀어 넣으면
    /// ① 복원된 카메라와 **다른 동네의 목록**이 잠깐 보이고(지도는 보던 자리에 있는데
    /// 리스트·마커만 기준점 주변으로 바뀐다) ② 복귀 즉시 조회가 그 엉뚱한 범위로 가 버린다.
    /// 그래서 「첫 범위」라는 뜻을 여기서 지킨다 — 복귀는 `onScreenStart` 가 마지막 범위로 처리한다.
    public func onInitialBounds(_ bounds: MapBounds) {
        if self.bounds != nil { return }
        onVisibleBoundsChange(bounds)
    }

    /// 에러 화면의 「다시 시도」 — 마지막으로 본 범위를 그대로 다시 읽는다. 카운트다운은 그대로다.
    ///
    /// 에러 화면을 지도 + 빈 목록(+ 도는 버튼)으로 바꿔 눌렀다는 것을 보여 준다. 자동 갱신의 재시도는
    /// 에러 화면을 그대로 둔다 — 15초마다 에러 화면과 지도가 번갈아 깜빡이지 않게.
    public func refresh() {
        guard cycle.isRunning else { return } // 아직 범위조차 못 받았거나 가려져 있다
        if case .error = uiState { setState(.loading) }
        cycle.retry()
    }

    /// 지도의 **새로고침 버튼** — 지금 범위를 즉시 다시 읽고 카운트다운을 15부터 다시 센다.
    ///
    /// 목록이 있으면 로딩으로 덮지 않는다(`load`) — 버튼이 도는 동안 보던 목록은 그대로다. 조회가 나가 있는
    /// 동안 눌린 것은 버린다(`ExploreRefreshCycle.refreshNow`).
    public func refreshNow() {
        cycle.refreshNow()
    }

    /// 범위 하나를 읽어 화면에 반영한다 — 무엇이 불렀든(자동 갱신·지도 이동·버튼·복귀) 같은 길이다.
    ///
    /// 성공하면 그 목록으로 바꾼다(「낡음」도 꺼진다). 실패하면 **보여 줄 목록이 있느냐**로 갈린다: 있으면
    /// 목록을 남기고 연속 실패를 센다(`staleAfterPollFailures`) — 지도를 통째로 에러 화면으로 바꾸지 않는다
    /// (21 대기 화면과 같은 판단). 없으면(첫 조회) 에러 화면이다.
    private func load(_ bounds: MapBounds) async {
        let parties: [Ride]?
        do {
            parties = try await bounds.query(repository)
        } catch {
            // 범위가 바뀌었거나 **화면이 가려져** 끊긴 것 — 실패가 아니므로 세지도, 에러로 바꾸지도 않는다.
            //
            // 판정은 **이 태스크가 취소됐는가**만 본다(`isCancellation` 을 쓰지 않는다). 태스크가 살아 있는데 온
            // `URLError(.cancelled)` 는 시스템이 전송을 끊은 것으로, 원본에서는 OkHttp 의 `IOException` 이라
            // 아래 실패 경로로 간다. 이걸 끊긴 것으로 보면 첫 조회였을 때 재시도 버튼도 없는 로딩에 멈춘다.
            if Task.isCancelled { return }
            parties = nil
        }
        // 코루틴은 취소되면 대기 지점에서 던져 여기까지 오지 않는다. URLSession 은 취소와 응답이 엇갈릴 수 있어
        // 직접 본다 — 앞 범위의 결과가 새 범위 위에 덮이면 안 된다.
        if Task.isCancelled { return }
        if let parties {
            failures = 0
            setState(.success(parties: parties))
            return
        }
        failures += 1
        if case .success(let shown, let stale) = uiState {
            // 목록은 남기고 **버리지 않고 세어 둔다** — 상한이 없던 동안 낡은 마커가 영구히 남았다
            if staleAfterPollFailures(consecutiveFailures: failures) && !stale {
                setState(.success(parties: shown, stale: true))
            }
        } else {
            setState(.error(message: "동승 목록을 불러오지 못했어요"))
        }
    }

    /// `MutableStateFlow` 처럼 같은 값은 내보내지 않는다 — 폴링 결과가 그대로일 때 화면을 다시 그리지 않는다.
    private func setState(_ next: UiState) {
        if uiState != next { uiState = next }
    }

    /// 버튼 상태도 같은 값은 다시 쓰지 않는다 — 1초마다 그리는 값이라 같은 값에 화면을 깨우지 않는다.
    private func setRefresh(_ next: ExploreRefreshUi) {
        if refreshUi != next { refreshUi = next }
    }

    private func hasParties() -> Bool {
        if case .success = uiState { return true }
        return false
    }
}

private extension MapBounds {
    // 인자 순서(남서 위도 → 남서 경도 → 북동 위도 → 북동 경도)를 한 곳에서만 쓴다.
    // 뒤바뀌면 서버가 오류 대신 빈 목록을 돌려주므로 호출부마다 풀어 쓰면 눈에 띄지 않는 버그가 된다.
    // 가시 영역보다 넓게 묻는다 — 경계에 걸친 방이 카메라가 조금 움직일 때마다 빠졌다 들어오며
    // 마커가 깜빡이는 것을 막는다(`MapBounds.expanded` 설명 참고).
    func query(_ repository: any RideRepository) async throws -> [Ride] {
        let area = expanded()
        return try await repository.getPartiesWithin(
            swLat: area.swLat,
            swLng: area.swLng,
            neLat: area.neLat,
            neLng: area.neLng
        )
    }
}

/// 17 탐색 모드(`ExploreMode`)를 맡겨 두는 `TabSavedState` 키 — 원본 `rememberSaveable` 의 `mode` 자리.
let ExploreModeKey = "explore.mode"

/// 「날짜로 찾기」의 고른 날짜(오늘로부터의 일수)를 맡겨 두는 키 — 원본 `rememberSaveable` 의 `dateOffset` 자리.
let ExploreDateOffsetKey = "explore.dateOffset"

// 17–19 합승 탐색 — 서버 목록 연동 진입점
public struct ExploreRoute: View {
    /// 지금 진행 중인 내 방(`ActivePartyViewModel.resolve` 결과). nil 이면 상단 배너를 그리지 않는다
    private let activeRide: Ride?
    /// 「날짜로 찾기」에 **실어 보낼 도착지**. nil 이면 도착지 없이 검색한다(서버 계약: 둘 다
    /// 또는 둘 다 아니다 — 보내면 도착지도 가까운 방이 먼저 온다).
    ///
    /// 이 값은 15 목적지에서 고른 장소이고 **호출부(MainNavGraph)가 들고 있어야 한다** — 탐색은
    /// 하단탭이라 장소를 고르러 가면 이 화면이 내려간다. 배선이 없으면 nil 로 남고 기능은
    /// 「도착지 없이 검색」으로 정상 동작한다(`onPickSearchDestination` 이 nil 이면 칩도 안 뜬다).
    private let searchDestination: Place?
    private let onJoinParty: (Ride) -> Void
    private let onOngoingRideClick: () -> Void
    /// 「새 동승 방 만들기」 — **지금 보고 있는 탭의 뜻을 함께 넘긴다.**
    ///
    /// 인자(`scheduled`)는 「16 모달을 시간 정하기로 열까」다. 예약 탭(`soon`·`byDate`)을 보다 누른 사람은
    /// **예약 방을 찾다가 없어서** 만들러 가는 것이라, 거기서 「지금 출발」로 열면 사용자가 방금까지 한 일을
    /// 화면이 잊은 꼴이 된다. 실시간 탭에서는 지금까지와 같다(false).
    private let onCreateRoomClick: (Bool) -> Void
    /// 도착지를 고르러 15 목적지로. **nil 이면 칩을 그리지 않는다**(배선 안 된 버튼을 보여 주지 않는다)
    private let onPickSearchDestination: (() -> Void)?
    private let onClearSearchDestination: () -> Void
    private let onTabSelect: (MoyeotaTab) -> Void

    @HostedViewModel private var viewModel: ExploreViewModel
    @HostedViewModel private var finderViewModel: ReservationFinderViewModel

    // 지도가 화면의 본체라 탭 진입 시 권한을 요청한다.
    // 목록 로딩·에러 분기 **밖**에서 잡아야 조회가 실패해도 권한 흐름이 죽지 않는다.
    @RememberMyLocationState private var myLocation

    @Environment(\.tabSavedState) private var tabSavedState

    // ─── 예약 모드 상태 ───────────────────────────────────────────────────────
    //
    // 모드·날짜는 **화면 상태**다(뷰모델이 아니다). 둘 다 「지금 무엇을 보고 있는가」이고
    // 탭을 다녀와도 살아남아야 하지만 서버에서 오는 값이 아니다 — 17 의 시트 단계·지도 카메라와
    // 같은 자리다. 뷰모델에 두면 조회 입력과 화면 상태가 한 덩어리가 되어, 모드를 되돌릴 때
    // 목록을 비우는 순서를 손으로 맞춰야 한다.
    //
    // 원본 `rememberSaveable` 자리라 시트 단계(`ExploreSheetStateKey`)처럼 `TabSavedState` 에 맡긴다 —
    // 이 뷰는 탭을 다녀오면 새로 만들어져 `@State` 가 처음 값으로 돌아오므로, 처음 읽을 때는 맡겨 둔
    // 값에서 시작하고(nil 이면 아직 이 뷰에서 고른 적이 없다) 바꿀 때마다 함께 적어 둔다.
    @State private var selectedMode: ExploreMode?
    // 날짜는 **오늘로부터의 일수**로 들고 있는다(16 모달의 `dateOffset` 과 같은 처방) — 날짜 객체로
    // 들고 있으면 자정을 넘길 때 목록에 없는 날이 선택된 채 남는다.
    @State private var selectedDateOffset: Int?
    // 날짜 띠·출발 시각 표기의 기준 시각. **화면이 보일 때마다 다시 읽는다** — 탐색은 하단탭이라
    // 뷰모델이 탭 칸에 남고, 고정 기준을 쓰면 자정을 넘긴 뒤에도 어제가 「오늘」로 남는다
    // (그 날짜는 서버 창을 벗어나 400 `INVALID_SEARCH_DATE` 다). 그릴 때마다 읽지 않는 이유는
    // 그러면 칩 목록이 1초마다 새로 만들어져 고른 칩이 손가락 아래에서 움직이기 때문이다.
    @State private var now = Date()
    // 「곧 출발」이 쓰는 지도 범위. 실시간 목록과 **같은 신호**를 받아 둔다 — 지도는 하나이고
    // 모드를 바꿀 때마다 카메라가 다시 idle 을 내지 않으므로(사용자가 건드리지 않으면) 마지막
    // 범위를 기억해 두지 않으면 모드를 바꾼 직후 조회할 범위가 없다.
    @State private var visibleBounds: MapBounds?
    // 화면이 지금 시작 상태인가(`lifecycleEffect`). 원본 `LifecycleStartEffect` 는 키(`mode`)가 바뀌면
    // 시작 상태에서 효과를 다시 돌리는데, `lifecycleEffect` 에는 키가 없어 모드 변경을 따로 받는다 —
    // 그때 화면이 가려져 있으면 아무것도 하지 않아야 해서 이 값을 들고 있는다.
    @State private var screenStarted = false

    public init(
        repository: any RideRepository,
        activeRide: Ride? = nil,
        searchDestination: Place? = nil,
        onJoinParty: @escaping (Ride) -> Void = { _ in },
        onOngoingRideClick: @escaping () -> Void = {},
        onCreateRoomClick: @escaping (Bool) -> Void = { _ in },
        onPickSearchDestination: (() -> Void)? = nil,
        onClearSearchDestination: @escaping () -> Void = {},
        onTabSelect: @escaping (MoyeotaTab) -> Void = { _ in }
    ) {
        _viewModel = HostedViewModel(wrappedValue: ExploreViewModel(repository: repository))
        _finderViewModel = HostedViewModel(wrappedValue: ReservationFinderViewModel(repository: repository))
        self.activeRide = activeRide
        self.searchDestination = searchDestination
        self.onJoinParty = onJoinParty
        self.onOngoingRideClick = onOngoingRideClick
        self.onCreateRoomClick = onCreateRoomClick
        self.onPickSearchDestination = onPickSearchDestination
        self.onClearSearchDestination = onClearSearchDestination
        self.onTabSelect = onTabSelect
    }

    /// 호스트가 뷰모델을 들고 있는 경로 — 원본 `viewModel(factory = …)` 이 돌려주는 **백스택 엔트리의 뷰모델** 자리.
    ///
    /// 원본은 `popUpTo(HOME) { saveState = true }` + `restoreState = true` 로 탭을 떠나도 뷰모델이 남는다.
    /// 그 전제 위에서 `onInitialBounds` 가 복귀 때의 기준 범위를 무시하고 `onScreenStart` 가 마지막 범위로 바로
    /// 읽는다. 탭을 `switch` 로 갈아 끼우는 호스트는 뷰가 없어지므로, 위의 `init(repository:…)` 를 쓰면 복귀할
    /// 때마다 새 뷰모델이 로딩부터 다시 시작하고 기준 범위로 조회가 나간다. 그런 호스트는 탭 바깥에서
    /// `ExploreViewModel` 을 하나 들고 여기로 넘기고, 로그아웃 때 버린다(`clearBackStack` 자리).
    /// `TabView` 처럼 뷰를 살려 두는 호스트는 `init(repository:…)` 로 충분하다.
    ///
    /// 예약 조회(`ReservationFinderViewModel`)도 원본에서는 같은 엔트리의 뷰모델이라 **같은 수명으로**
    /// 함께 받는다 — 한쪽만 탭 바깥에 두면 복귀 때 예약 목록만 비어 「불러오는 중」부터 다시 그린다.
    ///
    /// 뷰 수명 동안 처음 받은 인스턴스를 쓴다.
    public init(
        viewModel: ExploreViewModel,
        finderViewModel: ReservationFinderViewModel,
        activeRide: Ride? = nil,
        searchDestination: Place? = nil,
        onJoinParty: @escaping (Ride) -> Void = { _ in },
        onOngoingRideClick: @escaping () -> Void = {},
        onCreateRoomClick: @escaping (Bool) -> Void = { _ in },
        onPickSearchDestination: (() -> Void)? = nil,
        onClearSearchDestination: @escaping () -> Void = {},
        onTabSelect: @escaping (MoyeotaTab) -> Void = { _ in }
    ) {
        _viewModel = HostedViewModel(wrappedValue: viewModel)
        _finderViewModel = HostedViewModel(wrappedValue: finderViewModel)
        self.activeRide = activeRide
        self.searchDestination = searchDestination
        self.onJoinParty = onJoinParty
        self.onOngoingRideClick = onOngoingRideClick
        self.onCreateRoomClick = onCreateRoomClick
        self.onPickSearchDestination = onPickSearchDestination
        self.onClearSearchDestination = onClearSearchDestination
        self.onTabSelect = onTabSelect
    }

    private var mode: ExploreMode {
        selectedMode ?? tabSavedState?.value(ExploreModeKey) ?? .realtime
    }

    private var dateOffset: Int {
        selectedDateOffset ?? tabSavedState?.value(ExploreDateOffsetKey) ?? 0
    }

    private func setMode(_ next: ExploreMode) {
        selectedMode = next
        tabSavedState?.set(ExploreModeKey, next)
    }

    private func setDateOffset(_ next: Int) {
        selectedDateOffset = next
        tabSavedState?.set(ExploreDateOffsetKey, next)
    }

    /// 화면이 시작 상태가 됐거나, 시작 상태에서 모드가 바뀌었다 — 원본의 두 `LifecycleStartEffect` 가 시작될 때 하는 일.
    ///
    /// **예약 모드에서는 실시간 폴링을 끈다.** 그 목록은 화면에 없고(모드가 하나다) 15초마다
    /// 뷰포트를 다시 읽는 비용만 남는다 — 가시성 게이트가 이미 「보이지 않으면 멈춘다」를 아는
    /// 스위치이므로(`ExploreViewModel.visible`) 같은 스위치를 모드에도 쓴다. 뷰모델에 모드를
    /// 알려 줄 필요가 없고, 모드를 되돌리면 그 자리에서 1회 조회 후 주기가 재개된다.
    ///
    /// 예약 조회도 **보이는 동안만** 돈다 — 「곧 출발」·「날짜로 찾기」 모두 15초 주기 갱신을 한다(실시간과
    /// 같은 이유, `ExploreRefresh.swift`). 같은 가시성 스위치를 쓴다(`ReservationFinderViewModel.onScreenStart`).
    /// 기준 시각도 여기서 갱신해 자정을 넘긴 뒤의 「오늘」을 바로잡는다. 실시간 모드일 때는 요청이 nil 이라
    /// 아무것도 조회하지 않고 시계도 돌지 않는다.
    ///
    /// 모드가 바뀌어도 예약 쪽은 **다시 시작하지 않는다** — 이미 보이는 상태면 `onScreenStart` 가 아무것도 하지
    /// 않는다(원본도 예약 쪽 `LifecycleStartEffect` 의 키에서 `mode` 를 뺐다). 다시 시작하면 「곧 출발」↔「날짜로
    /// 찾기」를 오갈 때마다 카운트다운이 15로 돌아간다. 새 조회는 요청(`ReservationFinderViewModel.request`)이 즉시
    /// 읽는다. 기준 시각은 모드를 바꿀 때도 다시 읽는다(원본 `LaunchedEffect(mode)`).
    private func startEffects(mode: ExploreMode) {
        if mode.isReservation { viewModel.onScreenStop() } else { viewModel.onScreenStart() }
        now = Date()
        finderViewModel.onScreenStart()
    }

    public var body: some View {
        let viewModel = viewModel
        let finderViewModel = finderViewModel
        let location = myLocation
        let mode = mode
        // 좌표·오차·방향을 한 덩어리로 넘긴다 — 지도가 파란 점과 오차 원을 같은 fix 로 그려야 한다
        let myFix = location.coordinates.map {
            MyLocationFix(
                position: LatLng($0.latitude, $0.longitude),
                accuracyMeters: $0.accuracyMeters,
                bearingDegrees: $0.bearingDegrees
            )
        }
        // `now` 가 바뀔 때만 달라진다(화면이 다시 보일 때) — 그릴 때마다 시계를 읽지 않는다
        let dateOptions = reservationDates(now: now)
        let selectedDate = dateOptions[min(max(dateOffset, 0), dateOptions.count - 1)]

        // 조회 입력이 바뀔 때마다(모드·지도 범위·내 좌표·날짜·도착지) 요청을 다시 올린다(아래 `.task(id:)`).
        // 입력이 모자라면 `reservationQueryOrNull` 이 nil 을 주고 뷰모델은 목록을 비운다 —
        // 화면은 그 상태를 「실패」가 아니라 「아직 못 물어봤다」로 그린다.
        let reservationDestination = reservationDestinationOrNull(
            latitude: searchDestination?.latitude,
            longitude: searchDestination?.longitude
        )
        let reservationQuery = reservationQueryOrNull(
            mode: mode,
            bounds: visibleBounds,
            myLatitude: myFix?.position.latitude,
            myLongitude: myFix?.position.longitude,
            date: selectedDate,
            destination: reservationDestination,
            now: now
        )

        // 내가 이미 참여 중인 방은 목록·마커에서 뺀다(`exploreList`·`reservationFeed`).
        //
        // **뷰모델이 아니라 여기서** 거르는 이유:
        // ① `activeRide` 는 `ActivePartyViewModel`(앱 전체가 공유하는 홀더)이 들고 있는 값이고
        //    이 뷰모델은 그걸 모른다. 넘겨주려면 탐색 뷰모델에 두 번째 데이터 출처가 생기고,
        //    그 출처가 바뀔 때마다 상태를 다시 만들어야 한다.
        // ② `UiState.success(parties, stale)` 는 **서버가 말한 것**이어야 한다. 거기서 걸러
        //    버리면 `stale`(갱신 연속 실패 표시)과 목록이 다른 뜻을 갖게 된다 — 「서버 목록은
        //    낡지 않았는데 내가 뺀 탓에 비었다」를 구분할 수 없고, `hasParties` 같은 폴링 판정이
        //    표시용 목록을 보게 된다.
        // 거르는 층이 화면 쪽이라도 **마커·카드·헤더 N 은 어긋나지 않는다** — 모드마다 그 셋이 모두
        // 한 목록에서 나온다(`ExploreScreen` 의 `shownRides`).
        let realtime: (parties: [Ride], stale: Bool)? =
            if case .success(let parties, let stale) = viewModel.uiState { (parties, stale) } else { nil }
        let list = exploreList(parties: realtime?.parties ?? [], myPartyId: activeRide?.id)
        let finderSuccess: (items: [ReservationCardUi], stale: Bool)? =
            if case .success(let items, let stale) = finderViewModel.uiState { (items, stale) } else { nil }
        let finderItems = finderSuccess?.items ?? []
        let feed = reservationFeed(items: finderItems, myPartyId: activeRide?.id)
        // 「낡음」은 **갱신의 연속 실패** 신호다 — 지금 보이는 목록을 읽는 쪽의 값을 넘긴다.
        let stale = switch mode {
        case .realtime: realtime?.stale == true
        case .soon, .byDate: finderSuccess?.stale == true
        }
        // 지도 오른쪽 아래 카운트다운 버튼 — 주기 갱신이 도는 모드에서 그린다(`exploreAutoRefreshes`, 지금은 세 모드 모두).
        // 모드마다 **그 목록을 읽는 뷰모델** 의 카운트다운을 보여 주고, 누르면 그쪽을 다시 읽는다.
        let refresh: ExploreRefreshUi? = switch mode {
        case .realtime: viewModel.refreshUi
        // 물어볼 것이 없으면(「날짜로 찾기」가 내 위치를 기다리는 중) 시계도 돌지 않는다 — 멈춘 숫자를
        // 그리지 않는다. 그 사이 목록 자리는 「내 위치를 확인하는 중이에요」가 말한다.
        case .soon, .byDate: reservationQuery != nil ? finderViewModel.refreshUi : nil
        }

        // 분기를 `ZStack` 하나로 감싼다. 아래 이펙트가 상태 분기마다 따로 걸리면(`Group`) 로딩 → 목록 전환이
        // 사라짐·나타남으로 읽혀 가시성이 끊겼다 이어지고, 그때마다 조회가 한 번 더 나간다.
        ZStack {
            // 실시간 첫 조회가 실패했다 — 에러에서도 하단탭은 남긴다(조회 실패로 탭 이동이 막히면 안 된다, QA F-1).
            //
            // **예약 모드에서는 실시간 조회 상태가 화면을 가리지 않는다.** 그 폴링은 멈춰 있어서
            // (아래 `lifecycleEffect`) 그 상태는 지금 보고 있는 목록과 무관하고, 전체 화면 에러로
            // 덮으면 모드를 되돌릴 칩까지 사라져 **빠져나올 길이 없다**.
            if !mode.isReservation, case .error(let message) = viewModel.uiState {
                TabStateScaffold(selectedTab: .explore, onTabSelect: onTabSelect) {
                    ErrorBox(message: message, onRetry: { viewModel.refresh() })
                }
            } else {
                // **실시간 첫 조회도 이 화면으로 그린다**(2026-11, 오너 UX 피드백 2차) — 예전에는 가운데 스피너
                // 한 장(`LoadingBox`)이 지도·모드 칩까지 덮었다. 지금은 지도와 빈 목록을 바로 그리고, 기다림은
                // 새로고침 버튼의 도는 고리 하나로만 보인다(예약 모드의 새 조회와 같은 규칙 — 버튼이 없는 위치 권한 거부
                // 경로는 목록 맨 위의 작은 스피너, `showListLoadingFallback`). 전체 화면으로 남는 것은 에러뿐이다.
                ExploreScreen(
                    parties: list.parties,
                    activeRide: activeRide,
                    // 빈 목록 문구가 이 값으로 갈린다 — 모드에 맞는 쪽을 넘긴다
                    myPartyHidden: mode.isReservation ? feed.myPartyHidden : list.myPartyHidden,
                    stale: stale,
                    loading: viewModel.uiState == .loading,
                    refresh: exploreAutoRefreshes(mode: mode) ? refresh : nil,
                    onRefreshClick: {
                        switch mode {
                        case .realtime: viewModel.refreshNow()
                        case .soon, .byDate: finderViewModel.refreshNow()
                        }
                    },
                    locationGranted: location.isGranted,
                    myLocation: myFix,
                    initialSheetState: tabSavedState?.value(ExploreSheetStateKey) ?? .peek,
                    reservations: ReservationPaneUi(
                        mode: mode,
                        dates: dateOptions,
                        selectedDate: selectedDate,
                        items: feed.items,
                        loading: finderViewModel.uiState == .loading,
                        failed: finderViewModel.uiState == .failed,
                        // 「날짜로 찾기」인데 내 좌표가 없다 — **실패가 아니라 아직 못 물어본 것**이다.
                        // 권한이 없을 때는 이 화면이 지도 대신 권한 안내를 그리므로 여기 오지 않는다.
                        locating: mode == .byDate && location.isGranted && myFix == nil,
                        destinationName: reservationDestination != nil ? searchDestination?.name : nil,
                        now: now
                    ),
                    onJoinParty: onJoinParty,
                    onOngoingRideClick: onOngoingRideClick,
                    // 탭의 뜻을 여기서 한 번만 번역한다 — 화면은 모드를 모른 채 버튼만 그린다
                    onCreateRoomClick: { onCreateRoomClick(createOpensScheduled(mode: mode)) },
                    onRequestLocationPermission: { location.onRequestPermission() },
                    onVisibleBoundsChange: { bounds in
                        // 지도는 하나이고 두 목록이 같은 신호를 쓴다 — 실시간 조회는 뷰모델이 받고,
                        // 「곧 출발」은 기억해 둔 마지막 범위로 요청을 다시 만든다(위 `reservationQuery`).
                        visibleBounds = bounds
                        viewModel.onVisibleBoundsChange(bounds)
                    },
                    onModeSelect: { setMode($0) },
                    onDateSelect: { date in
                        // 선택은 **일수**로 저장한다 — 화면 상태를 날짜 객체로 들고 있으면 자정을 넘길 때
                        // 목록에 없는 날이 선택된 채 남는다(`reservationQueryOrNull` 의 마지막 줄).
                        setDateOffset(dateOptions.firstIndex(of: date) ?? 0)
                    },
                    onRetryReservations: { finderViewModel.retry() },
                    onPickSearchDestination: onPickSearchDestination,
                    onClearSearchDestination: onClearSearchDestination,
                    onTabSelect: onTabSelect
                )
            }
        }
        .myLocationEffect($myLocation)
        // 화면이 보이는 동안만 조회·폴링한다 — 탭을 옮기거나 다른 화면이 위에 올라오거나 앱이 백그라운드로
        // 가면 즉시 멈추고, 돌아오면 그 자리에서 1회 조회한 뒤 주기를 재개한다 (24 채팅방과 같은 배치).
        // 실시간·예약 두 뷰모델이 같은 신호를 받는다.
        .lifecycleEffect(
            onStart: {
                screenStarted = true
                startEffects(mode: mode)
            },
            onStop: {
                screenStarted = false
                viewModel.onScreenStop()
                finderViewModel.onScreenStop()
            }
        )
        // 원본은 두 `LifecycleStartEffect` 의 키에 `mode` 가 있어, 시작 상태에서 모드가 바뀌면 효과가 멈췄다
        // 다시 시작한다. `lifecycleEffect` 에는 키가 없어 그 재시작을 여기서 한다 — 가려진 동안의 모드 변경은
        // 다음 시작이 그 모드로 처리하므로 건드리지 않는다.
        .onChange(of: mode) { _, next in
            guard screenStarted else { return }
            startEffects(mode: next)
        }
        .task(id: reservationQuery) {
            finderViewModel.request(reservationQuery)
        }
        // 첫 조회는 지도를 기다리지 않고 기준 범위로 먼저 쏜다.
        // 지도의 첫 idle 을 기다리면 그만큼 첫 목록이 늦고, 권한을 거부해 지도가 아예 없는 경로는 영영
        // 범위를 받지 못한다. 실좌표가 뒤늦게 잡히면 지도 카메라가 그리로 옮겨가며 idle → 실제 범위로 다시 조회된다.
        //
        // 탭을 다녀오면 이 이펙트가 **다시** 실행되지만, 그때 쓸 범위는 기준점이 아니라
        // 보던 카메라다 — `ExploreViewModel.onInitialBounds` 가 이미 범위를 받은 뒤의 호출을 무시한다.
        .task {
            let initial = defaultExploreBounds(center: myFix?.position)
            viewModel.onInitialBounds(initial)
            // 「곧 출발」도 **같은 기준 범위로** 시작한다. 지도의 첫 idle 을 기다리면 모드를 바꾼 직후
            // 조회할 범위가 없어 목록이 0건이 되는데, 그 0건은 **「없다」가 아니라 「못 물어봤다」**다 —
            // 그 상태를 「30분 안에 출발하는 예약이 없어요」로 적으면 거짓이다. 위치 권한을 거부해
            // 지도가 아예 없는 경로도 이 범위를 쓴다(실시간 목록이 하는 것과 같다).
            if visibleBounds == nil { visibleBounds = initial }
        }
    }
}

/// 17 이 실제로 그릴 목록 — 서버 목록에서 **내가 이미 참여 중인 방**을 뺀 결과.
///
/// - Parameters:
///   - parties: 서버가 지도 범위로 돌려준 목록(`status = ACTIVE` 인 방만 온다)
///   - myPartyHidden: 이 범위의 목록에서 **내 방을 실제로 빼냈는가**. 빈 목록 문구가 이 값으로
///     갈린다 — 내 방 하나뿐인 동네에서 「이 근처엔 동승이 없어요」는 거짓말이 된다
struct ExploreList: Equatable {
    var parties: [Ride]
    var myPartyHidden: Bool
}

/// 내가 참여 중인 방을 17 목록·마커에서 **뺀다.**
///
/// **왜 빼는가.** 서버 목록은 내 방을 빼지 않아서, 내가 속한 방이 남의 방과 **똑같은 「합류」 카드**로
/// 섞여 보였다. 그 카드는 거짓말을 한다 — 「합류」 버튼이 활성이고 인원 배지는 내가 들어가기 **전**의
/// 수처럼 읽힌다. 눌러서 20 합류 확인에 가면 `joinGate` 가 `ALREADY_JOINED` 로 받아 「이미 참여
/// 중인 방이에요」 + 「방으로 돌아가기」를 주므로 막힌 길은 아니지만, **같은 화면 맨 위에 진행 중 방
/// 배너가 이미 있다**(`ExploreScreen` 의 `ActiveRideBanner` → `onOngoingRideClick`): 한 번 눌러
/// 21/25/26 으로 바로 간다. 20 을 거치는 카드는 탭이 한 번 더 들고 방 상세를 한 번 더 읽는 **더 긴
/// 우회로**이며, 그 사이 화면은 내가 합류할 수 있는 방처럼 보인다. 돌아가는 길이 이미 더 짧게 있으니
/// 그 카드는 소음이다.
///
/// **20 의 `ALREADY_JOINED` 분기는 그대로 남는다** — 이 필터는 17 의 **표시**만 바꾼다. 목록이
/// 낡아 내 방이 아직 섞여 있는 순간, 알림으로 20 에 바로 들어오는 경우, 그리고 `activeRide` 홀더가
/// 아직 비어 있는 순간(앱 시작 직후 첫 `resolve` 전)이 모두 그 분기로 간다.
///
/// **판정은 `activeRide` 의 id 하나로 한다.** `ride.members.contains { $0.isMe }` 는 이 데이터로는
/// **영원히 false** 다 — 목록 응답에는 멤버 식별자가 없어 매퍼가 자리 표시용 멤버를 만들고
/// (`PartyMappers.placeholderMembers`) 그 멤버에는 `publicId` 가 없어 `User.isMe` 가 늘 false 다.
/// 즉 목록 데이터만으로는 「내가 그 방에 있는가」를 알 수 없고, 알고 있는 쪽은 방 상세를 읽어 둔
/// `ActivePartyViewModel` 뿐이다.
///
/// id 비교는 **Int64 로 먼저** 본다(`needsDetailAfterRemember` 와 같은 이유): 두 값은 서로 다른
/// 응답에서 왔고(목록 `partyId`, 상세 `id`) 문자열 모양이 어긋날 수 있다. 숫자로 안 읽히는 id 는
/// 문자열로 비교한다.
///
/// `activeRide` 의 단계는 보지 않는다. 끝난 방(COMPLETED·CANCELED)은 `status = ACTIVE` 목록에
/// 아예 오지 않아 id 가 걸릴 일이 없고, 「어느 단계부터 거른다」는 조건을 두면 그 조건이 배너를
/// 그리는 조건(nil 이 아니면 그린다)과 갈릴 수 있다.
func exploreList(parties: [Ride], myPartyId: String?) -> ExploreList {
    guard let myPartyId, !myPartyId.isBlank else {
        return ExploreList(parties: parties, myPartyHidden: false)
    }
    let remaining = parties.filter { !samePartyId($0.id, myPartyId) }
    return ExploreList(
        parties: remaining,
        myPartyHidden: remaining.count != parties.count
    )
}

/// 같은 방인가. 숫자로 읽히면 숫자로, 아니면 문자열로 본다(`exploreList` 설명).
///
/// `internal` 인 이유: 예약 목록도 **같은 규칙으로** 내 방을 걸러야 한다(`reservationFeed`).
/// 두 곳이 각자 비교를 세우면 한쪽만 「목록 partyId 와 상세 id 의 문자열 모양이 다를 수 있다」는
/// 사정을 알게 된다.
func samePartyId(_ a: String, _ b: String) -> Bool {
    let left = Int64(a)
    let right = Int64(b)
    return left != nil || right != nil ? left == right : a == b
}

/// 갱신 실패를 **사용자에게 알릴 때인가** — `nearbyLoadTiming` 과 같은 자리의 판정이다(순수 함수 한 곳에
/// 모으고 루프는 결과만 따른다).
///
/// 한 번의 실패는 알리지 않는다(지도 앱의 흔한 일시 끊김이다). 연속 `STALE_NOTICE_FAILURES` 회부터
/// 알린다 — 무엇을 세는지와 임계값의 근거는 그 상수에 적어 두었다. **성공 한 번이 카운터를 0 으로
/// 돌린다**(호출부)이므로, 이 함수는 「지금까지 연속 몇 번 실패했는가」만 보면 된다.
///
/// - Parameter consecutiveFailures: 마지막 성공 이후 연속 실패 횟수 — 자동 갱신·지도 이동·버튼 어느 조회든 센다
func staleAfterPollFailures(consecutiveFailures: Int) -> Bool {
    consecutiveFailures >= STALE_NOTICE_FAILURES
}
