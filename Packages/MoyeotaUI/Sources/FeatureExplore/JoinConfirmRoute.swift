import Foundation
import MoyeotaDomain
import Observation
import PresentationCore
import SwiftUI

/// 원인을 가릴 수 없는 합류 실패(401·5xx·직렬화 등)의 문구 — 재시도 말고는 안내할 게 없다
private let JOIN_FAILED_MESSAGE = "합류하지 못했어요. 잠시 후 다시 시도해 주세요"

@MainActor
@Observable
public final class JoinConfirmViewModel {
    public enum UiState: Equatable, Sendable {
        case loading
        case success(ride: Ride)
        case error(message: String)
    }

    /// 합류 제출 상태. `joinedPartyId` 가 채워지면 Route 가 21 매칭 대기로 넘긴다.
    ///
    /// 넘기는 건 방 **id 하나**다. 합류 응답에 동승자 목록이 없고(Backend #213) 21 이 구독하는 SSE 의
    /// 첫 스냅샷이 방 상세 전체를 주므로, 예전처럼 여기서 상세를 한 번 더 읽어 `Ride` 를 만들어 넘기면
    /// **왕복 1회가 그냥 버려진다.**
    public struct JoinState: Equatable, Sendable {
        public var joining: Bool
        public var errorMessage: String?
        public var joinedPartyId: Int64?

        public init(joining: Bool = false, errorMessage: String? = nil, joinedPartyId: Int64? = nil) {
            self.joining = joining
            self.errorMessage = errorMessage
            self.joinedPartyId = joinedPartyId
        }
    }

    public private(set) var uiState: UiState = .loading
    public private(set) var joinState = JoinState()

    @ObservationIgnored private let repository: any RideRepository
    /// 합류를 막은 **그 다른 방**이 어떤 방인지 알아내는 용도 하나로 쓴다(`blockingPartyConfirmed`).
    /// 서버는 409 에 「어느 방인지」도 「확정됐는지」도 싣지 않으므로, 그걸 알려면 내 진행 중인 방을
    /// 따로 찾아야 한다. 실패 경로에서만 부르므로 평상시 왕복은 늘지 않는다.
    @ObservationIgnored private let activeParty: any ActivePartyRepository
    @ObservationIgnored private let partyId: Int64
    @ObservationIgnored private let scope = ViewModelScope()

    public init(repository: any RideRepository, activeParty: any ActivePartyRepository, partyId: Int64) {
        self.repository = repository
        self.activeParty = activeParty
        self.partyId = partyId
        refresh()
    }

    public func refresh() {
        uiState = .loading
        let repository = repository
        let partyId = partyId
        // 대기 중에 self 를 잡지 않는다 — 잡고 있으면 화면을 떠나도 뷰모델이 해제되지 않아 요청이 취소되지 않는다.
        scope.launch { [weak self] in
            do {
                let ride = try await repository.getPartyDetail(partyId: partyId)
                self?.uiState = .success(ride: ride)
            } catch {
                self?.uiState = .error(message: "동승 정보를 불러오지 못했어요")
            }
        }
    }

