import MoyeotaDesignSystem
import SwiftUI

// 하단탭 화면(14 홈 · 17 합승 · 24 채팅 · 35 마이)의 로딩·에러 골격.
//
// LoadingBox/ErrorBox 는 화면 전체를 채운다. 탭바를 각 화면이 직접 그리는 구조에서
// 이걸 Route 최상단에 그대로 두면 로딩·에러 동안 탭바가 통째로 사라져 인앱 이동이 끊긴다(QA F-1).
// 그래서 탭바는 항상 남기고 콘텐츠 영역만 상태에 따라 바꾼다.
//
// 바탕은 흰색이다 — 앱의 기본 화면 바탕(디자인 QA G2). 회색은 묶음 목록 화면만 쓴다.
public struct TabStateScaffold<Content: View>: View {
    private let selectedTab: MoyeotaTab
    private let onTabSelect: (MoyeotaTab) -> Void
    private let content: Content

    public init(
        selectedTab: MoyeotaTab,
        onTabSelect: @escaping (MoyeotaTab) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.selectedTab = selectedTab
        self.onTabSelect = onTabSelect
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            MoyeotaBottomBar(selected: selectedTab, onSelect: onTabSelect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
    }
}

// 탭바가 없는 화면(20·21·22 등)의 로딩·에러 골격.
// 이쪽의 인앱 이동 수단은 뒤로가기 하나뿐이라, 상태가 무엇이든 뒤로가기는 남겨둔다.
public struct BackStateScaffold<Content: View>: View {
    private let title: String
    private let onBack: () -> Void
    private let content: Content

    public init(
        title: String,
        onBack: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onBack = onBack
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                StatusBarSpacer()
                MoyeotaTopBar(title: title, onBack: onBack)
            }
            .frame(maxWidth: .infinity)
            .background(MoyeotaColor.SurfaceCanvas)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
    }
}

// 서버 연동 화면 공용 로딩/에러 상태
public struct LoadingBox: View {
    public init() {}

    public var body: some View {
        CircularProgressIndicator(color: MoyeotaColor.Primary500)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct ErrorBox: View {
    private let message: String
    private let onRetry: () -> Void
    private let actionLabel: String

    /// - Parameters:
    ///   - actionLabel: 버튼 문구. 기본값은 **다시 불러오는** 경우를 가정한다.
    ///
    ///     `onRetry` 가 재조회가 아니라 **되돌아가기**일 때는 바꿔 넘긴다 — 눌러도 다시 불러오지 않는
    ///     버튼에 「다시 시도」를 적으면 거짓이 된다. 21 의 「방 id 없음」 분기가 그 경우다.
    public init(
        message: String,
        onRetry: @escaping () -> Void,
        actionLabel: String = "다시 시도"
    ) {
        self.message = message
        self.onRetry = onRetry
        self.actionLabel = actionLabel
    }

    public var body: some View {
        // 34 지난 탑승 기록 · 38 노쇼 기록의 실패 상태와 같은 모양이다 — 가운데 회색 문장 + 테두리 알약 버튼.
        // 예전엔 이 자리에만 r12 · 40 솔리드 파란 상자가 있어 앱의 CTA 모양이 하나 더 늘었다(디자인 QA G5).
        VStack(spacing: 0) {
            Text(message)
                .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 16)
            SecondaryButton(text: actionLabel, onClick: onRetry)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// `Modifier.clip(shape).clickable { }` 의 눌림 표시. 머티리얼 상태 레이어처럼 모양 안에 10% 를 덮는다.
///
/// 배경이 칠해진 눌림 영역(배너)에 쓴다. 배경이 없는 아이콘·탭은 `MoyeotaDesignSystem` 의 투명도 표시를 쓴다.
public struct PressOverlayStyle<S: Shape>: ButtonStyle {
    private let shape: S

    public init(shape: S) {
        self.shape = shape
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    shape.fill(Color.black.opacity(0.1))
                }
            }
            .contentShape(shape)
    }
}
