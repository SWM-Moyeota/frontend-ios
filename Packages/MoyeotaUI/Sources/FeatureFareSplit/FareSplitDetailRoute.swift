import MoyeotaDesignSystem
import MoyeotaDomain
import Observation
import PresentationCore
import SwiftUI

/// 39 정산 상세의 상태·호출.
///
/// ### 본문 없는 204 셋 뒤에는 **반드시 재조회한다** ★★
/// 「보냈어요」·「받았어요」·「아직 안 들어왔어요」는 모두 **응답 본문이 없다.** 즉 서버가 무엇을
/// 바꿨는지 앱이 알 길이 없고, 한 행만 낙관적으로 고치면 두 가지를 놓친다:
///
/// | 놓치는 것 | 그래서 보이는 화면 |
/// |---|---|
/// | **마지막 확인이 정산 전체를 닫는다**(COMPLETED + 계좌번호 삭제) | 닫힌 정산에 계좌번호가 남아 보이고, 「받았어요」가 그대로 떠 있다 |
/// | 그사이 다른 사람이 누른 「보냈어요」 | 내 화면만 과거에 머문다 |
///
/// 그래서 모든 쓰기는 `runMutation` 한 곳을 지나고, **성공이든 「낡았다」는 실패든 상세를 다시
/// 읽는다.** 「이미 보냈습니다」 같은 문구는 만들지 않는다 — 멱등 204 는 「이미 그 상태였다」와
/// 「지금 바뀌었다」를 구분할 수 없다.
///
/// ### 재조회를 **기다린 뒤에** 버튼을 푼다 (Android PR #106 리뷰 반영) ★
/// 원본은 쓰기 뒤의 재조회를 띄워 놓고(fire-and-forget) 바로 `actionInProgress` 를 내렸다. 그 사이 버튼이 다시
/// 열려 **낡은 상세 위에서 두 번째 동작**을 누를 수 있었고(이미 닫힌 정산에 「받았어요」), 늦게 끝난 쪽의 낡은
/// 응답이 새 응답을 덮을 수도 있었다. 여기서는:
///
/// - 쓰기 태스크가 재조회를 **끝까지 기다린 뒤** `actionInProgress` 를 내린다 — 버튼이 다시 열리는 순간 화면은 이미 새 상세다.
/// - 조회는 **늘 하나만** 돈다(`loadTask`). 새 조회(화면 복귀·재시도·쓰기 뒤 재조회)는 앞의 것을 취소하고, 세대 번호가
///   맞지 않는 응답은 화면에 쓰지 않는다 — **마지막에 건 요청이 이긴다.** 쓰기는 기다리던 조회가 더 새 조회로
///   바뀌었으면 그 새 조회까지 기다린다.
///
/// ### 「받았어요」는 끝까지 멱등이 아니다 — 그 처리는 data 계층에 있다
/// 마지막 송금을 확인하면 정산이 닫히고 그다음부터는 409 `FARE_SPLIT_CLOSED` 가 온다(실측).
/// 데이터 계층이 그 409 를 성공으로 접으므로 이 뷰모델은 신경 쓰지 않는다 — 다만 **성공 뒤
/// 재조회**는 그래서 더 중요하다(그 호출이 정산 전체를 닫았을 수 있다).
///
/// ### 정산이 없는 것은 실패가 아니다
/// 저장소가 404 `FARE_SPLIT_NOT_FOUND` 를 **nil 로** 접어 준다 — 끝난 방의 정상 상태다. 그때는
/// 「시작할 수 있는가」를 방 상세로 한 번 더 묻는다(`UiState.absent`): 묻지 않으면 방장이 아닌
/// 사람에게 「정산 시작하기」가 떠서 403 `NOT_PARTY_HOST` 로만 끝난다.
///
/// 로그를 남기지 않는다 — 다루는 값에 계좌번호가 섞여 있다(`FareSplitActions.swift` 주석). 그래서 다른 화면들과
/// 달리 실패를 `Diagnostics` 로도 보내지 않는다.
@MainActor
@Observable
public final class FareSplitDetailViewModel {

    public enum UiState: Equatable, Sendable {
        case loading

