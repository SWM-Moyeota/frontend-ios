import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

let ChatListScrollKey = "chat.list"

/// 24 · 채팅 목록 — 내가 속한 채팅방(GET /chat-rooms/me)
///
/// 이동:
/// - 방 행 탭 → 24 채팅방 (onRoomClick)
/// - 방 행 길게 누르기 → 알림 끄기/켜기 · 나가기 (onToggleMuted · onLeave)
/// - 하단탭 → 14/17/35 (onTabSelect)
///
/// 제목은 **참여자 닉네임**(`ChatRoomListItem.peerTitle` · `chatRoomPeerTitle`), 그 아래에 **경로 한 줄**과
/// **마지막 메시지** 한 줄(`chatRoomSubtitle`), 우측에 마지막 메시지 시각과 안읽음 점.
/// 정렬은 Route 가 이미 마친 상태로 넘어온다(`chatRoomSortKey` — 마지막 활동 시각 내림차순).
/// 알림을 끈 방은 제목 옆에 사선 그은 종이 붙는다(`MutedMark`) — 켜진 방은 아무것도 붙지 않는다.
///
/// 길게 누르기 메뉴는 **iOS 기본 메뉴**(`contextMenu`)다 — 원본은 아래쪽 카드(`ChatRoomActionSheet`)를
/// 그리지만, iOS 사용자는 길게 누르면 행이 떠오르며 메뉴가 붙는 모양에 익숙하다(docs/IOS-DIFFERENCES.md).
///
/// - Parameter notice: 길게 누르기 메뉴의 동작이 실패했을 때 목록 위에 띄우는 한 줄
public struct ChatListScreen: View {
    private let rooms: [ChatRoomListItem]
    private let notice: String?
    private let onRoomClick: (MyChatRoom) -> Void
    private let onToggleMuted: (ChatRoomListItem) -> Void
    private let onLeave: (ChatRoomListItem) -> Void
    private let onTabSelect: (MoyeotaTab) -> Void

    public init(
        rooms: [ChatRoomListItem] = [],
        notice: String? = nil,
        onRoomClick: @escaping (MyChatRoom) -> Void = { _ in },
        onToggleMuted: @escaping (ChatRoomListItem) -> Void = { _ in },
        onLeave: @escaping (ChatRoomListItem) -> Void = { _ in },
        onTabSelect: @escaping (MoyeotaTab) -> Void = { _ in }
    ) {
        self.rooms = rooms
        self.notice = notice
        self.onRoomClick = onRoomClick
        self.onToggleMuted = onToggleMuted
        self.onLeave = onLeave
        self.onTabSelect = onTabSelect
    }

