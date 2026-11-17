@testable import FeatureMatching
import MoyeotaDomain
import Testing

/// 21 대기 화면의 **나가기 판정**(`canLeaveParty`)과 **정원 판정**(`isMatchFull`).
///
/// 이 파일은 `WaitingModeTest` 였다 — 판정들이 서버 택시 모드(`taxiEnabled`)에 따라 갈렸고 그 분기가
/// 주제였는데, 기사·배차를 걷어내면서 모드 자체가 사라져 이름을 「단계」로 바꿨다.
///
/// ### 🔴 2026-11-12 에 주제가 또 줄었다 ★
/// `isFinishStage`·`canFinishParty` 를 보던 네 테스트를 **지웠다** — 서버가 `/finish` 를 없애
/// (`b16551b7`) 두 함수가 사라졌다. 그 테스트들이 못 박던 사실의 운명이 각각 다르다:
///
/// | 옛 테스트가 못 박던 것 | 지금 |
/// |---|---|
/// | 「합승 완료 단계는 정원이 찼을 때다」 | **거짓이 됐다** — 서버 COMPLETED 는 「확정」이다. 정원 판정은 `isMatchFull` 이 목록으로 한다 |
/// | 「방장이어도 그 단계에서만 누른다」 | **출발로 옮겨 갔다** — `WaitingHostNoticeTest` 가 `canDepartParty` 로 맡는다 |
/// | 「확정된 방에서는 합승 완료가 사라진다」 | 가리킬 버튼이 없어 성립하지 않는다 |
/// | 「닫힌 방에서는 둘 다 거짓」 | 나가기 쪽만 남았다(아래) |
///
/// 대신 **뒤집힌 판정 둘**을 이 파일이 맡는다: 확정·예약이 더 이상 나가기를 막지 않는다는 것과,
/// 정원 판정이 status 가 아니라 **목록 길이**라는 것.
struct WaitingStageTest {
    private func ride(
        _ status: RideStatus,
        members: [User] = [],
        isConfirmed: Bool = false,
        capacity: Int = 3
    ) -> Ride {
        Ride(
            id: "1",
            origin: "부산대",
            destination: "서면",
            departureLabel: "지금 출발",
            capacity: capacity,
            members: members,
            farePerPerson: 0,
            totalFare: 0,
            status: status,
            isConfirmed: isConfirmed
        )
    }

    /// 방장인 나 — 권한 분기를 보려면 목록에 내가 방장으로 있어야 한다.
    private let hostMe = User(
        id: "me",
        nickname: "나",
        verifiedLabel: "",
        rating: 0.0,
        rideCount: 0,
        isMe: true,
        isHost: true
    )

    private func other(_ id: String) -> User {
        User(id: id, nickname: id, verifiedLabel: "", rating: 0.0, rideCount: 0)
    }

    /// 서버가 통과시키는 두 상태를 그대로 반영한다 — 모집 중(ACTIVE)이든 확정됐든(COMPLETED).
    ///
    /// 예전에는 택시 모드에서 COMPLETED 의 나가기를 미리 막았다(곧 배차가 시작돼 409 였다).
    /// 그 모드가 없어지면서 **막을 이유도 없어졌다** — 여기서 false 로 되돌리면 21 의 「방 나가기」가
    /// 서버가 허용하는 자리에서 비활성이 된다.
    @Test("대기 단계에서는 모집 중이든 확정됐든 나갈 수 있다")
    func leaveInWaitingStage() {
        #expect(canLeaveParty(ride: ride(.recruiting)))
        #expect(canLeaveParty(ride: ride(.confirmed)))
    }

    /// 🔴 **확정된 방에서도 나갈 수 있다** — 이 테스트는 **정반대로 뒤집힌 자리**다.
    ///
    /// 2026-11-06 ~ 11-12 사이 이 자리의 이름은 「확정된 방에서는 나갈 수 없다」였고, 근거는 「서버가
    /// 확정과 함께 이탈을 막는다」였다. **서버가 그 규칙을 버렸다**(`b16551b7`: 「확정 방에서도 나갈
    /// 수 있고, 확정 방에서 혼자 남으면 닫는다」).
    ///
    /// 뒤집힌 쪽을 못 박는 이유는 **틀렸을 때의 대가가 비대칭**이기 때문이다. `&& !ride.isConfirmed`
    /// 한 줄을 되돌리면 ① 확정된 방과 ② **모든 예약 방**(그쪽은 `Ride.isConfirmed` 가 늘 true 다)에서
    /// 나가기가 사라진다. 들어간 사람에게 방을 벗어날 길이 없고, 서버가 그 계정의 다른 방 합류·생성·
    /// 예약까지 전부 막으므로(`ALREADY_JOINED_OTHER_PARTY`) **앱 안에서 복구할 방법이 없다.**
    ///
    /// 예약 쪽 짝은 `MeetingStageTest` 의 「예약 방에서도 나갈 수 있다」가 맡는다.
    @Test("확정된 방에서도 나갈 수 있다")
    func leaveWhenConfirmed() {
        #expect(canLeaveParty(ride: ride(.confirmed, isConfirmed: true)))
        // 서버는 확정과 함께 ACTIVE→COMPLETED 로 옮기지만, SSE `confirmed` 는 status 를 건드리지
        // 않으므로 확정된 RECRUITING 을 그리는 한 프레임이 있다 — 거기서도 열려 있어야 한다.
        #expect(canLeaveParty(ride: ride(.recruiting, isConfirmed: true)))
    }

