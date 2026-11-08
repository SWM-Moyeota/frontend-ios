import Foundation
import MoyeotaDomain
import PresentationCore
import Testing
@testable import FeatureHome

/// 16 도착지 확인의 **예약 방 규칙** — 정원 범위·7일 창·시각 슬롯·보내는 값·실패 문구.
///
/// 원본 `ReservationRulesTest`(26개) 가운데 홈에 남은 함수를 보는 19개다. 나머지 7개(날짜·검색 날짜·
/// 날짜와 시각 문구·나갈 수 없다는 안내)는 함수와 함께 `PresentationCoreTests/ReservationRulesTest.swift`
/// 로 옮겼다.
///
/// 이 테스트가 잡는 것은 전부 **화면에서는 안 보이는 결함**이다: 7일 뒤 늦은 시각을 고를 수 있는
/// 화면과 올바른 화면은 눈으로 같고, 차이는 서버 400 으로만 드러난다. KST 자정 직후의 날짜 계산도
/// 같다 — 기기 시간대로 셈하면 검색이 하루 밀리는데 그 자리에는 「그 날 예약이 없어요」가 뜬다.
@Suite struct ReservationRulesTest {

    /// KST 2026-11-09 (월) 13:00 — 기준 시각. UTC 로는 11-09 04:00 이라 날짜가 같다.
    private let now = Date(timeIntervalSince1970: 1_794_196_800) // 2026-11-09T04:00:00Z

    // ─────────────────────────── 정원 ───────────────────────────

    /// 서버 계약: 실시간 `Capacity` 는 1~3, **예약은 2~3**. 벗어나면 400 `INVALID_CAPACITY`.
    @Test("정원 선택지는 모드마다 다르다 - 예약은 1 을 지운다")
    func capacityChoicesPerMode() {
        #expect(capacityChoices(mode: .now) == [1, 2, 3])
        #expect(capacityChoices(mode: .scheduled) == [2, 3])
    }

    /// **1 을 고른 채 「시간 정하기」로 바꾸는 길이 있다** — 그 상태는 보낼 수 없으므로 접는다.
    /// 고른 값 자체는 화면이 그대로 들고 있어서 모드를 되돌리면 1 이 살아 있다(여기서는 변환만 본다).
    @Test("예약으로 바꾸면 1명은 2명으로 접힌다")
    func scheduledFoldsSoloToTwo() {
        #expect(capacityFor(mode: .scheduled, selected: 1) == 2)
        #expect(capacityFor(mode: .scheduled, selected: 2) == 2)
        #expect(capacityFor(mode: .scheduled, selected: 3) == 3)
        // 실시간에서는 1 이 유효한 선택이다 — 접지 않는다(혼자 타기를 상품으로 인정한 결정)
        #expect(capacityFor(mode: .now, selected: 1) == 1)
    }

    /// 화면에 없는 값이 들어와도 **가장 가까운 유효값**이다 — 서버가 막아 주는 것과 앱이 보내지 않는 것은 다른 보호막이다.
    @Test("범위 밖 정원은 가장 가까운 유효값이 된다")
    func outOfRangeCapacityClamps() {
        #expect(capacityFor(mode: .now, selected: 9) == 3)
        #expect(capacityFor(mode: .scheduled, selected: 9) == 3)
        #expect(capacityFor(mode: .now, selected: 0) == 1)
        #expect(capacityFor(mode: .scheduled, selected: 0) == 2)
    }

    // ─────────────────────────── 시각 슬롯 ───────────────────────────