    // 흰 바탕 위 꽉 찬 행 목록(디자인 QA C1). 예전엔 회색 화면 위에 그림자 진 큰 카드 하나를 띄우고 그 안에
    // 행을 넣었다 — 카드가 행을 한 번 더 감싸 목록이 "판 위의 판"으로 보였다. 메신저 목록의 관습대로 행이
    // 화면 폭을 다 쓰고, 행 사이는 글 시작선에 맞춘 얇은 선 하나로 나눈다.
    public var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            MoyeotaTabHeader(title: "채팅")
            // 스크롤 밖 머리 아래에 둔다 — 아래쪽 행에서 메뉴를 썼어도 보이고, VoiceOver 가 바로 읽는다
            if let notice {
                NoticeBanner(kind: .error, text: notice)
                    .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                    .padding(.vertical, MoyeotaSpacing.Xs)
                    .task(id: notice) { AccessibilityNotification.Announcement(notice).post() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: MoyeotaSpacing.Xs)
                    if rooms.isEmpty {
                        Text("아직 참여 중인 채팅방이 없어요. 동승에 합류하면 채팅방이 열려요")
                            .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                            .padding(.vertical, MoyeotaSpacing.Lg)
                    } else {
                        ForEach(Array(rooms.enumerated()), id: \.offset) { index, item in
                            ChatRoomRow(item: item, onClick: { onRoomClick(item.room) })
                                .contextMenu {
                                    let muted = item.room.membership.notificationMuted
                                    Button {
                                        onToggleMuted(item)
                                    } label: {
                                        Label(chatMuteActionLabel(muted: muted), systemImage: muted ? "bell" : "bell.slash")
                                    }
                                    Button(role: .destructive) {
                                        onLeave(item)
                                    } label: {
                                        Label("나가기", systemImage: "rectangle.portrait.and.arrow.right")
                                    }
                                }
                                // VoiceOver 는 길게 누르기 대신 동작 목록으로 같은 두 항목을 고른다(원본 `onLongClickLabel` 자리)
                                .accessibilityAction(named: chatMuteActionLabel(muted: item.room.membership.notificationMuted)) {
                                    onToggleMuted(item)
                                }
                                .accessibilityAction(named: "나가기") { onLeave(item) }
                            if index != rooms.count - 1 {
                                // 글 시작선(여백 16 + 아바타 48 + 간격 12)에 맞춘다 — 아바타 열은 끊김 없이 이어진다
                                HorizontalDivider(color: MoyeotaColor.Hairline)
                                    .padding(.leading, ChatRowTextStart)
                            }
                        }
                    }
                    Spacer().frame(height: MoyeotaSpacing.Md)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 원본 `rememberScrollState` 는 저장 상태라 탭을 다녀와도 읽던 자리가 남는다
                .savedScrollOffset(ChatListScrollKey)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            MoyeotaBottomBar(selected: .chat, onSelect: onTabSelect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
    }
}

/// 행 아바타 지름 — 40 → 48(디자인 QA C1). 부제가 두 줄인 행(약 76)에서도 얼굴이 작아 보이지 않게
private let ChatRowAvatarSize: CGFloat = 48

/// 행 글 묶음이 시작하는 x — 구분선도 여기서 시작한다
private let ChatRowTextStart: CGFloat = MoyeotaSpacing.ScreenGutter + ChatRowAvatarSize + MoyeotaSpacing.Sm

/// 목록 행에서 제목 아래 오는 두 줄 — 경로와 마지막 메시지.
///
/// ### 경로는 메시지가 있어도 늘 보인다 (2026-11, 오너 피드백)
/// 예전엔 마지막 메시지가 있으면 미리보기가 경로 자리를 차지해, 대화가 오간 방은 **어디서 어디로 가는
/// 방인지** 목록에서 알 수 없었다(경로는 메시지가 없는 방에서만 보였다).
///
/// - `route`: 경로 한 줄(`RouteLine`). 참여자를 못 받은 방은 **제목이 이미 경로**라 nil 이다
///   (`chatRoomListTitle`) — 같은 말을 두 번 쓰지 않는다
/// - `preview`: 마지막 메시지 미리보기. 메시지가 없으면 nil — 다만 제목이 경로인 방은 방 상태
///   (「진행 중」·「종료된 방」)를 대신 쓴다. 그 방은 경로 줄이 없어 제목 아래가 비기 때문이다
struct ChatRoomSubtitle: Equatable, Sendable {
    var route: RouteLine?
    var preview: String?
}

/// 「강남역 → 판교역」 한 줄. `closed` 면 앞에 「종료 · 」가 붙는다 — 닫힌 방의 표시는 이 줄이 맡는다.
struct RouteLine: Equatable, Sendable {
    var departure: String
    var destination: String
    var closed: Bool = false
}

/// 목록 부제 — 경로 한 줄 + 마지막 메시지 미리보기.
/// 위치 공유 메시지는 본문이 좌표라 사람 말로 바꾼다. 삭제된 메시지는 서버가 이미 「삭제된 메시지입니다」로 준다.
///
/// 닫힌 방의 「종료 · 」는 **한 번만** 붙인다 — 경로 줄이 있으면 그 줄에, 제목이 경로인 방이면 미리보기 줄에.
func chatRoomSubtitle(item: ChatRoomListItem) -> ChatRoomSubtitle {
    let room = item.room.room
    let active = room.status == .active
    let preview: String? = item.room.membership.lastMessage.map { last in
        switch last.type {
        // 이모지를 앞에 붙이지 않는다 — 글꼴마다 모양이 달라지고 문장만으로 뜻이 선다(디자인 QA C2)
        case .location: "위치를 공유했어요"
        case .text: last.content
        }
    }
    if item.peerTitle == nil {
        let line: String
        if let preview {
            line = active ? preview : "종료 · \(preview)"
        } else {
            line = active ? "진행 중" : "종료된 방"
        }
        return ChatRoomSubtitle(route: nil, preview: line)
    }
    return ChatRoomSubtitle(
        route: RouteLine(departure: room.departure, destination: room.destination, closed: !active),
        preview: preview
    )
}

/// 경로 한 줄의 폭 나누기 — 출발지와 도착지가 **각자** 쓸 폭.
///
/// 「출발 → 도착」을 통째로 끝에서 줄이면, 출발지가 길 때(역지오코딩 실주소가 들어온다) 화살표 뒤가 잘려
/// **도착지가 통째로 사라진다.** 그래서 둘을 따로 줄인다:
/// - 둘 다 들어가면 그대로
/// - 한쪽이 절반 이하면 그쪽은 다 보이고, 남은 폭을 긴 쪽이 쓴다
/// - 둘 다 절반을 넘으면 반씩 — 양쪽 다 앞부분이 남는다
func splitRouteWidths(available: CGFloat, departure: CGFloat, destination: CGFloat) -> (departure: CGFloat, destination: CGFloat) {
    guard available > 0 else { return (0, 0) }
    if departure + destination <= available { return (departure, destination) }
    let half = available / 2
    if departure <= half { return (departure, available - departure) }
    if destination <= half { return (available - destination, destination) }
    return (half, available - half)
}

/// 「[종료 · ]출발 → 도착」 한 줄 — 출발지와 도착지를 따로 줄여 **둘 다 남긴다**(`splitRouteWidths`).
/// VoiceOver 에는 화살표 대신 「출발지 …, 도착지 …」로 읽힌다.
private struct RouteOneLine: View {
    let route: RouteLine
    let style: MoyeotaType
    let color: Color

