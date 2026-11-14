import FeatureAuth
import FeatureChat
import FeatureExplore
import FeatureHome
import FeatureMatching
import FeatureMyPage
import FeatureOnboarding
import MoyeotaDesignSystem
import MoyeotaDomain
import Observation
import PresentationCore
import SwiftUI

// 37 탈퇴 중 세션이 사라졌을 때 **탈퇴 응답을 기다리는 한도**. 기다리는 대상은 04a 로그인 화면의
// 안내 문구 하나뿐이고(화면 이동은 어차피 일어난다), 실제로는 한두 프레임이면 결론이 난다.
// 끝내 못 기다리면 「탈퇴됐다」도 「세션이 만료됐다」도 말하지 않는다(둘 중 하나는 거짓말이다).
private let ACCOUNT_DELETE_RESULT_WAIT_MS: Int64 = 200
private let ACCOUNT_DELETE_RESULT_POLL_MS: Int64 = 16

// 16 뒤를 덮는 어둡기. 원본은 대화상자 창이 깔아 주는 플랫폼 기본값이고 상태 표시줄·홈 인디케이터 줄에서 15 가 어둡게 비쳐 보인다
// (`_workspace/screenshots/config-change/16_modal_portrait.png`). 다른 대화상자 오버레이와 같은 60% 다.
private let DIALOG_DIM_ALPHA = 0.6

/// `authRepository.authState` 를 화면에 내리는 홀더 — 원본 `collectAsState`.
@MainActor
@Observable
private final class AuthStateHolder {
    private(set) var state: AuthState
    @ObservationIgnored private let scope = ViewModelScope()

    init(repository: any AuthRepository) {
        state = repository.authState.value
        let states = repository.authState.values()
        scope.launch { [weak self] in
            for await state in states {
                self?.state = state
            }
        }
    }
}

/// 테스트가 화면 밖에서 상태를 보고 37·35 콜백 자리의 표시를 세우는 입구. 앱은 넘기지 않는다.
@MainActor
final class MainNavGraphProbe {
    var navController: MoyeotaNavController?
    var activePartyViewModel: ActivePartyViewModel?
    var signOutNotices: [String?] = []
    var markLogoutRequested: () -> Void = {}
    var markDeleteRequested: () -> Void = {}
    var markDeleted: () -> Void = {}
    var markDeleteKept: () -> Void = {}
}

/// 앱의 진입 라우팅. 세션이 확정되기 전에는 어떤 화면도 열지 않는다.
///
/// `AuthState.unknown` 은 "아직 저장소에서 토큰을 못 읽었다"는 뜻이지 미로그인이 아니다.
/// 이걸 미로그인으로 취급하면 이미 로그인한 사용자가 앱을 켤 때마다 온보딩을 스쳐 본다.
/// 확정된 뒤에야 `MainNavHost` 를 만들고, 그 시점의 상태가 시작 화면을 정한다.
public struct MainNavGraph: View {
    private let authRepository: any AuthRepository
    private let appConfigRepository: any AppConfigRepository
    private let rideRepository: any RideRepository
    private let placeRepository: any PlaceRepository
    private let chatRepository: any ChatRepository
    private let activePartyRepository: any ActivePartyRepository
    private let rideRecordRepository: any RideRecordRepository
    private let noShowRepository: any NoShowRepository
    private let pendingChatRoomId: Int64?
    private let onPendingChatRoomHandled: () -> Void
    private let installedVersionCode: Int64
    private let probe: MainNavGraphProbe?

    @HostedViewModel private var authState: AuthStateHolder

    /// - Parameters:
    ///   - rideRecordRepository: 34 지난 탑승 기록(`GET /api/v1/users/me/parties`).
    ///
    ///     **필수 인자다.** 기본값을 두면 배선을 빠뜨린 호출부가 컴파일에서 걸리지 않고 **실행 중에만** 34 가
    ///     「불러오지 못했어요」로 떨어진다 — 그 실패는 서버 장애와 구분되지 않는다.
    ///   - noShowRepository: 38 노쇼 기록·이의 신청(`GET /api/v1/matching/no-shows`).
    ///
    ///     **필수 인자다** — `rideRecordRepository` 와 같은 이유다. 기본값을 두면 배선을 빠뜨렸을 때
    ///     컴파일이 통과하고 **실행 중에만** 38 이 빈 화면으로 떨어진다. 그 화면은 노쇼로 찍힌 사람이
    ///     이의를 낼 **유일한 창구**라, 조용히 비어 있는 것이 가장 나쁜 실패다.
    ///   - pendingChatRoomId: 채팅 알림 탭으로 열어 달라는 방. 로그인돼 있고 그래프가 준비되면 그 채팅방을 **스택에 쌓고**
    ///     `onPendingChatRoomHandled` 로 소비를 알린다. 미로그인이면 무시한다(로그인 뒤 엉뚱한 방을 여는 것보다 낫다).
    ///   - installedVersionCode: 강제 업데이트 게이트가 비교할 설치 버전.
    public init(
        authRepository: any AuthRepository,
        appConfigRepository: any AppConfigRepository,
        rideRepository: any RideRepository,
        placeRepository: any PlaceRepository,
        chatRepository: any ChatRepository,
        activePartyRepository: any ActivePartyRepository,
        rideRecordRepository: any RideRecordRepository,
        noShowRepository: any NoShowRepository,
        pendingChatRoomId: Int64? = nil,
        onPendingChatRoomHandled: @escaping () -> Void = {},
        installedVersionCode: Int64 = appVersionCode()
    ) {
        self.init(
            authRepository: authRepository,
            appConfigRepository: appConfigRepository,
            rideRepository: rideRepository,
            placeRepository: placeRepository,
            chatRepository: chatRepository,
            activePartyRepository: activePartyRepository,
            rideRecordRepository: rideRecordRepository,
            noShowRepository: noShowRepository,
            pendingChatRoomId: pendingChatRoomId,
            onPendingChatRoomHandled: onPendingChatRoomHandled,
            installedVersionCode: installedVersionCode,
            probe: nil
        )
    }

    init(
        authRepository: any AuthRepository,
        appConfigRepository: any AppConfigRepository,
        rideRepository: any RideRepository,
        placeRepository: any PlaceRepository,
        chatRepository: any ChatRepository,
        activePartyRepository: any ActivePartyRepository,
        rideRecordRepository: any RideRecordRepository,
        noShowRepository: any NoShowRepository,
        pendingChatRoomId: Int64?,
        onPendingChatRoomHandled: @escaping () -> Void,
        installedVersionCode: Int64,
        probe: MainNavGraphProbe?
    ) {
        self.authRepository = authRepository
        self.appConfigRepository = appConfigRepository
        self.rideRepository = rideRepository
        self.placeRepository = placeRepository
        self.chatRepository = chatRepository
        self.activePartyRepository = activePartyRepository
        self.rideRecordRepository = rideRecordRepository
        self.noShowRepository = noShowRepository
        self.pendingChatRoomId = pendingChatRoomId
        self.onPendingChatRoomHandled = onPendingChatRoomHandled
        self.installedVersionCode = installedVersionCode
        self.probe = probe
        _authState = HostedViewModel(wrappedValue: AuthStateHolder(repository: authRepository))
    }

    public var body: some View {
        MoyeotaTheme {
            if authState.state == .unknown {
                SplashScreen()
                    .ignoresSafeArea(.container)
            } else {
                MainNavHost(
                    loggedIn: isLoggedIn(authState.state),
                    authRepository: authRepository,
                    appConfigRepository: appConfigRepository,
                    rideRepository: rideRepository,
                    placeRepository: placeRepository,
                    chatRepository: chatRepository,
                    activePartyRepository: activePartyRepository,
                    rideRecordRepository: rideRecordRepository,
                    noShowRepository: noShowRepository,
                    pendingChatRoomId: pendingChatRoomId,
                    onPendingChatRoomHandled: onPendingChatRoomHandled,
                    installedVersionCode: installedVersionCode,
                    probe: probe
                )
            }
        }
    }

    private func isLoggedIn(_ state: AuthState) -> Bool {
        if case .authenticated = state { return true }
        return false
    }
}

/// 원본 `MainNavHost` 의 앞부분 — 화면 스택 바깥에 살아야 하는 것들과 강제 업데이트 게이트.
///
/// 게이트 아래(`MainNavContent`)를 뷰 하나로 뗀 이유: 원본은 게이트에 걸리면 그 아래의 `remember` 와 효과가 컴포지션에서
/// 통째로 빠진다. 뷰로 나누면 `@State` 와 `.task` 가 같은 시점에 함께 사라진다.
private struct MainNavHost: View {
    let loggedIn: Bool
    let authRepository: any AuthRepository
    let appConfigRepository: any AppConfigRepository
    let rideRepository: any RideRepository
    let placeRepository: any PlaceRepository
    let chatRepository: any ChatRepository
    let activePartyRepository: any ActivePartyRepository
    let rideRecordRepository: any RideRecordRepository
    let noShowRepository: any NoShowRepository
    let pendingChatRoomId: Int64?
    let onPendingChatRoomHandled: () -> Void
    let installedVersionCode: Int64
    let probe: MainNavGraphProbe?