        /// 이 방에 정산이 **아직 없다**. 오류가 아니다.
        ///
        /// - `canStart`: 내가 시작할 수 있는가(`startDraftGate` 가 판정한다).
        /// - `blockedReason`: 시작할 수 없는 이유. **nil 이면 「알 수 없다」**다(방 상세 조회 실패) —
        ///   그때는 단정하지 않고 다시 불러오게 한다.
        case absent(canStart: Bool, blockedReason: String?)

        case ready(FareSplitDetail)

        case error(message: String)
    }

    public private(set) var uiState: UiState = .loading

    /// 쓰기 호출이 도는 중. 세 버튼을 **함께** 잠근다 — 한 행을 누른 뒤 다른 행을 누르면 재조회가 겹친다.
    /// **재조회가 끝난 뒤에야** 내려간다(이 타입 주석의 「재조회를 기다린 뒤에」).
    public private(set) var actionInProgress = false

    public private(set) var actionError: String?

    @ObservationIgnored private let repository: any FareSplitRepository
    /// 방 상세를 읽는 **한 가지 일**만 받는다 — `RideRepository` 전체가 아니다.
    ///
    /// 이유가 둘이다.
    /// 1. **쓰는 것이 하나뿐이다.** 이 뷰모델이 방에서 필요한 것은 「도착을 누른 멤버가 누구인가」
    ///    (`getPartyDetail` → `Ride.fareSplitRiders`) 하나다. 저장소 전체를 받으면 의존이 실제보다 넓다고 말하게 된다.
    /// 2. **테스트가 큰 프로토콜을 흉내 내지 않아도 된다.** `RideRepository` 는 매칭·예약·SSE 까지 품은 큰
    ///    프로토콜이고 지금도 바뀌는 중이다. 전체를 구현한 가짜를 두면 **정산과 무관한 시그니처 변경마다 이 테스트가
    ///    깨진다** — 그러면 깨짐이 신호가 아니라 잡음이 된다.
    @ObservationIgnored private let loadRide: @Sendable (Int64) async throws -> Ride
    @ObservationIgnored private let partyId: Int64
    @ObservationIgnored private let scope = ViewModelScope()

    /// 지금 도는 조회 — **늘 하나다.** 테스트가 조회가 끝나기를 기다리는 손잡이이기도 하다.
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?
    /// 조회 세대. 새 조회를 걸 때마다 올리고, 응답은 자기 세대가 마지막일 때만 화면에 쓴다.
    @ObservationIgnored private var loadGeneration = 0
    /// 지금 도는 쓰기. 테스트가 「쓰기 + 재조회」가 끝나기를 기다리는 손잡이다.
    @ObservationIgnored private(set) var mutationTask: Task<Void, Never>?

    public init(
        repository: any FareSplitRepository,
        loadRide: @escaping @Sendable (Int64) async throws -> Ride,
        partyId: Int64
    ) {
        self.repository = repository
        self.loadRide = loadRide
        self.partyId = partyId
        load(showLoading: true)
    }

    /// 에러 화면의 「다시 시도」와 첫 진입이 같은 길을 쓴다.
    public func refresh() {
        load(showLoading: true)
    }

    /// 화면이 보이기 시작했다 — **40 수정 화면에서 돌아온 경우**가 이 길의 이유다.
    ///
    /// 수정은 상세를 돌려주지만 그 값은 수정 화면이 들고 있던 것이다. 여기서 다시 읽지 않으면
    /// 뒤로 돌아온 상세가 옛 금액을 보여 준다. 들고 있던 값은 지우지 않으므로(`showLoading: false`)
    /// 깜빡이지 않는다.
    ///
    /// 첫 진입 조회가 아직 도는 중이면 건너뛴다 — 진입 직후의 시작 신호가 같은 조회를 한 번 더 거는 일을 막는다.
    public func onScreenStart() {
        if uiState == .loading { return }
        load(showLoading: false)
    }

    public func markSent() {
        let partyId = self.partyId
        runMutation(.markSent) { repository in try await repository.markSent(partyId: partyId) }
    }

