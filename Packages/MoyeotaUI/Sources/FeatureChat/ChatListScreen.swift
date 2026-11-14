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
/// 제목은 **참여자 닉네임**(`ChatRoomListItem.peerTitle` · `chatRoomPeerTitle`), 부제는 **마지막 메시지**
/// (없으면 「출발지:」·「도착지:」 두 줄 — `chatRoomSubtitle`), 우측에 마지막 메시지 시각과 안읽음 점.
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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: MoyeotaSpacing.Xs)
                    if let notice {
                        NoticeBanner(kind: .error, text: notice)
                            .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                            .padding(.vertical, MoyeotaSpacing.Xs)
                    }
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

/// 목록 부제 — 한 줄 글(`line`) 또는 경로 두 줄(`route`).
///
/// 경로를 「강남역 → 판교역」 한 줄로 쓰지 않고 「출발지: 강남역」·「도착지: 판교역」 **두 줄**로 쓴다
/// (2026-11, 오너 UX 피드백) — 장소 이름이 길면(역지오코딩 실주소) 한 줄의 화살표 뒤가 잘려 도착지가
/// 통째로 사라졌다(`RoutePlace`). 24 채팅방 **헤더**는 그대로 한 줄 경로다(그쪽은 폭이 넉넉하다).
enum ChatRoomSubtitle: Equatable, Sendable {
    /// 한 줄 — 마지막 메시지 미리보기, 또는 제목이 이미 경로일 때의 방 상태.
    case line(String)

    /// 경로 두 줄. 닫힌 방이면 첫 줄 이름표 앞에 「종료 · 」가 붙는다.
    case route([RoutePlace])
}

/// 목록 부제 — **마지막 메시지 미리보기**가 있으면 그것, 없으면 경로(+종료 여부).
/// 위치 공유 메시지는 본문이 좌표라 사람 말로 바꾼다. 삭제된 메시지는 서버가 이미 「삭제된 메시지입니다」로 준다.
///
/// **제목이 이미 경로면 경로를 또 쓰지 않는다** — 참여자를 못 받은 방은 제목이 「출발 → 도착」으로
/// 떨어지는데(`chatRoomListTitle`), 그 아래에 출발지·도착지 두 줄이 또 오면 같은 말이 세 줄이다.
/// 그때 부제는 방 상태(「진행 중」·「종료된 방」) 한 줄이다.
func chatRoomSubtitle(item: ChatRoomListItem) -> ChatRoomSubtitle {
    let room = item.room.room
    let active = room.status == .active
    if let last = item.room.membership.lastMessage {
        let preview: String
        switch last.type {
        // 이모지를 앞에 붙이지 않는다 — 글꼴마다 모양이 달라지고 문장만으로 뜻이 선다(디자인 QA C2)
        case .location: preview = "위치를 공유했어요"
        case .text: preview = last.content
        }
        return .line(active ? preview : "종료 · \(preview)")
    }
    if item.peerTitle == nil { return .line(active ? "진행 중" : "종료된 방") }
    let places = routePlaces(departure: room.departure, destination: room.destination)
    if active { return .route(places) }
    return .route(places.enumerated().map { index, place in
        guard index == 0 else { return place }
        var closed = place
        closed.label = "종료 · \(place.label)"
        return closed
    })
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
        let title = chatRoomListTitle(item: item)
        let subtitle = chatRoomSubtitle(item: item)
        let timeLabel = membership.lastMessage?.createdAt.toListTimeLabel()
        let unread = membership.hasUnread
        Button(action: onClick) {
            HStack(alignment: .center, spacing: 0) {
                // 제목이 부르는 사람의 얼굴(`ChatRoomListItem.peerImageUrl`) — 제목과 **같은 멤버 목록**에서
                // 뽑아 Route 가 실어 보낸다. 참여자를 못 받은 방은 제목이 경로로 떨어지고 여기도 회색 원이다.
                // 부제가 두 줄이 되어 행이 높아져도 아바타는 행 가운데에 선다.
                AvatarCircle(size: ChatRowAvatarSize, imageUrl: item.peerImageUrl)
                Spacer().frame(width: MoyeotaSpacing.Sm)
                // 글 묶음과 오른쪽 시각은 **제목의 기준선**에 맞춘다 — 부제가 두 줄이 된 행에서 시각이 행 가운데로
                // 내려가면 어느 줄의 시각인지 흐려진다(디자인 QA 4-10).
                // 원본 `Row` 의 기준선 맞춤 묶음은 행 위에 붙고 아바타만 가운데에 선다 — 글 묶음이 아바타보다 낮을 때도
                // 글이 위에 붙도록 묶음에 아바타 높이를 최소 높이로 주고 그 안의 위에 둔다.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 제목이 길어도 종이 밀려나지 않게 제목만 줄어든다 — 짧은 제목 바로 옆에 붙는다
                        HStack(alignment: .center, spacing: 0) {
                            Text(title)
                                .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if membership.notificationMuted {
                                MutedMark().fixedSize()
                            }
                        }
                        Spacer().frame(height: 2)
                        switch subtitle {
                        case .line(let text):
                            Text(text)
                                // 안 읽은 방은 미리보기를 진하게 — 배지와 함께 「새 대화」를 두 신호로 알린다
                                .moyeotaText(
                                    MoyeotaType.BodySm.copy(fontWeight: unread ? .semibold : .regular).hangulTrimmed,
                                    color: unread ? MoyeotaColor.InkPrimary : MoyeotaColor.TextMute
                                )
                                .lineLimit(1)
                                .truncationMode(.tail)
                        case .route(let places):
                            ForEach(Array(places.enumerated()), id: \.offset) { index, place in
                                // 두 줄 사이 2(디자인 QA 4-10)
                                if index > 0 { Spacer().frame(height: 2) }
                                RoutePlaceLine(place: place)
                            }
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
