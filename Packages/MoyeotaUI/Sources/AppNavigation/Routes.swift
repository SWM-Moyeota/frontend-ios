// v15 와이어프레임 화면 번호 · 화면 ID 매핑
public enum Routes {
    // A · 온보딩
    public static let ONBOARDING_SAVING = "onboarding/saving"        // 01 O01
    public static let ONBOARDING_TRUST = "onboarding/trust"          // 02 O02
    public static let ONBOARDING_SAFETY = "onboarding/safety"        // 03 O03

    // B · 로그인
    public static let LOGIN = "auth/login"                           // 04 S01
    public static let LOGIN_FORM = "auth/login-form"                 // 04a 신규 (아이디 로그인)

    /// 04b 아이디 찾기 · 04c 비밀번호 재설정 (신규, 2026-11) — 백엔드 #314 · #331.
    ///
    /// iOS 가 먼저 붙였고 원본이 따라왔다(Android frontend #100). 둘 다 04a 위에 쌓이고, 끝나면 04a 로 되돌아간다.
    public static let FIND_ID = "auth/find-id"                       // 04b 신규 (아이디 찾기)
    public static let PASSWORD_RESET = "auth/password-reset"         // 04c 신규 (비밀번호 재설정)

    // B' · 부가 인증 05~09 — **가입 그래프에 등록하지 않는다**
    //
    // 서버 가입(POST /api/v1/users)에는 계정 유형 개념이 없고(loginId·password·name·birthDate·
    // phone·gender·email 뿐), 학교/재직 인증은 「마이페이지에서 나중에 추가」하는 컨셉이다.
    // 09 휴대폰 본인 인증은 MVP 범위 밖이라 인증 없이 값만 묻는 화면이 되어 있었다
    // — 받던 값(실명·생년월일·성별·휴대폰)은 10 프로필의 「기본 정보」 절이 이어받았다.
    // 가입 필수 경로에 세워두면 아무 데도 쓰이지 않는 값을 4~5화면 더 묻게 된다.
    // 화면 파일과 라우트 상수는 남겨둔다 — 인증을 붙일 때 그대로 재사용한다.
    //
    // 원본은 이 문자열이 `NavHost` 에 없어 그리로 이동하면 런타임에 던진다. iOS 는 `Route` 에 이 다섯 경우를
    // 두지 않아 그리로 가는 코드가 **컴파일되지 않는다** — 닿을 수 없다는 사실은 같다.
    public static let ACCOUNT_TYPE = "auth/account-type"             // 05 S25 (미연결)
    public static let SCHOOL_EMAIL = "auth/school-email"             // 06 S02 (미연결)
    public static let EMAIL_CODE = "auth/email-code"                 // 07 S03 (미연결)
    public static let WORK_VERIFY = "auth/work-verify"               // 08 S26 (미연결)
    public static let IDENTITY_VERIFY = "auth/identity"              // 09 S04 (미연결)

    // C · 가입 (2단계: 10 → 12 → 13 완료)
    public static let PROFILE_SETUP = "auth/profile"                 // 10 S05
    public static let MANNER_PLEDGE = "auth/manner-pledge"           // 12 S07
    public static let SIGNUP_COMPLETE = "auth/signup-complete"       // 13 S08

    // D · 홈 · 목적지
    public static let HOME = "home"                                  // 14 S09
    public static let DESTINATION = "home/destination"               // 15 S10
    public static let DESTINATION_CONFIRM = "home/destination-confirm" // 16 신규 (모달)

    // E · 합승 탐색 (17–19 는 한 화면의 시트 상태)
    public static let EXPLORE = "explore"                            // 17–19 V07·V07b·V07c
    public static let JOIN_CONFIRM = "explore/join-confirm"          // 20 신규

    // F · 매칭 · 탑승
    public static let MATCH_WAITING = "matching/waiting"             // 21 S11
    public static let RIDE_DETAIL = "ride/detail"                    // 22 S12
    public static let PARTNER_PROFILE = "ride/partner-profile"       // 23 S13

    // G · 채팅 · 안심
    public static let CHAT = "chat"                                  // 24 S16 (+24a 메뉴 · 24b 공유 시트)

    /// 24 S16 — **채팅방 단독 목적지**. 21 대기 화면의 「채팅 열기」가 이리로 push 한다.
    ///
    /// 채팅 탭(`CHAT`)으로 보내면 매칭 화면이 스택에서 빠져 뒤로가기로 돌아올 곳이 없어진다
    /// (사용자 신고: "채팅방에서 매칭 진행 화면으로 돌아갈 수 없다"). 방을 **쌓아** 열면
    /// 뒤로가기가 곧 원래 화면 복귀다. 채팅 탭 목록에서 여는 경로는 예전 그대로 탭 안에서 전환한다.
    public static let CHAT_ROOM = "chat/room/{roomId}"               // 24 S16 (단독 진입)

