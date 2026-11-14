import MoyeotaDesignSystem
import MoyeotaDomain
import SwiftUI

// 예약 날짜·시각을 고르는 조각 중 **날짜 띠** — 16 도착지 확인과 17 탐색 「날짜로 찾기」가 함께 쓴다.
//
// 모양(칸)은 디자인시스템(`WeekDateStrip`)이 갖고, **무엇을 고를 수 있는가**는 순수 함수(`reservationDateCells`)가
// 정한다. 이 파일은 둘을 잇기만 한다 — 판정을 여기서 다시 세우지 않는다.
//
// 원본 `feature/home/ReservationPickers.kt` 에는 시·분 휠(`ReservationTimeWheel`)도 있다. 휠은 16 만 쓰므로
// `FeatureHome` 에 남고, 17 이 import 하는 이 띠만 여기로 옮겼다(기능 모듈끼리는 import 할 수 없다 —
// `headcountLabel`·`reservationDates` 와 같은 선례).

/// 오늘~7일 뒤 **주간 달력 띠**. `selected` 가 목록에 없으면(자정을 넘긴 탐색 탭 등) 아무 칸도 칠하지 않는다.
///
/// - Parameters:
///   - dates: `reservationDates` 결과 그대로. 첫 원소가 오늘이다
///   - contentPadding: 띠 양 끝 여백 — 호출부 본문의 좌우 여백과 같게 줘야 첫 칸이 제목과 같은 선에서
///     시작한다(띠는 스크롤될 수 있으므로 여백을 바깥 `padding` 이 아니라 여기로 준다)
///   - isSelectable: 그 날을 고를 수 있는가 — 16 은 「그 날에 남은 시각이 있는가」, 17 은 늘 true(`reservationDateCells`)
public struct ReservationDateStrip: View {
    private let dates: [LocalDate]
    private let selected: LocalDate?
    private let onSelect: (LocalDate) -> Void
    private let contentPadding: EdgeInsets
    private let isSelectable: (LocalDate) -> Bool

    public init(
        dates: [LocalDate],
        selected: LocalDate?,
        onSelect: @escaping (LocalDate) -> Void,
        contentPadding: EdgeInsets = EdgeInsets(),
        isSelectable: @escaping (LocalDate) -> Bool = { _ in true }
    ) {
        self.dates = dates
        self.selected = selected
        self.onSelect = onSelect
        self.contentPadding = contentPadding
        self.isSelectable = isSelectable
    }

    public var body: some View {
        if let today = dates.first {
            WeekDateStrip(
                cells: reservationDateCells(dates: dates, today: today, isSelectable: isSelectable),
                selectedIndex: selected.flatMap { dates.firstIndex(of: $0) } ?? -1,
                onSelect: { index in
                    if dates.indices.contains(index) { onSelect(dates[index]) }
                },
                contentPadding: contentPadding
            )
            .frame(maxWidth: .infinity)
        }
    }
}
