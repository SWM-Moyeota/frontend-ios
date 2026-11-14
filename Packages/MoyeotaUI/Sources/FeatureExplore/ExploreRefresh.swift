import Foundation
import MoyeotaDesignSystem
import MoyeotaDomain
import os
import PresentationCore
import SwiftUI

/// 갱신 시계가 삼킨 결함을 남기는 곳 — 예외 **종류 이름만** 적는다(`ExploreRefreshCycle` 의 `load` 설명).
private let refreshLogger = Logger(subsystem: "com.moyeota.presentation", category: "ExploreRefresh")

// 17 탐색 목록의 **주기 새로고침 + 카운트다운 버튼** — 판정과 숫자, 그리고 그 시계(`ExploreRefreshCycle`)를 한 곳에 모은다.
//
// ### 4초 → 15초 (2026-11, 오너 UX 피드백)
// 예전에는 화면이 보이는 동안 **4초마다** 같은 범위를 다시 읽었다. 목록이 4초마다 바뀌면 카드를 읽는
// 도중 순서가 바뀌고 누르려던 카드가 손가락 아래에서 움직인다. 그리고 방이 차고 비는 주기는 분 단위라
// 4초 간격은 대부분 같은 결과를 다시 받는 비용이었다. 15초는 「합류」를 누르기 전에 한 번은 갱신되는
// 간격이면서(카드를 읽고 고르는 데 그 정도 걸린다) 읽는 동안 목록을 흔들지 않는 간격이다.
//
// 대신 **언제 갱신되는지 보이게** 한다 — 네이버 지도의 「주변 다시 검색」처럼 지도 오른쪽 아래에 남은
// 초를 세는 원형 버튼(`ExploreRefreshButton`)을 두고, 누르면 그 자리에서 다시 읽고 15초를 새로 센다.
// 주기가 길어진 만큼 「지금 보고 있는 게 최신인가」를 사용자가 직접 정할 수 있어야 한다.
//
// ### 세 모드 모두 돈다 — `exploreAutoRefreshes` (2026-11, 오너 UX 피드백 2차)
// | 모드 | 주기 갱신·버튼 | 이유 |
// |---|---|---|
// | 실시간 | 있음 | 방이 **지금** 차고 빈다 — 낡은 목록이 곧 「사라진 방의 합류」다 |
// | 곧 출발 | 있음 | 30분 안에 출발하는 방이라 실시간만큼 빨리 낡는다(곧 떠나 목록에서 빠진다) |
// | 날짜로 찾기 | 있음 | 출발 시각은 바뀌지 않아도 **자리는 바뀐다** — 남의 합류·나감·취소로 마지막 자리가 차고, 낡은 카드의 「합류」는 20 에서야 거절된다 |
//
// 「날짜로 찾기」는 예전에 **한 번의 검색**이라 돌지 않았다(「며칠 뒤 출발 시각은 바뀌지 않는다」). 그 근거는
// 시각에만 맞고 자리에는 맞지 않았고, 오너 확인에서 이 탭만 버튼이 없어 「언제 읽은 목록인가」를 알 수 없다는
// 지적이 나왔다. 그래서 세 탭이 **같은 버튼·같은 주기·같은 「낡음」 규칙**을 갖는다.
//
// ### 카운트다운은 지도와 따로 돈다 ★ (2026-11, 오너 UX 피드백 2차)
// 예전에는 「조회 하나 = 패스 하나」였다. 지도를 움직이면 새 범위라 새 패스가 열리고 카운트다운이 15부터 다시
// 셌다 — 지도를 조금씩 옮기며 보는 사람에게는 숫자가 끝까지 내려가지 않아, 버튼이 「언제 갱신되는가」를
// 말하지 못했다. 지금은 **시계와 조회를 떼어 둔다**(`ExploreRefreshCycle`):
//
// | 일 | 조회 | 카운트다운 |
// |---|---|---|
// | 화면이 보이기 시작함 | 즉시 | **15부터 새로** |
// | 0 에 닿음(자동 갱신) | 그 순간의 **최신 입력**(범위·날짜·도착지)으로 | 15부터 다시 |
// | 버튼을 누름 | 즉시 | **15부터 다시** |
// | 지도를 움직임 | `BOUNDS_DEBOUNCE_MS` 뒤 | 그대로 센다 |
// | 날짜·도착지·모드를 바꿈 | 즉시 | 그대로 센다 |
// | 「다시 시도」 | 즉시 | 그대로 센다 |
// | 화면이 가려짐 | 멈춤(나가 있던 조회도 끊는다) | 멈춤 — 남은 초를 기억하지 않는다 |
//
// 숫자를 15로 되돌리는 것은 **버튼과 화면 복귀뿐**이다. 버튼은 사용자가 「지금 읽었다」를 직접 만든 것이고,
// 복귀는 가려진 동안 시계가 멈춰 있었기 때문이다. 조회가 나가 있는 동안 버튼은 도는 고리를 그리고 눌리지
// 않지만 **초는 밑에서 계속 줄어든다** — 조회가 끝나면 그 사이 줄어든 숫자부터 이어 보인다. 0 은 조회가
// 끝나기를 기다리지 않고 바로 다음 15초를 센다(고정 15초 주기 — 응답이 느려도 주기가 늘지 않는다).
//
// ### 시계는 `sleep` 하나다 — 테스트가 가상 시간으로 돌린다
// 카운트다운은 `countDownToNextRefresh` 가 1초씩 `sleep` 하며 남은 초를 알리는 것이 전부이고, 지도 디바운스도
// 같은 `sleep` 이다. 벽시계를 읽지 않으므로 뷰모델에 주입한 `sleep` 이 곧 이 화면의 시계다(`ExploreRefreshTest` 가
// 가상 시계를 넣는다).

