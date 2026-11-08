/// 서버가 앱 시작 시 알려주는 운영 설정(`GET /api/v1/config`).
///
/// 예전에는 `taxiEnabled` 가 여기 있었다. 기사·배차를 걷어내면서 서버가 그 값을 `false` 로 박아
/// 더 갈릴 것이 없어졌고(모드가 하나뿐), 그래서 필드째 지웠다. 서버는 출시된 앱 호환을 위해
/// 응답에 키를 남겨 두지만 앱은 읽지 않는다 — JSON 디코더가 모르는 키를 흘린다.
public struct AppConfig: Hashable, Sendable {
    /// 이 값보다 낮은 `versionCode` 는 **더 못 쓰게 막는다**. 서버가 안 주면 null 이고, 그러면 통과다.
    ///
    /// 왜 자리를 미리 만드나: 앱이 한 번 스토어에 나가면 그 코호트는 영영 업데이트를 강제할 수 없다.
    /// 나중에 서버가 이 필드를 내려줘도 **그 필드를 모르는 빌드**는 조용히 무시한다
    /// (JSON 디코더가 모르는 키를 무시한다). 2026-11-01 현재 서버는 이 필드를 주지 않는다(실측).
    public var minVersionCode: Int?
    /// 막지는 않고 한 번 알리기만 할 기준. 서버가 안 주면 null 이고, 그러면 안내도 없다.
    public var recommendedVersionCode: Int?

    public init(
        minVersionCode: Int? = nil,
        recommendedVersionCode: Int? = nil
    ) {
        self.minVersionCode = minVersionCode
        self.recommendedVersionCode = recommendedVersionCode
    }

    /// 설정을 못 받았을 때의 값 — **아무것도 막지 않는다.**
    ///
    /// `minVersionCode`·`recommendedVersionCode` 가 null 이라 업데이트 게이트가 통과로 떨어진다.
    /// 서버 장애로 전원이 업데이트 화면에 잠기는 쪽이 낡은 앱 몇 대가 도는 것보다 훨씬 나쁘다.
    public static let Default = AppConfig()
}
