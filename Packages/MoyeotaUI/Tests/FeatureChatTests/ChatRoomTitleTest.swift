import MoyeotaDomain
import Testing
@testable import FeatureChat

/// 채팅방 이름은 **앱이 짓는다** — 서버가 방에 이름을 주지 않는다.
/// 예전 이름(출발지 → 도착지)은 역지오코딩된 전체 주소가 들어와 목록에서 방을 가려낼 수 없었다.
@Suite struct ChatRoomTitleTest {

    private func member(_ nickname: String, isMe: Bool = false, active: Bool = true) -> ChatMember {
        ChatMember(
            userId: nil,
            publicId: "public-\(nickname)",
            nickname: nickname,
            imageUrl: nil,
            active: active,
            isMe: isMe
        )
    }

    @Test("나를 뺀 한 명이면 그 사람 이름이 방 이름이다")
    func onePeerIsTitle() {
        let members = [member("스모크일"), member("스모크이", isMe: true)]
        #expect(chatRoomPeerTitle(members: members) == "스모크일")
    }

    @Test("둘이면 쉼표로 잇는다")
    func twoPeersJoinedByComma() {
        let members = [member("스모크일"), member("스모크삼"), member("나", isMe: true)]
        #expect(chatRoomPeerTitle(members: members) == "스모크일, 스모크삼")
    }

    /// 「첫 사람 외 N명」으로 줄이면 제목 옆 인원과 「외 2명 4명」으로 겹쳐 읽혔다 — 다 적고 넘치면 행이 줄인다.
    @Test("셋 이상도 이름을 모두 쉼표로 잇는다")
    func threePeersAllNamed() {
        let members = [
            member("스모크일"),
            member("스모크삼"),
            member("스모크사"),
            member("나", isMe: true),
        ]
        #expect(chatRoomPeerTitle(members: members) == "스모크일, 스모크삼, 스모크사")
    }

    @Test("나 혼자면 동승자 없음")
    func aloneIsNoPeer() {
        #expect(chatRoomPeerTitle(members: [member("나", isMe: true)]) == "동승자 없음")
    }

    @Test("방을 나간 사람은 이름에서 뺀다")
    func leftMemberIsExcluded() {
        let members = [
            member("남은사람"),
            member("나간사람", active: false),
            member("나", isMe: true),
        ]
        #expect(chatRoomPeerTitle(members: members) == "남은사람")
    }

    /// 전원이 나갔다고 「동승자 없음」이라 부르면, 대화 상대가 분명히 있었던 방의 이름이 사라진다.
    /// 남은 사람이 없을 때만 나간 사람을 되살려 쓴다.
    @Test("남은 사람이 없으면 나간 사람이라도 쓴다")
    func fallsBackToLeftMember() {
        let members = [member("나간사람", active: false), member("나", isMe: true)]
        #expect(chatRoomPeerTitle(members: members) == "나간사람")
    }

    @Test("닉네임이 빈 문자열이면 동승자로 적는다")
    func blankNicknameIsPeerFallback() {
        let members = [member(""), member("나", isMe: true)]
        #expect(chatRoomPeerTitle(members: members) == "동승자")
    }

    /// 정렬 키는 **마지막 활동 시각** — 마지막 메시지 시각, 없으면 방 개설 시각. 카카오톡식 최근 대화 순.
    @Test("마지막 메시지가 최근인 방이 방 id 와 무관하게 위로 온다")
    func recentMessageComesFirst() {
        let rooms = [
            myRoom(1, lastMessageAt: "2026-09-11T03:00:00Z"),
            myRoom(9, lastMessageAt: "2026-09-10T03:00:00Z"),
            myRoom(4, lastMessageAt: "2026-09-11T01:00:00Z"),
        ]
        #expect(sortedByDescendingSortKey(rooms).map(\.room.id) == [1, 4, 9])
    }

    @Test("메시지가 없는 새 방은 개설 시각으로 끼어든다")
    func newRoomUsesCreatedAt() {
        let rooms = [
            myRoom(1, lastMessageAt: "2026-09-11T03:00:00Z"),
            myRoom(2, createdAt: "2026-09-11T04:00:00Z"), // 방금 열린 방, 메시지 없음
            myRoom(3, lastMessageAt: "2026-09-11T02:00:00Z"),
        ]
        #expect(sortedByDescendingSortKey(rooms).map(\.room.id) == [2, 1, 3])
    }

    @Test("미리보기는 마지막 메시지이고 위치 공유는 사람 말로 바꾼다")
    func previewIsLastMessage() {
        let text = ChatRoomListItem(
            room: myRoom(1, lastMessageAt: "2026-09-11T03:00:00Z", content: "어디쯤이세요?"),
            peerTitle: "스모크일"
        )
        #expect(chatRoomSubtitle(item: text).preview == "어디쯤이세요?")

        let location = ChatRoomListItem(
            room: myRoom(1, lastMessageAt: "2026-09-11T03:00:00Z", content: "35.1,129.0", type: .location),
            peerTitle: "스모크일"
        )
        #expect(chatRoomSubtitle(item: location).preview == "위치를 공유했어요")
    }

