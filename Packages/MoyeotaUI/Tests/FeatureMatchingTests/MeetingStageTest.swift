@testable import FeatureMatching
import Foundation
import MoyeotaDomain
import Testing

/// 21 매칭 대기의 **약속 단계 판정** — 리더가 정한 화면 상태표를 값으로 못 박는다(`meetingStage`).
///
/// ### 왜 이 테스트가 필요한가 ★
/// 이 판정은 **시계에 달려 있고, 틀려도 스크린샷에 보이지 않는다.** 도착 버튼이 약속 10분 전에 떠야
/// 하는데 9분 전에 뜨는 화면과 올바른 화면은 눈으로 구분할 수 없고, 그 차이는 **서버 409
/// `ARRIVAL_NOT_OPEN`** 으로만 드러난다 — 사용자가 버튼을 눌러 실패한 뒤에야 안다. 그래서 경계
/// 하나하나를 값으로 고정한다.
///
/// 경계 둘이 이 파일의 주제다.
/// | 경계 | 규칙 | 서버 쪽 근거 |
/// |---|---|---|
/// | 도착 창 | `now ≥ 약속 − 10분` (정확히 10분 전이 **참**) | 「약속 시간 10분 전부터」 · 409 `ARRIVAL_NOT_OPEN` |
/// | 출발 | `now ≥ 약속` (정각이 **참**) | 「약속 시간 뒤에만」 · 409 `MEETING_NOT_STARTED` |
///
/// `now` 는 전부 **인자로 넣는다** — 판정 함수가 제 안에서 시계를 읽으면 이 테스트를 쓸 수 없다.
struct MeetingStageTest {
    /// 기준 시각. 약속 시각을 이 값에서 분으로 옮겨 각 경계를 만든다.
    private let now = instant("2026-11-06T06:00:00Z")

    private func at(_ minutesFromNow: Int) -> String {
        iso(now.addingTimeInterval(TimeInterval(minutesFromNow * 60)))
    }

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

    /// 나(비방장) + 동승자 둘 — 정원 3인이 찬 방의 기본 구성.
    private func members(meArrived: Bool = false, otherArrived: Bool = false) -> [User] {
        [
            member("me", isMe: true, arrived: meArrived),
            member("u2", isHost: true, arrived: otherArrived),
            member("u3", arrived: otherArrived),
        ]
    }

    private func ride(
        status: RideStatus = .confirmed,
        members: [User]? = nil,
        isConfirmed: Bool = false,
        departureAt: String? = nil,
        roomType: RoomType = .realtime,
        capacity: Int = 3
    ) -> Ride {
        Ride(
            id: "1",
            origin: "부산대",
            destination: "서면",
            departureLabel: "지금 출발",
            capacity: capacity,
            members: members ?? self.members(),
            farePerPerson: 0,
            totalFare: 0,
            status: status,
            departureAt: departureAt,
            isConfirmed: isConfirmed,
            roomType: roomType
        )
    }

    /// 내가 방장인 목록 — 확정 권한 분기를 보려면 내 줄에 host 가 서 있어야 한다.
    private func hostedByMe(meArrived: Bool = false) -> [User] {
        [
            member("me", isMe: true, isHost: true, arrived: meArrived),
            member("u2"),
            member("u3"),
        ]
    }

    // ─────────────────────── 확정 전 ───────────────────────

    /// 모집 중이어도 **혼자면** 약속 흐름이 끼어들지 않는다 — 서버가 409 `NOT_ENOUGH_MEMBERS` 로
    /// 막는 자리라 프리셋을 띄우면 누를 수 없는 버튼이 된다.
    @Test("모집 중이고 혼자면 약속 흐름이 끼어들지 않는다")
    func recruitingAlone() {
        let alone = ride(status: .recruiting, members: [member("me", isMe: true, isHost: true)])

        #expect(meetingStage(ride: alone, now: now) == .recruiting)
        #expect(!canConfirmMeeting(ride: alone))
    }

