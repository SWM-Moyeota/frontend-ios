import MoyeotaDesignSystem
import SwiftUI

/// 01 · 온보딩 — 절약 [O01]
///
/// 진입: 로그인되지 않은 채 앱을 켤 때마다 시작 화면(`MainNavGraph.kt:448`). 원본 KDoc 의 「최초 실행 1회,
/// 마이 > 도움말에서 재열람」은 낡은 기록이다 — 원본에 그런 플래그도, 다른 진입 경로도 없다.
/// 목적: 1/N 절약 가치 전달
///
/// 인터랙션
/// - 「다음」 → 02 온보딩 신뢰 (onNext)
/// - 「건너뛰기」 → 04 로그인 (onSkip)
/// - 좌우 스와이프 → 02 (제스처, 프로토타입 미구현 → 미구현)
///
/// 검증·상태
/// - 화면은 콜백만 노출. 시작 분기는 `loggedIn` 하나뿐이고 온보딩 완료 플래그는 없다(원본 KDoc 과 다르다)
/// - 요금 예시(9,600 → 3,200)는 3인 기준 하드코딩 값
public struct OnboardingSavingScreen: View {
    private let onNext: () -> Void
    private let onSkip: () -> Void

    public init(onNext: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.onNext = onNext
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()

            // 건너뛰기 (우상단) — 48 터치 + 눌림 표시(디자인 QA G12). 링크 안쪽 8 만큼 줄 여백을 줄여
            // 글자 끝이 16 화면 여백에 선다
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                TextLinkButton(text: "건너뛰기", onClick: onSkip, color: MoyeotaColor.TextMute)
            }
            .padding(.horizontal, 8)

            Spacer().frame(height: 24)

            SavingIllustration()
                .frame(maxWidth: .infinity)
                .frame(height: 330)
                .padding(.horizontal, 16)

            Spacer().frame(height: 32)

            Text(OnboardingSavingCopy.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .moyeotaText(MoyeotaType.DisplayMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 12)

            Text(OnboardingSavingCopy.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 32)

            PageDots(count: 3, activeIndex: 0)

            Spacer(minLength: 0)

            PrimaryCtaButton(text: "다음", onClick: onNext)
                .padding(.horizontal, 16)

            Spacer(minLength: 0)

            NavigationBarSpacer()
        }
        // 작은 화면에서 넘치면 원본 Column 처럼 위를 고정하고 아래로 넘긴다(기본값이면 위아래로 나뉜다).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MoyeotaColor.SurfaceCanvas)
    }
}

/// 일러스트 — 요금 비교 (9,600원 → 3,200원) 두 알약만.
///
/// 예전엔 옅은 파란 판 위에 44pt 「₩」 글자를 담은 원이 있었다(디자인 QA A3). 글자를 그림 대신 쓴 장식이고,
/// 판까지 더해 파랑이 화면을 덮었다. 메시지는 두 금액이 전부 말하므로 그것만 흰 바탕에 남긴다.
/// 높이는 호출부가 주는 그대로 두어(다른 두 장과 같은 330) 페이지를 넘겨도 제목 자리가 흔들리지 않는다.
private struct SavingIllustration: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FarePill(
                text: "9,600원",
                background: MoyeotaColor.SurfaceCanvas,
                textColor: MoyeotaColor.InkPrimary,
                outlined: true
            )
            // 「→」 — 예전엔 더하기 기호였는데 두 금액은 더하는 관계가 아니라 줄어드는 관계다
            ChevronIcon(size: MoyeotaIconSize.Md, tint: MoyeotaColor.TextMute)
            FarePill(text: "3,200원", background: MoyeotaColor.Primary500, textColor: MoyeotaColor.TextOnDark)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FarePill: View {
    let text: String
    let background: Color
    let textColor: Color
    var outlined = false

    var body: some View {
        Text(text)
            .moyeotaText(MoyeotaType.HeadingLg.tabularNums().hangulTrimmed, color: textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(background, in: MoyeotaShape.Card)
            // 흰 알약은 흰 화면에서 모양이 사라지므로 테두리로 선다(디자인 QA G4)
            .overlay {
                if outlined {
                    MoyeotaShape.Card.strokeBorder(MoyeotaColor.Border, lineWidth: 1)
                }
            }
    }
}
