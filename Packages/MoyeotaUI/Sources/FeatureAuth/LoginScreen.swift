import MoyeotaDesignSystem
import PresentationCore
import SwiftUI

/// 04 시작 화면의 신뢰 불릿 두 줄. 둘 다 서버 동작으로 확인한 사실이다.
///
/// - 휴대폰 인증: 문자 인증 토큰이 없으면 서버가 가입을 `USER207 PHONE_NOT_VERIFIED` 로 거절한다
///   (`AuthError.phoneNotVerified`). 앱만의 검사가 아니라 **서버가 막는다**.
/// - 탑승 횟수: 서버 `PartyDetailResult.MemberInfo.rideCount` 를 20·21·22·23 이 그대로 그린다
///   (`User.rideCountLabel`).
///
/// 2026-10-13 에 지운 두 줄과 이유:
/// - 「같은 성별끼리만 매칭돼요」 — **성별 조건 매칭이 없다.** 성별은 가입 때 받아 `UserProfile` 에
///   저장될 뿐이고, 백엔드 `matching` 패키지 어디에도 성별이 등장하지 않는다.
/// - 「운행 중 위치를 지인과 공유할 수 있어요」 — **위치 공유 기능이 없다**
///   (`docs/BACKEND-GAP-CLEANUP.md` §1 에서 보호자 공유·동승자 위치 보고를 전부 제거했다).
///
/// 불릿은 **두 줄로 유지한다** — 화면 높이가 두 줄 기준으로 맞춰져 있다.
/// (2026-11 디자인 QA A1: 그림자 카드를 걷어내고 페이지 위에 바로 놓았다 — 카드 하나에 두 줄을 담으면
/// "강조 상자"가 되어 바로 아래 CTA 와 시선을 다툰다.)
let LoginTrustBullets = [
    "휴대폰 인증을 마친 사람만 가입해요",
    "함께 탈 사람의 탑승 횟수가 보여요",
]

/// `signupConsentNotice` 의 결과. 원본 `AnnotatedString` 과 그 안의 링크 리스너 자리다.
///
/// `Text` 는 링크를 `\.openURL` 로 보내므로 콜백을 글자 안에 넣을 수 없어 함께 들고 있다.
struct SignupConsentNotice {
    let attributed: AttributedString
    let onOpen: (String) -> Void

    /// `AnnotatedString.text` 자리.
    var text: String { String(attributed.characters) }

    /// 링크가 걸린 주소들. 문장 순서다.
    var urls: [String] { attributed.runs.compactMap { $0.link?.absoluteString } }
}

/// 「가입하면 이용약관 · 개인정보 처리방침에 동의하게 돼요」 — **문서 이름 두 조각만** 링크다.
///
/// 문장은 주소가 있든 없든 똑같다. 동의하게 된다는 사실 자체는 주소와 무관하게 참이기 때문이다
/// (가입하면 실제로 그 두 문서에 동의한다). 주소가 nil 인 문서만 링크 없는 평범한 글자로 남는다
/// — 35 마이페이지가 행을 숨기는 것과 같은 원칙이다(죽은 링크를 보여 주지 않는다).
///
/// 링크를 누르면 `onOpen` 이 불린다. 시스템 기본 동작에 맡기지 않는 이유: 받아 줄 앱이 없으면 그대로
/// 아무 일도 없다. 앱의 다른 외부 이동과 똑같이 `ExternalIntents` 를 지나게 해서 안내 토스트로 바꾼다.
///
/// 줄 전체를 탭 영역으로 두지 않는다 — 두 문서를 가려낼 수 없어서다(그전에는 줄 전체에
/// 아무 일도 하지 않는 `clickable` 이 걸려 있었다).
func signupConsentNotice(
    termsUrl: String? = SupportLinks.TERMS_URL,
    privacyUrl: String? = SupportLinks.PRIVACY_URL,
    onOpen: @escaping (String) -> Void
) -> SignupConsentNotice {
    var notice = AttributedString("가입하면 ")
    notice += legalDocument(label: "이용약관", url: termsUrl)
    notice += AttributedString(" · ")
    notice += legalDocument(label: "개인정보 처리방침", url: privacyUrl)
    notice += AttributedString("에 동의하게 돼요")
    return SignupConsentNotice(attributed: notice, onOpen: onOpen)
}

/// 주소가 있으면 링크로, 없으면 그냥 글자로 붙인다. 12pt 회색 문장에서 링크만 파랑 + 밑줄이다.
/// 링크 글자색은 `Text` 가 `tint` 로 칠하므로 그리는 쪽에서 `MoyeotaColor.Link` 를 준다.
private func legalDocument(label: String, url: String?) -> AttributedString {
    var document = AttributedString(label)
    if let url, let target = URL(string: url) {
        document.link = target
        document.underlineStyle = .single
    }
    return document
}