/// 주기 갱신 간격 — **15초**. 근거는 이 파일 머리말.
let NEARBY_POLL_INTERVAL_MS = 15_000

/// 카운트다운 한 칸 — 1초. 버튼의 숫자가 1씩 줄어드는 간격이다.
let REFRESH_TICK_MS = 1_000

/// 버튼이 세기 시작하는 숫자(15). 간격을 칸으로 나눈 값이라 둘 중 하나만 바꿔도 따라온다.
// `@usableFromInline` 인 이유: 공개 이니셜라이저 `ExploreRefreshUi.init` 의 기본값이다 — 기본값 식은 호출하는
// 모듈 쪽에서 평가되므로 internal 그대로면 컴파일이 막힌다. 다른 모듈에 이름을 여는 것은 아니다.
@usableFromInline
let REFRESH_COUNTDOWN_SECONDS: Int = (NEARBY_POLL_INTERVAL_MS + REFRESH_TICK_MS - 1) / REFRESH_TICK_MS

/// 카메라가 멈춘 뒤 조회까지 두는 여유.
///
/// 팬·줌을 연타하면 idle 이 연달아 들어오는데, 중간 범위마다 서버를 때릴 이유가 없다.
/// 손을 뗀 직후의 체감 지연으로 느껴지지 않을 만큼만 둔다. 실시간과 「곧 출발」이 같은 값을 쓴다
/// (`ExploreLoadTiming.debounced`).
let BOUNDS_DEBOUNCE_MS = 400

/// 새로고침 버튼이 그릴 것.
///
/// - Parameters:
///   - secondsLeft: 다음 자동 갱신까지 남은 초(15 → 1). `refreshing` 이어도 밑에서 계속 줄어든다 — 조회가
///     끝나면 그 숫자부터 이어 보인다
///   - refreshing: 조회가 나가 있다 — 버튼은 숫자 대신 도는 고리를 그리고 눌리지 않는다(연타가
///     같은 조회를 겹쳐 보내지 않게)
// `ExploreScreen` 의 공개 파라미터에 실려 나가므로 공개 타입이다(`ExploreMode` 와 같은 이유).
public struct ExploreRefreshUi: Equatable, Sendable {
    public var secondsLeft: Int
    public var refreshing: Bool

    public init(secondsLeft: Int = REFRESH_COUNTDOWN_SECONDS, refreshing: Bool = false) {
        self.secondsLeft = secondsLeft
        self.refreshing = refreshing
    }
}

/// 이 모드가 **주기 갱신과 새로고침 버튼을 갖는가** — 위 표의 판정이다. 지금은 세 모드 모두 그렇다.
///
/// `switch` 로 적어 `ExploreMode` 가 늘면 컴파일이 깨지게 한다(새 탭이 주기 갱신을 할지 그 자리에서 정한다).
/// 두 뷰모델의 시계(`ExploreRefreshCycle`)는 모드를 모르고 **조회가 있으면 돈다** — 어느 모드가 false 가
/// 되면 그 모드의 조회가 시계에 들어가지 않게 하는 일도 함께 해야 한다(지금은 화면이 버튼만 숨긴다).
func exploreAutoRefreshes(mode: ExploreMode) -> Bool {
    switch mode {
    case .realtime, .soon, .byDate: true
    }
}

