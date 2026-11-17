import Foundation
import MoyeotaDomain
import Testing
@testable import FeatureFareSplit

struct FakeFailure: Error {}

/// 테스트가 열어 줄 때까지 호출을 붙잡아 둔다 — 「요청이 날아간 상태」를 재현한다(FeatureAuthTests 의 `Gate` 와 같다).
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

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
            let current = waiters
            waiters = []
            return current
        }
        pending.forEach { $0.resume() }
    }
}

/// 조건이 참이 될 때까지 기다린다. 저장소 호출은 메인 액터 밖에서 돌므로 「요청이 저장소에 닿았다」를
/// 태스크 손잡이로는 기다릴 수 없다 — 그 순간을 호출 기록으로 본다.
@MainActor
func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(3)) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}

/// 호출을 **순서대로** 적어 두는 저장소. 「불렀는가」가 아니라 「**언제** 불렀는가」를 보기
/// 때문이다 — 쓰기 전에 읽은 한 번과 쓰기 **뒤에** 읽은 한 번을 구분하지 못하면 재조회 테스트는
/// 재조회가 없어도 통과한다.
///
/// 조회(`getFareSplit`·`getMyFareSplits`)는 **몇 번째 호출인지**로 붙잡거나 다른 값을 돌려줄 수 있다 —
/// 「먼저 보낸 요청이 늦게 도착한다」를 재현하는 자리다.
final class RecordingFareSplitRepository: FareSplitRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var currentDetail: FareSplitDetail?
    private let failure: FareSplitException?

    private var getCount = 0
    private var getGates: [Int: Gate] = [:]
    private var getResponses: [Int: FareSplitDetail?] = [:]

    private var listCount = 0
    private var listGates: [Int: Gate] = [:]
    private var listResponses: [Int: Result<[MyFareSplit], FakeFailure>] = [:]

    init(detail: FareSplitDetail? = FeatureFareSplitTests.detail(role: .sender), failure: FareSplitException? = nil) {
        self.currentDetail = detail
        self.failure = failure
    }

    var calls: [String] { lock.withLock { recorded } }

    /// 다음 조회부터 돌려줄 상세 — 「쓰기 뒤에 서버가 바뀌었다」를 흉내 낸다.
    func setDetail(_ detail: FareSplitDetail?) { lock.withLock { currentDetail = detail } }

    /// `index` 번째(0부터) `getFareSplit` 을 문이 열릴 때까지 붙잡는다.
    func holdGet(_ index: Int, on gate: Gate) { lock.withLock { getGates[index] = gate } }

    /// `index` 번째 `getFareSplit` 이 돌려줄 값. 지정하지 않으면 그때의 `setDetail` 값이다.
    func respondGet(_ index: Int, with detail: FareSplitDetail?) { lock.withLock { getResponses[index] = .some(detail) } }

    func holdList(_ index: Int, on gate: Gate) { lock.withLock { listGates[index] = gate } }

    func respondList(_ index: Int, with result: Result<[MyFareSplit], FakeFailure>) {
        lock.withLock { listResponses[index] = result }
    }

    private func record(_ call: String) { lock.withLock { recorded.append(call) } }

    func startFareSplit(partyId: Int64, draft: FareSplitDraft) async throws -> FareSplitDetail {
        record("start")
        if let failure { throw failure }
        guard let detail = lock.withLock({ currentDetail }) else { throw FakeFailure() }
        return detail
    }

    func getFareSplit(partyId: Int64) async throws -> FareSplitDetail? {
        let (index, gate) = lock.withLock { () -> (Int, Gate?) in
            let index = getCount
            getCount += 1
            recorded.append("get")
            return (index, getGates[index])
        }
        if let gate { await gate.wait() }
        return lock.withLock { getResponses[index] ?? currentDetail }
    }

    func editFareSplit(partyId: Int64, draft: FareSplitDraft) async throws -> FareSplitDetail {
        record("edit")
        if let failure { throw failure }
        guard let detail = lock.withLock({ currentDetail }) else { throw FakeFailure() }
        return detail
    }

    func markSent(partyId: Int64) async throws {
        record("markSent")
        if let failure { throw failure }
    }

    func confirmReceived(partyId: Int64, senderPublicId: String) async throws {
        record("confirmReceived(\(senderPublicId))")
        if let failure { throw failure }
    }

    func markNotReceived(partyId: Int64, senderPublicId: String) async throws {
        record("markNotReceived(\(senderPublicId))")
        if let failure { throw failure }
    }

    func getMyFareSplits(status: TransferStatus) async throws -> [MyFareSplit] {
        let (index, gate) = lock.withLock { () -> (Int, Gate?) in
            let index = listCount
            listCount += 1
            recorded.append("myList")
            return (index, listGates[index])
        }
        if let gate { await gate.wait() }
        let result = lock.withLock { listResponses[index] } ?? .success([])
        return try result.get()
    }
}