    /// ★ **정원이 차지 않아도 2명이면 방장은 약속 시간을 정할 수 있다.**
    ///
    /// 서버 `confirm` 의 방 조건은 「실시간 · 2명 이상」뿐이고 **정원은 보지 않는다** — 확정이
    /// 모집을 끝낸다(`Party.confirm`: ACTIVE 면 COMPLETED 로 넘긴다). 정원 2/3 방으로 실측했다:
    /// `POST /matching/rooms/{id}/confirm` → **204**, status 가 ACTIVE → COMPLETED 로 바뀌었다(2026-11-09).
    ///
    /// 예전에는 앱이 정원 참을 요구해 이 방의 방장에게 **할 수 있는 일이 하나도 없었다**:
    /// 확정은 화면이 숨기고 「합승 완료」는 서버가 409 `PARTY_NOT_COMPLETED` 로 막았다.
    @Test("정원이 차지 않아도 2명이면 방장은 약속 시간을 정한다")
    func twoOfThreeHostConfirms() {
        let twoOfThree = ride(
            status: .recruiting,
            members: [member("me", isMe: true, isHost: true), member("u2")],
            capacity: 3
        )

        #expect(meetingStage(ride: twoOfThree, now: now) == .confirmByMe)
        #expect(canConfirmMeeting(ride: twoOfThree))
    }

    /// 같은 방을 비방장이 보면 「방장이 정해요」다 — 비활성 버튼을 두지 않는다.
    @Test("정원이 차지 않아도 2명이면 비방장은 방장을 기다린다")
    func twoOfThreeNonHostWaits() {
        let twoOfThree = ride(
            status: .recruiting,
            members: [member("me", isMe: true), member("u2", isHost: true)],
            capacity: 3
        )

        #expect(meetingStage(ride: twoOfThree, now: now) == .confirmByHost)
        #expect(!canConfirmMeeting(ride: twoOfThree))
    }

    /// ★ **정원은 확정 조건이 아니다** — 2/3 든 3/3 든 방장은 확정할 수 있다.
    ///
    /// 짝이던 테스트(「정원이 차지 않은 방에서 「합승 완료」는 여전히 닫혀 있다」)는 **지웠다**:
    /// 그 버튼이 서버에서 사라졌고(`b16551b7`) 판정 함수 `canFinishParty` 도 함께 지웠다. 그 테스트가
    /// 못 박던 사실(「확정과 완료를 같은 조건으로 묶으면 한쪽이 서버와 어긋난다」)은 비교 대상이
    /// 없어져 성립하지 않는다 — 대신 **정원과 확정이 서로 무관하다**를 양쪽 값으로 고정한다.
    @Test("정원이 차든 안 차든 방장은 약속 시간을 정한다")
    func capacityIsNotAConfirmCondition() {
        let host = member("me", isMe: true, isHost: true)
        let twoOfThree = ride(status: .recruiting, members: [host, member("u2")], capacity: 3)
        let threeOfThree = ride(status: .recruiting, members: [host, member("u2"), member("u3")], capacity: 3)

        #expect(canConfirmMeeting(ride: twoOfThree), "2/3 에서 확정이 막혔다 — 그 방은 끝낼 길이 없어진다")
        #expect(canConfirmMeeting(ride: threeOfThree), "3/3 에서 확정이 막혔다")
        #expect(meetingStage(ride: twoOfThree, now: now) == .confirmByMe)
        #expect(meetingStage(ride: threeOfThree, now: now) == .confirmByMe)
    }

    @Test("정원이 차고 내가 방장이면 약속 시간을 정할 수 있다")
    func confirmByMe() {
        let stage = meetingStage(ride: ride(members: hostedByMe()), now: now)

        #expect(stage == .confirmByMe)
        #expect(canConfirmMeeting(ride: ride(members: hostedByMe())))
    }

    @Test("정원이 차고 내가 방장이 아니면 방장이 정하기를 기다린다")
    func confirmByHost() {
        #expect(meetingStage(ride: ride(), now: now) == .confirmByHost)
        #expect(!canConfirmMeeting(ride: ride()))
    }

