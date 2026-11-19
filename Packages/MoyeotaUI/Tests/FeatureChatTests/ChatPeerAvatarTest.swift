import CoreGraphics
import MoyeotaDomain
import Testing
@testable import FeatureChat

/// 채팅 아바타에 **상대 사진**을 그리는 규칙.
///
/// 못 박는 것은 두 가지다.
/// - 목록 행: 제목이 부르는 사람과 얼굴이 **같은 사람**이어야 한다. 제목과 얼굴이 멤버를 따로 고르면
///   「A 이름 + B 얼굴」이 되는데, 둘 다 그럴듯해 보여 눈으로는 잡히지 않는다.
/// - 말풍선: 메시지 응답에는 사진이 없다. 참여자 조회로 세운 `publicId → 사진` 사전이 유일한 출처다.
///
/// 사진 URL 은 CDN 의 프리셋 주소 형태를 그대로 쓴다(백엔드 소스 기준 — 이번에 로컬 서버 DB 가 죽어
/// API 를 실제로 호출해 보지는 못했다).
@Suite struct ChatPeerAvatarTest {

    private func member(
        _ nickname: String,
        imageUrl: String? = "https://cdn.moyeota.co.kr/profile/presets/01.png",
        active: Bool = true,
        isMe: Bool = false
    ) -> ChatMember {
        ChatMember(
            userId: nil,
            publicId: "public-\(nickname)",
            nickname: nickname,
            imageUrl: imageUrl,
            active: active,
            isMe: isMe
        )
    }

