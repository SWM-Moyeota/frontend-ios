@testable import FeatureMatching
import Foundation
import MoyeotaDomain
import PresentationCore
import Testing

/// 21 매칭 대기의 **방장 분기** — 방을 끝내는 버튼을 누구에게 보이고, 못 보는 사람에게 무엇을 말하고,
/// 멤버 목록에 배지를 누구에게 붙이는가.
///
/// ### 🔴 가리키는 버튼이 바뀌었다 (2026-11-12) ★
/// 이 파일은 「합승 완료」(`canFinishParty` · `finishHostNotice`)를 보고 있었다. 서버가 `/finish` 를
/// 없애면서(`b16551b7`) 그 버튼과 두 함수가 사라졌다 — 그런데 **같은 커밋이 「출발」을 방장 전용으로
/// 만들었다**(「출발은 도착한 방장만 누른다」). 그래서 이 파일이 지키던 세 가지가 **그대로 필요하다**:
///
/// | 지키는 것 | 옛 자리 | 지금 자리 |
/// |---|---|---|
/// | 비방장에게 버튼을 주지 않는다 | `canFinishParty` | `canDepartParty` |
/// | 못 보는 사람에게 누가 누르는지 말한다 | `finishHostNotice` | `departHostNotice` |
/// | 배지는 서버 값만 본다 | `showsHostBadge` | 그대로 |
///
/// 한동안 앱은 서버가 좁힌 버튼을 **전원에게** 보여 주고 있었고(「합승 완료」 때 Backend #237),
/// 비방장은 확인을 거친 끝에 403 `NOT_PARTY_HOST` 를 맞았다. **같은 실수가 「출발」에서 다시
/// 가능해졌다** — 옛 코드는 출발을 도착한 멤버 전원에게 열어 두었기 때문이다. 그래서 테스트를
/// 지우지 않고 **새 버튼으로 옮겨 적는다.**
///
/// **여기서 지키는 것은 「추정하지 않는다」다.** 2026-08-30 에 지운 방장 로직은 앱이 `joinedAt`
/// 최소값으로 방장을 **추정**하던 것이었고(`_workspace/33_api-integrator_no_host.md`), 되살린 지금은
/// 서버 값만 본다. 그 구분이 무너지는 자리가 둘 있어 각각 못 박는다:
/// ① 매퍼의 fail-open 폴백(`host ?? isMe`)이 **내 줄만** true 로 만드는 것 → 배지에 쓰면 거짓이 된다
/// ② 안내문이 방장을 **이름으로** 부를 때 → 부를 수 없는 경우를 지어내면 거짓이 된다
struct WaitingHostNoticeTest {
    /// 기준 시각. 약속 시각은 이 값보다 **앞**에 둔다 — 출발 단계에 닿아야 방장 분기가 보인다.
    private let now = Date(timeIntervalSince1970: 1_793_944_800) // 2026-11-06T06:00:00Z

    private func member(
        _ id: String,
        nickname: String? = nil,
        isMe: Bool = false,
        isHost: Bool = false,
        arrived: Bool = false
    ) -> User {
        User(
            id: id,
            nickname: nickname ?? "승객\(id)",
            verifiedLabel: "",
            rating: 0.0,
            rideCount: 0,
            isMe: isMe,
            isHost: isHost,
            hasArrived: arrived
        )
    }

    /// **탈퇴(soft delete) 모양** — 서버는 행을 지우지 않는다. `publicId` 는 **그대로 오고** 닉네임만
    /// 서버 상수로 가려진다(`user/users/domain/User` 의
    /// `return isDeleted() ? DELETED_DISPLAY_NAME : nickname`).
    ///
    /// 예전 헬퍼는 여기에 `id = ""` 를 넣어 **서버가 내지 않는 모양**을 만들고 있었다 — 그래서 빈 id
    /// 검사(`isWithdrawn`)에 걸려 테스트는 통과했지만, 실제 응답은 식별자가 살아 있어 그 검사를 그냥
    /// 통과했고 안내문에 「탈퇴한 사용자」가 찍혔다.
    private func softDeleted(id: String = "u2", isHost: Bool = false) -> User {
        member(id, nickname: WithdrawnMemberNames.SERVER_DELETED, isHost: isHost)
    }