    // 로그인 상태는 앱을 켤 때 한 번만 시작 화면을 정한다. 이후 전이는 `MainNavContent` 의 효과가 다룬다
    // — 시작 화면을 계속 따라가게 만들면 스택이 통째로 재생성돼 백스택이 날아간다.
    @HostedViewModel private var navController: MoyeotaNavController

    // 로그인 사용자의 이름 — 스택 바깥에 두어 홈·마이가 한 인스턴스를 공유한다.
    // 화면별 뷰모델로 두면 탭을 오갈 때마다 같은 조회가 반복된다.
    @HostedViewModel private var profileViewModel: UserProfileViewModel

    // 서버 운영 설정(`GET /api/v1/config`). 지금 이 값이 정하는 것은 **강제 업데이트 게이트 하나뿐**이다
    // — 동승/택시 모드(`taxiEnabled`)는 기사·배차와 함께 사라졌고, 그래서 화면이 따를 값과 서버가 준 값을
    // 가르던 디버그 강제값도 함께 지웠다(AppConfigViewModel 주석).
    @HostedViewModel private var appConfigViewModel: AppConfigViewModel

    // 「지금 내가 타고 있는 방」 — 홈·합승 배너, 앱 시작 시 단계 복귀가 같은 값을 본다.
    // profileViewModel 과 같은 이유로 스택 바깥에 둔다(탭을 옮길 때마다 재조회하지 않게).
    @HostedViewModel private var activePartyViewModel: ActivePartyViewModel

    init(
        loggedIn: Bool,
        authRepository: any AuthRepository,
        appConfigRepository: any AppConfigRepository,
        rideRepository: any RideRepository,
        placeRepository: any PlaceRepository,
        chatRepository: any ChatRepository,
        activePartyRepository: any ActivePartyRepository,
        rideRecordRepository: any RideRecordRepository,
        noShowRepository: any NoShowRepository,
        pendingChatRoomId: Int64?,
        onPendingChatRoomHandled: @escaping () -> Void,
        installedVersionCode: Int64,
        probe: MainNavGraphProbe?
    ) {
        self.loggedIn = loggedIn
        self.authRepository = authRepository
        self.appConfigRepository = appConfigRepository
        self.rideRepository = rideRepository
        self.placeRepository = placeRepository
        self.chatRepository = chatRepository
        self.activePartyRepository = activePartyRepository
        self.rideRecordRepository = rideRecordRepository
        self.noShowRepository = noShowRepository
        self.pendingChatRoomId = pendingChatRoomId
        self.onPendingChatRoomHandled = onPendingChatRoomHandled
        self.installedVersionCode = installedVersionCode
        self.probe = probe
        _navController = HostedViewModel(
            wrappedValue: MoyeotaNavController(startDestination: loggedIn ? .home : .onboardingSaving)
        )
        _profileViewModel = HostedViewModel(wrappedValue: UserProfileViewModel(repository: authRepository))
        _appConfigViewModel = HostedViewModel(wrappedValue: AppConfigViewModel(repository: appConfigRepository))
        _activePartyViewModel = HostedViewModel(
            wrappedValue: ActivePartyViewModel(
                activePartyRepository: activePartyRepository,
                chatRepository: chatRepository
            )
        )
    }

    var body: some View {
        let activePartyViewModel = self.activePartyViewModel
        let appConfigViewModel = self.appConfigViewModel
        let _ = probe?.navController = navController
        let _ = probe?.activePartyViewModel = activePartyViewModel
        ZStack {
            // ── 강제 업데이트 게이트 ──
            // 서버가 「이 버전은 더 못 쓴다」고 답하면 **스택을 세우지 않는다**. 스택이 없으면
            // 뒤로가기로 갈 수 있는 앱 화면 자체가 없어서, 오버레이+가로채기처럼 그리는 순서에
            // 기대지 않아도 된다.
            //
            // 설정은 비동기로 오므로 이 판정은 **앱 시작 몇 초 뒤에 바뀔 수 있다.** 그때 스택이
            // 헐리는 것은 의도한 동작이다 — 서버가 못 쓴다고 한 버전으로 합승을 계속 진행시키는 쪽이
            // 더 나쁘다. 설정을 못 받았거나(기본값 nil) 서버가 필드를 안 주면 여기는 통과한다.
            if updateRequirement(config: appConfigViewModel.config, installedVersionCode: installedVersionCode) == .blocked {
                UpdateRequiredScreen()
                    .ignoresSafeArea(.container)
            } else {
                MainNavContent(
                    loggedIn: loggedIn,
                    navController: navController,
                    profileViewModel: profileViewModel,
                    appConfigViewModel: appConfigViewModel,
                    activePartyViewModel: activePartyViewModel,
                    authRepository: authRepository,
                    rideRepository: rideRepository,
                    placeRepository: placeRepository,
                    chatRepository: chatRepository,
                    activePartyRepository: activePartyRepository,
                    rideRecordRepository: rideRecordRepository,
                    noShowRepository: noShowRepository,
                    pendingChatRoomId: pendingChatRoomId,
                    onPendingChatRoomHandled: onPendingChatRoomHandled,
                    probe: probe
                )
            }
        }
        // 합류 시점에 생기는 채팅방을 뒤늦게라도 잡는다(21 의 「채팅 열기」가 이 값으로 뜬다).
        // 뷰 수명이라 화면이 사라지면 함께 멈춘다.
        .task { await activePartyViewModel.pollChatRoom() }
        // 위 폴링(10초 주기 `GET /chat-rooms/me`)을 **앱이 백그라운드로 가면 멈춘다.**
        // 뷰 수명만으로는 부족하다 — 이 뷰모델과 스택은 앱 루트라 홈 버튼을 눌러도 살아 있어서,
        // 배선이 없으면 앱을 쓰지 않는 동안에도 10초마다 요청이 나간다
        // (17 탐색의 4초 폴링과 같은 종류의 누수다).
        .lifecycleEffect(
            onStart: { activePartyViewModel.onHostStart() },
            onStop: { activePartyViewModel.onHostStop() }
        )
        // 앱을 다시 앞으로 가져올 때마다 재조회한다 — 배경에 있는 동안 방이 끝났을 수 있다.
        // 탭 진입마다의 재조회는 각 화면(홈·합승)의 `.task` 가 따로 건다.
        .lifecycleEffect(onStart: {
            activePartyViewModel.refresh()
            // 시작 시 설정 조회가 실패했으면(서버 장애 등) 복귀할 때 다시 받는다 —
            // 그동안은 기준이 nil 인 기본값이라 아무도 업데이트 게이트에 막히지 않는다
            appConfigViewModel.loadIfUnresolved()
        })
    }
}

// v15 와이어프레임 35화면 이동 규칙을 한곳에서 배선한다.
// 각 화면은 콜백만 노출하는 순수 뷰 — 화면 안에는 내비게이션 코드가 없다.
//
// **`@State` 인 값들**: 원본은 회전·다크모드 전환을 견디려고 `rememberSaveable` 로 둔 것들이 있다. iOS 는 세로 고정이고
// 시스템 설정 변경이 뷰를 다시 만들지 않으며 프로세스가 죽으면 스택도 사라지므로 `@State` 면 같은 약속이 지켜진다.
private struct MainNavContent: View {
    let loggedIn: Bool
    let navController: MoyeotaNavController
    let profileViewModel: UserProfileViewModel
    let appConfigViewModel: AppConfigViewModel
    let activePartyViewModel: ActivePartyViewModel
    let authRepository: any AuthRepository
    let rideRepository: any RideRepository
    let placeRepository: any PlaceRepository
    let chatRepository: any ChatRepository
    let activePartyRepository: any ActivePartyRepository
    let rideRecordRepository: any RideRecordRepository
    let noShowRepository: any NoShowRepository
    let pendingChatRoomId: Int64?
    let onPendingChatRoomHandled: () -> Void
    let probe: MainNavGraphProbe?