    @Test("오늘 슬롯은 지금보다 뒤이고 10분 여유를 둔다")
    func todaySlotsKeepLeadTime() throws {
        let today = try LocalDate.of(2026, 11, 9) // 기준 시각은 KST 13:00
        let slots = reservationTimeSlots(date: today, now: now)

        // 13:00 + 10분 = 13:10 **초과**여야 하므로 13:30 이 가장 이르다(13:00 도 13:10 도 아니다)
        #expect(try slots.first == LocalTime.of(13, 30))
        #expect(try slots.last == LocalTime.of(23, 30))
        #expect(try !slots.contains(LocalTime.of(12, 30)), "이미 지난 시각")
        // 30분 간격이라 자정 뒤 전부를 세면 하루 48개에서 지난 만큼이 빠진다
        #expect(slots.count == 21)
    }

    @Test("내일은 자정부터 전부 고를 수 있다")
    func tomorrowHasAllSlots() throws {
        let slots = try reservationTimeSlots(date: LocalDate.of(2026, 11, 10), now: now)

        #expect(slots.count == 48)
        #expect(try slots.first == LocalTime.of(0, 0))
        #expect(try slots.last == LocalTime.of(23, 30))
    }

    /// ★ **보이지 않는 경계** — 「7일 뒤」 칩은 있는데 그 날 늦은 시각은 창을 넘는다.
    ///
    /// 기준 시각이 KST 13:00 이므로 7일 뒤에 허용되는 것은 **그 날 13:00 까지**다. 이 필터가 없으면
    /// 사용자가 7일 뒤 23:30 을 골라 400 `INVALID_DEPARTURE_TIME` 을 만든다.
    @Test("7일 뒤는 지금 시각까지만 고를 수 있다")
    func lastDayEndsAtNow() throws {
        let slots = try reservationTimeSlots(date: LocalDate.of(2026, 11, 16), now: now)

        #expect(try slots.first == LocalTime.of(0, 0))
        // 정확히 「지금 + 7일」인 13:00 은 **포함**이다(서버가 그 경계를 받는다)
        #expect(try slots.last == LocalTime.of(13, 0))
        #expect(try !slots.contains(LocalTime.of(13, 30)))
    }

    /// 자정 직후에는 7일 뒤의 선택지가 **자정 한 칸**으로 줄어든다(비지는 않는다).
    @Test("자정 직후의 7일 뒤는 자정 한 칸만 남는다")
    func lastDayJustAfterMidnight() throws {
        let justAfterMidnight = Date(timeIntervalSince1970: 1_794_150_300) // 2026-11-08T15:05:00Z, KST 11-09 00:05
        let lastDay = try #require(reservationDates(now: justAfterMidnight).last) // 11-16

        #expect(try reservationTimeSlots(date: lastDay, now: justAfterMidnight) == [LocalTime.of(0, 0)])
    }

    /// 늦은 밤에는 **「오늘」에 고를 시각이 없다** — 화면이 안내를 띄우는 상태다
    /// (`RESERVATION_NO_SLOT_NOTICE`). 오늘의 마지막 슬롯이 23:30 이고 10분 여유가 필요하다.
    @Test("밤 23시 55분에는 오늘 고를 시간이 없다")
    func lateNightHasNoSlotToday() throws {
        let lateNight = Date(timeIntervalSince1970: 1_794_236_100) // 2026-11-09T14:55:00Z, KST 23:55
        let today = try #require(reservationDates(now: lateNight).first)

        #expect(reservationTimeSlots(date: today, now: lateNight).isEmpty)
        // 내일은 고를 수 있다 — 「고를 수 없다」가 날짜 하나에만 걸린다.
        // 다만 **자정 칸은 빠진다**(지금부터 5분 뒤라 10분 여유에 걸린다) — 48개가 아니라 47개다.
        let tomorrow = reservationTimeSlots(date: today.plusDays(1), now: lateNight)
        #expect(tomorrow.count == 47)
        #expect(try tomorrow.first == LocalTime.of(0, 30))
    }

    // ─────────────────────────── 보내는 값 ───────────────────────────

