import MoyeotaDesignSystem
import MoyeotaDomain
import Observation
import PresentationCore
import SwiftUI

/// 40 정산 시작·수정의 상태·호출.
///
/// ### 입력을 뷰모델에 두는 이유
/// 34 기록·36 프로필 수정과 같다 — 화면이 다시 만들어져도 입력이 살아남아야 한다. 더 센 이유가 하나 더 있다:
/// **은행 선택 창이 떴다 사라지는 동안** 금액 칸들이 그대로 있어야 하고, 그 값들은 서로 **합계 제약**으로 묶여 있다
/// (`submitBlockOf`) — 일부만 복원되면 합이 어긋난 폼이 된다.
///
/// ### 시작과 수정이 **읽는 곳이 다르다** ★
///
/// | 모드 | 탑승자 목록의 출처 | 왜 |
/// |---|---|---|
/// | `FareSplitEditMode.start` | **방 상세**(`getPartyDetail`) | 아직 정산이 없으니 도착을 누른 멤버를 방에서만 알 수 있다(`Ride.fareSplitRiders`) |
/// | `FareSplitEditMode.edit` | **정산 상세**(`getFareSplit`) | 받는 사람 + `transfers` 가 곧 탑승자 전원이다 — 방을 다시 읽을 이유가 없다 |
///
/// 수정에서 방을 읽지 않는 것이 단순한 절약이 아니다: 방이 지워진 뒤에도 정산은 남으므로
/// (`MyFareSplit` 의 nil 경로) 방을 필수로 읽으면 **고칠 수 있는 정산을 못 고치는** 경우가 생긴다.
///
/// ### 409 둘을 **실패로만 끝내지 않는다**
///
/// | 서버 | 뜻 | 이 화면이 하는 일 |
/// |---|---|---|
/// | `FARE_SPLIT_ALREADY_EXISTS` | 이미 그 방에 정산이 있다 | 적은 값을 **남긴 채** 「지금 있는 정산 보기」를 준다(`FareSplitEditScreen` 의 `onSeeExisting`) |
/// | `FARE_SPLIT_ALREADY_STARTED` | 그사이 누가 「보냈어요」를 눌렀다 | 적은 값을 **남긴 채** 읽기 전용으로 바꾼다 |
///
/// 둘 다 **화면을 닫지 않는다.** 금액을 다 채운 뒤에 오는 실패라, 닫으면 그 입력이 통째로 사라진다.
@MainActor
@Observable
public final class FareSplitEditViewModel {

    public enum UiState: Equatable, Sendable {
        case loading

        /// 적는 중.
        ///
        /// - `readOnlyReason`: nil 이 아니면 **보낼 길이 닫혔지만 적은 값은 남아 있다**(409 `FARE_SPLIT_ALREADY_STARTED`).
        /// - `existingFound`: 이미 그 방에 정산이 있었다 — 화면이 「지금 있는 정산 보기」를 준다.
        case editing(Editing)

        /// 애초에 열 수 없는 화면. `recoverable` 이 false 면 **이 방은 영구히 정산할 수 없다** —
        /// 화면이 「다시 시도」를 권하지 않는다(`FareSplitDraftGate.blocked`).
        case blocked(message: String, recoverable: Bool)

        case error(message: String)
    }

    public struct Editing: Equatable, Sendable {
        public internal(set) var draft: FareSplitDraftState
        public internal(set) var fareHint: String?
        public internal(set) var submitting = false
        public internal(set) var errorMessage: String?
        public internal(set) var readOnlyReason: String?
        public internal(set) var existingFound = false
    }

    public private(set) var uiState: UiState = .loading

    /// 저장이 끝났다 — Route 가 이 신호로 되돌아간다(39 가 복귀하며 다시 읽는다).
    public private(set) var saved = false

    @ObservationIgnored private let repository: any FareSplitRepository
    /// 방 상세를 읽는 **한 가지 일**만 받는다 — 근거는 `FareSplitDetailViewModel.loadRide` 와 같다.
    @ObservationIgnored private let loadRide: @Sendable (Int64) async throws -> Ride
    @ObservationIgnored private let partyId: Int64
    @ObservationIgnored private let mode: FareSplitEditMode
    @ObservationIgnored private let scope = ViewModelScope()

    /// 지금 도는 조회 — 늘 하나다(새로 걸면 앞의 것을 취소한다). 테스트가 기다리는 손잡이이기도 하다.
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?
    /// 지금 도는 제출. 테스트가 기다리는 손잡이다.
    @ObservationIgnored private(set) var submitTask: Task<Void, Never>?

    public init(
        repository: any FareSplitRepository,
        loadRide: @escaping @Sendable (Int64) async throws -> Ride,
        partyId: Int64,
        mode: FareSplitEditMode
    ) {
        self.repository = repository
        self.loadRide = loadRide
        self.partyId = partyId
        self.mode = mode
        load()
    }

