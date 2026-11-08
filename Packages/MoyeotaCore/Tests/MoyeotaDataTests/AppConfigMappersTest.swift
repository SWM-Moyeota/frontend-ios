import Foundation
import MoyeotaDomain
import Testing
@testable import MoyeotaData

/// `GET /api/v1/config`.
///
/// 서버 응답은 아직 `{"taxiEnabled":false}` 하나지만 **앱은 그 키를 받지 않는다** — 기사·배차가
/// 사라져 갈릴 모드가 없어졌고, 서버는 출시된 앱 호환으로 키만 남겨 두었다. 그래서 아래 JSON 들은
/// 일부러 `taxiEnabled` 를 싣는다: 「모르는 키를 조용히 흘린다」가 이 매퍼의 남은 계약이다.
@Suite struct AppConfigMappersTest {

    /// 모르는 필드가 늘어나도 깨지지 않는다 — 서버가 `taxiEnabled` 를 계속 보내도, 다른 키를 더해도
    /// 역직렬화가 살아 있어야 한다. 여기서 터지면 **앱 시작이 막힌다**(설정은 시작 때 한 번 읽는다).
    @Test("모르는 필드가 늘어나도 깨지지 않고 앱으로 새지 않는다")
    func unknownFields() throws {
        let config = try decodeJSON(AppConfigResponse.self, #"{"taxiEnabled":true,"minVersion":"1.2.0"}"#)
            .toAppConfig()

        // 모르는 키는 아무것도 채우지 않는다 — 버전 기준만 읽는 DTO 다.
        #expect(config.minVersionCode == nil)
        #expect(config.recommendedVersionCode == nil)
    }

    @Test("응답이 비어도 기본값으로 떨어진다")
    func emptyResponse() throws {
        let config = try decodeJSON(AppConfigResponse.self, "{}").toAppConfig()

        #expect(config.minVersionCode == nil)
        #expect(config.recommendedVersionCode == nil)
    }

    // ─────────────── 강제 업데이트 기준 (서버가 아직 주지 않는 필드) ───────────────

    @Test("지금 서버 응답에는 버전 기준이 없어 둘 다 null 이다")
    func noVersionFields() throws {
        // 2026-11-01 로컬 :8080 실측 응답 모양. null 이면 게이트가 아무도 막지 않는다.
        let config = try decodeJSON(AppConfigResponse.self, #"{"taxiEnabled":false}"#).toAppConfig()

        #expect(config.minVersionCode == nil)
        #expect(config.recommendedVersionCode == nil)
    }

    @Test("서버가 버전 기준을 주기 시작하면 그대로 옮긴다")
    func versionFields() throws {
        // 백엔드에 필드를 더하는 날 앱 배포 없이 바로 걸려야 한다 — 그게 이 필드를 미리 둔 이유다.
        let config = try decodeJSON(
            AppConfigResponse.self,
            #"{"taxiEnabled":false,"minVersionCode":26110102,"recommendedVersionCode":26110103}"#
        ).toAppConfig()

        #expect(config.minVersionCode == 26110102)
        #expect(config.recommendedVersionCode == 26110103)
    }

    // iOS 에서 더한 경우. 한동안 iOS 만 `iosMinVersionCode`·`iosRecommendedVersionCode` 를 읽었다 —
    // 지금은 두 플랫폼이 같은 키 한 쌍을 쓰므로(서버에도 그 한 쌍뿐이다) 옛 키가 남아 있으면
    // 서버가 주지도 않는 값을 기다리거나, 누군가 옛 키를 실었을 때 공통 기준을 덮어쓴다.
    @Test("옛 iOS 전용 키(iosMinVersionCode·iosRecommendedVersionCode)는 이제 읽지 않는다")
    func legacyIosKeysAreIgnored() throws {
        let legacyOnly = try decodeJSON(
            AppConfigResponse.self,
            #"{"taxiEnabled":false,"iosMinVersionCode":7,"iosRecommendedVersionCode":8}"#
        ).toAppConfig()

        #expect(legacyOnly.minVersionCode == nil)
        #expect(legacyOnly.recommendedVersionCode == nil)

        let both = try decodeJSON(
            AppConfigResponse.self,
            #"{"taxiEnabled":false,"minVersionCode":26110102,"recommendedVersionCode":26110103,"iosMinVersionCode":7,"iosRecommendedVersionCode":8}"#
        ).toAppConfig()

        #expect(both.minVersionCode == 26110102)
        #expect(both.recommendedVersionCode == 26110103)
    }

    // iOS 에서 더한 경우. 서버 `AppConfigResponse` 는 `@JsonInclude(NON_NULL)` 이라 정하지 않은 기준은
    // 키째 빠지고, 출시된 앱 호환 키 `taxiEnabled` 도 언젠가 빠진다. Swift 합성 디코더는 키가 없으면
    // 실패하므로(PORTING §3) 어느 키가 빠져도 디코딩이 살아 있는지 따로 본다 — 빠진 쪽은 「요구 없음」이다.
    @Test("taxiEnabled 가 없어도·한쪽 키만 와도 디코딩된다")
    func partialKeys() throws {
        let config = try decodeJSON(AppConfigResponse.self, #"{"minVersionCode":26110102}"#).toAppConfig()

        #expect(config.minVersionCode == 26110102)
        #expect(config.recommendedVersionCode == nil)
    }
}