    // ── 화면 사이에 넘겨야 하는 값 ──
    // 10 프로필 만들기가 채우는 가입 정보 — 12 매너 서약에서 제출한다.
    //
    // **뷰 수명 내내 살아남아야 한다.** 원본에서 이 값이 `remember` 였던 탓에 구성 변경 뒤 초안이 빈 `SignupDraft` 로 리셋돼,
    // 「동의하고 가입 완료」가 `toNewUser() == nil` → 「가입 정보가 부족해요」에서 더 나아가지 못했다 — 사용자는 **가입 직전에
    // 원인 불명의 거절**을 본다.
    @State private var signupDraft = SignupDraft()
    // 12 가 가입에서 PHONE_NOT_VERIFIED 를 받고 10 으로 되돌려 보낸 횟수.
    // 10 은 이 값이 바뀔 때마다 문자 인증 블록을 초기화한다 — 토큰이 서버에서 이미 죽었기 때문이다.
    // Bool 이 아니라 카운터인 이유: 같은 일이 두 번 일어날 수 있고(새 토큰도 또 만료될 수 있다),
    // Bool 이면 두 번째 신호가 "이미 true" 에 묻혀 10 이 알아채지 못한다.
    //
    // **카운터라서 남아 있어야 한다.** 비교 상대인 `PhoneVerifyViewModel.handledReverifyRequest` 는 뷰모델이라 값을 유지하는데,
    // 이쪽만 0 으로 돌아가면 그 뒤의 재인증 신호가 「이미 처리한 번호」로 조용히 버려진다.
    @State private var reverifyPhoneRequest = 0
    // 로그인 화면으로 돌아온 이유. 세션 만료일 때만 채워지고 사용자가 스스로 로그아웃하면 비운다.
    @State private var signOutNotice: String?

    /// 04b 에서 찾았거나 04c 에서 비밀번호를 바꾼 아이디. 04a 로 돌아왔을 때 아이디 칸을 채우고,
    /// 04b → 04c 로 건너갈 때 04c 의 아이디 칸도 채운다. 로그인에 성공하면 버린다.
    @State private var recoveredLoginId: String?
    @State private var logoutRequested = false
    // ── 37 탈퇴의 두 표시 ──
    //
    // 하나로 두면 안 된다. 예전에는 **요청을 보내기 직전에** 세우는 플래그 하나였는데, 그 값은
    // "204 를 받았다"가 아니라 "요청을 보냈다"는 뜻이었다. `DELETE /users/me` 가 401 → 재발급 실패로
    // 끝나면 세션이 사라지면서 아래 전이 감지가 돌고, **계정이 살아 있는데** 로그인 화면에
    // 「탈퇴가 처리됐어요」가 떴다(2026-10-28 결함). 그래서 「보냈다」와 「됐다」를 가른다.
    //
    // `accountDeleteRequested` = 요청을 보냈고 결과를 아직 모른다. 실패하면 AccountDeleteRoute 가
    // 되돌린다 — 안 되돌리면 나중의 진짜 세션 만료가 조용해진다.
    @State private var accountDeleteRequested = false
    // `accountDeleted` = 서버가 204 를 돌려줬다. **「탈퇴가 처리됐어요」의 유일한 근거다.**
    @State private var accountDeleted = false
    // 14 홈이 넘기는 첫 검색어 — 15 는 이 값을 첫 진입에 한 번만 읽고
    // (DestinationRoute: `state.query.isBlank` 일 때만) 그 뒤 검색어는 뷰모델이 들고 있다.
    @State private var searchInitialQuery = ""
    // 15 에서 고른 출발지·도착지(좌표 포함) — 16 방 생성에 필요하다.
    // 15 는 출발지(고른 곳 또는 실위치)가 있어야만 16 으로 넘긴다. 15 를 거치지 않은 복원 진입이면 nil — 16 이 안내만 한다.
    //
    // **살아남아야 한다.** 이 값이 사라지면 방금 고른 경로가 없어져 「출발지가 없어요. 15 목적지 화면에서 출발지를 검색해 주세요」가
    // 뜬다 — 이미 끝낸 단계를 다시 하라는 안내다.
    @State private var confirmedOrigin: Place?
    @State private var confirmedDestination: Place?

    // 17 예약 날짜 검색의 **도착지 필터**. nil 이면 출발지만으로 찾는다.
    //
    // 서버는 도착지를 **둘 다 또는 둘 다 없이** 받고(400 `INCOMPLETE_DESTINATION`), 보내면
    // 도착지도 1km 안인 방(`destinationNearby`)을 먼저 준다. 그래서 「없음」이 정상 상태다 —
    // 기본값을 지어내면 사용자가 고르지 않은 조건으로 걸러진 목록을 보게 된다.
    //
    // 원본이 `rememberSaveable` 이 아니라 `remember` 인 이유: 검색 조건이라 프로세스가 죽었다 살아나면
    // **지워지는 쪽이 맞다.** 되살리면 날짜는 초기화됐는데 도착지만 남아 사용자가 고르지 않은 조합이 된다.
    // iOS 의 `@State` 는 프로세스와 함께 사라지므로 위 값들과 같은 선언이 그 약속을 지킨다.
    @State private var reservationSearchDestination: Place?

    // 15 를 **도착지 필터를 고르러** 열었는가. 평소(홈 검색·방 만들기)에는 false 라 고른 뒤 16 으로 간다.
    //
    // 깃발을 쓰는 이유: 15 는 한 화면인데 **돌아갈 곳이 둘**이다(16 모달 / 17 필터). 라우트를 둘로
    // 쪼개면 같은 화면이 두 벌이 되고, 15 가 들고 있는 검색 상태도 갈린다.
    @State private var pickingSearchDestination = false
    // 「방금 끝난 방」을 잡아 두던 `finishedRide` 는 지웠다 — 그 값의 유일한 독자가 33 도착 완료
    // 화면이었고, 그 화면은 26 운행 중과 함께 사라졌다(서버가 운행 종료를 보낼 수 없다).
    // 이제 방이 끝나면 21 이 `onPartyClosed` 로 알려 주고, 사용자는 요약 없이 14 홈으로 간다.
    //
    // ── 방 id 는 살아남아야 한다 (selectedPartyId · createdPartyId) ──
    //
    // 원본은 이 id 들이 구성 변경에 null 로 돌아가 라우트가 「어느 방인지 모르는」 상태가 됐고, 21 은 그 상태에서 예시 방을
    // 그려 **남의 가짜 방**을 보여 줬다(출시 차단 결함, 2026-10-15).
    @State private var selectedPartyId: Int64?
    // 20·22 에서 탭한 동승자 — 23 프로필이 이 값을 그린다.
    // 라우트 인자로 넘기지 않는 이유: User 는 방 상세 응답의 일부라 id 만 넘기면 23 이 방을 다시
    // 조회해야 하는데, 그 조회 API 는 "멤버 한 명"이 아니라 방 전체다.
    //
    // 원본도 일부러 저장 상태에 넣지 않는다. 23 은 nil 이면 예시 프로필을 그리는 대신 사실대로 말하고 되돌린다.
    @State private var selectedPartner: User?
    // 16 에서 만든 방 — 21 매칭 대기가 이 방을 조회한다. 위 selectedPartyId 와 같은 이유로 남긴다
    @State private var createdPartyId: Int64?

    // 16 도착지 확인을 **시간 정하기로 열까.** 17 탐색의 예약 탭에서 「새 동승 방 만들기」를 누른
    // 경우에만 참이다.
    //
    // 깃발을 쓰는 이유: 15 → 16 은 두 걸음이고 그 사이에 출발지·도착지가 정해진다. 경로 인자로
    // 실어 나르면 두 라우트의 주소가 모두 바뀌는데, 이 값은 **어디서 눌렀는지**일 뿐 화면의
    // 정체성이 아니다. `selectedPartyId`·`createdPartyId` 와 같은 자리에 같은 이유로 둔다
    // (15 가 위에 쌓여도 남아야 하므로 `@State` — 이 뷰 머리의 `@State` 설명).
    //
    // **16 에 들어가지 않는 길에서는 반드시 내린다** — 홈 검색으로 들어온 사람이 직전에 예약 탭을
    // 봤다는 이유로 시간 정하기 화면을 받으면 안 된다.
    @State private var createScheduled = false
    // 탐색용 selectedPartyId 와 진행용 createdPartyId 는 **일부러 둘이다** — 탐색 중 다른 방을 눌러도
    // 내가 들어 있는 방이 바뀌면 안 된다.
    //
    // 셋이었다. `activePartyId`(「지금 배차·운행 중인 방」)는 25 배차 현황·26 운행 중·27 신고가 읽던
    // 값이고, 그 세 화면이 사라지면서 독자가 하나도 남지 않아 함께 지웠다 — 쓰이지 않는 세 번째 방 id 를
    // 남겨 두면 「어느 값이 진짜 내 방인가」가 다시 두 갈래가 된다.
    // 로그인 → 미로그인 전이 감지용 직전 값.
    @State private var wasLoggedIn: Bool
    // 진행 중 방 자동 복귀의 빗장. 복귀 효과가 세우고 로그아웃 전이가 되돌린다 — 쓰임은 복귀 효과의 주석에 적었다.
    @State private var startupStageHandled = false
    // 직전 갱신까지 경로에 쌓여 있던 칸 수(`startsCovered`). 값이 바뀌어도 다시 그릴 일이 없어 관찰하지 않는 상자에 둔다.
    @State private var renderedPath = RenderedPathDepth()

