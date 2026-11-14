import SwiftUI

/// 출발·도착 점 지름 — 예전 11 은 이름 글자보다 무거워 보였다
private let RouteDotSize: CGFloat = 8

/// 점과 이름 사이
private let RouteDotGap: CGFloat = 12

/// 점선의 기준 좌표계 이름
private let RouteSummarySpace = "routeSummary"

/// 출발지 → 도착지 요약 — 16 도착지 확인, 20 합류 확인, 22 탑승 상세가 함께 쓴다 (디자인 QA G9, 2026-11).
///
/// 예전엔 세 화면이 각자 그렸고 셋 다 **옅은 파란 판 위에 15 Bold 네 줄**이었다: 이름과 시각이 같은 무게라
/// 무엇이 중요한지 읽히지 않았고, 흰 시트 안에 파란 판·회색 판이 겹겹이 쌓여 "AI 가 만든 카드 더미"로 보였다.
///
/// - **판(배경)이 없다.** 흰 시트 위에 바로 놓인다
/// - 점 8(`MoyeotaColor.MarkerOrigin`·`MoyeotaColor.MarkerDestination`) — 지도 표식과 같은 색
/// - 장소 이름 `MoyeotaType.BodyStrong` 한 줄 말줄임(역지오코딩 실주소가 들어와도 오른쪽 시각을 밀어내지 않는다)
/// - 오른쪽 시각·소요 시간 `MoyeotaType.BodyMd` `MoyeotaColor.TextBody`, 숫자 폭 고정(`tabularNums()`)
/// - 두 점 사이는 1.5 `MoyeotaColor.BorderStrong` 점선. 줄 높이와 상관없이 **점 가운데에서 점 가운데까지**
///   이어지도록 위치를 재어 그린다 — 「조정」 버튼(48 터치)이 있으면 줄이 높아져도 선이 끊기지 않는다
/// - `connectorNote`(「내 위치에서 350m」)는 점선 옆 `MoyeotaType.CaptionMd` `MoyeotaColor.TextMute`
///
/// - Parameters:
///   - originMeta: 출발 줄 오른쪽(「오후 7:51」·「오늘 오후 9:30 출발」). nil/빈 값이면 비운다
///   - destinationMeta: 도착 줄 오른쪽(「오후 8:16 도착」·「약 25분」)
///   - onAdjustOrigin: 있으면 출발 줄 끝에 「조정」(16 의 좌표 조정 진입점). 없으면 그리지 않는다
public struct RouteSummary: View {
    private let origin: String
    private let destination: String
    private let originMeta: String?
    private let destinationMeta: String?
    private let connectorNote: String?
    private let onAdjustOrigin: (() -> Void)?
    private let onAdjustDestination: (() -> Void)?

    // 두 점의 세로 가운데 — 점선을 그 사이에 긋는다
    @State private var originCenterY: CGFloat = 0
    @State private var destinationCenterY: CGFloat = 0

    public init(
        origin: String,
        destination: String,
        originMeta: String? = nil,
        destinationMeta: String? = nil,
        connectorNote: String? = nil,
        onAdjustOrigin: (() -> Void)? = nil,
        onAdjustDestination: (() -> Void)? = nil
    ) {
        self.origin = origin
        self.destination = destination
        self.originMeta = originMeta
        self.destinationMeta = destinationMeta
        self.connectorNote = connectorNote
        self.onAdjustOrigin = onAdjustOrigin
        self.onAdjustDestination = onAdjustDestination
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteEndRow(
                dotColor: MoyeotaColor.MarkerOrigin,
                name: origin,
                meta: originMeta,
                onAdjust: onAdjustOrigin,
                adjustLabel: "출발지 위치 조정"
            )
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(RouteSummarySpace)).midY } action: { originCenterY = $0 }

            // 원본 `heightIn(min = 20.dp)` 안쪽에 위아래 2 — 설명이 없어도 두 점 사이는 20 이다
            ZStack(alignment: .leading) {
                Color.clear.frame(height: 20 - 2 * 2)
                if let connectorNote, !connectorNote.allSatisfy(\.isWhitespace) {
                    Text(connectorNote)
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.leading, RouteDotSize + RouteDotGap)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)

            RouteEndRow(
                dotColor: MoyeotaColor.MarkerDestination,
                name: destination,
                meta: destinationMeta,
                onAdjust: onAdjustDestination,
                adjustLabel: "도착지 위치 조정"
            )
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(RouteSummarySpace)).midY } action: { destinationCenterY = $0 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            RouteConnector(originCenterY: originCenterY, destinationCenterY: destinationCenterY)
        }
        .coordinateSpace(.named(RouteSummarySpace))
    }
}

