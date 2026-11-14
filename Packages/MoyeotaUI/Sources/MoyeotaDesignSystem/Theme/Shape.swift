import SwiftUI

/// 모서리 반경 — **이 넷 밖의 값을 쓰지 않는다**(디자인 QA G3, 2026-11).
///
/// 예전엔 카드 반경이 12·14·16·18, 시트 윗모서리가 20·24 로 화면마다 달랐다. 하나하나는 그럴듯해도
/// 나란히 놓이면 "화면마다 따로 만든" 티가 난다. 디자인 문서의 rounded 표(sm 6 · md 12 · lg 20 · full)로 모은다.
///
/// 원본 `RoundedCornerShape`·`CircleShape` 는 원호 모서리라 모두 `.circular` 다(`ShapeCornerStyleTest`).
/// 도형이 아니라 숫자가 필요한 자리(`Path(roundedRect:cornerRadius:)` 등)는 `…Radius` 값을 쓴다.
public enum MoyeotaShape {
    public static let SmallRadius: CGFloat = 6
    public static let CardRadius: CGFloat = 12
    public static let SheetRadius: CGFloat = 20
    public static let DialogRadius: CGFloat = 20

    /// 6 — 작은 선택 상자·진행 막대
    public static var Small: RoundedRectangle { RoundedRectangle(cornerRadius: SmallRadius, style: .circular) }

    /// 12 — 카드·목록 묶음·입력칸·안내 배너. 기본값이다
    public static var Card: RoundedRectangle { RoundedRectangle(cornerRadius: CardRadius, style: .circular) }

    /// 윗모서리만 20 — 화면 아래에서 올라오는 시트
    public static var Sheet: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: SheetRadius, topTrailingRadius: SheetRadius, style: .circular)
    }

    /// 20 — 확인 다이얼로그
    public static var Dialog: RoundedRectangle { RoundedRectangle(cornerRadius: DialogRadius, style: .circular) }

    /// 완전한 알약 — 모든 CTA·칩·상태 배지
    public static var Pill: Capsule { Capsule(style: .circular) }
}
