@testable import FeatureExplore
import Foundation
import MoyeotaDomain
import Observation
import Testing

/// 17 탐색의 **15초 주기 갱신 + 카운트다운 버튼** (`ExploreRefresh.swift`).
///
/// 화면에는 「숫자가 줄어든다」로만 보이는 동작이라 스크린샷으로는 주기·재시작·멈춤을 확인할 수 없다.
/// 시계는 주입한 `sleep` 하나뿐이므로(`countDownToNextRefresh`·지도 디바운스) 시험의 **가상 시계**(`VirtualClock`)가
/// 곧 이 화면의 시계다 — `advance(by:)` 로 시간을 밀어 보고, 그동안 서버를 몇 번·무엇으로 불렀는지 센다.
///
/// 못 박는 것:
/// - **세 모드 모두** 15초마다 다시 읽고, 버튼 숫자가 15 → 1 로 줄어든다(「날짜로 찾기」 포함)
/// - 버튼은 **즉시** 다시 읽고 15부터 다시 센다. 조회 중에 누른 것은 버린다
/// - **지도를 움직여도 카운트다운은 그대로다** — 새 범위는 디바운스 뒤 곧바로 읽고, 남은 초는 이어 센다.
///   0 에서는 그때의 **최신 범위**로 읽는다. 날짜·도착지를 바꿔도 마찬가지다
/// - **가려지면 멈추고**, 돌아오면 즉시 1회 읽고 15부터 새로 센다
/// - 연속 `STALE_NOTICE_FAILURES`(=2) 회 실패하면 「낡음」을 켜고 성공 한 번이 끈다 — 지도 이동 조회의 실패도 센다
/// - 같은 목록을 다시 읽을 때 목록을 **로딩으로 덮지 않는다**. 새 목록(날짜·도착지)은 자리를 비우고 헤더에 개수가 없다
/// - 버튼은 FULL 에서도 보인다(자리 판정)
///
/// 원본은 `kotlinx-coroutines-test` 의 가상 시간(`advanceTimeBy`·`runCurrent`)으로 돈다. Swift 에는 그 시험 디스패처가
/// 없어 뷰모델에 주입하는 `sleep` 자리에 가상 시계를 넣는다 — 시각은 시계가 쥐고, 「지금 돌 수 있는 일」은 실제
/// 태스크가 시계의 다음 대기에 들어설 때까지 기다려 확인한다(`VirtualClock.runCurrent`). 카운트다운은 조회를
/// 기다리지 않고 다음 칸에 들어가므로, 시계를 민 뒤 그 사이 나간 조회가 끝나는 것은 `settle` 로 따로 본다.
@MainActor
@Suite(.serialized)
struct ExploreRefreshTest {
    private let bounds = MapBounds(swLat: 35.15, swLng: 129.05, neLat: 35.17, neLng: 129.07)
    private let moved = MapBounds(swLat: 35.20, swLng: 129.10, neLat: 35.22, neLng: 129.12)

    private func byDate(date: String = "2026-11-17", lat: Double = 35.23, lng: Double = 129.08) -> ReservationQuery {
        .byDate(departureLat: lat, departureLng: lng, date: date, destination: nil)
    }

    /// 나가 있던 조회가 끝나 버튼이 숫자로 돌아올 때까지 기다린다(원본 `runCurrent` 가 조회까지 돌리는 자리).
    private func settle(_ refreshUi: @MainActor () -> ExploreRefreshUi, sourceLocation: SourceLocation = #_sourceLocation) async {
        await eventually("조회가 끝난다", sourceLocation: sourceLocation) { !refreshUi().refreshing }
    }

    // ─────────────────────────── 순수 판정 ───────────────────────────

    @Test("카운트다운은 15에서 1까지 1초마다 줄고 15초 뒤에 끝난다")
    func countdownTicksFromFifteenToOne() async {
        let clock = VirtualClock()
        let log = TickLog()
        let task = Task { @MainActor in
            try? await countDownToNextRefresh(onTick: { log.ticks.append($0) }, sleep: { try await clock.sleep($0) })
            log.finished = true
        }
        await clock.runCurrent()
        #expect(log.ticks == [15])

        await clock.advance(by: 14_000)
        #expect(log.ticks == Array((1...15).reversed()))
        #expect(!log.finished, "1 을 보여 준 1초 동안은 아직 기다린다")

        await clock.advance(by: 1_000)
        #expect(log.finished)
        task.cancel()
    }

    @Test("주기는 15초이고 버튼은 15부터 센다")
    func intervalIsFifteenSeconds() {
        #expect(NEARBY_POLL_INTERVAL_MS == 15_000)
        #expect(REFRESH_COUNTDOWN_SECONDS == 15)
        #expect(ExploreRefreshUi().secondsLeft == REFRESH_COUNTDOWN_SECONDS)
    }

    /// 「날짜로 찾기」도 돈다 — 출발 시각은 그대로여도 자리는 차고 빈다(2026-11, 오너 UX 피드백 2차).
    @Test("세 모드 모두 주기 갱신과 버튼이 있다")
    func everyModeAutoRefreshes() {
        for mode in ExploreMode.allCases {
            #expect(exploreAutoRefreshes(mode: mode), "\(mode) 에 버튼이 없다")
        }
    }

    /// 남은 초는 읽지 않는다 — 1초마다 바뀌는 상태를 VoiceOver 가 쉬지 않고 읽게 된다.
    @Test("버튼의 스크린리더 상태는 주기와 조회 중만 말한다")
    func accessibilityStateNamesPeriodOnly() {
        #expect(REFRESH_BUTTON_LABEL == "목록 새로고침")
        #expect(refreshButtonStateDescription(ui: ExploreRefreshUi(secondsLeft: 7)) == "15초마다 자동")
        #expect(refreshButtonStateDescription(ui: ExploreRefreshUi(secondsLeft: 1)) == "15초마다 자동")
        #expect(refreshButtonStateDescription(ui: ExploreRefreshUi(refreshing: true)) == "새로고침 중")
    }