    private func message(
        id: Int64 = 1,
        senderPublicId: String? = "public-스모크일",
        isMine: Bool = false
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            chatRoomId: 7,
            senderPublicId: senderPublicId,
            content: "정문 앞 편의점에 있어요",
            type: .text,
            createdAt: "2026-09-11T03:00:00Z",
            deleted: false,
            isMine: isMine,
            senderName: "스모크일"
        )
    }

    @Test("목록 행의 얼굴은 제목이 부르는 순서 그대로다")
    func listFacesFollowTitle() {
        let members = [
            member("스모크일", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/01.png"),
            member("스모크삼", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/03.png"),
            member("나", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/09.png", isMe: true),
        ]
        #expect(chatRoomPeerTitle(members: members) == "스모크일, 스모크삼")
        #expect(chatRoomPeerImageUrls(members: members) == ["https://cdn.moyeota.co.kr/profile/presets/01.png", "https://cdn.moyeota.co.kr/profile/presets/03.png"])
    }

    /// 셋 이상인 방은 얼굴을 모두 모은다 — 사람 수가 얼굴로 보인다.
    @Test("셋 이상인 방은 얼굴을 모두 모은다")
    func threePeersAllFaces() {
        let members = [
            member("스모크일", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/01.png"),
            member("스모크삼", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/03.png"),
            member("스모크사", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/04.png"),
            member("나", isMe: true),
        ]
        #expect(chatRoomPeerTitle(members: members) == "스모크일, 스모크삼, 스모크사")
        #expect(chatRoomPeerImageUrls(members: members) == ["https://cdn.moyeota.co.kr/profile/presets/01.png", "https://cdn.moyeota.co.kr/profile/presets/03.png", "https://cdn.moyeota.co.kr/profile/presets/04.png"])
    }

    @Test("얼굴은 넷까지만 모은다")
    func facesCapAtFour() {
        let members = (1...6).map { member("동승\($0)") } + [member("나", isMe: true)]
        #expect(chatRoomPeerImageUrls(members: members).count == MAX_PEER_FACES)
    }

    @Test("방을 나간 사람은 제목과 얼굴에서 함께 빠진다")
    func leftMembersDropFromBoth() {
        let members = [
            member("나간사람", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/02.png", active: false),
            member("남은사람", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/05.png"),
            member("나", isMe: true),
        ]
        #expect(chatRoomPeerTitle(members: members) == "남은사람")
        #expect(chatRoomPeerImageUrls(members: members) == ["https://cdn.moyeota.co.kr/profile/presets/05.png"])
    }

    /// 제목이 나간 사람을 되살려 쓰는 경우에는 얼굴도 같이 되살아나야 한다(둘의 근거가 하나라서).
    @Test("남은 사람이 없으면 나간 사람의 얼굴이라도 쓴다")
    func leftMemberFallback() {
        let members = [
            member("나간사람", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/02.png", active: false),
            member("나", isMe: true),
        ]
        #expect(chatRoomPeerTitle(members: members) == "나간사람")
        #expect(chatRoomPeerImageUrls(members: members) == ["https://cdn.moyeota.co.kr/profile/presets/02.png"])
    }

    /// 참여자를 못 받은 방(구버전 서버 응답은 멤버가 빈 목록이다)과 나 혼자인 방은 그릴 얼굴이 없다 —
    /// 빈 목록이면 `AvatarCircle` 하나가 회색 원으로 떨어진다.
    @Test("나 혼자인 방과 참여자를 못 받은 방은 얼굴이 없다")
    func noFaces() {
        #expect(chatRoomPeerImageUrls(members: [member("나", isMe: true)]).isEmpty)
        #expect(chatRoomPeerImageUrls(members: []).isEmpty)
    }

    /// 사진이 빈 문자열이면 없는 것으로 보되 **자리는 남긴다** — 얼굴 수가 곧 사람 수라 회색 원으로라도 그린다.
    @Test("사진이 없는 사람도 자리는 남긴다")
    func blankImageKeepsSlot() {
        let members = [member("스모크일", imageUrl: ""), member("스모크삼", imageUrl: nil), member("나", isMe: true)]
        #expect(chatRoomPeerImageUrls(members: members) == [nil, nil])
    }

    /// 인원은 나 포함, 지금 방에 있는 사람만 센다 — 이름만으로는 몇 명이 탄 방인지 모른다.
    @Test("인원은 나를 포함해 남아 있는 사람만 센다")
    func memberCountActiveOnly() {
        let members = [member("스모크일"), member("나간사람", active: false), member("스모크삼"), member("나", isMe: true)]
        #expect(chatRoomMemberCount(members: members) == 3)
    }

    /// 제목은 나간 사람이라도 부르지만 수는 그러지 않는다 — 아무도 없는 방에 둘이 있다고 말하지 않는다.
    @Test("모두 나간 방은 나만 센다")
    func memberCountOnlyMe() {
        #expect(chatRoomMemberCount(members: [member("나간사람", active: false), member("나", isMe: true)]) == 1)
    }

    /// 얼굴은 상대만 그려 1:1 방에 「2명」을 붙이면 얼굴 하나 옆에 2 가 선다 — 카카오톡처럼 셋부터 적는다.
    @Test("인원 표기는 셋 이상인 방에만 붙는다")
    func memberCountLabelFromThree() {
        #expect(chatRoomMemberCountLabel(count: 2) == nil)
        #expect(chatRoomMemberCountLabel(count: 1) == nil)
        #expect(chatRoomMemberCountLabel(count: nil) == nil)
        #expect(chatRoomMemberCountLabel(count: 3) == "3명")
        #expect(chatRoomMemberCountLabel(count: 4) == "4명")
    }

    @Test("참여자를 모르면 인원도 모른다")
    func memberCountUnknown() {
        #expect(chatRoomMemberCount(members: []) == nil)
        #expect(chatRoomMemberCount(members: [member("나간사람", active: false)]) == nil)
    }

    @Test("얼굴 수만큼 자리를 만들고 하나뿐이면 상자를 꽉 채운다")
    func slotCounts() {
        #expect(peerFaceSlots(count: 1) == [FaceSlot(x: 0, y: 0, size: 1)])
        #expect(peerFaceSlots(count: 0) == [FaceSlot(x: 0, y: 0, size: 1)])
        for count in 2...4 { #expect(peerFaceSlots(count: count).count == count) }
        #expect(peerFaceSlots(count: 9).count == 4)
    }

    /// 모든 얼굴이 상자 안에 들어간다 — 넘치면 옆 행이나 제목을 덮는다.
    @Test("얼굴은 상자 밖으로 나가지 않는다")
    func slotsStayInside() {
        for count in 1...4 {
            for slot in peerFaceSlots(count: count) {
                #expect(slot.x >= 0 && slot.y >= 0 && slot.x + slot.size <= 1 + 1e-6 && slot.y + slot.size <= 1 + 1e-6)
            }
        }
    }

    /// 둘은 왼쪽 위·오른쪽 아래, 셋은 위 가운데 하나와 아래 둘 — 뒤에 오는 얼굴이 아래쪽에서 위에 그려진다.
    @Test("둘은 비껴 겹치고 셋은 삼각형이다")
    func pairAndTrioShapes() {
        let pair = peerFaceSlots(count: 2)
        #expect(pair[0].x == 0 && pair[0].y == 0)
        #expect(abs(pair[1].x + pair[1].size - 1) < 1e-6 && abs(pair[1].y + pair[1].size - 1) < 1e-6)

        let trio = peerFaceSlots(count: 3)
        #expect(abs(trio[0].x + trio[0].size / 2 - 0.5) < 1e-6 && trio[0].y == 0)
        #expect(trio[1].y == trio[2].y && trio[1].x == 0)
        #expect(abs(trio[2].x + trio[2].size - 1) < 1e-6)
    }

    @Test("사전은 참여자의 publicId 에 사진을 잇는다")
    func dictionaryMapsPublicIdToImage() {
        let members = [
            member("스모크일", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/01.png"),
            member("나", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/09.png", isMe: true),
        ]
        #expect(
            chatMemberImageUrls(members: members) == [
                "public-스모크일": "https://cdn.moyeota.co.kr/profile/presets/01.png",
                "public-나": "https://cdn.moyeota.co.kr/profile/presets/09.png",
            ]
        )
    }

    /// 사진 없는 사람을 nil 값으로 담아 두면 「사전에 있다」와 「얼굴이 있다」가 달라진다 — 아예 담지 않는다.
    @Test("사진이 없는 참여자는 사전에 담지 않는다")
    func noImageIsNotInDictionary() {
        let members = [member("무사진", imageUrl: nil), member("빈문자", imageUrl: "")]
        #expect(chatMemberImageUrls(members: members) == [:])
    }

    /// 나간 사람이 남긴 메시지도 얼굴을 유지한다 — 이름을 남기는 것과 같은 이유다.
    @Test("방을 나간 사람도 사전에 남는다")
    func leftMemberStaysInDictionary() {
        let members = [
            member("나간사람", imageUrl: "https://cdn.moyeota.co.kr/profile/presets/02.png", active: false),
        ]
        #expect(
            chatMemberImageUrls(members: members) == ["public-나간사람": "https://cdn.moyeota.co.kr/profile/presets/02.png"]
        )
    }

    @Test("상대 메시지는 사전에서 발신자 사진을 찾아 싣는다")
    func peerMessageCarriesImage() {
        let dictionary = ["public-스모크일": "https://cdn.moyeota.co.kr/profile/presets/01.png"]
        let ui = message().toUiMessage(imageUrls: dictionary)
        #expect(ui.senderImageUrl == "https://cdn.moyeota.co.kr/profile/presets/01.png")
        #expect(ui.senderName == "스모크일")
    }

    /// 내 말풍선에는 아바타 자리가 없다 — 사전에 내 사진이 있어도 싣지 않는다(이름도 그렇다).
    @Test("내 메시지는 사전에 내 사진이 있어도 싣지 않는다")
    func myMessageCarriesNoImage() {
        let dictionary = ["public-나": "https://cdn.moyeota.co.kr/profile/presets/09.png"]
        let ui = message(senderPublicId: "public-나", isMine: true).toUiMessage(imageUrls: dictionary)
        #expect(ui.senderImageUrl == nil)
        #expect(ui.senderName == nil)
    }

    /// 참여자 조회가 아직/끝내 안 끝난 방, 탈퇴로 서버가 신원을 못 실은 메시지 — 둘 다 회색 원이다.
    /// 이름이 「동승자」로 떨어지는 것과 같은 자리다.
    @Test("사전에 없는 발신자와 신원 없는 메시지는 사진 없이 그린다")
    func unknownSenderHasNoImage() {
        #expect(message().toUiMessage(imageUrls: [:]).senderImageUrl == nil)
        let unknown = message(senderPublicId: nil)
            .toUiMessage(imageUrls: ["public-스모크일": "https://cdn.moyeota.co.kr/profile/presets/01.png"])
        #expect(unknown.senderImageUrl == nil)
    }
}
