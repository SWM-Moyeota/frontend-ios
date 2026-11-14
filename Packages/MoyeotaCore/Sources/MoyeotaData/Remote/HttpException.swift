import Foundation
import MoyeotaDomain

/// `retrofit2.Response` 의 자리 — 상태 코드와 성공 본문 또는 에러 본문.
///
/// 원본의 `Response<T>` 를 돌려주는 API(`PlaceApi.reverseGeocode`)는 4xx 를 예외 없이 그대로 받아
/// 호출부가 판정한다. 그 판정을 옮기려면 같은 모양이 필요하다.
public struct Response<T> {
    private let statusCode: Int
    private let successBody: T?
    private let rawErrorBody: Data?
    /// 응답 헤더(이름은 소문자). 실패 응답에서 `Retry-After` 를 읽으려고 든다 — 성공 응답은 비워 둔다.
    private let responseHeaders: [String: String]

    private init(statusCode: Int, successBody: T?, rawErrorBody: Data?, responseHeaders: [String: String] = [:]) {
        self.statusCode = statusCode
        self.successBody = successBody
        self.rawErrorBody = rawErrorBody
        self.responseHeaders = responseHeaders
    }

    public static func success(_ body: T?, code: Int = 200) -> Response<T> {
        Response(statusCode: code, successBody: body, rawErrorBody: nil)
    }

    public static func error(_ code: Int, _ errorBody: String?) -> Response<T> {
        Response(statusCode: code, successBody: nil, rawErrorBody: errorBody.map { Data($0.utf8) })
    }

    public static func error(_ code: Int, bytes: Data, headers: [String: String] = [:]) -> Response<T> {
        Response(
            statusCode: code,
            successBody: nil,
            rawErrorBody: bytes,
            responseHeaders: Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        )
    }

    /// 실패 응답의 헤더 값. 이름은 대소문자를 가리지 않는다.
    public func header(_ name: String) -> String? { responseHeaders[name.lowercased()] }

    public var isSuccessful: Bool { (200..<300).contains(statusCode) }

    public func code() -> Int { statusCode }

    public func body() -> T? { successBody }

    /// 에러 본문 원문. OkHttp 와 달리 이미 메모리에 있는 값이라 다시 읽어도 사라지지 않지만, 호출 규칙은
    /// 원본과 같다 — 한 번 읽어 결과를 들고 다닌다.
    public func errorBody() -> String? {
        rawErrorBody.map { String(decoding: $0, as: UTF8.self) }
    }

    /// 에러 본문 바이트 그대로. 게이트웨이가 UTF-8 이 아닌 본문을 줘도 손실 없이 볼 수 있다.
    public func errorBodyBytes() -> Data? { rawErrorBody }
}

extension Response: Sendable where T: Sendable {}

/// `retrofit2.HttpException` 의 자리 — 서버가 2xx 가 아닌 응답을 줬다.
///
/// 전송 계층 실패(`URLError` 등, 원본의 `IOException`)와 갈라야 화면이 「서버가 거절했다」와 「응답을 못 받았다」를
/// 다르게 안내할 수 있다.
public struct HttpException: Throwable {
    private let statusCode: Int
    private let rawErrorBody: Data?
    private let retryAfter: String?

    public init<T>(_ response: Response<T>) {
        statusCode = response.code()
        rawErrorBody = response.errorBodyBytes()
        retryAfter = response.header("Retry-After")
    }

    /// 실패 응답의 `Retry-After` 원문. 앱이 실패 응답에서 읽는 헤더는 이것 하나라 이것만 옮겨 든다.
    public func retryAfterHeader() -> String? { retryAfter }

    public func code() -> Int { statusCode }

    /// 에러 본문 원문(원본의 `response()?.errorBody()?.string()`).
    public func errorBody() -> String? {
        rawErrorBody.map { String(decoding: $0, as: UTF8.self) }
    }

    /// 에러 본문 바이트 그대로.
    public func errorBodyBytes() -> Data? { rawErrorBody }

    public var message: String? { "HTTP \(statusCode)" }

    public var cause: (any Error)? { nil }
}