    private final class RenderedPathDepth {
        var depth = 0
    }

    private struct StageKey: Equatable {
        let resolved: Bool
        let ride: Ride?
    }

    private struct PendingKey: Equatable {
        let roomId: Int64?
        let loggedIn: Bool
    }

    init(
        loggedIn: Bool,
        navController: MoyeotaNavController,
        profileViewModel: UserProfileViewModel,
        appConfigViewModel: AppConfigViewModel,
        activePartyViewModel: ActivePartyViewModel,
        authRepository: any AuthRepository,
        rideRepository: any RideRepository,
        placeRepository: any PlaceRepository,
        chatRepository: any ChatRepository,
        activePartyRepository: any ActivePartyRepository,
        rideRecordRepository: any RideRecordRepository,
        noShowRepository: any NoShowRepository,
        pendingChatRoomId: Int64?,
        onPendingChatRoomHandled: @escaping () -> Void,
        probe: MainNavGraphProbe?
    ) {
        self.loggedIn = loggedIn
        self.navController = navController
        self.profileViewModel = profileViewModel
        self.appConfigViewModel = appConfigViewModel
        self.activePartyViewModel = activePartyViewModel
        self.authRepository = authRepository
        self.rideRepository = rideRepository
        self.placeRepository = placeRepository
        self.chatRepository = chatRepository
        self.activePartyRepository = activePartyRepository
        self.rideRecordRepository = rideRecordRepository
        self.noShowRepository = noShowRepository
        self.pendingChatRoomId = pendingChatRoomId
        self.onPendingChatRoomHandled = onPendingChatRoomHandled
        self.probe = probe
        _wasLoggedIn = State(initialValue: loggedIn)
    }

    private func back() {
        navController.popBackStack()
    }

    private func resetTo(_ route: Route) {
        navController.resetTo(route)
    }

    /// 04b·04c 를 끝내고 04a 로 돌아간다. 둘 다 04a 위에 쌓여 열리므로 그 엔트리로 되돌아가면 되고,
    /// 스택에 없으면(있을 수 없는 경로지만 화면 없는 그래프를 남기지 않으려고) 04a 로 새로 연다.
    private func returnToLoginForm() {
        if !navController.popBackStack(.loginForm, inclusive: false) { resetTo(.loginForm) }
    }

    private func navigateTab(_ tab: MoyeotaTab) {
        navController.navigateTab(tab)
    }

    /// 진행 중인 방의 **지금 단계 화면**으로 보낸다. 배너·채팅방 헤더·앱 시작 복귀가 모두 여기로 모인다.
    /// 목적지 표와 스택 모양은 `MoyeotaNavController.stageRoute`·`navigateToStage(route:)` 에 있다.
    private func navigateToStage(_ ride: Ride) {
        if let id = Int64(ride.id) { createdPartyId = id }
        guard let route = MoyeotaNavController.stageRoute(ride.activeStage) else {
            activePartyViewModel.clearParty()
            navigateTab(.home)
            return
        }
        navController.navigateToStage(route: route)
    }

    private func openActiveChatRoom(_ roomId: Int64) {
        navController.openActiveChatRoom(roomId: roomId)
    }

    /// 21 의 「채팅 열기」. 채팅방을 아직 못 찾았으면 nil 이고 화면이 버튼을 그리지 않는다.
    private var onOpenActiveChat: (() -> Void)? {
        activePartyViewModel.chatRoomId.map { roomId in { openActiveChatRoom(roomId) } }
    }

    private func openActiveStage() {
        if let ride = activePartyViewModel.ride { navigateToStage(ride) }
    }

    /// 로그인 → 미로그인 전이는 두 경로로 온다: 사용자의 로그아웃, 그리고 재발급까지 실패한 세션 만료.
    /// 어느 화면에 있든 결과는 같아야 하므로 개별 화면이 아니라 여기 한 곳에서 처리한다
    /// (별도 이벤트 채널은 없다 — authState 스트림이 유일한 통보 경로다).
    private func handleLoginTransition() async {
        if wasLoggedIn && !loggedIn {
            // 37 탈퇴 요청이 떠 있으면 **결과를 기다린다.** 세션이 사라진 이유가 탈퇴 성공(204)인지
            // 탈퇴 중 세션 만료(401 → 재발급 실패)인지를 가릴 수 있는 사실은 그 응답뿐인데, 두 경로의
            // 도착 순서가 보장되지 않는다. 기다리지 않고 「요청을 보냈다」만 보고
            // 판단하면 계정이 살아 있는데 「탈퇴가 처리됐어요」가 뜬다(2026-10-28 결함).
            // 실패는 AccountDeleteRoute 의 catch 가 `accountDeleteRequested` 를 즉시 되돌리므로
            // 그쪽 경로에서는 사실상 기다리지 않는다.
            var waitedMs: Int64 = 0
            while accountDeleteRequested && !accountDeleted && waitedMs < ACCOUNT_DELETE_RESULT_WAIT_MS {
                do {
                    try await Task.sleep(for: .milliseconds(ACCOUNT_DELETE_RESULT_POLL_MS))
                } catch {
                    return
                }
                waitedMs += ACCOUNT_DELETE_RESULT_POLL_MS
            }
            // 네 경로가 같은 전이로 들어온다 — 탈퇴 성공 · 탈퇴 중 세션 만료 · 사용자의 로그아웃 ·
            // 재발급까지 실패한 세션 만료. 안내가 서로 달라야 한다: 스스로 탈퇴한 사람에게
            // 「세션이 만료됐어요」는 오해를 주고, 아무 안내도 없으면 탈퇴가 처리된 건지 알 수 없다.
            let notice: String? = if accountDeleted {
                // 204 를 받았을 때만 탈퇴를 말한다
                "탈퇴가 처리됐어요. 그동안 이용해 주셔서 고마웠어요"
            } else if accountDeleteRequested {
                // 요청은 보냈는데 결과를 끝내 못 봤다 — **아무 말도 하지 않는다.** 둘 중 하나는
                // 거짓말이고(탈퇴됐는지 모른다), 사용자가 할 일은 어느 쪽이든 로그인 시도뿐이다.
                nil
            } else if logoutRequested {
                nil
            } else {
                "세션이 만료됐어요. 다시 로그인해 주세요"
            }
            signOutNotice = notice
            probe?.signOutNotices.append(notice)
            accountDeleted = false
            accountDeleteRequested = false
            logoutRequested = false
            // 로컬 기억은 남긴다(계정에 매인 값이라 같은 계정 재로그인 시 되살아나야 한다) —
            // 화면이 들고 있던 값만 버린다. 탈퇴는 예외로 디스크 기억까지 지우는데, 그건 여기가 아니라
            // AuthRepository.deleteAccount 가 세션을 비우면서 함께 한다(계정이 사라져 되살아날 길이 없다).
            activePartyViewModel.forget()
            // 진행 중 방 복귀의 빗장도 되돌린다. `ActivePartyViewModel` 은 앱 루트라
            // 로그아웃 뒤에도 살아 있고 `forget()` 이 resolvedOnce 를 되돌리므로, **같은 프로세스에서
            // 재로그인**하면 복귀 판단이 다시 돌아야 한다 — 빗장만 true 로 남으면 진행 중인 방이
            // 있어도 홈에 떨어진다.
            startupStageHandled = false
            navController.resetAfterSignOut(.loginForm)
        }
        wasLoggedIn = loggedIn
    }