    /// 합류 제출. 합류 주체는 Bearer 토큰이 정한다 — memberId 를 넘기지 않는다 (22 보고서 §2).
    ///
    /// 성공하면 **응답을 쓰지 않고** 방 id 만 세운다(상태·인원은 21 의 첫 스냅샷이 더 정확히 준다).
    ///
    /// 실패 중 하나는 실패가 아니다: `PartyJoinException.isAlreadyInThisParty` 는 **서버에 내가 이미 그 방
    /// 멤버로 들어가 있다**는 뜻이고(데이터 계층이 상세로 확인한 증거다) — 그러니 **성공과 똑같은 길로**
    /// 21 로 보낸다. 이 분기가 없으면 그 계정은 재시도도 409, 다른 방도 409 라 30분 스윕 전까지 어떤 방에도
    /// 못 들어간다(합류는 서버가 멤버 추가를 먼저 커밋하고 응답을 만든다).
    ///
    /// 나머지 실패는 `joinFailureMessage` 가 각각 다른 문구로 안내한다. 방 사정이 바뀌어 막힌 경우
    /// (가득 참·모집 종료)에는 들고 있는 상세를 **조용히** 다시 읽어 지금 인원이 보이게 한다 —
    /// 화면을 로딩으로 덮으면 방금 띄운 안내 문구가 사라진다.
    public func join() {
        if joinState.joining { return } // 중복 제출 차단 (공통 규칙)
        // 잠금은 태스크를 띄우기 **전에** 건다. 태스크 첫 줄은 다음 차례에야 돌아서, 그 안에서 걸면
        // 연타한 두 번째 호출이 위 검사를 통과해 합류 요청이 두 번 나간다.
        joinState.joining = true
        joinState.errorMessage = nil
        Analytics.track(.partyJoinClicked)
        let repository = repository
        let activeParty = activeParty
        let partyId = partyId
        scope.launch { [weak self] in
            do {
                _ = try await repository.joinParty(partyId: partyId)
                self?.finishJoin(joinedPartyId: partyId)
            } catch {
                // 화면을 떠나며 태스크가 취소된 것 — 실패 문구를 띄우지 않는다. 살아 있는 태스크의 `URLError(.cancelled)` 는
                // 원본에서 `isNetwork` 인 `PartyJoinException` 이 되는 `IOException` 이라 같은 값을 만든다.
                let live = failureOnLiveTask(error: error) {
                    PartyJoinException(code: nil, serverMessage: nil, isNetwork: true, cause: $0)
                }
                guard let live else {
                    self?.finishJoin()
                    return
                }
                guard let e = live as? PartyJoinException else {
                    self?.finishJoin(errorMessage: JOIN_FAILED_MESSAGE)
                    Analytics.track(.matchRequestFailed(method: .join, reason: "unknown"))
                    return
                }
                if e.isAlreadyInThisParty {
                    self?.finishJoin(joinedPartyId: partyId)
                    return
                }
                // 「다른 방에 참여 중」일 때만 그 방의 사정을 확인한다 — 확정된 방이면 나갈 수가 없어서
                // 안내할 행동이 완전히 달라진다(`alreadyInPartyMessage`).
                let blockingConfirmed: Bool? = if e.isAlreadyInAnotherParty {
                    await JoinConfirmViewModel.blockingPartyConfirmed(activeParty: activeParty)
                } else {
                    nil
                }
                // 그 조회를 기다리는 사이 화면을 떠났으면 문구도 실패 기록도 남기지 않는다 — 원본에서
                // `blockingPartyConfirmed` 가 되던지는 `CancellationException` 자리다.
                if Task.isCancelled { return }
                self?.finishJoin(errorMessage: joinFailureMessage(e: e, blockingConfirmed: blockingConfirmed))
                Analytics.track(.matchRequestFailed(method: .join, reason: joinFailureReason(e: e)))
                if e.isPartyFull || e.isPartyClosed {
                    // 떠 있는 방을 로딩으로 덮지 않고 다시 읽는다. 실패는 조용히 둔다 — 보던 값이 조금 낡는 것보다 낫다.
                    guard let ride = try? await repository.getPartyDetail(partyId: partyId) else { return }
                    self?.uiState = .success(ride: ride)
                }
            }
        }
    }

    private func finishJoin(errorMessage: String? = nil, joinedPartyId: Int64? = nil) {
        joinState.joining = false
        if let errorMessage { joinState.errorMessage = errorMessage }
        if let joinedPartyId {
            joinState.joinedPartyId = joinedPartyId
            // 핵심 퍼널 2단계(합류 쪽). 「이미 이 방 멤버」로 복구된 경우도 서버에 내 자리가 있다는 뜻이라 같이 센다.
            // 방 상세에는 주소가 없어 지역은 싣지 못한다 — 방 생성 쪽만 지역이 있다.
            let ride: Ride? = if case .success(let ride) = uiState { ride } else { nil }
            Analytics.track(.matchRequested(
                method: .join,
                capacity: ride?.capacity,
                originArea: nil,
                destinationArea: nil,
                estimatedFare: ride?.estimatedFare
            ))
        }
    }

