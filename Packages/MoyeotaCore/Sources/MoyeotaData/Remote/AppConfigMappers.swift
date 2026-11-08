import MoyeotaDomain

extension AppConfigResponse {
    public func toAppConfig() -> AppConfig {
        AppConfig(
            minVersionCode: minVersionCode,
            recommendedVersionCode: recommendedVersionCode
        )
    }
}
