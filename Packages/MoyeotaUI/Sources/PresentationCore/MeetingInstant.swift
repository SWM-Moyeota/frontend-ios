import Foundation
import MoyeotaDomain

// ─── 서버 시각 ───────────────────────────────────────────────────────────────
//
// 서버 ISO-8601(Instant 또는 오프셋 표기) → `Date`. 그 외 형식은 nil.
//
// 21 약속(FeatureMatching `MeetingFlow.swift`)과 17·20 예약(FeatureExplore)이 **함께 쓰는 한 사본**이다.
// 원본은 `feature/matching/MeetingFlow.kt` 에 두고 예약 탐색(`ReservationFinder.kt`)이 일부러 그걸
// import 한다 — 둘 다 같은 서버 필드(`Ride.departureAt`)를 읽으므로 사본을 하나 더 만들면 한쪽만
// 형식 변화를 따라간다. 기능 모듈끼리는 서로 import 할 수 없어 PresentationCore 로 옮겼다
// (`headcountLabel` 과 같은 선례).
//
// `RideHistoryDisplay`·`ChatRoute` 의 해석기는 원본처럼 **따로 둔다** — 그 둘은 서로를 모르는 채로
// 각자 들고 있고, 받는 꼴이 같아야 하므로 같은 구현을 옮겼다. 그래서 문자열 단계의 해석기
// (`String.toInstantOrNull`)는 이 파일 밖으로 내놓지 않는다: 공개하면 그 두 모듈의 같은 이름 사본과
// 부딪친다. 밖에서 부르는 입구는 `toMeetingInstantOrNull` 하나다.
//
// 여기서는 `Date` 로 돌려준다. 두 사본이 별도 시각 타입을 둔 이유(`Date` 는 초를 `Double` 로 들고 있어
// 소수 초가 어긋날 수 있다)는 이 파일에 해당하지 않는다 — 약속·예약 판정의 경계는 분 단위이고, 정수
// 초는 `Double` 로 정확히 담긴다.

extension Optional where Wrapped == String {
    /// null·빈 값·알 수 없는 형식을 **한 자리에서** nil 로 접는다 — 판정마다 같은 방어를 쓰지 않도록.
    public func toMeetingInstantOrNull() -> Date? {
        guard let text = self, !text.isBlank else { return nil }
        return text.toInstantOrNull()
    }
}

private func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let quotient = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? quotient - 1 : quotient
}

/// 1970-01-01 부터의 일 수 ← 달력 날짜 (Howard Hinnant `days_from_civil`).
private func daysFromCivil(year: Int64, month: Int, day: Int) -> Int64 {
    let y = month <= 2 ? year - 1 : year
    let era = floorDiv(y, 400)
    let yearOfEra = y - era * 400
    let shiftedMonth = Int64(month > 2 ? month - 3 : month + 9)
    let dayOfYear = (153 * shiftedMonth + 2) / 5 + Int64(day) - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
}

private func daysInMonth(year: Int64, month: Int) -> Int {
    switch month {
    case 2:
        let leap = (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0)
        return leap ? 29 : 28
    case 4, 6, 9, 11:
        return 30
    default:
        return 31
    }
}

/// `Instant.parse` 실패 시 `OffsetDateTime.parse` 로 넘어가는 원본의 두 단계를 한 번에 받는 해석기.
/// `ISO8601DateFormatter` 는 소수 초 유무를 옵션으로 갈라야 하고 자릿수·소문자·오프셋 초 처리도 달라 쓰지 않는다.
///
/// 받는 꼴(`RideHistoryDisplay.swift` 의 해석기와 같다 — JDK 결과와의 대조는 `RideHistoryBehaviorTest` 에 있다):
/// `연-월-일 T 시:분[:초[.소수 0~9자리]] (Z | ±시[:분[:초]])`, `T`·`Z` 는 소문자도 된다.
/// 연도는 부호 없이 4자리, `+` 면 5자리 이상, `-` 면 4자리 이상이다. `24:00:00`(다음 날 0시)과 `23:59:60`(윤초)을 받는다.
private struct InstantScanner {
    private let bytes: [UInt8]
    private var index = 0

    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    private var isAtEnd: Bool { index >= bytes.count }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard !isAtEnd, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func consumeIgnoringCase(_ upper: UInt8) -> Bool {
        consume(upper) || consume(upper + 32)
    }

