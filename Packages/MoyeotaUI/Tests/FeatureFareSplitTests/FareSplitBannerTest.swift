import Foundation
import MoyeotaDomain
import Testing
@testable import FeatureFareSplit

/// 14 홈 「아직 보내지 않은 택시비」 배너의 조회 시점 (Android PR #106 리뷰 반영).
///
/// 원본은 `init` 과 화면 시작이 **둘 다** 조회를 걸어 첫 진입에서 같은 요청이 두 번 나갔고, 응답 순서가
/// 바뀌면 먼저 보낸(더 낡은) 응답이 새 목록을 덮을 수 있었다. 여기서 못 박는 것은 셋이다:
/// 조회는 **화면 시작에서만**, 조회는 **늘 하나만**, 실패는 **보던 목록을 지우지 않는다.**
@MainActor
@Suite struct FareSplitBannerTest {

    @Test("뷰모델을 만들기만 해서는 조회하지 않는다")
    func initDoesNotFetch() async {
        let repository = RecordingFareSplitRepository()
        let vm = FareSplitBannerViewModel(repository: repository)
        try? await Task.sleep(for: .milliseconds(20))

        #expect(repository.calls.isEmpty)
        #expect(vm.refreshTask == nil)
        #expect(vm.items.isEmpty)
    }

    @Test("화면이 보이면 한 번 조회해 목록을 채운다")
    func screenStartFetchesOnce() async {
        let repository = RecordingFareSplitRepository()
        repository.respondList(0, with: .success([myFareSplit()]))
        let vm = FareSplitBannerViewModel(repository: repository)

        vm.onScreenStart()
        await vm.refreshTask?.value

        #expect(repository.calls == ["myList"])
        #expect(vm.items == [myFareSplit()])
    }

    /// 홈 복귀가 연달아 오면(탭 왕복) 조회가 겹친다. 먼저 보낸 느린 응답이 늦게 와도 새 목록을 덮지 않는다 —
    /// 덮으면 방금 「보냈어요」를 누른 정산이 배너에 되살아난다.
    @Test("먼저 보낸 느린 조회가 늦게 와도 새 목록을 덮지 않는다")
    func latestRefreshWins() async {
        let repository = RecordingFareSplitRepository()
        let slowGate = Gate()
        repository.holdList(0, on: slowGate)
        repository.respondList(0, with: .success([myFareSplit(partyId: 1), myFareSplit(partyId: 2)]))
        repository.respondList(1, with: .success([myFareSplit(partyId: 2)]))
        let vm = FareSplitBannerViewModel(repository: repository)

        vm.onScreenStart()
        let slow = vm.refreshTask
        #expect(await waitUntil { repository.calls.count == 1 })

        vm.onScreenStart()
        await vm.refreshTask?.value
        #expect(vm.items.map(\.partyId) == [2])

        slowGate.open()
        await slow?.value
        #expect(vm.items.map(\.partyId) == [2])
    }

    /// 배너는 **불러 주지 않은 알림**이라 실패를 말할 자리가 없다. 깜빡이며 사라지지 않게 보던 목록을 남긴다.
    @Test("조회가 실패해도 보던 목록을 지우지 않는다")
    func failureKeepsItems() async {
        let repository = RecordingFareSplitRepository()
        repository.respondList(0, with: .success([myFareSplit()]))
        repository.respondList(1, with: .failure(FakeFailure()))
        let vm = FareSplitBannerViewModel(repository: repository)

        vm.onScreenStart()
        await vm.refreshTask?.value
        vm.onScreenStart()
        await vm.refreshTask?.value

        #expect(repository.calls == ["myList", "myList"])
        #expect(vm.items == [myFareSplit()])
    }
}
