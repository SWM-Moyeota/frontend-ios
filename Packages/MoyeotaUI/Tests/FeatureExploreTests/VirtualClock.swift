import Foundation

// 원본에는 없는 파일이다 — 원본 테스트가 쓰는 `kotlinx-coroutines-test` 의 가상 시간을 대신한다
// (`ExploreRefreshTest`·`ReservationFinderViewModelTest` 가 함께 쓴다).

/// 가상 시계 — 원본 `kotlinx-coroutines-test` 의 가상 시간 자리. 뷰모델의 `sleep` 으로 넣는다.
///
/// `sleep` 은 「지금 + 기간」에 깨어날 대기로 적히고, 시험이 `advance(by:)` 로 시각을 밀 때 그 시각이 된 대기만
/// 순서대로 깨어난다. 대기 중인 태스크가 취소되면 곧바로 `CancellationError` 로 깨운다(원본 `delay` 와 같다).
final class VirtualClock: @unchecked Sendable {
    private struct Sleeper {
        let deadline: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var now = 0
    private var registrations = 0
    private var sleepers: [UUID: Sleeper] = [:]
    // 대기를 적기도 전에 취소가 먼저 온 것 — 적는 쪽이 보고 곧바로 깨운다
    private var cancelledEarly: Set<UUID> = []

    private var pendingCount: Int { lock.withLock { sleepers.count } }
    private var registrationCount: Int { lock.withLock { registrations } }

    func sleep(_ duration: Duration) async throws {
        let millis = Int(duration / .milliseconds(1))
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let cancelled: Bool = lock.withLock {
                    if cancelledEarly.remove(id) != nil { return true }
                    registrations += 1
                    sleepers[id] = Sleeper(deadline: now + millis, continuation: continuation)
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let sleeper: Sleeper? = lock.withLock {
                if let sleeper = sleepers.removeValue(forKey: id) { return sleeper }
                cancelledEarly.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// 원본 `advanceTimeBy(ms)` + `runCurrent()` — 시각을 `millis` 만큼 밀며 그 사이에 깨어날 대기를 시각 순서대로
    /// 깨우고, 깨운 일이 다음 대기에 들어서거나 더 할 일이 없을 때까지 돌린다.
    @MainActor
    func advance(by millis: Int) async {
        await runCurrent()
        let target = lock.withLock { now + millis }
        while true {
            let due: [CheckedContinuation<Void, any Error>]? = lock.withLock {
                guard let next = sleepers.values.map(\.deadline).min(), next <= target else { return nil }
                now = next
                let ready = sleepers.filter { $0.value.deadline <= next }
                for key in ready.keys { sleepers.removeValue(forKey: key) }
                return ready.values.map(\.continuation)
            }
            guard let due else { break }
            due.forEach { $0.resume() }
            await runCurrent()
        }
        lock.withLock { now = target }
    }

    /// 원본 `runCurrent()` — 지금 시각에 돌 수 있는 일을 다 돌린다.
    ///
    /// 실제 태스크라 「다 돌았다」를 직접 알 수 없다. 새 대기가 한동안 적히지 않으면 돌아온다 — 걸린 대기가 있으면
    /// 그 태스크는 이 시계만 기다리는 것이라 짧게, 없으면(조회가 문 앞에 매달림·흐름이 끝남) 넉넉히 본다.
    @MainActor
    func runCurrent() async {
        var last = registrationCount
        var quiet = 0
        for _ in 0..<2_000 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
            let current = registrationCount
            if current != last {
                last = current
                quiet = 0
                continue
            }
            quiet += 1
            if quiet >= (pendingCount > 0 ? 5 : 40) { return }
        }
    }
}