/// 두 점 사이의 점선. 점 가장자리에서 4 떨어져 시작·끝난다 — 점에 붙으면 점이 꼬리를 단 것처럼 보인다.
private struct RouteConnector: View {
    let originCenterY: CGFloat
    let destinationCenterY: CGFloat

    var body: some View {
        Canvas { context, _ in
            guard destinationCenterY > originCenterY else { return }
            let x = RouteDotSize / 2
            let inset = RouteDotSize / 2 + 4
            var path = Path()
            path.move(to: CGPoint(x: x, y: originCenterY + inset))
            path.addLine(to: CGPoint(x: x, y: destinationCenterY - inset))
            context.stroke(
                path,
                with: .color(MoyeotaColor.BorderStrong),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3])
            )
        }
        .accessibilityHidden(true)
    }
}

private struct RouteEndRow: View {
    let dotColor: Color
    let name: String
    let meta: String?
    let onAdjust: (() -> Void)?
    let adjustLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Circle()
                .fill(dotColor)
                .frame(width: RouteDotSize, height: RouteDotSize)
            Spacer().frame(width: RouteDotGap)
            Text(name)
                .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 빈 문자열이면 글자를 세우지 않는다 — 빈 글자도 폭을 먹어 이름 말줄임 위치가 달라진다
            if let meta, !meta.isEmpty {
                Spacer().frame(width: 8)
                Text(meta)
                    .moyeotaText(MoyeotaType.BodyMd.tabularNums().hangulTrimmed, color: MoyeotaColor.TextBody)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let onAdjust {
                // 파랑이 아니라 회색 — 이 시트에서 파랑은 CTA 하나에만 둔다(예전엔 한 시트에 파랑이 여섯 번 나왔다)
                TextLinkButton(
                    text: "조정",
                    onClick: onAdjust,
                    color: MoyeotaColor.TextMute,
                    style: MoyeotaType.BodySm.copy(fontWeight: .semibold),
                    onClickLabel: adjustLabel
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24)
    }
}

/// 요금 요약 — 20 합류 확인·22 탑승 상세 (디자인 QA G9).
///
/// 예전엔 회색 판 안에 옅은 파란 판이 또 들어 있고 그 안에 19 파란 숫자가 있었다(판 속의 판). 이제는
/// 구분선 하나 아래 **두 줄**이다: 총액은 작게, 1인 부담은 `MoyeotaType.HeadingLg` 검정으로 크게 —
/// 사용자가 실제로 내는 돈이 이 화면에서 가장 큰 숫자다. 파랑은 쓰지 않는다(CTA 의 색이다).
///
/// - Parameters:
///   - total: 「24,000원」
///   - perPerson: 「8,000원」
///   - capacity: 1인 부담을 나눈 정원 — 아래 한 줄 설명에 들어간다
///   - perPersonLabel: 20 은 「합류 시 1인 부담」, 22 는 「1인 부담」
public struct FareSummary: View {
    private let total: String
    private let perPerson: String
    private let capacity: Int
    private let perPersonLabel: String

    public init(total: String, perPerson: String, capacity: Int, perPersonLabel: String = "1인 부담") {
        self.total = total
        self.perPerson = perPerson
        self.capacity = capacity
        self.perPersonLabel = perPersonLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HorizontalDivider(color: MoyeotaColor.Hairline)
            Spacer().frame(height: 16)
            HStack(alignment: .center, spacing: 0) {
                Text("총 예상 요금")
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(total)
                    .moyeotaText(MoyeotaType.BodyMd.tabularNums().hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    .fixedSize()
            }
            Spacer().frame(height: 8)
            HStack(alignment: .center, spacing: 0) {
                Text(perPersonLabel)
                    .moyeotaText(MoyeotaType.BodyStrong.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(perPerson)
                    .moyeotaText(MoyeotaType.HeadingLg.tabularNums().hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    .fixedSize()
            }
            Spacer().frame(height: 4)
            // 계산 근거 한 줄 — 체크 아이콘을 달지 않는다(확인된 "사실"이 아니라 계산 방식의 설명이다)
            Text(fareSummaryNote(capacity: capacity))
                .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `FareSummary` 아래 한 줄 설명
func fareSummaryNote(capacity: Int) -> String {
    "총 예상 요금을 정원 \(capacity)명으로 나눈 금액이에요"
}