    /// 「받았어요」 — **되돌릴 수 없다.** 화면이 확인 다이얼로그를 거친 뒤에만 부른다.
    ///
    /// `senderPublicId` 가 빈 값이면 **부르지 않는다**(서버가 404 로 막는다). 화면이
    /// `FareSplitTransfer.isConfirmable` 로 버튼을 잠그지만, 여기서 한 번 더 막는 이유는 이 함수가
    /// 외부에서 보이는 API 라서다 — 잠금이 한 겹뿐이면 그 한 겹이 풀릴 때 조용히 404 가 된다.
    public func confirmReceived(senderPublicId: String) {
        if senderPublicId.isEmpty { return }
        let partyId = self.partyId
        runMutation(.confirmReceived) { repository in
            try await repository.confirmReceived(partyId: partyId, senderPublicId: senderPublicId)
        }
    }

    /// 「아직 안 들어왔어요」 — **멱등이 아닌 유일한 동작**이다(SENT 에서만 된다).
    public func markNotReceived(senderPublicId: String) {
        if senderPublicId.isEmpty { return }
        let partyId = self.partyId
        runMutation(.markNotReceived) { repository in
            try await repository.markNotReceived(partyId: partyId, senderPublicId: senderPublicId)
        }
    }

    public func clearActionError() {
        actionError = nil
    }

    /// 쓰기 호출 하나 — **성공 뒤 재조회가 이 함수의 존재 이유다.**
    ///
    /// 실패도 두 갈래로 다룬다: 「낡았다」는 신호면(`needsReloadAfter`) 문구와 **함께** 다시 읽는다.
    /// 그래야 사용자가 어긋난 화면 위에서 다음 동작을 하지 않는다.
    ///
    /// 중복 호출을 막는 이유는 네트워크 절약이 아니라 **순서**다 — 두 번 눌린 「받았어요」가 각자
    /// 재조회를 걸면 늦게 끝난 쪽의 낡은 응답이 화면을 되돌린다. 빗장은 태스크 **밖에서**(호출 자리에서) 세운다 —
    /// 태스크 안에서 세우면 두 번째 호출이 첫 태스크가 돌기 전에 검사를 지나간다.
    private func runMutation(
        _ action: FareSplitAction,
        _ block: @escaping @Sendable (any FareSplitRepository) async throws -> Void
    ) {
        if actionInProgress { return }
        actionInProgress = true
        actionError = nil

        let repository = self.repository
        mutationTask = scope.launch { [weak self] in
            var message: String?
            var reload = false
            do {
                try await block(repository)
                // ★ 본문이 없다 — 다시 읽는 것이 유일한 진실이다.
                reload = true
            } catch let failure as FareSplitException {
                message = fareSplitFailureMessage(failure: failure, action: action)
                reload = needsReloadAfter(failure: failure)
            } catch {
                // 화면을 떠나 취소됐으면 아무것도 쓰지 않는다 — 뷰모델이 사라지는 중이다.
                if Task.isCancelled { return }
                message = fareSplitGenericFailure(action: action)
            }
            guard let self else { return }
            if let message { self.actionError = message }
            if reload { await self.reloadAndWait() }
            self.actionInProgress = false
        }
    }

    /// 다시 읽고 **그 결과가 화면에 쓰일 때까지** 기다린다. 기다리는 사이 더 새 조회가 걸렸으면(화면 복귀 등)
    /// 그것까지 기다린다 — 버튼이 다시 열리는 순간의 화면이 늘 마지막 조회의 결과여야 한다.
    private func reloadAndWait() async {
        var awaited = load(showLoading: false)
        while true {
            await awaited.value
            guard let current = loadTask, current != awaited else { return }
            awaited = current
        }
    }