    /// 서버 `confirm` 은 **실시간 방만** 받는다(409 `NOT_REALTIME_PARTY`). 프리셋을 띄우면 무엇을
    /// 눌러도 409 이므로 띄우지 않는다.
    ///
    /// 떨어지는 단계가 `finishOnly` 에서 `MeetingStage.recruiting` 으로 바뀌었다 — 그 단계를
    /// 지웠기 때문이다(「합승 완료」가 서버에서 사라져 거기서 할 수 있는 일이 하나도 없어졌고,
    /// 「정원이 찼다」를 알려 주던 status 도 뜻이 바뀌었다). 실제로 그게 맞다: 이 방에서 사용자가
    /// 할 수 있는 일은 **기다리거나 나가는 것**이고, 그건 모집 중 화면이 이미 말하는 바다.
    @Test("예약 방에서는 약속 시간을 정할 수 없다")
    func reservationCannotConfirm() {
        let reservation = ride(members: hostedByMe(), roomType: .reservation)

        #expect(meetingStage(ride: reservation, now: now) == .recruiting)
        #expect(!canConfirmMeeting(ride: reservation))
    }

    /// 🔴 **예약 방에서도 나갈 수 있다** — 이 테스트가 **정반대로 뒤집힌 자리**다.
    ///
    /// 예전 이름은 「예약 방은 나가기도 합승 완료도 열지 않는다」였고, 근거는 「예약 방은 만드는
    /// 순간부터 확정이라 나가기가 **영원히** 409 `CANNOT_LEAVE_CONFIRMED_PARTY` 다」였다.
    /// **서버가 그 규칙과 그 코드를 함께 지웠다**(`b16551b7`: 「확정 방에서도 나갈 수 있고, 확정
    /// 방에서 혼자 남으면 닫는다」).
    ///
    /// 뒤집힌 쪽을 못 박아 두는 이유: 예약 방은 `Ride.isConfirmed` 가 **늘 true** 라, 나가기 판정이
    /// 확정을 보기만 하면 **모든 예약 방에서 나가기가 사라진다.** 들어간 사람에게 방을 벗어날 길이
    /// 없고, 서버가 그 계정의 다른 방 합류·생성·예약까지 전부 막으므로(`ALREADY_JOINED_OTHER_PARTY`)
    /// **앱 안에서 복구할 방법이 없다.** 되돌리기 쉬운 한 줄(`&& !ride.isConfirmed`)이 만드는 가장
    /// 큰 사용자 피해라, 값으로 고정한다.
    ///
    /// 변하지 않은 것: 약속 정하기는 여전히 닫혀 있다(409 `NOT_REALTIME_PARTY`).
    @Test("예약 방에서도 나갈 수 있다")
    func reservationCanLeave() {
        for status in [RideStatus.recruiting, .confirmed] {
            let reservation = ride(
                status: status,
                members: hostedByMe(),
                isConfirmed: true,
                departureAt: at(60),
                roomType: .reservation
            )

            #expect(canLeaveParty(ride: reservation), "\(status) 예약 방에서 나가기가 막혀 있다 — 벗어날 길이 없어진다")
            #expect(!canConfirmMeeting(ride: reservation), "\(status) 예약 방에서 약속 정하기가 열려 있다")
        }
    }

    /// 🔴 **확정된 실시간 방에서도 나갈 수 있다** — 위와 같은 사실의 실시간 쪽이다.
    ///
    /// 확정은 모집을 끝내지만(ACTIVE→COMPLETED) 이탈을 막지 않는다. 그리고 SSE `confirmed` 는
    /// `isConfirmed` 만 세우고 status 는 건드리지 않으므로 **확정된 RECRUITING** 을 그리는 한
    /// 프레임이 실제로 있다 — 거기서도 열려 있어야 한다.
    @Test("확정된 방에서도 나갈 수 있다")
    func confirmedCanLeave() {
        for status in [RideStatus.recruiting, .confirmed] {
            let confirmed = ride(status: status, isConfirmed: true, departureAt: at(30))
            #expect(canLeaveParty(ride: confirmed), "\(status) 확정 방에서 나가기가 막혀 있다")
        }
    }

