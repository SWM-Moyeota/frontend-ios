import FirebaseAnalytics
import os

private let logger = Logger(subsystem: "com.moyeota.app", category: "GoogleAds")

/// 구글 광고의 iOS 앱 설치 측정을 켠다. Firebase Analytics 를 아는 파일은 이것 하나다.
///
/// ### 왜 필요한가
/// 구글 광고는 iOS 설치를 직접 볼 수 없다. 앱이 Firebase Analytics 로 「첫 실행」(`first_open`)을 알려 줘야
/// 설치가 전환으로 잡히고 iOS 캠페인의 입찰도 학습한다. Android 는 Google Play 가 설치를 세므로 해당 없다.
///
/// ### 왜 이 호출이 있어야 하나
/// `FirebaseAnalyticsCore` 는 동적 프레임워크라, 앱 코드가 그 심볼을 하나도 부르지 않으면 링커가 연결(LC_LOAD_DYLIB)을 빼 버린다.
/// 그러면 프레임워크가 번들에 들어 있어도 실행 중에 로드되지 않아 아무것도 보내지 않는다
/// (Crashlytics 로그: "Firebase Analytics SDK not detected"). 여기서 명시적으로 켜서 링크와 수집을 함께 보장한다.
///
/// ### 무엇을 하지 않는가
/// - 직접 보내는 이벤트(`logEvent`)와 사용자 ID(`setUserID`)가 없다. SDK 의 자동 이벤트(first_open·session_start 등)만 간다.
/// - IDFA·IDFV·화면 자동 기록·광고 개인화 신호는 `Info.plist` 에서 끈다 (`docs/ANALYTICS.md`).
enum GoogleAdsAttribution {

    /// `AppDelegate.didFinishLaunching` 에서 한 번 부른다. `GoogleService-Info.plist` 가 없으면 아무것도 하지 않는다.
    ///
    /// - Returns: 수집을 켰는가.
    @discardableResult
    static func start() -> Bool {
        guard FirebaseRuntime.isConfigured else {
            logger.notice("Firebase 미구성 — 구글 광고 측정을 끈다")
            return false
        }
        // 도메인의 `Analytics`(Mixpanel)와 이름이 겹쳐 모듈 이름을 붙인다.
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(true)
        return true
    }
}
