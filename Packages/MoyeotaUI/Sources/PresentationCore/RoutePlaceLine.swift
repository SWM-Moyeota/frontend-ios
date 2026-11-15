import MoyeotaDesignSystem
import SwiftUI

/// 경로의 한 끝 — 「출발지: 강남역」의 **이름표**(「출발지」)와 **장소**(「강남역」).
///
/// 「강남역 → 판교역」 한 줄은 장소 이름이 길면(역지오코딩 실주소가 들어온다) 화살표 뒤가 잘려 **도착지가
/// 통째로 사라진다**. 두 줄로 나누고 각 줄에 이름표를 붙이면 잘려도 어느 쪽이 잘렸는지 남는다
/// (2026-11, 오너 UX 피드백 — 24 채팅 목록).
public struct RoutePlace: Hashable, Sendable {
    public var label: String
    public var place: String

    public init(label: String, place: String) {
        self.label = label
        self.place = place
    }
}

/// 출발지·도착지 두 줄. 이름표 문구를 한 곳에 둔다 — 화면마다 「출발」·「출발지」가 갈리지 않게.
public func routePlaces(departure: String, destination: String) -> [RoutePlace] {
    [
        RoutePlace(label: "출발지", place: departure),
        RoutePlace(label: "도착지", place: destination),
    ]
}

/// 「출발지: 강남역」 한 줄 — 이름표는 `TextMute`, 장소는 `TextBody`(디자인 QA 4-10), 둘 다 `BodySm`.
/// 한 줄을 넘으면 끝을 줄인다(이름표는 앞에 있어 늘 보인다).
///
/// 이름표와 장소를 **한 `Text`** 에 담는다 — 둘로 나누면 말줄임이 장소 쪽에만 걸리게 폭을 따로
/// 계산해야 하고, VoiceOver 도 한 문장(「출발지: 강남역」)으로 읽는 편이 자연스럽다.
/// 24 채팅 목록과 17 탐색 목록이 **이 조각 하나**를 쓴다(디자인 QA E5) — 두 화면의 이름표 모양이 어긋나지 않게.
///
/// - Parameter emphasizePlace: 장소를 `BodyStrong`·`InkPrimary` 로 — **장소가 그 줄의 제목인 자리**에서만 켠다
///   (17 실시간 목록: 줄에 방 이름 같은 다른 제목이 없다). 이름표는 그대로 `BodySm`·`TextMute` 라 두 화면의
///   「출발지:」는 같은 모양이다. 기본값 false 가 24 채팅 목록의 모양(방 이름이 제목, 장소는 부제)이다
public struct RoutePlaceLine: View {
    private let place: RoutePlace
    private let emphasizePlace: Bool

    public init(place: RoutePlace, emphasizePlace: Bool = false) {
        self.place = place
        self.emphasizePlace = emphasizePlace
    }

    public var body: some View {
        Text(routePlaceLineText(place, emphasizePlace: emphasizePlace))
            // 강조할 때는 문단 기준을 BodyStrong 으로 둬 줄 높이가 15 장소에 맞는다(이름표는 글자 안에서 13 으로 덮는다)
            .moyeotaText(emphasizePlace ? .BodyStrong : .BodySm)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// 한 줄의 글 — 이름표(「출발지: 」, `BodySm`·`TextMute`)와 장소(문단 글꼴, `TextBody` 또는 강조 시 `InkPrimary`).
/// 원본 `buildAnnotatedString` 자리.
func routePlaceLineText(_ place: RoutePlace, emphasizePlace: Bool = false) -> AttributedString {
    var label = AttributedString("\(place.label): ")
    label.font = MoyeotaType.BodySm.font
    label.foregroundColor = MoyeotaColor.TextMute
    var value = AttributedString(place.place)
    value.foregroundColor = emphasizePlace ? MoyeotaColor.InkPrimary : MoyeotaColor.TextBody
    return label + value
}
