/// `AppConfigResponse` — 서버가 필드를 늘려도 깨지지 않게 모르는 키는 무시한다.
///
/// 서버는 아직 `taxiEnabled` 를 응답에 담지만(출시된 앱 호환용, 늘 `false`) 여기에 받지 않는다.
/// 기사·배차가 사라져 갈릴 것이 없다 — 모르는 키라 그냥 흘린다.
///
/// ### 업데이트 기준을 Android 와 다른 키로 읽는 이유
/// 서버의 `minVersionCode`·`recommendedVersionCode` 는 **Android `versionCode` 수열**을 기준으로 한 값이다.
/// iOS 빌드 번호는 그 수열과 아무 관계가 없으므로 이 키로 판정하면 Android 배포에 맞춰 올린 숫자에 iOS 사용자가
/// 잠기거나, 반대로 막아야 할 iOS 빌드가 통과한다. 그래서 **두 키는 아예 읽지 않고**
/// `iosMinVersionCode`·`iosRecommendedVersionCode` 만 받는다(`docs/IOS-DIFFERENCES.md`).
public struct AppConfigResponse: Decodable, Equatable, Sendable {
    /// iOS 강제 업데이트 기준. **키가 없으면 null 이고 아무도 막지 않는다.**
    /// 안 와도 역직렬화가 깨지지 않고, 서버가 나중에 추가하면 그날부터 걸린다.
    public var iosMinVersionCode: Int?
    /// iOS 권장 업데이트 기준. 막지 않고 한 번 알리기만 한다. 위와 같은 이유로 null 기본값이다.
    public var iosRecommendedVersionCode: Int?

    public init(
        iosMinVersionCode: Int? = nil,
        iosRecommendedVersionCode: Int? = nil
    ) {
        self.iosMinVersionCode = iosMinVersionCode
        self.iosRecommendedVersionCode = iosRecommendedVersionCode
    }

    private enum CodingKeys: String, CodingKey {
        case iosMinVersionCode, iosRecommendedVersionCode
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iosMinVersionCode = try c.decodeIfPresent(Int.self, forKey: .iosMinVersionCode)
        iosRecommendedVersionCode = try c.decodeIfPresent(Int.self, forKey: .iosRecommendedVersionCode)
    }
}
