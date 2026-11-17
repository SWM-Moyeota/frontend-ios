import Foundation
import MoyeotaDomain
import Testing
@testable import FeatureFareSplit

/// **본문 없는 204 뒤에 상세를 다시 읽는가** — 이 작업에서 가장 비싼 불변식이다.
///
/// ### 왜 뷰모델을 직접 돌려 보는가 ★
/// 「보냈어요」·「받았어요」·「아직 안 들어왔어요」는 **응답 본문이 없다.** 즉 서버가 무엇을 바꿨는지
/// 앱이 알 길이 없고, 한 행만 낙관적으로 고치면 **마지막 확인이 정산 전체를 닫는 것**(COMPLETED +
/// 계좌번호 삭제)을 놓친다. 그러면 닫힌 정산에 계좌번호가 남아 보이고 「받았어요」가 그대로 떠 있다.
///
/// 그 결함은 **화면으로도, 순수 함수 테스트로도 보이지 않는다.** 재조회를 빼도 화면은 멀쩡히
/// 그려지고(`transferActionsOf` 는 받은 상세대로 정확히 판정한다), 다만 **그 상세가 과거**다.
/// 그래서 「호출 순서」를 값으로 못 박는 테스트가 따로 필요하다.
///
/// 화면은 그리지 않는다. 원본 테스트 디스패처의 `advanceUntilIdle` 자리는 뷰모델의 태스크 손잡이
/// (`loadTask`·`mutationTask`)가 맡는다 — 쓰기 태스크는 **재조회가 화면에 쓰일 때까지** 끝나지 않으므로
/// 그것 하나를 기다리면 「쓰기 + 재조회」가 다 끝난 상태다.
@MainActor
@Suite struct FareSplitMutationReloadTest {

    /// 방 상세 조회. 뷰모델이 **이 한 가지만** 받으므로(`loadRide`) 가짜도 클로저 하나다.
    ///
    /// 기본값은 **기록한다**: 정산 상세가 있는 경우에는 방을 읽을 이유가 없고, 읽는다면 그건
    /// 요청이 하나 늘어난 결함이다(끝난 방 카드마다 붙는다).
    private static let forbiddenRideLoad: @Sendable (Int64) async throws -> Ride = { _ in
        Issue.record("정산 상세가 있는 경우에는 방 상세를 읽지 않아야 한다")
        throw FakeFailure()
    }

    private func viewModel(_ repository: RecordingFareSplitRepository) async -> FareSplitDetailViewModel {
        let vm = FareSplitDetailViewModel(repository: repository, loadRide: Self.forbiddenRideLoad, partyId: 42)
        await vm.loadTask?.value
        return vm
    }

    // ─────────────────── 성공 뒤 재조회 ───────────────────

    /// 「보냈어요」가 성공하면 **그 뒤에** 상세를 다시 읽는다. 홈 배너도 함께 낡지만 그쪽은 홈이
    /// 복귀하며 스스로 읽는다(`FareSplitBannerViewModel.onScreenStart`).
    @Test("보냈어요가 성공하면 그 뒤에 상세를 다시 읽는다")
    func markSentReloads() async {
        let repository = RecordingFareSplitRepository()
        let vm = await viewModel(repository)

        vm.markSent()
        await vm.mutationTask?.value

        #expect(repository.calls == ["get", "markSent", "get"])
    }

    /// 마지막 확인이 정산 전체를 닫는다 — 재조회가 없으면 지워진 계좌번호가 화면에 남는다.
    @Test("받았어요가 성공하면 그 뒤에 상세를 다시 읽는다")
    func confirmReceivedReloads() async {
        let repository = RecordingFareSplitRepository(detail: detail())
        let vm = await viewModel(repository)

        vm.confirmReceived(senderPublicId: SENDER_A)
        await vm.mutationTask?.value

        #expect(repository.calls == ["get", "confirmReceived(\(SENDER_A))", "get"])
    }

    @Test("못 받았어요가 성공하면 그 뒤에 상세를 다시 읽는다")
    func markNotReceivedReloads() async {
        let repository = RecordingFareSplitRepository(detail: detail())
        let vm = await viewModel(repository)

        vm.markNotReceived(senderPublicId: SENDER_A)
        await vm.mutationTask?.value

        #expect(repository.calls == ["get", "markNotReceived(\(SENDER_A))", "get"])
    }

    // ─────────────────── 실패 뒤 처리 ───────────────────

    /// 「낡았다」는 신호는 문구와 **함께** 재조회한다 — 어긋난 화면 위에서 다음 동작을 하면 같은
    /// 실패가 되풀이되거나 이미 지워진 계좌번호를 유효한 것처럼 보여 준다.
    @Test("상세가 낡았다는 실패에도 다시 읽는다")
    func staleFailureReloads() async {
        let repository = RecordingFareSplitRepository(detail: detail(), failure: failure("FARE_SPLIT_CLOSED", httpStatus: 409))
        let vm = await viewModel(repository)

        vm.confirmReceived(senderPublicId: SENDER_A)
        await vm.mutationTask?.value

        #expect(repository.calls == ["get", "confirmReceived(\(SENDER_A))", "get"])
        #expect(vm.actionError != nil)
    }