    /// 앱을 껐다 켜도 매칭 화면으로 돌아온다 — 첫 `ActivePartyViewModel.resolve` 가 끝난 뒤 딱 한 번.
    ///
    /// `resolvedOnce` 를 기다리는 이유는 「아직 모른다」와 「없다」가 둘 다 nil 이기 때문이다. 이미 사용자가 홈을 떠났으면
    /// 끼어들지 않는다 — 켜자마자 목적지를 검색하는 사람의 화면을 빼앗는 것이 복귀보다 나을 리 없다.
    ///
    /// 복귀는 한 번만 하지만, 그 「한 번」을 세는 빗장(`startupStageHandled`)은 **① 실제로 복귀했을 때
    /// ② 사용자가 홈을 떠났을 때**만 선다. 방을 보기 전에 미리 세우면 「조회 실패」와 「방 없음」이
    /// 같아진다 — `resolve()` 는 네트워크 실패에도 nil 을 주므로(`ActivePartyViewModel` 주석:
    /// Loading/Error 3상태가 없다), 서버가 살아난 뒤 재조회로 방을 찾아도 복귀하지 않고 위 약속이
    /// 조용히 깨졌다. 홈에 머무는 동안은 창을 열어 두어 늦게라도 복귀하게 한다.
    private func handleStartupStage() {
        if !loggedIn || startupStageHandled || !activePartyViewModel.resolvedOnce { return }
        // 원본의 `currentDestination == null → delay(100)` 은 NavHost 가 그래프를 세우기 전의 틈을 메운다. 이 컨트롤러는 만들 때
        // 시작 화면을 갖고 있어 그 틈이 없다. 빈 스택(목적지 없음)이면 원본처럼 판단을 미룬다 — 빗장도 세우지 않는다.
        guard let route = navController.currentRoute else { return }
        if route != .home {
            // 사용자가 이미 홈을 떠났다 = 시작 복귀의 창이 닫혔다. **여기서 빗장을 건다.** 안 걸면
            // 방을 만들어 21 로 올라간 뒤 「방을 두고 홈으로」 돌아올 때(홈 진입의 refresh() 가 ride 를
            // 갱신해 이 효과가 다시 돈다) 방금 떠난 화면으로 사용자를 되끌어 올린다.
            startupStageHandled = true
            return
        }
        guard let ride = activePartyViewModel.ride else { return }
        startupStageHandled = true
        navigateToStage(ride)
    }

    /// 채팅 알림 탭 → 그 채팅방. 미로그인이면 소비만 하고 지나간다 — 로그인 화면을 채팅방으로 덮을 순 없다.
    private func handlePendingChatRoom() {
        guard let roomId = pendingChatRoomId else { return }
        if !loggedIn {
            onPendingChatRoomHandled()
            return
        }
        navController.openPendingChatRoom(roomId: roomId)
        onPendingChatRoomHandled()
    }

    var body: some View {
        let projection = projectBackStack(navController.backStack)
        ZStack {
            NavigationStack(
                path: Binding(
                    get: { projection.path },
                    set: { navController.applyPoppedPath($0) }
                )
            ) {
                Group {
                    if let root = projection.root {
                        screen(root)
                    } else {
                        // 원본의 「화면 없는 빈 그래프」. 뒤로가기 가드 덕분에 닿을 일이 없는 자리다.
                        Color.clear
                    }
                }
                .background(BackGestureBridge(pathCount: projection.path.count))
                .navigationDestination(for: NavBackStackEntry.self) { entry in
                    screen(entry)
                }
            }
            .ignoresSafeArea(.container)

            // 16 은 15 위에 뜨는 모달 — 스크림 탭·닫기로만 닫힌다. 쌓지 않고 얹어 15 가 스크림 뒤에 그대로 보인다.
            //
            // 모달은 **화면 끝까지** 그린다(디자인 QA S16-1 — 모달 안의 `.ignoresSafeArea(.container)`, 원본은 대화상자 창의
            // `decorFitsSystemWindows = false`). 그래서 모달의 `StatusBarSpacer`·`NavigationBarSpacer` 가 실제 인셋을 받아 두 바
            // 자리를 흰색으로 칠한다. 원본은 그 창에서만 시스템 바 아이콘을 어둡게 바꾸지만(`DialogLightSystemBars`) 여기는 같은
            // 창이고 앱이 라이트 모드 고정이라 상태바 글자가 이미 어둡다. 원본 대화상자는 시스템 뒤로가기로 닫히므로 스와이프도 같게 닫는다.
            if let overlay = projection.overlay {
                ZStack {
                    Color.black.opacity(DIALOG_DIM_ALPHA)
                        .ignoresSafeArea(.container)
                        .onTapGesture { back() }
                    destination(overlay)
                        .id(overlay.id)
                }
                .moyeotaBackHandler { back() }
                .accessibilityAddTraits(.isModal)
                // 원본 대화상자는 창이 따로라 창 포커스를 가져간다. 여기는 같은 창이라 15 검색칸이 first responder 로 남아 키보드가
                // 16 을 덮고 밀어 올린다. 16 에는 입력 칸이 없으므로 뜨는 순간 내린다. 닫혀도 다시 올리지 않는다(docs/IOS-DIFFERENCES.md).
                .background(VisibleTopProbe { $0.endEditing(true) })
            }
        }
        .onChange(of: projection.path.count, initial: true) { _, count in
            renderedPath.depth = count
        }
        // 화면 조회(`view_screen`)는 **여기 한 곳**에서만 기록한다. 화면마다 `onAppear` 로 심지 않는 이유는
        // `isTopStackEntry` 주석에 있다 — `NavigationStack` 은 덮인 화면에도 `onAppear` 를 다시 부른다.
        // 스택의 맨 위(`currentRoute`)가 바뀐 순간이 곧 「사용자가 그 화면을 봤다」이고, 16 대화상자도 맨 위라 함께 잡힌다.
        // 이름은 인자를 채우기 전 패턴(`Route.destination`)이라 채팅방 id 가 섞이지 않는다.
        .onChange(of: navController.currentRoute, initial: true) { _, route in
            guard let route else { return }
            Analytics.track(.screenViewed(screen: route.destination))
        }
        .onAppear {
            probe?.markLogoutRequested = { logoutRequested = true }
            probe?.markDeleteRequested = { accountDeleteRequested = true }
            probe?.markDeleted = { accountDeleted = true }
            probe?.markDeleteKept = { accountDeleteRequested = false }
        }
        // 어느 화면에 있든 볼 수 있어야 하므로 화면이 아니라 호스트에 건다.
        .task(id: loggedIn) { await handleLoginTransition() }
        .task(id: StageKey(resolved: activePartyViewModel.resolvedOnce, ride: activePartyViewModel.ride)) {
            handleStartupStage()
        }
        .task(id: PendingKey(roomId: pendingChatRoomId, loggedIn: loggedIn)) {
            handlePendingChatRoom()
        }
    }

    /// 스택에 들어가는 화면의 공통 틀. 시스템 바 없이 가장자리까지 그린다 — 화면들은 `StatusBarSpacer`·`NavigationBarSpacer` 로
    /// 직접 비운다. 스택 바깥의 `ignoresSafeArea` 는 쌓인 화면까지 닿지 않아(각자 자기 호스팅 컨트롤러의 안전 영역을 받는다) 칸마다 건다.
    ///
    /// `.id` 가 원본의 「엔트리마다 컴포지션」 자리다 — `resetTo(.home)` 으로 새 칸이 서면 같은 라우트라도 화면 상태를 새로 시작한다.
    private func screen(_ entry: NavBackStackEntry) -> some View {
        CoveredEntryGate(startsCovered: startsCovered(entry), isTop: isTopEntry(entry)) {
            destination(entry)
                .environment(\.isTopStackEntry, isTopEntry(entry))
        }
        .id(entry.id)
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .ignoresSafeArea(.container)
    }

    /// 이 칸이 지금 만들어지면 **창 밖**인가 — 이유는 `CoveredEntryGate` 에 적었다.
    ///
    /// 맨 위가 아니면 복원으로 함께 들어온 덮인 칸이다. 맨 위라도 경로가 방금 비었으면 뿌리는 아직 빠지는 화면 아래에 있다
    /// (`renderedPath` 는 `onChange` 가 갱신 뒤에 맞추므로 이 시점에는 직전 값이다). 16 은 스택 밖이라 맨 위 판정에 넣지 않는다.
    private func startsCovered(_ entry: NavBackStackEntry) -> Bool {
        guard isTopEntry(entry) else { return true }
        return projectBackStack(navController.backStack).path.isEmpty && renderedPath.depth > 0
    }

    private func isTopEntry(_ entry: NavBackStackEntry) -> Bool {
        let projection = projectBackStack(navController.backStack)
        return entry.id == (projection.path.last ?? projection.root)?.id
    }

