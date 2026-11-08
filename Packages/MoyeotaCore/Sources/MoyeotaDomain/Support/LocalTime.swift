import Foundation

/// `java.time.LocalTime` 의 자리 — 시간대 없는 벽시계 시각(시·분·초).
///
/// 원본이 이 타입을 쓰는 자리는 예약 화면의 시각 칩·카드 문구다(`LocalTime.of(h, m)`,
/// `instant.atZone(zone).toLocalTime()`, `date.atTime(time)`). 그 자리들은 분 단위로만 읽으므로
/// **나노초는 들지 않는다** — 순간을 내릴 때(`ofInstant`) 초 아래는 버린다.
///
/// 범위 밖 값은 이 타입의 값이 될 수 없다(`LocalDate` 와 같은 성질). 24:00 도 거절한다 — Java 와 같다.
public struct LocalTime: Hashable, Comparable, Sendable {
    public let hour: Int
    public let minute: Int
    public let second: Int

    private static let secondsPerDay = 86_400

    private init(unchecked hour: Int, _ minute: Int, _ second: Int) {
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    /// 범위 밖이면 nil. `LocalDate(year:month:dayOfMonth:)` 와 같은 자리다.
    public init?(hour: Int, minute: Int, second: Int = 0) {
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        self.init(unchecked: hour, minute, second)
    }

    /// Java `LocalTime.of(hour, minute[, second])`. 범위 밖이면 `DateTimeException` 을 던진다.
    public static func of(_ hour: Int, _ minute: Int, _ second: Int = 0) throws -> LocalTime {
        guard (0...23).contains(hour) else {
            throw DateTimeException("Invalid value for HourOfDay (valid values 0 - 23): \(hour)")
        }
        guard (0...59).contains(minute) else {
            throw DateTimeException("Invalid value for MinuteOfHour (valid values 0 - 59): \(minute)")
        }
        guard (0...59).contains(second) else {
            throw DateTimeException("Invalid value for SecondOfMinute (valid values 0 - 59): \(second)")
        }
        return LocalTime(unchecked: hour, minute, second)
    }

    /// Java `LocalTime.ofInstant` / 원본의 `instant.atZone(zone).toLocalTime()`.
    /// `LocalDate.ofInstant` 와 같은 셈이고, 그 날의 몇 초째인지만 남긴다.
    public static func ofInstant(_ instant: Date, _ zone: TimeZone) -> LocalTime {
        let seconds = Int(instant.timeIntervalSince1970.rounded(.down)) + zone.secondsFromGMT(for: instant)
        let secondOfDay = ((seconds % secondsPerDay) + secondsPerDay) % secondsPerDay
        return LocalTime(unchecked: secondOfDay / 3_600, (secondOfDay / 60) % 60, secondOfDay % 60)
    }

    /// Java `toSecondOfDay` — 자정으로부터의 초.
    public func toSecondOfDay() -> Int {
        hour * 3_600 + minute * 60 + second
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        lhs.toSecondOfDay() < rhs.toSecondOfDay()
    }
}

/// `java.time.DayOfWeek` 의 자리. raw value 가 Java `getValue()` 와 같다(월요일 1 ~ 일요일 7).
///
/// 요일 **문구**는 여기 두지 않는다 — 원본도 로케일 표기(`getDisplayName`)에 맡기지 않고 화면이 직접
/// 한 글자 표를 든다(기기 로케일이 영어면 「Sun」이 섞인다).
public enum DayOfWeek: Int, CaseIterable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday
}
