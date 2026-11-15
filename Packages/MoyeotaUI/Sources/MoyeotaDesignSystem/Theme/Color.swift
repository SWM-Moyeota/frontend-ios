import SwiftUI
import UIKit

// moyeota-figma-tokens.json 의 core.color 값 그대로
public enum MoyeotaColor {
    // primary
    public static let Primary500 = Color(argb: 0xFF085AF5)
    public static let Primary600 = Color(argb: 0xFF054BC7)
    public static let Primary700 = Color(argb: 0xFF033D9F)
    public static let Primary50 = Color(argb: 0xFFE6EEFE)

    // status
    public static let Success500 = Color(argb: 0xFF10B981)
    public static let Success600 = Color(argb: 0xFF0F8F66)
    public static let Success50 = Color(argb: 0xFFD1FAE5)
    public static let Waiting500 = Color(argb: 0xFFF59E0B)
    public static let Waiting600 = Color(argb: 0xFFB57407)
    public static let Waiting50 = Color(argb: 0xFFFEF3C7)
    public static let Danger500 = Color(argb: 0xFFE63946)
    public static let Danger600 = Color(argb: 0xFFB32836)
    public static let Danger50 = Color(argb: 0xFFFDECEE)

    // 비상 신고 전용 — 다른 곳 사용 금지
    public static let Safety500 = Color(argb: 0xFFDC2626)
    public static let Safety600 = Color(argb: 0xFFA81D1D)

    // ink / text
    public static let InkPrimary = Color(argb: 0xFF111111)
    public static let InkDeep = Color(argb: 0xFF0A0A0B)
    public static let TextBody = Color(argb: 0xB8111111)      // rgba(17,17,17,0.72)
    /// 보조 글자(메타·시각·설명). 흰 바탕 대비 4.8:1 — **정보를 싣는 회색은 이것 하나다.**
    /// 예전에 화면마다 따로 두던 `#8A93A0`(3.1:1)·`#9AA1AC`(2.6:1)는 WCAG 4.5:1 에 못 미쳐 여기로 모았다.
    public static let TextMute = Color(argb: 0xFF6B7280)
    /// 입력 자리표시자와 비활성 글자 **전용**. 흰 바탕 대비 2.6:1 이라 읽혀야 하는 정보에는 쓰지 않는다 —
    /// "아직 비어 있음"·"지금은 못 누름"처럼 흐린 것 자체가 뜻인 자리만.
    public static let TextPlaceholder = Color(argb: 0xFF9AA1AC)
    /// 읽지 않아도 되는 **장식 회색** — 시트 손잡이·비활성 페이지 점·비활성 아이콘 선. 흰 바탕 대비 1.47:1 이라
    /// 글자에는 쓰지 않는다(글자는 `TextPlaceholder`). `BorderStrong` 과 같은 값(디자인 문서의 ash-light).
    public static let TextAsh = Color(argb: 0xFFD1D5DB)
    public static let TextOnDark = Color(argb: 0xFFFFFFFF)
    public static let Link = Color(argb: 0xFF054BC7)

    // surface
    /// 기본 화면·시트 바탕(흰색). 설정형 묶음 목록(마이페이지·탑승 기록·노쇼 기록)만 `SurfaceSoft` 를 쓴다.
    public static let SurfaceCanvas = Color(argb: 0xFFFFFFFF)
    /// 흰 화면 안의 옅은 면(검색 입력·상대 말풍선·읽기 전용 칸)과 묶음 목록 화면의 바탕
    public static let SurfaceSoft = Color(argb: 0xFFF4F6FA)
    public static let SurfaceCard = Color(argb: 0xFFFFFFFF)
    /// 비활성 버튼 바탕. `SurfaceSoft` 로 칠하던 예전 값은 `SurfaceSoft` 화면 위에서 대비가 1.01:1 이라
    /// 버튼 모양이 **사라지고** 회색 글자만 떠 있었다.
    public static let SurfaceDisabled = Color(argb: 0xFFE8EBF0)
    public static let MapOverlay = Color(argb: 0xF0FFFFFF)    // rgba(255,255,255,0.94)
    /// 구분선·진행 막대 바닥 — 면을 나누는 가장 옅은 선
    public static let Hairline = Color(argb: 0xFFEDEFF3)
    /// 칩·목록 카드의 테두리. `Hairline` 은 흰 바탕에서 1.15:1 이라 "모양"을 만들지 못한다
    public static let Border = Color(argb: 0xFFE2E6EC)
    /// 입력칸·보조 버튼의 테두리, 경로 연결 점선 — 디자인 문서의 ash-light
    public static let BorderStrong = Color(argb: 0xFFD1D5DB)

    // shadow — 그림자는 지도 위에 뜬 것과 시트 가장자리에만 쓴다(`MoyeotaElevation`)
    /// 지도 위 알약·버튼의 그림자 색
    public static let ShadowOverlay = Color(argb: 0x1A1B2A4A)
    /// 시트 가장자리·다이얼로그의 그림자 색
    public static let ShadowSheet = Color(argb: 0x141B2A4A)

    // route / marker
    public static let RouteShared = Color(argb: 0xFF085AF5)
    public static let RouteUserA = Color(argb: 0xFF3B82F6)
    public static let RouteUserB = Color(argb: 0xFF8B5CF6)
    public static let MarkerOrigin = Color(argb: 0xFF085AF5)
    public static let MarkerDestination = Color(argb: 0xFFEF4444)
    public static let MarkerPickup = Color(argb: 0xFF10B981)
    public static let MarkerDropoff = Color(argb: 0xFFF97316)

    public static let Scrim = Color(argb: 0x66000000)         // opacity.scrim 40%
}

public extension Color {
    /// Compose 의 `Color(0xAARRGGBB)` 자리. 값은 sRGB 다.
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }

    /// Compose 의 `color.copy(alpha = x)` 자리. `opacity(_:)` 는 원래 알파에 **곱하지만** 이것은 알파를 x 로 **바꾼다.**
    func copy(alpha: Double) -> Color {
        Color(uiColor: UIColor(self).withAlphaComponent(alpha))
    }

    /// 지도 오버레이처럼 `UIColor` 를 받는 자리에 넘길 때 쓴다 (Compose 의 `toArgb()` 자리).
    func toUIColor() -> UIColor {
        UIColor(self)
    }
}
