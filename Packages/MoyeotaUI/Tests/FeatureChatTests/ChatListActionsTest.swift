@testable import FeatureChat
import MoyeotaDomain
import Testing

/// 채팅 목록 길게 누르기 — 「나가기」가 **무엇에서** 나가는지는 방 상태가 정한다(develop 규칙).
///
/// - 끝났거나 취소된 방 → 채팅방만 나간다(목록 정리)
/// - 진행 중이고 도착 전 → 동승에서 나간다. 서버가 채팅방도 함께 정리한다
/// - 도착을 누른 뒤 → 서버가 409 `ARRIVED_MEMBER_CANNOT_LEAVE` 로 막는다. 누르기 전에 말한다
@Suite struct ChatListActionsTest {

    private func member(_ id: String, isMe: Bool = false, isHost: Bool = false, arrived: Bool = false) -> User {
        User(id: id, nickname: id, verifiedLabel: "", rating: 0, rideCount: 0, isMe: isMe, isHost: isHost, hasArrived: arrived)
    }

    private func ride(_ status: RideStatus, _ members: [User], roomType: RoomType = .realtime) -> Ride {
        Ride(
            id: "42", origin: "강남역", destination: "서울시청", departureLabel: "지금 출발", capacity: 3,
            members: members, farePerPerson: 0, totalFare: 0, status: status,
            isConfirmed: status == .matched, roomType: roomType
        )
    }

    private func leave(isHost: Bool = false, alone: Bool = false, cancelsMeeting: Bool = false) -> ChatLeavePlan {
        .leaveParty(ChatLeavePlan.LeaveParty(
            chatRoomId: 7, partyId: 42, isHost: isHost, alone: alone, cancelsMeeting: cancelsMeeting,
            capacity: 3, memberCount: 2
        ))
    }

    // ─────────────────────── 무엇에서 나가나 ───────────────────────

    @Test("방을 찾지 못하면 채팅방만 나간다")
    func missingRideLeavesChatOnly() {
        #expect(chatLeavePlan(chatRoomId: 7, ride: nil) == .chatOnly(chatRoomId: 7))
    }

    @Test("끝난 방과 취소된 방은 채팅방만 나간다")
    func closedRidesLeaveChatOnly() {
        let finished = ride(.completed, [member("me", isMe: true, arrived: true), member("b")])
        let canceled = ride(.canceled, [member("me", isMe: true)])
        #expect(chatLeavePlan(chatRoomId: 7, ride: finished) == .chatOnly(chatRoomId: 7))
        #expect(chatLeavePlan(chatRoomId: 7, ride: canceled) == .chatOnly(chatRoomId: 7))
    }

    @Test("이미 방 멤버가 아니면 채팅방만 나간다")
    func notAMemberLeavesChatOnly() {
        let other = ride(.recruiting, [member("a", isHost: true), member("b")])
        #expect(chatLeavePlan(chatRoomId: 7, ride: other) == .chatOnly(chatRoomId: 7))
    }

    @Test("진행 중이고 도착 전이면 동승에서 나간다")
    func openRideLeavesParty() {
        let open = ride(.recruiting, [member("a", isHost: true), member("me", isMe: true)])
        #expect(chatLeavePlan(chatRoomId: 7, ride: open) == leave())
    }

    @Test("예약 방도 도착 전이면 나갈 수 있다")
    func reservationCanBeLeft() {
        let reservation = ride(.recruiting, [member("me", isMe: true, isHost: true), member("b")], roomType: .reservation)
        guard case .leaveParty(let plan) = chatLeavePlan(chatRoomId: 7, ride: reservation) else {
            Issue.record("동승 나가기여야 한다")
            return
        }
        #expect(plan.isHost)
    }

    @Test("약속이 정해진 둘뿐인 방에서 나가면 약속이 취소된다")
    func confirmedPairCancelsMeeting() {
        let pair = ride(.matched, [member("a", isHost: true), member("me", isMe: true)])
        let trio = ride(.matched, [member("a", isHost: true), member("b"), member("me", isMe: true)])
        guard case .leaveParty(let pairPlan) = chatLeavePlan(chatRoomId: 7, ride: pair),
              case .leaveParty(let trioPlan) = chatLeavePlan(chatRoomId: 7, ride: trio)
        else {
            Issue.record("동승 나가기여야 한다")
            return
        }
        #expect(pairPlan.cancelsMeeting)
        #expect(!trioPlan.cancelsMeeting)
    }