    /// 숫자 정확히 `count` 자리.
    private mutating func digits(_ count: Int) -> Int? {
        guard index + count <= bytes.count else { return nil }
        var value = 0
        for offset in 0..<count {
            let byte = bytes[index + offset]
            guard byte >= 0x30, byte <= 0x39 else { return nil }
            value = value * 10 + Int(byte - 0x30)
        }
        index += count
        return value
    }

    private mutating func digitRun() -> [UInt8] {
        let start = index
        while !isAtEnd, bytes[index] >= 0x30, bytes[index] <= 0x39 {
            index += 1
        }
        return Array(bytes[start..<index])
    }

    private mutating func year() -> Int64? {
        let negative = consume(0x2D)
        let positive = !negative && consume(0x2B)
        let run = digitRun()
        if positive {
            guard run.count >= 5 else { return nil }
        } else if negative {
            guard run.count >= 4 else { return nil }
        } else {
            guard run.count == 4 else { return nil }
        }
        // java.time 의 연도 범위(±999,999,999)
        guard run.count <= 9 else { return nil }
        let value = run.reduce(Int64(0)) { $0 * 10 + Int64($1 - 0x30) }
        return negative ? -value : value
    }

    /// `Z` 또는 `±시[:분[:초]]` → 초. 범위는 `ZoneOffset` 과 같이 ±18:00 이다.
    private mutating func offsetSeconds() -> Int? {
        if consumeIgnoringCase(0x5A) { return 0 }
        let sign: Int
        if consume(0x2B) {
            sign = 1
        } else if consume(0x2D) {
            sign = -1
        } else {
            return nil
        }
        guard let hours = digits(2) else { return nil }
        var minutes = 0
        var seconds = 0
        if consume(0x3A) {
            guard let parsedMinutes = digits(2), parsedMinutes <= 59 else { return nil }
            minutes = parsedMinutes
            if consume(0x3A) {
                guard let parsedSeconds = digits(2), parsedSeconds <= 59 else { return nil }
                seconds = parsedSeconds
            }
        }
        let total = hours * 3_600 + minutes * 60 + seconds
        guard total <= 18 * 3_600 else { return nil }
        return sign * total
    }

    mutating func parse() -> Date? {
        guard let year = year(), consume(0x2D),
              let month = digits(2), (1...12).contains(month), consume(0x2D),
              let day = digits(2), day >= 1, day <= daysInMonth(year: year, month: month),
              consumeIgnoringCase(0x54),
              let hour = digits(2), consume(0x3A),
              let minute = digits(2)
        else { return nil }

        var second = 0
        var nano = 0
        var hasSeconds = false
        if consume(0x3A) {
            guard let parsedSecond = digits(2) else { return nil }
            second = parsedSecond
            hasSeconds = true
            if consume(0x2E) {
                let fraction = digitRun()
                guard fraction.count <= 9 else { return nil }
                nano = fraction.reduce(0) { $0 * 10 + Int($1 - 0x30) }
                for _ in fraction.count..<9 {
                    nano *= 10
                }
            }
        }
        guard let offset = offsetSeconds(), isAtEnd else { return nil }

        var dayCarry: Int64 = 0
        var resolvedHour = hour
        var resolvedSecond = second
        if hour == 24, minute == 0, second == 0, nano == 0, hasSeconds {
            // `Instant.parse` 는 하루의 끝 24:00:00 을 다음 날 0시로 받는다.
            resolvedHour = 0
            dayCarry = 1
        } else if hour == 23, minute == 59, second == 60 {
            // 윤초 — `Instant.parse` 는 59초로 접는다.
            resolvedSecond = 59
        } else {
            guard hour <= 23, minute <= 59, second <= 59 else { return nil }
        }

        let days = daysFromCivil(year: year, month: month, day: day) + dayCarry
        let secondOfDay = Int64(resolvedHour * 3_600 + minute * 60 + resolvedSecond)
        let epochSecond = days * 86_400 + secondOfDay - Int64(offset)
        return Date(timeIntervalSince1970: TimeInterval(epochSecond) + TimeInterval(nano) / 1_000_000_000)
    }
}

private extension String {
    /// 서버 ISO-8601(Instant 또는 오프셋 표기) → `Date`. 그 외 형식은 nil.
    func toInstantOrNull() -> Date? {
        var scanner = InstantScanner(self)
        return scanner.parse()
    }
}
