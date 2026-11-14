import MoyeotaDesignSystem
import PresentationCore
import SwiftUI

/// 35 · 마이페이지 · 설정 [S24]
///
/// 진입: 하단탭 마이페이지
///
/// 구성: 프로필 카드 → (제재 배너) → 「탑승」 카드 → 「설정」 카드 → 「안내」 카드 → 「계정」 카드 → 버전
///
/// ```
/// 프로필 카드 (사진 · 이름 / 닉네임·사진 바꾸기)  ›
/// ▓ 노쇼 2건으로 11월 7일 오후 3:20까지 방을 만들거나 … ▓  ← 2026-11-06 추가, 제재 중에만
/// [탑승]  지난 탑승 기록                       ›   ← 2026-11-01 추가
///         노쇼 기록                           ›   ← 2026-11-06 추가
/// [설정]  알림 설정                          ↗
/// [안내]  개인정보 처리방침 / 이용약관 / 문의하기   ↗   ← 한 카드, 구분선
/// [계정]  로그아웃                           ›
///         탈퇴하기                                ← 카드 밖 회색 글자 링크 (2026-11 디자인 QA M2)
///         탈퇴하면 계정과 저장한 정보가 사라지고…
///                      v1.0                      ← 가운데
/// ```
///
/// 이동(디스크립션):
/// - 하단탭 홈 / 합승 / 채팅 → 14 / 17 / 24 (onTabSelect)
/// - 프로필 카드 → 36 프로필 수정 (onEditProfile)
/// - 「지난 탑승 기록」 → 34 지난 탑승 기록 (onRideHistory)
/// - 「노쇼 기록」 → 38 노쇼 기록·이의 신청 (onNoShowRecords)
/// - 「알림 설정」 → OS 앱 알림 설정 (앱 밖)
/// - 「개인정보 처리방침」 · 「이용약관」 → 브라우저 (앱 밖)
/// - 「문의하기」 → 메일 앱, 제목·환경 정보 자동 입력 (앱 밖)
/// - 「로그아웃」 → 확인 다이얼로그 후 04a 로그인 (onLogout)
/// - 「탈퇴하기」 → 37 회원 탈퇴 (onDeleteAccount)
///
/// ### 2026-10-14 재구성 — 무엇을 바꿨고 왜인가
/// 1. **「안내」 카드가 생겼다.** 약관·개인정보 주소가 없어 숨어 있던 행이 주소가 생겨 드러났다
///    (`SupportLinks`). 스토어 심사는 **앱 안에서 개인정보 처리방침에 닿는 경로**를 본다.
/// 2. **로그아웃이 카드 행이 됐다.** 그전엔 13sp 회색 글자 한 줄이어서, 탈퇴(번듯한 카드 행)보다
///    작았다 — 훨씬 자주 쓰는 기능이 더 작아 위계가 뒤집혀 있었다. 이제 탈퇴와 같은 56pt 행이고
///    **같은 「계정」 카드 안에** 나란히 있다. 둘을 가르는 것은 크기가 아니라 색(탈퇴만 빨강)과
///    확인 단계다: 로그아웃은 확인 다이얼로그, 탈퇴는 37 에서 비밀번호 + 또 한 번의 다이얼로그.
///    (그전의 오탭 보호는 40pt 간격이었는데, 간격으로 떼어 놓으려면 로그아웃을 작게 둬야 했다.)
/// 3. **버전은 맨 아래 가운데로.** 로그아웃 줄 오른쪽에 있던 값이라, 로그아웃이 카드로 들어가면서
///    같이 들어가면 행 안에 뜻이 다른 두 정보가 섞인다.
///
/// ### 2026-11 디자인 QA — 떠 있는 카드를 걷어 냈다
/// - 카드의 그림자를 없앴다. 회색 바탕 위 흰 카드는 면의 차이만으로 묶음이 읽힌다 — 그림자까지 얹으면
///   카드마다 떠 있어 화면 전체가 들뜬다(G4). 모서리 18 → 12pt, 안쪽 여백 20 → 16pt, 프로필 카드 104 → 80pt
/// - **「탈퇴하기」는 카드 밖으로 뗐다**(M2). 위 2번의 「색으로 가른다」는 한 카드 안에 빨간 행을 두는 방식이었는데,
///   되돌릴 수 없는 동작은 자주 쓰는 행 옆이 아니라 **공간으로도** 떨어져 있어야 한다(destructive-nav-separation).
///   그래서 로그아웃만 카드에 남기고, 탈퇴는 카드 아래 회색 글자 링크로 둔다 — 37 이 이미 빨간
///   「탈퇴하기」 버튼과 비밀번호 확인을 갖고 있어 여기서까지 빨강으로 부를 이유가 없다.
///
/// 상태(디스크립션):
/// - **없는 기능은 행을 만들지 않는다.** 고객센터는 서버 API 가 없어 빠져 있고
///   (`docs/BACKEND-GAP-CLEANUP.md`), 매너 점수 · 마일리지 · 결제 수단도 같은 이유로 없다.
///   **「지난 탑승 기록」만 2026-11-01 에 들어왔다** — 서버에 `GET /api/v1/users/me/parties` 가
///   생겨 「없다」가 더 이상 사실이 아니게 됐다(`docs/BACKEND-GAP-CLEANUP.md` §6).
///   레퍼런스에 있는 「로그인 수단 안내」도 두지 않았다 — 지금 이 화면이 아는 서버 값은 이름과
///   프로필 사진뿐이고, 로그인 수단은 추측해서 적을 값이 아니다.
/// - 「안내」 행은 `links` 의 주소가 nil 이면 그리지 않고, 셋 다 nil 이면 **카드와 머리말까지**
///   사라진다(`myPageGroups` 가 판정하고 `MyPageMenuRulesTest` 가 고정한다).
/// - 앱 안에 알림 토글을 두지 않는 이유는 `openAppNotificationSettings` 의 설명과 같다
///   (서버에 알림 설정 저장 API 가 없어 앱만의 토글은 지키지 못할 약속이 된다).
/// - **제재 배너가 「왜 막혔나」를 말하는 유일한 자리다**(2026-11-06). 노쇼 횟수 × 24시간 동안 방
///   만들기·합류·예약 생성이 **전부 403 `NO_SHOW_RESTRICTED`** 로 막히는데(「걸어서 가까운 방」 후보
///   조회는 막히지 않는다 — `UserProfileInfo.restrictedUntil` 주석), 그 403 을 받는 화면들은 「지금 이
///   동작이 막혔다」까지만 말할 수 있다(그 말도 16 예약 생성만 하고, 실시간 생성·합류는 원본처럼
///   일반 문구로 떨어진다) — 기한과 횟수는 프로필 조회에만 있다.
///   그래서 막힌 사람이 「내 계정에 무슨 문제가 있나」를 찾아 오는 이 화면에 둔다. 판정과 문구는
///   `noShowSanction` 이고, **제한이 없고 노쇼도 0건이면 배너 자체가 없다**(「제재 없음」 배지를
///   만들지 않는다 — 아무 일 없는 사용자에게 제재 어휘를 가르칠 이유가 없다).
/// - 이름과 프로필 사진이 서버 값이다(GET /local/users/info — 이름은 닉네임, 없으면 실명).
///   둘 다 한 번의 조회에서 함께 오고, **조회 전에는 둘 다 자리만 비워 둔다**(스켈레톤·빈 원).
///   사진을 고른 적 없는 사용자에게도 서버는 기본 이미지 주소를 주므로, 로딩 중에 그리면
///   기본 이미지가 한 번 스쳐 보인다. 사진은 36 에서 서버가 주는 16장 중에 고른다.
/// - 하단 버전 표기는 설치된 앱의 표시 버전이다(읽기 실패 시 숨김).
///
/// 개발자 옵션 절은 없다. 유일한 항목이었던 「동승/택시 모드 강제」가 모드와 함께 사라졌고
/// (서버가 `taxiEnabled` 를 보내지 않는다), 빈 절만 남기면 디버그 빌드에 아무것도 없는 제목이 뜬다.
/// 새 개발자 옵션이 필요해지면 그때 절을 다시 세운다.
public struct MyPageScreen: View {
    // 로그인 사용자의 표시 이름(닉네임)·프로필 사진 주소·**노쇼 횟수와 제한 기한**. 넷 다 같은 한 번의
    // 조회(GET /local/users/info)에서 오므로 한 상태로 받는다 — 파라미터를 쪼개면 "이름은 왔는데
    // 제재는 아직"이라는 있을 수 없는 조합이 타입으로 표현돼 버린다(아바타 호출부 주석의 그 이유).
    // 조회 전에는 loading(이름·사진 자리를 비우고 제재 배너도 그리지 않는다).
    private let userName: UserNameState
    private let onEditProfile: () -> Void          // → 36 프로필 수정
    private let onRideHistory: () -> Void          // → 34 지난 탑승 기록
    private let onNoShowRecords: () -> Void        // → 38 노쇼 기록·이의 신청
    private let onLogout: () -> Void               // → 04a 로그인 (세션 정리 후)
    private let onDeleteAccount: () -> Void        // → 37 회원 탈퇴
    private let onTabSelect: (MoyeotaTab) -> Void  // → 14 / 17 / 24
    // 「안내」 카드가 여는 주소. 기본값은 운영 값이고, 테스트가 빈 상태를 넣어 본다.
    private let links: SupportLinkTargets