    /// 서버는 `Instant` 를 받는다 — **오프셋 없는 로컬 시각은 400** 이고 그 400 은 어떤 사유에도
    /// 걸리지 않아 일반 문구로 떨어진다(가장 찾기 어려운 실패다).
    @Test("출발 시각은 오프셋이 붙은 순간 문자열로 나간다")
    func departureIsInstantString() throws {
        let iso = try reservationDepartureIso(date: LocalDate.of(2026, 11, 9), time: LocalTime.of(18, 30))

        // KST 18:30 = UTC 09:30 — **문자열 모양이 아니라 가리키는 순간**을 고정한다
        #expect(try Date(iso, strategy: .iso8601) == Date(timeIntervalSince1970: 1_794_216_600)) // 2026-11-09T09:30:00Z
        #expect(iso.hasSuffix("Z"), "UTC 표기(Z)로 끝나야 한다: \(iso)")
        #expect(!iso.contains(" "), "날짜와 시각 사이에 공백을 넣지 않는다: \(iso)")
    }

    // ─────────────────────────── 표기 ───────────────────────────

    /// CTA 앞에서 두 선택이 합쳐져 무엇이 되는지 되읽어 주는 줄 — 예약은 되돌릴 수 없다.
    @Test("고른 출발 시각 요약은 날짜와 시각을 함께 적는다")
    func departureSummary() throws {
        let today = try LocalDate.of(2026, 11, 9)

        #expect(try reservationDepartureSummary(date: today, time: LocalTime.of(18, 30), today: today) == "오늘 오후 6:30")
        #expect(
            try reservationDepartureSummary(date: today.plusDays(6), time: LocalTime.of(9, 0), today: today)
                == "11월 15일 (일) 오전 9:00"
        )
    }

    // ─────────────────────────── 실패 문구 ───────────────────────────

    private func failure(_ code: String?, httpStatus: Int? = 400) -> PartyOpenException {
        PartyOpenException(code: code, serverMessage: nil, httpStatus: httpStatus)
    }

    /// 「다시 시도」류를 403·409 에 붙이지 않는다 — `FinishFailureMessageTest` 가 세운 규칙이다.
    private func expectNoRetryPromise(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for forbidden in ["다시 시도", "잠시 후", "잠시만", "재시도"] {
            #expect(!message.contains(forbidden), "재시도를 약속한다: \(message)", sourceLocation: sourceLocation)
        }
    }

    /// ★ 403 `NO_SHOW_RESTRICTED` — **재시도할 수 없는 실패**다. 끝나는 시각이 서버에 있고
    /// 그때까지는 몇 번 눌러도 같은 403 이다.
    ///
    /// 그 시각(`restrictedUntil`)을 **여기서 말하지 않는다**: 이 화면은 그 값을 읽지 않으므로
    /// 숫자를 적으면 지어내는 것이고, 「마이페이지에서 보세요」는 이 화면이 확인할 수 없는 약속이다.
    @Test("노쇼 제재는 왜 막혔는지만 말하고 재시도를 약속하지 않는다")
    func noShowRestrictedSaysWhyOnly() {
        let message = reservationOpenFailureMessage(e: failure(PartyOpenException.NO_SHOW_RESTRICTED, httpStatus: 403))

        #expect(message == "노쇼 제재 중에는 방을 만들 수 없어요. 제재가 끝나면 다시 만들 수 있어요")
        expectNoRetryPromise(message)
        #expect(message.contains("노쇼"), "왜 막혔는지 말해야 한다")
        // 모르는 숫자·다른 화면을 가리키지 않는다
        #expect(!message.contains("시까지"), "\(message)")
        #expect(!message.contains("마이페이지"), "\(message)")
    }

    /// 409 `PARTY_TIME_CONFLICT` — 앱이 **예측하지 않는** 실패다(내 다른 예약 목록을 이 화면이
    /// 모른다). 그래서 문구가 유일한 안내이고, 다음 행동은 **다른 시간을 고르는 것**이다.
    @Test("출발 2시간 안에 다른 예약이 있으면 다른 시간을 고르라고 말한다")
    func timeConflictAsksOtherTime() {
        let message = reservationOpenFailureMessage(e: failure(PartyOpenException.PARTY_TIME_CONFLICT, httpStatus: 409))

        #expect(message == "출발 2시간 안에 다른 예약이 있어요. 다른 시간으로 골라 주세요")
        expectNoRetryPromise(message)
        // 「2시간」은 서버 규칙이라 숫자를 적는다 — 없으면 얼마나 옮겨야 하는지 알 수 없다
        #expect(message.contains("2시간"), "\(message)")
    }

    @Test("출발 시각이 7일을 벗어나면 창을 숫자로 말한다")
    func invalidDepartureTimeNamesWindow() {
        let message = reservationOpenFailureMessage(e: failure(PartyOpenException.INVALID_DEPARTURE_TIME))

        #expect(message == "출발 시각은 지금부터 7일 안이어야 해요. 다른 시간으로 골라 주세요")
        #expect(message.contains("7일"), "\(message)")
    }

    /// ★ 정원 문구가 실시간과 **달라야** 한다 — 예약에서 1 은 고를 수 없는 값이다.
    ///
    /// 다만 **정원 1 은 이 코드로 오지 않는다**: 서버가 `@Min(2)` 빈 검증으로 먼저 막아 400
    /// `INVALID_REQUEST` 가 되고, 그건 `PartyOpenException.isInvalidCapacity` 에 걸리지 않아
    /// 일반 문구로 떨어진다(아래 테스트). 그래서 **진짜 방어는 칩에서 1 을 지우는 것**이고
    /// (`capacityChoices`·`capacityFor`) 이 문구는 상한을 어긴 요청 같은 나머지를 받는다.
    @Test("예약 정원 실패는 2에서 3이라고 말한다")
    func reservationCapacityCopy() {
        let message = reservationOpenFailureMessage(e: failure(PartyOpenException.INVALID_CAPACITY))

        #expect(message == "예약 방 인원은 2~3명이어야 해요")
        #expect(!message.contains("1~3"), "실시간 범위를 말하면 고를 수 없는 값을 고르라고 하게 된다")
        // 실시간 쪽은 그대로다 — 두 문구가 서로를 덮지 않는다
        #expect(openFailureMessage(e: failure(PartyOpenException.INVALID_CAPACITY)) == "인원은 1~3명까지만 정할 수 있어요")
    }

    /// 겹치는 사유는 **같은 문장**을 쓴다 — 같은 사실을 두 가지로 말하지 않는다.
    @Test("실시간과 같은 사유는 같은 문구를 쓴다")
    func sharedReasonsShareCopy() {
        for code in [PartyOpenException.SAME_DEPARTURE_DESTINATION, PartyOpenException.OUT_OF_SERVICE_AREA] {
            #expect(openFailureMessage(e: failure(code)) == reservationOpenFailureMessage(e: failure(code)))
        }
        let conflict = failure("ALREADY_JOINED_OTHER_PARTY", httpStatus: 409)
        #expect(reservationOpenFailureMessage(e: conflict) == ALREADY_IN_PARTY_MESSAGE)
    }

    /// **정원 1 로 보낸 예약은 `INVALID_REQUEST` 다**(서버 `@Min(2)` 빈 검증이 도메인보다 먼저 돈다).
    /// 그 코드는 어느 사유에도 걸리지 않아 일반 문구로 떨어진다 — 그래서 UI 가 1 을 **고를 수 없게**
    /// 만드는 것이 유일한 실질적 방어다(`capacityChoices`). 그 사실을 여기 값으로 고정해 둔다.
    @Test("정원 1 로 보낸 예약은 일반 문구로 떨어진다 - 칩에서 막는 것이 유일한 방어다")
    func soloReservationFallsToGeneralCopy() {
        #expect(reservationOpenFailureMessage(e: failure("INVALID_REQUEST")) == RESERVATION_OPEN_FAILED_MESSAGE)
        // 고를 수 있는 값에 1 이 없다 — 이 보장이 위 문구보다 먼저다
        #expect(!capacityChoices(mode: .scheduled).contains(1))
    }

    /// 서버가 코드를 늘려도 앱이 지어내지 않는다. **경로 실패 가지를 두지 않은 것**도 여기서 드러난다 —
    /// 서버는 예약 방에 경로를 계산하지 않으므로 그 코드가 와도 「경로를 찾지 못했어요」로 말하지 않는다.
    @Test("모르는 코드는 일반 문구로 떨어진다")
    func unknownCodeFallsToGeneralCopy() {
        #expect(reservationOpenFailureMessage(e: failure("SOMETHING_NEW")) == RESERVATION_OPEN_FAILED_MESSAGE)
        #expect(reservationOpenFailureMessage(e: failure(nil, httpStatus: 500)) == RESERVATION_OPEN_FAILED_MESSAGE)
        #expect(
            reservationOpenFailureMessage(e: failure(PartyOpenException.ROUTE_SEARCH_FAILED, httpStatus: 502))
                == RESERVATION_OPEN_FAILED_MESSAGE
        )
        // 예약을 만들려던 사람에게 「동승 방」이라고 말하지 않는다
        #expect(RESERVATION_OPEN_FAILED_MESSAGE.contains("예약 방"), "\(RESERVATION_OPEN_FAILED_MESSAGE)")
    }

    // ─────────────────────────── 요금 없음 문구 ───────────────────────────

    /// ★ **예약 방에 예상 요금·소요 시간이 없다는 것을 말해야 한다.**
    ///
    /// 이 저장소는 거짓 문구 19개를 들어낸 이력이 있고(`ProductClaimsTest`), 이 자리가 바로 그런
    /// 자리였다: `POST /matching/routes` 추정은 예약에서도 성공하므로 아무것도 고치지 않으면
    /// 화면이 **방에는 없는 금액**을 적는다. 그래서 숫자를 감추고 **없다는 사실**을 적는다.
    @Test("예약 안내는 요금과 소요 시간이 없다고 말한다")
    func noEstimateNotice() {
        #expect(RESERVATION_NO_ESTIMATE_NOTICE.contains("예상 요금"), "\(RESERVATION_NO_ESTIMATE_NOTICE)")
        #expect(RESERVATION_NO_ESTIMATE_NOTICE.contains("소요 시간"), "\(RESERVATION_NO_ESTIMATE_NOTICE)")
        // 「계산 중」처럼 곧 나올 것처럼 말하지 않는다 — 서버가 끝까지 주지 않는다
        #expect(!RESERVATION_NO_ESTIMATE_NOTICE.contains("계산"), "\(RESERVATION_NO_ESTIMATE_NOTICE)")
        // 서버가 보내는 알림(예약 리마인더)을 **약속하지 않는다** — 앱이 확인할 수 없는 말이다
        for copy in [RESERVATION_NO_ESTIMATE_NOTICE, RESERVATION_CAPACITY_NOTICE, RESERVATION_NEEDS_TIME_NOTICE] {
            #expect(!copy.contains("알림"), "없는 알림을 약속한다: \(copy)")
            #expect(!copy.contains("알려 드려요"), "없는 알림을 약속한다: \(copy)")
        }
    }

    @Test("예약 정원 안내는 2명부터라는 사실만 말한다")
    func capacityNotice() {
        #expect(RESERVATION_CAPACITY_NOTICE == "예약 방은 2명부터 만들 수 있어요")
        // 혼자 출발 안내와 **함께 뜨지 않는다** — 예약에서 정원은 1 이 될 수 없다
        #expect(soloCapacityNotice(capacity: capacityFor(mode: .scheduled, selected: 1)) == nil)
    }
}
