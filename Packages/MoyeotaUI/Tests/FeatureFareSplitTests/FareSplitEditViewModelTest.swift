import Foundation
import MoyeotaDomain
import Testing
@testable import FeatureFareSplit

/// 40 정산 시작·수정 뷰모델 — **무엇을 보내고, 실패하면 적은 값을 어떻게 남기는가.**
///
/// 409 두 가지(`FARE_SPLIT_ALREADY_EXISTS`·`FARE_SPLIT_ALREADY_STARTED`)는 사용자가 금액을 **다 채운 뒤에**
/// 온다. 화면을 닫거나 입력을 비우면 그 입력이 통째로 사라진다 — 여기서 그 두 갈래를 값으로 못 박는다.
@MainActor
@Suite struct FareSplitEditViewModelTest {

    private func startViewModel(_ repository: RecordingFareSplitRepository) async -> FareSplitEditViewModel {
        let vm = FareSplitEditViewModel(repository: repository, loadRide: { _ in ride() }, partyId: 42, mode: .start)
        await vm.loadTask?.value
        return vm
    }

    private func editing(_ vm: FareSplitEditViewModel) -> FareSplitEditViewModel.Editing? {
        if case .editing(let editing) = vm.uiState { return editing }
        return nil
    }

    private func fill(_ vm: FareSplitEditViewModel) {
        vm.onFareChange("18700")
        vm.onBankSelect(.kakao)
        vm.onAccountChange("3333-01-2345678")
    }

    @Test("다 채운 시작 폼은 한 번 보내고 저장 신호를 올린다")
    func startSubmits() async throws {
        let repository = RecordingFareSplitRepository(detail: detail())
        let vm = await startViewModel(repository)
        fill(vm)

        vm.submit()
        await vm.submitTask?.value

        #expect(repository.calls == ["start"])
        #expect(vm.saved)
    }

    /// 버튼이 잠겨 있어도 뷰모델이 한 번 더 본다 — 잠금이 한 겹뿐이면 그 한 겹이 풀릴 때 조용히 400 이 된다.
    @Test("잠금 사유가 남아 있으면 서버를 부르지 않는다")
    func blockedNeverCalls() async {
        let repository = RecordingFareSplitRepository(detail: detail())
        let vm = await startViewModel(repository)
        vm.onFareChange("18700")

        vm.submit()
        await vm.submitTask?.value

        #expect(repository.calls.isEmpty)
        #expect(!vm.saved)
    }

    /// 그사이 누가 「보냈어요」를 눌렀다 — **보낼 길만 닫고 값은 남긴다.** 사용자가 그 숫자를 보며 채팅으로 이야기할 수 있다.
    @Test("이미 누가 보냈다는 409 면 적은 값을 남긴 채 읽기 전용이 된다")
    func alreadyStartedTurnsReadOnly() async throws {
        let repository = RecordingFareSplitRepository(detail: detail(), failure: failure("FARE_SPLIT_ALREADY_STARTED", httpStatus: 409))
        let vm = await startViewModel(repository)
        fill(vm)

        vm.submit()
        await vm.submitTask?.value

        let state = try #require(editing(vm))
        #expect(state.readOnlyReason != nil)
        #expect(state.errorMessage != nil)
        #expect(!state.submitting)
        #expect(state.draft.fareInput == "18700")
        #expect(state.draft.accountInput == "3333-01-2345678")
        #expect(!vm.saved)

        // 읽기 전용이면 입력이 들어가지 않는다 — 화면이 칸을 잠그지만 상태 쪽도 막는다.
        vm.onFareChange("1")
        #expect(editing(vm)?.draft.fareInput == "18700")
    }

    /// 이미 있는 정산 — 서버가 「GET 으로 본다」라고 적어 둔 복구 가능한 실패다. 저절로 화면을 바꾸지 않고
    /// 「지금 있는 정산 보기」를 준다(적은 값이 저장되지 않았다는 사실을 사용자가 알아야 한다).
    @Test("이미 정산이 있다는 409 면 지금 있는 정산으로 갈 길을 준다")
    func alreadyExistsOffersExisting() async throws {
        let repository = RecordingFareSplitRepository(detail: detail(), failure: failure("FARE_SPLIT_ALREADY_EXISTS", httpStatus: 409))
        let vm = await startViewModel(repository)
        fill(vm)

        vm.submit()
        await vm.submitTask?.value

        let state = try #require(editing(vm))
        #expect(state.existingFound)
        #expect(state.readOnlyReason == nil)
        #expect(state.draft.fareInput == "18700")
        #expect(!vm.saved)
    }

    /// 서버가 거절한 이유를 고치는 중인데 그 문구가 남아 있으면 **방금 고친 것이 또 거절된 것처럼** 보인다.
    @Test("값을 고치면 서버 실패 문구를 지운다")
    func editingClearsServerError() async throws {
        let repository = RecordingFareSplitRepository(detail: detail(), failure: failure("INVALID_ACCOUNT_NUMBER", httpStatus: 400))
        let vm = await startViewModel(repository)
        fill(vm)
        vm.submit()
        await vm.submitTask?.value
        #expect(editing(vm)?.errorMessage != nil)

        vm.onAccountChange("3333-01-2345679")

        #expect(editing(vm)?.errorMessage == nil)
    }

    /// 고치려고 왔는데 정산이 사라졌다(= 아무도 시작하지 않았다). 빈 폼을 그리지 않는다 — 수정 폼은
    /// 기존 값을 전제로 만들어졌고, 시작은 39 를 거쳐야 한다.
    @Test("수정하러 왔는데 정산이 없으면 빈 폼 대신 막힘을 보여 준다")
    func editWithoutFareSplitIsBlocked() async {
        let repository = RecordingFareSplitRepository(detail: nil)
        let vm = FareSplitEditViewModel(
            repository: repository,
            loadRide: { _ in
                Issue.record("수정 폼은 방 상세를 읽지 않는다")
                throw FakeFailure()
            },
            partyId: 42,
            mode: .edit
        )
        await vm.loadTask?.value

        #expect(vm.uiState == .blocked(message: "이 방에는 택시비 정산이 없어요", recoverable: true))
    }

    @Test("수정 폼은 고친 값을 PATCH 로 보낸다")
    func editSubmitsPatch() async {
        let repository = RecordingFareSplitRepository(detail: detail())
        let vm = FareSplitEditViewModel(repository: repository, loadRide: { _ in ride() }, partyId: 42, mode: .edit)
        await vm.loadTask?.value

        vm.onAccountChange("1002-123-456789")
        vm.submit()
        await vm.submitTask?.value

        #expect(repository.calls == ["get", "edit"])
        #expect(vm.saved)
    }
}
