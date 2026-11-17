@testable import FeatureExplore
import Foundation
import Testing

/// 17 탐색의 조회가 **화면이 보일 때만** 도는지 — 갱신 시계(`ExploreRefreshCycle`)의 문.
///
/// 탐색은 하단탭이라 21 매칭 대기·20 합류 확인·채팅이 위에 올라와도 뷰모델이 살아 있고,
/// `ViewModelScope` 는 화면이 보이는지 보지 않는다. 그래서 게이트가 없으면
/// 다른 화면에 머무는 내내 `GET /matching/rooms?swLat=…` 가 나갔다
/// (QA D-1: 4초 주기 시절 21 체류 135초에 34회). 화면에는 아무 증상이 없어 **로그/프록시로만 드러난다** —
/// 그래서 시계를 직접 돌려 여기서 고정한다.
///
/// 함께 지켜야 하는 것도 같이 본다.
/// - **돌아오면 즉시 1회**, 카운트다운은 15부터 새로: 복귀 후 주기를 기다리면 이미 사라진 방의 「합류」를 누르게 된다
/// - **팬·줌 디바운스 유지**: 중간 범위마다 서버를 때리던 것을 막는 기존 동작을 게이트가 지우지 않는다
/// - **물어볼 것이 없으면 시계도 돌지 않는다**: 실시간 모드에서 예약 시계가 1초마다 깨어날 이유가 없다
///
/// 원본은 `backgroundScope` 위의 시계를 가상 시간으로 돌린다. 여기서는 `VirtualClock` 을 시계의 `sleep` 으로 넣는다.
@MainActor
@Suite(.serialized)
struct ExplorePollGateTest {
    /// 읽은 입력을 차례로 적는 시계 하나와 그 가상 시계.
    private func makeCycle() -> (ExploreRefreshCycle<String>, ReadLog, VirtualClock) {
        let clock = VirtualClock()
        let log = ReadLog()
        let cycle = ExploreRefreshCycle<String>(
            sleep: { try await clock.sleep($0) },
            load: { log.reads.append($0) },
            onUi: { log.ui = $0 }
        )
        return (cycle, log, clock)
    }

    @Test("화면이 보이지 않으면 어떤 입력도 읽지 않는다")
    func hiddenNeverReads() async {
        let (cycle, log, clock) = makeCycle()
        // 21·20·채팅이 위에 올라온 동안, 그리고 앱이 백그라운드인 동안의 모든 입구
        for (index, timing) in ExploreLoadTiming.allCases.enumerated() {
            #expect(cycle.update("범위\(index)", timing: timing) == nil)
        }
        #expect(cycle.refreshNow() == nil)
        #expect(cycle.retry() == nil)
        await clock.advance(by: 120_000)

        #expect(log.reads.isEmpty)
    }

    @Test("보이기 시작하면 마지막 입력을 기다리지 않고 바로 읽는다")
    func startReadsLatestImmediately() async {
        let (cycle, log, clock) = makeCycle()
        cycle.update("기준 범위", timing: .now)
        cycle.update("움직인 범위", timing: .debounced) // 가려진 동안 들어온 범위도
        await cycle.setVisible(true)?.value
        await clock.runCurrent()

        #expect(log.reads == ["움직인 범위"], "디바운스 없이 마지막 입력으로")
        #expect(log.ui == ExploreRefreshUi(secondsLeft: 15))
        cycle.setVisible(false)
    }

    @Test("가려지면 멈추고 돌아오면 즉시 읽고 15부터 센다")
    func hiddenStopsAndReturnRestarts() async {
        let (cycle, log, clock) = makeCycle()
        cycle.update("범위", timing: .now)
        await cycle.setVisible(true)?.value
        await clock.advance(by: 7_000)

        cycle.setVisible(false)
        await clock.advance(by: 120_000)
        #expect(log.reads.count == 1, "가려진 동안 0회")

        await cycle.setVisible(true)?.value
        await clock.runCurrent()
        #expect(log.reads.count == 2)
        #expect(log.ui?.secondsLeft == 15, "남은 8초를 이어 세지 않는다")
        cycle.setVisible(false)
    }

    @Test("카메라를 움직인 새 범위는 디바운스 뒤에 읽는다")
    func movedBoundsAreDebounced() async {
        let (cycle, log, clock) = makeCycle()
        cycle.update("앞 범위", timing: .now)
        await cycle.setVisible(true)?.value
        await clock.runCurrent()

        cycle.update("중간 범위", timing: .debounced)
        await clock.advance(by: 200)
        cycle.update("새 범위", timing: .debounced) // 팬·줌 연타
        await clock.advance(by: BOUNDS_DEBOUNCE_MS - 1)
        #expect(log.reads == ["앞 범위"])
        await clock.advance(by: 1)
        await eventually("새 범위를 읽는다") { log.reads.count == 2 }

        #expect(log.reads == ["앞 범위", "새 범위"], "중간 범위는 건너뛴다")
        cycle.setVisible(false)
    }

    @Test("새 목록은 기다리지 않고 다음 자동 갱신 입력은 지금 읽지 않는다")
    func nowAndNextTick() async {
        let (cycle, log, clock) = makeCycle()
        cycle.update("11월 17일", timing: .now)
        await cycle.setVisible(true)?.value
        await clock.runCurrent()

        await cycle.update("11월 18일", timing: .now)?.value
        #expect(cycle.update("11월 18일 · 몇 m 옆", timing: .nextTick) == nil)
        await clock.advance(by: 14_999)
        #expect(log.reads == ["11월 17일", "11월 18일"])

        await clock.advance(by: 1)
        await eventually("0 에서 읽는다") { log.reads.count == 3 }
        #expect(log.reads.last == "11월 18일 · 몇 m 옆", "0 에서 최신 입력으로")
        cycle.setVisible(false)
    }

    @Test("물어볼 것이 없으면 시계도 읽기도 멈추고 생기면 15부터 새로 센다")
    func noQueryStopsClock() async {
        let (cycle, log, clock) = makeCycle()
        cycle.setVisible(true)
        await cycle.update("곧 출발", timing: .now)?.value
        await clock.advance(by: 6_000)

        cycle.update(nil, timing: .now) // 실시간 모드로
        await clock.advance(by: 60_000)
        #expect(log.reads.count == 1)
        #expect(cycle.refreshNow() == nil, "물어볼 것이 없으면 버튼도 아무 일도 하지 않는다")
        #expect(!cycle.isRunning)

        await cycle.update("곧 출발", timing: .now)?.value
        await clock.runCurrent()
        #expect(log.reads.count == 2)
        #expect(log.ui?.secondsLeft == 15)
        cycle.setVisible(false)
    }

    /// 실시간 목록의 지도 이동 — 보여 주던 목록이 있으면 디바운스, 없으면(첫 조회·에러 화면) 늦출 이득이 없다.
    @Test("실시간 지도 이동은 목록이 있으면 디바운스하고 없으면 바로 읽는다")
    func nearbyTiming() {
        #expect(nearbyLoadTiming(listShown: true) == .debounced)
        #expect(nearbyLoadTiming(listShown: false) == .now)
    }
}

@MainActor
private final class ReadLog {
    var reads: [String] = []
    var ui: ExploreRefreshUi?
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
