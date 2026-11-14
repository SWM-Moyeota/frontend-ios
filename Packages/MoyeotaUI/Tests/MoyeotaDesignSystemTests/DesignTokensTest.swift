import SwiftUI
import Testing
import UIKit
@testable import MoyeotaDesignSystem

// 원본에 없는 테스트. 원본 토큰은 Kotlin 상수라 단위 테스트가 없다. iOS 는 디자인 다듬기(2026-11)의 토큰 표를 옮기며
// 값을 손으로 옮겼으므로, 표의 값과 "뜻이 갈리는" 두 곳(info 의 배너·배지 색, 숫자 폭 고정)을 여기서 못 박는다.

/// `Color` → 0xAARRGGBB (sRGB, 반올림)
private func argb(_ color: Color) -> UInt32 {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
    return byte(a) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b)
}

@Suite struct DesignTokensTest {
    @Test("다듬기에서 더한 색 토큰은 원본 값 그대로다")
    func newColors() {
        #expect(argb(MoyeotaColor.TextPlaceholder) == 0xFF9AA1AC)
        #expect(argb(MoyeotaColor.SurfaceDisabled) == 0xFFE8EBF0)
        #expect(argb(MoyeotaColor.Border) == 0xFFE2E6EC)
        #expect(argb(MoyeotaColor.BorderStrong) == 0xFFD1D5DB)
        #expect(argb(MoyeotaColor.ShadowOverlay) == 0x1A1B2A4A)
        #expect(argb(MoyeotaColor.ShadowSheet) == 0x141B2A4A)
        #expect(argb(MapOverlayShadow) == argb(MoyeotaColor.ShadowOverlay), "옛 이름은 같은 값을 가리킨다")
    }

    @Test("글자 표 — BodyStrong 은 15/600/1.4, CaptionMd 는 500 이다")
    func typeTable() {
        #expect(MoyeotaType.BodyStrong.fontSize == 15)
        #expect(MoyeotaType.BodyStrong.fontWeight == .semibold)
        #expect(MoyeotaType.BodyStrong.lineHeight == .em(1.4))
        #expect(MoyeotaType.CaptionMd.fontWeight == .medium)
        #expect(MoyeotaType.CaptionMd.letterSpacing == 0.2)
        #expect(MoyeotaType.bodyStrong == MoyeotaType.BodyStrong)
    }

    @Test("tabularNums 는 숫자 폭만 고정하고 나머지 값은 그대로 둔다")
    func tabularNums() {
        let tabular = MoyeotaType.BodyMd.tabularNums()
        #expect(tabular.monospacedDigits)
        #expect(!MoyeotaType.BodyMd.monospacedDigits)
        #expect(tabular.fontSize == 15 && tabular.lineHeight == .em(1.5))
        let one = ("1" as NSString).size(withAttributes: [.font: tabular.uiFont]).width
        let eight = ("8" as NSString).size(withAttributes: [.font: tabular.uiFont]).width
        #expect(abs(one - eight) < 0.01, "고정폭 숫자는 1 과 8 의 폭이 같다")
    }

    @Test("간격·모서리·그림자 높이 표")
    func layoutTokens() {
        #expect([MoyeotaSpacing.Xxs, MoyeotaSpacing.Xs, MoyeotaSpacing.Sm, MoyeotaSpacing.Md, MoyeotaSpacing.Lg, MoyeotaSpacing.Xl]
            == [4, 8, 12, 16, 24, 32])
        #expect(MoyeotaSpacing.ScreenGutter == 16 && MoyeotaSpacing.SectionGap == 24)
        #expect([MoyeotaShape.SmallRadius, MoyeotaShape.CardRadius, MoyeotaShape.SheetRadius, MoyeotaShape.DialogRadius]
            == [6, 12, 20, 20])
        #expect([MoyeotaElevation.MapOverlay, MoyeotaElevation.Sheet, MoyeotaElevation.Modal] == [4, 8, 12])
        #expect([MoyeotaIconSize.Lg, MoyeotaIconSize.Md, MoyeotaIconSize.Sm] == [24, 20, 16])
        #expect(IconStrokeWidth == 1.75)
        #expect(abs(iconStroke(16.0 / 24).lineWidth - 1.75 * 16 / 24) < 0.0001, "선 굵기는 아이콘 크기에 비례한다")
    }

    @Test("info 는 배너에서 회색, 배지에서 옅은 파랑이다 — neutral 은 둘 다 회색")
    func noticeColors() {
        #expect(argb(NoticeKind.info.bannerColors.background) == argb(MoyeotaColor.SurfaceSoft))
        #expect(argb(NoticeKind.info.bannerColors.foreground) == argb(MoyeotaColor.TextBody))
        #expect(argb(NoticeKind.info.badgeColors.background) == argb(MoyeotaColor.Primary50))
        #expect(argb(NoticeKind.info.badgeColors.foreground) == argb(MoyeotaColor.Primary600))
        #expect(argb(NoticeKind.neutral.bannerColors.background) == argb(MoyeotaColor.SurfaceSoft))
        #expect(argb(NoticeKind.neutral.badgeColors.foreground) == argb(MoyeotaColor.TextBody))
        // 색이 뜻을 싣는 셋은 배너·배지가 같다
        for kind in [NoticeKind.error, .success, .waiting] {
            #expect(argb(kind.bannerColors.background) == argb(kind.badgeColors.background))
            #expect(argb(kind.bannerColors.foreground) == argb(kind.badgeColors.foreground))
        }
    }

    @Test("요금 요약의 설명 줄은 정원을 넣어 읽는다")
    func fareNote() {
        #expect(fareSummaryNote(capacity: 3) == "총 예상 요금을 정원 3명으로 나눈 금액이에요")
    }
}
