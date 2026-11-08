@testable import FeatureMatching
import MoyeotaDomain
import Testing

/// 21 대기 화면의 **단계 판정** — 나가기를 보여 줄지(`canLeaveParty`), 방을 손으로 닫는 단계인지
/// (`isFinishStage`), 그 단계에서 내가 누를 수 있는지(`canFinishParty`).
///
/// 이 파일은 `WaitingModeTest` 였다. 세 판정이 서버 택시 모드(`taxiEnabled`)에 따라 갈렸고 그 분기가
/// 테스트의 주제였는데, 기사·배차를 걷어내면서 **모드 자체가 사라졌다** — 서버가 `MATCHING`·
/// `DRIVER_ASSIGNED`·`IN_RIDE` 를 보낼 수 없어 갈릴 쪽이 없다. 그래서 남은 쪽(동승)의 동작만 못 박고
/// 이름을 「단계」로 바꿨다. **삭제하지 않은 이유**는 아래 네 가지가 모드와 무관한 사실이기 때문이다:
/// 어느 status 에서 나갈 수 있고, 어느 status 가 완료 단계이고, 방장 조건이 어디에 걸리고, 닫힌 방에서는
/// 셋 다 거짓이어야 한다.
///
/// **단계(`isFinishStage`)와 권한(`canFinishParty`)은 다른 질문이다.** 전자는 「방이 어떤 단계인가」,
/// 후자는 「내가 누를 수 있는가」 — 방장 조건은 후자에만 걸린다. 방장 쪽 분기는
/// `WaitingHostNoticeTest` 가 따로 맡는다.
struct WaitingStageTest {
    private func ride(_ status: RideStatus, members: [User] = [], isConfirmed: Bool = false) -> Ride {
        Ride(
            id: "1",
            origin: "부산대",
            destination: "서면",
            departureLabel: "지금 출발",
            capacity: 3,
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

    /// 서버 `ensureRecruiting` = ACTIVE·COMPLETED 를 그대로 반영한다 — 정원이 찬 방에서 나가면
    /// 서버가 방을 ACTIVE 로 되돌려 다시 모집한다.
    ///
    /// 예전에는 택시 모드에서 MATCHED 의 나가기를 미리 막았다(곧 배차가 시작돼 409 였다).
    /// 그 모드가 없어지면서 **막을 이유도 없어졌다** — 여기서 false 로 되돌리면 21 의 「방 나가기」가
    /// 서버가 허용하는 자리에서 비활성이 된다.
    @Test("대기 단계에서는 모집 중이든 정원이 찼든 나갈 수 있다")
    func leaveInWaitingStage() {
        #expect(canLeaveParty(ride: ride(.recruiting)))
        #expect(canLeaveParty(ride: ride(.matched)))
    }

    /// **약속이 확정되면 아무도 나갈 수 없다**(2026-11-06). 서버가 확정과 함께 이탈을 막는데
    /// status 는 COMPLETED 로 남아 `isWaitingForMembers` 를 통과하므로, 확정 여부를 보지 않으면
    /// 「방 나가기」가 **서버가 거절하는 버튼**으로 남는다.
    ///
    /// 이 판정이 틀렸을 때의 대가가 유독 크다: 나갈 수 있다고 믿은 사람이 약속 장소에 가지 않으면
    /// 「출발」이 그 사람을 **노쇼로 기록**한다(약속 시간부터 노쇼 횟수 × 24시간 제한). 화면의
    /// 거짓말이 실제 제재로 이어지는 자리라 값으로 못 박는다.
    @Test("확정된 방에서는 나갈 수 없다")
    func noLeaveWhenConfirmed() {
        #expect(!canLeaveParty(ride: ride(.matched, isConfirmed: true)))
        // 서버는 확정과 함께 ACTIVE→COMPLETED 로 옮기지만, SSE `confirmed` 는 status 를 건드리지
        // 않으므로 확정된 RECRUITING 을 그리는 한 프레임이 있다 — 거기서도 막혀야 한다.
        #expect(!canLeaveParty(ride: ride(.recruiting, isConfirmed: true)))
    }

    /// **확정된 방에서는 「합승 완료」가 사라진다.** 그 방을 끝내는 길은 「출발」뿐이고(서버가 409
    /// `USE_DEPART_FOR_CONFIRMED_PARTY` 로 거절한다), 완료로 닫히면 **노쇼 기록 없이** 방이 끝나
    /// 약속을 어긴 사람이 제재를 면한다 — 성공하는 편이 오히려 더 나쁜 버튼이다.
    @Test("확정된 방에서는 합승 완료가 사라진다")
    func noFinishWhenConfirmed() {
        #expect(canFinishParty(ride: ride(.matched, members: [hostMe])))
        #expect(!canFinishParty(ride: ride(.matched, members: [hostMe], isConfirmed: true)))
    }

    @Test("합승 완료 단계는 정원이 찼을 때다")
    func finishStage() {
        #expect(isFinishStage(status: .matched))
        #expect(!isFinishStage(status: .recruiting))
    }

    /// 방장이어도 단계가 아니면 누를 수 없다 — 방장 조건이 단계 조건을 대체하지 않는다.
    @Test("방장이어도 합승 완료는 그 단계에서만")
    func hostOnlyInStage() {
        #expect(canFinishParty(ride: ride(.matched, members: [hostMe])))
        #expect(!canFinishParty(ride: ride(.recruiting, members: [hostMe])))
    }

    /// 닫힌 방에서는 셋 다 거짓이다. 서버가 방을 닫은 순간과 Route 가 그걸 알아채 화면을 떠나는
    /// 순간 사이에 한 프레임이 있고, 그 프레임에서 눌린 나가기·완료는 409 로만 끝난다.
    @Test("닫힌 방에서는 나가기도 합승 완료도 안 된다")
    func closedParty() {
        for status in [RideStatus.completed, .canceled] {
            #expect(!canLeaveParty(ride: ride(status)), "\(status) 에서 나가기가 열려 있다")
            #expect(!isFinishStage(status: status), "\(status) 가 완료 단계로 읽힌다")
            #expect(
                !canFinishParty(ride: ride(status, members: [hostMe])),
                "\(status) 에서 「합승 완료」가 보인다"
            )
        }
    }

    /// **열거형 전체를 훑어** 대기 단계 둘 밖에서는 나가기가 열리지 않는 것을 못 박는다.
    ///
    /// 위 테스트가 지금 있는 두 종료 상태를 이름으로 적는 것과 역할이 다르다 — 서버에 단계가 늘어
    /// `RideStatus` 에 값이 더해지면, 이름을 적는 쪽은 그 값을 **묻지 않고 지나간다.**
    /// 「새 단계는 기본적으로 나갈 수 없다」가 안전한 기본값이다(눌러서 409 를 맞는 쪽이 더 나쁘다).
    @Test("대기 단계가 아닌 모든 status 에서 나가기가 막힌다")
    func leaveBlockedOutsideWaiting() {
        for status in RideStatus.allCases where status != .recruiting && status != .matched {
            #expect(!canLeaveParty(ride: ride(status)), "\(status) 에서 나가기가 열려 있다")
        }
    }
}