    /// 상세를 읽는다. `showLoading` 이 false 면 **보던 화면을 지우지 않는다** — 쓰기 뒤의 재조회와
    /// 화면 복귀가 그 경우다(깜빡이면 사용자가 자기가 누른 결과를 못 본다).
    ///
    /// 앞서 걸린 조회는 취소한다 — 늘 하나만 돈다(이 타입 주석의 「마지막에 건 요청이 이긴다」).
    @discardableResult
    private func load(showLoading: Bool) -> Task<Void, Never> {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        if showLoading { uiState = .loading }

        let repository = self.repository
        let loadRide = self.loadRide
        let partyId = self.partyId
        let task = scope.launch { [weak self] in
            let next: UiState
            do {
                if let detail = try await repository.getFareSplit(partyId: partyId) {
                    next = .ready(detail)
                } else {
                    next = await Self.absentState(loadRide: loadRide, partyId: partyId)
                }
            } catch let failure as FareSplitException {
                next = .error(message: fareSplitFailureMessage(failure: failure, action: .load))
            } catch {
                next = .error(message: fareSplitGenericFailure(action: .load))
            }
            // 뒤에 건 조회가 이 조회를 밀어냈다 — 이 응답은 더 낡았다.
            guard !Task.isCancelled, let self, generation == self.loadGeneration else { return }
            self.apply(next)
        }
        loadTask = task
        return task
    }

    /// 조회 결과를 화면 상태로 옮긴다.
    ///
    /// 실패면 **이미 보고 있던 상세를 지우지 않는다** — 쓰기 뒤의 재조회가 한 번 실패했다고 사용자가 보던
    /// 금액·계좌를 빼앗을 이유가 없다(17 탐색의 `markStale` 과 같은 판단). 그때 실패는 `actionError` 가 이미
    /// 말하고 있거나, 다음 복귀에서 다시 읽힌다.
    private func apply(_ next: UiState) {
        if case .error = next, case .ready = uiState { return }
        uiState = next
    }

    /// 정산이 없을 때 **누구에게 「정산 시작하기」를 띄울지** 방 상세로 묻는다.
    ///
    /// 방 상세 조회가 실패하면 **단정하지 않는다** — `canStart = false` + 이유 nil 이고, 화면은
    /// 「정산이 아직 없어요」와 다시 불러오기만 보여 준다. 실패를 「당신은 시작할 수 없다」로 읽으면
    /// 방장이 자기 방을 정산하지 못하는 막다른 화면이 된다.
    private nonisolated static func absentState(
        loadRide: @Sendable (Int64) async throws -> Ride,
        partyId: Int64
    ) async -> UiState {
        guard let ride = try? await loadRide(partyId) else {
            return .absent(canStart: false, blockedReason: nil)
        }
        switch startDraftGate(ride: ride) {
        case .ready: return .absent(canStart: true, blockedReason: nil)
        case .blocked(let message, _): return .absent(canStart: false, blockedReason: message)
        }
    }
}

/// 39 정산 상세 진입점. 역할 분기는 화면이 한다(`FareSplitDetailScreen`).
///
/// 방 id 로 뷰를 가른다(`.id(partyId)`) — 방이 다른데 같은 뷰모델을 물려받으면 **남의 정산이 보인다.**
/// 정산은 돈이 걸린 화면이라 그 혼동의 대가가 특히 크다(원본 `key = "fare-split-$partyId"` 자리).
public struct FareSplitDetailRoute: View {
    private let repository: any FareSplitRepository
    private let rideRepository: any RideRepository
    private let partyId: Int64?
    private let onBack: () -> Void
    private let onOpenEditor: (Bool) -> Void
    private let onOpenChat: (() -> Void)?

    /// - Parameters:
    ///   - onOpenEditor: 40 정산 시작·수정으로. **인자(`start`)가 둘을 가른다** — 아직 정산이 없는 방에서는
    ///     시작(POST)이고, 있는 정산에서는 수정(PATCH)이다. 한 콜백으로 묶은 이유는 목적지가 같은 라우트라서이고,
    ///     불리언으로 가르는 이유는 **호출하는 자리가 이미 그 사실을 알고 있기** 때문이다
    ///     (시작은 `FareSplitAbsentScreen`, 수정은 `FareSplitDetailScreen` 에서 온다).
    ///   - onOpenChat: 채팅으로. 열 곳이 없으면 nil — 버튼을 그리지 않는다.
    public init(
        repository: any FareSplitRepository,
        rideRepository: any RideRepository,
        partyId: Int64?,
        onBack: @escaping () -> Void = {},
        onOpenEditor: @escaping (Bool) -> Void = { _ in },
        onOpenChat: (() -> Void)? = nil
    ) {
        self.repository = repository
        self.rideRepository = rideRepository
        self.partyId = partyId
        self.onBack = onBack
        self.onOpenEditor = onOpenEditor
        self.onOpenChat = onOpenChat
    }

