import MoyeotaDesignSystem
import MoyeotaDomain
import SwiftUI

// 예약 날짜·시각을 고르는 조각 중 **시·분 휠** — 16 도착지 확인만 쓴다.
//
// 모양(휠)은 디자인시스템(`SnapWheelPicker`·`WheelPickerFrame`)이 갖고, **무엇을 고를 수 있는가**는 이 모듈의
// 순수 함수(`reservationTimeRange`·`reservationHourOptions`·`reservationMinuteOptions`)가 정한다. 이 파일은 둘을
// 잇기만 한다 — 판정을 여기서 다시 세우지 않는다.
//
// 원본 `feature/home/ReservationPickers.kt` 에는 날짜 띠(`ReservationDateStrip`)도 있다. 띠는 17 탐색 「날짜로 찾기」도
// 함께 쓰므로 `PresentationCore/ReservationPickers.swift` 로 옮겼고(기능 모듈끼리는 import 할 수 없다 —
// `headcountLabel`·`reservationDates` 와 같은 선례), 16 만 쓰는 이 휠은 여기 남는다.

/// 시·분 **휠 두 개**(시 0~23 · 분 00/10/…/50) — 그 날의 `range` 안 값만 담는다.
///
/// - 시 휠은 `reservationHourOptions`, 분 휠은 지금 시에 대한 `reservationMinuteOptions` 다.
///   범위 밖 값은 **목록에 없다**(흐리게 남기지 않는다 — `SnapWheelPicker` 설명)
/// - 시를 굴리면 분은 지키되 범위로 접는다(`reservationTimeWithHour`) — 그래서 오늘의 첫 시로
///   굴리면 분이 가장 이른 값으로 올라갈 수 있고, 분 휠이 그 칸으로 따라 움직인다
/// - `selected` 는 호출부가 `reservationSelectedTime` 으로 접어 둔 값이고, **그 값이 곧 서버에 가는
///   값**이다(휠이 보여 주는 것과 보내는 것이 갈라지지 않게 같은 값 하나를 쓴다)
///
/// 단위 글자 「시」·「분」은 휠 **오른쪽 고정 글자**다(가운데 줄 높이) — 휠 줄마다 붙이면 굴릴 때 단위까지
/// 흘러가 숫자를 읽기 어렵다. VoiceOver 에는 휠마다 조절 가능한 값 하나로 「출발 시, 18시」처럼 읽힌다.
///
/// **24시간제 두 휠**이다(시 0~23 · 분). 오전/오후 휠을 따로 두지 않는다 — 오너가 준 참고(흔한 한국식
/// 시/분 휠)가 그 모양이고, 휠이 하나 늘면 같은 값을 고르는 데 손이 한 번 더 간다. 오전·오후는 CTA 위
/// 되읽기 줄(「오늘 오후 6:30 출발」)이 말해 준다.
struct ReservationTimeWheel: View {
    let range: ReservationTimeRange
    let selected: LocalTime
    let onSelect: (LocalTime) -> Void

    var body: some View {
        let hours = reservationHourOptions(range: range)
        let minutes = reservationMinuteOptions(range: range, hour: selected.hour)
        WheelPickerFrame {
            SnapWheelPicker(
                items: hours.map { reservationHourLabel(hour: $0) },
                selectedIndex: hours.firstIndex(of: selected.hour) ?? 0,
                onSelectedIndexChange: { index in
                    if hours.indices.contains(index) {
                        onSelect(reservationTimeWithHour(current: selected, hour: hours[index], range: range))
                    }
                },
                label: "출발 시",
                itemDescription: { index in "\(hours[index])시" }
            )
            .frame(maxWidth: .infinity)
            WheelUnit(text: "시")
            Spacer().frame(width: 8)
            SnapWheelPicker(
                items: minutes.map { reservationMinuteLabel(minute: $0) },
                selectedIndex: minutes.firstIndex(of: selected.minute) ?? 0,
                onSelectedIndexChange: { index in
                    if minutes.indices.contains(index) {
                        onSelect(reservationTimeWithMinute(current: selected, minute: minutes[index], range: range))
                    }
                },
                label: "출발 분",
                itemDescription: { index in "\(minutes[index])분" }
            )
            .frame(maxWidth: .infinity)
            WheelUnit(text: "분")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WheelUnit: View {
    let text: String

    var body: some View {
        Text(text)
            .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
            .fixedSize()
            // 휠 줄의 문장(「18시」)이 단위를 이미 말한다 — 이 글자가 따로 읽히면 「시」가 한 번 더 들린다
            .accessibilityHidden(true)
    }
}
