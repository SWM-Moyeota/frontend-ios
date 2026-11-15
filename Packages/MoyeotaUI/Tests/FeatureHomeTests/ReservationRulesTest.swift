import Foundation
import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import Testing
@testable import FeatureHome

/// 16 도착지 확인의 **예약 방 규칙** — 정원 범위·7일 창·시각 범위와 휠·보내는 값·실패 문구.
///
/// 원본 `ReservationRulesTest`(41개) 가운데 홈에 남은 함수를 보는 31개다. 나머지 10개(날짜·검색 날짜·
/// 날짜 띠의 칸과 달 표시·날짜와 시각 문구·나갈 수 없다는 안내)는 함수와 함께
/// `PresentationCoreTests/ReservationRulesTest.swift` 로 옮겼다. 「고를 시각이 없는 날」은 칸을 PresentationCore 의
/// `reservationDateCells` 가 만들지만 막는 판정(`reservationTimeRange`)과 기본 선택(`reservationSelectableDateIndex`)이
/// 홈에 있어 여기 남는다.
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

    // ─────────────────────────── 시각 범위(10분 휠) ───────────────────────────

    /// KST 벽시계 시각 → 순간. 테스트가 「한국 시간 몇 시」로 읽히게 한다.
    private func kst(_ date: LocalDate, _ hour: Int, _ minute: Int, _ second: Int = 0) throws -> Date {
        try date.atTime(LocalTime.of(hour, minute, second), LocalDate.seoulZone)
    }

    private var monday: LocalDate { LocalDate(year: 2026, month: 11, dayOfMonth: 9)! }

    /// 오늘의 가장 이른 값 = 「지금 + 10분」을 **10분 단위로 올림**. 정확히 경계에 떨어지면(초까지 0) 그대로다
    /// — 그 값이 이미 10분 여유를 품고 있다.
    @Test("오늘은 지금부터 10분 뒤를 10분 단위로 올린 시각부터다")
    func todayStartsAtLeadCeiled() throws {
        let range = try #require(reservationTimeRange(date: monday, now: now)) // 기준 시각 KST 13:00:00

        #expect(try range.earliest == LocalTime.of(13, 10))
        #expect(try range.latest == LocalTime.of(23, 50))
        #expect(try !range.contains(LocalTime.of(12, 50)), "이미 지난 시각")
    }

    /// 초가 남아 있으면 분 단위로 먼저 올린다 — 13:00:30 + 10분을 13:10 으로 내리면 여유가 30초 모자란다.
    @Test("초가 남아 있으면 다음 10분으로 올린다")
    func secondsCeilToNextStep() throws {
        #expect(try reservationTimeRange(date: monday, now: kst(monday, 13, 0, 30))?.earliest == LocalTime.of(13, 20))
        #expect(try reservationTimeRange(date: monday, now: kst(monday, 13, 3))?.earliest == LocalTime.of(13, 20))
        #expect(try reservationTimeRange(date: monday, now: kst(monday, 13, 10))?.earliest == LocalTime.of(13, 20))
    }

    @Test("내일은 자정부터 23시 50분까지 전부 고를 수 있다")
    func tomorrowIsWholeDay() throws {
        let range = try #require(reservationTimeRange(date: monday.plusDays(1), now: now))

        #expect(try range.earliest == LocalTime.of(0, 0))
        #expect(try range.latest == LocalTime.of(23, 50))
        #expect(reservationHourOptions(range: range) == Array(0...23))
        #expect(reservationMinuteOptions(range: range, hour: 18) == [0, 10, 20, 30, 40, 50])
    }

    /// ★ **보이지 않는 경계** — 「7일 뒤」 칸은 있는데 그 날 늦은 시각은 창을 넘는다.
    ///
    /// 기준 시각이 KST 13:00 이므로 7일 뒤에 허용되는 것은 **그 날 13:00 까지**다(경계 포함 — 서버가
    /// `isAfter` 로 본다). 이 경계가 없으면 사용자가 7일 뒤 23:50 을 골라 400 `INVALID_DEPARTURE_TIME` 을 만든다.
    @Test("7일 뒤는 지금 시각까지만 고를 수 있다")
    func lastDayEndsAtNow() throws {
        let range = try #require(reservationTimeRange(date: LocalDate.of(2026, 11, 16), now: now))

        #expect(try range.earliest == LocalTime.of(0, 0))
        #expect(try range.latest == LocalTime.of(13, 0))
        #expect(reservationHourOptions(range: range) == Array(0...13))
        #expect(reservationMinuteOptions(range: range, hour: 13) == [0], "마지막 시에는 정각만 남는다")
    }

    /// 늦은 쪽은 10분 단위로 **내린다** — 13:05 의 7일 뒤 13:10 은 이미 창 밖이다.
    @Test("7일 뒤의 마지막 값은 10분 단위로 내린다")
    func lastDayFloorsToStep() throws {
        let range = try #require(reservationTimeRange(date: LocalDate.of(2026, 11, 16), now: kst(monday, 13, 5)))

        #expect(try range.latest == LocalTime.of(13, 0))
    }

    /// 자정 직후에는 7일 뒤의 선택지가 **자정 한 칸**으로 줄어든다(비지는 않는다).
    @Test("자정 직후의 7일 뒤는 자정 한 칸만 남는다")
    func lastDayJustAfterMidnight() throws {
        let justAfterMidnight = Date(timeIntervalSince1970: 1_794_150_300) // 2026-11-08T15:05:00Z, KST 11-09 00:05
        let lastDay = try #require(reservationDates(now: justAfterMidnight).last) // 11-16

        let range = try #require(reservationTimeRange(date: lastDay, now: justAfterMidnight))
        #expect(try range.earliest == LocalTime.of(0, 0))
        #expect(try range.latest == LocalTime.of(0, 0))
    }

    /// 늦은 밤에는 **「오늘」에 고를 시각이 없다** — 오늘의 마지막 값이 23:50 이고 10분 여유가 필요하다.
    /// 그 날은 띠에서 누를 수 없고(`reservationDateCells`) 기본 선택이 다음 날로 옮겨 간다.
    @Test("밤 23시 55분에는 오늘 고를 시간이 없고 내일은 00시 10분부터다")
    func lateNightHasNoTimeToday() throws {
        let lateNight = Date(timeIntervalSince1970: 1_794_236_100) // 2026-11-09T14:55:00Z, KST 23:55
        let today = try #require(reservationDates(now: lateNight).first)

        #expect(reservationTimeRange(date: today, now: lateNight) == nil)
        // 23:55 + 10분 = 00:05 → 10분 단위로 올려 00:10
        #expect(try reservationTimeRange(date: today.plusDays(1), now: lateNight)?.earliest == LocalTime.of(0, 10))
    }

    @Test("밤 23시 40분 정각이면 오늘은 23시 50분 한 칸이 남는다")
    func lastStepAt2340() throws {
        let range = try #require(reservationTimeRange(date: monday, now: kst(monday, 23, 40)))

        #expect(try range.earliest == LocalTime.of(23, 50))
        #expect(try range.latest == LocalTime.of(23, 50))
        #expect(try reservationTimeRange(date: monday, now: kst(monday, 23, 41)) == nil, "1분만 지나도 오늘은 끝이다")
    }

    @Test("시 휠은 범위에 걸치는 시만 담고 분 휠은 그 시 안의 값만 담는다")
    func wheelOptionsFollowRange() throws {
        let range = try #require(reservationTimeRange(date: monday, now: kst(monday, 13, 3))) // 13:20 ~ 23:50

        #expect(reservationHourOptions(range: range) == Array(13...23))
        #expect(reservationMinuteOptions(range: range, hour: 13) == [20, 30, 40, 50], "첫 시는 잘린다")
        #expect(reservationMinuteOptions(range: range, hour: 14) == [0, 10, 20, 30, 40, 50])
    }

    // ─────────────────────────── 휠의 기본값·접기 ───────────────────────────

    /// ★ **규칙 변경** — 칩 시절에는 기본 선택이 없었다. 휠은 늘 값을 보여 주므로 손대지 않았으면
    /// **그 날의 가장 이른 시각**이 선택이고, CTA 는 켜진다(`reservationSelectedTime` 설명).
    @Test("휠을 건드리지 않았으면 그 날의 가장 이른 시각이 선택이다")
    func untouchedWheelSelectsEarliest() throws {
        #expect(try reservationSelectedTime(stored: nil, range: reservationTimeRange(date: monday, now: now)) == LocalTime.of(13, 10))
        #expect(
            try reservationSelectedTime(stored: nil, range: reservationTimeRange(date: monday.plusDays(1), now: now))
                == LocalTime.of(0, 0)
        )
    }

    @Test("그 날에 시각이 없으면 선택도 없다")
    func noRangeNoSelection() throws {
        let lateNight = Date(timeIntervalSince1970: 1_794_236_100) // 2026-11-09T14:55:00Z
        #expect(try reservationSelectedTime(stored: LocalTime.of(18, 0), range: reservationTimeRange(date: monday, now: lateNight)) == nil)
    }

    /// 날짜를 바꾸면 보여 줄 값만 그 날의 범위로 접는다 — 고른 값은 다른 날로 돌아가면 살아 있다.
    @Test("날짜를 바꾸면 고른 시각을 그 날의 범위로 접는다")
    func changingDateFoldsSelection() throws {
        let chosen = try LocalTime.of(18, 30)
        let lastDay = try reservationTimeRange(date: LocalDate.of(2026, 11, 16), now: now) // ~13:00
        let today = reservationTimeRange(date: monday, now: now) // 13:10~

        #expect(try reservationSelectedTime(stored: chosen, range: lastDay) == LocalTime.of(13, 0), "7일 뒤로 가면 마지막 값으로")
        #expect(
            try reservationSelectedTime(stored: LocalTime.of(9, 0), range: today) == LocalTime.of(13, 10),
            "오늘 이른 값은 가장 이른 값으로"
        )
        #expect(reservationSelectedTime(stored: chosen, range: today) == chosen, "범위 안이면 그대로")
    }

    @Test("10분 단위가 아닌 값은 10분 단위로 내려 접는다")
    func offStepValueSnapsDown() throws {
        let tomorrow = reservationTimeRange(date: monday.plusDays(1), now: now)
        #expect(try reservationSelectedTime(stored: LocalTime.of(18, 37, 12), range: tomorrow) == LocalTime.of(18, 30))
    }

    /// 시를 굴리면 분은 지키고, 범위를 벗어나면 범위 안으로 올린다.
    @Test("시를 굴리면 분을 지키되 범위로 접는다")
    func hourWheelKeepsMinute() throws {
        let range = try #require(reservationTimeRange(date: monday, now: kst(monday, 13, 3))) // 13:20 ~

        #expect(try reservationTimeWithHour(current: LocalTime.of(18, 40), hour: 15, range: range) == LocalTime.of(15, 40))
        #expect(try reservationTimeWithHour(current: LocalTime.of(18, 40), hour: 13, range: range) == LocalTime.of(13, 40))
        #expect(try reservationTimeWithHour(current: LocalTime.of(18, 0), hour: 13, range: range) == LocalTime.of(13, 20))
        #expect(try reservationTimeWithMinute(current: LocalTime.of(18, 0), minute: 50, range: range) == LocalTime.of(18, 50))
    }

    /// ★ **휠에 보이는 값 = 서버로 가는 값.** 접힌 값으로 ISO 를 만들고, 보내는 자리에서 시계를 다시 읽지
    /// 않는다 — 화면의 시각과 보낸 시각이 어긋나면 약속 시간이 다른 방이 만들어진다(바꿀 수 없다).
    @Test("보내는 출발 시각은 휠이 보여 주는 값과 같다")
    func sentValueIsShownValue() throws {
        let shown = try #require(reservationSelectedTime(stored: nil, range: reservationTimeRange(date: monday, now: now)))
        let iso = reservationDepartureIso(date: monday, time: shown)

        #expect(try shown == LocalTime.of(13, 10))
        #expect(try Date(iso, strategy: .iso8601) == Date(timeIntervalSince1970: 1_794_197_400)) // 2026-11-09T04:10:00Z
    }

    @Test("휠 글자는 시는 그대로 분은 두 자리다")
    func wheelLabels() {
        #expect(reservationHourLabel(hour: 0) == "0")
        #expect(reservationHourLabel(hour: 18) == "18")
        #expect(reservationMinuteLabel(minute: 0) == "00")
        #expect(reservationMinuteLabel(minute: 50) == "50")
    }

    // ─────────────────────────── 날짜 띠 ───────────────────────────

    /// 16 은 「그 날에 남은 시각이 있는가」로 칸을 막는다 — 늦은 밤의 오늘 칸은 누를 수 없다.
    @Test("고를 시각이 없는 날은 누를 수 없는 칸이 되고 기본 선택은 다음 날로 간다")
    func unselectableDayMovesDefault() {
        let lateNight = Date(timeIntervalSince1970: 1_794_236_100) // 2026-11-09T14:55:00Z, KST 23:55
        let dates = reservationDates(now: lateNight)
        let selectable: (LocalDate) -> Bool = { reservationTimeRange(date: $0, now: lateNight) != nil }
        let cells = reservationDateCells(dates: dates, today: dates[0], isSelectable: selectable)

        let todaySelectable = cells[0].enabled
        let restSelectable = cells.dropFirst().allSatisfy { $0.enabled }
        #expect(!todaySelectable)
        #expect(restSelectable)
        #expect(reservationSelectableDateIndex(storedIndex: 0, dates: dates, isSelectable: selectable) == 1)
        #expect(
            reservationSelectableDateIndex(storedIndex: 3, dates: dates, isSelectable: selectable) == 3,
            "고를 수 있는 날을 고른 것은 그대로"
        )
    }

    // ─────────────────────────── 기준 시각을 옮길 때 ───────────────────────────

    private func selectableAt(_ now: Date) -> (LocalDate) -> Bool {
        { reservationTimeRange(date: $0, now: now) != nil }
    }

    /// ★ 리뷰 반영(원본 PR #99): 23:58 에 「내일」을 고르고 00:05 에 누르면 다시 재기가 실패해 기준이 옮겨진다. 일수(1)를
    /// 그대로 두면 새 띠에서 「모레」를 가리킨다 — 보던 **달력 날짜**의 자리를 다시 찾는다. 화면 복귀(`onAppear`)도 같은 길이다.
    @Test("자정을 넘겨 기준을 옮겨도 고른 날짜는 그대로다")
    func clockMoveAcrossMidnightKeepsDate() throws {
        let opened = Date(timeIntervalSince1970: 1_794_236_280) // 2026-11-09T14:58:00Z, KST 11-09 23:58
        let tomorrow = LocalDate(year: 2026, month: 11, dayOfMonth: 10)!
        #expect(reservationDates(now: opened)[1] == tomorrow)
        // 「내일」의 기본 시각(가장 이른 00:10)은 00:05 에 누르면 여유를 잃었다 — 기준을 옮기는 길이다
        let defaultTime = try #require(reservationTimeRange(date: tomorrow, now: opened)).earliest
        #expect(defaultTime == LocalTime(hour: 0, minute: 10))
        let fresh = Date(timeIntervalSince1970: 1_794_236_700) // 2026-11-09T15:05:00Z, KST 11-10 00:05
        #expect(!reservationTimeStillValid(date: tomorrow, time: defaultTime, now: fresh))

        let freshDates = reservationDates(now: fresh)
        let offset = reservationDateOffsetAfterClockMove(
            selectedDate: tomorrow, newDates: freshDates, isSelectable: selectableAt(fresh)
        )

        #expect(offset == 0)
        let shown = reservationSelectableDateIndex(storedIndex: offset, dates: freshDates, isSelectable: selectableAt(fresh))
        #expect(freshDates[shown] == tomorrow)
        #expect(freshDates[1] == LocalDate(year: 2026, month: 11, dayOfMonth: 11)!, "예전처럼 일수를 그대로 두면 「모레」가 된다")
    }

    /// 자정을 넘기지 않으면 일수는 그대로다 — 날짜 띠가 움직이지 않았다.
    @Test("같은 날 안에서 기준을 옮기면 일수는 그대로다")
    func clockMoveWithinDayKeepsOffset() {
        let picked = reservationDates(now: now)[3]
        let fresh = now.addingTimeInterval(15 * 60) // KST 13:15
        #expect(
            reservationDateOffsetAfterClockMove(
                selectedDate: picked, newDates: reservationDates(now: fresh), isSelectable: selectableAt(fresh)
            ) == 3
        )
    }

    /// 「오늘」을 골라 둔 채 자정을 넘기면 그 날은 **어제**가 돼 띠에서 사라진다 — 고를 수 있는 첫 날로 간다.
    /// 고를 수 있는 날을 판정으로 고르는지는 가짜 판정으로 따로 본다(실제로는 자정 직후의 오늘은 늘 고를 수 있다).
    @Test("고른 날짜가 범위를 벗어나면 고를 수 있는 첫 날로 간다")
    func clockMoveDropsPastDateToFirstSelectable() {
        let today = LocalDate(year: 2026, month: 11, dayOfMonth: 9)!
        let fresh = Date(timeIntervalSince1970: 1_794_236_700) // KST 11-10 00:05 — 11-09 는 띠에서 빠졌다
        let freshDates = reservationDates(now: fresh)
        #expect(!freshDates.contains(today))

        #expect(
            reservationDateOffsetAfterClockMove(
                selectedDate: today, newDates: freshDates, isSelectable: selectableAt(fresh)
            ) == 0
        )
        #expect(
            reservationDateOffsetAfterClockMove(
                selectedDate: today, newDates: freshDates, isSelectable: { $0 != freshDates[0] }
            ) == 1
        )
    }

    /// 범위 안이지만 고를 수 없게 된 날(밤 23:40 을 넘긴 「오늘」)은 그 자리를 저장한다 — 보여 줄 때
    /// `reservationSelectableDateIndex` 가 다음 날로 접는다(「고른 값은 지우지 않고 보여 줄 값만 접는다」).
    @Test("범위 안이지만 고를 수 없게 된 날은 그 자리를 두고 보여 줄 때 접는다")
    func clockMoveKeepsUnselectableTodayForFolding() {
        let today = LocalDate(year: 2026, month: 11, dayOfMonth: 9)!
        let fresh = Date(timeIntervalSince1970: 1_794_235_500) // 2026-11-09T14:45:00Z, KST 23:45 — 오늘은 고를 시각이 없다
        let freshDates = reservationDates(now: fresh)

        let offset = reservationDateOffsetAfterClockMove(
            selectedDate: today, newDates: freshDates, isSelectable: selectableAt(fresh)
        )

        #expect(offset == 0)
        #expect(reservationSelectableDateIndex(storedIndex: offset, dates: freshDates, isSelectable: selectableAt(fresh)) == 1)
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

    @Test("지금 출발이면 휠에 시각이 있어도 출발 시각을 싣지 않는다")
    func nowModeSendsNoDepartureAt() throws {
        let date = LocalDate(year: 2026, month: 11, dayOfMonth: 14)!
        let time = LocalTime(hour: 21, minute: 30)!
        // 휠은 늘 값을 보여 준다 — 그 값을 「지금 출발」에서 실으면 실시간 방 대신 예약 방이 만들어진다
        #expect(matchDepartureAt(scheduled: false, date: date, time: time) == nil)
        // 「시간 정하기」면 휠 값 그대로 — 한국 21:30 = UTC 12:30
        let iso = try #require(matchDepartureAt(scheduled: true, date: date, time: time))
        #expect(try Date(iso, strategy: .iso8601) == Date(timeIntervalSince1970: 1_794_659_400)) // 2026-11-14T12:30:00Z
        #expect(iso == reservationDepartureIso(date: date, time: time))
        // 고를 시각이 없는 날(늦은 밤의 오늘)은 「시간 정하기」여도 없다 — CTA 가 잠긴다
        #expect(matchDepartureAt(scheduled: true, date: date, time: nil) == nil)
    }

    @Test("오래 열어 둬 여유를 잃은 기본 시각은 보내기 전에 다시 잰다")
    func staleDefaultTimeIsRechecked() throws {
        let opened = Date(timeIntervalSince1970: 1_794_628_830) // 2026-11-14T04:00:30Z, 한국 13:00:30
        let today = LocalDate(year: 2026, month: 11, dayOfMonth: 14)!
        let earliest = try #require(reservationTimeRange(date: today, now: opened)).earliest
        #expect(earliest == LocalTime(hour: 13, minute: 20)) // 13:10:30 → 10분 단위로 올림
        // 1분 뒤에 누르면 그대로 보낸다
        #expect(reservationTimeStillValid(date: today, time: earliest, now: opened.addingTimeInterval(60)))
        // 10분 넘게 머물면 13:20 은 여유가 없다 — 보내지 않고 기준을 옮긴다
        #expect(!reservationTimeStillValid(date: today, time: earliest, now: opened.addingTimeInterval(10 * 60 + 1)))
        // 고를 시각이 없으면 보낼 것이 없다
        #expect(!reservationTimeStillValid(date: today, time: nil, now: opened))
    }

    // ─────────────────────────── 다시 재기 안내 ───────────────────────────

    /// ★ 원본 리뷰 반영 2차(PR #99): 다시 재기가 실패하면 보내지 않고 휠만 옮기는데, 예전에는 그 사실을 말하지 않아
    /// 「안 눌렸다」로 읽혔다. 날짜가 그대로면 「가장 빠른 시각」, 날짜도 바뀌었으면 날짜와 시각을 둘 다 확인하라고 한다.
    /// 오류가 아니라 안내라 빨강으로 칠하지 않는다.
    @Test("다시 재기로 휠을 옮기면 날짜가 바뀌었는지에 따라 다른 안내를 남긴다")
    func clockMovedNoticeCopy() {
        #expect(reservationClockMovedNotice(dateChanged: false) == "시간이 지나 가장 빠른 시각으로 바꿨어요. 확인하고 다시 눌러 주세요")
        #expect(
            reservationClockMovedNotice(dateChanged: true) == "시간이 지나 다른 날로 바꿨어요. 날짜와 시각을 확인하고 다시 눌러 주세요"
        )
        for notice in [RESERVATION_TIME_MOVED_NOTICE, RESERVATION_DATE_MOVED_NOTICE] {
            #expect(notice.hasSuffix("다시 눌러 주세요"), "할 일을 말한다: \(notice)")
            #expect(!notice.contains("못") && !notice.contains("실패") && !notice.contains("오류"), "실패가 아니다: \(notice)")
        }
        #expect(RESERVATION_CLOCK_MOVED_NOTICE_KIND != NoticeKind.error, "오류 빨강이 아니다")
    }

    /// 안내가 가르는 「날짜가 바뀌었나」는 모달의 `moveClock(to:)` 이 하는 접기 그대로다 — 저장 일수를 새 띠에서 다시
    /// 찾고(`reservationDateOffsetAfterClockMove`) 고를 수 없는 날이면 첫 날로 접는다(`reservationSelectableDateIndex`).
    @Test("같은 날 안에서 여유를 잃으면 시각 안내고 그 날의 시각이 다 지나면 날짜 안내다")
    func clockMovedNoticeFollowsShownDate() throws {
        let today = LocalDate(year: 2026, month: 11, dayOfMonth: 14)!
        func shownAfterMove(_ selected: LocalDate, _ fresh: Date) -> LocalDate {
            let dates = reservationDates(now: fresh)
            let selectable = selectableAt(fresh)
            let offset = reservationDateOffsetAfterClockMove(selectedDate: selected, newDates: dates, isSelectable: selectable)
            return dates[reservationSelectableDateIndex(storedIndex: offset, dates: dates, isSelectable: selectable)]
        }

        // 13:00:30 에 열고 13:10:31 에 누름 — 오늘은 아직 고를 시각이 있다. 휠은 그 날의 가장 이른 값으로 접힌다
        let afternoon = Date(timeIntervalSince1970: 1_794_629_431) // 2026-11-14T04:10:31Z, 한국 13:10:31
        #expect(shownAfterMove(today, afternoon) == today)
        #expect(
            reservationSelectedTime(stored: LocalTime(hour: 13, minute: 20), range: reservationTimeRange(date: today, now: afternoon))
                == LocalTime(hour: 13, minute: 30)
        )
        #expect(reservationClockMovedNotice(dateChanged: shownAfterMove(today, afternoon) != today) == RESERVATION_TIME_MOVED_NOTICE)

        // 23:41 에 누름 — 오늘은 고를 시각이 없어 띠가 내일로 접힌다
        let lateNight = Date(timeIntervalSince1970: 1_794_667_260) // 2026-11-14T14:41:00Z, 한국 23:41
        let shown = shownAfterMove(today, lateNight)
        #expect(shown == LocalDate(year: 2026, month: 11, dayOfMonth: 15)!)
        #expect(reservationClockMovedNotice(dateChanged: shown != today) == RESERVATION_DATE_MOVED_NOTICE)
    }
}
