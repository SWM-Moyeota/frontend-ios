@testable import FeatureChat
import Foundation
import MoyeotaDomain
import Testing

// 채팅 목록 길게 누르기 — 메뉴(알림 끄기/켜기 · 나가기) → 확인창 → 요청.
// 메뉴를 여는 순간 방 상태를 읽어 「나가기」의 뜻을 정해 둔다(`ChatLeavePlan`). 진행 중인 방은 동승에서,
// 끝난 방은 채팅방에서만 나간다.

private struct TestFailure: Error {}

private final class AnalyticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [AnalyticsEvent] = []
    func add(_ event: AnalyticsEvent) { lock.withLock { entries.append(event) } }
    var seen: [AnalyticsEvent] { lock.withLock { entries } }
}

private enum AnalyticsCapture {
    @TaskLocal static var current: AnalyticsRecorder?
}

private func myRoom(_ chatRoomId: Int64, muted: Bool = false) -> MyChatRoom {
    MyChatRoom(
        room: ChatRoom(
            id: chatRoomId, partyId: 0, departure: "강남역", destination: "서울시청",
            createdAt: "2026-11-13T07:00:0\(chatRoomId % 10)Z", status: .active
        ),
        membership: ChatRoomMembership(
            chatRoomId: chatRoomId, lastReadMessageId: nil, notificationMuted: muted, joinedAt: "2026-11-13T07:00:00Z",
            members: [
                ChatMember(userId: nil, publicId: "p-me", nickname: "나", imageUrl: nil, active: true, isMe: true),
                ChatMember(userId: nil, publicId: "p-b", nickname: "상대", imageUrl: nil, active: true, isMe: false),
            ]
        )
    )
}

private func item(_ chatRoomId: Int64) -> ChatRoomListItem {
    ChatRoomListItem(room: myRoom(chatRoomId), peerTitle: "상대")
}

private func member(_ id: String, isMe: Bool = false, isHost: Bool = false, arrived: Bool = false) -> User {
    User(id: id, nickname: id, verifiedLabel: "", rating: 0, rideCount: 0, isMe: isMe, isHost: isHost, hasArrived: arrived)
}

private func me(arrived: Bool = false) -> User { member("me", isMe: true, arrived: arrived) }
private func other(_ id: String = "b") -> User { member(id, isHost: id == "b") }

private func ride(_ status: RideStatus, _ members: User...) -> Ride {
    Ride(
        id: "42", origin: "강남역", destination: "서울시청", departureLabel: "지금 출발", capacity: 3,
        members: members, farePerPerson: 0, totalFare: 0, status: status, isConfirmed: status == .matched
    )
}

/// 목록 두 방(7·8). 채팅방 상세는 방 42 를 가리킨다
private final class FakeListRepository: ChatRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _leftChatRooms: [Int64] = []
    private var _muteCalls: [(Int64, Bool)] = []
    var getRoomError: (any Error)?
    var leaveError: (any Error)?
    var muteError: (any Error)?
    var beforeGetRoom: @Sendable () async -> Void = {}

    var leftChatRooms: [Int64] { lock.withLock { _leftChatRooms } }
    var muteCalls: [(Int64, Bool)] { lock.withLock { _muteCalls } }

    func getMyChatRooms() async throws -> [MyChatRoom] { [myRoom(8), myRoom(7)] }

    func getChatRoom(chatRoomId: Int64) async throws -> ChatRoom {
        await beforeGetRoom()
        if let getRoomError { throw getRoomError }
        var room = myRoom(chatRoomId).room
        room.partyId = 42
        return room
    }

    func joinChatRoom(chatRoomId: Int64) async throws {}

    func leaveChatRoom(chatRoomId: Int64) async throws {
        if let leaveError { throw leaveError }
        lock.withLock { _leftChatRooms.append(chatRoomId) }
    }

    func getChatRoomMembers(chatRoomId: Int64) async throws -> [ChatMember] { [] }

    func setNotificationMuted(chatRoomId: Int64, muted: Bool) async throws {
        if let muteError { throw muteError }
        lock.withLock { _muteCalls.append((chatRoomId, muted)) }
    }

    func markAsRead(chatRoomId: Int64, readMessageId: Int64) async throws {}
    func getMessages(chatRoomId: Int64, cursor: Int64?, size: Int) async throws -> ChatMessagePage {
        ChatMessagePage(messages: [], nextCursor: nil, hasNext: false)
    }
    func observeRoom(chatRoomId: Int64) -> AsyncStream<ChatRealtimeEvent> { AsyncStream { $0.finish() } }
    func getMessagesAfter(chatRoomId: Int64, cursor: Int64, size: Int) async throws -> ChatMessagePage {
        ChatMessagePage(messages: [], nextCursor: nil, hasNext: false)
    }
    func sendMessage(chatRoomId: Int64, content: String) async throws -> ChatMessage { throw TestFailure() }
    func deleteMessage(chatRoomId: Int64, messageId: Int64) async throws {}
    func searchMessages(chatRoomId: Int64, keyword: String, cursor: Int64?, size: Int) async throws -> ChatMessagePage {
        ChatMessagePage(messages: [], nextCursor: nil, hasNext: false)
    }
    func reportMessage(chatRoomId: Int64, chatMessageId: Int64, reason: ChatReportReason, description: String?) async throws {}
}