    /// ★ **나가기를 막는 유일한 사유는 「내가 도착을 눌렀다」다** — 409 `ARRIVED_MEMBER_CANNOT_LEAVE`.
    ///
    /// 도착한 멤버가 곧 탑승자이고 택시비 정산 대상이라 장부에서 빠질 수 없기 때문이고, **도착 취소
    /// API 가 없으므로** 되돌릴 수도 없다. 조건이 「방이 어떤 상태인가」에서 **「내가 무엇을
    /// 눌렀는가」**로 옮겨 간 것이 이번 변경의 핵심이다.
    ///
    /// **남이 도착한 것은 나를 막지 않는다** — 그 줄을 함께 못 박는다. `members.contains { $0.hasArrived }`
    /// 같은 식으로 잘못 쓰면 먼저 도착한 사람 하나가 나머지 전원을 가둔다.
    @Test("도착을 누른 뒤에는 나갈 수 없다 - 남의 도착은 나를 막지 않는다")
    func arrivedCannotLeave() {
        let iArrived = ride(members: members(meArrived: true), isConfirmed: true, departureAt: at(-1))
        let othersArrived = ride(members: members(otherArrived: true), isConfirmed: true, departureAt: at(-1))

        #expect(!canLeaveParty(ride: iArrived), "도착을 누른 뒤에 나가기가 열려 있다 — 서버가 409 로 막는다")
        #expect(canLeaveParty(ride: othersArrived), "남이 도착했다고 내 나가기를 막으면 안 된다")
    }

    /// 서버는 **멤버 2명 이상**에서만 확정을 받는다(409 `NOT_ENOUGH_MEMBERS`). 정원 1인 방은
    /// 「정원 참」이면서 혼자라 그 조건을 못 맞춘다 — `capacity` 가 아니라 **목록 길이**를 세는 이유다.
    @Test("혼자 있는 방에서는 약속 시간을 정할 수 없다")
    func soloCannotConfirm() {
        let solo = ride(
            members: [member("me", isMe: true, isHost: true)],
            capacity: 1
        )

        // `finishOnly` 였다 — 그 단계를 지워 `MeetingStage.recruiting` 으로 떨어진다.
        // 정원 1인 방은 「정원 참」이면서 혼자라, 할 수 있는 일이 기다리거나 나가는 것뿐이다.
        #expect(meetingStage(ride: solo, now: now) == .recruiting)
        #expect(!canConfirmMeeting(ride: solo))
    }

    // ─────────────────────── 도착 창 경계 ───────────────────────

    @Test("확정됐지만 약속 10분 전이 아직 안 됐으면 도착 창이 닫혀 있다")
    func arrivalWindowClosed() {
        let stage = meetingStage(ride: ride(isConfirmed: true, departureAt: at(30)), now: now)

        #expect(stage == .confirmedWaiting)
        #expect(!canArriveAtDeparture(ride: ride(isConfirmed: true, departureAt: at(30)), now: now))
    }

    /// **정확히 10분 전이 참이다.** 서버가 「10분 전부터」라고 적었으므로 그 순간은 열려 있어야 한다.
    /// 한 칸 어긋나면 10분 전에 맞춰 도착한 사람이 버튼을 못 보고, 10분 1초 전에는 눌러서 409 를 맞는다.
    @Test("도착 창은 약속 10분 전 그 순간에 열린다")
    func arrivalWindowBoundary() {
        // 10분 1초 전 — 아직 닫혀 있다
        #expect(!canArriveAtDeparture(ride: ride(isConfirmed: true, departureAt: plusOneSecond(at(10))), now: now))
        // 정확히 10분 전 — 열린다
        #expect(canArriveAtDeparture(ride: ride(isConfirmed: true, departureAt: at(10)), now: now))
        // 9분 전 — 열려 있다
        #expect(canArriveAtDeparture(ride: ride(isConfirmed: true, departureAt: at(9)), now: now))
    }

    /// 도착 창에는 **상한이 없다.** 약속 시간이 지난 뒤에도 도착을 알릴 수 있어야 한다 — 늦게 온
    /// 사람이 **그 방의 탑승자로 남을 유일한 길**이고(미도착자는 탑승 기록·정산에서 빠진다),
    /// 서버 도착 창에도 상한이 없다.
    @Test("약속 시간이 지나도 미도착이면 도착을 알릴 수 있다")
    func lateArrivalStillOpen() {
        let late = ride(isConfirmed: true, departureAt: at(-5))

        #expect(meetingStage(ride: late, now: now) == .arriveOpen)
        #expect(canArriveAtDeparture(ride: late, now: now))
        // 단계에는 드러나지 않는 사실 — 「왜 나만 출발이 없는지」를 말해 줄 근거다
        #expect(isMeetingTimePassed(departureAt: late.departureAt, now: now))
    }