/// 다음 자동 갱신까지 **1초씩 세며 기다린다** — `onTick` 으로 15, 14, …, 1 을 차례로 알리고, 1 을 알린 뒤
/// 1초가 더 지나면 돌아온다(합계 `intervalMs`). 돌아오면 호출부가 조회한다.
///
/// 취소되면(화면이 가려짐·사용자가 버튼을 누름) 그 자리에서 멈춘다 — 남은 초를 기억하지 않는다.
/// 지도 이동·날짜 변경은 이 대기를 건드리지 않는다(`ExploreRefreshCycle`).
///
/// 원본은 `delay` 를 직접 부른다. 여기서는 그 자리를 `sleep` 으로 받는다 — 뷰모델이 주입받은 시계를
/// 그대로 넘겨 테스트가 시간을 쥔다(`docs/PORTING.md` 3절 `delay(ms)`). `@MainActor` 인 이유는 부르는
/// 시계가 메인 액터이고 `onTick` 이 그 상태를 바로 쓰기 때문이다.
@MainActor
func countDownToNextRefresh(
    onTick: (_ secondsLeft: Int) -> Void,
    intervalMs: Int = NEARBY_POLL_INTERVAL_MS,
    tickMs: Int = REFRESH_TICK_MS,
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
) async throws {
    var remainingMs = intervalMs
    while remainingMs > 0 {
        onTick((remainingMs + tickMs - 1) / tickMs)
        let step = min(tickMs, remainingMs)
        try await sleep(.milliseconds(step))
        remainingMs -= step
    }
}

/// 조회 입력이 바뀌었을 때 **언제 읽는가** — 카운트다운은 어느 쪽이든 건드리지 않는다.
///
/// 판정은 목록마다 다르고(실시간 `nearbyLoadTiming` · 예약 `reservationLoadTiming`) 시계는 그 결과만 따른다.
enum ExploreLoadTiming: CaseIterable {
    /// 지금 읽는다 — 새 목록(첫 조회·날짜·도착지·모드)이거나, 보여 줄 목록이 없어 늦출 이득이 없다
    case now

    /// `BOUNDS_DEBOUNCE_MS` 뒤에 읽는다 — 지도를 움직였다. 팬·줌 연타의 중간 범위마다 서버를 때리지 않는다
    case debounced

    /// 지금은 읽지 않는다 — **다음 자동 갱신이 새 입력으로 읽는다.** 「날짜로 찾기」의 내 위치가 조금
    /// 움직였는데 목록이 보이거나 빈 자리로 조회가 오는 중일 때다: GPS 는 1초마다 몇 m 씩 흔들리는데, 그때마다
    /// 읽으면 1km 검색이 1초마다 나가고 응답이 1초보다 느리면 영영 끝나지 않는다(`reservationLoadTiming`)
    case nextTick
}

/// 탐색 목록 하나(실시간 · 예약)의 **갱신 시계와 조회 칸** — 이 파일 머리말의 표를 그대로 옮긴 것이다.
///
/// 두 뷰모델이 같은 규칙으로 돌아야 해서 한 곳에 둔다. 뷰모델은 **무엇을 어떻게 읽어 보여 줄지**만
/// `load` 로 넘기고(결과·실패 처리·「낡음」 판정은 그쪽 몫이다), 언제 읽는지는 이 클래스가 정한다.
///
/// ### 세 가지가 따로 돈다
/// - **세션** — 화면이 보이고(`setVisible`) 물어볼 것(`update`)이 있는 동안. 시작하면 즉시 한 번 읽고 15부터 센다.
///   끝나면(가려짐·조회 없음) 카운트다운·디바운스·나가 있는 조회를 모두 끊는다
/// - **카운트다운** — 15 → 1 을 세고 0 에서 **그 순간의 최신 입력**을 읽은 뒤 곧바로 다시 15부터 센다.
///   버튼(`refreshNow`)과 세션 시작만 이것을 처음부터 다시 돌린다
/// - **조회 칸** — 나가 있는 조회는 하나뿐이다. 다른 입력의 조회가 오면 앞 것을 끊는다(늦은 앞 범위 응답이 새
///   범위 목록을 덮지 않게). 자동 갱신·「다시 시도」 때 **같은 입력의 조회가 이미 나가 있으면 그것을 이번
///   조회로 친다** — 응답이 15초보다 느려도 같은 요청을 겹쳐 보내거나 끊었다 다시 보내지 않는다
///
/// 원본은 `viewModelScope` 를 받아 그 위에 코루틴을 띄운다. 여기서는 제 `ViewModelScope` 를 들고 태스크는 이
/// 객체를 약하게 잡는다 — 뷰모델이 해제되면 이 객체도 해제되고 그때 태스크가 모두 끊긴다. 끊긴 조회가
/// 뒤늦게 값을 들고 돌아와도 **`load` 가 `Task.isCancelled` 를 보고 버려야 한다**(URLSession 은 취소와 응답이
/// 엇갈릴 수 있다).
///
/// 돌려주는 태스크(나간 조회)는 테스트가 끝을 기다리는 용도다. 화면은 쓰지 않는다.
///
/// ### `load` 가 약속을 어기고 던지면 — 삼키고 시계를 살린다 (원본 리뷰 반영 2차, PR #99)
/// 원본은 조회를 `viewModelScope` 의 자식으로 돌려, 새는 예외 하나가 프로세스를 죽였다. 여기서는 `load` 를
/// `throws` 로 받아 조회 태스크가 직접 받는다: 취소(`CancellationError`)는 그대로 끝내고, 그 밖은 삼킨 뒤 **종류
/// 이름만** 로그와 `Diagnostics` 로 남긴다(메시지를 싣지 않는다 — 조회 입력은 지도 범위·내 좌표다). 조회 칸 정리
/// (`finishFetch`)는 그대로 돌아 다음 0 이 평소처럼 읽는다.
///
/// 삼킨 오류는 「낡음」의 연속 실패로 **세지 않는다.** 그 계수기는 뷰모델의 `load` 안에 있고, 서버 조회의 실패는
/// 이미 거기서 받아 센다(그래서 두 뷰모델의 `load` 는 던지지 않는다). 그 밖으로 새는 것은 **세고 난 뒤의 상태
/// 정리**에서 생긴 결함이다 — 여기서 다시 세게 하려면 시계가 모르는 뷰모델 계수기에 두 번째 통로를 내야 하고,
/// 생긴 자리가 `failures += 1` 뒤라면 같은 실패를 두 번 센다. 결함은 「낡음」이 아니라 진단으로 드러낸다.
@MainActor
final class ExploreRefreshCycle<Query: Equatable & Sendable> {
    private let sleep: @Sendable (Duration) async throws -> Void
    private let load: @MainActor (Query) async throws -> Void
    private let onUi: @MainActor (ExploreRefreshUi) -> Void
    private let scope = ViewModelScope()