    @ViewBuilder
    private func destination(_ entry: NavBackStackEntry) -> some View {
        switch entry.route {
        // A · 온보딩 01–03 — 건너뛰기는 항상 04 로그인
        case .onboardingSaving:
            OnboardingSavingScreen(
                onNext: { navController.navigate(.onboardingTrust) },
                onSkip: { navController.navigate(.login) }
            )
        case .onboardingTrust:
            OnboardingTrustScreen(
                onNext: { navController.navigate(.onboardingSafety) },
                onSkip: { navController.navigate(.login) }
            )
        case .onboardingSafety:
            OnboardingSafetyScreen(
                onStart: { navController.navigate(.login) },
                // 계정이 이미 있는 사람은 가입 플로우가 아니라 로그인으로 보낸다
                onAlreadyHaveAccount: { navController.navigate(.loginForm) },
                onSkip: { navController.navigate(.login) }
            )

        // B · 로그인 04 · 04a
        case .login:
            LoginScreen(
                // 「이메일로 시작하기」 = 가입 시작 → 10 프로필 설정. 소셜(카카오) 로그인은 백엔드에 없어 제공하지 않는다
                onEmailStart: {
                    signupDraft = SignupDraft() // 새 가입은 빈 초안에서 시작
                    // 지난 가입에서 인증 되돌림이 있었어도 새 폼에 그 안내가 남으면 안 된다
                    reverifyPhoneRequest = 0
                    navController.navigate(.profileSetup)
                },
                onLogin: { navController.navigate(.loginForm) }
            )
        case .loginForm:
            LoginFormRoute(
                repository: authRepository,
                onBack: {
                    // 세션 만료·로그아웃으로 스택이 비워진 채 들어왔으면 돌아갈 곳이 없다 — 04 로 보낸다.
                    // 그냥 popBackStack 하면 화면 없는 빈 그래프가 남는다.
                    if navController.previousBackStackEntry != nil { back() } else { resetTo(.login) }
                },
                onLoggedIn: {
                    signOutNotice = nil
                    recoveredLoginId = nil
                    resetTo(.home)
                },
                onSignUp: {
                    signupDraft = SignupDraft()
                    reverifyPhoneRequest = 0
                    navController.navigate(.profileSetup)
                },
                onFindId: { navController.navigate(.findId) },
                onResetPassword: {
                    // 직접 들어가는 재설정은 빈 아이디 칸에서 시작한다 — 지난번에 찾은 아이디를 끌고 가지 않는다
                    recoveredLoginId = nil
                    navController.navigate(.passwordReset)
                },
                prefillLoginId: recoveredLoginId,
                noticeMessage: signOutNotice
            )

        // B · 계정 찾기 04b · 04c (2026-11 신규)
        case .findId:
            FindIdRoute(
                repository: authRepository,
                onBack: back,
                // 가입되지 않은 번호 — 가입으로 보낸다. 04a 의 「가입하기」와 같은 시작이다.
                onSignUp: {
                    signupDraft = SignupDraft()
                    reverifyPhoneRequest = 0
                    navController.navigate(.profileSetup)
                },
                onLogin: { loginId in
                    recoveredLoginId = loginId
                    returnToLoginForm()
                },
                onResetPassword: { loginId in
                    recoveredLoginId = loginId
                    navController.navigate(.passwordReset)
                }
            )
        case .passwordReset:
            PasswordResetRoute(
                repository: authRepository,
                initialLoginId: recoveredLoginId ?? "",
                onBack: back,
                onFindId: { navController.navigate(.findId) },
                onCompleted: { loginId in
                    recoveredLoginId = loginId
                    // 성공해도 서버는 토큰을 주지 않는다 — 새 비밀번호로 직접 로그인해야 한다는 걸 04a 에서 말한다.
                    // 세션 만료 안내와 같은 자리(noticeMessage)라 로그인에 성공하면 함께 지워진다.
                    signOutNotice = "비밀번호를 바꿨어요. 새 비밀번호로 로그인해 주세요"
                    returnToLoginForm()
                }
            )

        // C · 가입 10 · 12 · 13 (2단계 — 11 안심 설정은 삭제)
        //
        // 05 계정 유형 · 06 학교 이메일 · 07 인증 코드 · 08 재직 인증 · 09 본인 인증은 여기 없다.
        // 가입 API 에 계정 유형이 없고, 학교·재직 인증은 마이페이지에서 나중에 붙이는 컨셉이며,
        // 휴대폰 본인 인증은 MVP 범위 밖이다 — 필수 경로에 두면 인증 없이 값만 묻거나
        // 서버로 가지도 않는 값을 묻는 화면이 된다(Routes.swift B' 절 참고).
        // 09 가 받던 실명·생년월일·성별·휴대폰은 10 의 「기본 정보」 절이 이어받았다.
        case .profileSetup:
            // Route 인 이유는 닉네임 중복 확인(POST /auth/nickname/check) 하나 때문이다 —
            // 입력값 자체는 여전히 화면이 들고 있다.
            ProfileSetupRoute(
                repository: authRepository,
                onBack: back,
                onNext: { info in
                    // 닉네임·문자 인증 토큰을 포함한 서버 가입 9개 값이 이 화면에서 한 번에 채워진다
                    signupDraft = info
                    navController.navigate(.mannerPledge)
                },
                // 이미 가입된 번호(409)로 인증번호 발송이 끊겼을 때의 길 — 가입을 계속하게 두지 않고 로그인으로 보낸다.
                // 가입 폼 위에 쌓으므로 뒤로 가면 적어 둔 입력이 그대로 있다.
                onGoToLogin: { navController.navigate(.loginForm) },
                reverifyPhoneRequest: reverifyPhoneRequest
            )
        case .mannerPledge:
            // 여기서 회원가입 + 자동 로그인이 실행된다. 성공했을 때만 13 으로 넘어간다.
            MannerPledgeRoute(
                repository: authRepository,
                draft: signupDraft,
                onBack: back,
                onCompleted: { navController.navigate(.signupComplete) },
                // 409 닉네임 중복 — 10 으로 되돌린다. 스택에 남아 있는 그 엔트리로 pop 하므로
                // 이미 채운 나머지 7개 필드는 그대로 있고 닉네임만 고치면 된다.
                onEditNickname: { navController.popBackStack(.profileSetup, inclusive: false) },
                // 400 USER207 — 토큰이 만료·소진됐다. 10 으로 되돌리면서 인증 블록을 초기화하라고 알린다.
                // 입력값(@State)은 그대로 남아 휴대폰 인증만 다시 하면 된다.
                onReverifyPhone: {
                    reverifyPhoneRequest += 1
                    navController.popBackStack(.profileSetup, inclusive: false)
                }
            )
        case .signupComplete:
            SignupCompleteScreen(
                onStart: { resetTo(.home) },
                // 17 합승 탐색으로 보내되 **홈을 바닥에 남긴다.** resetTo(.explore) 로 바로 가면
                // 스택이 [explore] 하나뿐이라 ① 뒤로가기가 그 하나를 pop 해 빈 그래프가 되고
                // ② `navigateTab` 이 걷어낼 홈이 없어 탭이 교체가 아니라 쌓인다.
                onExplore: {
                    resetTo(.home)
                    navigateTab(.explore)
                }
            )

        // D · 홈 · 목적지 14–16
        case .home:
            HomeRoute(
                viewModel: navController.retained(for: entry) { HomeViewModel(repository: placeRepository) },
                activeRide: activePartyViewModel.ride,
                onSearchClick: {
                    searchInitialQuery = ""
                    createScheduled = false
                    navController.navigate(.destination)
                },
                onActiveRideClick: openActiveStage,
                onPlaceQuery: { query in
                    searchInitialQuery = query
                    createScheduled = false
                    navController.navigate(.destination)
                },
                onTabSelect: navigateTab
            )
            .environment(\.mapCameraMemory, navController.retained(for: entry) { MapCameraMemory() })
            .environment(\.tabSavedState, navController.retained(for: entry) { TabSavedState() })
            // 탭으로 돌아올 때마다 진행 중 방을 다시 읽는다 — 배너가 끝난 방을 가리키면 안 된다
            .task { activePartyViewModel.refresh() }
        case .destination:
            DestinationRoute(
                repository: placeRepository,
                initialQuery: searchInitialQuery,
                onBack: back,
                onConfirmRoute: { origin, place in
                    if pickingSearchDestination {
                        // 17 의 도착지 필터만 고른 것이다 — 방을 만들러 온 길이 아니므로 16 을 열지 않는다.
                        reservationSearchDestination = place
                        back()
                    } else {
                        confirmedOrigin = origin
                        confirmedDestination = place
                        navController.navigate(.destinationConfirm)
                    }
                }
            )
            // 15 를 떠날 때 깃발을 **반드시** 내린다. `onBack` 에만 두면 안 된다 — 시스템 뒤로가기
            // 제스처(가장자리 스와이프)는 그 클로저를 타지 않아, 필터를 고르다 그냥 나온 사용자가 다음에 방을
            // 만들려고 15 를 열면 16 이 뜨지 않고 고른 도착지가 조용히 필터로 먹힌다.
            .onDisappear { pickingSearchDestination = false }
        // 16 은 15 위에 뜨는 모달 — body 가 오버레이로 그린다(`projectBackStack`)
        case .destinationConfirm:
            DestinationConfirmRoute(
                repository: rideRepository,
                // 핀 조정·GPS 출발지의 좌표를 실주소로 되짚는다 (GET /places/reverse)
                placeRepository: placeRepository,
                origin: confirmedOrigin,
                destination: confirmedDestination,
                // 17 예약 탭에서 눌러 온 길이면 시간 정하기로 연다 — 위 createScheduled 참고
                initiallyScheduled: createScheduled,
                onDismiss: back,
                onPartyCreated: { ride in
                    createdPartyId = Int64(ride.id)
                    // 진행 중 방으로 기억한다 — 앱을 껐다 켜거나 탭을 옮겨도 여기로 돌아올 근거
                    activePartyViewModel.rememberParty(partyId: ride.id)
                    // 모달을 닫고 21 매칭 대기로 — 뒤로 눌러 모달로 돌아오지 않게 한다
                    navController.navigate(.matchWaiting) {
                        $0.popUpTo(.destinationConfirm, inclusive: true)
                    }
                },
                // 추천 방을 고르면 19 합류 확인으로 — 모달은 닫고 뒤로 눌러 돌아오지 않게 한다.
                // 방을 만들지 않았으므로 createdPartyId 는 건드리지 않는다.
                onCandidateSelected: { ride in
                    selectedPartyId = Int64(ride.id)
                    navController.navigate(.joinConfirm) {
                        $0.popUpTo(.destinationConfirm, inclusive: true)
                    }
                },
                // 「이미 참여 중인 방이 있어요」를 만났을 때의 **탈출구**. 문구만으로는 부족하다 —
                // 기억이 지워졌거나 앱을 새로 깐 상태면 홈 배너가 없어 그 방으로 돌아갈 길이 없다.
                onActivePartyRefresh: { activePartyViewModel.refresh() }
            )

        // E · 합승 탐색 17–20 (17·18·19 는 한 화면의 시트 상태)
        case .explore:
            ExploreRoute(
                viewModel: navController.retained(for: entry) { ExploreViewModel(repository: rideRepository) },
                // 예약 조회 뷰모델도 같은 칸에 맡긴다 — 원본에서 둘은 같은 엔트리의 뷰모델이라 수명이 같다.
                finderViewModel: navController.retained(for: entry) {
                    ReservationFinderViewModel(repository: rideRepository)
                },
                activeRide: activePartyViewModel.ride,
                // 예약 날짜 검색의 도착지 필터 — 15 를 **고르기 전용**으로 열었다가 돌아온다.
                searchDestination: reservationSearchDestination,
                onJoinParty: { ride in
                    selectedPartyId = Int64(ride.id)
                    navController.navigate(.joinConfirm)
                },
                // 배너는 **지금 단계 화면**으로 바로 간다
                onOngoingRideClick: openActiveStage,
                onCreateRoomClick: { scheduled in
                    createScheduled = scheduled
                    navController.navigate(.destination)
                },
                onPickSearchDestination: {
                    pickingSearchDestination = true
                    searchInitialQuery = ""
                    // 필터만 고르러 가는 길이라 16 을 열지 않는다 — 깃발도 남기지 않는다
                    createScheduled = false
                    navController.navigate(.destination)
                },
                onClearSearchDestination: { reservationSearchDestination = nil },
                onTabSelect: navigateTab
            )
            .environment(\.mapCameraMemory, navController.retained(for: entry) { MapCameraMemory() })
            .environment(\.tabSavedState, navController.retained(for: entry) { TabSavedState() })
            .topEntryTask { activePartyViewModel.refresh() }
        case .joinConfirm:
            JoinConfirmRoute(
                repository: rideRepository,
                // 합류가 「다른 방에 참여 중」으로 막혔을 때 그 방이 확정된 방인지 알아내는 데 쓴다 —
                // 확정된 방은 나갈 수가 없어서 안내할 행동이 달라진다(JoinConfirmRoute.alreadyInPartyMessage)
                activePartyRepository: activePartyRepository,
                partyId: selectedPartyId,
                onDismiss: back,
                // 합류가 끝나면 **방 id 만** 받아 21 매칭 대기로 넘긴다 — 합류 응답은 더 이상 방 상세가
                // 아니고(Backend #213), 대기 화면이 SSE 첫 스냅샷으로 상세 전체를 받으므로 여기서 상세를
                // 읽어 넘길 필요가 없다. 「이미 그 방 멤버였다」로 복구된 경우도 같은 길로 온다.
                // (준비/출발 버튼이 사라진 뒤로 합류의 다음 단계는 22 상세가 아니라 대기다)
                onJoined: { joinedPartyId in
                    createdPartyId = joinedPartyId
                    activePartyViewModel.rememberParty(partyId: String(joinedPartyId))
                    navController.navigate(.matchWaiting) {
                        $0.popUpTo(.joinConfirm, inclusive: true)
                    }
                },
                onMemberClick: { member in
                    selectedPartner = member
                    navController.navigate(.partnerProfile)
                }
            )

        // F · 매칭 · 탑승 21–23
        case .matchWaiting:
            MatchWaitingRoute(
                repository: rideRepository,
                partyId: createdPartyId,
                // 나가기 성공 후 14 홈 — 방에서 빠졌으니 진행 중 기억도 함께 지운다
                onCancelSearch: {
                    activePartyViewModel.clearParty()
                    navigateTab(.home)
                },
                // 방을 **유지한 채** 화면만 벗어난다 — 어느 방인지 모르는 진입(복원 뒤 id 유실)과
                // 닫힌 방 한 프레임의 뒤로가기가 여기로 온다. 나가기 쪽으로 모으지 않는다:
                // 되돌릴 수 없는 일을 뒤로가기로 일으키지 않는다.
                onExitKeepingParty: { navigateTab(.home) },
                onCardClick: {
                    selectedPartyId = createdPartyId
                    navController.navigate(.rideDetail)
                },
                // 방이 닫혔다(내·남의 「합승 완료」, 30분 스윕). 끝난 방이라 진행 중 기억을 지우고 홈으로.
                onPartyClosed: {
                    activePartyViewModel.clearParty()
                    navigateTab(.home)
                },
                // **다음 단계 화면으로 넘기는 콜백(`onMatchingStarted`)은 없다.** 정원이 차면 서버가
                // 기사 매칭을 시작하고 앱이 25 배차 현황으로 넘어가던 길이 사라졌다 — 서버가
                // `DISPATCHING` 을 보낼 수 없고 그 화면도 없다. 정원이 찬 방은 21 에 머물며
                // 채팅으로 만날 곳을 정하고, 방장의 「합승 완료」가 `onPartyClosed` 로 끝낸다.
                onOpenChat: onOpenActiveChat
            )
            // 시스템 뒤로가기(스와이프)는 기본 pop 이라 헤더 ← 가 타는 분기
            // (MatchWaitingScreen: 나가기 확인 다이얼로그 / onExitKeepingParty)를 **건너뛴다.**
            // 스택이 [home, destination, matchWaiting] 이어서 그냥 pop 하면 15 목적지 검색으로
            // 떨어졌고, 거기서 방을 또 만들면 서버가 409 로 막는다(진행 중인 방을 떠난 자리에서
            // 받는 실패 메시지다). 그래서 `onExitKeepingParty` 와 같은 결론으로 모은다 — **방은
            // 그대로 두고** 14 홈. 나가기 쪽으로 모으지 않는 이유: 되돌릴 수 없는 일을 시스템
            // 뒤로가기로 일으키지 않는다(다이얼로그를 띄울 `canLeave` 는 화면 안의 상태라 여기서 못 본다).
            .moyeotaBackHandler { navigateTab(.home) }
        case .rideDetail:
            RideDetailRoute(
                repository: rideRepository,
                partyId: selectedPartyId,
                onBack: back,
                onPartnerClick: { partner in
                    selectedPartner = partner
                    navController.navigate(.partnerProfile)
                },
                // 이 화면에는 다음 단계로 넘기는 길이 없다 — 수동 출발 CTA 는 자동 기사 매칭 전환으로
                // 사라졌고, 그 자동 매칭마저 걷어낸 뒤로는 넘어갈 화면 자체가 없다.
                //
                // 나가기는 **서버 나가기가 성공한 뒤에만** 불린다(RideDetailViewModel.left) —
                // 21 의 onCancelSearch 와 같은 자리이므로 진행 중 기억도 같이 지운다. 안 지우면
                // 홈 진입의 refresh() 가 돌아 스스로 낫기까지의 한 왕복 동안 배너가 이미 나간 방을
                // 가리키고, 그걸 누르면 유령 대기방으로 들어간다.
                onLeave: {
                    activePartyViewModel.clearParty()
                    navigateTab(.home)
                }
            )
        case .partnerProfile:
            // 20·22 를 거치지 않고 이 라우트에 닿을 길은 없다. 그래도 nil 이면 데모 프로필을
            // 그리는 대신 사실대로 말하고 되돌린다 — 존재하지 않는 사람을 보여주는 것보다 낫다.
            if let partner = selectedPartner {
                PartnerProfileScreen(
                    user: partner,
                    onBack: back,
                    onChatClick: { navController.navigate(.chat) }
                )
            } else {
                BackStateScaffold(title: "프로필", onBack: back) {
                    ErrorBox(message: "동승자 정보를 불러오지 못했어요", onRetry: back)
                }
            }

        // G · 채팅 24
        case .chat:
            ChatRoute(
                state: navController.retained(for: entry) { ChatTabState(repository: chatRepository, rideRepository: rideRepository) },
                // 열린 방이 진행 중인 그 방이면 헤더에 「매칭 화면으로」 줄이 뜨고 「나가기」가 사라진다.
                // **판정의 1순위는 채팅방 id 다** — 이 경로의 방은 목록 응답(`GET /chat-rooms/me`)으로
                // 만든 것이어서 partyId 가 0(모름)이고, 그걸로 비교하면 늘 "내 방이 아니다"가 됐다.
                activeChatRoomId: activePartyViewModel.chatRoomId,
                activePartyId: activePartyViewModel.ride?.id,
                onOpenMatching: openActiveStage,
                onLeaveChat: {
                    // 나간 방 id 를 진행 화면이 들고 있으면 「채팅 열기」가 죽은 방으로 간다 — 캐시를 버린다
                    activePartyViewModel.forgetChatRoom()
                    navigateTab(.home)
                },
                // 목록 길게 누르기로 동승에서 나갔다 — 그 방이 진행 중인 방이면 기억을 지우고, 아니면(예약 방 등)
                // 진행 중인 방을 다시 찾는다. 홈 배너와 「채팅 열기」가 나간 방을 붙들고 있지 않게 한다
                onLeftParty: { partyId in
                    if activePartyViewModel.ride?.id == String(partyId) {
                        activePartyViewModel.clearParty()
                    } else {
                        activePartyViewModel.refresh()
                    }
                },
                onLeftChatRoom: { chatRoomId in
                    if chatRoomId == activePartyViewModel.chatRoomId { activePartyViewModel.forgetChatRoom() }
                },
                onTabSelect: navigateTab,
                onNotParticipant: { activePartyViewModel.forgetChatRoom() }
            )
            .environment(\.tabSavedState, navController.retained(for: entry) { TabSavedState() })
        // 24 채팅방 **단독 목적지** — 21 대기 화면의 「채팅 열기」가 이 위에 쌓인다.
        // 뒤로가기 한 번이면 21 로 돌아온다(탭 이동은 스택을 갈아엎어 그럴 수 없었다).
        // 원본의 「인자 없는 진입」 분기(`roomId == null`)는 `Route.chatRoom(roomId:)` 가 인자를 강제해 생기지 않는다.
        case .chatRoom(let roomId):
            ChatRoomDestinationRoute(
                repository: chatRepository,
                roomId: roomId,
                // 이 경로는 방 상세에서 온 진짜 partyId 를 들고 있어 둘 다 근거가 된다.
                // 채팅방 id 를 아직 못 찾은 구간은 partyId 가 메운다.
                activeChatRoomId: activePartyViewModel.chatRoomId,
                activePartyId: activePartyViewModel.ride?.id,
                onBack: back,
                onOpenMatching: openActiveStage,
                onLeaveChat: {
                    // 나간 방 id 를 진행 화면이 들고 있으면 「채팅 열기」가 죽은 방으로 간다 — 캐시를 버린다
                    activePartyViewModel.forgetChatRoom()
                    navigateTab(.home)
                },
                onTabSelect: navigateTab,
                onNotParticipant: { activePartyViewModel.forgetChatRoom() }
            )

        // I · 마이페이지 35 · 프로필 수정 36
        case .mypage:
            MyPageScreen(
                userName: profileViewModel.userName,
                onEditProfile: { navController.navigate(.profileEdit) },
                onRideHistory: { navController.navigate(.rideHistory) },
                onNoShowRecords: { navController.navigate(.noShowRecords) },
                // logout() 은 실패하지 않는다 — 상태 전이는 위 `.task(id: loggedIn)` 이 받아 04a 로 보낸다.
                // logoutRequested 를 먼저 세워 두면 그 전이를 세션 만료로 오해하지 않는다.
                onLogout: {
                    logoutRequested = true
                    let authRepository = self.authRepository
                    Task { try? await authRepository.logout() }
                },
                onDeleteAccount: { navController.navigate(.accountDelete) },
                onTabSelect: navigateTab
            )
            .environment(\.tabSavedState, navController.retained(for: entry) { TabSavedState() })
        case .profileEdit:
            // 36 프로필 수정 — 35 와 같은 홀더를 쓴다. 홀더가 이름과 **프로필 사진 주소**를 함께
            // 들고 있어, 36 은 그걸로 닉네임을 프리필하고 「기본 이미지로 되돌리기」를 보일지 정한다.
            // 저장이 끝나면 그 홀더를 다시 조회해 35 프로필 카드·14 홈 인사말이 새 닉네임과 새 사진으로
            // 함께 바뀌게 한 뒤 되돌아간다(화면마다 따로 들고 있으면 한쪽만 옛 값으로 남는다).
            ProfileEditRoute(
                repository: authRepository,
                userName: profileViewModel.userName,
                onBack: back,
                onSaved: {
                    profileViewModel.refresh()
                    back()
                }
            )
        case .rideHistory:
            // 34 지난 탑승 기록 — GET /api/v1/users/me/parties.
            //
            // **진행 중인 방은 여기 나오지 않는다**(실측 2026-11-01, 로컬 :8080: 진행 중인 방을
            // 가진 계정도 빈 배열). 그래서 activePartyRepository 를 넘기지 않는다 — 둘은
            // 서로를 대체하지 않고, 진행 중인 방은 14·17 의 배너가 보여 준다.
            //
            // 조회가 실패하면 화면은 「불러오지 못했어요 · 다시 시도」로 떨어진다. 조용히 빈 목록을
            // 그리지 않는 이유: 「기록이 없다」와 「못 불러왔다」는 다른 사실이고, 앞쪽을 보여 주면
            // 사용자는 자기 기록이 사라졌다고 읽는다.
            RideHistoryRoute(
                repository: rideRecordRepository,
                onBack: back
            )
        case .noShowRecords:
            // 38 노쇼 기록·이의 신청 — GET /api/v1/matching/no-shows, 최대 20건.
            //
            // 34 와 달리 **진행 중인 방과 무관**하다. 노쇼는 이미 끝난 방에서만 생기므로
            // activePartyRepository 를 넘길 이유가 없다.
            //
            // 이 화면이 하는 일의 절반은 **이의 신청**이다. 노쇼는 약속 시간부터 (횟수 × 24시간)
            // 동안 방 만들기·참여를 막는 실제 제재이고, 잘못 찍힌 사람이 그걸 되돌릴 길은 여기뿐이다
            // — 조회가 실패하면 빈 목록이 아니라 「불러오지 못했어요 · 다시 시도」로 떨어뜨린다.
            NoShowRecordsRoute(
                repository: noShowRepository,
                onBack: back
            )
        case .accountDelete:
            // 37 회원 탈퇴 — DELETE /api/v1/users/me.
            //
            // 성공 뒤의 이동을 여기서 하지 않는다. 탈퇴가 204 를 받으면 Repository 가 세션을 비우고
            // authState 가 전이하므로, 위의 로그인 전이 `.task` 가 스택을 통째로 비우며
            // 04a 로 보낸다(이 화면도 그때 사라진다). 여기서 또 navigate 하면 전이와 겹친다.
            //
            // 플래그가 둘인 이유는 선언부 주석에 있다 — 「요청을 보냈다」와 「204 를 받았다」는
            // 다른 사실이고, 안내를 고를 수 있는 것은 **뒤쪽**뿐이다. 응답이 전이보다 늦게 도착할 수
            // 있어서 위 전이 감지가 짧게 기다린다(ACCOUNT_DELETE_RESULT_WAIT_MS).
            AccountDeleteRoute(
                repository: authRepository,
                onBack: back,
                onSessionEndExpected: { accountDeleteRequested = true },
                onDeleted: { accountDeleted = true },
                onSessionKept: { accountDeleteRequested = false }
            )
        }
    }
}
