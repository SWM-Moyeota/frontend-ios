import SwiftUI
import UIKit

// 온보딩 페이지 인디케이터 — 활성은 20x8 pill, 비활성은 8x8 dot
public struct PageDots: View {
    private let count: Int
    private let activeIndex: Int

    public init(count: Int, activeIndex: Int) {
        self.count = count
        self.activeIndex = activeIndex
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ForEach(0..<count, id: \.self) { i in
                if i == activeIndex {
                    Capsule(style: .circular)
                        .fill(MoyeotaColor.Primary500)
                        .frame(width: 20, height: 8)
                } else {
                    Circle()
                        .fill(MoyeotaColor.TextAsh)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
}

/// 안내·상태의 종류. 색이 **뜻을 싣는** 셋(error 빨강 · success 초록 = 매칭/확정 · waiting 호박 = 대기)과
/// 뜻이 없는 둘(info · neutral)로 나뉜다.
public enum NoticeKind: Sendable {
    case info, error, success, waiting, neutral

    /// `NoticeBanner` 의 바탕·글자 색. **info 는 회색이다** — `NoticeBanner` 참고.
    var bannerColors: (background: Color, foreground: Color) {
        switch self {
        case .info, .neutral: (MoyeotaColor.SurfaceSoft, MoyeotaColor.TextBody)
        case .error: (MoyeotaColor.Danger50, MoyeotaColor.Danger600)
        case .success: (MoyeotaColor.Success50, MoyeotaColor.Success600)
        case .waiting: (MoyeotaColor.Waiting50, MoyeotaColor.Waiting600)
        }
    }

    /// `StatusBadge` 의 바탕·글자 색. 배지의 info 는 옅은 파랑 그대로다.
    var badgeColors: (background: Color, foreground: Color) {
        switch self {
        case .info: (MoyeotaColor.Primary50, MoyeotaColor.Primary600)
        case .neutral: (MoyeotaColor.SurfaceSoft, MoyeotaColor.TextBody)
        case .error: (MoyeotaColor.Danger50, MoyeotaColor.Danger600)
        case .success: (MoyeotaColor.Success50, MoyeotaColor.Success600)
        case .waiting: (MoyeotaColor.Waiting50, MoyeotaColor.Waiting600)
        }
    }
}

/// 공통 규칙: 화면 단위 오류는 CTA 위 NoticeBanner Kind=error.
///
/// **info 는 회색이다**(디자인 QA G8, 2026-11). 예전엔 옅은 파랑이었는데, 안내 한 줄마다 파란 판이 깔려
/// 화면 곳곳이 "강조"가 되고 정작 파란 CTA 가 묻혔다. 색이 뜻을 싣는 error·success·waiting 만 물들인다.
public struct NoticeBanner: View {
    private let kind: NoticeKind
    private let text: String

    public init(kind: NoticeKind, text: String) {
        self.kind = kind
        self.text = text
    }

    public var body: some View {
        let colors = kind.bannerColors
        Text(text)
            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: colors.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colors.background, in: MoyeotaShape.Card)
    }
}

/// 상태 배지 (모집 중 · 매칭 완료 · 대기 등).
///
/// `NoticeKind.neutral` 은 상태가 아니라 **사실**(「2/3명」·「도착지」)을 붙일 때 쓴다 — 초록(=매칭됨)이나
/// 호박(=기다리는 중)으로 칠하면 없는 상태를 말하게 된다(디자인 QA S16-5·E2).
public struct StatusBadge: View {
    private let kind: NoticeKind
    private let text: String

    public init(kind: NoticeKind, text: String) {
        self.kind = kind
        self.text = text
    }

    public var body: some View {
        let colors = kind.badgeColors
        // 지정 줄 높이는 16.2 지만 원본 한글 한 줄은 대체 폰트 높이 17.2dp 로 그려진다(22 「모집 중」 UI 트리에서 잼).
        Text(text)
            .moyeotaText(
                MoyeotaType.CaptionMd.copy(fontWeight: .semibold, lineHeight: .sp(17.25)),
                color: colors.foreground
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(colors.background, in: Capsule(style: .circular))
    }
}

/// 묶음 머리말 — 「즐겨찾기」·「매칭 조건」·「이미 참여한 사람」 (디자인 QA G9).
///
/// 예전엔 같은 역할의 머리말이 13 Bold · 13 Medium · 12 Bold 로 여섯 갈래였다. 13 SemiBold `MoyeotaColor.TextMute`
/// 한 가지로 모으고, 아래 8 을 띄운다. **좌우 여백은 놓이는 자리가 준다** — 대부분 이미 16 화면 여백 안에
/// 놓이므로 여기서 또 주면 두 번 들어간다. VoiceOver 에는 제목(머리말)으로 알린다.
///
/// - Parameter trailing: 오른쪽 끝의 작은 행동(「편집」) — `TextLinkButton` 을 넘긴다
public struct SectionLabel<Trailing: View>: View {
    private let text: String
    private let hasTrailing: Bool
    private let trailing: Trailing

    public init(text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.hasTrailing = true
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(text)
                .moyeotaText(MoyeotaType.BodySm.copy(fontWeight: .semibold).hangulTrimmed, color: MoyeotaColor.TextMute)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if hasTrailing { trailing }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }
}

public extension SectionLabel where Trailing == EmptyView {
    init(text: String) {
        self.text = text
        self.hasTrailing = false
        self.trailing = EmptyView()
    }
}

/// 글자만 있는 작은 행동(「편집」·「조정」·「로그인」·「지도 접기」) — **보이는 건 글자지만 터치 영역은 48** 이고
/// 누르면 눌림 표시가 난다(디자인 QA G12). 예전엔 글자 크기 그대로(24 안팎) 눌리고 눌림 표시도 없었다.
///
/// 좌우 8 안쪽 여백이 있어 글자는 터치 상자보다 8 안에 그려진다 — 화면 여백에 글자 끝을 맞추려면
/// 호출부가 그만큼 바깥으로 둔다(원본 `Modifier.offset(x = ±8.dp)` 자리는 `.offset(x:)`).
///
/// - Parameters:
///   - onClickLabel: 누르면 무엇을 하는지(「출발지 위치 조정」). VoiceOver 힌트로 읽힌다
///   - trailingIcon: 글자 뒤의 16 아이콘(「지도 접기」의 꺾쇠)
public struct TextLinkButton<TrailingIcon: View>: View {
    private let text: String
    private let onClick: () -> Void
    private let color: Color
    private let style: MoyeotaType
    private let enabled: Bool
    private let onClickLabel: String?
    private let trailingIcon: TrailingIcon

    public init(
        text: String,
        onClick: @escaping () -> Void,
        color: Color = MoyeotaColor.Primary600,
        style: MoyeotaType = MoyeotaType.ButtonMd,
        enabled: Bool = true,
        onClickLabel: String? = nil,
        @ViewBuilder trailingIcon: () -> TrailingIcon
    ) {
        self.text = text
        self.onClick = onClick
        self.color = color
        self.style = style
        self.enabled = enabled
        self.onClickLabel = onClickLabel
        self.trailingIcon = trailingIcon()
    }

    public var body: some View {
        Button(action: onClick) {
            HStack(alignment: .center, spacing: 2) {
                Text(text)
                    .moyeotaText(style.hangulTrimmed, color: enabled ? color : MoyeotaColor.TextPlaceholder)
                    .lineLimit(1)
                    .fixedSize()
                trailingIcon
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 48, minHeight: 48)
            .contentShape(MoyeotaShape.Small)
        }
        .buttonStyle(PressFeedbackStyle())
        .disabled(!enabled)
        .accessibilityHint(onClickLabel ?? "")
    }
}

public extension TextLinkButton where TrailingIcon == EmptyView {
    init(
        text: String,
        onClick: @escaping () -> Void,
        color: Color = MoyeotaColor.Primary600,
        style: MoyeotaType = MoyeotaType.ButtonMd,
        enabled: Bool = true,
        onClickLabel: String? = nil
    ) {
        self.init(
            text: text,
            onClick: onClick,
            color: color,
            style: style,
            enabled: enabled,
            onClickLabel: onClickLabel
        ) { EmptyView() }
    }
}

/// 아바타. `imageUrl` 이 있으면 서버 프로필 사진을 그리고, **그릴 수 없을 때는 `label`**(없으면 회색 원)
/// 으로 되돌아간다.
///
/// ### 네 경우에 무엇이 보이는가
///
/// | 경우 | 보이는 것 |
/// |---|---|
/// | `imageUrl` 이 nil/빈 값 | `label` 또는 빈 회색 원 — **요청을 만들지 않는다** |
/// | 로딩 중 | 같음 |
/// | 성공 | 사진 |
/// | 실패(403·타임아웃·디코드 실패) | 같음 |
///
/// 이 앱에서 사진 없음은 **정상 경우**(유저 요약이 없는 멤버·조회 실패)라, 요청을 만들고 실패 경로를
/// 타는 것보다 분기로 거르는 쪽이 의도를 정확히 말한다.
///
/// 대체 표시를 **아래에 깔고 성공했을 때만 가린다.** 페이드를 두지 않는다 — 대체 표시를 지운 뒤
/// 사진이 떠오르는 동안 빈 원만 남아 깜빡이기 때문이다(`MoyeotaImageLoader` 도 페이드를 쓰지 않는다).
///
/// ### 표시 상태의 키가 `imageUrl` 인 이유
/// 채팅 목록이 최근 메시지 순으로 재정렬되거나 매칭 대기의 멤버가 한 명 나가 목록이 밀리면, 같은 위치의
/// 뷰가 **다른 방·다른 사람**을 받을 수 있다. 키가 없으면 **새 사람의 대체 표시가 가려진 채 앞 사람 사진이
/// 남는다.** `MoyeotaAsyncImage` 가 URL 이 다른 결과를 버리는 건 같은 이유다.
public struct AvatarCircle: View {
    private let size: CGFloat
    private let label: String?
    private let imageUrl: String?

    public init(size: CGFloat = 40, label: String? = nil, imageUrl: String? = nil) {
        self.size = size
        self.label = label
        self.imageUrl = imageUrl
    }

    public var body: some View {
        MoyeotaAsyncImage(url: imageUrl) { image in
            ZStack {
                if let label, image == nil {
                    Text(label)
                        .moyeotaText(.CaptionMd, color: MoyeotaColor.TextMute)
                }
                if let image {
                    // 지름에서 2 를 빼는 이유: 꽉 찬 원형 이미지는 부모의 1dp 헤어라인을 덮는다.
                    // 비정사각 이미지가 원 안에서 레터박스가 되지 않게 채워서 자른다.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size - 2, height: size - 2)
                        .clipShape(Circle())
                        // 이름을 바로 옆에서 읽어 주는 자리들이라 사진은 장식이다 — 중복 낭독을 막는다.
                        .accessibilityHidden(true)
                }
            }
            .frame(width: size, height: size)
            .background(MoyeotaColor.SurfaceSoft, in: Circle())
            .overlay(Circle().strokeBorder(MoyeotaColor.Hairline, lineWidth: 1))
        }
    }
}

/// Coil `AsyncImage` 자리. 불러온 `UIImage`(아직 없거나 실패했으면 nil)를 받아 그린다.
///
/// `url` 이 nil·빈 값이면 요청을 만들지 않는다. 메모리 캐시에 있으면 첫 프레임부터 사진이 나온다.
public struct MoyeotaAsyncImage<Content: View>: View {
    private let url: String?
    private let content: (UIImage?) -> Content

    @State private var loaded: (url: String, image: UIImage)?

    public init(url: String?, @ViewBuilder content: @escaping (UIImage?) -> Content) {
        self.url = url?.allSatisfy(\.isWhitespace) == true ? nil : url
        self.content = content
    }

    public var body: some View {
        content(currentImage)
            .task(id: url) {
                guard let url, currentImage == nil else { return }
                // 실패·취소는 대체 표시로 남는다.
                guard let image = try? await MoyeotaImageLoader.load(url) else { return }
                loaded = (url, image)
            }
    }

    private var currentImage: UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return MoyeotaImageLoader.cachedImage(url)
    }
}

/// 이미지 로더. 원본의 `MoyeotaApplication.newImageLoader` 자리다.
///
/// 네트워크 구성은 이 모듈이 알지 못한다 — 앱 시작 때 `configure(session:)` 에 `Apis.imageClient` 를 넘긴다
/// (디스크 캐시 32MB 는 그 세션의 `URLCache` 가 맡는다). 메모리 캐시 크기는 원본과 같이 앱 메모리의 15% 다.
@MainActor
public enum MoyeotaImageLoader {
    private static var session: URLSession = .shared

    private static let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = Int(Double(ProcessInfo.processInfo.physicalMemory) * 0.15)
        return cache
    }()

    public static func configure(session: URLSession) {
        self.session = session
    }

    public static func cachedImage(_ url: String) -> UIImage? {
        memoryCache.object(forKey: url as NSString)
    }

    public static func load(_ url: String) async throws -> UIImage {
        if let cached = cachedImage(url) { return cached }
        guard let parsed = URL(string: url) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: parsed)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = await Task.detached { UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data) }.value
        guard let decoded else { throw URLError(.cannotDecodeContentData) }
        memoryCache.setObject(decoded, forKey: url as NSString, cost: data.count * 4)
        return decoded
    }
}

