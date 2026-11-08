@testable import FeatureExplore
import Foundation
import MoyeotaDomain
import Testing

/// 20 합류 확인이 **예약 방에 대해 거짓을 말하지 않는지** 못 박는다.
///
/// 예약 방이 탐색 목록에 뜨기 시작하면서 생긴 자리다. 서버는 예약 방에 요금·경로·소요 시간을 넣지
/// 않는데 `Ride.totalFare`·`Ride.farePerPerson` 은 옵셔널이 아닌 `Int` 라 **0 으로 온다** — 고치기 전
/// 이 화면은 그 0 을 금액으로 그려 「총 예상 요금 0원 · 합류 시 1인 부담 0원」이라고 적었다.
/// 「공짜로 탄다」로 읽히는 문구를 합류 버튼 바로 위에 두는 셈이었다.
struct JoinFareDisplayTest {
    /// KST 2026-11-09 13:00.
    private let now = Date(timeIntervalSince1970: 1_794_196_800) // 2026-11-09T04:00:00Z

    private func ride(
        totalFare: Int = 0,
        farePerPerson: Int = 0,
        roomType: RoomType = .reservation,
        departureAt: String? = "2026-11-09T09:30:00Z",
        departureLabel: String = ""
    ) -> Ride {
        Ride(
            id: "1",
            origin: "부산대 정문",
            destination: "서면역",
            departureLabel: departureLabel,
            capacity: 3,
            members: [],
            farePerPerson: farePerPerson,
            totalFare: totalFare,
            status: .recruiting,
            departureAt: departureAt,
            isConfirmed: true,
            roomType: roomType
        )
    }

    // ─────────────────────────── 요금 ───────────────────────────

    @Test("요금을 모르는 방에는 요금 카드를 그리지 않는다")
    func noFareNoCard() {
        #expect(joinFareOrNull(totalFare: 0, farePerPerson: 0) == nil, "0원을 금액으로 그리면 공짜로 읽힌다")
    }

    @Test("요금이 있으면 서버 값을 그대로 쓴다")
    func fareKeepsServerValues() {
        #expect(
            joinFareOrNull(totalFare: 9_600, farePerPerson: 3_200)
                == JoinFare(totalFare: 9_600, farePerPerson: 3_200)
        )
        // 한쪽만 아는 응답에서도 카드는 세운다 — 그 조합은 지금 오지 않지만 값을 버리지 않는다
        #expect(joinFareOrNull(totalFare: 9_600, farePerPerson: 0) == JoinFare(totalFare: 9_600, farePerPerson: 0))
        #expect(joinFareOrNull(totalFare: 0, farePerPerson: 3_200) == JoinFare(totalFare: 0, farePerPerson: 3_200))
    }

    /// 예약 방은 **왜 없는지**를 말할 수 있다. 실시간 방의 0 은 사유를 모르므로 단정하지 않는다.
    @Test("요금이 없는 이유는 방 종류에 따라 다르게 말한다")
    func absentNoticeDependsOnRoomType() {
        let reservation = joinFareAbsentNotice(roomType: .reservation)
        #expect(reservation.contains("예약 방"), "\(reservation)")
        #expect(reservation.contains("미터기"), "무엇이 요금을 정하는지 말한다")

        let realtime = joinFareAbsentNotice(roomType: .realtime)
        #expect(realtime == "예상 요금을 받지 못했어요")
        #expect(!realtime.contains("예약"), "사유를 모르는 쪽에 예약을 붙이면 틀린 설명이 된다")
    }

    /// 둘 다 「요금을 받게 된다」고 약속하지 않는다 — 앱이 확인할 수 없는 말이다.
    @Test("요금 없음 안내는 요금이 생길 것이라고 약속하지 않는다")
    func absentNoticeMakesNoPromise() {
        for type in RoomType.allCases {
            let notice = joinFareAbsentNotice(roomType: type)
            for forbidden in ["계산 중", "곧 ", "나중에 알려", "다시 시도"] {
                #expect(!notice.contains(forbidden), "\(notice) — 지킬 수 없는 말: \(forbidden)")
            }
        }
    }

    // ─────────────────────────── 출발 표기 ───────────────────────────

    /// 예약 방에서 이 줄이 비면 **언제 출발하는지 모르고 합류**한다 — 목록에서 본 시각이 합류
    /// 화면에는 없는 상태가 된다.
    @Test("예약 방은 약속 시각에서 출발 표기를 만든다")
    func reservationDepartureFromMeetingTime() {
        #expect(joinDepartureLabel(ride: ride(), now: now) == "오늘 오후 6:30 출발")
    }

    /// 실시간 방은 예전 표기를 그대로 쓴다 — 서버 라벨에 거리가 함께 들어 있다.
    @Test("실시간 방은 서버 표기를 쓴다")
    func realtimeUsesServerLabel() {
        #expect(
            joinDepartureLabel(
                ride: ride(roomType: .realtime, departureLabel: "3분 후 출발 예정 · 6.2km"),
                now: now
            ) == nil
        )
    }

    /// 읽을 수 없는 약속 시각은 nil — 「시간 미정」으로 확정된 방을 미정처럼 보여 주지 않는다.
    @Test("약속 시각을 읽을 수 없으면 출발 표기가 없다")
    func unreadableMeetingTimeHasNoLabel() {
        #expect(joinDepartureLabel(ride: ride(departureAt: nil), now: now) == nil)
        #expect(joinDepartureLabel(ride: ride(departureAt: "2026-11-09T18:30:00"), now: now) == nil)
    }
}