    /// **요약이 없는 멤버** — 서버가 publicId·nickname 을 전부 null 로 주고 매퍼가 이렇게 접는다.
    private func noSummary(isHost: Bool = false) -> User {
        member("", nickname: WithdrawnMemberNames.NO_SUMMARY, isHost: isHost)
    }

    /// **출발 직전의 방** — 확정됐고 · 약속 시간이 지났고 · **나는 도착했다**.
    ///
    /// 노출 조건을 보려면 이 네 가지가 다 서 있어야 한다(`canDepartParty`). 예전 헬퍼는
    /// `status: .matched` 하나로 「손으로 닫는 단계」를 만들 수 있었는데, 그 status 의 뜻이
    /// 「정원 충족」에서 「확정」으로 바뀌면서(`b16551b7`) **status 만으로는 어떤 단계도 만들 수
    /// 없게 됐다** — 확정·도착·시각을 각각 세워야 한다.
    ///
    /// 나를 늘 도착으로 두는 이유: 미도착이면 방장이어도 `MeetingStage.arriveOpen` 에 머물러
    /// 방장 분기가 아예 보이지 않는다(그 경계는 `MeetingStageTest` 가 맡는다).
    private func departableParty(_ members: [User]) -> Ride {
        Ride(
            id: "1",
            origin: "부산대",
            destination: "서면",
            departureLabel: "지금 출발",
            capacity: members.count,
            members: members.map { member in
                var next = member
                if member.isMe { next.hasArrived = true }
                return next
            },
            farePerPerson: 0,
            totalFare: 0,
            status: .confirmed,
            departureAt: now.addingTimeInterval(-60).formatted(.iso8601),
            isConfirmed: true
        )
    }

    // ─── 노출 조건 ───────────────────────────────────────────────────────────

    @Test("도착한 방장에게는 출발 버튼이 보인다")
    func hostSeesButton() {
        let ride = departableParty([member("me", isMe: true, isHost: true), member("u2")])

        #expect(canDepartParty(ride: ride, now: now))
        #expect(meetingStage(ride: ride, now: now) == .departByMe)
    }

    /// **이 테스트가 이번 변경의 핵심이다.** 옛 코드는 도착한 멤버 누구에게나 「출발」을 띄웠고,
    /// 서버가 방장 전용으로 좁힌 뒤로 그 버튼은 비방장에게 403 `NOT_PARTY_HOST` 로만 끝난다.
    @Test("비방장에게는 출발 버튼을 보이지 않는다")
    func nonHostDoesNotSeeButton() {
        let ride = departableParty([member("me", isMe: true), member("u2", isHost: true)])

        #expect(!canDepartParty(ride: ride, now: now))
        // 숨기기만 하면 「왜 나만 안 되지」에 답할 자리가 없다 — 그 자리가 departByHost 다.
        #expect(meetingStage(ride: ride, now: now) == .departByHost)
    }

    /// 내가 목록에 아예 없으면(식별자 없는 응답·요약 없는 멤버) 「내가 방장이다」라고 말해 주는 근거가
    /// 없다 — 그걸 「방장이 따로 있다」로 읽지 않더라도, **근거 없이 버튼을 주지는 않는다.**
    @Test("내가 목록에 없으면 버튼을 주지 않는다")
    func notInListNoButton() {
        let ride = departableParty([member("u1", isHost: true), member("u2")])

        #expect(!canDepartParty(ride: ride, now: now))
    }

    /// 매퍼의 fail-open 폴백(`host ?? isMe`)이 살아 있는 경로 — 옛 서버를 보고 있으면 내 줄만 true 다.
    /// 그때 **버튼은 보여야 한다**: 방장이 못 보면 방을 끝낼 길이 없어 자동 정리를 기다려야 하고,
    /// 아니었다면 서버 403 이 바로잡아 준다(`PartyMappers.toUser` 의 표).
    @Test("서버가 host 를 안 줘도 내 줄의 폴백은 버튼으로 이어진다")
    func fallbackShowsButton() {
        // 폴백 결과와 같은 모양: 내 줄만 isHost = true
        let ride = departableParty([member("me", isMe: true, isHost: true), member("u2"), member("u3")])

        #expect(canDepartParty(ride: ride, now: now))
    }

    // ─── 안내문 ──────────────────────────────────────────────────────────────