    // ─────────────────────── 출발 경계 ───────────────────────

    @Test("도착했지만 약속 시간 전이면 출발할 수 없다")
    func arrivedBeforeMeeting() {
        let waiting = ride(members: members(meArrived: true), isConfirmed: true, departureAt: at(5))

        #expect(meetingStage(ride: waiting, now: now) == .arrivedWaiting)
        #expect(!canDepartParty(ride: waiting, now: now))
    }

    /// **약속 시간 정각이 참이다.** 서버는 약속 시간 **전**에만 409 `MEETING_NOT_STARTED` 를 던지므로,
    /// 정각을 막으면 약속 시간에 딱 맞춰 누른 사람이 서버가 허용하는 일을 못 하게 된다.
    ///
    /// 1초 단위로 짚는 이유: 분 단위로만 보면 「정각 포함/제외」가 갈리지 않는다.
    @Test("출발은 약속 시간 정각에 열린다")
    func departBoundary() {
        // 출발이 방장 전용이 된 뒤로 이 경계는 **방장 구성**에서만 볼 수 있다 — `members()` 로
        // 두면 방장 조건에 먼저 걸려 세 가지가 모두 false 가 되고, 경계를 짚지 못한다.
        func departableAtSeconds(_ offsetSeconds: Int) -> Bool {
            canDepartParty(
                ride: ride(
                    members: hostedByMe(meArrived: true),
                    isConfirmed: true,
                    departureAt: iso(now.addingTimeInterval(TimeInterval(offsetSeconds)))
                ),
                now: now
            )
        }

        #expect(!departableAtSeconds(1), "약속 1초 전에는 막혀야 한다")
        #expect(departableAtSeconds(0), "정각은 열린다")
        #expect(departableAtSeconds(-60), "지난 뒤에도 열린다")
    }

    /// 🔴 **출발은 방장 전용이다** — 이 테스트도 **정반대로 뒤집혔다**.
    ///
    /// 예전 이름은 「출발은 도착한 멤버 누구나 누를 수 있다 - 방장 조건이 아니다」였고, 근거는
    /// 「방장 조건을 베껴 오면 방장이 늦는 방이 영원히 출발하지 못한다」였다. **서버가 그
    /// 트레이드오프를 반대로 골랐다**(`b16551b7`: 「출발은 도착한 방장만 누른다」) — 그래서 지금
    /// 방장이 오지 않는 방은 **실제로 출발할 수 없고**, 앱이 할 수 있는 일은 그 사실을 비방장에게
    /// 말해 주는 것뿐이다.
    ///
    /// 그래서 단계가 둘로 갈렸다: 도착한 방장은 `MeetingStage.departByMe`(버튼), 도착한
    /// 비방장은 `MeetingStage.departByHost`(안내문). 갈라 두지 않으면 비방장에게 403
    /// `NOT_PARTY_HOST` 로만 끝나는 버튼을 띄운다.
    @Test("출발은 도착한 방장만 누를 수 있다")
    func departHostOnly() {
        // 내 줄에 host 가 없다(u2 가 방장) — 도착해도 버튼이 없어야 한다
        let notHostButArrived = ride(members: members(meArrived: true), isConfirmed: true, departureAt: at(-1))
        let hostAndArrived = ride(members: hostedByMe(meArrived: true), isConfirmed: true, departureAt: at(-1))

        #expect(meetingStage(ride: notHostButArrived, now: now) == .departByHost)
        #expect(!canDepartParty(ride: notHostButArrived, now: now), "비방장에게 출발이 열렸다 — 403 으로만 끝난다")

        #expect(meetingStage(ride: hostAndArrived, now: now) == .departByMe)
        #expect(canDepartParty(ride: hostAndArrived, now: now), "도착한 방장이 출발할 수 없다 — 방을 끝낼 길이 없어진다")
    }