    /// 합류를 막은 그 방이 **약속이 정해진 방인가.** 모르면 nil.
    ///
    /// 실패했을 때만 부른다. 실패하거나 못 찾으면 nil 로 떨어뜨려 **단정하지 않는 문구**로 가게 한다 —
    /// 안내 한 줄을 정확히 만들려다 안내 자체를 못 띄우면 더 나쁘다.
    ///
    /// 취소(`CancellationError`)도 여기서는 nil 이다 — 정말 화면을 떠났는지는 부르는 쪽이 `Task.isCancelled` 로
    /// 보고 끝낸다. 살아 있는 태스크의 `URLError(.cancelled)` 는 원본의 `IOException` 이라 다른 실패와 같이 nil 이다.
    /// 정적 함수로 두는 건 조회를 기다리는 동안 self 를 잡지 않으려는 것이다 — 잡고 있으면 화면을 떠나도
    /// 뷰모델이 해제되지 않아 조회가 취소되지 않는다(`refresh` 와 같은 처방).
    private static func blockingPartyConfirmed(activeParty: any ActivePartyRepository) async -> Bool? {
        do {
            return try await activeParty.resolve()?.isConfirmed
        } catch {
            return nil
        }
    }
}

/// `fail_match_request` 의 `reason` — `joinFailureMessage` 와 같은 분기를 문구가 아니라 상수로 옮긴다.
/// `isAlreadyInThisParty` 는 여기 오지 않는다(성공 경로).
func joinFailureReason(e: PartyJoinException) -> String {
    if e.isPartyFull { return "party_full" }
    if e.isPartyClosed { return "party_closed" }
    if e.isPartyNotFound { return "party_not_found" }
    if e.isAlreadyInAnotherParty { return "already_in_party" }
    if e.isAlreadyJoined { return "already_joined" }
    if e.isNetwork { return "network" }
    return "unknown"
}

/// 합류 실패를 사용자 문구로 옮긴다 — 실패마다 **다른 말**을 해야 다음 행동이 갈린다
/// (가득 찬 방은 다른 방을 고르면 되고, 다른 방에 참여 중이면 그 방을 먼저 정리해야 한다).
///
/// 분기 근거는 서버 코드 문자열이 아니라 `PartyJoinException` 의 프로퍼티다 — 서버가 enum 이름을 바꿀 때
/// 화면이 조용히 어긋나지 않게 도메인이 한 번 걸러 준 값이다.
///
/// `PartyJoinException.isAlreadyInThisParty` 는 여기 오지 않는다 — 그건 실패가 아니라 **이미 합류됨**이라
/// 호출부가 성공 경로로 보낸다.
///
/// 「다른 방에 참여 중」과 「이 방인지 확인 실패」가 같은 자리에 섞여 있는 건 서버 사정이다: 재합류도
/// 다른 방 참여도 똑같이 `ALREADY_JOINED_OTHER_PARTY` 로 오고, 데이터 계층이 상세 조회로 가른다.
/// 그 조회까지 실패하면 「다른 방」으로 떨어지므로, 문구는 **그 방으로 가 보라는 쪽**으로 적는다.
///
/// - Parameter blockingConfirmed: 합류를 막은 그 방이 약속이 정해진 방인가. 모르면 nil — `alreadyInPartyMessage` 참고.
func joinFailureMessage(e: PartyJoinException, blockingConfirmed: Bool? = nil) -> String {
    if e.isPartyFull { return "방이 가득 찼어요. 다른 방을 찾아 주세요" }
    if e.isPartyClosed { return "모집이 끝난 방이에요. 다른 방을 찾아 주세요" }
    if e.isPartyNotFound { return "사라진 방이에요. 목록을 다시 불러와 주세요" }
    if e.isAlreadyInAnotherParty { return alreadyInPartyMessage(blockingConfirmed: blockingConfirmed) }
    if e.isAlreadyJoined { return "이미 참여 중이에요. 홈에서 진행 중인 방을 확인해 주세요" }
    if e.isNetwork { return "네트워크가 불안정해요. 연결을 확인하고 다시 시도해 주세요" }
    return JOIN_FAILED_MESSAGE
}