    public static func chatRoom(roomId: Int64) -> String { "chat/room/\(roomId)" }

    // I · 마이페이지
    public static let MYPAGE = "mypage"                              // 35 S24
    public static let PROFILE_EDIT = "mypage/profile-edit"           // 36 신규 (닉네임 수정)

    /// 34 지난 탑승 기록 (2026-11-01 재도입) — `GET /api/v1/users/me/parties`.
    ///
    /// 예전의 34 「내 탑승」과 **보여 주는 것이 다르다.** 그쪽은 「진행 중 · 예정」 탭이었고
    /// 서버에 완료 방 목록도 예약 개념도 없어 삭제됐다.
    /// 지금 이 화면은 **하차까지 끝난 탑승만** 그린다 — 서버가 그것만 주기 때문이다.
    /// 진행 중인 방은 홈·탐색 배너가 맡으므로 35 와의 순환 링크도 되살리지 않았다.
    public static let RIDE_HISTORY = "mypage/ride-history"           // 34 재도입 (지난 탑승 기록)

    /// 37 회원 탈퇴 (신규, 2026-10) — `DELETE /api/v1/users/me`. 앱 계정 삭제 요건.
    ///
    /// 다이얼로그가 아니라 **별 화면**인 이유는 `AccountDeleteScreen` 주석에 있다
    /// (서버가 비밀번호를 본문으로 요구한다 → 입력란 + 두 가지 실패 표시 + 경고 네 줄).
    ///
    /// 성공 뒤의 이동을 이 라우트가 하지 않는다 — 세션이 사라지면 `MainNavGraph` 의 로그인 전이
    /// 감지가 04a 로 보내면서 스택을 통째로 비운다(이 화면도 그때 사라진다).
    public static let ACCOUNT_DELETE = "mypage/account-delete"       // 37 신규 (회원 탈퇴)

    /// 로그인 수단 관리 — 아이디·비밀번호와 구글 연결(2026-11 소셜 로그인). 원본 `Routes.LOGIN_METHODS`
    public static let LOGIN_METHODS = "mypage/login-methods"

    // J · 택시비 정산 39–40 (신규, 2026-11-12)
    //
    // **38 을 비워 두는 이유**: 그 번호는 노쇼 기록·이의 신청이 쓰다가 서버 기능이 통째로 사라져
    // 지운 자리다. 되쓰면 옛 문서·보고서의 「38」이 두 가지를 가리키게 된다.
    //
    // 두 라우트가 **같은 `{partyId}` 를 경로 인자로** 받는다. 화면 바깥에 방 id 를 들고 있는
    // 홀더(`selectedPartyId`·`createdPartyId`)를 쓰지 않는 이유는 진입점이 셋이고 서로 다른
    // 스택 위치에서 오기 때문이다(끝난 방 상세 · 탑승 기록 카드 · 홈 배너). 홀더에 기대면
    // 「홈 배너로 열었는데 직전에 보던 방의 정산이 뜨는」 혼동이 가능해지고, **돈이 걸린 화면에서
    // 그 혼동의 대가가 가장 크다.**

    /// 39 택시비 정산 상세 — **역할에 따라 받는 사람/보내는 사람 화면이 갈린다**
    /// (서버가 `myRole` 로 같은 엔드포인트에서 두 모양을 준다).
    ///
    /// 정산이 아직 없는 방도 이 라우트로 들어온다 — 404 는 **정상 상태**이고 화면이
    /// 「정산 시작하기」로 그린다(`FareSplitAbsentScreen`).
    public static let FARE_SPLIT = "faresplit/{partyId}"             // 39 신규 (정산 상세)

    public static func fareSplit(partyId: Int64) -> String { "faresplit/\(partyId)" }

    /// 40 택시비 정산 시작·수정 — **방장 전용**. 39 위에 쌓이므로 뒤로가기가 곧 상세 복귀다.
    ///
    /// 시작과 수정이 **같은 라우트**인 이유: 서버가 POST·PATCH 에 같은 본문을 쓰고(`FareSplitDraft`)
    /// 화면도 같다. 어느 쪽인지는 `start` 인자가 정한다 — 라우트를 둘로 나누면 같은 화면이 두 곳에 등록되고,
    /// 한쪽만 고치는 날이 온다.
    public static let FARE_SPLIT_EDIT = "faresplit/{partyId}/edit?start={start}" // 40 신규 (정산 시작·수정)