    public var body: some View {
        // 방 id 없이 닿을 길은 없다. 그래도 nil 이면 **예시 정산을 그리지 않고** 사실대로 말하고 되돌린다
        // (21 의 waitingRideDummy 가 프로덕션에 샜던 사고와 같은 종류의 방어다).
        if let partyId {
            FareSplitDetailContent(
                repository: repository,
                rideRepository: rideRepository,
                partyId: partyId,
                onBack: onBack,
                onOpenEditor: onOpenEditor,
                onOpenChat: onOpenChat
            )
            .id(partyId)
        } else {
            BackStateScaffold(title: "택시비 정산", onBack: onBack) {
                ErrorBox(message: "정산 정보를 불러오지 못했어요", onRetry: onBack, actionLabel: "돌아가기")
            }
        }
    }
}

/// 방 id 를 아는 Route 본체. 뷰모델은 id 가 있어야 만들 수 있어 나눴다.
private struct FareSplitDetailContent: View {
    @HostedViewModel private var viewModel: FareSplitDetailViewModel

    private let onBack: () -> Void
    private let onOpenEditor: (Bool) -> Void
    private let onOpenChat: (() -> Void)?

    init(
        repository: any FareSplitRepository,
        rideRepository: any RideRepository,
        partyId: Int64,
        onBack: @escaping () -> Void,
        onOpenEditor: @escaping (Bool) -> Void,
        onOpenChat: (() -> Void)?
    ) {
        _viewModel = HostedViewModel(
            wrappedValue: FareSplitDetailViewModel(
                repository: repository,
                loadRide: { try await rideRepository.getPartyDetail(partyId: $0) },
                partyId: partyId
            )
        )
        self.onBack = onBack
        self.onOpenEditor = onOpenEditor
        self.onOpenChat = onOpenChat
    }

    var body: some View {
        let viewModel = self.viewModel

        // 효과는 바뀌지 않는 바깥 컨테이너에 건다 — 상태 분기마다 걸면 로딩→성공 전환에서 시작 신호가 한 번 더 난다.
        ZStack {
            switch viewModel.uiState {
            case .loading:
                BackStateScaffold(title: "택시비 정산", onBack: onBack) {
                    LoadingBox()
                }
            case .error(let message):
                BackStateScaffold(title: "택시비 정산", onBack: onBack) {
                    ErrorBox(message: message, onRetry: { viewModel.refresh() })
                }
            case .absent(let canStart, let blockedReason):
                FareSplitAbsentScreen(
                    canStart: canStart,
                    blockedReason: blockedReason,
                    onBack: onBack,
                    onStart: { onOpenEditor(true) },
                    onRetry: { viewModel.refresh() }
                )
            case .ready(let detail):
                FareSplitDetailScreen(
                    detail: detail,
                    actionInProgress: viewModel.actionInProgress,
                    actionErrorMessage: viewModel.actionError,
                    onBack: onBack,
                    onEdit: { onOpenEditor(false) },
                    onMarkSent: { viewModel.markSent() },
                    onConfirmReceived: { viewModel.confirmReceived(senderPublicId: $0) },
                    onMarkNotReceived: { viewModel.markNotReceived(senderPublicId: $0) },
                    // 딥링크는 **서버가 준 문자열 그대로** 넘긴다. `supertoss` 가 아니거나 열지 못하면 false 가 돌아가
                    // 화면이 복사 안내로 바뀐다(`TOSS_OPEN_FAILED_NOTICE`).
                    onOpenToss: { await openTossTransfer(deeplink: $0) },
                    onCopy: { target, value in copyToPasteboard(value, target: target) },
                    onOpenChat: onOpenChat
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 40 에서 돌아오면 금액이 바뀌어 있을 수 있다 — 복귀마다 다시 읽는다(깜빡이지 않는다).
        .lifecycleEffect(onStart: { viewModel.onScreenStart() })
    }
}