/// 「이미 참여 중인 방이 있다」를 **그 방의 사정에 맞춰** 말한다.
///
/// 예전에는 한 문구였다 — 「그 방에서 나온 뒤 합류해 주세요」. 확정 전 방에서는 맞는 말이지만
/// **약속이 정해진 방에서는 할 수 없는 일을 시킨다**: 나가기가 409 `CANNOT_LEAVE_CONFIRMED_PARTY` 로
/// 막히고, 방 종료도 409 `USE_DEPART_FOR_CONFIRMED_PARTY` 로 막힌다. 끝내는 길은 **출발지에 가서
/// 「출발」을 누르는 것 하나뿐**이라, 나가기 버튼을 찾아 헤매게 하지 않고 그 길을 말해 준다.
///
/// nil(모름)일 때 「나온 뒤」를 말하지 않는 이유도 같다 — 틀릴 수 있는 지시보다 **틀릴 수 없는 안내**가
/// 낫다. 그 방으로 보내면 방 화면이 「약속을 정한 뒤에는 나갈 수 없어요」로 사실을 말해 준다.
func alreadyInPartyMessage(blockingConfirmed: Bool?) -> String {
    switch blockingConfirmed {
    case true?: "약속이 정해진 방에 참여 중이에요. 출발지에서 「출발」을 눌러 그 방을 끝낸 뒤에 합류할 수 있어요"
    case false?: "이미 참여 중인 방이 있어요. 그 방에서 나온 뒤 합류해 주세요"
    case nil: "이미 참여 중인 방이 있어요. 홈에서 진행 중인 방을 확인해 주세요"
    }
}

/// 20 합류 확인 — 서버 상세 조회 + 합류 액션 진입점. partyId 없으면 오류 안내 후 되돌린다.
///
/// 합류가 끝나면 **방 id 만** 넘긴다(`onJoined`) — 합류 응답은 더 이상 방 상세가 아니고(Backend #213),
/// 다음 화면(21 매칭 대기)이 SSE 첫 스냅샷으로 상세 전체를 받으므로 여기서 상세를 읽어 넘길 이유가 없다.
public struct JoinConfirmRoute: View {
    private let repository: any RideRepository
    private let activePartyRepository: any ActivePartyRepository
    private let partyId: Int64?
    private let onDismiss: () -> Void
    private let onJoined: (Int64) -> Void
    private let onMemberClick: (User) -> Void

    /// - Parameter onJoined: 합류가 끝난(또는 **이미 돼 있던**) 방 id — 호출자는 21 매칭 대기로 넘긴다
    public init(
        repository: any RideRepository,
        activePartyRepository: any ActivePartyRepository,
        partyId: Int64?,
        onDismiss: @escaping () -> Void = {},
        onJoined: @escaping (Int64) -> Void = { _ in },
        onMemberClick: @escaping (User) -> Void = { _ in }
    ) {
        self.repository = repository
        self.activePartyRepository = activePartyRepository
        self.partyId = partyId
        self.onDismiss = onDismiss
        self.onJoined = onJoined
        self.onMemberClick = onMemberClick
    }

