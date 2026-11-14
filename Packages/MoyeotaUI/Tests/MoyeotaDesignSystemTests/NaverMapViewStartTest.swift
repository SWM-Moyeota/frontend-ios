import SwiftUI
import Testing
import UIKit
@testable import MoyeotaDesignSystem

// 원본에 없는 테스트. 원본은 `NaverMapOptions.locale`·`camera` 로 지도를 만들 때부터 한국어 라벨과 화면의 카메라로 시작한다.
// iOS SDK 에는 생성 옵션이 없어 만든 직후(크기 0)에 넣으므로, SDK 가 그 순서를 받아 주는지와 결과가 같은지 창에 올려 본다.

@MainActor
private final class MapBox {
    var map: NMFMapView?
}

@MainActor
@Suite(.serialized) struct NaverMapViewStartTest {
    /// 크기 0 에서 옮긴 카메라는 크기를 받으면서 SDK 가 중심을 약 60m 밀어 둔다(시뮬레이터 실측: 위도 0.00056°·경도 0.00069°).
    /// 그래서 `NaverMapView` 는 첫 레이아웃에서 같은 카메라를 다시 넣는다 — 여기서는 「서울이 아니라 그 동네다」까지만 본다.
    @Test("크기가 0 일 때 넣은 로케일과 카메라가 크기를 받은 뒤에도 그 동네에 남는다")
    func zeroSizedMapKeepsLocaleAndCamera() {
        let map = NMFMapView(frame: .zero)
        map.locale = MoyeotaMapLocale
        map.moveCamera(NMFCameraUpdate(position: NMFCameraPosition(LatLng(35.2313, 129.0846).nmgLatLng, zoom: 15)))

        map.frame = CGRect(x: 0, y: 0, width: 393, height: 300)
        map.layoutIfNeeded()

        #expect(map.locale == "ko-KR")
        #expect(abs(map.cameraPosition.target.lat - 35.2313) < 0.01, "서울(37.57)로 돌아가지 않는다")
        #expect(abs(map.cameraPosition.target.lng - 129.0846) < 0.01)
        #expect(abs(map.cameraPosition.zoom - 15) < 1e-9)
    }

    @Test("NaverMapView 는 한국어 라벨과 화면이 준 카메라로 준비된다")
    func mapViewStartsKoreanAtGivenCamera() async throws {
        let box = MapBox()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = UIHostingController(
            rootView: NaverMapView(center: LatLng(35.2313, 129.0846), zoom: 15, onMapReady: { box.map = $0 })
                .frame(width: 393, height: 300)
        )
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<40 where box.map == nil {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(25))
        }

        let map = try #require(box.map)
        #expect(map.locale == MoyeotaMapLocale)
        #expect(abs(map.cameraPosition.target.lat - 35.2313) < 1e-4)
        #expect(abs(map.cameraPosition.target.lng - 129.0846) < 1e-4)
        #expect(abs(map.cameraPosition.zoom - 15) < 1e-6)
    }
}