    // ─────────────────────────── 버튼 자리 ───────────────────────────

    /// ★ FULL 에서 **숨기지 않는다** — 지도가 다 가려져도 목록은 15초마다 바뀐다. 목록 위 오른쪽 아래, 끝에서
    /// 16, 하단 CTA 윗변 16 위에 뜬다.
    @Test("FULL 에서는 목록 위 CTA 16 위 끝에서 16 에 뜬다")
    func fullFloatsOverList() {
        let placement = refreshButtonPlacement(sheetState: .full, containerHeight: 600, sheetHeight: 600, bottomCtaTop: 60)

        #expect(placement == RefreshButtonPlacement(spot: .overList, end: 16, bottom: 76))
    }

    /// 접힘·반펼침은 예전 자리 그대로 — 네이버 줌 컨트롤과 같은 세로선, 시트 윗변 16 위.
    @Test("접힘과 반펼침에서는 지도 위 시트 윗변 16 위에 선다")
    func peekAndHalfStayAboveSheet() {
        for (state, sheet) in [(ExploreSheetState.hidden, CGFloat(28)), (.peek, 96), (.half, 300)] {
            let placement = refreshButtonPlacement(sheetState: state, containerHeight: 600, sheetHeight: sheet, bottomCtaTop: 60)
            #expect(placement == RefreshButtonPlacement(spot: .aboveSheet, end: RefreshButtonEndInset, bottom: sheet + 16), "\(state)")
        }
    }

    /// 끝까지 끌어 올리는 동안 지도에 자리가 없어지면 숨지 않고 목록 위로 내려온다.
    @Test("지도에 버튼 자리가 없으면 목록 위로 내려오고 CTA 가 없으면 아래 끝에서 16 이다")
    func noRoomFloatsOverList() {
        let dragged = refreshButtonPlacement(sheetState: .half, containerHeight: 600, sheetHeight: 560, bottomCtaTop: 60)
        #expect(dragged.spot == .overList)
        #expect(dragged.bottom == 76)

        let noCta = refreshButtonPlacement(sheetState: .full, containerHeight: 600, sheetHeight: 600, bottomCtaTop: nil)
        #expect(noCta.bottom == 16)
    }

    /// 목록 위에 뜬 버튼은 목록 아래 끝에서 8~56 을 덮는다(CTA 줄 위 여백 8 + 간격 16 + 버튼 48). 목록 끝
    /// 여백이 그보다 커야 끝까지 내린 마지막 줄의 「합류」가 버튼 밑에 깔리지 않는다.
    @Test("목록 끝 여백은 떠 있는 버튼보다 높다")
    func listClearanceCoversFloatingButton() {
        let coveredAboveListBottom = RefreshButtonGap + RefreshButtonSize - 8
        #expect(RefreshButtonListClearance > coveredAboveListBottom)
    }

    // ─────────────────────────── 버튼이 없을 때의 기다림 ───────────────────────────

    /// 권한이 없으면 지도 대신 권한 안내가 깔리고 버튼도 없다 — 조회는 기준 범위로 그대로 돈다(`ExploreRoute`).
    /// 그릴 것이 없을 때(「날짜로 찾기」가 내 위치를 기다리는 중)도 없다.
    @Test("새로고침 버튼은 그릴 것이 있고 위치 권한이 있을 때만 보인다")
    func refreshButtonNeedsPermission() {
        #expect(refreshButtonShown(refresh: ExploreRefreshUi(), locationGranted: true))
        #expect(!refreshButtonShown(refresh: ExploreRefreshUi(), locationGranted: false))
        #expect(!refreshButtonShown(refresh: nil, locationGranted: true))
        #expect(!refreshButtonShown(refresh: nil, locationGranted: false))
    }

    /// ★ 리뷰 반영(원본 PR #99): 목록 가운데 스피너를 걷은 뒤 기다림을 보이는 것은 버튼뿐이었다. 권한을 거부하면
    /// 버튼이 없어, 첫 조회와 에러 화면의 「다시 시도」 동안 목록이 빈 채 아무것도 돌지 않았다. 버튼이 없을 때만
    /// 목록에 작은 스피너를 둔다 — 버튼이 있으면 두 자리에서 기다림을 보이지 않는다. 세 모드 모두 같은 규칙이다.
    @Test("읽는 중인데 버튼이 없을 때만 목록에 대체 로딩 표시를 둔다")
    func listLoadingFallbackOnlyWithoutButton() {
        #expect(showListLoadingFallback(loading: true, refreshButtonShown: false))
        #expect(!showListLoadingFallback(loading: true, refreshButtonShown: true), "버튼의 도는 고리가 이미 기다림을 보인다")
        #expect(!showListLoadingFallback(loading: false, refreshButtonShown: false))
        #expect(!showListLoadingFallback(loading: false, refreshButtonShown: true))

        // 권한 거부 경로 그대로: 그릴 것(15초 버튼)은 있어도 권한이 없으면 버튼이 없고, 그래서 목록이 스피너를 맡는다
        let shownWithoutPermission = refreshButtonShown(refresh: ExploreRefreshUi(refreshing: true), locationGranted: false)
        #expect(showListLoadingFallback(loading: true, refreshButtonShown: shownWithoutPermission))
    }

    // ─────────────────────────── 망가진 조회 ───────────────────────────

