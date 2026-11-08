import Foundation
import MoyeotaDomain
import Testing
@testable import PresentationCore

/// 예약 방 규칙 중 **PresentationCore 로 옮겨 온 몫** — 7일 창·한국 달력 날짜·날짜와 시각 문구·나갈 수
/// 없다는 안내.
///
/// 원본 `ReservationRulesTest`(26개) 가운데 옮겨 온 함수만 보는 7개다. 나머지 19개(정원·시각 슬롯·
/// 보내는 값·실패 문구·요금 없음 안내)는 `FeatureHomeTests/ReservationRulesTest.swift` 에 있다.
///
/// 이 테스트가 잡는 것은 전부 **화면에서는 안 보이는 결함**이다: KST 자정 직후의 날짜 계산을 기기
/// 시간대로 셈하면 검색이 하루 밀리는데, 그 자리에는 「그 날 예약이 없어요」가 뜬다.
@Suite struct ReservationRulesTest {
    /// KST 2026-11-09 (월) 13:00 — 기준 시각. UTC 로는 11-09 04:00 이라 날짜가 같다.
    private let now = Date(timeIntervalSince1970: 1_794_196_800) // 2026-11-09T04:00:00Z

    // ─────────────────────────── 날짜 (한국 달력) ───────────────────────────

    @Test("날짜는 오늘부터 7일 뒤까지 여덟 개다")
    func eightDatesFromToday() throws {
        let dates = reservationDates(now: now)

        #expect(dates.count == 8)
        #expect(try dates.first == LocalDate.of(2026, 11, 9))
        #expect(try dates.last == LocalDate.of(2026, 11, 16))
        // 하루씩 **빠짐없이** 이어진다 — 중간이 비면 사용자가 고를 수 없는 날이 생긴다
        for (a, b) in zip(dates, dates.dropFirst()) {
            #expect(b == a.plusDays(1))
        }
    }

    /// ★ **이 테스트가 「하루 밀림」을 막는다.**
    ///
    /// KST 자정 직후(UTC 로는 전날 15:30)에 서버의 「오늘」은 11-09 다. 기기 시간대나 UTC 로
    /// 셈하면 11-08 이 「오늘」이 되고, 그 날짜는 서버의 「오늘~7일 뒤」를 벗어나 400
    /// `INVALID_SEARCH_DATE` 가 된다 — 화면에는 「그 날 예약이 없어요」로만 보인다.
    @Test("한국 자정을 넘기면 한국 날짜가 오늘이다 - UTC 날짜가 아니다")
    func koreanMidnightDecidesToday() throws {
        let justAfterKoreanMidnight = Date(timeIntervalSince1970: 1_794_151_800) // 2026-11-08T15:30:00Z, KST 11-09 00:30

        #expect(try reservationDates(now: justAfterKoreanMidnight).first == LocalDate.of(2026, 11, 9))
        // 같은 순간을 UTC 로 보면 11-08 이다 — 그래서 기본 시간대를 고정해 둔 것이다
        #expect(
            try reservationDates(now: justAfterKoreanMidnight, zone: LocalDate.utcZone).first
                == LocalDate.of(2026, 11, 8)
        )
    }

    /// `date` 파라미터는 **달력 날짜**다 — 순간 문자열을 자른 값이 아니다.
    @Test("검색 날짜는 yyyy-MM-dd 로 나간다")
    func searchDateApiValue() throws {
        #expect(try reservationDateApiValue(date: LocalDate.of(2026, 11, 9)) == "2026-11-09")
        // 한 자리 월·일도 두 자리로 — 서버 파서가 `yyyy-MM-dd` 를 기대한다
        #expect(try reservationDateApiValue(date: LocalDate.of(2026, 1, 2)) == "2026-01-02")
    }

    @Test("검색 가능한 날짜는 오늘부터 7일 뒤까지다")
    func searchableDates() throws {
        let today = try LocalDate.of(2026, 11, 9)

        #expect(isReservationSearchDate(date: today, now: now))
        #expect(isReservationSearchDate(date: today.plusDays(7), now: now))
        #expect(!isReservationSearchDate(date: today.plusDays(8), now: now), "7일을 넘겼다")
        #expect(!isReservationSearchDate(date: today.minusDays(1), now: now), "어제는 고를 수 없다")
    }

    // ─────────────────────────── 표기 ───────────────────────────

    @Test("날짜 칩은 오늘 내일을 이름으로 부르고 그 뒤는 요일을 붙인다")
    func dateChipLabels() throws {
        let today = try LocalDate.of(2026, 11, 9) // 월요일

        #expect(reservationDateLabel(date: today, today: today) == "오늘")
        #expect(reservationDateLabel(date: today.plusDays(1), today: today) == "내일")
        #expect(reservationDateLabel(date: today.plusDays(6), today: today) == "11월 15일 (일)")
    }

    @Test("시각 표기는 자정과 정오를 12 로 적는다")
    func timeLabelTwelve() throws {
        #expect(try reservationTimeLabel(time: LocalTime.of(0, 0)) == "오전 12:00")
        #expect(try reservationTimeLabel(time: LocalTime.of(0, 30)) == "오전 12:30")
        #expect(try reservationTimeLabel(time: LocalTime.of(12, 0)) == "오후 12:00")
        #expect(try reservationTimeLabel(time: LocalTime.of(18, 30)) == "오후 6:30")
    }

    // ─────────────────────────── 나갈 수 없다는 안내 ───────────────────────────

    /// ★ **나갈 수 없다는 사실을 두 자리가 같은 문장으로 말한다.**
    ///
    /// 예약 방은 만들어진 순간부터 확정이라 나가기가 **언제나** 409
    /// `CANNOT_LEAVE_CONFIRMED_PARTY` 다(서버 소스 실측). 실시간 방은 「그만 찾기」로 빠져나올 수
    /// 있어서, 이 말을 빼면 사용자는 **되돌릴 수 있다고 배운 동작**으로 되돌릴 수 없는 약속을 한다.
    @Test("예약은 나갈 수 없다는 사실을 만들기와 합류 양쪽에서 같은 말로 알린다")
    func commitmentNoticeSharedSentence() {
        let creating = reservationCommitmentNotice(joining: false)
        let joining = reservationCommitmentNotice(joining: true)

        #expect(creating == "예약 방은 만들면 나갈 수 없어요. 출발 시각에 안 가면 노쇼로 기록돼요")
        #expect(joining == "예약 방은 합류하면 나갈 수 없어요. 출발 시각에 안 가면 노쇼로 기록돼요")
        // 두 문장의 **뒷문장이 같다** — 같은 대가를 두 화면이 다른 무게로 말하지 않는다
        let consequence = "출발 시각에 안 가면 노쇼로 기록돼요"
        #expect(creating.hasSuffix(consequence), "\(creating)")
        #expect(joining.hasSuffix(consequence), "\(joining)")
        // 확인할 수 없는 알림을 약속하지 않는다(서버에 예약 리마인더가 있지만 앱이 발송을 모른다)
        for copy in [creating, joining] {
            #expect(!copy.contains("알림"), "\(copy)")
            #expect(!copy.contains("알려 드려요"), "\(copy)")
        }
    }
}
