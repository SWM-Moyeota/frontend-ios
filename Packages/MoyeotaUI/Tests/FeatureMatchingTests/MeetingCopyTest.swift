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
            status: .confirmed,
            isConfirmed: isConfirmed
        )
    }

    // ─────────────────────── 약속 시간 휠 ───────────────────────

    /// 휠에는 **서버가 받는 시각만** 있다 — 지금부터 10분 뒤(올림) ~ 1시간 뒤(내림), 5분 정각.
    /// 06:13:47 이면 06:23:47 을 올린 **06:25** 부터 07:13:47 을 내린 **07:10** 까지 열 칸이다.
    @Test("휠은 10분 뒤부터 1시간 뒤까지 5분 정각만 담는다")
    func timeOptionsRange() {
        let options = meetingTimeOptions(now: now)

        #expect(options.first == instant("2026-11-06T06:25:00Z"))
        #expect(options.last == instant("2026-11-06T07:10:00Z"))
        #expect(options.count == 10)
        for at in options {
            #expect(Int(at.timeIntervalSince1970) % 300 == 0, "5분 정각이 아니다: \(at)")
            #expect(at >= now.addingTimeInterval(600), "10분이 안 된다: \(at)")
            #expect(at <= now.addingTimeInterval(3600), "1시간을 넘는다: \(at)")
        }
        #expect(options == options.sorted())
    }

    /// 10분 뒤가 마침 5분 정각이면 그 칸부터다 — 올림이 한 칸을 더 건너뛰지 않는다.
    @Test("정각에 맞으면 그 칸부터 시작한다")
    func timeOptionsExactBoundary() {
        let options = meetingTimeOptions(now: instant("2026-11-06T06:15:00Z"))

        #expect(options.first == instant("2026-11-06T06:25:00Z"))
        #expect(options.last == instant("2026-11-06T07:15:00Z"))
    }

    /// 자정을 넘는 범위도 시각 순서 그대로다 — 시·분 휠이었다면 고를 수 없는 조합이 생기는 자리다.
    @Test("자정을 넘어도 이른 순서로 이어진다")
    func timeOptionsAcrossMidnight() {
        // KST 23:40
        let labels = meetingTimeOptions(now: instant("2026-11-06T14:40:00Z"))
            .map { meetingTimeLabel(departureAt: meetingTimeIso($0), zone: kst) }

        #expect(labels.first == "오후 11:50")
        #expect(labels.last == "오전 12:40")
        #expect(labels.contains("오전 12:00"))
    }

    /// 시간이 흘러 고른 시각이 목록에서 빠지면 가장 이른 시각을 가리킨다 — 빠진 값으로 확정하지 않는다.
    @Test("고른 시각이 목록에서 빠지면 가장 이른 시각으로 옮긴다")
    func selectedTimeFallsBack() {
        let options = meetingTimeOptions(now: now)

        #expect(meetingSelectedTime(options: options, picked: nil) == options.first)
        #expect(meetingSelectedTime(options: options, picked: options[3]) == options[3])
        #expect(meetingSelectedTime(options: options, picked: instant("2026-11-06T06:20:00Z")) == options.first)
    }

    /// **버튼이 말하는 시각이 그대로 보내진다** — 휠이 가리키는 값 하나를 버튼 글자와 요청이 함께 쓴다
    /// (실측 2026-11-06: 제목과 요청이 시계를 따로 읽어 「오전 10:59에 만날까요?」로 묻고 11:00 으로 확정됐다).
    @Test("버튼이 말하는 시각이 실제로 보내는 시각이다")
    func buttonReadsBackSentTime() throws {
        let picked = try #require(meetingTimeOptions(now: now).first)
        let iso = meetingTimeIso(picked)

        #expect(iso == "2026-11-06T06:25:00Z")
        #expect(meetingTimeLabel(departureAt: iso, zone: kst) == "오후 3:25")
        #expect(meetingConfirmButtonText(timeLabel: meetingTimeLabel(departureAt: iso, zone: kst)) == "오후 3:25에 만나기")
    }

    /// 휠 아래 되읽기는 남은 분을 **올림**한다 — 11분 13초 남았으면 「12분 뒤」.
    @Test("휠 아래에 지금부터 몇 분 뒤인지 적는다")
    func minutesFromNowLabel() {
        #expect(meetingMinutesFromNowLabel(now: now, at: instant("2026-11-06T06:25:00Z")) == "지금부터 12분 뒤")
        #expect(meetingMinutesFromNowLabel(now: now, at: instant("2026-11-06T07:10:00Z")) == "지금부터 57분 뒤")
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

    @Test("확정 버튼은 시각을 못 읽으면 숫자를 빼고 적는다")
    func confirmButtonFallback() {
        #expect(meetingConfirmButtonText(timeLabel: nil) == "이 시간으로 정하기")
    }

    // ─────────────────────── 방장 안내 ───────────────────────

    /// 이름을 쓸 수 있으면 이름으로 부르고, 못 쓰면 **조건**을 말한다 — 서버 `Party.hostId()` 가
    /// 현재 멤버 중 `min(joinedAt, memberId)` 라 「가장 먼저 참여한 분」은 사실이다
    /// (`departHostNotice` 와 같은 근거·같은 표현 — 그쪽은 옛 `finishHostNotice` 를 옮겨 온 것이다).
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

    /// 🔴 ★ **이 테스트가 이 파일에서 가장 중요하고, 뜻이 바뀐 자리다.**
    ///
    /// 옛 문구: 「… 아직 도착하지 않은 2명은 **노쇼로 기록돼요** — 약속 시간부터 노쇼 횟수 × 24시간
    /// 동안 방·예약을 만들거나 참여할 수 없어요」. **서버가 노쇼 기능을 통째로 지웠다**
    /// (`b16551b7`, V37 이 테이블까지 떨어뜨린다) — 그 제재는 **존재하지 않는 일**이라, 남겨 두면
    /// 겁을 주고 그 겁이 거짓이다.
    ///
    /// **대가가 사라진 건 아니다.** 서버는 「도착을 누른 멤버 = 탑승자」로 세므로(`Party.riderIds`)
    /// 미도착자는 **탑승 기록 · 탑승 횟수 · 택시비 정산 대상**에서 함께 빠진다. 같이 탔는데도 정산
    /// 장부에 이름이 없는 것이 지금의 대가다. 그래서 **겁주지 않고 사실만** 적는다 — 처벌조
    /// (「제외됩니다」)가 아니라 「빠져요」로.
    ///
    /// 「출발」이 되돌릴 수 없고 누르는 사람이 보통 **남의 손해**를 만든다는 것은 그대로다. 그래서
    /// 숫자는 여전히 필수다.
    @Test("출발 확인 문구는 빠지는 인원과 무엇에서 빠지는지를 말한다")
    func departMessageSaysWhatIsLost() {
        let message = departConfirmMessage(notArrivedCount: 2)

        #expect(message == "같이 탄 사람 모두의 방이 끝나요. 아직 도착하지 않은 2명은 탑승 기록과 택시비 정산에서 빠져요")
        #expect(message.contains("2명"), "몇 명이 빠지는지 말해야 한다")
        #expect(message.contains("탑승 기록"), "탑승 기록에서 빠진다는 것을 말해야 한다")
        #expect(message.contains("정산"), "정산에서 빠지는 것이 실제 대가다")
        #expect(message.contains("모두의 방이 끝나요"), "모두의 방이 끝난다는 것을 말해야 한다")
        // 🔴 사라진 제재로 겁을 주지 않는다
        #expect(!message.contains("노쇼"), "서버에 없는 제재를 말한다: \(message)")
        #expect(!message.contains("24시간"), "서버에 없는 제재 기간을 말한다: \(message)")
    }

    /// **아무도 빠지지 않으면 그 문장을 말하지 않는다.** 겁만 주고, 정말 미도착자가 있을 때 같은
    /// 문구가 무게를 잃는다.
    @Test("모두 도착했으면 빠진다는 말을 하지 않는다")
    func allArrivedSaysNothingLost() {
        let message = departConfirmMessage(notArrivedCount: 0)

        #expect(message == "모두 도착했어요. 출발하면 같이 탄 사람 모두의 방이 끝나요")
        #expect(!message.contains("빠져요"), "아무도 빠지지 않는데 빠진다고 말한다: \(message)")
        #expect(!message.contains("노쇼"), "\(message)")
    }

    /// 음수는 올 수 없지만(목록 개수다) 와도 「0명이 빠진다」를 그리지 않는다.
    @Test("미도착 인원이 음수여도 빠진다는 말을 하지 않는다")
    func negativeCountSaysNothingLost() {
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