    /// 비방장도 **도착은 해야 한다** — `departByHost` 는 「도착했는데 버튼이 없다」는 뜻이고,
    /// 미도착이면 `MeetingStage.arriveOpen` 에 머물러 도착 버튼을 본다.
    ///
    /// 두 상태를 가르는 것이 요점이다: 저쪽은 **내가 할 일이 남았고**, 이쪽은 **방장을 기다린다**.
    /// 한 문구로 뭉개면 할 일이 남은 사람에게 「기다려 주세요」라고 말하게 된다.
    @Test("비방장이 미도착이면 방장 대기가 아니라 도착 단계다")
    func nonHostNotArrivedStillArrives() {
        let notHostNotArrived = ride(isConfirmed: true, departureAt: at(-1))

        #expect(meetingStage(ride: notHostNotArrived, now: now) == .arriveOpen)
        #expect(isMeetingTimePassed(departureAt: notHostNotArrived.departureAt, now: now))
    }

    @Test("도착하지 않으면 약속 시간이 지나도 출발할 수 없다")
    func notArrivedCannotDepart() {
        let notArrived = ride(isConfirmed: true, departureAt: at(-1))

        #expect(meetingStage(ride: notArrived, now: now) == .arriveOpen)
        #expect(!canDepartParty(ride: notArrived, now: now))
    }

    // ─────────────────────── 읽을 수 없는 값 · 닫힌 방 ───────────────────────

    /// **약속 시각을 읽을 수 없으면 아무 창도 열지 않는다.** 열어 두고 409 를 맞게 하는 것보다
    /// 「확정됐다」만 보여 주는 편이 낫다 — 틀린 시각으로 사람을 엉뚱한 때에 모이게 하는 것이 최악이다.
    @Test("약속 시각을 읽을 수 없으면 도착도 출발도 열지 않는다")
    func unreadableDepartureAt() {
        for broken in [nil, "", "   ", "오후 3시", "2026-11-06 15:00"] as [String?] {
            let label = "departureAt=\(String(describing: broken))"
            let r = ride(members: members(meArrived: true), isConfirmed: true, departureAt: broken)
            #expect(meetingStage(ride: r, now: now) == .arrivedWaiting, "\(label)")
            #expect(!canDepartParty(ride: r, now: now), "\(label)")

            let notArrived = ride(isConfirmed: true, departureAt: broken)
            #expect(meetingStage(ride: notArrived, now: now) == .confirmedWaiting, "\(label)")
            #expect(!canArriveAtDeparture(ride: notArrived, now: now), "\(label)")
        }
    }

    /// 오프셋 표기(`+09:00`)도 읽는다 — 서버가 UTC `Z` 로 주지만 계약은 ISO-8601 이다.
    @Test("오프셋 표기도 읽는다")
    func offsetNotation() {
        // 2026-11-06T15:05:00+09:00 == 06:05:00Z == now + 5분 → 도착 창이 열려 있다
        let offset = ride(isConfirmed: true, departureAt: "2026-11-06T15:05:00+09:00")

        #expect(meetingStage(ride: offset, now: now) == .arriveOpen)
    }

    /// 닫힌 방(FINISHED·CANCELED)에서는 **모든 단계가 CLOSED** 다. Route 가 곧 화면을 떠나지만
    /// 그 사이 한 프레임을 그리고, 그 프레임에서 눌린 확정·도착·출발은 409 로만 끝난다.
    ///
    /// 확정 플래그가 서 있어도 그렇다 — 닫힘 판정이 **맨 위**에 있어야 하는 이유다.
    @Test("닫힌 방에서는 약속 흐름이 전부 닫힌다")
    func closedPartyClosesFlow() {
        for status in [RideStatus.completed, .canceled] {
            let closed = ride(
                status: status,
                members: members(meArrived: true),
                isConfirmed: true,
                departureAt: at(-1)
            )
            #expect(meetingStage(ride: closed, now: now) == .closed, "\(status)")
            #expect(!canArriveAtDeparture(ride: closed, now: now), "\(status)")
            #expect(!canDepartParty(ride: closed, now: now), "\(status)")
            #expect(!canConfirmMeeting(ride: closed), "\(status)")
        }
    }