    /// ★ 메시지가 있어도 경로가 남는다(오너 피드백 2026-11) — 예전엔 미리보기가 경로 자리를 차지해
    /// 대화가 오간 방은 어디서 어디로 가는 방인지 목록에서 알 수 없었다.
    @Test("메시지가 있어도 경로 한 줄이 함께 보인다")
    func routeStaysWithMessages() {
        let talked = ChatRoomListItem(
            room: myRoom(1, lastMessageAt: "2026-09-11T03:00:00Z", content: "어디쯤이세요?"),
            peerTitle: "스모크일"
        )

        #expect(
            chatRoomSubtitle(item: talked)
                == ChatRoomSubtitle(route: RouteLine(departure: "출발", destination: "도착"), preview: "어디쯤이세요?")
        )
    }

    @Test("메시지가 없으면 경로만 쓴다")
    func noMessageIsRouteOnly() {
        #expect(
            chatRoomSubtitle(item: ChatRoomListItem(room: myRoom(1), peerTitle: "스모크일"))
                == ChatRoomSubtitle(route: RouteLine(departure: "출발", destination: "도착"), preview: nil)
        )
    }

    /// 닫힌 방의 「종료 · 」는 경로 줄이 한 번만 맡는다 — 미리보기에까지 붙으면 한 행에 두 번이다.
    @Test("닫힌 방은 경로 줄에만 종료를 붙인다")
    func closedRoomMarksRouteOnly() {
        let closed = ChatRoomListItem(
            room: myRoom(1, lastMessageAt: "2026-09-11T03:00:00Z", content: "감사합니다", status: .closed),
            peerTitle: "스모크일"
        )

        #expect(
            chatRoomSubtitle(item: closed)
                == ChatRoomSubtitle(route: RouteLine(departure: "출발", destination: "도착", closed: true), preview: "감사합니다")
        )
    }

    /// 합승이 끝난 방(FINISHED·CANCELED)도 닫힌 방과 같이 「종료」다 — 대화는 계속돼도 탑승은 끝났다.
    @Test("합승이 끝난 방도 경로 줄에 종료를 붙인다", arguments: [ChatRoomStatus.finished, .canceled])
    func endedRoomsAreMarked(status: ChatRoomStatus) {
        #expect(chatRoomSubtitle(item: ChatRoomListItem(room: myRoom(1, status: status), peerTitle: "스모크일")).route?.closed == true)
    }

    /// ★ 참여자를 못 받은 방은 **제목이 이미 경로**다(「출발 → 도착」) — 그 아래에 경로를 또 쓰면
    /// 같은 말이 두 번이다. 그때 경로 줄은 없고, 미리보기가 없으면 방 상태를 쓴다.
    @Test("제목이 경로로 떨어진 방은 경로를 되풀이하지 않는다")
    func routeTitleDoesNotRepeatRoute() {
        let noPeers = ChatRoomListItem(room: myRoom(1), peerTitle: nil)

        #expect(chatRoomListTitle(item: noPeers) == "출발 → 도착")
        #expect(chatRoomSubtitle(item: noPeers) == ChatRoomSubtitle(route: nil, preview: "진행 중"))
        #expect(
            chatRoomSubtitle(item: ChatRoomListItem(room: myRoom(1, status: .closed), peerTitle: nil))
                == ChatRoomSubtitle(route: nil, preview: "종료된 방")
        )
        #expect(
            chatRoomSubtitle(
                item: ChatRoomListItem(
                    room: myRoom(1, lastMessageAt: "2026-09-11T03:00:00Z", content: "감사합니다", status: .closed),
                    peerTitle: nil
                )
            ) == ChatRoomSubtitle(route: nil, preview: "종료 · 감사합니다")
        )
    }

    @Test("경로 두 장소가 다 들어가면 그대로 쓴다")
    func routeFitsAsIs() {
        let widths = splitRouteWidths(available: 100, departure: 40, destination: 50)
        #expect(widths.departure == 40 && widths.destination == 50)
    }

    /// ★ 출발지가 길어도 도착지는 다 보인다 — 한 줄을 끝에서 줄이던 때는 도착지가 통째로 사라졌다.
    @Test("한쪽이 짧으면 짧은 쪽은 다 보이고 긴 쪽이 남은 폭을 쓴다")
    func shortSideKeepsFullWidth() {
        let longDeparture = splitRouteWidths(available: 100, departure: 300, destination: 30)
        #expect(longDeparture.departure == 70 && longDeparture.destination == 30)
        let longDestination = splitRouteWidths(available: 100, departure: 30, destination: 300)
        #expect(longDestination.departure == 30 && longDestination.destination == 70)
    }

    @Test("둘 다 길면 반씩 나눠 양쪽 앞부분이 남는다")
    func bothLongSplitInHalf() {
        let widths = splitRouteWidths(available: 101, departure: 300, destination: 200)
        #expect(widths.departure == 50.5 && widths.destination == 50.5)
    }

    @Test("쓸 폭이 없으면 둘 다 0이다")
    func noRoomIsZero() {
        let widths = splitRouteWidths(available: 0, departure: 30, destination: 30)
        #expect(widths.departure == 0 && widths.destination == 0)
    }

    @Test("참여자 이름이 있으면 그것이 제목이다")
    func peerNameIsTitle() {
        #expect(chatRoomListTitle(item: ChatRoomListItem(room: myRoom(1), peerTitle: "스모크일")) == "스모크일")
    }

    private func myRoom(
        _ id: Int64,
        createdAt: String = "2026-09-09T07:33:00Z",
        lastMessageAt: String? = nil,
        content: String = "안녕하세요",
        type: ChatMessageType = .text,
        status: ChatRoomStatus = .active
    ) -> MyChatRoom {
        MyChatRoom(
            room: ChatRoom(
                id: id,
                partyId: id + 100,
                departure: "출발",
                destination: "도착",
                createdAt: createdAt,
                status: status
            ),
            membership: ChatRoomMembership(
                chatRoomId: id,
                lastReadMessageId: nil,
                notificationMuted: false,
                joinedAt: createdAt,
                lastMessage: lastMessageAt.map {
                    ChatLastMessage(id: id * 10, senderPublicId: "peer", content: content, type: type, createdAt: $0, isMine: false)
                }
            )
        )
    }
}
