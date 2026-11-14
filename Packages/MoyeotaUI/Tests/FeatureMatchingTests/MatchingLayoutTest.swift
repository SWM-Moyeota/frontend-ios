import MoyeotaDesignSystem
import MoyeotaDomain
import SwiftUI
import Testing
import UIKit
@testable import FeatureMatching

// 원본에 없는 테스트. 원본 렌더(UI 트리·스크린샷)에서 잰 값을 지킨다.

/// 씬이 없는 창에는 안전 영역이 없다. 실기 값(iPhone 17: 위 62, 아래 34)을 흉내 낸다.
private final class InsetWindow: UIWindow {
    override var safeAreaInsets: UIEdgeInsets { UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0) }
}

@MainActor
@Suite(.serialized) struct ConfirmDialogGeometryTest {

    private func brightness(_ window: UIWindow, x: CGFloat, y: CGFloat) -> CGFloat {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else { return -1 }
        context.translateBy(x: -x, y: -y)
        window.layer.render(in: context)
        return (CGFloat(pixel[0]) + CGFloat(pixel[1]) + CGFloat(pixel[2])) / (3 * 255)
    }

    /// 21 의 확인창은 공용 `MoyeotaConfirmDialog` 다(디자인 QA G11). 화면이 그 오버레이를 덮어 띄우는 자리에서 잰다.
    @Test("21 확인창은 본문이 접히면 폭 320 이고 시스템 바를 뺀 영역의 가운데에 놓인다")
    func widthAndPosition() async {
        let window = InsetWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UIHostingController(
            rootView: MatchWaitingScreen(ride: geometryRide, now: geometryNow).seeded(cancelConfirming: true).ignoresSafeArea(.container)
        )
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<12 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(25))
        }
        // 카드 왼쪽 안쪽 여백 세로줄에서 흰 구간을 찾는다. 글자는 안쪽 여백 24 안으로 들어오지 않는다.
        let white = (0..<874).filter { brightness(window, x: 55, y: CGFloat($0)) > 0.98 }
        let longest = white.reduce(into: [[Int]]()) { runs, y in
            if let last = runs.last?.last, last == y - 1 { runs[runs.count - 1].append(y) } else { runs.append([y]) }
        }.max { $0.count < $1.count } ?? []
        #expect(longest.count > 100, "카드를 찾아야 시험이 된다")
        let top = longest.first ?? 0
        let bottom = (longest.last ?? 0) + 1
        // (62 + (874 − 34)) / 2 = 451. 화면 가운데(437)가 아니다.
        #expect(abs(CGFloat(top + bottom) / 2 - 451) < 1, "카드 \(top)…\(bottom)")

        // 원본은 문구와 상관없이 320 이다. 가장 긴 줄로 줄어들면 이 값이 달라진다.
        let xs = (0..<402).filter { brightness(window, x: CGFloat($0), y: CGFloat(top + 40)) > 0.98 }
        let width = CGFloat((xs.last ?? 0) + 1 - (xs.first ?? 0))
        #expect(abs(width - 320) < 1, "카드 폭 \(width)")
    }
}

@MainActor
@Suite(.serialized) struct RenderedGeometryTest {

    private func hosted(_ view: some View) async -> UIWindow {
        let window = InsetWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UIHostingController(rootView: AnyView(view.ignoresSafeArea(.container)))
        window.isHidden = false
        for _ in 0..<12 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(25))
        }
        return window
    }

    private func brightness(_ window: UIWindow, x: CGFloat, y: CGFloat) -> CGFloat {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else { return -1 }
        context.translateBy(x: -x, y: -y)
        window.layer.render(in: context)
        return (CGFloat(pixel[0]) + CGFloat(pixel[1]) + CGFloat(pixel[2])) / (3 * 255)
    }

    private func rideCountInkWidth(rideCount: Int) async -> CGFloat {
        let window = await hosted(PartnerProfileScreen(user: geometryUser(rideCount: rideCount)))
        defer { window.isHidden = true }
        // 「탑승 횟수 · N회」는 닉네임 바로 아래 한 줄이다(PP1 — 지표 카드가 없어졌다). 위에서부터
        // 상태바 62 · 앱바 56 · 16 · 아바타 80 · 12 · 닉네임 34.6 · 8 을 지나 268.6 에서 21.6 높이로 놓인다.
        // 그 위아래 24 안쪽에는 다른 글자가 없다(닉네임은 255 위, 안내 문구는 314 아래). 글자색이 72% 회색
        // (`TextBody`)에 굵기 Regular 라 획이 옅으므로, 흰 바탕에서 조금이라도 물든 칸을 글자로 센다.
        var xs: [Int] = []
        for y in stride(from: CGFloat(262), to: 300, by: 1) {
            for x in 40..<362 where brightness(window, x: CGFloat(x) + 0.5, y: y) < 0.8 { xs.append(x) }
        }
        return CGFloat((xs.max() ?? 0) + 1 - (xs.min() ?? 0))
    }

    @Test("23 「11회」는 1 이 좁아지지 않아 「88회」와 폭이 같다(원본 Roboto 숫자는 폭이 같다)")
    func rideCountDigitsAreTabular() async {
        let eleven = await rideCountInkWidth(rideCount: 11)
        let eightyEight = await rideCountInkWidth(rideCount: 88)
        #expect(eleven > 80, "「탑승 횟수 · 11회」 줄을 찾아야 시험이 된다: \(eleven)")
        #expect(abs(eleven - eightyEight) < 3, "11회 \(eleven) 대 88회 \(eightyEight)")
    }
}

private func geometryUser(rideCount: Int) -> User {
    User(id: "1", nickname: "모여타이", verifiedLabel: "", rating: 0, rideCount: rideCount)
}

private let geometryRide = Ride(
    id: "1", origin: "센텀시티역", destination: "서면역", departureLabel: "지금 출발",
    capacity: 3, members: [], farePerPerson: 3600, totalFare: 10800, status: .recruiting
)

/// 약속 단계 판정의 고정 시각. 모집 중인 방이라 단계에 영향이 없지만, 화면이 시계를 읽지 않으므로 넘겨야 한다.
private let geometryNow = Date(timeIntervalSince1970: 1_793_944_800) // 2026-11-06T06:00:00Z