    /// ★ 원본 리뷰 반영 2차(PR #99): `ExploreRefreshCycle` 의 `load` 는 던지지 않기로 했지만, 어기고 새는 오류 하나가
    /// 원본에서는 프로세스를 죽였다. 이제 조회 태스크가 받아 삼키고(종류만 로그·진단) 다음 0 에서 다시 읽는다.
    @Test("조회가 약속을 어기고 던져도 시계는 살아 있고 다음 0 에서 다시 읽는다")
    func brokenLoadKeepsCycleAlive() async {
        let clock = VirtualClock()
        let log = BrokenLoadLog()
        let reports = ReportLog()
        Diagnostics.install { site, error in reports.add(site: site, error: error) }
        defer { Diagnostics.reset() }
        let cycle = ExploreRefreshCycle<String>(
            sleep: { try await clock.sleep($0) },
            load: { query in
                log.reads.append(query)
                if log.reads.count == 1 { throw IllegalStateException("상태 정리에서 생긴 결함") }
            },
            onUi: { log.ui = $0 }
        )
        cycle.update("범위", timing: .now)
        await cycle.setVisible(true)?.value
        await clock.runCurrent()

        #expect(log.reads.count == 1)
        #expect(log.ui == ExploreRefreshUi(secondsLeft: 15), "조회 칸이 비고 버튼이 숫자로 돌아온다")
        let broken = reports.entries.filter { $0.site == .exploreRefresh }
        #expect(broken.count == 1)
        #expect(broken.first?.error is IllegalStateException)

        await clock.advance(by: 15_000)
        await eventually("다음 0 에서 다시 읽는다") { log.reads.count == 2 }
        await settle { log.ui ?? ExploreRefreshUi(refreshing: true) }

        await cycle.refreshNow()?.value
        #expect(log.reads.count == 3, "버튼도 그대로 듣는다")
        #expect(
            reports.entries.filter { $0.site == .exploreRefresh }.count == 1,
            "두 번째부터는 멀쩡한 조회라 보고가 늘지 않는다"
        )
        cycle.setVisible(false)
    }

    // ─────────────────────────── 실시간 (ExploreViewModel) ───────────────────────────

    private func realtimeViewModel(_ repository: CountingRepository, _ clock: VirtualClock) -> ExploreViewModel {
        ExploreViewModel(repository: repository, sleep: { try await clock.sleep($0) })
    }

    @Test("실시간 목록은 보이는 동안 15초마다 다시 읽고 버튼 숫자가 줄어든다")
    func realtimePollsEveryFifteenSeconds() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = realtimeViewModel(repository, clock)
        viewModel.onInitialBounds(bounds)
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        #expect(repository.nearbyCalls == 1, "보이자마자 1회")
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 15))

        await clock.advance(by: 5_000)
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 10))
        #expect(repository.nearbyCalls == 1)

        await clock.advance(by: 10_000)
        await settle { viewModel.refreshUi }
        #expect(repository.nearbyCalls == 2, "15초가 지나면 다시 읽는다")
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 15), "읽고 나면 15부터 다시 센다")

        await clock.advance(by: 14_999)
        #expect(repository.nearbyCalls == 2)
        await clock.advance(by: 1)
        await settle { viewModel.refreshUi }
        #expect(repository.nearbyCalls == 3)

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    @Test("새로고침 버튼은 즉시 다시 읽고 15부터 다시 센다")
    func refreshButtonReadsNowAndRestartsCountdown() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = realtimeViewModel(repository, clock)
        viewModel.onInitialBounds(bounds)
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }
        await clock.advance(by: 9_000)
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 6))

        viewModel.refreshNow()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        #expect(repository.nearbyCalls == 2, "기다리지 않고 바로 읽는다(디바운스 없음)")
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 15))
        // 새 카운트다운이 처음부터 돈다 — 옛 카운트다운의 남은 6초에 다시 읽지 않는다
        await clock.advance(by: 6_000)
        #expect(repository.nearbyCalls == 2)
        await clock.advance(by: 9_000)
        await settle { viewModel.refreshUi }
        #expect(repository.nearbyCalls == 3)

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    @Test("조회 중에 누른 새로고침은 버린다")
    func refreshWhileFetchingIsDropped() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = realtimeViewModel(repository, clock)
        viewModel.onInitialBounds(bounds)
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        let gate = Gate()
        repository.gate = gate
        await clock.advance(by: 15_000) // 주기 조회가 나가서 문 앞에 매달린다
        await eventually("주기 조회가 나간다") { repository.nearbyCalls == 2 }
        #expect(viewModel.refreshUi.refreshing)

        viewModel.refreshNow()
        await clock.runCurrent()
        #expect(repository.nearbyCalls == 2, "겹친 조회를 보내지 않는다")

        repository.gate = nil
        gate.open()
        await settle { viewModel.refreshUi }
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 15))

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    @Test("가려진 동안에는 읽지 않고 돌아오면 즉시 읽고 15부터 새로 센다")
    func hiddenStopsAndReturnReadsNow() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = realtimeViewModel(repository, clock)
        viewModel.onInitialBounds(bounds)
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }
        await clock.advance(by: 5_000)
        #expect(viewModel.refreshUi.secondsLeft == 10)

        viewModel.onScreenStop()
        await clock.runCurrent()
        await clock.advance(by: 120_000)
        #expect(repository.nearbyCalls == 1, "가려진 2분 동안 0회")

        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }
        #expect(repository.nearbyCalls == 2, "돌아오자마자 1회")
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 15), "남은 10초를 이어 세지 않고 처음부터")

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// ★ 오너 요청 B — **지도를 움직여도 카운트다운은 그대로다.** 새 범위는 디바운스(400) 뒤 곧바로 읽지만
    /// 남은 초는 이어 세고, 0 에서는 **그때의 범위**(움직인 범위)로 다시 읽는다.
    @Test("지도를 움직여도 카운트다운은 이어 세고 0 에서 최신 범위로 읽는다")
    func mapMoveKeepsCountdown() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = realtimeViewModel(repository, clock)
        viewModel.onInitialBounds(bounds)
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }
        await clock.advance(by: 5_000)
        #expect(viewModel.refreshUi.secondsLeft == 10)

        viewModel.onVisibleBoundsChange(moved)
        await clock.runCurrent()
        #expect(repository.nearbyCalls == 1, "디바운스 동안은 읽지 않는다")
        await clock.advance(by: BOUNDS_DEBOUNCE_MS)
        await settle { viewModel.refreshUi }
        #expect(repository.nearbyCalls == 2, "움직인 범위를 곧바로 읽는다")
        #expect(repository.nearbyAreas.last == moved.expanded())
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 10), "15로 돌아가지 않는다")

        await clock.advance(by: 600)
        #expect(viewModel.refreshUi.secondsLeft == 9, "그 자리에서 이어 센다")

        await clock.advance(by: 9_000) // 보이기 시작한 지 15초
        await settle { viewModel.refreshUi }
        #expect(repository.nearbyCalls == 3, "0 에서 자동 갱신")
        #expect(repository.nearbyAreas.last == moved.expanded(), "자동 갱신은 최신 범위로 읽는다")
        #expect(viewModel.refreshUi.secondsLeft == 15)

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// 지도 이동 조회가 나가 있는 동안 버튼은 돌지만, **초는 밑에서 계속 줄어** 끝나면 그 숫자부터 보인다.
    @Test("지도 이동 조회 중에도 초는 줄어들고 끝나면 이어 보인다")
    func countdownContinuesUnderMapMoveFetch() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = realtimeViewModel(repository, clock)
        viewModel.onInitialBounds(bounds)
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }
        await clock.advance(by: 5_000)

        let gate = Gate()
        repository.gate = gate
        viewModel.onVisibleBoundsChange(moved)
        await clock.advance(by: BOUNDS_DEBOUNCE_MS)
        await eventually("지도 이동 조회가 나간다") { repository.nearbyCalls == 2 }
        #expect(viewModel.refreshUi.refreshing, "지도 이동 조회 중에는 돈다")

        await clock.advance(by: 3_000) // 보이기 시작한 지 8.4초
        #expect(viewModel.refreshUi.refreshing)
        repository.gate = nil
        gate.open()
        await settle { viewModel.refreshUi }

        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 7), "15가 아니라 줄어든 7초부터")

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// 0 에 닿았을 때 디바운스가 아직 기다리는 중이면 자동 갱신이 **그 범위로** 읽고 디바운스는 그것으로 갈음한다
    /// — 같은 범위를 0.4초 사이에 두 번 읽지 않는다.
    @Test("디바운스 중에 0 이 오면 움직인 범위로 한 번만 읽는다")
    func tickDuringDebounceReadsLatestOnce() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = realtimeViewModel(repository, clock)
        viewModel.onInitialBounds(bounds)
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        await clock.advance(by: 14_800)
        viewModel.onVisibleBoundsChange(moved)
        await clock.advance(by: 200) // 0 — 디바운스는 아직 200 남았다
        await settle { viewModel.refreshUi }
        #expect(repository.nearbyCalls == 2)
        #expect(repository.nearbyAreas.last == moved.expanded())

        await clock.advance(by: 1_000)
        await settle { viewModel.refreshUi }
        #expect(repository.nearbyCalls == 2, "디바운스가 같은 범위를 또 읽지 않는다")

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    @Test("주기 조회가 연속 두 번 실패하면 낡음을 켜고 성공하면 끈다")
    func staleAfterTwoPollFailures() async {
        let repository = CountingRepository()
        repository.failNearbyFromCall = 2
        let clock = VirtualClock()
        let viewModel = realtimeViewModel(repository, clock)
        viewModel.onInitialBounds(bounds)
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        await clock.advance(by: 15_000) // 실패 1회 — 아직 알리지 않는다
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.realtimeStale == false)

        await clock.advance(by: 15_000) // 실패 2회 = 30초 — 알린다. 목록은 그대로다
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.realtimeStale == true)
        #expect(viewModel.uiState.realtimeParties?.count == 1)

        repository.failNearbyFromCall = Int.max
        await clock.advance(by: 15_000)
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.realtimeStale == false)

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// ★ 다시 세운 「낡음」 규칙 — 지도 이동이 더는 패스를 새로 열지 않으므로 **지도 이동 조회의 실패도 같은
    /// 카운터에 들어간다**. 지도 이동 실패 1회 + 자동 갱신 실패 1회 = 연속 2회.
    @Test("지도 이동 조회의 실패와 자동 갱신의 실패를 함께 센다")
    func mapMoveAndTickFailuresCountTogether() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = realtimeViewModel(repository, clock)
        viewModel.onInitialBounds(bounds)
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        repository.failNearby = true
        viewModel.onVisibleBoundsChange(moved)
        await clock.advance(by: BOUNDS_DEBOUNCE_MS) // 지도 이동 조회 실패 1회
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.realtimeStale == false, "한 번으로는 알리지 않는다")

        await clock.advance(by: 15_000 - BOUNDS_DEBOUNCE_MS) // 자동 갱신 실패 — 연속 2회
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.realtimeStale == true)

        repository.failNearby = false
        viewModel.refreshNow()
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.realtimeStale == false, "성공 한 번이 끈다")

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// 첫 조회는 가운데 스피너 대신 버튼이 돈다 — 그동안 화면 상태는 `loading` 이고 버튼은 「조회 중」이다.
    @Test("실시간 첫 조회 동안 버튼이 돌고 끝나면 숫자가 보인다")
    func firstLoadSpinsButton() async {
        let repository = CountingRepository()
        let gate = Gate()
        repository.gate = gate
        let clock = VirtualClock()
        let viewModel = realtimeViewModel(repository, clock)
        viewModel.onInitialBounds(bounds)
        viewModel.onScreenStart()
        await clock.runCurrent()
        await eventually("첫 조회가 나간다") { repository.nearbyCalls == 1 }

        #expect(viewModel.uiState == .loading)
        #expect(viewModel.refreshUi.refreshing)

        repository.gate = nil
        gate.open()
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.realtimeParties != nil)
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 15))

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    // ─────────────────────────── 예약 (ReservationFinderViewModel) ───────────────────────────

    private func finderViewModel(_ repository: CountingRepository, _ clock: VirtualClock) -> ReservationFinderViewModel {
        ReservationFinderViewModel(repository: repository, sleep: { try await clock.sleep($0) })
    }

    @Test("곧 출발은 15초마다 다시 읽고 버튼과 지도 이동도 목록을 로딩으로 덮지 않는다")
    func soonPollsWithoutCoveringList() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = finderViewModel(repository, clock)
        let states = FinderStateRecorder(viewModel)
        viewModel.request(.soon(bounds: bounds))
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        #expect(repository.soonCalls == 1)
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 15))

        await clock.advance(by: 15_000)
        await settle { viewModel.refreshUi }
        #expect(repository.soonCalls == 2)

        viewModel.refreshNow()
        // 원본의 상태 기록은 `StateFlow` 가 합쳐 흘릴 수 있다. 여기서는 로딩을 바로 그 자리에서 쓰는지도 본다
        #expect(viewModel.uiState != .loading, "버튼이 보던 목록을 로딩으로 덮었다")
        await settle { viewModel.refreshUi }
        #expect(repository.soonCalls == 3, "버튼은 즉시 읽는다")
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 15))

        await clock.advance(by: 3_000)
        viewModel.request(.soon(bounds: moved))
        #expect(viewModel.uiState != .loading, "지도 이동이 보던 목록을 로딩으로 덮었다")
        await clock.advance(by: BOUNDS_DEBOUNCE_MS)
        await settle { viewModel.refreshUi }
        #expect(repository.soonCalls == 4, "지도를 움직이면 디바운스 뒤 읽는다")
        #expect(repository.soonAreas.last == moved.expanded())
        #expect(viewModel.refreshUi.secondsLeft == 12, "카운트다운은 그대로")

        // 첫 목록이 뜬 뒤로는 로딩이 한 번도 끼어들지 않는다
        // (처음의 로딩은 곧 이어진 성공과 함께 기록되지 않을 수 있어 세지 않는다)
        let recorded = states.states
        let firstShown = recorded.firstIndex { if case .success = $0 { true } else { false } }
        #expect(firstShown != nil)
        if let firstShown {
            #expect(
                !recorded[firstShown...].contains(.loading),
                "목록을 보여 준 뒤 로딩으로 덮었다: \(recorded)"
            )
        }

        viewModel.onScreenStop()
        await clock.runCurrent()
        await clock.advance(by: 60_000)
        #expect(repository.soonCalls == 4, "가려지면 멈춘다")
    }

    /// ★ 오너 요청 A — 「날짜로 찾기」도 보이는 동안 15초마다 다시 읽는다(예전에는 한 번의 검색이었다).
    @Test("날짜로 찾기도 보이는 동안 15초마다 다시 읽는다")
    func byDatePollsEveryFifteenSeconds() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = finderViewModel(repository, clock)
        viewModel.request(byDate())
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }
        #expect(repository.searchCalls == 1)
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 15))

        await clock.advance(by: 5_000)
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 10))
        await clock.advance(by: 10_000)
        await settle { viewModel.refreshUi }
        #expect(repository.searchCalls == 2, "15초에 다시 읽는다")
        await clock.advance(by: 15_000)
        await settle { viewModel.refreshUi }
        #expect(repository.searchCalls == 3)

        viewModel.onScreenStop()
        await clock.runCurrent()
        await clock.advance(by: 60_000)
        #expect(repository.searchCalls == 3, "가려지면 멈춘다")
    }

    /// ★ 같은 목록을 다시 읽을 때(자동 갱신·버튼·화면 복귀·내 위치가 조금 움직임) **목록을 로딩으로 덮지 않는다** —
    /// 오너 스크린샷의 「목록 가운데 큰 스피너」가 그 덮개였다.
    @Test("날짜로 찾기에서 같은 목록을 다시 읽을 때는 로딩으로 덮지 않는다")
    func byDateSameListRefreshKeepsList() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = finderViewModel(repository, clock)
        let states = FinderStateRecorder(viewModel)
        viewModel.request(byDate())
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        await clock.advance(by: 15_000) // 자동 갱신
        await settle { viewModel.refreshUi }
        viewModel.refreshNow() // 버튼
        #expect(viewModel.uiState != .loading)
        await settle { viewModel.refreshUi }
        viewModel.request(byDate(lat: 35.2301, lng: 129.0801)) // GPS 가 몇 m 흔들림
        #expect(viewModel.uiState != .loading)
        await clock.runCurrent()
        viewModel.onScreenStop() // 화면 복귀
        viewModel.onScreenStart()
        #expect(viewModel.uiState != .loading)
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        #expect(repository.searchCalls == 4)
        let recorded = states.states
        let firstShown = recorded.firstIndex { if case .success = $0 { true } else { false } }
        #expect(firstShown != nil)
        if let firstShown {
            #expect(!recorded[firstShown...].contains(.loading), "같은 목록을 다시 읽는 동안 로딩이 끼어들었다: \(recorded)")
        }

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// ★ 날짜를 바꾸면 **새 목록**이다 — 앞 날짜의 줄을 남기지 않고 비운 채(loading) 읽는다. 헤더에는 개수가 없고
    /// (「11월 18일 (수) 출발 · 출발 시간 순」), 기다림은 버튼의 도는 고리뿐이다. 카운트다운은 그대로 센다.
    @Test("날짜를 바꾸면 목록을 비우고 헤더에 개수 없이 읽으며 카운트다운은 그대로다")
    func newDateClearsListAndKeepsCountdown() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = finderViewModel(repository, clock)
        viewModel.request(byDate(date: "2026-11-17"))
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }
        await clock.advance(by: 5_000)
        #expect(viewModel.uiState.finderItems != nil)

        let gate = Gate()
        repository.reservationGate = gate
        viewModel.request(byDate(date: "2026-11-18"))
        #expect(viewModel.uiState == .loading, "앞 날짜의 줄을 남기지 않는다")
        await eventually("새 날짜를 기다리지 않고 읽는다") { repository.searchedDates.last == "2026-11-18" }
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 10, refreshing: true), "카운트다운은 그대로, 버튼만 돈다")
        let count = exploreHeaderCount(0, loading: true, locating: false, failed: false)
        #expect(count == nil, "읽는 중에는 개수를 적지 않는다")
        #expect(exploreListTitle(mode: .byDate, count: count, dateLabel: "11월 18일 (수)") == "11월 18일 (수) 출발 · 출발 시간 순")

        repository.reservationGate = nil
        gate.open()
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.finderItems != nil)
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 10))

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// 「날짜로 찾기」의 내 위치는 1초마다 몇 m 씩 흔들린다 — 그때마다 읽지 않고, **다음 자동 갱신이 최신 위치로** 읽는다.
    @Test("내 위치가 움직이면 바로 읽지 않고 다음 자동 갱신이 새 위치로 읽는다")
    func locationDriftWaitsForTick() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = finderViewModel(repository, clock)
        viewModel.request(byDate(lat: 35.23, lng: 129.08))
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        await clock.advance(by: 3_000)
        viewModel.request(byDate(lat: 35.2302, lng: 129.0803))
        await clock.advance(by: 1_000)
        viewModel.request(byDate(lat: 35.2304, lng: 129.0806))
        await clock.advance(by: 1_000)
        #expect(repository.searchCalls == 1, "위치가 바뀔 때마다 읽지 않는다")

        await clock.advance(by: 10_000)
        await settle { viewModel.refreshUi }
        #expect(repository.searchCalls == 2)
        #expect(repository.searchedFrom.last == .init(lat: 35.2304, lng: 129.0806), "자동 갱신은 최신 위치로 읽는다")

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// ★ 원본 리뷰 반영 3차(PR #99): 실패 화면이어도 새 위치는 **다음 자동 갱신에** 읽는다. 위치는 1초마다 오므로, 실패
    /// 화면에서 바로 읽게 하면 빨리 실패하는 망(오프라인)에서 실패 → 다음 위치 → 다시 조회가 1초마다 되풀이된다.
    @Test("날짜로 찾기가 실패 화면이어도 새 위치는 다음 자동 갱신에 읽는다")
    func failedByDateReadsFreshLocationOnNextTick() async {
        let repository = CountingRepository()
        repository.failReservations = true
        let clock = VirtualClock()
        let viewModel = finderViewModel(repository, clock)
        viewModel.request(byDate(lat: 35.23, lng: 129.08))
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState == .failed)
        #expect(repository.searchCalls == 1)

        // 오프라인처럼 빨리 실패하는 망에서 위치가 1초마다 흔들린다 — 그때마다 보내지 않는다
        for i in 1...5 {
            await clock.advance(by: 1_000)
            viewModel.request(byDate(lat: 35.23 + Double(i) * 0.0001, lng: 129.08))
        }
        await clock.advance(by: BOUNDS_DEBOUNCE_MS)
        #expect(repository.searchCalls == 1, "위치가 흔들려도 다시 보내지 않는다")

        // 다음 자동 갱신(처음부터 15초)이 마지막 위치로 읽는다
        repository.failReservations = false
        await clock.advance(by: 15_000 - 5_000 - BOUNDS_DEBOUNCE_MS)
        await settle { viewModel.refreshUi }
        #expect(repository.searchCalls == 2, "다음 갱신에 읽는다")
        #expect(repository.searchedFrom.last == .init(lat: 35.23 + 5 * 0.0001, lng: 129.08))
        #expect(viewModel.uiState.finderItems != nil)

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// 빈 자리로 조회가 **오는 중**이면 위치가 1초마다 흔들려도 그 조회를 끊고 다시 보내지 않는다 — 끊으면 응답이
    /// 「다음 위치까지 남은 시간」보다 느린 망에서 조회가 영영 끝나지 않는다(`reservationLoadTiming` 설명).
    @Test("날짜로 찾기의 빈 자리로 조회가 오는 중이면 위치가 흔들려도 끊지 않는다")
    func pendingByDateFetchSurvivesDrift() async {
        let repository = CountingRepository()
        let gate = Gate()
        repository.reservationGate = gate
        let clock = VirtualClock()
        let viewModel = finderViewModel(repository, clock)
        viewModel.request(byDate(lat: 35.23, lng: 129.08))
        viewModel.onScreenStart()
        await clock.runCurrent()
        await eventually("첫 조회가 나간다") { repository.searchCalls == 1 }
        #expect(viewModel.uiState == .loading)

        for lat in [35.2301, 35.2302, 35.2303] {
            await clock.advance(by: 1_000)
            viewModel.request(byDate(lat: lat, lng: 129.08))
            await clock.runCurrent()
        }
        await clock.advance(by: BOUNDS_DEBOUNCE_MS)
        #expect(repository.searchCalls == 1, "오는 중인 조회를 끊고 다시 보내지 않는다")
        #expect(viewModel.refreshUi.refreshing)

        repository.reservationGate = nil
        gate.open()
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.finderItems != nil)

        await clock.advance(by: 15_000 - 3_000 - BOUNDS_DEBOUNCE_MS)
        await settle { viewModel.refreshUi }
        #expect(repository.searchedFrom.last == .init(lat: 35.2303, lng: 129.08), "다음 자동 갱신이 최신 위치로 읽는다")

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// 「곧 출발」↔「날짜로 찾기」는 같은 목록 자리다 — 카운트다운을 이어 센다. 실시간으로 가면(요청 없음) 멈추고,
    /// 예약 모드로 돌아오면 그 목록이 다시 보이는 것이라 즉시 읽고 15부터 센다.
    @Test("예약 모드끼리 바꾸면 이어 세고 실시간에 다녀오면 15부터 센다")
    func modeSwitchCountdown() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = finderViewModel(repository, clock)
        viewModel.request(.soon(bounds: bounds))
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }
        await clock.advance(by: 4_000)

        viewModel.request(byDate())
        await settle { viewModel.refreshUi }
        #expect(repository.searchCalls == 1)
        #expect(viewModel.refreshUi.secondsLeft == 11)

        viewModel.request(nil) // 실시간 모드
        await clock.runCurrent()
        #expect(viewModel.uiState == .idle)
        await clock.advance(by: 60_000)
        #expect(repository.soonCalls == 1, "실시간 모드에서는 예약을 읽지 않는다")
        #expect(repository.searchCalls == 1)

        viewModel.request(.soon(bounds: bounds))
        await clock.runCurrent()
        await settle { viewModel.refreshUi }
        #expect(repository.soonCalls == 2)
        #expect(viewModel.refreshUi == ExploreRefreshUi(secondsLeft: 15))

        viewModel.onScreenStop()
        await clock.runCurrent()
    }

    /// 예약 목록도 같은 「낡음」 규칙이다 — 「곧 출발」의 지도 이동 실패와 자동 갱신 실패를 함께 센다.
    @Test("곧 출발의 지도 이동 실패와 자동 갱신 실패가 연속 두 번이면 낡음을 켠다")
    func soonMapMoveAndTickFailuresCountTogether() async {
        let repository = CountingRepository()
        let clock = VirtualClock()
        let viewModel = finderViewModel(repository, clock)
        viewModel.request(.soon(bounds: bounds))
        viewModel.onScreenStart()
        await clock.runCurrent()
        await settle { viewModel.refreshUi }

        repository.failReservations = true
        viewModel.request(.soon(bounds: moved))
        await clock.advance(by: BOUNDS_DEBOUNCE_MS)
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.finderStale == false)

        await clock.advance(by: 15_000 - BOUNDS_DEBOUNCE_MS)
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.finderStale == true, "목록을 남긴 채 낡음을 켠다")
        #expect(viewModel.uiState.finderItems?.count == 1)

        repository.failReservations = false
        await clock.advance(by: 15_000)
        await settle { viewModel.refreshUi }
        #expect(viewModel.uiState.finderStale == false)

        viewModel.onScreenStop()
        await clock.runCurrent()
    }
}

