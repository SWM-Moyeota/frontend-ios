import CoreGraphics

/// 간격 — 4/8 리듬(디자인 문서 spacing 표).
///
/// 화면 좌우 여백은 **`ScreenGutter` 하나**다. 예전엔 16·18·20·24 가 섞여 같은 화면 안에서도 글자의
/// 왼쪽 끝이 어긋났다(홈 시트: 제목 20, 「즐겨찾기」 16). 세로 간격도 10·11·13·14·17·18 같은 값을
/// 쓰지 않고 이 표로 올리거나 내린다.
public enum MoyeotaSpacing {
    public static let Xxs: CGFloat = 4
    public static let Xs: CGFloat = 8
    public static let Sm: CGFloat = 12
    public static let Md: CGFloat = 16
    public static let Lg: CGFloat = 24
    public static let Xl: CGFloat = 32

    /// 모든 화면·시트의 좌우 여백
    public static let ScreenGutter: CGFloat = 16

    /// 한 화면 안의 묶음과 묶음 사이
    public static let SectionGap: CGFloat = 24
}
