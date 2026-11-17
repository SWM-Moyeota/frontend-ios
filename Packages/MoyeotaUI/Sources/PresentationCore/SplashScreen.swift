import MoyeotaDesignSystem
import SwiftUI

/// 세션 복원 중(= `AuthState.unknown`) 화면.
///
/// 앱 시작 직후에는 저장소에서 토큰을 아직 읽지 못했다. 이때 미로그인으로 단정하면
/// **이미 로그인한 사용자가 매번 온보딩·로그인 화면을 스쳐 본다** — 그래서 확정될 때까지
/// 여기서 기다린다. 복원은 저장소 한 번 읽기라 보통 한 프레임 남짓이다.
public struct SplashScreen: View {
    public init() {}

    public var body: some View {
        ZStack {
            // 흰 바탕 — 이어서 뜨는 첫 화면(온보딩·홈)과 같은 색이라 넘어갈 때 바탕이 깜빡이지 않는다(G2)
            MoyeotaColor.SurfaceCanvas
            VStack(spacing: 24) {
                Text("모여타")
                    .moyeotaText(MoyeotaType.DisplayMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                CircularProgressIndicator(size: 28, color: MoyeotaColor.Primary500)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
