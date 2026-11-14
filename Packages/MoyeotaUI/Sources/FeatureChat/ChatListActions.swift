import MoyeotaDesignSystem
import MoyeotaDomain
import SwiftUI

/// 채팅 목록에서 길게 누른 방의 「나가기」가 **무엇에서** 나가는가.
///
/// 서버에는 나가는 길이 둘이다 — 채팅방만 나가는 `DELETE /chat-rooms/{id}/users` 와 동승에서 나가는
/// `DELETE /matching/leave/{partyId}`. 진행 중인 방에서 채팅방만 나가면 동승은 남은 채 대화로 돌아올 길이
/// 없다(채팅방 안 메뉴가 그 방에서 「나가기」를 감추는 이유다). 그래서 진행 중인 방의 「나가기」는 **동승에서**
/// 나가고, 채팅방은 서버가 함께 정리한다(`PartyMemberLeftEvent` → 채팅방 멤버 정리).
///
/// 채팅방 상태로는 가를 수 없다 — 서버가 끝난 방의 채팅방을 닫지 않아(백엔드 #335) 목록의 `status` 가
/// 늘 `ACTIVE` 다. 그래서 방 상세를 읽어 판정한다(`chatLeavePlan`).
enum ChatLeavePlan: Equatable, Sendable {
    /// 끝났거나 취소된 방, 이미 내가 빠진 방, 찾을 수 없는 방 — 채팅방만 나가 목록에서 치운다
    case chatOnly(chatRoomId: Int64)

    /// 진행 중이고 도착 전 — 동승에서 나간다(develop: 도착을 누르기 전이면 어떤 방이든 나갈 수 있다).
    case leaveParty(LeaveParty)

    /// 도착을 누른 뒤 — 서버가 409 `ARRIVED_MEMBER_CANNOT_LEAVE` 로 막는다. 누르기 전에 말한다
    case blocked

    /// - `alone`: 나 혼자인 방 — 나가는 순간 방이 닫힌다(`CANCELED`)
    /// - `cancelsMeeting`: 약속이 정해진 실시간 방에 둘뿐 — 남은 한 명만 남아 서버가 방을 취소한다
    /// - `capacity`·`memberCount`: 21 의 「그만 찾기」와 같은 `matchCanceled` 이벤트를 남기려고 들고 간다
    struct LeaveParty: Equatable, Sendable {
        var chatRoomId: Int64
        var partyId: Int64
        var isHost: Bool
        var alone: Bool
        var cancelsMeeting: Bool
        var capacity: Int
        var memberCount: Int
    }
}

/// 방 상세(`ride`)로 「나가기」의 뜻을 정한다. 방을 못 찾았으면(`ride` nil) 채팅방만 정리한다 —
/// 방이 없는데 채팅방이 목록에 남아 있다면 치우는 것 말고 할 일이 없다.
func chatLeavePlan(chatRoomId: Int64, ride: Ride?) -> ChatLeavePlan {
    guard let ride else { return .chatOnly(chatRoomId: chatRoomId) }
    if ride.status == .completed || ride.status == .canceled { return .chatOnly(chatRoomId: chatRoomId) }
    guard let me = ride.members.first(where: \.isMe) else { return .chatOnly(chatRoomId: chatRoomId) }
    if me.hasArrived { return .blocked }
    guard let partyId = Int64(ride.id) else { return .chatOnly(chatRoomId: chatRoomId) }
    return .leaveParty(ChatLeavePlan.LeaveParty(
        chatRoomId: chatRoomId,
        partyId: partyId,
        isHost: ride.isHostedByMe,
        alone: ride.members.count == 1,
        cancelsMeeting: ride.status == .matched && ride.members.count == 2,
        capacity: ride.capacity,
        memberCount: ride.members.count
    ))
}

/// 나가기 확인창 문구. `dismissText` 가 nil 이면 버튼이 하나다(막힌 경우)
struct ChatLeaveDialogCopy: Equatable {
    var title: String
    var body: String
    var confirmText: String
    var dismissText: String?
    var destructive: Bool
}

private let LEAVE_PARTY_BODY = "동승에서 빠지고 이 채팅방도 함께 사라져요"
private let ARRIVED_CANNOT_LEAVE = "출발지에 도착했다고 누른 뒤에는 방에서 나갈 수 없어요"