    /// - Parameter start: true 면 시작(POST), false 면 수정(PATCH).
    public static func fareSplitEdit(partyId: Int64, start: Bool) -> String { "faresplit/\(partyId)/edit?start=\(start)" }
}

/// 그래프에 **등록된** 목적지. 원본 `NavHost { composable(…) }` 의 목록이다.
///
/// 원본의 문자열 라우트 대신 enum 인 이유: 경로 인자(`roomId`)와 라우트 이름이 어긋나면 런타임에야 드러나는
/// 함정(원본 `CHAT_ROOM_ID_ARG` 주석)이 없어지고, 목적지를 빠뜨리면 그래프의 `switch` 가 컴파일되지 않는다.
public enum Route: Hashable, Sendable {
    case onboardingSaving, onboardingTrust, onboardingSafety
    case login, loginForm, findId, passwordReset
    case profileSetup, mannerPledge, signupComplete
    case home, destination, destinationConfirm
    case explore, joinConfirm
    case matchWaiting, rideDetail, partnerProfile
    case chat
    case chatRoom(roomId: Int64)
    case mypage, profileEdit, rideHistory, accountDelete, loginMethods
    /// 39 택시비 정산 상세. 방 id 는 **경로 인자**다(`Routes.FARE_SPLIT` 주석 — 진입점이 셋이라 홀더에 기대지 않는다).
    case fareSplit(partyId: Int64)
    /// 40 택시비 정산 시작(`start` = true)·수정(false).
    ///
    /// 원본은 `start` 의 기본값을 **수정**으로 둔다 — 빠뜨린 호출이 시작(POST)으로 가면 이미 있는 정산에 409
    /// `FARE_SPLIT_ALREADY_EXISTS` 를 만들고, 수정으로 가면 404 로만 끝난다(아무것도 바꾸지 않는 실패). iOS 는
    /// 경우가 인자를 강제해 빠뜨릴 수 없다.
    case fareSplitEdit(partyId: Int64, start: Bool)

    /// 원본 `NavDestination.route` — 인자를 채우기 **전**의 패턴이다. 목적지가 같은지는 이 값으로 가른다
    /// (`popBackStack` · `launchSingleTop` · 저장된 스택의 열쇠가 모두 목적지 단위다).
    public var destination: String {
        switch self {
        case .onboardingSaving: Routes.ONBOARDING_SAVING
        case .onboardingTrust: Routes.ONBOARDING_TRUST
        case .onboardingSafety: Routes.ONBOARDING_SAFETY
        case .login: Routes.LOGIN
        case .loginForm: Routes.LOGIN_FORM
        case .findId: Routes.FIND_ID
        case .passwordReset: Routes.PASSWORD_RESET
        case .profileSetup: Routes.PROFILE_SETUP
        case .mannerPledge: Routes.MANNER_PLEDGE
        case .signupComplete: Routes.SIGNUP_COMPLETE
        case .home: Routes.HOME
        case .destination: Routes.DESTINATION
        case .destinationConfirm: Routes.DESTINATION_CONFIRM
        case .explore: Routes.EXPLORE
        case .joinConfirm: Routes.JOIN_CONFIRM
        case .matchWaiting: Routes.MATCH_WAITING
        case .rideDetail: Routes.RIDE_DETAIL
        case .partnerProfile: Routes.PARTNER_PROFILE
        case .chat: Routes.CHAT
        case .chatRoom: Routes.CHAT_ROOM
        case .mypage: Routes.MYPAGE
        case .profileEdit: Routes.PROFILE_EDIT
        case .rideHistory: Routes.RIDE_HISTORY
        case .accountDelete: Routes.ACCOUNT_DELETE
        case .loginMethods: Routes.LOGIN_METHODS
        case .fareSplit: Routes.FARE_SPLIT
        case .fareSplitEdit: Routes.FARE_SPLIT_EDIT
        }
    }

    /// 원본의 `dialog(…)` 목적지 — 16 하나뿐이다. 아래 화면 위에 뜨고, 다른 목적지로 가면 저절로 닫힌다.
    public var isDialog: Bool { self == .destinationConfirm }
}

// 하단탭 네 루트 — 탭 전환이 saveState 로 상태를 보관하는 대상이자, 로그아웃 때 그 보관분을 지울 대상.
let TabRoutes: [Route] = [.home, .explore, .chat, .mypage]