    @Test("혼자 있는 방이면 나가는 순간 방이 닫힌다")
    func aloneClosesRoom() {
        guard case .leaveParty(let plan) = chatLeavePlan(chatRoomId: 7, ride: ride(.recruiting, [member("me", isMe: true, isHost: true)])) else {
            Issue.record("동승 나가기여야 한다")
            return
        }
        #expect(plan.alone)
    }

    @Test("도착을 누른 뒤에는 나갈 수 없다")
    func arrivedIsBlocked() {
        let arrived = ride(.matched, [member("a", isHost: true), member("me", isMe: true, arrived: true)])
        #expect(chatLeavePlan(chatRoomId: 7, ride: arrived) == .blocked)
    }

    // ─────────────────────── 확인창 문구 ───────────────────────

    @Test("채팅방만 나갈 때는 되돌릴 수 없다고 먼저 말한다")
    func chatOnlyCopy() {
        let copy = chatLeaveDialog(plan: .chatOnly(chatRoomId: 7))
        #expect(copy.title == "채팅방을 나갈까요?")
        #expect(copy.body == "나가면 이 대화가 목록에서 사라지고 다시 들어올 수 없어요")
        #expect(copy.confirmText == "나가기")
        #expect(copy.destructive)
    }

    @Test("동승에서 나갈 때의 문구 — 기본·방장·혼자·둘뿐인 확정 방")
    func leavePartyCopy() {
        #expect(chatLeaveDialog(plan: leave()).title == "방에서 나갈까요?")
        #expect(chatLeaveDialog(plan: leave()).body == "동승에서 빠지고 이 채팅방도 함께 사라져요")
        #expect(chatLeaveDialog(plan: leave(isHost: true)).body
            == "동승에서 빠지고 이 채팅방도 함께 사라져요\n방장은 남은 분 중 먼저 들어온 분에게 넘어가요")
        #expect(chatLeaveDialog(plan: leave(isHost: true, alone: true)).body == "혼자 있는 방이라 나가면 방이 닫혀요")
        #expect(chatLeaveDialog(plan: leave(isHost: true, cancelsMeeting: true)).body
            == "동승에서 빠지고 이 채팅방도 함께 사라져요\n남은 분 혼자가 되어 약속이 취소돼요")
    }

    @Test("막힌 경우는 이유만 알리고 확인 하나로 닫는다")
    func blockedCopy() {
        let copy = chatLeaveDialog(plan: .blocked)
        #expect(copy.title == "지금은 나갈 수 없어요")
        #expect(copy.body == "출발지에 도착했다고 누른 뒤에는 방에서 나갈 수 없어요")
        #expect(copy.confirmText == "확인")
        #expect(copy.dismissText == nil)
        #expect(!copy.destructive)
    }

    // ─────────────────────── 알림·실패 문구 ───────────────────────

    @Test("알림이 켜진 방의 메뉴는 끄기, 꺼진 방은 켜기")
    func muteLabel() {
        #expect(chatMuteActionLabel(muted: false) == "알림 끄기")
        #expect(chatMuteActionLabel(muted: true) == "알림 켜기")
    }

    @Test("나가기 실패 문구 — 도착 뒤·끝난 방·그 밖")
    func leaveFailureMessages() {
        let arrived = PartyLeaveException(code: "ARRIVED_MEMBER_CANNOT_LEAVE", serverMessage: nil, httpStatus: 409)
        let closed = PartyLeaveException(code: "PARTY_CLOSED", serverMessage: nil, httpStatus: 409)
        struct Unknown: Error {}
        #expect(chatListLeaveFailureMessage(error: arrived) == "출발지에 도착했다고 누른 뒤에는 방에서 나갈 수 없어요")
        #expect(chatListLeaveFailureMessage(error: closed) == "이미 끝난 방이에요. 목록을 새로 불러와 주세요")
        #expect(chatListLeaveFailureMessage(error: Unknown()) == "나가지 못했어요. 잠시 뒤 다시 시도해 주세요")
    }

    @Test("채팅방 참여자가 아니라는 답은 이미 나간 것이다")
    func notParticipantMeansAlreadyOut() {
        #expect(isAlreadyOutOfChat(error: ChatException(code: "CHAT_NOT_PARTICIPANT", serverMessage: nil, httpStatus: 403)))
        #expect(!isAlreadyOutOfChat(error: ChatException(code: "CHAT_ROOM_NOT_FOUND", serverMessage: nil, httpStatus: 404)))
    }
}