/// 04 · 시작 — 로그인 방식 [S01]
///
/// 진입: 03 시작하기 · 온보딩 완료 후 재실행 · 로그아웃 직후
///
/// 소셜(카카오) 로그인은 없다 — 백엔드 AuthController 에 소셜 로그인 엔드포인트가 없고
/// 가입·로그인은 아이디/비밀번호뿐이다. 카카오 버튼과 「준비 중」 안내는 그래서 뺐다.
///
/// 신뢰 불릿은 `LoginTrustBullets` 에 있다 — 가입 전 마지막으로 "모여타가 무엇을 해 주는가"를
/// 말하는 자리라 **코드로 확인한 사실만** 적는다(2026-10-13).
public struct LoginScreen: View {
    private let onEmailStart: () -> Void
    private let onLogin: () -> Void

    /// - Parameter onEmailStart: 「이메일로 시작하기」 → 10 프로필 설정 (가입 1단계)
    /// - Parameter onLogin: 「로그인」(이미 계정이 있어요) → 04a 아이디 로그인
    public init(onEmailStart: @escaping () -> Void, onLogin: @escaping () -> Void) {
        self.onEmailStart = onEmailStart
        self.onLogin = onLogin
    }

    public var body: some View {
        let consentNotice = signupConsentNotice { url in openWebPage(url: url) }
        VStack(spacing: 0) {
            StatusBarSpacer()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 24)
                    Text("모여타")
                        .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)

                    Spacer().frame(height: 32)
                    Text("믿을 수 있는 사람과\n택시를 나눠 타요")
                        .moyeotaText(MoyeotaType.DisplayMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)

                    Spacer().frame(height: 16)
                    // 학교 이메일 인증은 가입 필수 경로가 아니다(마이페이지에서 나중에 추가하는 컨셉).
                    // 「학생만 · 학교 이메일로 확인」은 이제 사실이 아니라 지웠다.
                    Text("아이디로 간편하게 가입해요")
                        .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextMute)

                    Spacer().frame(height: 24)
                    VStack(alignment: .leading, spacing: 12) {
                        // 「학교 인증을 마친 학생만 매칭돼요」는 삭제 — 가입에 학교 인증 단계가 없어 사실이 아니다
                        ForEach(LoginTrustBullets, id: \.self) { TrustBulletRow(text: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 「이메일로 시작하기」 묶음은 스크롤 밖 = 화면 하단 고정.
            // 본문이 짧아 고정 Spacer 로 CTA 위치를 잡으면 본문 아래에 빈 공간이 남는다.
            // 하단 고정이면 남는 높이를 스크롤 영역이 흡수한다.
            VStack(spacing: 0) {
                PrimaryCtaButton(
                    text: "이메일로 시작하기",
                    onClick: onEmailStart
                )

                Spacer().frame(height: 4)
                HStack(alignment: .center, spacing: 0) {
                    Text("이미 계정이 있어요")
                        .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                    Spacer().frame(width: 4, height: 4)
                    // 글자 크기 그대로 눌리던 링크(≈19, 눌림 표시 없음)를 48 터치 + 눌림 표시로 바꿨다(디자인 QA G12)
                    TextLinkButton(
                        text: "로그인",
                        onClick: onLogin,
                        color: MoyeotaColor.Primary600
                    )
                }
                .frame(maxWidth: .infinity)

                Spacer().frame(height: 4)
                // 문구가 두 문서를 **이름으로** 부르므로 그 두 조각만 링크로 만든다. 2026-10-14 까지는
                // 줄 전체에 아무 일도 하지 않는 clickable 이 걸려 있었다(주소가 없어 열 곳이 없었다).
                // 이제 주소가 생겼고, 동의를 안내하는 자리에서 그 문서에 닿지 못하면 안내가 반쪽이다.
                // 11pt `#9AA1AC`(2.6:1)는 읽혀야 하는 동의 고지에 너무 흐렸다 — 캡션 크기·TextMute 로 올린다
                Text(consentNotice.attributed)
                    .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                    .tint(MoyeotaColor.Link)
                    .environment(\.openURL, OpenURLAction { url in
                        consentNotice.onOpen(url.absoluteString)
                        return .handled
                    })
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            .frame(maxWidth: .infinity)

            NavigationBarSpacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
    }
}

/// 회색 체크 + 안내 문구 한 줄.
///
/// 예전엔 22 파란 원 안의 흰 체크였다 — 화면 아래 파란 CTA 와 같은 색 덩어리가 두 개 더 생겨
/// "어디를 눌러야 하나"가 흐려졌다. 불릿은 누르는 것이 아니라 읽는 것이라 회색 선 아이콘으로 낮춘다.
private struct TrustBulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            CheckIcon(size: MoyeotaIconSize.Sm, tint: MoyeotaColor.TextMute)
            Spacer().frame(width: 8, height: 8)
            Text(text)
                .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextBody)
        }
    }
}
