import MoyeotaDomain
import SwiftUI

/// SDK는 앱에서 주입한다. 화면과 도메인은 SDK 사용자 객체를 보관하지 않는다.
public struct NativeSocialAuthentication: Sendable {
    public let google: @MainActor @Sendable () async throws -> String
    public init(google: @escaping @MainActor @Sendable () async throws -> String) { self.google = google }
}
private struct NativeSocialKey: EnvironmentKey { static let defaultValue: NativeSocialAuthentication? = nil }
extension EnvironmentValues {
    public var nativeSocialAuthentication: NativeSocialAuthentication? {
        get { self[NativeSocialKey.self] }
        set { self[NativeSocialKey.self] = newValue }
    }
}
