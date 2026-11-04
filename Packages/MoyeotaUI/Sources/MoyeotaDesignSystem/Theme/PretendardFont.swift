import CoreText
import SwiftUI
import UIKit

/// 패키지 리소스에서 한 번 등록하므로 앱과 SwiftUI Preview 모두 같은 폰트를 쓴다.
enum PretendardFont {
    private static let registered: Void = {
        for face in ["Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black"] {
            let name = "Pretendard-\(face)"
            guard let url = Bundle.module.url(forResource: name, withExtension: "otf", subdirectory: "Fonts") else {
                preconditionFailure("Missing bundled font: \(name)")
            }
            var error: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if !success {
                let registrationError = error?.takeRetainedValue()
                // 같은 프로세스의 다른 번들이 먼저 등록한 경우에는 이미 사용 가능하다.
                precondition(UIFont(name: name, size: 14) != nil, "Font registration failed: \(String(describing: registrationError))")
            }
        }
    }()

    static func font(size: CGFloat, weight: Font.Weight) -> UIFont {
        _ = registered
        let face: String
        switch weight {
        case .ultraLight: face = "Thin"
        case .thin: face = "ExtraLight"
        case .light: face = "Light"
        case .medium: face = "Medium"
        case .semibold: face = "SemiBold"
        case .bold: face = "Bold"
        case .heavy: face = "ExtraBold"
        case .black: face = "Black"
        default: face = "Regular"
        }
        guard let font = UIFont(name: "Pretendard-\(face)", size: size) else {
            preconditionFailure("Registered Pretendard font unavailable: \(face)")
        }
        return font
    }
}
