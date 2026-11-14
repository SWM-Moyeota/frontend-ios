import Foundation
import Testing

/// 화면 코드가 **디자인 토큰을 우회하지 않는지** 소스를 읽어 확인한다 (디자인 QA G1·G3, 2026-11). 원본 `DesignTokenGuardTest`.
///
/// "AI 가 만든 것 같다"는 피드백의 가장 큰 원인은 화면마다 따로 정한 값이었다 — 회색 네 가지, 페이지 회색 다섯 가지,
/// 글자 크기 열여섯 가지가 파일마다 `private let … = Color(argb: …)`·`MoyeotaType(fontSize: …)` 로 다시 정의돼 있었다.
/// 한 번 걷어내도 새 화면이 같은 방식으로 값을 들이면 금방 돌아온다. 린트 규칙을 새로 들이는 대신
/// (의존성을 늘리지 않는다) 이 테스트가 그 문을 닫는다.
///
/// - 색은 `MoyeotaColor` 만 — 원본 `Color(0x…)` 의 iOS 꼴(`Color(argb:`)과 시스템 생성자(`Color(red:`·`Color(hex`·
///   `UIColor(red:`·`Color(.sRGB`) 금지
/// - 글자 크기는 `MoyeotaType` 토큰만 — 원본 `fontSize =` 의 iOS 꼴(`fontSize:` 인자·매개변수 — `MoyeotaType(fontSize:`·
///   `.copy(fontSize:`, 크기를 받는 도우미 함수의 선언)과 `.font(.system(size:` 금지
///
/// 걸리면: 가장 가까운 토큰으로 바꾼다. 토큰에 없는 값이 정말 필요하면 디자인시스템에 토큰을 먼저 만든다.
///
/// 읽는 범위는 원본의 `presentation/src/main/kotlin/com/moyeota/presentation`(core + feature 전부)다. iOS 에서는
/// `PresentationCore`, `MainNavGraph`·`Routes` 가 옮겨 간 `AppNavigation`, 기능 모듈 일곱이다(docs/PORTING.md 2절).
/// 디자인시스템(`MoyeotaDesignSystem`)은 토큰을 정의하는 곳이라 원본처럼 읽지 않는다.
///
/// 색 무늬는 모두 `\b` 로 시작한다 — `ChipColor(red: …)` 같은 **다른 이름**의 생성자를 색으로 잡지 않는다(원본 리뷰
/// 반영: `\bColor\((0x|\d)`). 원본의 `.sp` 무늬 손질(`item1.sp` 를 지나친다)은 iOS 에 옮길 것이 없다 — 글자 크기를
/// 숫자 리터럴 뒤 접미사로 적는 꼴이 없고, 크기는 늘 `fontSize:` 인자나 `.system(size:` 로 들어온다(`\bfontSize` 는
/// 이미 `\b` 가 있다).
///
/// 알려진 한계 — 소스를 줄 단위 정규식으로 읽을 뿐 파서가 아니다(`codePart`). 원본과 같은 두 구멍을 알고 둔다.
/// - `*` 로 시작하는 줄은 문서 주석 줄로 보고 통째로 건너뛴다 — 곱셈 연산자로 시작하는 이어진 줄이 있으면 그 줄은 보지 못한다
/// - 문자열 안의 `//` 는 앞이 `:` 일 때(`"https://…"`)만 주석이 아닌 것으로 본다 — `"a//b"` 같은 문자열이면 그 뒤를
///   주석으로 잘라 같은 줄 뒤쪽의 직접 지정을 놓친다
@Suite struct DesignTokenGuardTest {
    static let scannedDirs = [
        "PresentationCore", "AppNavigation",
        "FeatureAuth", "FeatureOnboarding", "FeatureHome", "FeatureExplore", "FeatureMatching", "FeatureChat", "FeatureMyPage",
    ]

    static let colorPatterns = [
        #"\bColor\(argb:"#, #"\bColor\(red:"#, #"\bColor\(hex"#, #"\bUIColor\(red:"#, #"\bColor\(\.sRGB"#,
    ]

    static let fontSizePatterns = [
        #"\.font\(\.system\(size:"#, #"\bfontSize\s*:"#,
    ]

