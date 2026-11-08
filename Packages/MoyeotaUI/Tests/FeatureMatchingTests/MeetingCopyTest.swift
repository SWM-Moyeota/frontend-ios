@testable import FeatureMatching
import Foundation
import MoyeotaDomain
import Testing

/// 약속 흐름의 **프리셋 계산과 화면 문구** — 보내는 값과 보여 주는 값이 서로를 배신하지 않는지.
///
/// 세 가지를 못 박는다.
/// 1. **프리셋이 서버 한도를 넘지 않는다.** 서버는 약속 시간을 「지금부터 1시간 안」으로만 받고
///    벗어나면 400 `INVALID_MEETING_TIME` 이다. 프리셋을 둔 이유가 그 400 을 사용자가 만들 수 없게
///    하는 것이라, 프리셋 자체가 한도를 넘으면 **설계가 무의미해진다.**
/// 2. **표시한 시각과 보낸 시각이 같다.** 「오후 3:23 로 정할까요?」를 보고 누른 사람에게 3:23:47 이
///    확정되면 화면이 거짓을 말한 것이다.
/// 3. **모르는 값을 지어내지 않는다.** 약속 시각을 읽을 수 없으면 nil·폴백 문구이고, 틀린 시각을
///    띄우지 않는다 — 틀린 약속 시간은 사람을 엉뚱한 때에 모이게 한다.
struct MeetingCopyTest {
    private let now = instant("2026-11-06T06:13:47Z")

    /// 표기 검증은 **기기 시간대에 흔들려서는 안 된다** — KST 로 못 박는다(서버는 UTC 로 준다).
    private let kst = TimeZone(identifier: "Asia/Seoul")!

    private func member(_ id: String, isMe: Bool = false, isHost: Bool = false, arrived: Bool = false) -> User {
        User(
            id: id,
            nickname: id,
            verifiedLabel: "",
            rating: 0.0,
            rideCount: 0,
            isMe: isMe,
            isHost: isHost,
            hasArrived: arrived
        )
    }

    private func ride(members: [User], isConfirmed: Bool = true) -> Ride {
        Ride(
            id: "1",
            origin: "부산대",
            destination: "서면",
            departureLabel: "지금 출발",
            capacity: 3,
            members: members,
            farePerPerson: 0,
            totalFare: 0,
            status: .matched,
            isConfirmed: isConfirmed
        )
    }

    // ─────────────────────── 프리셋 ───────────────────────

    /// 리더가 정한 다섯 개. 늘리거나 줄이면 서버 한도·문구와 함께 다시 봐야 한다.
    @Test("프리셋은 10 20 30 45 60분이다")
    func presetMinutes() {
        #expect(MEETING_PRESET_MINUTES == [10, 20, 30, 45, 60])
    }

    /// **어느 프리셋도 서버의 「1시간 안」을 넘지 않는다.** 60분 프리셋이 경계에 걸려 있어
    /// 분 단위 내림이 돌려주는 여유(최대 59초)가 실제로 필요하다 — 기기 시계가 서버보다 앞서 있으면
    /// 그 여유가 400 을 막아 준다.
    @Test("모든 프리셋은 지금부터 1시간 안이다")
    func presetsWithinOneHour() {
        let limit = now.addingTimeInterval(3600)
        for minutes in MEETING_PRESET_MINUTES {
            let at = meetingPresetAt(now: now, minutes: minutes)
            #expect(at > now, "\(minutes)분 프리셋이 지금보다 과거다")
            #expect(at <= limit, "\(minutes)분 프리셋이 1시간을 넘는다: \(at)")
        }
    }

