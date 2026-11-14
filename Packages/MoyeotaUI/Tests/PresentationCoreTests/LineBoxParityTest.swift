import MoyeotaDesignSystem
import SwiftUI
import Testing
import UIKit
@testable import PresentationCore

// 원본에 없는 테스트. 칸 가운데 놓이는 두 화면의 자리를 원본 렌더에 맞춰 지킨다.

/// 씬이 없는 창에는 안전 영역이 없다. 실기 값(iPhone 17: 위 62, 아래 34)을 흉내 낸다.
private final class InsetWindow: UIWindow {
    override var safeAreaInsets: UIEdgeInsets { UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0) }
}

@MainActor
private func hosted<V: View>(_ view: V) async -> UIWindow {
    let window = InsetWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = UIHostingController(rootView: view.ignoresSafeArea(.container))
    window.isHidden = false
    for _ in 0..<12 {
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(25))
    }
    return window
}

/// `x` 범위 안에서 줄의 왼쪽 끝 색과 다른 픽셀이 있는 연속한 줄들의 (위, 아래). pt 단위.
@MainActor
private func inkBands(_ window: UIWindow, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> [(top: CGFloat, bottom: CGFloat)] {
    let scale: CGFloat = 3
    let width = Int(window.bounds.width * scale)
    let height = Int(window.bounds.height * scale)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        window.layer.render(in: context)
    }
    var bands: [(top: CGFloat, bottom: CGFloat)] = []
    var start: Int?
    for row in Int(y.lowerBound * scale)..<Int(y.upperBound * scale) {
        let base = row * width * 4
        let first = base + Int(x.lowerBound * scale) * 4
        let ink = (Int(x.lowerBound * scale)..<Int(x.upperBound * scale)).contains { column in
            let at = base + column * 4
            return (0..<3).contains { abs(Int(bytes[at + $0]) - Int(bytes[first + $0])) > 14 }
        }
        if ink, start == nil { start = row }
        if !ink, let begin = start {
            bands.append((CGFloat(begin) / scale, CGFloat(row) / scale))
            start = nil
        }
    }
    return bands
}

@MainActor
@Suite(.serialized) struct LineBoxParityTest {

    // 아래 두 화면의 기대값은 디자인 다듬기(2026-11) **전** 원본 렌더에서 잰 자리를, 다듬기가 바꾼 줄 상자·간격만큼 옮긴 값이다
    // (다듬은 원본은 아직 렌더해 재지 않았다). 줄 상자는 원본 규칙대로 셈한다: 토큰 글자는 `Trim.Both` 라 한 줄 상자가 한글
    // 대체 글꼴 높이(글자 크기 × 1.44)이고 줄 간격만 지정값이다. 상자 안의 잉크 자리는 다듬기 전과 같다고 본다.

    @Test("업데이트 안내의 제목·본문·CTA 는 화면 가운데 기준으로 원본 렌더의 자리에 있다")
    func updateRequired() async {
        let window = await hosted(UpdateRequiredScreen())
        defer { window.isHidden = true }
        let bands = inkBands(window, x: 10...390, y: 300...600)
        #expect(bands.count == 4)
        // 다듬기 전 원본: 제목 -77.7, 본문 첫 줄 -35.0, CTA +32.0 ~ +84.2(본문은 bodyLarge 상속 — 두 줄 상자 48, 줄 가운데 정렬).
        // 다듬은 뒤: 본문이 BodyMd(두 줄 상자 21.6 + 22.5 = 44.1, 첫 줄 위를 자른다)라 묶음이 3.9 짧아져 가운데 기준 1.95 씩 당겨진다.
        // 제목 -77.7 + 1.95 = -75.75, 본문 첫 줄은 묶음 위 끝 기준 상자 위 끝이 1.95 내려오고 잘린 1.2 만큼 잉크가 위로 → -34.25,
        // CTA 위 +32.0 − 1.95 = +30.05, 아래 +84.2 − 1.95 = +82.25.
        #expect(abs(bands[0].top - 437 + 75.75) < 1, "제목 \(bands[0].top - 437)")
        #expect(abs(bands[1].top - 437 + 34.25) < 1, "본문 \(bands[1].top - 437)")
        #expect(abs(bands[3].top - 437 - 30.05) < 1, "CTA 위 \(bands[3].top - 437)")
        #expect(abs(bands[3].bottom - 437 - 82.25) < 1, "CTA 아래 \(bands[3].bottom - 437)")
    }

    @Test("시작 화면 제목은 화면 가운데 기준으로 원본 렌더의 자리에 있다")
    func splash() async {
        let window = await hosted(SplashScreen())
        defer { window.isHidden = true }
        let bands = inkBands(window, x: 150...260, y: 380...430)
        #expect(bands.count == 1)
        // 다듬기 전 원본 -33.9. 다듬은 뒤 제목·스피너 사이가 20 → 24 라 묶음이 4 길어져 제목이 2 올라간다(DisplayMd 의 줄 상자는 그대로 34.6).
        #expect(abs((bands.first?.top ?? 0) - 437 + 35.9) < 1, "제목 \((bands.first?.top ?? 0) - 437)")
    }
}

// MARK: - 커서

@MainActor
private func textField(in view: UIView) -> UITextField? {
    if let field = view as? UITextField { return field }
    for child in view.subviews {
        if let found = textField(in: child) { return found }
    }
    return nil
}

@MainActor
@Suite(.serialized) struct CaretPlacementTest {

    @Test("커서는 첫 자리에서 칸 왼쪽 끝, 글자가 있으면 글자 끝에서 시작한다")
    func caretStartsAtTextEnd() async throws {
        let style = MoyeotaType.BodyMd
        let window = await hosted(
            BasicTextField(value: "a", onValueChange: { _ in }, textStyle: style, singleLine: true)
                .frame(width: 200, height: 48)
        )
        defer { window.isHidden = true }
        let field = try #require(textField(in: window))
        field.becomeFirstResponder()
        window.layoutIfNeeded()
        defer { field.resignFirstResponder() }
        let start = field.caretRect(for: field.beginningOfDocument)
        let end = field.caretRect(for: field.endOfDocument)
        let advance = ("a" as NSString).size(withAttributes: [.font: style.uiFont, .kern: style.letterSpacing]).width
        #expect(abs(start.minX) < 0.5, "첫 자리 \(start.minX)")
        // 원본 10 「a」: 칸 왼쪽에서 8.0 에 커서가 시작한다. 재정의가 빠지면 1 왼쪽으로 가 글자에 붙는다.
        #expect(abs(end.minX - advance) < 0.5, "글자 끝 \(end.minX) 대 \(advance)")
    }
}
