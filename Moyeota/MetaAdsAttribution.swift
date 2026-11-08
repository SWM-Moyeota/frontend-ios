import FacebookCore
import os
import UIKit

private let logger = Logger(subsystem: "com.moyeota.app", category: "MetaAds")

/// Meta(Facebook) 광고의 앱 설치 측정을 켠다. Meta SDK 를 아는 파일은 이것 하나다.
///
/// ### 왜 필요한가
/// Meta 광고관리자는 iOS 14+ 앱 설치 캠페인에서, 앱이 SDK 로 전환 데이터(취합된 이벤트 측정, AEM)를 보내지 않으면
/// 그 앱을 고를 수 없게 막는다. SDK 가 설치·첫 실행 같은 기본 앱 이벤트를 자동으로 보내면 그 제한이 풀리고,
/// 「어느 광고가 설치를 만들었나」를 Meta 가 계산할 수 있다.
///
/// ### 무엇을 하지 않는가
/// - 추적 허용 팝업(ATT)을 띄우지 않는다. `FacebookAdvertiserIDCollectionEnabled` 를 꺼서 광고 식별자(IDFA)를 읽지 않는다.
///   측정은 Apple 이 허용하는 익명 집계(AEM·SKAdNetwork)에 기대며, 개인 단위 광고 추적은 하지 않는다.
/// - 우리 행동 이벤트(`Analytics`)를 Meta 로 보내지 않는다. 그건 Mixpanel 몫이다. 여기서 나가는 건 SDK 의 자동 앱 이벤트뿐이다.
///
/// ### 키가 없으면 아무것도 하지 않는다
/// `Info.plist` 의 `FacebookAppID`(← `Config/Base.xcconfig`)와 `FacebookClientToken`(← `Config/Secrets.xcconfig`)
/// 중 하나라도 비면 SDK 를 초기화하지 않는다. Mixpanel·Firebase 와 같은 「없어도 돈다」 규칙이다 —
/// 토큰 없이 빌드한 앱(fork·CI·새 팀원)이 깨지거나 남의 앱 ID 로 이벤트를 쏘는 일이 없다.
///
/// App Store 개인정보 라벨에는 Meta 로 가는 앱 사용 데이터를 적어야 한다 (`docs/ANALYTICS.md`).
enum MetaAdsAttribution {

    /// `AppDelegate.didFinishLaunching` 에서 한 번 부른다.
    ///
    /// - Returns: SDK 를 켰는가. 키가 비어 있으면 false 다.
    @MainActor
    @discardableResult
    static func start(
        _ application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
        bundle: Bundle = .main
    ) -> Bool {
        guard isConfigured(bundle: bundle) else {
            logger.notice("FacebookAppID/FacebookClientToken 이 비어 있다 — Meta 광고 측정을 끈다")
            return false
        }
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        return true
    }

    /// 두 키가 모두 채워졌는가. xcconfig 변수가 비면 Info.plist 에는 빈 문자열이 들어온다.
    static func isConfigured(bundle: Bundle) -> Bool {
        ["FacebookAppID", "FacebookClientToken"].allSatisfy { key in
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