// ─────────────────────────── 시험 도구 ───────────────────────────

private struct TestFailure: Error {}

private func testRide() -> Ride {
    Ride(
        id: "1",
        origin: "부산대 정문",
        destination: "서면역",
        departureLabel: "",
        capacity: 3,
        members: [],
        farePerPerson: 0,
        totalFare: 0,
        status: .recruiting
    )
}

private extension ExploreViewModel.UiState {
    var realtimeStale: Bool? {
        if case .success(_, let stale) = self { stale } else { nil }
    }

    var realtimeParties: [Ride]? {
        if case .success(let parties, _) = self { parties } else { nil }
    }
}

private extension ReservationFinderViewModel.UiState {
    var finderStale: Bool? {
        if case .success(_, let stale) = self { stale } else { nil }
    }

    var finderItems: [ReservationCardUi]? {
        if case .success(let items, _) = self { items } else { nil }
    }
}

@MainActor
private final class BrokenLoadLog {
    var reads: [String] = []
    var ui: ExploreRefreshUi?
}

/// `Diagnostics` 로 올라온 보고를 적는다 — sink 는 아무 스레드에서나 불릴 수 있어 잠근다.
private final class ReportLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [(site: FailureSite, error: any Error)] = []

    var entries: [(site: FailureSite, error: any Error)] { lock.withLock { log } }

    func add(site: FailureSite, error: any Error) {
        lock.withLock { log.append((site, error)) }
    }
}

