import Foundation
import Testing
@testable import MoyeotaDomain

@Suite struct LocalDateTest {
    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
        try LocalDate.of(year, month, day)
    }

    @Test("없는 날짜는 값이 되지 못한다")
    func invalidDatesThrow() {
        for (year, month, day) in [(2025, 2, 30), (2023, 2, 29), (2024, 13, 1), (2024, 0, 1), (2024, 1, 0), (2024, 4, 31), (1900, 2, 29)] {
            #expect(throws: DateTimeException.self) { try LocalDate.of(year, month, day) }
            #expect(LocalDate(year: year, month: month, dayOfMonth: day) == nil)
        }
        #expect(LocalDate(year: 2024, month: 2, dayOfMonth: 29) != nil)
        #expect(LocalDate(year: 2000, month: 2, dayOfMonth: 29) != nil)
    }

    @Test("parse 는 ISO_LOCAL_DATE 만 받고 toString 과 왕복한다")
    func parseRoundTrips() throws {
        for text in ["2000-01-01", "1999-12-31", "2024-02-29", "0000-01-01", "-0001-12-31", "+12345-06-07"] {
            #expect(try LocalDate.parse(text).toString() == text)
        }
        for text in ["", "2025-02-30", "2000-1-1", "20000101", "2000-01-01 ", " 2000-01-01", "+2000-01-01", "12345-01-01", "-0000-01-01", "2000-13-01", "２０００-01-01", "2000/01/01"] {
            #expect(throws: DateTimeException.self, "\(text)") { try LocalDate.parse(text) }
        }
    }

    @Test("BASIC_ISO_DATE 와 ISO_LOCAL_DATE 형식")
    func formats() throws {
        let value = try date(2012, 10, 3)
        #expect(value.format(.basicIsoDate) == "20121003")
        #expect(value.format(.isoLocalDate) == "2012-10-03")
        #expect("\(value)" == "2012-10-03")
    }

    @Test("plusYears 는 윤일을 2월 28일로 맞춘다")
    func plusYearsClampsLeapDay() throws {
        #expect(try date(2008, 2, 29).plusYears(14) == date(2022, 2, 28))
        #expect(try date(2008, 2, 29).plusYears(16) == date(2024, 2, 29))
        #expect(try date(2024, 2, 29).minusYears(1) == date(2023, 2, 28))
    }

    @Test("plusMonths 는 말일로 맞추고 해를 넘긴다")
    func plusMonthsClamps() throws {
        #expect(try date(2023, 1, 31).plusMonths(1) == date(2023, 2, 28))
        #expect(try date(2024, 1, 31).plusMonths(1) == date(2024, 2, 29))
        #expect(try date(2024, 11, 15).plusMonths(3) == date(2025, 2, 15))
        #expect(try date(2024, 1, 15).minusMonths(1) == date(2023, 12, 15))
        #expect(try date(2024, 3, 31).minusMonths(1) == date(2024, 2, 29))
        #expect(try date(2024, 1, 15).minusMonths(25) == date(2021, 12, 15))
    }

    @Test("plusDays 는 달과 해의 경계를 넘는다")
    func plusDaysCrossesBoundaries() throws {
        #expect(try date(2023, 12, 31).plusDays(1) == date(2024, 1, 1))
        #expect(try date(2024, 2, 28).plusDays(1) == date(2024, 2, 29))
        #expect(try date(2024, 3, 1).minusDays(1) == date(2024, 2, 29))
        #expect(try date(2023, 3, 1).minusDays(1) == date(2023, 2, 28))
        #expect(try date(2024, 1, 1).plusWeeks(1) == date(2024, 1, 8))
        #expect(try date(2024, 1, 8).minusWeeks(1) == date(2024, 1, 1))
    }

    @Test("에포크 일수는 Java 와 같다")
    func epochDays() throws {
        #expect(try date(1970, 1, 1).toEpochDay() == 0)
        #expect(try date(1969, 12, 31).toEpochDay() == -1)
        #expect(try date(2000, 3, 1).toEpochDay() == 11_017)
        #expect(try date(1582, 10, 10).toEpochDay() == -141_432) // 역산 그레고리력 — 율리우스력 전환 없음
        #expect(try LocalDate.ofEpochDay(19_782) == date(2024, 2, 29))
        for day in stride(from: -800_000, through: 800_000, by: 997) {
            #expect(LocalDate.ofEpochDay(day).toEpochDay() == day)
        }
    }

    @Test("비교")
    func comparison() throws {
        let earlier = try date(2012, 12, 31)
        let later = try date(2013, 1, 1)
        #expect(earlier < later)
        #expect(earlier.isBefore(later))
        #expect(later.isAfter(earlier))
        #expect(!later.isBefore(later))
        #expect(later.isEqual(later))
        #expect(Set([earlier, earlier, later]).count == 2)
    }

    @Test("시각을 시간대의 날짜로 내린다")
    func ofInstantUsesZone() throws {
        // 2026-10-13T15:30:00Z — 서울은 이미 14일이다.
        let instant = Date(timeIntervalSince1970: 1_791_905_400)
        #expect(try LocalDate.ofInstant(instant, LocalDate.utcZone) == date(2026, 10, 13))
        #expect(try LocalDate.ofInstant(instant, LocalDate.seoulZone) == date(2026, 10, 14))
        // 음의 에포크에서도 내림이다.
        #expect(try LocalDate.ofInstant(Date(timeIntervalSince1970: -1), LocalDate.utcZone) == date(1969, 12, 31))
    }

    /// 원본 `java.time.LocalDate.now()` 는 기기 시간대를 쓴다. 생년월일·만 나이 판정의 「오늘」이 이 값이다.
    ///
    /// 두 시간대를 쓰는 이유: 서울(+9) 기준 20시 전이면 파고파고(-11)가 전날이고, 19시 뒤면 키리티마티(+14)가
    /// 다음 날이라 **언제 돌려도 둘 중 하나는 서울과 날짜가 다르다.** 기기가 서울이어도 서울 고정을 잡아낸다.
    @Test("now 의 기본값은 기기 시간대의 날짜다")
    func nowDefaultsToDeviceZone() throws {
        let saved = getenv("TZ").map { String(cString: $0) }
        defer {
            if let saved { setenv("TZ", saved, 1) } else { unsetenv("TZ") }
            tzset()
            NSTimeZone.resetSystemTimeZone()
        }
        for identifier in ["Pacific/Pago_Pago", "Pacific/Kiritimati"] {
            setenv("TZ", identifier, 1)
            tzset()
            NSTimeZone.resetSystemTimeZone()
            let zone = try #require(TimeZone(identifier: identifier))

            let before = Date()
            let today = LocalDate.now()
            let after = Date()

            #expect([LocalDate.ofInstant(before, zone), LocalDate.ofInstant(after, zone)].contains(today), "\(identifier)")
        }
    }

    @Test("atStartOfDay 는 그 시간대의 자정이다")
    func atStartOfDay() throws {
        #expect(try date(2000, 1, 1).atStartOfDay(LocalDate.utcZone).timeIntervalSince1970 == 946_684_800)
        #expect(try date(2000, 1, 1).atStartOfDay(LocalDate.seoulZone).timeIntervalSince1970 == 946_684_800 - 9 * 3600)
    }

    // 아래는 원본에 대응 테스트가 없는 iOS 쪽 자리(`java.time` 의 `getDayOfWeek`·`atTime`·`LocalTime`)다.
    // 예약 날짜 칩의 요일과 서버로 보내는 출발 시각이 이 셈에 기댄다.

    /// 1970-01-01 이 목요일이라는 기준점에서 셈한다 — 에포크 앞쪽(음수 일수)도 같은 식이어야 한다.
    @Test("요일은 Java getDayOfWeek 와 같다")
    func dayOfWeek() throws {
        #expect(try date(2026, 11, 9).dayOfWeek == .monday)
        #expect(try date(2026, 11, 15).dayOfWeek == .sunday)
        #expect(try date(1970, 1, 1).dayOfWeek == .thursday)
        #expect(try date(1969, 12, 31).dayOfWeek == .wednesday)
        #expect(DayOfWeek.monday.rawValue == 1)
        #expect(DayOfWeek.sunday.rawValue == 7)
    }

    /// 한국 달력의 날짜 + 벽시계 시각 → 서버가 받는 순간. KST 18:30 은 UTC 09:30 이다.
    @Test("atTime 은 그 시간대의 벽시계 시각을 순간으로 올린다")
    func atTime() throws {
        let evening = try LocalTime.of(18, 30)

        #expect(try date(2026, 11, 9).atTime(evening, LocalDate.seoulZone).timeIntervalSince1970 == 1_794_216_600)
        #expect(try date(2026, 11, 9).atTime(evening, LocalDate.utcZone).timeIntervalSince1970 == 1_794_216_600 + 9 * 3600)
        // 자정은 atStartOfDay 와 같다.
        #expect(try date(2000, 1, 1).atTime(LocalTime.of(0, 0), LocalDate.seoulZone) == date(2000, 1, 1).atStartOfDay(LocalDate.seoulZone))
    }

    /// 순간을 시간대의 벽시계 시각으로 내린다 — 같은 순간이 서울과 UTC 에서 다른 시각이다.
    @Test("LocalTime ofInstant 는 시간대의 벽시계 시각이다")
    func localTimeOfInstant() throws {
        // 2026-11-08T23:45:30Z
        let instant = Date(timeIntervalSince1970: 1_794_181_530)

        #expect(LocalTime.ofInstant(instant, LocalDate.seoulZone) == (try LocalTime.of(8, 45, 30)))
        #expect(LocalTime.ofInstant(instant, LocalDate.utcZone) == (try LocalTime.of(23, 45, 30)))
        // 초 아래는 버린다.
        #expect(LocalTime.ofInstant(instant.addingTimeInterval(0.9), LocalDate.utcZone) == (try LocalTime.of(23, 45, 30)))
    }

    /// Java 처럼 범위 밖은 값이 되지 못한다 — 24:00 도 아니다.
    @Test("LocalTime of 는 범위 밖 시각을 던진다")
    func localTimeOfThrows() throws {
        #expect(throws: DateTimeException.self) { try LocalTime.of(24, 0) }
        #expect(throws: DateTimeException.self) { try LocalTime.of(12, 60) }
        #expect(throws: DateTimeException.self) { try LocalTime.of(-1, 0) }
        #expect(LocalTime(hour: 24, minute: 0) == nil)
        #expect(try LocalTime.of(23, 59, 59).toSecondOfDay() == 86_399)
        #expect(try LocalTime.of(9, 30) < LocalTime.of(18, 0))
    }
}