    public func load() {
        loadTask?.cancel()
        uiState = .loading
        let repository = self.repository
        let loadRide = self.loadRide
        let partyId = self.partyId
        let mode = self.mode
        loadTask = scope.launch { [weak self] in
            let next: UiState
            do {
                switch mode {
                case .start:
                    let ride = try await loadRide(partyId)
                    next = Self.state(gate: startDraftGate(ride: ride), fareHint: estimatedFareHint(ride: ride))
                case .edit:
                    // 고치려고 왔는데 정산이 사라졌다(= 아무도 시작하지 않았다). 빈 폼을 그리지
                    // 않는다 — 수정 폼은 기존 값을 전제로 만들어졌고, 시작은 39 를 거쳐야 한다.
                    if let detail = try await repository.getFareSplit(partyId: partyId) {
                        next = Self.state(gate: editDraftGate(detail: detail), fareHint: nil)
                    } else {
                        next = .blocked(message: "이 방에는 택시비 정산이 없어요", recoverable: true)
                    }
                }
            } catch let failure as FareSplitException {
                next = .error(message: fareSplitFailureMessage(failure: failure, action: .load))
            } catch {
                next = .error(message: fareSplitGenericFailure(action: .load))
            }
            guard !Task.isCancelled, let self else { return }
            self.uiState = next
        }
    }

    private nonisolated static func state(gate: FareSplitDraftGate, fareHint: String?) -> UiState {
        switch gate {
        case .ready(let draft): .editing(Editing(draft: draft, fareHint: fareHint))
        case .blocked(let message, let recoverable): .blocked(message: message, recoverable: recoverable)
        }
    }

    // ─── 입력 ───
    //
    // 전부 순수 함수에 맡긴다(`FareSplitDraftState` 의 with… 함수) — 1/N 자동 채우기와
    // 자릿수 상한 같은 규칙이 뷰모델과 화면 두 곳으로 갈리지 않게 한다.

    public func onFareChange(_ raw: String) { editDraft { $0.withFare(raw: raw) } }

    public func onBankSelect(_ bank: Bank) { editDraft { $0.withBank(bank: bank) } }

    public func onAccountChange(_ raw: String) { editDraft { $0.withAccount(raw: raw) } }

    public func onAmountChange(publicId: String, raw: String) { editDraft { $0.withAmount(publicId: publicId, raw: raw) } }

    public func onSplitEvenly() { editDraft { $0.splitEvenly() } }

    /// 적은 값을 고친다. **읽기 전용이면 아무것도 하지 않는다** — 409 뒤에도 값은 남겨 두지만
    /// 고칠 수는 없다(화면이 `enabled: false` 로 막지만, 상태 쪽에서도 막아 두 겹으로 둔다).
    ///
    /// 고칠 때마다 `Editing.errorMessage` 를 지운다 — 서버가 거절한 이유를 고치고 있는
    /// 중인데 그 문구가 남아 있으면 **방금 고친 것이 또 거절된 것처럼** 보인다.
    private func editDraft(_ transform: (FareSplitDraftState) -> FareSplitDraftState) {
        guard case .editing(var editing) = uiState,
              editing.readOnlyReason == nil, !editing.submitting
        else { return }
        editing.draft = transform(editing.draft)
        editing.errorMessage = nil
        uiState = .editing(editing)
    }

    /// 서버로 보낸다. **`submitBlockOf` 가 nil 일 때만** 실제 호출이 나간다 — 화면이 버튼을 잠그지만
    /// 여기서도 한 번 더 본다(잠금이 한 겹뿐이면 그 한 겹이 풀릴 때 조용히 400 이 된다).
    public func submit() {
        guard case .editing(var editing) = uiState,
              !editing.submitting, editing.readOnlyReason == nil,
              submitBlockOf(state: editing.draft) == nil,
              let draft = editing.draft.toDraft()
        else { return }

        editing.submitting = true
        editing.errorMessage = nil
        uiState = .editing(editing)

        let repository = self.repository
        let partyId = self.partyId
        let mode = self.mode
        let action = submitAction
        submitTask = scope.launch { [weak self] in
            do {
                switch mode {
                case .start: _ = try await repository.startFareSplit(partyId: partyId, draft: draft)
                case .edit: _ = try await repository.editFareSplit(partyId: partyId, draft: draft)
                }
                // 응답으로 온 상세는 쓰지 않는다 — 되돌아가면 39 가 다시 읽는다
                // (`FareSplitDetailViewModel.onScreenStart`). 두 화면이 각자 상세를 들고 있으면
                // 한쪽만 낡는 자리가 생긴다.
                self?.saved = true
            } catch let failure as FareSplitException {
                self?.failSubmit { now in
                    let message = fareSplitFailureMessage(failure: failure, action: action)
                    now.errorMessage = message
                    // 그사이 누가 「보냈어요」를 눌렀다 — 보낼 길만 닫고 **값은 남긴다.**
                    if failure.isAlreadyStarted { now.readOnlyReason = message }
                    // 이미 있는 정산 — 서버가 「GET 으로 본다」라고 적어 둔 복구 가능한 실패다.
                    if failure.isAlreadyExists { now.existingFound = true }
                }
            } catch {
                if Task.isCancelled { return }
                self?.failSubmit { now in now.errorMessage = fareSplitGenericFailure(action: action) }
            }
        }
    }