/// 선택 칩 — 앱의 **단 하나뿐인 칩** (디자인 QA G6, 2026-11). 16 매칭 조건, 16a 출발지/도착지 토글,
/// 17 탐색 모드·날짜, 21 약속 프리셋이 모두 이걸 쓴다.
///
/// - 보이는 높이 36, **터치 영역 48**(원본 `minimumInteractiveComponentSize`), 그림자 없음
/// - 미선택: 흰 바탕 + `MoyeotaColor.Border` 테두리 + `MoyeotaColor.TextBody` 글자
/// - 선택: 옅은 파랑 바탕 + 파란 테두리 + 진한 파랑 글자
///
/// 선택을 **솔리드 파랑으로 칠하지 않는 이유**: 한 화면에 솔리드 파랑은 CTA 하나만 둔다(디자인 문서
/// "primary 를 아껴 쓴다"). 예전 16 은 흰 그림자 칩 + 솔리드 파랑 선택 칩, 17 은 옅은 칩으로 두 갈래였다.
///
/// - Parameter horizontalPadding: 글자 좌우 여백. 둘뿐인 토글(16a 출발지/도착지)처럼 넓게 누르게 할 때만 늘린다
public struct MoyeotaChip: View {
    private let text: String
    private let selected: Bool
    private let onClick: () -> Void
    private let enabled: Bool
    private let horizontalPadding: CGFloat