    /// ★ **나가기를 막는 유일한 사유는 「내가 도착을 눌렀다」다** — 409 `ARRIVED_MEMBER_CANNOT_LEAVE`.
    ///
    /// 도착한 멤버가 곧 탑승자이고 택시비 정산 대상이라 서버가 묶는다. **도착 취소 API 가 없으므로**
    /// 되돌릴 수도 없고, 그래서 이 버튼은 **비활성 + 사유 문구**가 맞다(숨기면 뒤로 갈 길이 사라진
    /// 것처럼 보인다).
    @Test("도착을 누른 뒤에는 나갈 수 없다")
    func noLeaveAfterArrival() {
        var arrivedMe = hostMe
        arrivedMe.hasArrived = true

        #expect(!canLeaveParty(ride: ride(.confirmed, members: [arrivedMe], isConfirmed: true)))
        #expect(canLeaveParty(ride: ride(.confirmed, members: [hostMe], isConfirmed: true)))
    }

    /// 🔴 **정원 판정은 status 가 아니라 목록 길이다** — `complete_match` 퍼널의 판정이다
    /// (`isMatchFull`). **Android 와 같은 식이어야 한다.**
    ///
    /// 옛 식은 `status == .matched` 였고, 서버가 그 값의 뜻을 「방장이 약속을 확정했다」로 바꾸면서
    /// (`b16551b7`) **양쪽으로 거짓이 됐다**: 2/3 짜리 확정 방을 매칭 완료로 세고, 정원이 꽉 찬
    /// 미확정 방은 세지 않았다. 퍼널 숫자가 조용히 틀리는 종류라 값으로 고정한다.
    @Test("정원 판정은 멤버 수와 정원을 비교한다 - status 를 보지 않는다")
    func matchFullCountsMembers() {
        let two = [hostMe, other("u2")]
        let three = two + [other("u3")]

        // 정원이 찼으면 status 가 무엇이든 참이다 — 서버는 정원이 찬 방도 ACTIVE 로 둔다
        #expect(isMatchFull(ride: ride(.recruiting, members: three)))
        #expect(isMatchFull(ride: ride(.confirmed, members: three)))
        // 정원이 안 찼으면 **확정됐어도** 거짓이다 — 2/3 확정 방을 「매칭 완료」로 세면 퍼널이 거짓이 된다
        #expect(!isMatchFull(ride: ride(.confirmed, members: two, isConfirmed: true)))
        #expect(!isMatchFull(ride: ride(.recruiting, members: two)))
    }

    /// ★ **정원을 모르는 방(`capacity` 0)은 「찼다」로 세지 않는다.**
    ///
    /// 목록·추천·더미 응답으로 만든 `Ride` 가 그렇다 — 0 은 「정원이 0명」이 아니라 **「정원을
    /// 모른다」**다. 가드가 없으면 `0 >= 0` 이 참이라 **방금 만든 1인 방까지 전부 매칭 완료**로
    /// 세어, 퍼널 3단계가 1단계와 같은 숫자가 된다.
    @Test("정원을 모르는 방은 찼다고 세지 않는다")
    func unknownCapacityIsNotFull() {
        #expect(!isMatchFull(ride: ride(.recruiting, members: [hostMe], capacity: 0)))
        #expect(!isMatchFull(ride: ride(.confirmed, members: [], capacity: 0)))
    }

    /// 닫힌 방에서는 나가기가 거짓이다. 서버가 방을 닫은 순간과 Route 가 그걸 알아채 화면을 떠나는
    /// 순간 사이에 한 프레임이 있고, 그 프레임에서 눌린 나가기는 409 `PARTY_CLOSED` 로만 끝난다.
    @Test("닫힌 방에서는 나갈 수 없다")
    func closedParty() {
        for status in [RideStatus.completed, .canceled] {
            #expect(!canLeaveParty(ride: ride(status)), "\(status) 에서 나가기가 열려 있다")
        }
    }

    /// **열거형 전체를 훑어** 대기 단계 둘 밖에서는 나가기가 열리지 않는 것을 못 박는다.
    ///
    /// 위 테스트가 지금 있는 두 종료 상태를 이름으로 적는 것과 역할이 다르다 — 서버에 단계가 늘어
    /// `RideStatus` 에 값이 더해지면, 이름을 적는 쪽은 그 값을 **묻지 않고 지나간다.**
    /// 「새 단계는 기본적으로 나갈 수 없다」가 안전한 기본값이다(눌러서 409 를 맞는 쪽이 더 나쁘다).
    @Test("대기 단계가 아닌 모든 status 에서 나가기가 막힌다")
    func leaveBlockedOutsideWaiting() {
        for status in RideStatus.allCases where status != .recruiting && status != .confirmed {
            #expect(!canLeaveParty(ride: ride(status)), "\(status) 에서 나가기가 열려 있다")
        }
    }
}