func chatLeaveDialog(plan: ChatLeavePlan) -> ChatLeaveDialogCopy {
    switch plan {
    case .chatOnly:
        return ChatLeaveDialogCopy(
            title: "채팅방을 나갈까요?",
            body: "나가면 이 대화가 목록에서 사라지고 다시 들어올 수 없어요",
            confirmText: "나가기",
            dismissText: "취소",
            destructive: true
        )
    case .leaveParty(let leave):
        let body: String
        if leave.alone {
            body = "혼자 있는 방이라 나가면 방이 닫혀요"
        } else if leave.cancelsMeeting {
            body = "\(LEAVE_PARTY_BODY)\n남은 분 혼자가 되어 약속이 취소돼요"
        } else if leave.isHost {
            body = "\(LEAVE_PARTY_BODY)\n방장은 남은 분 중 먼저 들어온 분에게 넘어가요"
        } else {
            body = LEAVE_PARTY_BODY
        }
        return ChatLeaveDialogCopy(title: "방에서 나갈까요?", body: body, confirmText: "나가기", dismissText: "취소", destructive: true)
    case .blocked:
        return ChatLeaveDialogCopy(
            title: "지금은 나갈 수 없어요",
            body: ARRIVED_CANNOT_LEAVE,
            confirmText: "확인",
            dismissText: nil,
            destructive: false
        )
    }
}

/// 길게 누르기 메뉴의 알림 항목 — 지금 상태의 **반대**를 적는다
func chatMuteActionLabel(muted: Bool) -> String { muted ? "알림 켜기" : "알림 끄기" }

/// 나가기 실패 뒤 다시 할 일 — 판정과 요청 사이에 방 상태가 바뀐 경우다
enum ChatLeaveRetry: Equatable {
    /// 다시 할 것 없음 — 문구만 보여 준다
    case none
    /// 409 `PARTY_CLOSED` — 그사이 방이 끝났다. 다시 판정하면 「채팅방만 나가기」가 된다
    case replan
    /// 409 `ARRIVED_MEMBER_CANNOT_LEAVE` — 그사이 도착을 눌렀다. 막힌 이유를 확인창으로 보여 준다
    case blocked
}

/// 동승 나가기(`.leaveParty`)의 실패만 다시 판정한다. 서버 코드 문자열은 develop 기준이다 —
/// 도메인의 `PartyLeaveException` 에는 아직 이 두 코드의 뜻 플래그가 없다.
func chatListLeaveRetry(plan: ChatLeavePlan, error: any Error) -> ChatLeaveRetry {
    guard case .leaveParty = plan else { return .none }
    switch (error as? PartyLeaveException)?.code {
    case "PARTY_CLOSED": return .replan
    case "ARRIVED_MEMBER_CANNOT_LEAVE": return .blocked
    default: return .none
    }
}

/// 동승 나가기 실패 문구. 다시 판정하는 두 코드(`chatListLeaveRetry`)는 여기까지 오지 않는다
let LEAVE_PARTY_FAILED_MESSAGE = "나가지 못했어요. 잠시 뒤 다시 시도해 주세요"

/// 채팅방 나가기가 **이미 나간 것**인가 — 403(참여자 아님)과 404(채팅방 없음). 사용자가 할 일이 같아 성공으로 친다.
/// 404 를 빼면 채팅방 상세가 404 라 「채팅방만 나가기」로 판정된 방이 영영 목록에서 안 빠진다.
func isAlreadyOutOfChat(error: any Error) -> Bool {
    guard let chat = error as? ChatException else { return false }
    return chat.isNotParticipant || chat.isRoomNotFound
}

/// 목록 행 제목 오른쪽의 「알림 꺼짐」 표시 — 켜진 방은 아무것도 붙이지 않는다. VoiceOver 에도 읽힌다
struct MutedMark: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: MoyeotaSpacing.Xs)
            // 자리표시 회색(2.6:1)이 아니라 TextMute(4.8:1) — 장식이 아니라 상태를 알리는 표시라 3:1 을 넘겨야 한다
            BellOffIcon(size: MoyeotaIconSize.Sm, tint: MoyeotaColor.TextMute)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("알림 꺼짐")
    }
}
