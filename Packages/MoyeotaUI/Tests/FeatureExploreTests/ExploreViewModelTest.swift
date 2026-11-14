@testable import FeatureExplore
import Foundation
import MoyeotaDesignSystem
import MoyeotaDomain
import Testing

// 원본에는 없는 테스트다. 원본은 시계와 조회 칸(`ExploreRefreshCycle`)을 가상 시간으로만 시험하는데, iOS 는
// 그 태스크(끊기·취소 뒤 결과 버리기·실패 세기)를 직접 쓰므로 실제 태스크로 따르는지 여기서 본다.

private struct TestFailure: Error {}

private let bounds = MapBounds(swLat: 35.15, swLng: 129.05, neLat: 35.17, neLng: 129.07)
private let otherBounds = MapBounds(swLat: 36.15, swLng: 129.05, neLat: 36.17, neLng: 129.07)

private func party(_ id: String) -> Ride {
    Ride(
        id: id,
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

/// 시간을 시험이 쥔다. `advance` 를 부르기 전까지 뷰모델의 대기가 끝나지 않고, 취소되면 곧바로 던진다.
private final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var requested: [Duration] = []

    var requests: [Duration] { lock.withLock { requested } }
    var waitingCount: Int { lock.withLock { waiting.count } }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    requested.append(duration)
                    waiting[id] = continuation
                }
            }
        } onCancel: {
            lock.withLock { waiting.removeValue(forKey: id) }?.resume(throwing: CancellationError())
        }
    }

    func advance() {
        let released = lock.withLock {
            let current = waiting
            waiting = [:]
            return current
        }
        released.values.forEach { $0.resume() }
    }
}

/// 범위 조회만 쓴다. 나머지는 이 화면이 부르지 않으므로 부르면 던진다.
private final class FakeRideRepository: RideRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var queries: [MapBounds] = []
    private var results: [@Sendable () async throws -> [Ride]] = []

    var queried: [MapBounds] { lock.withLock { queries } }

    func enqueue(_ result: @escaping @Sendable () async throws -> [Ride]) {
        lock.withLock { results.append(result) }
    }

    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] {
        let next: (@Sendable () async throws -> [Ride])? = lock.withLock {
            queries.append(MapBounds(swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng))
            return results.isEmpty ? nil : results.removeFirst()
        }
        return try await next?() ?? []
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

    // 예약 방 — 이 테스트가 보는 동작에는 쓰이지 않는다.
    func createReservation(request: NewReservation) async throws -> Ride { throw TestFailure() }
    func getReservations(from: String, to: String) async throws -> [Ride] { [] }
    func getReservationsSoon(
        swLat: Double,
        swLng: Double,
        neLat: Double,
        neLng: Double
    ) async throws -> [Ride] { [] }
    func searchReservations(
        departureLat: Double,
        departureLng: Double,
        date: String,
        destination: ReservationDestination?
    ) async throws -> [ReservationSearchResult] { [] }
}

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

/// 15초 카운트다운을 끝까지 넘긴다 — 1초 대기가 걸릴 때마다 하나씩 풀어 준다(`countDownToNextRefresh`).
/// 이미 걸려 있는 첫 칸부터 센다.
@MainActor
private func finishCountdown(
    _ sleeper: ManualSleeper,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for tick in 1...REFRESH_COUNTDOWN_SECONDS {
        await eventually("카운트다운 \(tick)번째 칸", sourceLocation: sourceLocation) { sleeper.waitingCount == 1 }
        sleeper.advance()
    }
}