    private var query: Query?
    private var visible = false
    private var secondsLeft = REFRESH_COUNTDOWN_SECONDS

    private var countdown: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var fetch: Task<Void, Never>?
    private var fetchQuery: Query?

    /// 끊긴 조회가 뒤늦게 끝날 때 지금 조회의 표시를 지우지 않게 하는 번호
    private var fetchGeneration = 0

    /// 세션이 돌고 있는가 — 보이고, 물어볼 것이 있다. false 면 `retry`·`refreshNow` 는 아무 일도 하지 않는다.
    var isRunning: Bool { countdown != nil }

    /// 조회가 나가 있는가 — 「날짜로 찾기」가 빈 목록 자리로 오는 중인 조회를 GPS 흔들림으로 끊지 않게 본다
    /// (`reservationLoadTiming`).
    var isFetching: Bool { fetch != nil }

    /// - Parameters:
    ///   - sleep: 카운트다운·디바운스의 시계(테스트가 가상 시계를 넣는다)
    ///   - load: 조회 하나를 읽어 화면 상태에 반영한다. **실패는 안에서 처리하고 던지지 않는다** — 어겨도 앱은 죽지
    ///     않는다(클래스 설명). `throws` 인 것은 그 방어를 이 자리에서 하기 위해서다
    ///   - onUi: 버튼이 그릴 것이 바뀌었다(원본 `ui` `StateFlow` 자리)
    init(
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        load: @escaping @MainActor (Query) async throws -> Void,
        onUi: @escaping @MainActor (ExploreRefreshUi) -> Void
    ) {
        self.sleep = sleep
        self.load = load
        self.onUi = onUi
    }

    /// 화면이 보이기 시작했다(true) · 가려졌다(false). 보이기 시작하면 즉시 읽고 **15부터 새로** 센다.
    @discardableResult
    func setVisible(_ shown: Bool) -> Task<Void, Never>? {
        if visible == shown { return nil }
        visible = shown
        if shown { return start() }
        stop()
        return nil
    }

    /// 조회 입력이 바뀌었다. **nil 이면 물어볼 것이 없다**(세션을 멈춘다).
    ///
    /// 세션이 돌고 있으면 `timing` 대로 읽고 **카운트다운은 건드리지 않는다.** 아직 돌지 않았으면(첫 조회·
    /// 다른 모드에서 넘어옴) 세션을 시작한다 — 보이는 동안만이다. 가려져 있으면 입력만 받아 두고, 보이면 그
    /// 입력으로 즉시 읽는다.
    @discardableResult
    func update(_ next: Query?, timing: ExploreLoadTiming) -> Task<Void, Never>? {
        query = next
        guard next != nil else {
            stop()
            return nil
        }
        guard visible else { return nil }
        guard isRunning else { return start() }
        switch timing {
        case .now: return read(joinSame: false)
        case .debounced:
            readAfterDebounce()
            return nil
        case .nextTick: return nil
        }
    }

