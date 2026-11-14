import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 23 · 동승자 프로필 [S13]
///
/// 이동(디스크립션):
/// - 뒤로 → 22 탑승 상세 (onBack)
/// - 「채팅으로 물어보기」 → 24 채팅 (onChatClick)
///
/// 서버 계약(2026-09): 방 상세 `members[]` 가 주는 것은 닉네임·이미지·탑승 횟수뿐이다.
/// 그래서 이 화면은 그 값만 보여 준다 — 지표는 탑승 횟수 하나이고, 서버에 없는 평가·집계·검증
/// 항목은 「준비 중」 자리표시도 두지 않고 요소째 뺐다. 프로필은 사람을 판단하는 화면이라
/// 지어낸 수치나 빈 칸 하나가 그대로 신뢰의 근거가 된다.
///
/// ### 2026-11 디자인 QA (PP1)
/// - 지표가 하나뿐인데 88 그림자 카드에 담겨 있었다 — 칸 하나짜리 표는 표가 아니라 장식이다.
///   이름 아래 한 줄 「탑승 횟수 · 12회」로 줄였다
/// - CTA 는 앱 공용 `PrimaryCtaButton`(알약 52)이다. 예전 r16 · 56 · 파란 빛번짐 그림자 버튼은 이
///   화면에만 있는 모양이었다. 말풍선 아이콘은 `leadingIcon` 자리로 지켰다
/// - 머리줄은 하위 화면 공용 `MoyeotaTopBar`, 바탕은 흰색(G2)
public struct PartnerProfileScreen: View {
    private let user: User
    private let onBack: () -> Void
    private let onChatClick: () -> Void

    /// - Parameter user: 22·20 에서 탭한 그 멤버. 호출부가 반드시 넘긴다(기본값 없음).
    public init(user: User, onBack: @escaping () -> Void = {}, onChatClick: @escaping () -> Void = {}) {
        self.user = user
        self.onBack = onBack
        self.onChatClick = onChatClick
    }

    public var body: some View {
        let hasBadge = !user.verifiedLabel.isBlank

        VStack(spacing: 0) {
            StatusBarSpacer()
            MoyeotaTopBar(title: "프로필", onBack: onBack)

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)

                    // 아바타 + 인증 배지 — 인증 배지는 서버가 badgeId 를 주기 시작할 때만 붙인다.
                    // 아무나 체크 표시를 달면 "확인된 사람" 이라는 잘못된 신호가 된다.
                    ZStack(alignment: .bottomTrailing) {
                        MemberAvatar(user: user, size: 80)
                        if hasBadge {
                            CheckIcon(size: MoyeotaIconSize.Sm, tint: MoyeotaColor.TextOnDark)
                                .frame(width: 28, height: 28)
                                .background(MoyeotaColor.Primary500, in: Circle())
                        }
                    }
                    Spacer().frame(height: 12)
                    Text(user.displayNickname)
                        .moyeotaText(MoyeotaType.DisplayMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    // 서버가 배지 라벨을 줄 때만 한 줄 붙인다 — 없으면 줄째 생략한다
                    if hasBadge {
                        Spacer().frame(height: 4)
                        Text(user.verifiedLabel)
                            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                    }
                    Spacer().frame(height: 8)
                    // 서버가 주는 지표는 탑승 횟수 하나뿐이다 — 카드 없이 이름 아래 한 줄로 둔다.
                    // 원본 숫자(Roboto)는 폭이 모두 같아 「11회」와 「88회」의 폭이 같다. SF 는 1 이 좁아 숫자 폭을 고정한다.
                    Text("탑승 횟수 · \(user.rideCount <= 0 ? "첫 탑승" : "\(user.rideCount)회")")
                        .moyeotaText(MoyeotaType.BodyMd.tabularNums().hangulTrimmed, color: MoyeotaColor.TextBody)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Spacer().frame(height: 24)

                    // 「학번」은 지웠다 — 학교 인증(06·07)이 가입 경로에 없어 학번을 받은 적이 없다.
                    // 서버가 주는 멤버 정보는 publicId·닉네임·이미지·탑승 횟수뿐이다(2026-10-13).
                    Text("실명과 연락처는 서로에게 공개되지 않아요")
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Spacer().frame(height: 16)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)

            // CTA — 채팅으로 물어보기 → 24 채팅
            PrimaryCtaButton(text: "채팅으로 물어보기", onClick: onChatClick) {
                ChatBubbleIcon(size: 18, tint: MoyeotaColor.TextOnDark)
            }
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            Spacer().frame(height: 16)
            NavigationBarSpacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
    }
}