    var body: some View {
        RouteOneLineLayout {
            Text(route.closed ? "종료 · " : "")
            Text(route.departure)
            Text(" → ")
            Text(route.destination)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .moyeotaText(style.hangulTrimmed, color: color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((route.closed ? "종료, " : "") + "출발지 \(route.departure), 도착지 \(route.destination)")
    }
}

/// `RouteOneLine` 의 배치 — 머리말·출발지·화살표·도착지 네 칸을 한 줄로 잇는다. 원본 `Layout` 자리.
/// 네 칸이 같은 글꼴이라 높이가 같아 위에 맞춰 놓고, 기준선은 출발지 칸의 것을 쓴다.
private struct RouteOneLineLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = sizes(proposal: proposal, subviews: subviews)
        return CGSize(width: sizes.reduce(0) { $0 + $1.width }, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, size) in zip(subviews, sizes(proposal: proposal, subviews: subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width
        }
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? {
        let departure = sizes(proposal: proposal, subviews: subviews)[1]
        return bounds.minY + subviews[1].dimensions(in: ProposedViewSize(departure))[guide]
    }

    private func sizes(proposal: ProposedViewSize, subviews: Subviews) -> [CGSize] {
        let prefix = subviews[0].sizeThatFits(.unspecified)
        let arrow = subviews[2].sizeThatFits(.unspecified)
        let widths = splitRouteWidths(
            available: max((proposal.width ?? .infinity) - prefix.width - arrow.width, 0),
            departure: subviews[1].sizeThatFits(.unspecified).width,
            destination: subviews[3].sizeThatFits(.unspecified).width
        )
        return [
            prefix,
            subviews[1].sizeThatFits(ProposedViewSize(width: widths.departure, height: nil)),
            arrow,
            subviews[3].sizeThatFits(ProposedViewSize(width: widths.destination, height: nil)),
        ]
    }
}

/// 목록 행 제목 — 참여자 닉네임(`ChatRoomListItem.peerTitle`), 못 받았으면 경로 한 줄.
/// 경로로 떨어질 때 부제는 경로를 되풀이하지 않는다(`chatRoomSubtitle`).
func chatRoomListTitle(item: ChatRoomListItem) -> String {
    item.peerTitle ?? "\(item.room.room.departure) → \(item.room.room.destination)"
}

private struct ChatRoomRow: View {
    let item: ChatRoomListItem
    let onClick: () -> Void

    var body: some View {
        let membership = item.room.membership
        let subtitle = chatRoomSubtitle(item: item)
        let timeLabel = membership.lastMessage?.createdAt.toListTimeLabel()
        let unread = membership.hasUnread
        Button(action: onClick) {
            HStack(alignment: .center, spacing: 0) {
                // 제목이 부르는 사람들의 얼굴(`ChatRoomListItem.peerImageUrls`) — 제목과 **같은 멤버 목록**에서
                // 뽑아 Route 가 실어 보낸다. 참여자를 못 받은 방은 제목이 경로로 떨어지고 여기도 회색 원이다.
                // 부제가 두 줄이 되어 행이 높아져도 아바타는 행 가운데에 선다.
                PeerAvatarGroup(imageUrls: item.peerImageUrls, size: ChatRowAvatarSize)
                Spacer().frame(width: MoyeotaSpacing.Sm)
                // 글 묶음과 오른쪽 시각은 **제목의 기준선**에 맞춘다 — 부제가 두 줄이 된 행에서 시각이 행 가운데로
                // 내려가면 어느 줄의 시각인지 흐려진다(디자인 QA 4-10).
                // 원본 `Row` 의 기준선 맞춤 묶음은 행 위에 붙고 아바타만 가운데에 선다 — 글 묶음이 아바타보다 낮을 때도
                // 글이 위에 붙도록 묶음에 아바타 높이를 최소 높이로 주고 그 안의 위에 둔다.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 제목이 길어도 종이 밀려나지 않게 제목만 줄어든다 — 짧은 제목 바로 옆에 붙는다
                        HStack(alignment: .center, spacing: 0) {
                            if let peerTitle = item.peerTitle {
                                Text(peerTitle)
                                    .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                // 참여자를 못 받은 방은 경로가 제목이다 — 제목에서도 도착지가 잘려 사라지지 않게 따로 줄인다
                                RouteOneLine(
                                    route: RouteLine(departure: item.room.room.departure, destination: item.room.room.destination),
                                    style: MoyeotaType.HeadingMd,
                                    color: MoyeotaColor.InkPrimary
                                )
                            }
                            // 셋 이상인 방의 인원(나 포함, `chatRoomMemberCountLabel`) — 이름만으로는 몇 명이 탄 방인지
                            // 모른다. 숫자만 쓰면 닉네임 끝 숫자와 붙어 읽혀 「명」을 붙인다. 제목이 길어도 밀려나지 않는다.
                            if let label = chatRoomMemberCountLabel(count: item.memberCount) {
                                Text(label)
                                    .moyeotaText(MoyeotaType.BodySm.tabularNums().hangulTrimmed, color: MoyeotaColor.TextMute)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.leading, MoyeotaSpacing.Xs)
                            }
                            if membership.notificationMuted {
                                MutedMark().fixedSize()
                            }
                        }
                        if let route = subtitle.route {
                            Spacer().frame(height: 2)
                            // 경로는 보조 정보라 미리보기보다 한 단계 작고 흐리게 둔다 — 눈은 제목 다음에 미리보기로 간다
                            RouteOneLine(route: route, style: MoyeotaType.CaptionMd, color: MoyeotaColor.TextMute)
                        }
                        if let preview = subtitle.preview {
                            Spacer().frame(height: 2)
                            Text(preview)
                                // 안 읽은 방은 미리보기를 진하게 — 배지와 함께 「새 대화」를 두 신호로 알린다
                                .moyeotaText(
                                    MoyeotaType.BodySm.copy(fontWeight: unread ? .semibold : .regular).hangulTrimmed,
                                    color: unread ? MoyeotaColor.InkPrimary : MoyeotaColor.TextMute
                                )
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer().frame(width: MoyeotaSpacing.Xs)
                    VStack(alignment: .trailing, spacing: 0) {
                        if let timeLabel {
                            Text(timeLabel)
                                .moyeotaText(MoyeotaType.CaptionMd.tabularNums().hangulTrimmed, color: MoyeotaColor.TextMute)
                                .fixedSize()
                            Spacer().frame(height: MoyeotaSpacing.Xs)
                        }
                        // 안읽음 배지 — 서버가 개수를 주면 숫자(99+ 상한), 개수 없는 구버전 응답이면 점
                        if unread {
                            UnreadBadge(count: membership.unreadCount)
                        }
                    }
                }
                .frame(minHeight: ChatRowAvatarSize, alignment: .top)
            }
            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
            .padding(.vertical, MoyeotaSpacing.Sm)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressOverlayStyle(shape: Rectangle()))
    }
}

/// 묶음 아바타의 얼굴 한 자리 — 한 변이 1 인 상자 안에서 왼쪽 위 모서리(`x`·`y`)와 지름(`size`)의 비율.
struct FaceSlot: Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
}

/// 묶음 아바타 배치 — 얼굴 `count` 개를 한 상자에 모은다(2026-11 오너 피드백, 카카오톡 채팅 목록 모양).
/// - 0·1개: 상자를 꽉 채운 하나(지금까지의 1:1 방 모양)
/// - 2개: 왼쪽 위·오른쪽 아래로 비껴 겹친다
/// - 3개: 위 가운데 하나, 아래 둘 — 삼각형
/// - 4개 이상: 2×2(넘치는 얼굴은 `MAX_PEER_FACES` 에서 이미 잘렸다)
///
/// 뒤에 오는 얼굴이 위에 그려진다 — 제목의 첫 사람이 맨 뒤(왼쪽 위)다.
func peerFaceSlots(count: Int) -> [FaceSlot] {
    switch count {
    case ...1:
        return [FaceSlot(x: 0, y: 0, size: 1)]
    case 2:
        let d = PairFace
        return [FaceSlot(x: 0, y: 0, size: d), FaceSlot(x: 1 - d, y: 1 - d, size: d)]
    case 3:
        let d = TrioFace
        return [FaceSlot(x: (1 - d) / 2, y: 0, size: d), FaceSlot(x: 0, y: 1 - d, size: d), FaceSlot(x: 1 - d, y: 1 - d, size: d)]
    default:
        let d = GridFace
        return [
            FaceSlot(x: 0, y: 0, size: d), FaceSlot(x: 1 - d, y: 0, size: d),
            FaceSlot(x: 0, y: 1 - d, size: d), FaceSlot(x: 1 - d, y: 1 - d, size: d),
        ]
    }
}

// 얼굴 지름 ÷ 상자 한 변. 둘은 크게 겹치고(48 상자에서 33), 셋은 서로 조금씩 물리며(29),
// 넷은 겹치지 않고 사이를 조금 띄운다(23).
private let PairFace: CGFloat = 0.68
private let TrioFace: CGFloat = 0.6
private let GridFace: CGFloat = 0.48

/// 겹친 얼굴 사이의 흰 테 두께 — 앞 얼굴이 뒤 얼굴을 파고든 자리가 보여야 두 사람으로 읽힌다.
private let PeerFaceRing: CGFloat = 1.5

/// 목록 행 아바타 — 상대가 하나면 지금까지처럼 원 하나, 여럿이면 얼굴을 모아 그린다(`peerFaceSlots`).
/// 사진은 장식이다(이름은 바로 옆 제목이 읽어 준다).
private struct PeerAvatarGroup: View {
    let imageUrls: [String?]
    let size: CGFloat