    /// 새로고침 버튼 — **즉시 읽고 15부터 다시 센다.** 조회가 나가 있는 동안 들어온 탭은 버린다(버튼은
    /// 그동안 비활성이지만, 탭과 상태 변경이 엇갈려 들어온 것이 같은 조회를 겹쳐 보내게 두지 않는다).
    @discardableResult
    func refreshNow() -> Task<Void, Never>? {
        guard isRunning, fetch == nil else { return nil }
        let task = read(joinSame: false)
        restartCountdown()
        return task
    }

    /// 「다시 시도」 — 즉시 읽는다. 카운트다운은 그대로다(숫자를 되돌리는 것은 새로고침 버튼뿐이다).
    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard isRunning else { return nil }
        return read(joinSame: true)
    }

    private func start() -> Task<Void, Never>? {
        guard query != nil else { return nil }
        let task = read(joinSame: false)
        restartCountdown()
        return task
    }

    private func stop() {
        countdown?.cancel()
        countdown = nil
        debounce?.cancel()
        debounce = nil
        cancelFetch()
        secondsLeft = REFRESH_COUNTDOWN_SECONDS
        publish()
    }

    private func restartCountdown() {
        countdown?.cancel()
        secondsLeft = REFRESH_COUNTDOWN_SECONDS
        publish()
        let sleep = sleep
        // 대기 중에 self 를 강하게 잡지 않는다 — 잡고 있으면 뷰모델이 해제돼도 이 객체가 남아 주기가 영영 끝나지 않는다.
        countdown = scope.launch { [weak self] in
            do {
                while !Task.isCancelled {
                    try await countDownToNextRefresh(
                        onTick: { left in self?.tick(left) },
                        sleep: sleep
                    )
                    // 0 — 그 순간의 최신 입력으로 읽고, 끝나기를 기다리지 않고 다시 15부터 센다
                    try Task.checkCancellation()
                    self?.read(joinSame: true)
                }
            } catch {
                // 여기로 오는 것은 이 태스크의 취소뿐이다(가려짐·버튼·해제)
            }
        }
    }

    private func tick(_ left: Int) {
        secondsLeft = left
        publish()
    }

    private func readAfterDebounce() {
        debounce?.cancel()
        // 앞 입력의 조회는 끊는다 — 그 결과는 이제 다른 동네의 목록이다
        cancelFetch()
        publish()
        let sleep = sleep
        debounce = scope.launch { [weak self] in
            do {
                try await sleep(.milliseconds(BOUNDS_DEBOUNCE_MS))
            } catch {
                return
            }
            // 대기가 끝난 뒤 메인 액터로 돌아오기 전에 끊겼을 수 있다(더 새 범위·자동 갱신·가려짐)
            guard !Task.isCancelled, let self else { return }
            self.debounce = nil
            self.read(joinSame: false)
        }
    }

    /// 지금 입력(`query`)으로 읽는다. 기다리던 디바운스는 이 조회가 대신한다.
    ///
    /// - Parameter joinSame: 같은 입력의 조회가 이미 나가 있으면 그것을 이번 조회로 친다(자동 갱신·「다시 시도」)
    @discardableResult
    private func read(joinSame: Bool) -> Task<Void, Never>? {
        guard let query else { return nil }
        debounce?.cancel()
        debounce = nil
        if let fetch {
            if joinSame && fetchQuery == query { return fetch }
            cancelFetch()
        }
        fetchGeneration += 1
        let generation = fetchGeneration
        let load = load
        let task = scope.launch { [weak self] in
            do {
                try await load(query)
            } catch {
                // 취소(`CancellationError`·`URLError(.cancelled)`)는 더 새 입력·가려짐·버튼으로 끊긴 것 — 실패가 아니다.
                // 그 밖은 `load` 가 약속을 어긴 것이다 — 앱을 죽이지 않고 종류만 남긴다(클래스 설명). 시계는 계속 돈다
                if !isCancellation(throwable: error) {
                    refreshLogger.error("load threw \(String(describing: type(of: error)), privacy: .public) — swallowed")
                    try? Diagnostics.report(site: .exploreRefresh, throwable: error)
                }
            }
            self?.finishFetch(generation)
        }
        fetch = task
        fetchQuery = query
        publish()
        return task
    }

    private func finishFetch(_ generation: Int) {
        guard generation == fetchGeneration else { return }
        fetch = nil
        fetchQuery = nil
        publish()
    }

    private func cancelFetch() {
        fetch?.cancel()
        fetch = nil
        fetchQuery = nil
        fetchGeneration += 1
    }

    private func publish() {
        onUi(ExploreRefreshUi(secondsLeft: secondsLeft, refreshing: fetch != nil))
    }
}

/// 실시간 목록의 지도 이동을 **언제 읽는가** — 보여 주던 목록이 있으면 디바운스 뒤, 없으면(첫 조회·에러
/// 화면) 늦출 이득이 없으니 지금.
func nearbyLoadTiming(listShown: Bool) -> ExploreLoadTiming {
    listShown ? .debounced : .now
}

