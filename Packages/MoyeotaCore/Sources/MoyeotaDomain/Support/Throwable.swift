import Foundation

/// Kotlin `Throwable` 의 자리 — 도메인 예외가 공통으로 들고 있는 `message`·`cause`.
///
/// Swift `Error` 에는 없는 두 프로퍼티다. `LocalizedError` 를 함께 채택해 `error.localizedDescription` 도
/// 같은 `message` 를 돌려준다(원본 `e.message` 를 그대로 쓰던 자리).
public protocol Throwable: LocalizedError, Sendable {
    var message: String? { get }
    var cause: (any Error)? { get }
}

extension Throwable {
    public var errorDescription: String? { message }
}

/// `java.lang.IllegalStateException` 의 자리. 있어선 안 되는 상태를 만났다는 뜻이다 — STOMP·SSE 의
/// 프로토콜 위반, 값을 돌려줘야 하는 호출이 본문 없는 응답을 받은 경우 등.
public struct IllegalStateException: Throwable {
    public let message: String?
    public let cause: (any Error)?

    public init(_ message: String? = nil, cause: (any Error)? = nil) {
        self.message = message
        self.cause = cause
    }
}

/// `java.lang.IllegalArgumentException` 의 자리. 원본에서 Retrofit 이 잘못된 선언·base URL 을 거부할 때 던진다.
public struct IllegalArgumentException: Throwable {
    public let message: String?
    public let cause: (any Error)?

    public init(_ message: String? = nil, cause: (any Error)? = nil) {
        self.message = message
        self.cause = cause
    }
}

/// `java.io.IOException` 의 자리. `URLSession` 이 던지는 `URLError` 말고, 앱이 직접 만드는 전송 실패
/// (응답 없이 끊긴 스트림·소켓 등)에 쓴다. `Diagnostics` 는 이것을 결함으로 보고하지 않는다.
public struct IOException: Throwable {
    public let message: String?
    public let cause: (any Error)?

    public init(_ message: String? = nil, cause: (any Error)? = nil) {
        self.message = message
        self.cause = cause
    }
}