    /// 입력 실수는 상세가 낡았다는 뜻이 아니다 — 쓸데없는 재조회로 화면을 흔들지 않는다.
    @Test("입력 실수 실패에는 다시 읽지 않는다")
    func inputMistakeDoesNotReload() async {
        let repository = RecordingFareSplitRepository(detail: detail(), failure: failure("INVALID_REQUEST", httpStatus: 400))
        let vm = await viewModel(repository)

        vm.confirmReceived(senderPublicId: SENDER_A)
        await vm.mutationTask?.value

        #expect(repository.calls == ["get", "confirmReceived(\(SENDER_A))"])
        #expect(!vm.actionInProgress)
    }

    /// 서버가 식별하지 못한 행은 **부를 publicId 가 없다** — 지어내면 404
    /// `FARE_SPLIT_TRANSFER_NOT_FOUND` 다. 화면이 버튼을 잠그지만(`transferActionsOf`) 뷰모델도
    /// 한 번 더 막는다(잠금이 한 겹뿐이면 그 한 겹이 풀릴 때 조용히 404 가 된다).
    @Test("publicId 가 비어 있으면 서버를 부르지 않는다")
    func emptyPublicIdNeverCalls() async {
        let repository = RecordingFareSplitRepository(detail: detail())
        let vm = await viewModel(repository)

        vm.confirmReceived(senderPublicId: "")
        vm.markNotReceived(senderPublicId: "")
        await vm.mutationTask?.value

        #expect(repository.calls == ["get"])
        #expect(!vm.actionInProgress)
    }

    /// 두 번 눌린 「받았어요」가 각자 재조회를 걸면 **늦게 끝난 쪽의 낡은 응답이 화면을 되돌린다.**
    /// 그래서 쓰기는 하나만 돈다.
    @Test("쓰기가 도는 중에는 두 번째 호출이 나가지 않는다")
    func secondTapIgnored() async {
        let repository = RecordingFareSplitRepository(detail: detail())
        let vm = await viewModel(repository)

        vm.confirmReceived(senderPublicId: SENDER_A)
        let first = vm.mutationTask
        vm.confirmReceived(senderPublicId: SENDER_B)
        await first?.value
        await vm.mutationTask?.value

        #expect(repository.calls == ["get", "confirmReceived(\(SENDER_A))", "get"])
    }

    // ─────────────────── 재조회가 끝나야 버튼이 열린다 (iOS, 리뷰 반영) ───────────────────

    /// 원본은 쓰기가 끝나면 **재조회를 걸기만 하고** 바쁨 표시를 내렸다 — 그 사이 버튼이 **낡은 상세 위에서**
    /// 다시 열려, 방금 확인한 행의 「받았어요」를 한 번 더 누를 수 있었다. 여기서는 재조회 결과가 화면에 쓰인
    /// **뒤에야** 내려간다.
    @Test("재조회가 화면에 쓰이기 전까지는 버튼이 잠겨 있다")
    func busyUntilFreshDetail() async {
        let repository = RecordingFareSplitRepository(detail: detail())
        let vm = await viewModel(repository)
        let reloadGate = Gate()
        repository.holdGet(1, on: reloadGate)

        vm.confirmReceived(senderPublicId: SENDER_A)
        #expect(vm.actionInProgress)
        #expect(await waitUntil { repository.calls == ["get", "confirmReceived(\(SENDER_A))", "get"] })

        // 쓰기는 끝났지만 재조회가 아직이다 — 버튼은 여전히 잠겨 있어야 한다.
        #expect(vm.actionInProgress)

        let fresh = detail(transfers: [
            transfer(SENDER_A, "동승자A", 6_233, status: .confirmed),
            transfer(SENDER_B, "동승자B", 6_233),
        ])
        repository.setDetail(fresh)
        reloadGate.open()
        await vm.mutationTask?.value

        #expect(!vm.actionInProgress)
        #expect(vm.uiState == .ready(fresh))
    }

    /// 재조회를 기다리는 사이 **더 새 조회**가 걸렸다(화면 복귀). 버튼은 그 새 조회까지 기다린다 —
    /// 앞의 것이 취소돼 화면에 쓰이지 않았는데 버튼만 열리면, 열린 순간의 화면이 다시 낡은 상세다.
    @Test("재조회 도중 더 새 조회가 걸리면 그것까지 기다린다")
    func busyWaitsForNewerLoad() async {
        let repository = RecordingFareSplitRepository(detail: detail())
        let vm = await viewModel(repository)
        let reloadGate = Gate()
        let returnGate = Gate()
        repository.holdGet(1, on: reloadGate)
        repository.holdGet(2, on: returnGate)

        vm.markNotReceived(senderPublicId: SENDER_A)
        #expect(await waitUntil { repository.calls.count == 3 })

        vm.onScreenStart()
        #expect(await waitUntil { repository.calls.count == 4 })

        // 밀려난 재조회가 먼저 돌아온다 — 화면에 쓰이지 않고, 버튼도 아직 잠겨 있다.
        repository.respondGet(1, with: detail(totalFare: 1))
        reloadGate.open()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(vm.actionInProgress)
        #expect(vm.uiState == .ready(detail()))

        let newest = detail(totalFare: 20_000)
        repository.respondGet(2, with: newest)
        returnGate.open()
        await vm.mutationTask?.value

        #expect(!vm.actionInProgress)
        #expect(vm.uiState == .ready(newest))
    }