/// 새로고침 버튼의 VoiceOver 이름.
let REFRESH_BUTTON_LABEL = "목록 새로고침"

/// 새로고침 버튼의 VoiceOver 값 — 「15초마다 자동」 / 「새로고침 중」.
///
/// **남은 초를 읽어 주지 않는다.** 숫자는 1초마다 바뀌는데, VoiceOver 는 초점이 놓인 요소의 값이 바뀔
/// 때마다 그것을 읽는다 — 「14초 후 자동」, 「13초 후 자동」이 쉬지 않고 들린다. 그래서 값에는 **주기**를
/// 적는다(바뀌지 않는다). 조회 중일 때만 「새로고침 중」으로 바뀌고 그때 버튼은 눌리지 않는다.
func refreshButtonStateDescription(ui: ExploreRefreshUi) -> String {
    ui.refreshing ? "새로고침 중" : "\(REFRESH_COUNTDOWN_SECONDS)초마다 자동"
}

/// 버튼 지름 — 48 터치 타깃과 같다.
let RefreshButtonSize: CGFloat = 48

/// 버튼의 오른쪽 여백 — **네이버 지도 줌 컨트롤과 같은 세로선**에 세운다.
///
/// SDK 의 줌 컨트롤은 폭 46 · 오른쪽 여백 10 이다(`NaverMapView` 가 `NMFZoomControlView` 를 그 값으로 붙인다 —
/// 원본 SDK 3.23.3 의 `navermap_map_controls_view.xml` · `navermap_zoom_control_view.xml` 과 같은 값). 그 중심선은
/// 오른쪽에서 33 이고, 48 버튼의 중심을 거기 맞추면 여백은 33 − 24 = 9 다.
let RefreshButtonEndInset: CGFloat = 9

/// 버튼과 그 아래(시트 윗변 · 하단 CTA) 사이 — 16.
let RefreshButtonGap: CGFloat = MoyeotaSpacing.Md

/// 목록 위에 뜬 버튼(`RefreshButtonSpot.overList`)이 마지막 줄을 가리지 않게 목록 끝에 더하는 여백.
///
/// 버튼은 CTA 위 16 에서 48 을 차지하고, 목록의 아래 끝은 CTA 줄의 위 여백(8)만큼 CTA 보다 위다 —
/// 그래서 버튼은 목록 아래 끝에서 8~56 을 덮는다. 버튼 + 간격(64)을 두면 끝까지 내린 마지막 줄이 버튼
/// 위 8 에서 끝나 「합류」 터치 영역이 버튼 밑에 깔리지 않는다.
let RefreshButtonListClearance: CGFloat = RefreshButtonSize + RefreshButtonGap

/// 새로고침 버튼이 서는 자리 — `refreshButtonPlacement` 의 판정.
enum RefreshButtonSpot: Equatable {
    /// 지도 위 — 시트 윗변 16 위, 네이버 줌 컨트롤과 같은 세로선(접힘·반펼침)
    case aboveSheet

    /// 목록 위에 뜬다 — 끝에서 16, 하단 CTA 16 위(지도가 다 가려진 FULL · 지도에 자리가 없을 때)
    case overList
}

/// 버튼의 자리와 여백. 둘 다 **컨테이너(지도+시트 영역)의 오른쪽 아래 모서리**에서 잰다.
///
/// - Parameters:
///   - end: 오른쪽 끝에서 버튼까지
///   - bottom: 컨테이너 아래 끝에서 버튼 아래 끝까지
struct RefreshButtonPlacement: Equatable {
    var spot: RefreshButtonSpot
    var end: CGFloat
    var bottom: CGFloat
}