@MainActor
private final class TickLog {
    var ticks: [Int] = []
    var finished = false
}

/// 원본 `backgroundScope.launch { uiState.collect { states += it } }` 자리 — 예약 조회 상태가 바뀔 때마다 적는다.
@MainActor
private final class FinderStateRecorder {
    private(set) var states: [ReservationFinderViewModel.UiState] = []
    private let viewModel: ReservationFinderViewModel

    init(_ viewModel: ReservationFinderViewModel) {
        self.viewModel = viewModel
        states.append(viewModel.uiState)
        track()
    }

    private func track() {
        withObservationTracking {
            _ = viewModel.uiState
        } onChange: { [weak self] in
            guard let self else { return }
            // 바뀌기 직전에 불린다 — 바뀐 값은 다음 차례에 읽는다
            Task { @MainActor in self.record() }
        }
    }

    private func record() {
        states.append(viewModel.uiState)
        track()
    }
}

/// 시험이 열어 줄 때까지 조회를 붙잡는 문(원본 `CompletableDeferred<Unit>`).
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if opened { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let pending = lock.withLock {
            opened = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}

/// 부른 횟수·물은 값을 세는 가짜 저장소. `gate`·`reservationGate` 가 있으면 조회가 그 문이 열릴 때까지 매달린다
/// (조회 중 상태). 실패는 엔드포인트마다 켜고 끈다.
private final class CountingRepository: RideRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var nearby = 0
    private var soon = 0
    private var search = 0
    private var failFrom = Int.max
    private var failingNearby = false
    private var failingReservations = false
    private var currentGate: Gate?
    private var currentReservationGate: Gate?
    private var nearbyAreaLog: [MapBounds] = []
    private var soonAreaLog: [MapBounds] = []
    private var searchedFromLog: [LatLngPair] = []
    private var searchedDateLog: [String] = []

    struct LatLngPair: Equatable {
        var lat: Double
        var lng: Double
    }

    var nearbyCalls: Int { lock.withLock { nearby } }
    var soonCalls: Int { lock.withLock { soon } }
    var searchCalls: Int { lock.withLock { search } }
    var nearbyAreas: [MapBounds] { lock.withLock { nearbyAreaLog } }
    var soonAreas: [MapBounds] { lock.withLock { soonAreaLog } }
    var searchedFrom: [LatLngPair] { lock.withLock { searchedFromLog } }
    var searchedDates: [String] { lock.withLock { searchedDateLog } }
    var failNearbyFromCall: Int {
        get { lock.withLock { failFrom } }
        set { lock.withLock { failFrom = newValue } }
    }
    var failNearby: Bool {
        get { lock.withLock { failingNearby } }
        set { lock.withLock { failingNearby = newValue } }
    }
    var failReservations: Bool {
        get { lock.withLock { failingReservations } }
        set { lock.withLock { failingReservations = newValue } }
    }
    var gate: Gate? {
        get { lock.withLock { currentGate } }
        set { lock.withLock { currentGate = newValue } }
    }
    var reservationGate: Gate? {
        get { lock.withLock { currentReservationGate } }
        set { lock.withLock { currentReservationGate = newValue } }
    }

    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] {
        let gate: Gate? = lock.withLock {
            nearby += 1
            nearbyAreaLog.append(MapBounds(swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng))
            return currentGate
        }
        await gate?.wait()
        let failing = lock.withLock { failingNearby || nearby >= failFrom }
        if failing { throw URLError(.notConnectedToInternet) }
        return [testRide()]
    }

    func getReservationsSoon(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] {
        let gate: Gate? = lock.withLock {
            soon += 1
            soonAreaLog.append(MapBounds(swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng))
            return currentReservationGate
        }
        await gate?.wait()
        if lock.withLock({ failingReservations }) { throw URLError(.notConnectedToInternet) }
        return [testRide()]
    }

    func searchReservations(
        departureLat: Double,
        departureLng: Double,
        date: String,
        destination: ReservationDestination?
    ) async throws -> [ReservationSearchResult] {
        let gate: Gate? = lock.withLock {
            search += 1
            searchedFromLog.append(LatLngPair(lat: departureLat, lng: departureLng))
            searchedDateLog.append(date)
            return currentReservationGate
        }
        await gate?.wait()
        if lock.withLock({ failingReservations }) { throw URLError(.notConnectedToInternet) }
        return [ReservationSearchResult(ride: testRide(), destinationNearby: nil)]
    }

    func getNearbyParties() -> [Ride] { [] }
    func getParties() async throws -> [Ride] { throw TestFailure() }
    func getPartyDetail(partyId: Int64) async throws -> Ride { throw TestFailure() }
    func getPartyDetailWithVersion(partyId: Int64) async throws -> PartyDetail { throw TestFailure() }
    func findRealtimeCandidates(
        departureLat: Double,
        departureLng: Double,
        destinationLat: Double,
        destinationLng: Double
    ) async throws -> [MatchCandidate] { throw TestFailure() }
    func observePartyEvents(partyId: Int64) -> AsyncThrowingStream<PartyEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: TestFailure()) }
    }
    func createParty(request: NewParty) async throws -> Ride { throw TestFailure() }
    func joinParty(partyId: Int64) async throws -> PartyStatus { throw TestFailure() }
    func leaveParty(partyId: Int64) async throws { throw TestFailure() }
    func finishParty(partyId: Int64) async throws { throw TestFailure() }
    func confirmMeeting(partyId: Int64, departureAt: String) async throws { throw TestFailure() }
    func arriveAtDeparture(partyId: Int64, latitude: Double, longitude: Double) async throws { throw TestFailure() }
    func departParty(partyId: Int64) async throws { throw TestFailure() }
    func previewRoute(
        departureLat: Double,
        departureLng: Double,
        destinationLat: Double,
        destinationLng: Double
    ) async throws -> RouteEstimate { throw TestFailure() }
    func createReservation(request: NewReservation) async throws -> Ride { throw TestFailure() }
    func getReservations(from: String, to: String) async throws -> [Ride] { [] }
}

/// 조건이 설 때까지 기다린다 — 카운트다운은 조회를 기다리지 않고 다음 칸에 들어가므로, 시계를 민 뒤 나간 조회가
/// 끝나는 것은 따로 본다(원본은 `runCurrent` 가 같은 디스패처의 조회까지 돌린다).
@MainActor
private func eventually(
    _ what: Comment,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async {
    for _ in 0..<2_000 {
        if condition() { return }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("시간 안에 일어나지 않았다: \(what)", sourceLocation: sourceLocation)
}