    var body: some View {
        if imageUrls.count <= 1 {
            AvatarCircle(size: size, imageUrl: imageUrls.first ?? nil)
        } else {
            let slots = peerFaceSlots(count: imageUrls.count)
            ZStack(alignment: .topLeading) {
                ForEach(Array(imageUrls.enumerated()), id: \.offset) { index, url in
                    let slot = slots[index]
                    let face = size * slot.size
                    AvatarCircle(size: face - PeerFaceRing * 2, imageUrl: url)
                        .frame(width: face, height: face)
                        .background(MoyeotaColor.SurfaceCanvas, in: Circle())
                        .offset(x: size * slot.x, y: size * slot.y)
                }
            }
            .frame(width: size, height: size, alignment: .topLeading)
        }
    }
}

/// 안읽음 개수 표기 — 두 자리까지 그대로, 그 위는 「99+」(배지가 행 높이를 넘지 않게). nil 은 개수 모름(점)
func unreadBadgeLabel(count: Int?) -> String? {
    guard let count, count > 0 else { return nil }
    return count > 99 ? "99+" : String(count)
}

private struct UnreadBadge: View {
    let count: Int?

    var body: some View {
        if let label = unreadBadgeLabel(count: count) {
            // 숫자뿐이라 한글 글자 상자(`hangulTrimmed`)를 쓰지 않는다
            Text(label)
                .moyeotaText(
                    MoyeotaType.CaptionSm.copy(fontWeight: .semibold).tabularNums(),
                    color: MoyeotaColor.TextOnDark
                )
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(MoyeotaColor.Primary500, in: Capsule(style: .circular))
        } else {
            Circle()
                .fill(MoyeotaColor.Primary500)
                .frame(width: 8, height: 8)
        }
    }
}