    private func failSubmit(_ update: (inout Editing) -> Void) {
        guard case .editing(var now) = uiState else { return }
        now.submitting = false
        update(&now)
        uiState = .editing(now)
    }

    private var submitAction: FareSplitAction {
        switch mode {
        case .start: .start
        case .edit: .edit
        }
    }
}

/// 40 정산 시작·수정 진입점.
///
/// 뷰를 방과 **모드까지** 묶어 가른다(`.id`) — 같은 방의 시작 폼과 수정 폼은 **다른 값을 들고 있다**
/// (하나는 빈 폼, 하나는 서버 값). 섞이면 시작하려다 되돌아온 뒤 수정으로 들어갔을 때 빈 폼이 재사용돼
/// **기존 금액이 보이지 않는다**(원본 `key = "fare-split-edit-$partyId-$mode"` 자리).
public struct FareSplitEditRoute: View {
    private let repository: any FareSplitRepository
    private let rideRepository: any RideRepository
    private let partyId: Int64?
    private let mode: FareSplitEditMode
    private let onBack: () -> Void
    private let onSaved: () -> Void

    /// - Parameter onSaved: 저장 성공. 39 상세로 되돌아가고, 그쪽이 복귀하며 다시 읽는다.
    public init(
        repository: any FareSplitRepository,
        rideRepository: any RideRepository,
        partyId: Int64?,
        mode: FareSplitEditMode,
        onBack: @escaping () -> Void = {},
        onSaved: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.rideRepository = rideRepository
        self.partyId = partyId
        self.mode = mode
        self.onBack = onBack
        self.onSaved = onSaved
    }

    private struct ContentKey: Hashable {
        let partyId: Int64
        let mode: FareSplitEditMode
    }

    public var body: some View {
        if let partyId {
            FareSplitEditContent(
                repository: repository,
                rideRepository: rideRepository,
                partyId: partyId,
                mode: mode,
                onBack: onBack,
                onSaved: onSaved
            )
            .id(ContentKey(partyId: partyId, mode: mode))
        } else {
            BackStateScaffold(title: "택시비 정산", onBack: onBack) {
                ErrorBox(message: "정산 정보를 불러오지 못했어요", onRetry: onBack, actionLabel: "돌아가기")
            }
        }
    }
}

private struct FareSplitEditContent: View {
    @HostedViewModel private var viewModel: FareSplitEditViewModel

    private let mode: FareSplitEditMode
    private let onBack: () -> Void
    private let onSaved: () -> Void

    init(
        repository: any FareSplitRepository,
        rideRepository: any RideRepository,
        partyId: Int64,
        mode: FareSplitEditMode,
        onBack: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        _viewModel = HostedViewModel(
            wrappedValue: FareSplitEditViewModel(
                repository: repository,
                loadRide: { try await rideRepository.getPartyDetail(partyId: $0) },
                partyId: partyId,
                mode: mode
            )
        )
        self.mode = mode
        self.onBack = onBack
        self.onSaved = onSaved
    }

    var body: some View {
        let viewModel = self.viewModel
        let saved = viewModel.saved

        ZStack {
            switch viewModel.uiState {
            case .loading:
                BackStateScaffold(title: editTitle(mode: mode), onBack: onBack) {
                    LoadingBox()
                }
            case .error(let message):
                BackStateScaffold(title: editTitle(mode: mode), onBack: onBack) {
                    ErrorBox(message: message, onRetry: { viewModel.load() })
                }
            case .blocked(let message, let recoverable):
                BackStateScaffold(title: editTitle(mode: mode), onBack: onBack) {
                    // 되돌릴 수 없는 막힘에는 「다시 시도」를 적지 않는다 — 다시 눌러도 같은 답이다
                    // (`ErrorBox` 의 actionLabel 이 바로 이 경우를 위해 있다).
                    ErrorBox(
                        message: message,
                        onRetry: recoverable ? { viewModel.load() } : onBack,
                        actionLabel: recoverable ? "다시 시도" : "돌아가기"
                    )
                }
            case .editing(let editing):
                FareSplitEditScreen(
                    state: editing.draft,
                    fareHint: editing.fareHint,
                    submitting: editing.submitting,
                    errorMessage: editing.errorMessage,
                    readOnlyReason: editing.readOnlyReason,
                    onBack: onBack,
                    onFareChange: { viewModel.onFareChange($0) },
                    onBankSelect: { viewModel.onBankSelect($0) },
                    onAccountChange: { viewModel.onAccountChange($0) },
                    onAmountChange: { viewModel.onAmountChange(publicId: $0, raw: $1) },
                    onSplitEvenly: { viewModel.onSplitEvenly() },
                    onSubmit: { viewModel.submit() },
                    // 이미 있는 정산을 보러 간다 = 39 로 되돌아간다(그쪽이 복귀하며 읽는다).
                    onSeeExisting: editing.existingFound ? onSaved : nil
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: saved) {
            if saved { onSaved() }
        }
    }
}