/// 새로고침 버튼을 **어디에 세우는가** — 세 시트 단계 모두에서 보인다(2026-11, 오너 UX 피드백 2차).
///
/// 예전에는 FULL 에서 숨겼다(「지도가 다 가려졌으니 무엇을 새로 고치는지 알 수 없다」). 하지만 FULL 은 목록을
/// 읽는 상태이고, 그 목록도 15초마다 바뀐다 — 언제 바뀌는지 알려 주는 버튼이 가장 필요한 자리에서 사라졌다.
///
/// | 조건 | 자리 |
/// |---|---|
/// | FULL 이 아니고 시트 위 지도에 버튼 + 16 이 들어간다 | `aboveSheet` — 시트 윗변 16 위, 줌 컨트롤과 같은 세로선(`RefreshButtonEndInset`) |
/// | 그 밖(FULL · 끝까지 끌어 올리는 중) | `overList` — 끝에서 16(`MoyeotaSpacing.ScreenGutter`), 하단 CTA 16 위(CTA 가 없으면 아래 끝에서 16) |
///
/// 높이는 **실측 시트 높이**(드래그·정착 애니메이션 중의 값)로 판정한다 — 끌어 올리는 동안 버튼이 지도 밖으로
/// 밀려나지 않고, 들어갈 자리가 없어지는 순간 목록 위로 내려온다.
///
/// - Parameter bottomCtaTop: 컨테이너 아래 끝에서 하단 CTA(「새 동승 방 만들기」) 윗변까지. nil 이면 CTA 가 없다(접힘)
func refreshButtonPlacement(
    sheetState: ExploreSheetState,
    containerHeight: CGFloat,
    sheetHeight: CGFloat,
    bottomCtaTop: CGFloat?
) -> RefreshButtonPlacement {
    let fitsAboveSheet = sheetState != .full
        && containerHeight - sheetHeight - RefreshButtonGap >= RefreshButtonSize
    if fitsAboveSheet {
        return RefreshButtonPlacement(spot: .aboveSheet, end: RefreshButtonEndInset, bottom: sheetHeight + RefreshButtonGap)
    }
    return RefreshButtonPlacement(
        spot: .overList,
        end: MoyeotaSpacing.ScreenGutter,
        bottom: (bottomCtaTop ?? 0) + RefreshButtonGap
    )
}

/// 카운트다운 새로고침 버튼을 **그리는가** — 그릴 것(`refresh`)이 있고 위치 권한이 있을 때.
///
/// 권한이 없으면 지도 대신 권한 안내가 깔리지만 조회는 그대로 돈다(기준 범위로 첫 조회, 15초 주기 — `ExploreRoute`).
/// 그래도 **버튼은 그리지 않는다**:
/// - 버튼의 자리(`refreshButtonPlacement` — 줌 컨트롤 세로선, 시트 윗변 16 위)는 지도 위를 전제로 정한 것이다.
///   권한 안내 위에서는 그 화면의 유일한 행동인 「위치 권한 허용」 곁에 뜻 모를 원이 하나 더 생긴다
/// - 다시 읽는 범위가 눈에 보이지 않는 기준 범위라, 무엇을 새로 고치는지 화면이 말해 주지 못한다
///
/// 버튼이 없을 때의 기다림은 목록의 대체 로딩 표시가 맡는다(`showListLoadingFallback`).
func refreshButtonShown(refresh: ExploreRefreshUi?, locationGranted: Bool) -> Bool {
    refresh != nil && locationGranted
}

/// 목록 자리에 **대체 로딩 표시**(작은 스피너)를 그리는가 — 새 목록을 읽는 중인데(`loading`) 새로고침 버튼이
/// 없을 때(`refreshButtonShown` 이 false). 세 모드 모두 같은 규칙이다.
///
/// 목록 가운데 스피너를 걷은 근거는 「기다림은 버튼의 도는 고리가 보여 준다」였다(2026-11, 오너 UX 피드백 2차). 그
/// 근거는 버튼이 **있을 때만** 선다. 버튼이 없으면(위치 권한 없음 · 물어볼 것이 없음 · 주기 갱신이 없는 모드) 첫 조회와
/// 에러 화면의 「다시 시도」 동안 목록은 비어 있고 — 아직 묻지 못한 것을 「없다」고 말하지 않으려 빈 목록 문구도
/// 그리지 않는다 — 도는 것이 하나도 없어 **빈 화면**으로 보인다.
///
/// 버튼이 있으면 그리지 않는다 — 기다림을 두 자리에서 보이지 않는다. 접힘(PEEK)에는 목록이 없고 요약 줄이
/// 「불러오는 중」 문구를 적으므로 이 판정은 반펼침·FULL 의 목록에만 쓰인다.
func showListLoadingFallback(loading: Bool, refreshButtonShown: Bool) -> Bool {
    loading && !refreshButtonShown
}

/// 지도 오른쪽 아래의 **카운트다운 새로고침 버튼** — 오너가 준 네이버 지도 참고 그대로: 짙은 원에
/// 원형 화살표 고리, 가운데에 남은 초. 자리는 시트 단계가 정한다(`refreshButtonPlacement`).
///
/// - 누르면 즉시 다시 읽고 15부터 다시 센다(`onClick`). 조회가 나가 있는 동안은 숫자 대신 **고리가 돈다**
///   (눌리지 않는다). 이 화면의 **유일한 로딩 표시**다 — 새 날짜·도착지·모드를 읽는 동안에도 목록 가운데에
///   스피너를 두지 않는다
/// - **동작 줄이기**(손쉬운 사용)가 켜져 있으면 돌리지 않고 고리를 흐리게만 한다 — 도는 표시는 장식이고,
///   상태는 「새로고침 중」으로 이미 읽힌다
/// - 색: 짙은 원(`InkPrimary`)에 흰 글자 — 지도 타일 위 어디서나 대비가 선다. 그림자는 지도 위 알약과
///   같은 단계(`mapOverlayShadow` = `MoyeotaElevation.MapOverlay` 4)다
/// - 숫자는 `BodySm` 세미볼드(13/600)에 **숫자 폭 고정**(`tabularNums`) — 15 → 9 로 줄어도 가운데가 흔들리지 않는다.
///   Bold 를 쓰지 않는 이유는 앱의 굵기 규칙(Bold 는 큰 버튼 글자·Display 만)이다
struct ExploreRefreshButton: View {
    let ui: ExploreRefreshUi
    let onClick: () -> Void