    public init(
        text: String,
        selected: Bool,
        onClick: @escaping () -> Void,
        enabled: Bool = true,
        horizontalPadding: CGFloat = 14
    ) {
        self.text = text
        self.selected = selected
        self.onClick = onClick
        self.enabled = enabled
        self.horizontalPadding = horizontalPadding
    }

    public var body: some View {
        let bg = selected ? MoyeotaColor.Primary50 : MoyeotaColor.SurfaceCanvas
        let fg: Color = if !enabled {
            MoyeotaColor.TextPlaceholder
        } else if selected {
            MoyeotaColor.Primary600
        } else {
            MoyeotaColor.TextBody
        }
        let border = selected ? MoyeotaColor.Primary500 : MoyeotaColor.Border
        Button(action: onClick) {
            Text(text)
                .moyeotaText(MoyeotaType.ButtonMd.hangulTrimmed, color: fg)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, horizontalPadding)
                .frame(height: 36)
                .background(bg, in: Capsule(style: .circular))
                .overlay(Capsule(style: .circular).strokeBorder(border, lineWidth: 1))
                .frame(minWidth: 48, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackStyle())
        .disabled(!enabled)
        // 원본 `selectable` — iOS 에 라디오 역할이 없어 버튼 + 「선택됨」 특성으로 읽힌다
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// 바텀시트 핸들
public struct SheetHandle: View {
    public init() {}

    public var body: some View {
        Capsule(style: .circular)
            .fill(MoyeotaColor.TextAsh)
            .frame(width: 36, height: 4)
    }
}

// 지도 자리표시 — SDK 없이 와이어프레임처럼 격자 배경
public struct MapPlaceholder: View {
    public init() {}

    public var body: some View {
        ZStack {
            MoyeotaColor.SurfaceSoft
            Rectangle()
                .fill(MoyeotaColor.Border)
                .frame(height: 2)
                .padding(.horizontal, 24)
            Text("지도 영역")
                .moyeotaText(.CaptionMd, color: MoyeotaColor.TextPlaceholder)
        }
    }
}

public extension View {
    /// Compose `Modifier.shadow(elevation, shape, spotColor = …)` 자리. 뷰 뒤에 모양을 깔아 그림자를 드리운다.
    ///
    /// 안드로이드 그림자는 앰비언트(사방, 기본 검정)와 스폿(아래로 치우침, `spotColor`) 두 겹이고, 시스템이
    /// 각 색 알파에 0.039·0.19 를 곱한다. 같은 두 겹을 같은 알파로 그리되 번짐·거리는 고도에서 환산한 근사다.
    func moyeotaShadow<S: Shape>(
        elevation: CGFloat,
        shape: S,
        ambientColor: Color = .black,
        spotColor: Color = .black
    ) -> some View {
        background {
            ZStack {
                shape
                    .fill(Color.white)
                    .shadow(color: ambientColor.opacity(0.039), radius: elevation * 0.5)
                shape
                    .fill(Color.white)
                    .shadow(color: spotColor.opacity(0.19), radius: elevation * 0.5, y: elevation * 0.5)
            }
        }
    }
}
