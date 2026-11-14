import Foundation
import Testing
@testable import MoyeotaDesignSystem

/// 20 합류 확인 지도의 **카메라 맞춤과 물러나는 순서** — `routeCameraTarget`.
///
/// 원본은 `presentation/src/test/.../feature/explore/RouteCameraTargetTest.kt` 이고 디자인시스템 함수만 본다.
/// iOS 는 함수가 있는 모듈의 테스트로 옮겼다(FeatureExploreTests 에 다시 옮기지 않는다).
///
/// 오너 UX 피드백(2026-11): 「가끔 엉뚱한 곳, 심지어 해외가 보인다」. 원인은 (0,0) 같은 **값이 빠졌을 때의
/// 기본 좌표**가 카메라 범위에 섞여 기니만 앞바다까지 담으려 했던 것이다. 지도는 스크린샷 없이는 확인할 수
/// 없으므로 계산을 SDK 없는 순수 함수로 빼고 여기서 고정한다:
/// - 쓸 수 있는 점 둘 이상 → 그 점들의 **경계에 맞춘다**(최대 줌 16)
/// - (0,0) · NaN · 범위 밖은 **버린다**
/// - 못 맞추면 출발지 → 도착지 → 사용자 주변 → 앱 기본 카메라 순. **SDK 기본(서울)으로는 떨어지지 않는다**
@Suite struct RouteCameraTargetTest {
    private let seomyeon = GeoPoint(35.1578, 129.0594)
    private let pnu = GeoPoint(35.2313, 129.0846)
    private static let myAreaPoint = GeoPoint(35.1796, 129.0756)
    private var myArea: GeoPoint { Self.myAreaPoint }

    /// 20 의 지도 스트립(393 × 172)과 같은 크기·여백.
    private func target(
        origin: GeoPoint?,
        destination: GeoPoint?,
        route: [GeoPoint] = [],
        fallback: GeoPoint? = RouteCameraTargetTest.myAreaPoint
    ) -> CameraTarget {
        routeCameraTarget(
            origin: origin,
            destination: destination,
            route: route,
            fallback: fallback,
            widthDp: 393,
            heightDp: 172,
            insetTopDp: 46 + 55,
            insetBottomDp: 12 + 20,
            insetSideDp: 48
        )
    }

    private func isNear(_ camera: CameraTarget, _ point: GeoPoint, tolerance: Double = 0.05) -> Bool {
        abs(camera.latitude - point.latitude) < tolerance && abs(camera.longitude - point.longitude) < tolerance
    }

    @Test("출발지와 도착지가 있으면 둘 사이에 맞춘다")
    func fitsBetweenOriginAndDestination() {
        let camera = target(origin: pnu, destination: seomyeon)

        // 가운데는 두 점 사이(위도는 여백 비대칭으로 조금 북쪽으로 옮겨진다), 줌은 도시 단위
        #expect((seomyeon.longitude...pnu.longitude).contains(camera.longitude))
        #expect((seomyeon.latitude...(pnu.latitude + 0.05)).contains(camera.latitude))
        #expect((8.0...14.0).contains(camera.zoom), "두 점이 다 들어오려면 축소돼 있어야 한다: \(camera.zoom)")
    }

    /// 아주 가까운 두 점에 거리 단위까지 당기지 않는다 — 최대 줌 16.
    @Test("아주 가까운 두 점도 줌 16 을 넘지 않는다")
    func closePointsCapZoom() {
        let camera = target(origin: seomyeon, destination: GeoPoint(seomyeon.latitude + 0.0001, seomyeon.longitude))

        #expect(abs(camera.zoom - 16.0) < 1e-9)
    }

    /// ★ 「해외가 보인다」의 원인 — (0,0) 이 범위에 섞이면 바다 한가운데를 비춘다. 버리고 나머지로 맞춘다.
    @Test("0,0 출발지는 버리고 도착지로 물러난다")
    func zeroOriginFallsBackToDestination() {
        let camera = target(origin: GeoPoint(0.0, 0.0), destination: seomyeon)

        #expect(camera == CameraTarget(seomyeon.latitude, seomyeon.longitude, SinglePointZoom))
    }