    // 원본은 애니메이터 배율(「애니메이션 삭제」)을 진입 때 한 번 읽는다. iOS 는 시스템의 「동작 줄이기」가 그 자리다
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 도는 고리의 시작 시각 — 돌기 시작할 때마다 0° 에서 시작한다(원본은 그때 무한 전환을 새로 만든다)
    @State private var spinStart = Date()

    var body: some View {
        let spinning = ui.refreshing && !reduceMotion
        let ringColor = ui.refreshing && reduceMotion ? MoyeotaColor.TextOnDark.opacity(0.5) : MoyeotaColor.TextOnDark
        Button(action: onClick) {
            ZStack {
                TimelineView(.animation(paused: !spinning)) { context in
                    CircularArrowRing(color: ringColor)
                        .padding(7)
                        .rotationEffect(.degrees(spinning ? spinAngle(at: context.date) : 0))
                }
                if !ui.refreshing {
                    Text("\(ui.secondsLeft)")
                        .moyeotaText(MoyeotaType.BodySm.copy(fontWeight: .semibold).tabularNums(), color: MoyeotaColor.TextOnDark)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: RefreshButtonSize, height: RefreshButtonSize)
            .background(MoyeotaColor.InkPrimary, in: Circle())
            .contentShape(Circle())
        }
        // 눌림 표시만 둔다 — 비활성(조회 중)이라고 흐리게 하지 않는다. 원본 `clickable(enabled = false)` 도 모양을 바꾸지 않는다
        .buttonStyle(PressFeedbackStyle())
        .disabled(ui.refreshing)
        .mapOverlayShadow(Circle())
        // 역할·비활성은 버튼이 알린다. 이름과 값만 더한다 — 가운데 숫자는 이름이 덮어 읽히지 않는다
        // (1초마다 바뀌는 글자가 이름에 섞이지 않게)
        .accessibilityLabel(REFRESH_BUTTON_LABEL)
        .accessibilityValue(refreshButtonStateDescription(ui: ui))
        .accessibilityHint("지금 새로고침")
        .onChange(of: spinning) { _, now in
            if now { spinStart = Date() }
        }
    }

    /// 0.9초에 한 바퀴 — 원본 `tween(900, LinearEasing)` 의 무한 반복
    private func spinAngle(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(spinStart))
        return elapsed.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
    }
}

/// 원형 화살표 고리 — 12시 방향에서 시계 방향으로 30° 지난 곳부터 300° 를 돌고 끝에 작은 화살촉. 아이콘 자산이 없어
/// (이 앱의 다른 아이콘처럼) 직접 그린다.
private struct CircularArrowRing: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let stroke: CGFloat = 2
            let inset = stroke / 2 + 1
            let diameter = min(size.width, size.height) - inset * 2
            let radius = diameter / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let startDegrees: Double = -90 + 30
            let sweepDegrees: Double = 300
            // y 가 아래로 자라는 좌표라 각이 커지는 쪽이 화면에서 시계 방향이다(원본 `drawArc` 와 같다)
            var arc = Path()
            arc.addRelativeArc(
                center: center,
                radius: radius,
                startAngle: .degrees(startDegrees),
                delta: .degrees(sweepDegrees)
            )
            context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            // 화살촉 — 호의 끝점에서 진행 방향(접선)으로 작은 삼각형
            let end = (startDegrees + sweepDegrees) * .pi / 180
            let tip = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
            let tangent = CGPoint(x: -sin(end), y: cos(end)) // 시계 방향 진행
            let normal = CGPoint(x: cos(end), y: sin(end))
            let head: CGFloat = 4
            var arrow = Path()
            arrow.move(to: CGPoint(x: tip.x + tangent.x * head, y: tip.y + tangent.y * head))
            arrow.addLine(to: CGPoint(x: tip.x - normal.x * head, y: tip.y - normal.y * head))
            arrow.addLine(to: CGPoint(x: tip.x + normal.x * head, y: tip.y + normal.y * head))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(color))
        }
        .accessibilityHidden(true)
    }
}