    public var body: some View {
        // 목록에서 방을 고르지 않고 닿을 길은 없다. 그래도 nil 이면 예시 방을 그리는 대신
        // 사실대로 말하고 되돌린다 — 존재하지 않는 방에 합류 버튼을 보여 줄 수는 없다.
        if let partyId {
            JoinConfirmContent(
                repository: repository,
                activePartyRepository: activePartyRepository,
                partyId: partyId,
                onDismiss: onDismiss,
                onJoined: onJoined,
                onMemberClick: onMemberClick
            )
            // 원본 `viewModel(key = "join-$partyId")` 자리 — 다른 방이면 다른 뷰모델이다.
            .id(partyId)
        } else {
            BackStateScaffold(title: "합류할까요?", onBack: onDismiss) {
                ErrorBox(message: "동승 정보를 불러오지 못했어요", onRetry: onDismiss)
            }
        }
    }
}

private struct JoinConfirmContent: View {
    let partyId: Int64
    let onDismiss: () -> Void
    let onJoined: (Int64) -> Void
    let onMemberClick: (User) -> Void

    @HostedViewModel private var viewModel: JoinConfirmViewModel

    // 「내 위치에서 약 N m」용 좌표. 권한을 자동 요청하지 않는다 — 합류 판단에 꼭 필요한 값이 아니라
    // 여기서 다이얼로그를 띄우면 흐름을 끊는다. 이미 허용돼 있으면(14·17 에서) 거리 줄이 뜬다.
    @RememberMyLocationState(autoRequestPermission: false) private var myLocation

    init(
        repository: any RideRepository,
        activePartyRepository: any ActivePartyRepository,
        partyId: Int64,
        onDismiss: @escaping () -> Void,
        onJoined: @escaping (Int64) -> Void,
        onMemberClick: @escaping (User) -> Void
    ) {
        _viewModel = HostedViewModel(
            wrappedValue: JoinConfirmViewModel(
                repository: repository,
                activeParty: activePartyRepository,
                partyId: partyId
            )
        )
        self.partyId = partyId
        self.onDismiss = onDismiss
        self.onJoined = onJoined
        self.onMemberClick = onMemberClick
    }

    var body: some View {
        let viewModel = viewModel
        let join = viewModel.joinState
        let partyId = partyId
        let onJoined = onJoined

        // 분기를 `ZStack` 하나로 감싼다. 아래 이펙트가 상태 분기마다 따로 걸리면 로딩 → 상세 전환이
        // 사라짐·나타남으로 읽혀 위치 구독이 끊겼다 이어진다.
        ZStack {
            // 탭바가 없는 화면이라 뒤로가기가 유일한 이동 수단 — 로딩·에러에서도 남긴다 (QA F-1 동류)
            switch viewModel.uiState {
            case .loading:
                BackStateScaffold(title: "합류할까요?", onBack: onDismiss) {
                    LoadingBox()
                }
            case .error(let message):
                BackStateScaffold(title: "합류할까요?", onBack: onDismiss) {
                    ErrorBox(message: message, onRetry: { viewModel.refresh() })
                }
            case .success(let ride):
                JoinConfirmScreen(
                    ride: ride,
                    pickupDistanceMeters: pickupDistanceMeters(ride: ride, myLocation: myLocation.coordinates),
                    joining: join.joining,
                    joinErrorMessage: join.errorMessage,
                    onDismiss: onDismiss,
                    onConfirmJoin: { _ in viewModel.join() },
                    // 이미 그 방 멤버면 합류를 다시 시도할 이유가 없다 — **합류 성공과 같은 길**로 보낸다.
                    // 서버가 409 `ALREADY_JOINED` 를 돌려줬을 때 이미 이렇게 처리하고 있어(ViewModel.join 의
                    // isAlreadyInThisParty 분기) 새 네비게이션 인자가 필요 없다. partyId 는 이 Route 가
                    // 들고 있는 값이라 화면이 들고 있는 Ride 를 다시 쓰지 않는다.
                    onOpenJoinedRide: { _ in onJoined(partyId) },
                    onMemberClick: onMemberClick
                )
            }
        }
        .myLocationEffect($myLocation)
        .task(id: join.joinedPartyId) {
            if let joinedPartyId = join.joinedPartyId { onJoined(joinedPartyId) }
        }
    }
}
