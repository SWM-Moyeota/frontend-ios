import SwiftUI

/// 그림자 높이 — **지도 위에 뜬 것만 그림자를 갖는다**(디자인 QA G4, 2026-11).
///
/// 예전엔 2·3·4·8·10·12·14 일곱 가지 그림자가 카드·칩·말풍선·목록 묶음에까지 붙어 있었고, 세 곳은
/// 파란 빛번짐이었다. 이미 흰 시트 **안에** 있는 카드에 그림자를 주면 시트와 카드가 같은 높이를 다투어
/// 화면이 떠 보인다. 흰 면 위에서 카드를 나눌 때는 그림자 대신 `MoyeotaColor.Border` 선이나
/// `MoyeotaColor.SurfaceSoft` 면을 쓴다.
///
/// | 단계 | 값 | 쓰는 곳 |
/// |---|---|---|
/// | `MapOverlay` | 4 | 지도 위 알약·원형 버튼 |
/// | `Sheet` | 8 | 아래에서 올라온 시트의 윗가장자리 |
/// | `Modal` | 12 | 진짜 겹침(드롭다운 메뉴·다이얼로그)만 |
///
/// 그림자 색은 늘 회청색이다 — 브랜드 파랑으로 물든 그림자는 쓰지 않는다.
/// 그리는 방식은 원본 `Modifier.shadow` 자리의 `moyeotaShadow` 다(앰비언트·스폿 두 겹의 근사).
public enum MoyeotaElevation {
    public static let MapOverlay: CGFloat = 4
    public static let Sheet: CGFloat = 8
    public static let Modal: CGFloat = 12
}

public extension View {
    /// 지도 위에 뜬 알약·버튼의 그림자(`MoyeotaElevation.MapOverlay`)
    func mapOverlayShadow<S: Shape>(_ shape: S) -> some View {
        moyeotaShadow(elevation: MoyeotaElevation.MapOverlay, shape: shape, spotColor: MoyeotaColor.ShadowOverlay)
    }

    /// 시트 윗가장자리 그림자(`MoyeotaElevation.Sheet`)
    func sheetShadow<S: Shape>(_ shape: S) -> some View {
        moyeotaShadow(elevation: MoyeotaElevation.Sheet, shape: shape, spotColor: MoyeotaColor.ShadowSheet)
    }

    /// 시트 윗가장자리 그림자 — 모양은 `MoyeotaShape.Sheet`(원본 기본값)
    func sheetShadow() -> some View {
        sheetShadow(MoyeotaShape.Sheet)
    }

    /// 드롭다운 메뉴·다이얼로그처럼 화면 위에 진짜로 겹치는 것의 그림자(`MoyeotaElevation.Modal`)
    func modalShadow<S: Shape>(_ shape: S) -> some View {
        moyeotaShadow(elevation: MoyeotaElevation.Modal, shape: shape, spotColor: MoyeotaColor.ShadowSheet)
    }
}