    // 오탭 한 번으로 세션이 날아가지 않도록 확인을 한 단계 둔다 (와이어프레임의 확인 다이얼로그)
    @State private var logoutConfirming = false

    public init(
        userName: UserNameState = .loading,
        onEditProfile: @escaping () -> Void = {},
        onRideHistory: @escaping () -> Void = {},
        onNoShowRecords: @escaping () -> Void = {},
        onLogout: @escaping () -> Void = {},
        onDeleteAccount: @escaping () -> Void = {},
        onTabSelect: @escaping (MoyeotaTab) -> Void = { _ in },
        links: SupportLinkTargets = SupportLinkTargets()
    ) {
        self.userName = userName
        self.onEditProfile = onEditProfile
        self.onRideHistory = onRideHistory
        self.onNoShowRecords = onNoShowRecords
        self.onLogout = onLogout
        self.onDeleteAccount = onDeleteAccount
        self.onTabSelect = onTabSelect
        self.links = links
    }

    // 화면은 「무엇을 누르면 어디로 간다」만 안다. 앱 밖 이동은 ExternalIntents 가 맡는다.
    // switch 가 빠짐없이 갈라야 하므로, 행 종류가 늘면 여기서 컴파일이 막힌다.
    private func onAction(_ action: MyPageAction) {
        switch action {
        case .notificationSettings: openAppNotificationSettings()
        case .openWeb(let url): openWebPage(url: url)
        case .sendMail(let address): openSupportEmail(address: address)
        case .rideHistory: onRideHistory()
        case .noShowRecords: onNoShowRecords()
        case .logout: logoutConfirming = true
        case .deleteAccount: onDeleteAccount()
        }
    }