    // ─────────────────── 조회 ───────────────────

    /// 조회는 **늘 하나만** 돈다. 먼저 보낸 느린 조회가 나중에 도착해도 더 새 결과를 덮지 않는다.
    @Test("먼저 보낸 느린 조회가 늦게 와도 새 결과를 덮지 않는다")
    func latestLoadWins() async {
        let repository = RecordingFareSplitRepository(detail: detail())
        let slowGate = Gate()
        repository.holdGet(0, on: slowGate)
        repository.respondGet(0, with: detail(totalFare: 1))

        let vm = FareSplitDetailViewModel(repository: repository, loadRide: Self.forbiddenRideLoad, partyId: 42)
        let slow = vm.loadTask
        #expect(await waitUntil { repository.calls.count == 1 })

        let newest = detail(totalFare: 20_000)
        repository.respondGet(1, with: newest)
        vm.refresh()
        await vm.loadTask?.value
        #expect(vm.uiState == .ready(newest))

        slowGate.open()
        await slow?.value
        #expect(vm.uiState == .ready(newest))
    }

    /// 정산이 없으면 **오류가 아니다** — 「시작할 수 있는가」를 방 상세로 한 번 더 묻는다.
    @Test("정산이 없으면 방 상세로 시작 가능 여부를 묻는다")
    func absentAsksRide() async {
        let rides = RideCalls()
        let repository = RecordingFareSplitRepository(detail: nil)
        let vm = FareSplitDetailViewModel(
            repository: repository,
            loadRide: { id in
                rides.append(id)
                return ride()
            },
            partyId: 42
        )
        await vm.loadTask?.value

        #expect(rides.ids == [42])
        #expect(vm.uiState == .absent(canStart: true, blockedReason: nil), "방장 + 도착 + 2명이면 시작할 수 있다")
    }

    /// 방 상세 조회가 실패하면 **단정하지 않는다** — `canStart = false` 에 이유 nil 이다.
    /// 실패를 「당신은 시작할 수 없다」로 읽으면 방장이 자기 방을 정산하지 못하는 막다른 화면이 된다.
    @Test("방 상세를 못 읽으면 시작할 수 없다고 단정하지 않는다")
    func rideFailureIsNotAVerdict() async {
        let repository = RecordingFareSplitRepository(detail: nil)
        let vm = FareSplitDetailViewModel(repository: repository, loadRide: { _ in throw FakeFailure() }, partyId: 42)
        await vm.loadTask?.value

        #expect(vm.uiState == .absent(canStart: false, blockedReason: nil))
    }

    /// 쓰기 뒤의 재조회가 한 번 실패했다고 **보던 금액·계좌를 빼앗지 않는다.**
    @Test("재조회가 실패해도 보던 상세를 지우지 않는다")
    func reloadFailureKeepsDetail() async {
        let repository = ThrowingGetRepository(detail: detail())
        let vm = FareSplitDetailViewModel(repository: repository, loadRide: Self.forbiddenRideLoad, partyId: 42)
        await vm.loadTask?.value
        repository.failGets()

        vm.confirmReceived(senderPublicId: SENDER_A)
        await vm.mutationTask?.value

        #expect(vm.uiState == .ready(detail()))
        #expect(!vm.actionInProgress)
    }
}

private final class RideCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int64] = []
    var ids: [Int64] { lock.withLock { recorded } }
    func append(_ id: Int64) { lock.withLock { recorded.append(id) } }
}

/// 첫 조회 뒤로는 조회가 전부 실패하는 저장소.
private final class ThrowingGetRepository: FareSplitRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let detail: FareSplitDetail
    private var failing = false

    init(detail: FareSplitDetail) { self.detail = detail }

    func failGets() { lock.withLock { failing = true } }

    func getFareSplit(partyId: Int64) async throws -> FareSplitDetail? {
        if lock.withLock({ failing }) { throw failure(nil, httpStatus: nil, isNetwork: true) }
        return detail
    }

    func startFareSplit(partyId: Int64, draft: FareSplitDraft) async throws -> FareSplitDetail { throw FakeFailure() }
    func editFareSplit(partyId: Int64, draft: FareSplitDraft) async throws -> FareSplitDetail { throw FakeFailure() }
    func markSent(partyId: Int64) async throws {}
    func confirmReceived(partyId: Int64, senderPublicId: String) async throws {}
    func markNotReceived(partyId: Int64, senderPublicId: String) async throws {}
    func getMyFareSplits(status: TransferStatus) async throws -> [MyFareSplit] { [] }
}