    /// **분 단위로 내림한다** — 표시(「오후 3:23」)와 실제 경계가 어긋나지 않게. 06:13:47 + 10분은
    /// 06:23:47 이지만 보내는 값은 06:23:00 이다.
    ///
    /// 내림해도 지난 시각이 될 수 없다(최소 프리셋이 10분이다) — 위 테스트가 그것도 함께 본다.
    @Test("프리셋은 분 단위로 내림한다")
    func presetFloorsToMinute() {
        #expect(meetingPresetAt(now: now, minutes: 10) == instant("2026-11-06T06:23:00Z"))
        #expect(meetingPresetAt(now: now, minutes: 60) == instant("2026-11-06T07:13:00Z"))
    }

    /// **보여 준 시각이 그대로 보내진다** — 칩을 누르는 순간 한 번 만들어 `ConfirmingPreset` 에 담고,
    /// 다이얼로그 제목도 서버 요청도 그 값을 쓴다.
    ///
    /// 왜 테스트가 필요한가: 예전에는 제목과 요청이 시계를 **따로** 읽었다. 분으로 내림하는 값이라
    /// 「찰나뿐」이라고 적혀 있었지만, 다이얼로그를 몇 초 들여다보면 분은 쉽게 넘어간다 —
    /// 실측(2026-11-06)에서 「오전 10:59에 만날까요?」로 묻고 **11:00 으로 확정됐다.** 확정은
    /// 되돌릴 수 없고 어기면 노쇼가 되므로, 동의한 값과 보내는 값이 갈리면 안 된다.
    ///
    /// 아래 첫 단언이 그 갈림이 **실재함**을 고정하고(13초 뒤에 다시 만들면 값이 다르다),
    /// 둘째가 캡처하면 그 갈림이 **사라짐**을 고정한다.
    @Test("약속 시각은 칩을 누른 순간 한 번 만들어 제목과 요청이 함께 쓴다")
    func presetCapturedOnce() {
        // 06:13:47 + 10분 = 06:23:xx → 내림 06:23. 13초 뒤에 다시 만들면 06:24 다 — 옛 버그의 씨앗.
        let later = now.addingTimeInterval(13)
        #expect(meetingPresetAt(now: later, minutes: 10) == instant("2026-11-06T06:24:00Z"))

        // 캡처하면 제출이 언제든 값은 하나다.
        let picked = ConfirmingPreset(minutes: 10, departureAt: meetingPresetIso(now: now, minutes: 10))

        #expect(picked.departureAt == meetingPresetIso(now: now, minutes: 10))
        #expect(
            meetingTimeLabel(departureAt: picked.departureAt)
                == meetingTimeLabel(departureAt: meetingPresetIso(now: now, minutes: 10)),
            "제목이 읽는 값과 서버로 가는 값은 같아야 한다"
        )
        // 분이 넘어간 뒤에도 들고 있던 값은 그대로다.
        #expect(picked.departureAt == meetingPresetIso(now: now, minutes: 10))
    }

    /// 서버에 나가는 값은 ISO-8601 UTC 다. 초가 0 이어도 `:00` 을 적는다.
    @Test("프리셋은 ISO-8601 문자열로 나간다")
    func presetIsoString() {
        #expect(meetingPresetIso(now: now, minutes: 10) == "2026-11-06T06:23:00Z")
        // 왕복: 보낸 문자열을 그대로 다시 읽어도 같은 시각이다(화면이 이 값을 되읽어 표기한다)
        #expect(meetingPresetAt(now: now, minutes: 30) == instant(meetingPresetIso(now: now, minutes: 30)))
    }

    /// **보낸 값과 보여 준 값이 같다.** 다이얼로그 제목이 말하는 시각은 실제로 확정되는 시각이어야
    /// 한다 — 이 왕복이 깨지면 「오후 3:23 로 정할까요?」가 거짓이 된다.
    @Test("다이얼로그가 말하는 시각이 실제로 보내는 시각이다")
    func dialogTitleMatchesSentValue() {
        let iso = meetingPresetIso(now: now, minutes: 10)

        #expect(meetingTimeLabel(departureAt: iso, zone: kst) == "오후 3:23")
        #expect(meetingConfirmTitle(timeLabel: meetingTimeLabel(departureAt: iso, zone: kst)) == "오후 3:23에 만날까요?")
    }

    // ─────────────────────── 시각 표기 ───────────────────────

    /// **문자열을 자르면 안 된다.** 서버는 UTC 로 주므로 `T` 뒤를 잘라 쓰면 KST 오후 3시가 오전 6시로
    /// 보인다 — 채팅에서 실제로 났던 결함(QA 결함-3)과 같은 함정이고, 약속 시간에서는 **사람이
    /// 9시간 전에 나가게** 만든다.
    @Test("약속 시각은 기기 시간대로 바꿔 표기한다")
    func labelUsesZone() {
        #expect(meetingTimeLabel(departureAt: "2026-11-06T06:23:00Z", zone: kst) == "오후 3:23")
        #expect(meetingTimeLabel(departureAt: "2026-11-06T06:23:00Z", zone: TimeZone(identifier: "UTC")!) == "오전 6:23")
    }

    /// 0시·12시가 12 가 되어야 한다 — `hour % 12` 만 쓰면 자정이 「오전 0:05」로 찍힌다.
    @Test("자정과 정오를 12시로 적는다")
    func midnightAndNoon() {
        #expect(meetingTimeLabel(departureAt: "2026-11-06T15:05:00Z", zone: kst) == "오전 12:05") // KST 00:05
        #expect(meetingTimeLabel(departureAt: "2026-11-06T03:05:00Z", zone: kst) == "오후 12:05") // KST 12:05
    }

    @Test("읽을 수 없는 시각은 null 이다 - 그 자리를 비운다")
    func unreadableLabelIsNil() {
        for broken in [nil, "", "   ", "오후 3시", "2026-11-06 15:00", "15:00"] as [String?] {
            #expect(meetingTimeLabel(departureAt: broken, zone: kst) == nil, "departureAt=\(String(describing: broken))")
        }
    }

    /// 헤드라인은 **시각을 지어내지 않는다** — 읽을 수 없으면 확정됐다는 사실만 말한다.
    @Test("헤드라인은 시각을 못 읽으면 사실만 말한다")
    func headlineFallback() {
        #expect(meetingHeadline(departureAt: "2026-11-06T06:23:00Z", zone: kst) == "오후 3:23에 만나요")
        #expect(meetingHeadline(departureAt: nil, zone: kst) == "약속 시간이 정해졌어요")
        #expect(meetingHeadline(departureAt: "오후 3시", zone: kst) == "약속 시간이 정해졌어요")
    }

    @Test("프리셋 확인 제목은 시각을 못 읽으면 숫자를 빼고 묻는다")
    func confirmTitleFallback() {
        #expect(meetingConfirmTitle(timeLabel: nil) == "약속 시간을 정할까요?")
    }

    // ─────────────────────── 방장 안내 ───────────────────────

    /// 이름을 쓸 수 있으면 이름으로 부르고, 못 쓰면 **조건**을 말한다 — 서버 `Party.hostId()` 가
    /// 현재 멤버 중 `min(joinedAt, memberId)` 라 「가장 먼저 참여한 분」은 사실이다
    /// (`finishHostNotice` 와 같은 근거·같은 표현).
    @Test("방장 안내는 이름을 쓸 수 있을 때만 이름으로 부른다")
    func hostNoticeName() {
        #expect(meetingHostNotice(hostNickname: "해운대") == "방장 해운대님이 약속 시간을 정해요. 정해지면 여기에 보여요")
        #expect(
            meetingHostNotice(hostNickname: nil)
                == "방장(가장 먼저 참여한 분)이 약속 시간을 정해요. 정해지면 여기에 보여요"
        )
        #expect(meetingHostNotice(hostNickname: "  ") == meetingHostNotice(hostNickname: nil))
    }

    /// 비활성 버튼을 두지 않는 자리의 안내문이므로 **다음에 무엇이 일어나는지**를 말해야 한다.
    @Test("방장 안내는 정해지면 어떻게 되는지 말한다")
    func hostNoticeSaysWhatNext() {
        for message in [meetingHostNotice(hostNickname: "해운대"), meetingHostNotice(hostNickname: nil)] {
            #expect(message.contains("정해지면"), "\(message)")
        }
    }

    // ─────────────────────── 출발 확인 문구 ───────────────────────

    /// ★ **이 테스트가 이 파일에서 가장 중요하다.** 「출발」은 되돌릴 수 없고, 그 순간 도착하지 않은
    /// 사람에게 **실제 제재**가 붙는다(약속 시간부터 노쇼 횟수 × 24시간 동안 방 생성·참여 금지).
    /// 누르는 사람은 보통 **남의 제재**를 만들게 되므로, 숫자와 대가를 말하지 않으면 그 무게를 모른다.
    @Test("출발 확인 문구는 노쇼 인원과 그 대가를 말한다")
    func departMessageSaysNoShowCost() {
        let message = departConfirmMessage(notArrivedCount: 2)

        #expect(
            message == "같이 탄 사람 모두의 방이 끝나요. 아직 도착하지 않은 2명은 노쇼로 기록돼요 — "
                + "약속 시간부터 노쇼 횟수 × 24시간 동안 방을 만들거나 참여할 수 없어요"
        )
        #expect(message.contains("2명"), "몇 명이 노쇼가 되는지 말해야 한다")
        #expect(message.contains("노쇼"), "노쇼라는 말이 있어야 한다")
        #expect(message.contains("24시간"), "제재 기간을 말해야 한다")
        #expect(message.contains("모두의 방이 끝나요"), "모두의 방이 끝난다는 것을 말해야 한다")
    }

    /// **아무도 기록되지 않으면 제재를 말하지 않는다.** 겁만 주고, 정말 노쇼가 생길 때 같은 문구가
    /// 무게를 잃는다.
    @Test("모두 도착했으면 노쇼를 말하지 않는다")
    func allArrivedNoNoShow() {
        let message = departConfirmMessage(notArrivedCount: 0)

        #expect(message == "모두 도착했어요. 출발하면 같이 탄 사람 모두의 방이 끝나요")
        #expect(!message.contains("노쇼"), "없는 제재를 말한다: \(message)")
        #expect(!message.contains("24시간"), "\(message)")
    }

    /// 음수는 올 수 없지만(목록 개수다) 와도 「0명 노쇼」를 그리지 않는다.
    @Test("미도착 인원이 음수여도 노쇼를 말하지 않는다")
    func negativeCountNoNoShow() {
        #expect(departConfirmMessage(notArrivedCount: -1) == departConfirmMessage(notArrivedCount: 0))
    }

    // ─────────────────────── 도착 집계 표기 ───────────────────────

    @Test("도착 숫자는 확정된 방에서만 뜬다")
    func arrivalCountOnlyWhenConfirmed() {
        let members = [
            member("me", isMe: true, arrived: true),
            member("u2", isHost: true),
            member("u3"),
        ]

        #expect(arrivalCountLabel(ride: ride(members: members)) == "도착 1/3")
        #expect(arrivalCountLabel(ride: ride(members: members, isConfirmed: false)) == nil)
    }

    /// 멤버가 없는 응답(목록·생성 응답으로 만든 Ride)에서는 셀 것이 없다 — 「도착 0/0」을 그리지 않는다.
    @Test("멤버가 없으면 도착 숫자를 그리지 않는다")
    func noMembersNoArrivalCount() {
        #expect(arrivalCountLabel(ride: ride(members: [])) == nil)
    }
}

/// 기대값을 만드는 자리라 시험 대상 해석기(`toMeetingInstantOrNull`)를 쓰지 않는다. 깨진 고정값은
/// `distantPast` 로 떨어져 어느 단언에서든 바로 드러난다.
private func instant(_ text: String) -> Date {
    (try? Date(text, strategy: .iso8601)) ?? .distantPast
}