    /// 검사할 코드 부분. 줄 주석·문서 주석 줄은 통째로, 코드 뒤 주석은 잘라 낸다 — 단 `"https://…"` 같은 문자열
    /// 안의 `//` 는 주석이 아니다(앞이 `:` 인 `//` 는 남긴다). 예전엔 거기서 잘려 뒤쪽을 못 봤다(원본 리뷰 반영).
    static func codePart(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") { return "" }
        return line.replacingOccurrences(of: #"(?<!:)//.*$"#, with: "", options: .regularExpression)
    }

    /// 읽은 파일 수와 걸린 줄(`모듈/파일.swift:줄: 내용`). 주석은 보지 않는다(`codePart`).
    private func violations(_ patterns: [String]) throws -> (scanned: Int, found: [String]) {
        let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
        var scanned = 0
        var found: [String] = []
        let rootPath = SourceTree.root.standardizedFileURL.path + "/"
        for dir in Self.scannedDirs {
            for file in SourceTree.swiftFiles(under: dir) {
                scanned += 1
                let path = file.standardizedFileURL.path
                let relative = path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (index, line) in lines.enumerated() {
                    let code = Self.codePart(line)
                    let range = NSRange(code.startIndex..., in: code)
                    if regexes.contains(where: { $0.firstMatch(in: code, range: range) != nil }) {
                        found.append("\(relative):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        return (scanned, found)
    }

    @Test("화면 코드는 색을 직접 정의하지 않는다")
    func noRawColors() throws {
        let result = try violations(Self.colorPatterns)

        #expect(result.scanned > 50, "소스를 찾지 못했다: \(SourceTree.root.path)")
        #expect(result.found.isEmpty, "MoyeotaColor 토큰을 쓴다:\n\(result.found.joined(separator: "\n"))")
    }

    @Test("화면 코드는 글자 크기를 직접 정하지 않는다")
    func noRawFontSizes() throws {
        let result = try violations(Self.fontSizePatterns)

        #expect(result.scanned > 50, "소스를 찾지 못했다: \(SourceTree.root.path)")
        #expect(result.found.isEmpty, "MoyeotaType 토큰을 쓴다:\n\(result.found.joined(separator: "\n"))")
    }

    /// 원본에 없는 테스트. 검사가 실제로 걸리는지 — 무늬가 틀리면 위 두 테스트는 늘 통과해 뜻이 없다.
    @Test("검사 무늬는 iOS 의 직접 지정 꼴을 잡고 토큰 사용과 주석은 지나친다")
    func patternsMatchRawSpellings() throws {
        func hits(_ patterns: [String], _ code: String) throws -> Bool {
            let stripped = Self.codePart(code)
            return try patterns.contains { pattern in
                try NSRegularExpression(pattern: pattern)
                    .firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) != nil
            }
        }
        #expect(try hits(Self.colorPatterns, "private let GrayMute = Color(argb: 0xFF8A93A0)"))
        #expect(try hits(Self.colorPatterns, ".foregroundStyle(Color(red: 0.1, green: 0.2, blue: 0.3))"))
        #expect(try hits(Self.colorPatterns, "view.backgroundColor = UIColor(red: 1, green: 1, blue: 1, alpha: 1)"))
        #expect(try hits(Self.colorPatterns, "Color(.sRGB, red: 1, green: 0, blue: 0)"))
        #expect(try hits(Self.colorPatterns, ".background(SwiftUI.Color(red: 1, green: 0, blue: 0))"))
        #expect(try !hits(Self.colorPatterns, ".foregroundStyle(MoyeotaColor.TextMute)"))
        // 다른 이름의 생성자는 색이 아니다 — 앞의 `\b` 가 이름 한가운데의 `Color(` 를 지나친다
        #expect(try !hits(Self.colorPatterns, "let chip = ChipColor(red: true)"))
        #expect(try !hits(Self.colorPatterns, "let tone = BadgeColor(hex: code)"))
        #expect(try !hits(Self.colorPatterns, "// 예전엔 Color(argb: 0xFF8A93A0) 였다"))
        // 문자열 안의 `//`(URL) 뒤도 본다 — 주석으로 보고 잘라 내면 그 뒤의 직접 지정을 놓친다
        #expect(try hits(Self.colorPatterns, #"let url = "https://moyeota.co.kr"; let c = Color(argb: 0xFF8A93A0)"#))
        #expect(try !hits(Self.colorPatterns, "let c = MoyeotaColor.TextMute // 예전엔 Color(argb: 0xFF8A93A0)"))

        #expect(try hits(Self.fontSizePatterns, ".moyeotaText(MoyeotaType(fontSize: 13, fontWeight: .bold))"))
        #expect(try hits(Self.fontSizePatterns, ".moyeotaText(MoyeotaType.BodySm.copy(fontSize: 14))"))
        #expect(try hits(Self.fontSizePatterns, "func inlineType(_ fontSize: CGFloat, _ fontWeight: Font.Weight) -> MoyeotaType {"))
        #expect(try hits(Self.fontSizePatterns, ".font(.system(size: 13))"))
        #expect(try !hits(Self.fontSizePatterns, ".moyeotaText(MoyeotaType.BodySm.copy(fontWeight: .semibold))"))
        #expect(try !hits(Self.fontSizePatterns, "/// 원본 `Text(fontSize = …)` 자리"))
    }
}