    @Test("도착지를 못 쓰면 출발지에 줌 15 로 선다")
    func unusableDestinationUsesOrigin() {
        #expect(
            target(origin: pnu, destination: GeoPoint(Double.nan, 129.0))
                == CameraTarget(pnu.latitude, pnu.longitude, SinglePointZoom)
        )
        #expect(target(origin: pnu, destination: nil) == CameraTarget(pnu.latitude, pnu.longitude, SinglePointZoom))
    }

    @Test("둘 다 못 쓰면 사용자 주변으로 물러난다")
    func fallsBackToUserArea() {
        let camera = target(origin: GeoPoint(0.0, 0.0), destination: nil, fallback: myArea)

        #expect(camera == CameraTarget(myArea.latitude, myArea.longitude, AreaFallbackZoom))
    }

    /// 끝까지 아무것도 없어도 **앱 기본 카메라**(부산 서면)다 — SDK 기본값(서울)이 아니다.
    @Test("사용자 위치도 없으면 앱 기본 카메라다")
    func fallsBackToAppDefault() {
        let camera = target(origin: nil, destination: GeoPoint(0.0, 0.0), fallback: nil)

        #expect(camera == CameraTarget(MoyeotaDefaultGeoPoint.latitude, MoyeotaDefaultGeoPoint.longitude, AreaFallbackZoom))
        #expect(!isNear(camera, GeoPoint(37.5666, 126.9784), tolerance: 1.0), "SDK 기본(서울 시청 부근)이 아니다")
    }

    /// 위·경도가 뒤바뀐 응답(QA D-1, 위도 126.97)과 깨진 경로선 점도 버린다.
    @Test("범위 밖 좌표와 깨진 경로선 점은 카메라 범위에 들지 않는다")
    func dropsOutOfRangePoints() {
        let camera = target(
            origin: GeoPoint(126.97, 37.56), // 뒤바뀐 좌표 — 위도 126.97 은 없다
            destination: seomyeon,
            route: [pnu, GeoPoint(351.0, 1290.0), GeoPoint(0.0, 0.0), seomyeon]
        )

        // 남은 점은 서면·부산대 둘 — 그 사이에 맞춘다(해외·바다가 아니다)
        #expect(
            isNear(
                camera,
                GeoPoint((seomyeon.latitude + pnu.latitude) / 2, (seomyeon.longitude + pnu.longitude) / 2),
                tolerance: 0.1
            )
        )
        #expect(camera.zoom > 8.0)
    }

    @Test("같은 점 두 개는 맞출 수 없어 그 점으로 물러난다")
    func samePointFallsBack() {
        #expect(fitCameraTarget(points: [seomyeon, seomyeon], widthDp: 393, heightDp: 172) == nil)
        #expect(target(origin: seomyeon, destination: seomyeon) == CameraTarget(seomyeon.latitude, seomyeon.longitude, SinglePointZoom))
    }

    @Test("쓸 수 있는 좌표의 기준")
    func usableCoordinateRules() {
        #expect(isUsableMapCoordinate(latitude: 35.15, longitude: 129.05))
        #expect(!isUsableMapCoordinate(latitude: 0.0, longitude: 0.0), "값이 빠졌을 때의 기본값")
        #expect(isUsableMapCoordinate(latitude: 0.0, longitude: 129.0), "한쪽만 0 은 실제 좌표일 수 있다")
        #expect(!isUsableMapCoordinate(latitude: nil, longitude: 129.0))
        #expect(!isUsableMapCoordinate(latitude: Double.nan, longitude: 129.0))
        #expect(!isUsableMapCoordinate(latitude: 35.0, longitude: Double.infinity))
        #expect(!isUsableMapCoordinate(latitude: 126.97, longitude: 37.56))
    }
}