    /// **열거형 전체를 훑어** 「대기 단계가 아니면 CLOSED」를 못 박는다. 서버에 단계가 늘어
    /// `RideStatus` 에 값이 더해지면, 이름을 적는 위 테스트는 그 값을 **묻지 않고 지나간다.**
    /// 「새 단계에서는 약속 흐름을 열지 않는다」가 안전한 기본값이다.
    @Test("대기 단계가 아닌 모든 status 는 CLOSED 다")
    func everyNonWaitingStatusIsClosed() {
        for status in RideStatus.allCases where status != .recruiting && status != .confirmed {
            #expect(meetingStage(ride: ride(status: status), now: now) == .closed, "\(status)")
        }
    }

    /// **확정 판정이 정원 판정보다 위에 있어야 한다.** SSE `confirmed` 는 `isConfirmed` 만 세우고
    /// status 는 건드리지 않으므로(프레임의 status 가 문자열이라 옮길 수 없다) **확정된 RECRUITING**
    /// 을 그리는 한 프레임이 실제로 존재한다. 순서가 뒤집히면 이미 확정된 방에 「약속 시간 정하기」가
    /// 다시 떠서 409 `ALREADY_CONFIRMED` 로 끝난다.
    @Test("확정 플래그가 정원 단계보다 먼저 읽힌다")
    func confirmedBeforeFullStage() {
        let confirmedButRecruiting = ride(
            status: .recruiting,
            members: hostedByMe(),
            isConfirmed: true,
            departureAt: at(30)
        )

        #expect(meetingStage(ride: confirmedButRecruiting, now: now) == .confirmedWaiting)
        #expect(!canConfirmMeeting(ride: confirmedButRecruiting))
    }

    // ─────────────────────── 도착 집계 ───────────────────────

    @Test("내 도착 여부는 멤버 목록의 내 줄만 본다")
    func myArrivalFromMyRow() {
        #expect(hasArrivedMyself(ride: ride(members: members(meArrived: true))))
        #expect(!hasArrivedMyself(ride: ride(members: members(meArrived: false))))
    }

    /// 내가 목록에 없으면 false 다 — 그건 「도착하지 않았다」가 아니라 **「도착했다고 말해 주는
    /// 근거가 없다」**다. 그 경우 화면은 도착 버튼을 띄우고, 이미 도착했다면 서버가 멱등하게 받는다.
    @Test("내가 목록에 없으면 도착 여부를 단정하지 않는다")
    func notInListNotArrived() {
        #expect(!hasArrivedMyself(ride: ride(members: [member("u2"), member("u3")])))
    }

    @Test("도착 인원과 미도착 인원이 목록에서 나온다")
    func arrivedAndNotArrivedCounts() {
        let r = ride(members: members(meArrived: true, otherArrived: false))

        #expect(arrivedCount(ride: r) == 1)
        #expect(notArrivedCount(ride: r) == 2)
        #expect(arrivedCount(ride: r) + notArrivedCount(ride: r) == 3)
    }

    /// 「도착」 배지는 **확정된 방에서만** 뜻이 있다 — 확정 전에는 도착 개념이 없다.
    @Test("도착 배지는 확정 전에는 붙지 않는다")
    func arrivedBadgeOnlyWhenConfirmed() {
        let arrivedMember = member("me", isMe: true, arrived: true)

        #expect(showsArrivedBadge(member: arrivedMember, confirmed: true))
        #expect(!showsArrivedBadge(member: arrivedMember, confirmed: false))
        #expect(!showsArrivedBadge(member: member("u2"), confirmed: true))
    }
}

/// 원본 `Instant.parse` 자리. 기대값을 만드는 자리라 시험 대상 해석기(`toMeetingInstantOrNull`)를 쓰지 않는다 —
/// 깨진 고정값은 `distantPast` 로 떨어져 어느 단언에서든 바로 드러난다.
private func instant(_ text: String) -> Date {
    (try? Date(text, strategy: .iso8601)) ?? .distantPast
}

/// 원본 `Instant.toString()` 자리 — 화면이 서버로 보내는 값과 같은 형식(`meetingPresetIso`)으로 적는다.
private func iso(_ date: Date) -> String {
    date.formatted(.iso8601)
}

/// `at(10)` 보다 **1초 앞선** 시각 — 「정확히 10분 전」 경계의 바로 바깥을 짚는다.
private func plusOneSecond(_ text: String) -> String {
    iso(instant(text).addingTimeInterval(1))
}