/// 일어나면 안 되는 일을 볼 때 쓴다. 태스크가 돌 기회를 충분히 준다.
@MainActor
private func settle() async {
    for _ in 0..<50 {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
@Suite(.serialized)
struct ExploreViewModelTest {
    private let repository = FakeRideRepository()
    private let sleeper = ManualSleeper()

    private func makeViewModel() -> ExploreViewModel {
        let sleeper = sleeper
        return ExploreViewModel(repository: repository, sleep: { try await sleeper.sleep($0) })
    }

    @Test("보이기 전에는 조회하지 않고 보이면 디바운스 없이 넓힌 범위로 조회한다")
    func queriesOnlyWhenVisible() async {
        let viewModel = makeViewModel()
        repository.enqueue { [party("1")] }

        viewModel.onInitialBounds(bounds)
        await settle()
        #expect(repository.queried.isEmpty)

        viewModel.onScreenStart()
        await eventually("첫 조회 결과") { viewModel.uiState == .success(parties: [party("1")]) }
        #expect(repository.queried == [bounds.expanded()])
        // 첫 대기는 디바운스가 아니라 다음 주기의 첫 칸(1초)이다
        await eventually("주기 대기") { sleeper.waitingCount == 1 }
        #expect(sleeper.requests == [.milliseconds(1_000)])
        viewModel.onScreenStop()
    }

    @Test("가려지면 폴링이 멈추고 돌아오면 그 자리에서 즉시 읽는다")
    func stopsWhenHiddenAndReloadsOnReturn() async {
        let viewModel = makeViewModel()
        viewModel.onScreenStart()
        viewModel.onInitialBounds(bounds)
        await eventually("첫 주기 대기") { sleeper.waitingCount == 1 }
        #expect(repository.queried.count == 1)

        viewModel.onScreenStop()
        await eventually("대기 취소") { sleeper.waitingCount == 0 }
        await settle()
        #expect(repository.queried.count == 1)

        viewModel.onScreenStart()
        await eventually("복귀 즉시 조회") { repository.queried.count == 2 }
        // 복귀에는 디바운스가 없다 — 대기 요청은 여전히 주기뿐이다
        await eventually("복귀 뒤 주기 대기") { sleeper.waitingCount == 1 }
        #expect(sleeper.requests == [.milliseconds(1_000), .milliseconds(1_000)])
        viewModel.onScreenStop()
    }

    /// 지도 이동은 카운트다운을 건드리지 않는다 — 디바운스 대기가 카운트다운 대기 **옆에** 하나 더 걸린다
    /// (예전에는 새 패스가 카운트다운을 끊고 디바운스 하나만 남았다).
    @Test("목록이 있을 때 새 범위는 디바운스 뒤에 읽고 카운트다운은 이어 센다")
    func newBoundsDebounce() async {
        let viewModel = makeViewModel()
        viewModel.onScreenStart()
        viewModel.onInitialBounds(bounds)
        await eventually("첫 목록") { viewModel.uiState == .success(parties: []) }
        await eventually("첫 주기 대기") { sleeper.waitingCount == 1 }

        viewModel.onVisibleBoundsChange(otherBounds)
        await eventually("디바운스 대기") {
            sleeper.waitingCount == 2 && sleeper.requests.last == .milliseconds(400)
        }
        #expect(repository.queried == [bounds.expanded()])

        sleeper.advance()
        await eventually("새 범위 조회") { repository.queried == [bounds.expanded(), otherBounds.expanded()] }
        // 카운트다운은 끊기지 않고 다음 칸을 기다린다
        await eventually("카운트다운 다음 칸") { sleeper.waitingCount == 1 }
        #expect(sleeper.requests.filter { $0 == .milliseconds(1_000) }.count == 2)
        viewModel.onScreenStop()
    }

    @Test("같은 범위가 다시 와도 재조회하지 않는다")
    func sameBoundsIgnored() async {
        let viewModel = makeViewModel()
        viewModel.onScreenStart()
        viewModel.onVisibleBoundsChange(bounds)
        await eventually("첫 주기 대기") { sleeper.waitingCount == 1 }

        viewModel.onVisibleBoundsChange(bounds)
        viewModel.onInitialBounds(otherBounds)
        await settle()
        #expect(repository.queried.count == 1)
        viewModel.onScreenStop()
    }

    @Test("첫 조회 실패는 에러 화면이고 다시 시도하면 기다리지 않고 복구된다")
    func firstFailureShowsErrorAndRetryRecovers() async {
        let viewModel = makeViewModel()
        repository.enqueue { throw TestFailure() }
        repository.enqueue { [party("1")] }
        viewModel.onScreenStart()
        viewModel.onInitialBounds(bounds)
        await eventually("에러 화면") { viewModel.uiState == .error(message: "동승 목록을 불러오지 못했어요") }

        viewModel.refresh()
        await eventually("복구") { viewModel.uiState == .success(parties: [party("1")]) }
        #expect(repository.queried.count == 2)
        #expect(!sleeper.requests.contains(.milliseconds(400)))
        viewModel.onScreenStop()
    }

    @Test("연속 두 번 실패하면 목록을 둔 채 낡음을 켜고 성공하면 끈다")
    func staleAfterTwoFailures() async {
        let viewModel = makeViewModel()
        repository.enqueue { [party("1")] }
        viewModel.onScreenStart()
        viewModel.onInitialBounds(bounds)
        await eventually("첫 목록") { viewModel.uiState == .success(parties: [party("1")]) }

        for attempt in 1...STALE_NOTICE_FAILURES {
            repository.enqueue { throw TestFailure() }
            await eventually("주기 대기 \(attempt)") { sleeper.waitingCount == 1 }
            #expect(viewModel.uiState == .success(parties: [party("1")], stale: false))
            await finishCountdown(sleeper)
            await eventually("실패 \(attempt) 처리") { repository.queried.count == attempt + 1 }
        }
        await eventually("낡음 표시") { viewModel.uiState == .success(parties: [party("1")], stale: true) }

        repository.enqueue { [party("2")] }
        await finishCountdown(sleeper)
        await eventually("성공이 낡음을 끈다") { viewModel.uiState == .success(parties: [party("2")], stale: false) }
        viewModel.onScreenStop()
    }

    @Test("취소된 앞 범위의 응답은 새 범위 결과를 덮지 않는다")
    func cancelledResultIsDropped() async {
        let viewModel = makeViewModel()
        // 취소를 무시하고 늦게 끝나는 응답 — `URLSession` 은 취소와 응답이 엇갈릴 수 있다
        let gate = AsyncStream<Void>.makeStream()
        repository.enqueue {
            for await _ in gate.stream { break }
            return [party("old")]
        }
        repository.enqueue { [party("new")] }

        viewModel.onScreenStart()
        viewModel.onVisibleBoundsChange(bounds)
        await eventually("앞 조회 시작") { repository.queried.count == 1 }

        // 목록이 아직 없어 새 범위는 디바운스 없이 바로 읽는다
        viewModel.onVisibleBoundsChange(otherBounds)
        await eventually("새 범위 결과") { viewModel.uiState == .success(parties: [party("new")]) }

        gate.continuation.yield(())
        await settle()
        #expect(viewModel.uiState == .success(parties: [party("new")]))
        viewModel.onScreenStop()
    }

    @Test("첫 조회 중 가려지면 에러로 바꾸지 않고 돌아와 다시 읽는다")
    func cancelledFirstLoadIsNotAnError() async {
        let viewModel = makeViewModel()
        repository.enqueue {
            try await Task.sleep(for: .seconds(60))
            return []
        }
        repository.enqueue { [party("1")] }
        viewModel.onScreenStart()
        viewModel.onInitialBounds(bounds)
        await eventually("첫 조회 시작") { repository.queried.count == 1 }

        viewModel.onScreenStop()
        await settle()
        #expect(viewModel.uiState == .loading)

        viewModel.onScreenStart()
        await eventually("복귀 조회") { viewModel.uiState == .success(parties: [party("1")]) }
        viewModel.onScreenStop()
    }

    @Test("첫 조회가 태스크 취소 없이 URLError(.cancelled) 로 끝나면 에러 화면이고 폴링이 이어져 복구된다")
    func uncancelledTransportCancelOnFirstLoad() async {
        let viewModel = makeViewModel()
        repository.enqueue { throw URLError(.cancelled) }
        repository.enqueue { [party("1")] }
        viewModel.onScreenStart()
        viewModel.onInitialBounds(bounds)

        await eventually("에러 화면") { viewModel.uiState == .error(message: "동승 목록을 불러오지 못했어요") }
        await eventually("주기 대기") { sleeper.waitingCount == 1 }
        #expect(sleeper.requests == [.milliseconds(1_000)])

        await finishCountdown(sleeper)
        await eventually("다음 주기가 복구한다") { viewModel.uiState == .success(parties: [party("1")]) }
        viewModel.onScreenStop()
    }

    @Test("목록이 있을 때 URLError(.cancelled) 는 목록을 두고 폴링을 이어 가며 실패로 세어 낡음을 켠다")
    func uncancelledTransportCancelKeepsPolling() async {
        let viewModel = makeViewModel()
        repository.enqueue { [party("1")] }
        viewModel.onScreenStart()
        viewModel.onInitialBounds(bounds)
        await eventually("첫 목록") { viewModel.uiState == .success(parties: [party("1")]) }
        await eventually("첫 주기 대기") { sleeper.waitingCount == 1 }

        // 복귀 즉시 조회(`load`)가 이 오류로 끝나는 경우 — 고치기 전에는 여기서 패스가 끝났다
        viewModel.onScreenStop()
        await eventually("대기 취소") { sleeper.waitingCount == 0 }
        repository.enqueue { throw URLError(.cancelled) }
        viewModel.onScreenStart()
        await eventually("복귀 조회") { repository.queried.count == 2 }
        await eventually("폴링이 이어진다") { sleeper.waitingCount == 1 }
        // 복귀 조회의 실패도 1회로 센다(`STALE_NOTICE_FAILURES` 설명) — 한 번으로는 알리지 않는다
        await eventually("복귀 조회가 끝난다") { !viewModel.refreshUi.refreshing }
        #expect(viewModel.uiState == .success(parties: [party("1")]))

        for attempt in 1..<STALE_NOTICE_FAILURES {
            repository.enqueue { throw URLError(.cancelled) }
            await finishCountdown(sleeper)
            await eventually("실패 \(attempt) 처리") { repository.queried.count == attempt + 2 }
        }
        await eventually("낡음 표시") { viewModel.uiState == .success(parties: [party("1")], stale: true) }
        viewModel.onScreenStop()
    }

    @Test("뷰모델이 살아 있으면 탭 복귀 때 목록을 덮지 않고 기준 범위를 무시한 채 마지막 범위로 바로 읽는다")
    func retainedViewModelSurvivesTabReturn() async {
        let viewModel = makeViewModel()
        repository.enqueue { [party("1")] }
        viewModel.onScreenStart()
        viewModel.onInitialBounds(bounds)
        await eventually("첫 목록") { viewModel.uiState == .success(parties: [party("1")]) }
        await eventually("첫 주기 대기") { sleeper.waitingCount == 1 }

        // 호스트가 뷰모델을 들고 있는 탭 전환 — 뷰만 없어졌다 다시 생긴다
        viewModel.onScreenStop()
        await eventually("대기 취소") { sleeper.waitingCount == 0 }
        let requestsBefore = sleeper.requests.count
        _ = ExploreRoute(viewModel: viewModel, finderViewModel: ReservationFinderViewModel(repository: repository))

        let gate = AsyncStream<Void>.makeStream()
        repository.enqueue {
            for await _ in gate.stream { break }
            return [party("2")]
        }
        viewModel.onScreenStart()
        viewModel.onInitialBounds(otherBounds)

        await eventually("복귀 조회") { repository.queried.count == 2 }
        #expect(repository.queried[1] == bounds.expanded())
        // 응답을 기다리는 동안 로딩으로 깜빡이지 않고, 복귀에는 디바운스도 없다(카운트다운은 15부터 새로 센다)
        #expect(viewModel.uiState == .success(parties: [party("1")]))
        #expect(!sleeper.requests[requestsBefore...].contains(.milliseconds(400)))

        gate.continuation.yield(())
        await eventually("새 결과로 덮는다") { viewModel.uiState == .success(parties: [party("2")]) }
        viewModel.onScreenStop()
    }

    @Test("시트 드래그는 첫 값에서 움직이지 않고 끌린 만큼 범위 안에서 높이를 바꾼다")
    func sheetDragTracksWithinRange() {
        var drag = SheetDragTracker()
        #expect(drag.height == nil)

        drag.track(y: 500, resting: 400, range: 96...700)
        #expect(drag.height == 400)
        drag.track(y: 450, resting: 400, range: 96...700)
        #expect(drag.height == 450)
        drag.track(y: 0, resting: 400, range: 96...700)
        #expect(drag.height == 700)
        drag.track(y: 2_000, resting: 400, range: 96...700)
        #expect(drag.height == 96)
    }

    @Test("드래그를 끝내면 놓은 높이를 돌려주고 비워져 앵커 이동을 막지 않으며 다음 드래그가 튀지 않는다")
    func sheetDragFinishClearsEverything() {
        var drag = SheetDragTracker()
        drag.track(y: 500, resting: 400, range: 96...700)
        drag.track(y: 450, resting: 400, range: 96...700)

        #expect(drag.finish(resting: 400) == 450)
        // 남아 있으면 시트 높이 계산에서 앞서 「⌃」·「지도 접기/펼치기」가 먹지 않는다
        #expect(drag.height == nil)
        // 남아 있던 직전 위치와의 차이로 계산되면 첫 값에서 시트가 튄다
        drag.track(y: 100, resting: 96, range: 96...700)
        #expect(drag.height == 96)
    }

    @Test("드래그가 없을 때 끝내면 지금 높이에서 정착한다")
    func sheetDragFinishWithoutDrag() {
        var drag = SheetDragTracker()
        #expect(drag.finish(resting: 321) == 321)
        #expect(drag.height == nil)
    }

    @Test("드래그가 취소되면 속도 없이 가까운 앵커로 정착한다")
    func cancelledDragSettlesToNearestAnchor() {
        let anchors: (ExploreSheetState) -> CGFloat = { exploreSheetAnchor($0, containerHeight: 700) }
        var drag = SheetDragTracker()
        drag.track(y: 500, resting: 400, range: 96...700)
        drag.track(y: 420, resting: 400, range: 96...700)

        // 앵커: peek 96 · half 400 · full 700. 480 은 half 쪽이 가깝다
        let from = drag.finish(resting: 400)
        #expect(from == 480)
        #expect(settleTarget(fromPx: from, velocity: 0, anchorPx: anchors) == .half)
    }

    @Test("뷰모델이 해제되면 폴링 태스크도 끝난다")
    func deinitStopsPolling() async {
        var viewModel: ExploreViewModel? = makeViewModel()
        weak let weakViewModel = viewModel
        viewModel?.onScreenStart()
        viewModel?.onInitialBounds(bounds)
        await eventually("첫 주기 대기") { sleeper.waitingCount == 1 }

        viewModel = nil
        await eventually("해제") { weakViewModel == nil }
        await eventually("대기 취소") { sleeper.waitingCount == 0 }
        #expect(repository.queried.count == 1)
    }

    @Test("드래그를 던지면 그 방향의 다음 앵커, 아니면 가까운 앵커로 정착한다")
    func settleTargetRules() {
        let anchors: (ExploreSheetState) -> CGFloat = { state in
            exploreSheetAnchor(state, containerHeight: 700)
        }
        // 앵커: hidden 28 · peek 96 · half 400 · full 700
        #expect(settleTarget(fromPx: 500, velocity: 0, anchorPx: anchors) == .half)
        #expect(settleTarget(fromPx: 600, velocity: 0, anchorPx: anchors) == .full)
        #expect(settleTarget(fromPx: 500, velocity: 401, anchorPx: anchors) == .half)
        #expect(settleTarget(fromPx: 500, velocity: -401, anchorPx: anchors) == .full)
        #expect(settleTarget(fromPx: 400, velocity: 401, anchorPx: anchors) == .peek)
        #expect(settleTarget(fromPx: 700, velocity: -401, anchorPx: anchors) == .full)
        // 접힘에서 더 내리면 손잡이만 남는다(14 홈과 같다). 손잡이만에서 올려 던지면 접힘으로 돌아온다
        #expect(settleTarget(fromPx: 96, velocity: 401, anchorPx: anchors) == .hidden)
        #expect(settleTarget(fromPx: 50, velocity: 0, anchorPx: anchors) == .hidden)
        #expect(settleTarget(fromPx: 28, velocity: 401, anchorPx: anchors) == .hidden)
        #expect(settleTarget(fromPx: 28, velocity: -401, anchorPx: anchors) == .peek)
    }

    @Test("지도 범위가 없을 때의 기준 범위는 기본 카메라 또는 내 위치 주변이다")
    func defaultBounds() {
        let fallback = defaultExploreBounds(center: nil)
        #expect(abs(fallback.swLat - (35.1578 - 0.006)) < 1e-9)
        #expect(abs(fallback.neLng - (129.0594 + 0.006)) < 1e-9)
    }
}