    public var body: some View {
        let versionLabel = appVersionName().map { "v\($0)" }
        let groups = myPageGroups(links: links)

        VStack(spacing: 0) {
            StatusBarSpacer()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // 탭 첫 화면의 머리줄 — 채팅·동승 탭과 같은 크기·여백이다(G7)
                    MoyeotaTabHeader(title: "마이페이지")

                    Spacer().frame(height: 8)
                    profileCard

                    // 제재 배너는 **프로필 카드 바로 아래**다. 「계정에 무슨 문제가 있나」를 찾아 들어온
                    // 사람이 스크롤하지 않고 보는 자리이고, 바로 다음 카드의 둘째 행이 「노쇼 기록」이라
                    // 배너가 가리키는 길이 같은 화면 안에 보인다.
                    //
                    // 디자인시스템의 NoticeBanner 를 그대로 쓴다 — 이 앱의 「화면 단위 안내」는 이 컴포넌트
                    // 하나이고(공통 규칙), 제재를 위해 새 카드 모양을 만들면 이 화면에만 있는 시각 언어가
                    // 하나 늘어난다. 색은 두 가지뿐이다: 지금 막혀 있으면 error, 횟수만 남았으면 waiting.
                    if let sanction {
                        Spacer().frame(height: 12)
                        NoticeBanner(kind: sanctionNoticeKind(sanction.kind), text: sanction.text)
                            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    }

                    Spacer().frame(height: 24)
                    // 머리말 + 흰 카드 + 구분선으로 나뉜 행들. 같은 그룹의 행은 한 카드 안에 묶는다
                    // — 카드가 그룹의 경계고, 그래서 머리말이 무엇에 걸리는 말인지가 눈에 보인다.
                    ForEach(groups, id: \.label) { group in
                        MyPageMenuCard(group: group, onAction: onAction)
                    }

                    // 버전은 맨 아래 가운데. 사용자가 찾는 값이 아니라 **물어볼 때 읽어 주는** 값이라
                    // 눈에 걸리지 않는 자리에 둔다(문의 메일에도 같은 값이 자동으로 들어간다).
                    // 한글이 없는 글이라 한글 글자 상자(`hangulTrimmed`)를 쓰지 않는다.
                    if let versionLabel {
                        Text(versionLabel)
                            .moyeotaText(.CaptionMd, color: MoyeotaColor.TextMute)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    }

                    Spacer().frame(height: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 원본 `rememberScrollState` 는 저장 상태라 탭을 다녀와도 읽던 자리가 남는다
                .savedScrollOffset("mypage.scroll")
            }
            .scrollBounceBehavior(.basedOnSize)
            // 원본 `verticalScroll` 은 자기 칸에서 잘린다. SwiftUI `ScrollView` 는 안전 영역까지 그려 내용이 상태바에 겹친다.
            .clipped()

            // 하단탭 홈 / 합승 / 채팅 → 14 / 17 / 24
            MoyeotaBottomBar(selected: .mypage, onSelect: onTabSelect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 묶음 목록(inset-grouped) 화면이라 바탕은 SurfaceSoft 다 — 흰 카드가 면의 차이로 묶음이 된다(G2)
        .background(MoyeotaColor.SurfaceSoft)
        .overlay {
            if logoutConfirming {
                // 앱 공용 확인 다이얼로그(G11). 확인 버튼은 예전처럼 빨강 — 세션이 끝나는 이탈이다
                MoyeotaConfirmDialog(
                    title: "로그아웃할까요?",
                    confirmText: "로그아웃",
                    onConfirm: {
                        logoutConfirming = false
                        onLogout()
                    },
                    onDismiss: { logoutConfirming = false },
                    body: "다시 이용하려면 아이디로 로그인해야 해요",
                    dismissText: "취소",
                    destructive: true
                )
            }
        }
        // 원본 `remember` 는 화면이 컴포지션에서 빠지면 사라진다. `@State` 는 스택에 있는 동안 남으므로 직접 비운다.
        .onDisappear { logoutConfirming = false }
    }

    // 프로필 카드 → 36 프로필 수정. 꺾쇠는 "눌러서 갈 곳이 있다"는 표시다
    // — 갈 화면이 없던 동안에는 일부러 꺾쇠도 탭 동작도 두지 않았다.
    private var profileCard: some View {
        Button(action: onEditProfile) {
            HStack(spacing: 0) {
                // 아바타의 인증 체크 배지는 두지 않는다 — 서버가 학교·재직 인증 여부를 주지 않는
                // 지금은 체크 표시 자체가 거짓 신호다.
                //
                // 사진 주소를 따로 받지 않고 `userName` 에서 꺼낸다 — 이름과 사진은 같은 한 번의
                // 조회(GET /local/users/info)에서 함께 오는 값이라, 파라미터를 하나 더 두면
                // "이름은 왔는데 사진은 아직"이라는 있을 수 없는 조합이 타입으로 표현돼 버린다.
                //
                // loading 이면 nil 이고, 그래서 **로딩 중에는 요청조차 만들지 않는다.**
                // 바로 아래 이름이 스켈레톤인 것과 같은 이유다 — 서버는 고른 적 없는 사용자에게도
                // 기본 이미지 주소를 주므로, 로딩 중에 그리면 기본 이미지가 한 번 스쳐 보인다.
                //
                // label 은 비워 둔다. 이니셜을 깔면 사진 로드에 실패했을 때 옆 18pt 이름과 같은 글자가
                // 두 번 보인다 — 여기는 이름이 바로 옆에 있는 자리라 이니셜이 주는 정보가 없다.
                AvatarCircle(size: 56, imageUrl: resolvedImageUrl)
                Spacer().frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 0) {
                    switch userName {
                    // 조회 전 — 폴백 문구가 스쳐 보이지 않게 자리만 잡아 둔다
                    case .loading:
                        MoyeotaColor.Hairline
                            .frame(width: 88, height: 18)
                            .clipShape(MoyeotaShape.Small)
                    case .resolved(let name, _, _, _, _):
                        Text(name ?? "이름 미설정")
                            .moyeotaText(
                                MoyeotaType.HeadingLg.hangulTrimmed,
                                color: name != nil ? MoyeotaColor.InkPrimary : MoyeotaColor.TextMute
                            )
                    }
                    Spacer().frame(height: 4)
                    // 36 에서 바꿀 수 있는 것을 **빠짐없이 적는다.** 사진을 고를 수 있게 되면서
                    // 「닉네임 바꾸기」는 거짓이 됐지만, 그렇다고 「프로필 수정」으로 넓히지는 않았다
                    // — 실명·생년월일·성별·휴대폰·이메일은 서버에 수정 경로가 아예 없어서
                    // 「프로필 수정」을 보고 전화번호를 바꾸려 들어온 사람은 헛걸음을 한다.
                    // 바꿀 수 있는 둘을 그대로 적는 쪽이 들어가기 전에 알려 준다.
                    // (36 의 상단바 제목은 「프로필 수정」이다 — 그쪽은 들어온 뒤에 보는 글이라
                    //  무엇을 바꿀 수 있는지는 화면 안의 입력칸이 이미 말하고 있다.)
                    // 세 번째 값이 수정 가능해지면 이 라벨은 더 못 늘어난다. 그때가 「프로필 수정」
                    // 으로 넓힐 자리다.
                    Text("닉네임·사진 바꾸기")
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ChevronIcon()
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(MoyeotaColor.SurfaceCanvas)
        }
        .buttonStyle(PressOverlayStyle(shape: Rectangle()))
        .clipShape(MoyeotaShape.Card)
        .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
    }

    private var resolvedImageUrl: String? {
        if case .resolved(_, let imageUrl, _, _, _) = userName { imageUrl } else { nil }
    }

    // 제재 배너. 프로필 조회가 끝나기 전(loading)에는 그리지 않는다 — 이름·사진과 같은 이유다
    // (조회 전에 「제한 없음」을 그리는 일도, 「제한 중」을 그리는 일도 없어야 한다).
    //
    // 기한이 지나는 순간을 **초 단위로 따라가지 않는다.** 화면을 열어 둔 채로 24시간 제한이 끝나면
    // 배너가 잠깐 남는데, 그걸 없애려면 타이머를 돌려야 하고 그 타이머는 마이페이지에 상주하는
    // 유일한 반복 작업이 된다. 서버가 풀린 사실은 다음 조회에서 nil 로 온다.
    //
    // 원본 `remember(userName)` 은 키가 바뀔 때만 다시 잰다. 여기서는 본문을 다시 그릴 때마다 재는데,
    // 다시 그리는 계기(확인창 열고 닫기 등)에 기한이 이미 지났으면 원본보다 그만큼 일찍 「제한 중」이
    // 내려올 뿐이고 없는 제한을 말하는 일은 없다.
    private var sanction: NoShowSanction? {
        guard case .resolved(_, _, let noShowCount, let restrictedUntil, _) = userName else { return nil }
        return noShowSanction(noShowCount: noShowCount, restrictedUntil: restrictedUntil)
    }

    // 색은 두 가지뿐이다(판정 파일은 색을 모른다 — `NoShowRecordsDisplay` 머리말).
    private func sanctionNoticeKind(_ kind: NoShowSanctionKind) -> NoticeKind {
        switch kind {
        case .restricted: .error
        case .counted: .waiting
        }
    }
}

/// 머리말 + 카드 + (있으면) 카드 밖 회색 링크 + (있으면) 그 아래 한 줄.
///
/// 행마다 아이콘을 두지 않는다 — 글자 네 개짜리 목록에서 행마다 붙인 아이콘은 구분이 아니라 장식이다.
/// 대신 오른쪽 기호 두 개에만 뜻을 준다(`MyPageRowMark`: 바깥 화살표 = 앱 밖, 꺾쇠 = 앱 안). 두 기호는
/// 디자인시스템의 그린 아이콘 한 벌(`ExternalLinkIcon`·`ChevronIcon`, 16pt)을 쓴다.
///
/// **되돌릴 수 없는 행(`MyPageRow.danger`)은 카드에 넣지 않는다**(디자인 QA M2) — 카드 아래 회색 글자
/// 링크로 떼어 자주 쓰는 행과 공간으로 떨어뜨린다. 모델(`myPageGroups`)의 행 순서와 동작은 그대로다.
///
/// 빈 그룹은 `myPageGroups` 가 미리 걸러내므로 여기 오지 않는다. 그래도 방어로 한 줄 둔다
/// — 빈 카드는 "고장난 메뉴"로 보이고, 머리말만 남으면 더 이상하다.
private struct MyPageMenuCard: View {
    let group: MyPageGroup
    let onAction: (MyPageAction) -> Void

    var body: some View {
        if !group.rows.isEmpty {
            let cardRows = group.rows.filter { !$0.danger }
            let linkRows = group.rows.filter(\.danger)
            SectionLabel(text: group.label)
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            if !cardRows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(cardRows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            // 구분선은 글자 시작선에 맞춰 들여 둔다 — 카드 폭을 꽉 채우면 행이 카드에서 떨어져 보인다
                            HorizontalDivider(color: MoyeotaColor.Hairline)
                                .padding(.horizontal, 16)
                        }
                        Button {
                            onAction(row.action)
                        } label: {
                            HStack(spacing: 0) {
                                Text(row.text)
                                    .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                switch row.mark {
                                case .external: ExternalLinkIcon()
                                case .chevron: ChevronIcon()
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressOverlayStyle(shape: Rectangle()))
                    }
                }
                .frame(maxWidth: .infinity)
                .background(MoyeotaColor.SurfaceCanvas)
                .clipShape(MoyeotaShape.Card)
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            }
            ForEach(Array(linkRows.enumerated()), id: \.offset) { _, row in
                // 글자 링크의 안쪽 여백(8)만큼 덜 들여 글자 시작을 카드 가장자리(16)에 맞춘다
                TextLinkButton(
                    text: row.text,
                    onClick: { onAction(row.action) },
                    color: MoyeotaColor.TextMute,
                    style: MoyeotaType.BodySm
                )
                .padding(.leading, MoyeotaSpacing.ScreenGutter - 8)
                .padding(.top, 4)
            }
            if let caption = group.caption {
                // 카드(와 탈퇴 링크) **아래**에 둔다. 행 안에 넣으면 56pt 행이 두 줄로 늘어나 다른 행과 높이가
                // 달라지고, 카드 위에 두면 머리말과 붙어 무엇에 걸리는 말인지 흐려진다.
                Text(caption)
                    .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    .padding(.top, linkRows.isEmpty ? 8 : 0)
            }
            Spacer().frame(height: 24)
        }
    }
}

extension MyPageScreen {
    /// 테스트가 확인창이 열린 상태를 만드는 입구. 창에 올린 화면이라도 코드로는 SwiftUI 버튼을 누를 수 없다.
    func seeded(logoutConfirming: Bool) -> Self {
        var copy = self
        copy._logoutConfirming = State(initialValue: logoutConfirming)
        return copy
    }
}