    @Test("방장을 알면 이름으로 부른다")
    func callsHostByName() {
        let ride = departableParty([member("me", isMe: true), member("u2", nickname: "부산가자", isHost: true)])

        #expect(
            departHostNotice(hostNickname: ride.members.hostDisplayNameOrNull())
                == "약속 시간이 됐어요. 도착한 방장 부산가자님이 「출발」을 눌러 방을 끝내요"
        )
    }

    /// ### 이름을 못 쓰는 경우 ① 방장이 **탈퇴했다**(soft delete) ★
    ///
    /// 서버 탈퇴는 행을 지우지 않는다 — `publicId` 는 살아 있고 닉네임만 「탈퇴한 사용자」로 가려진다.
    /// 그래서 빈 id 검사(`isWithdrawn`)로는 **걸러지지 않고**, 공백 검사로도 걸러지지 않는다(멀쩡한
    /// 문자열이다). 그대로 통과하면 안내문이 이렇게 된다 — 「도착한 방장 **탈퇴한 사용자**님이
    /// 「출발」을 눌러 방을 끝내요」. 그 사람은 **영원히 누를 수 없다**(방은 자동 정리로만 닫힌다).
    @Test("방장이 탈퇴했으면 이름을 쓰지 않는다 - publicId 는 살아 있다")
    func softDeletedHostNotNamed() {
        let ride = departableParty([member("me", isMe: true), softDeleted(isHost: true)])

        let notice = departHostNotice(hostNickname: ride.members.hostDisplayNameOrNull())

        #expect(!notice.contains("탈퇴한 사용자"), "사람 이름이 아니다")
        #expect(notice == "약속 시간이 됐어요. 도착한 방장(가장 먼저 참여한 분)이 「출발」을 눌러 방을 끝내요")
    }

    /// **배지는 그대로 붙는다.** 서버가 그를 방장이라고 말한 건 사실이고, 그 사실이 방이 왜 끝나지
    /// 않는지를 설명해 준다 — 막는 것은 **이름으로 부르는 것** 하나뿐이다. 그래서 이 한 경우에만
    /// 「배지가 붙는 사람」과 「안내문이 부르는 사람」이 갈린다.
    @Test("탈퇴한 방장에게도 방장 배지는 붙는다 - 이름만 쓰지 않는다")
    func softDeletedHostHasBadge() {
        let host = softDeleted(isHost: true)

        #expect(host.showsHostBadge, "서버가 방장이라고 말한 건 사실이다")
        #expect([host].hostDisplayNameOrNull() == nil, "그래도 이름으로 부를 수는 없다")
    }

    /// ### 이름을 못 쓰는 경우 ② 방장의 **유저 요약이 없다**
    ///
    /// 서버가 `MemberSummary` 를 못 만든 경우다 — publicId·nickname 이 전부 null 로 와서 매퍼가
    /// `id = ""` · 닉네임 「탈퇴한 회원」으로 접는다. 탈퇴와 **다른 경우**이고(식별자가 없다), 역시
    /// 공백 검사로는 걸러지지 않는다.
    @Test("방장의 요약이 없으면 이름을 쓰지 않는다")
    func noSummaryHostNotNamed() {
        let ride = departableParty([member("me", isMe: true), noSummary(isHost: true)])

        let notice = departHostNotice(hostNickname: ride.members.hostDisplayNameOrNull())

        #expect(!notice.contains("탈퇴한 회원"), "사람 이름이 아니다")
        #expect(notice == "약속 시간이 됐어요. 도착한 방장(가장 먼저 참여한 분)이 「출발」을 눌러 방을 끝내요")
    }

    /// 아무도 방장으로 지목되지 않은 목록 — 지어내지 않고 조건을 말한다.
    @Test("방장을 지목할 줄이 없으면 조건으로 말한다")
    func noHostRow() {
        let ride = departableParty([member("me", isMe: true), member("u2")])

        #expect(ride.members.hostDisplayNameOrNull() == nil)
        #expect(
            departHostNotice(hostNickname: ride.members.hostDisplayNameOrNull())
                == "약속 시간이 됐어요. 도착한 방장(가장 먼저 참여한 분)이 「출발」을 눌러 방을 끝내요"
        )
    }

    /// 안내문은 **세 가지를 말해야 한다**: 누가 끝내는지(방장), 어떤 버튼인지(「출발」), 그게 방을
    /// 끝내는 행동이라는 것. 하나라도 빠지면 버튼을 숨긴 자리가 「왜 내가 할 일이 없는지」를
    /// 설명하지 못한다.
    ///
    /// **「도착한」이 들어가는 것도 요점이다** — 서버 조건이 방장이기만 한 게 아니라 **도착한
    /// 방장**이다(409 `NOT_ARRIVED`). 그 말이 없으면 「방장은 왜 안 누르지」에 답하지 못한다.
    @Test("안내문은 누가 어떤 버튼으로 방을 끝내는지 말한다")
    func noticeSaysWhoAndWhat() {
        for notice in [departHostNotice(hostNickname: "부산가자"), departHostNotice(hostNickname: nil)] {
            #expect(notice.contains("방장"), "\(notice)")
            #expect(notice.contains("도착한"), "\(notice)")
            #expect(notice.contains("출발"), "\(notice)")
            #expect(notice.contains("방을 끝내요"), "\(notice)")
        }
    }

    /// 지키지 못할 약속을 넣지 않는다(`ProductClaimsTest` 주석 — 거짓 문구 19건을 들어낸 이력).
    /// 여기서 특히 위험한 건 **기다리라는 말**이다: 기다려서 풀리는 일이 아니다. 방장이 와서 도착을
    /// 누르고 출발하거나, 방장이 나가 내게 승계되어야 바뀐다.
    @Test("안내문은 기다리거나 다시 시도하라고 말하지 않는다")
    func noticeMakesNoPromise() {
        for notice in [departHostNotice(hostNickname: "부산가자"), departHostNotice(hostNickname: nil)] {
            for forbidden in ["잠시 후", "다시 시도", "다시 눌러", "기다려", "곧 "] {
                #expect(!notice.contains(forbidden), "지키지 못할 약속이다: \(notice)")
            }
        }
    }

    /// 403 문구와 **같은 표현**을 쓴다 — 두 자리가 방장을 다르게 설명하면 사용자가 다른 사람을 찾는다.
    @Test("이름을 모를 때의 표현은 403 안내와 같은 근거를 쓴다")
    func sameWordingAs403() {
        #expect(departHostNotice(hostNickname: nil).contains("가장 먼저 참여한"))
        #expect(
            departFailureMessage(
                e: PartyDepartException(code: PartyDepartException.NOT_PARTY_HOST, serverMessage: nil, httpStatus: 403)
            ).contains("가장 먼저 참여한")
        )
    }

    // ─── 배지 ────────────────────────────────────────────────────────────────

    @Test("서버가 방장이라고 말한 남의 줄에 배지가 붙는다")
    func badgeOnOthers() {
        #expect(member("u2", isHost: true).showsHostBadge)
        #expect(!member("u2").showsHostBadge)
    }

    /// **폴백 비대칭 때문에 내 줄에는 붙이지 않는다.** 매퍼가 `host ?? isMe` 로 접으므로 옛 서버에서는
    /// 내 줄만 true 가 되고, 그걸 그대로 그리면 비방장이 자기 줄에서 「방장」을 읽는다 — 버튼의 거짓은
    /// 눌렀을 때 서버 403 이 바로잡지만 배지의 거짓은 **아무도 바로잡지 않는다.** 게다가 그 403 문구
    /// (「방장만 출발할 수 있어요」)와 정면으로 모순되는 화면이 된다.
    @Test("내 줄에는 방장 배지를 붙이지 않는다 - 폴백이 만든 true 일 수 있다")
    func noBadgeOnMine() {
        #expect(!member("me", isMe: true, isHost: true).showsHostBadge)
    }

    /// 배지와 안내문이 **같은 사람**을 가리킨다 — 판정이 갈리면 화면이 서로 다른 말을 한다.
    /// (갈리는 경우는 이름을 쓸 수 없을 때 하나뿐이고, 그때 안내문은 **아무도 부르지 않는다**.)
    @Test("배지가 붙는 사람과 안내문이 부르는 사람이 같다")
    func badgeAndNoticeAgree() {
        let members = [member("me", isMe: true), member("u2", nickname: "부산가자", isHost: true)]

        #expect(members.filter { $0.showsHostBadge }.map(\.nickname) == ["부산가자"])
        #expect(members.hostDisplayNameOrNull() == "부산가자")
    }
}