/// 방 상세·나가기만 쓰는 가짜 저장소. 채팅 탭 상태를 만드는 다른 테스트도 빈 값으로 쓴다
final class FakeChatListRideRepository: RideRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _leftParties: [Int64] = []
    var detail: @Sendable () throws -> Ride = { throw TestFailure() }
    var leaveError: (any Error)?
    var beforeLeave: @Sendable () -> Void = {}

    var leftParties: [Int64] { lock.withLock { _leftParties } }

    func getPartyDetail(partyId: Int64) async throws -> Ride { try detail() }
    func leaveParty(partyId: Int64) async throws {
        beforeLeave()
        if let leaveError { throw leaveError }
        lock.withLock { _leftParties.append(partyId) }
    }

    func joinParty(partyId: Int64) async throws -> PartyStatus { throw TestFailure() }
    func getNearbyParties() -> [Ride] { [] }
    func getParties() async throws -> [Ride] { throw TestFailure() }
    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] { throw TestFailure() }
    func getPartyDetailWithVersion(partyId: Int64) async throws -> PartyDetail { throw TestFailure() }
    func findRealtimeCandidates(departureLat: Double, departureLng: Double, destinationLat: Double, destinationLng: Double) async throws -> [MatchCandidate] { throw TestFailure() }
    func createParty(request: NewParty) async throws -> Ride { throw TestFailure() }
    func finishParty(partyId: Int64) async throws { throw TestFailure() }
    func previewRoute(departureLat: Double, departureLng: Double, destinationLat: Double, destinationLng: Double) async throws -> RouteEstimate { throw TestFailure() }
    func createReservation(request: NewReservation) async throws -> Ride { throw TestFailure() }
    func getReservations(from: String, to: String) async throws -> [Ride] { [] }
    func getReservationsSoon(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] { [] }
    func searchReservations(departureLat: Double, departureLng: Double, date: String, destination: ReservationDestination?) async throws -> [ReservationSearchResult] { [] }
    func confirmMeeting(partyId: Int64, departureAt: String) async throws { throw TestFailure() }
    func arriveAtDeparture(partyId: Int64, latitude: Double, longitude: Double) async throws { throw TestFailure() }
    func departParty(partyId: Int64) async throws { throw TestFailure() }
}

@MainActor
@Suite(.serialized)
final class ChatListMenuTest {
    private let chat = FakeListRepository()
    private let rides = FakeChatListRideRepository()
    private let recorder = AnalyticsRecorder()

    init() {
        Analytics.install { event in AnalyticsCapture.current?.add(event) }
    }

    deinit {
        Analytics.reset()
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func loaded() async -> ChatListViewModel {
        let viewModel = ChatListViewModel(repository: chat, rideRepository: rides)
        viewModel.refresh()
        #expect(await eventually { if case .success = viewModel.uiState { true } else { false } })
        return viewModel
    }

    private func roomIds(_ viewModel: ChatListViewModel) -> [Int64] {
        guard case .success(let rooms) = viewModel.uiState else { return [] }
        return rooms.map(\.room.room.id)
    }

    private func isConfirm(_ viewModel: ChatListViewModel) -> Bool {
        if case .confirm = viewModel.action { true } else { false }
    }

    /// iOS 메뉴의 「나가기」 → (판정) → 확인
    private func leave(_ viewModel: ChatListViewModel, _ target: ChatRoomListItem) async {
        viewModel.openMenu(item: target)
        viewModel.requestLeave()
        #expect(await eventually { self.isConfirm(viewModel) }, "확인창이 떠야 한다")
        viewModel.confirmLeave()
        #expect(await eventually { !self.isLeaving(viewModel) }, "나가기 요청이 끝나야 한다")
    }

    private func isLeaving(_ viewModel: ChatListViewModel) -> Bool {
        if case .leaving = viewModel.action { true } else { false }
    }

    @Test("메뉴를 열면 방 상태를 미리 읽어 나가기가 바로 확인창으로 간다")
    func prefetchedPlanGoesStraightToConfirm() async {
        rides.detail = { ride(.recruiting, me(), other()) }
        let viewModel = await loaded()

        viewModel.openMenu(item: item(7))
        #expect(await eventually {
            if case .menu(let menu) = viewModel.action { menu.plan != nil } else { false }
        })
        viewModel.requestLeave()

        guard case .confirm(_, let plan) = viewModel.action, case .leaveParty = plan else {
            Issue.record("동승 나가기 확인창이어야 한다")
            return
        }
    }

    @Test("판정 전에 나가기를 누르면 판정이 끝나는 대로 확인창으로 넘어간다")
    func leaveTappedBeforePlanAdvancesLater() async {
        rides.detail = { ride(.completed, me(arrived: true), other()) }
        chat.beforeGetRoom = { try? await Task.sleep(for: .milliseconds(100)) }
        let viewModel = await loaded()

        viewModel.openMenu(item: item(7))
        viewModel.requestLeave()
        if case .menu(let menu) = viewModel.action {
            #expect(menu.leaveTapped)
        } else {
            Issue.record("아직 메뉴 상태여야 한다")
        }

        #expect(await eventually { viewModel.action == .confirm(item: item(7), plan: .chatOnly(chatRoomId: 7)) })
    }

    @Test("진행 중인 방은 동승에서 나가고 목록에서 빠진다")
    func openRideLeavesParty() async {
        rides.detail = { ride(.matched, me(), other(), other("c")) }
        let viewModel = await loaded()
        var left: [ChatLeavePlan] = []
        viewModel.onLeft = { left.append($0) }

        await AnalyticsCapture.$current.withValue(recorder) {
            await leave(viewModel, item(7))
        }

        #expect(rides.leftParties == [42])
        #expect(chat.leftChatRooms.isEmpty)
        #expect(roomIds(viewModel) == [8])
        guard left.count == 1, case .leaveParty(let plan) = left[0] else {
            Issue.record("동승 나가기 결과가 한 번 나가야 한다: \(left)")
            return
        }
        #expect(plan.partyId == 42)
        #expect(recorder.seen.filter { if case .matchCanceled = $0 { true } else { false } }.count == 1)
        #expect(viewModel.action == nil)
    }

    @Test("끝난 방은 채팅방만 나간다")
    func finishedRideLeavesChatOnly() async {
        rides.detail = { ride(.completed, me(arrived: true), other()) }
        let viewModel = await loaded()

        await leave(viewModel, item(7))

        #expect(chat.leftChatRooms == [7])
        #expect(rides.leftParties.isEmpty)
        #expect(roomIds(viewModel) == [8])
    }

    @Test("채팅방 상세가 403 이면 채팅방만 정리한다")
    func forbiddenChatRoomLeavesChatOnly() async {
        chat.getRoomError = ChatException(code: "CHAT_NOT_PARTY_MEMBER", serverMessage: nil, httpStatus: 403)
        let viewModel = await loaded()

        await leave(viewModel, item(7))

        #expect(chat.leftChatRooms == [7])
    }

    @Test("이미 나간 채팅방이라는 답은 성공으로 친다")
    func alreadyOutCountsAsSuccess() async {
        rides.detail = { ride(.canceled, me()) }
        chat.leaveError = ChatException(code: "CHAT_NOT_PARTICIPANT", serverMessage: nil, httpStatus: 403)
        let viewModel = await loaded()

        await leave(viewModel, item(7))

        #expect(roomIds(viewModel) == [8])
        #expect(viewModel.notice == nil)
    }

    @Test("도착한 뒤에는 확인창이 이유만 알리고 아무 요청도 보내지 않는다")
    func arrivedSendsNothing() async {
        rides.detail = { ride(.matched, me(arrived: true), other()) }
        let viewModel = await loaded()

        await leave(viewModel, item(7))

        #expect(rides.leftParties.isEmpty)
        #expect(chat.leftChatRooms.isEmpty)
        #expect(roomIds(viewModel) == [8, 7])
    }

    @Test("나가기가 실패하면 목록에 남기고 이유를 알린다")
    func failedLeaveKeepsRoom() async {
        rides.detail = { ride(.recruiting, me(), other()) }
        rides.leaveError = TestFailure()
        let viewModel = await loaded()

        await leave(viewModel, item(7))

        #expect(roomIds(viewModel) == [8, 7])
        #expect(viewModel.notice == LEAVE_PARTY_FAILED_MESSAGE)
        #expect(viewModel.action == nil)
    }

    @Test("그사이 방이 끝났으면 다시 판정해 채팅방만 나가기 확인창으로 간다")
    func closedMeanwhileReplansToChatOnly() async {
        let finished = LockedFlag(false)
        rides.detail = { ride(finished.value ? .completed : .recruiting, me(), other()) }
        rides.leaveError = PartyLeaveException(code: "PARTY_CLOSED", serverMessage: nil, httpStatus: 409)
        let viewModel = await loaded()
        rides.beforeLeave = { finished.value = true }

        await leave(viewModel, item(7))

        #expect(await eventually { viewModel.action == .confirm(item: item(7), plan: .chatOnly(chatRoomId: 7)) })
        #expect(viewModel.notice == "그사이 방이 끝났어요. 채팅방만 나갈지 다시 확인해 주세요")
        #expect(chat.leftChatRooms.isEmpty)
    }

    @Test("그사이 도착을 눌렀으면 막힌 이유를 확인창으로 보여 준다")
    func arrivedMeanwhileShowsBlocked() async {
        rides.detail = { ride(.matched, me(), other(), other("c")) }
        rides.leaveError = PartyLeaveException(code: "ARRIVED_MEMBER_CANNOT_LEAVE", serverMessage: nil, httpStatus: 409)
        let viewModel = await loaded()

        await leave(viewModel, item(7))

        #expect(viewModel.action == .confirm(item: item(7), plan: .blocked))
    }

    @Test("채팅방이 없다는 답도 이미 나간 것으로 친다")
    func roomNotFoundCountsAsLeft() async {
        chat.getRoomError = ChatException(code: "CHAT_ROOM_NOT_FOUND", serverMessage: nil, httpStatus: 404)
        chat.leaveError = ChatException(code: "CHAT_ROOM_NOT_FOUND", serverMessage: nil, httpStatus: 404)
        let viewModel = await loaded()

        await leave(viewModel, item(7))

        #expect(roomIds(viewModel) == [8])
        #expect(viewModel.notice == nil)
    }

    /// iOS 메뉴는 「나가기」를 누른 뒤에야 판정한다 — 그 판정이 실패하는 길이 iOS 에서 실제로 닿는 실패다
    @Test("나가기를 누른 뒤 판정이 실패하면 메뉴를 닫고 알린다")
    func planFailureAfterTapClosesAndNotifies() async {
        let viewModel = await loaded()

        viewModel.openMenu(item: item(7))
        viewModel.requestLeave()

        #expect(await eventually { viewModel.notice == "방 상태를 확인하지 못했어요. 잠시 뒤 다시 시도해 주세요" })
        #expect(viewModel.action == nil)
    }

    @Test("알림을 바꾸면 앞서 떠 있던 실패 안내를 지운다")
    func muteClearsOldNotice() async {
        rides.detail = { ride(.recruiting, me(), other()) }
        rides.leaveError = TestFailure()
        let viewModel = await loaded()
        await leave(viewModel, item(7))
        #expect(viewModel.notice != nil)

        viewModel.toggleMuted(item: item(8))

        #expect(viewModel.notice == nil)
    }

    @Test("방 상태를 못 읽었으면 나가기를 누를 때 다시 읽는다")
    func failedPlanRetriesOnLeave() async {
        let fail = LockedFlag(true)
        rides.detail = { if fail.value { throw TestFailure() } else { return ride(.recruiting, me(), other()) } }
        let viewModel = await loaded()

        viewModel.openMenu(item: item(7))
        #expect(await eventually { if case .menu(let menu) = viewModel.action { menu.planFailed } else { false } })

        fail.value = false
        viewModel.requestLeave()
        #expect(await eventually { self.isConfirm(viewModel) })
    }

    @Test("알림 끄기는 바로 목록에 그려지고 서버에 간다")
    func muteIsOptimistic() async {
        let viewModel = await loaded()

        viewModel.toggleMuted(item: item(7))
        guard case .success(let rooms) = viewModel.uiState else { return }
        #expect(rooms.first { $0.room.room.id == 7 }?.room.membership.notificationMuted == true)

        #expect(await eventually { self.chat.muteCalls.count == 1 })
        #expect(chat.muteCalls.first.map { $0.0 == 7 && $0.1 } == true)
    }

    @Test("알림 설정이 실패하면 되돌리고 알린다")
    func failedMuteRollsBack() async {
        chat.muteError = TestFailure()
        let viewModel = await loaded()

        viewModel.toggleMuted(item: item(7))

        #expect(await eventually { viewModel.notice == "알림 설정을 바꾸지 못했어요" })
        guard case .success(let rooms) = viewModel.uiState else { return }
        #expect(rooms.first { $0.room.room.id == 7 }?.room.membership.notificationMuted == false)
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool
    init(_ value: Bool) { stored = value }
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
