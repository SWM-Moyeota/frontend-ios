@testable import FeatureMatching
import MoyeotaDomain
import Testing

/// 21 대기 화면이 **SSE 변경분만으로 방 상태를 만드는** 규칙.
///
/// 이 화면은 이제 평상시 서버를 주기적으로 부르지 않는다 — 들어오고 나가는 사람은 변경분으로 오고,
/// 그 변경분을 들고 있던 방에 **더하고 빼서** 화면을 만든다. 그래서 화면의 정확도가 통째로 이 함수들에 달려 있다:
/// 여기서 한 번 틀어지면 되돌릴 폴링이 없고(평상시 0회), 다음 재연결 스냅샷까지 틀린 인원이 떠 있게 된다.
///
/// 서버가 지문(fingerprint)과 상태 조회 API 를 지우면서(Backend #221) 「바뀌었나」를 싸게 묻던 장치도 사라졌다 —
/// 갱신의 근거는 이제 **스냅샷·변경분·(끊겼을 때만) 상세** 셋뿐이다.
struct WaitingSseStateTest {
    private func user(
        _ id: String,
        isMe: Bool = false,
        rideCount: Int = 0,
        isHost: Bool = false
    ) -> User {
        User(
            id: id,
            nickname: "승객\(id)",
            verifiedLabel: "",
            rating: 0.0,
            rideCount: rideCount,
            isMe: isMe,
            isHost: isHost
        )
    }

    private var me: User { user("me", isMe: true) }

    /// 원본 `me.copy(isHost = true)`
    private var hostMe: User { user("me", isMe: true, isHost: true) }

    private func ride(
        status: RideStatus = .recruiting,
        capacity: Int = 4,
        members: [User]? = nil
    ) -> Ride {
        Ride(
            id: "1",
            origin: "부산대",
            destination: "서면",
            departureLabel: "지금 출발",
            capacity: capacity,
            members: members ?? [me],
            farePerPerson: 0,
            totalFare: 0,
            status: status
        )
    }

    /// 확정 프레임 테스트의 바탕 — 상세·스냅샷이 주는 모양처럼 **출발지 좌표가 채워져 있다.**
    private func rideWithOrigin(status: RideStatus = .recruiting) -> Ride {
        var base = ride(status: status)
        base.origin = "부산대 정문"
        base.originLat = 35.2314
        base.originLng = 129.0846
        return base
    }

    // ─── 입장 ───────────────────────────────────────────────────────────────

    @Test("입장 - 멤버를 더하고 서버가 준 상태로 바꾼다")
    func joinAddsMember() {
        let before = ride(status: .recruiting, members: [me])

        let after = before.withMemberJoined(member: user("u2"), status: .recruiting)

        #expect(after.members.map(\.id) == ["me", "u2"])
        #expect(after.status == .recruiting)
    }

    /// 예전에는 전이가 둘이었다 — 정원 충족(동승 모드)과 배차 시작(택시 모드). 기사·배차를 걷어낸
    /// 뒤로 서버가 실어 보낼 수 있는 값이 정원 충족 하나다.
    ///
    /// 못 박는 것은 전이의 종류가 아니라 **「서버가 실어 준 status 를 그대로 반영한다」**다 —
    /// 합류로 바뀐 상태를 앱이 다시 계산하거나 물어보지 않는다.
    @Test("입장 - 마지막 자리를 채우면 서버가 실어 준 전이가 그대로 반영된다")
    func joinCarriesTransition() {
        let before = ride(status: .recruiting, capacity: 2, members: [me])

        let completed = before.withMemberJoined(member: user("u2"), status: .confirmed)
        #expect(completed.status == .confirmed)
        // 목록도 함께 늘어난다 — status 만 갈아 끼우는 것이 아니다
        #expect(completed.members.map(\.id) == ["me", "u2"])
    }

    @Test("입장 - 같은 publicId 는 자리를 지키며 교체한다 (인원이 부풀지 않는다)")
    func joinReplacesSameId() {
        let before = ride(members: [me, user("u2", rideCount: 3), user("u3")])

        let after = before.withMemberJoined(member: user("u2", rideCount: 9), status: .recruiting)

        #expect(after.members.map(\.id) == ["me", "u2", "u3"])
        #expect(after.members.count == 3)
        #expect(after.members[1].rideCount == 9) // 새 값으로 덮였다
    }

    @Test("입장 - isMe 는 온 그대로 쓴다 (화면이 다시 판정하지 않는다)")
    func joinKeepsIsMe() {
        // 데이터 계층이 상세와 같은 근거(publicId == 세션 uuid)로 채워 준다.
        let before = ride(members: [user("u2")])

        let after = before.withMemberJoined(member: user("me2", isMe: true), status: .recruiting)

        // 원본 `single { … }` 자리 — 같은 id 가 없거나 둘 이상이면 실패한다.
        #expect(after.members.filter { $0.id == "me2" }.map(\.isMe) == [true])
        #expect(after.members.filter { $0.id == "u2" }.map(\.isMe) == [false])
    }

    @Test("입장 - id 가 빈 멤버끼리는 같다고 보지 않는다 (구별할 근거가 없다)")
    func joinBlankIdsDiffer() {
        // 탈퇴 등으로 서버가 유저 요약을 못 만들면 publicId 가 빈 문자열로 온다.
        // 빈 id 끼리 같다고 보면 서로 다른 사람을 덮어쓴다.
        let before = ride(members: [me, user("")])

        let after = before.withMemberJoined(member: user(""), status: .recruiting)

        #expect(after.members.count == 3)
    }

    // ─── 도착 ───────────────────────────────────────────────────────────────

    @Test("도착 - publicId 로 그 한 명만 도착 표시한다")
    func arrivedMarksOne() {
        let before = ride(status: .confirmed, members: [me, user("u2"), user("u3")])

        let delta = before.withMemberArrived(publicId: "u2")

        #expect(delta.ride.members.map(\.hasArrived) == [false, true, false])
        #expect(!delta.needsDetail, "목록에 있는 사람이면 상세를 다시 읽을 이유가 없다")
    }

    /// **모르는 publicId 는 「목록이 낡았다」는 뜻이라 상세를 다시 읽는다** — 퇴장(아래)과 처방이 다르다.
    ///
    /// 서버도 그렇게 하라고 적어 두었지만(「목록에 없으면 방 상세를 다시 받는다」) 근거가 하나 더 있다.
    /// 도착 표시는 배지만 그리는 값이 아니라 **「출발」 확인 문구가 말하는 「빠지는 인원」**의 근거다
    /// (`notArrivedCount` — 서버가 「도착한 멤버 = 탑승자」로 센다). 낡은 목록을 두면 그 수가
    /// 실제보다 적어지고, 빠진 사람은 탑승 기록·택시비 정산에서 사라지는 실제
    /// 손해다 — 적게 말하고 누르게 하는 쪽이 조회 1건보다 나쁘다.
    @Test("도착 - 모르는 publicId 면 상세를 다시 읽는다")
    func arrivedUnknownNeedsDetail() {
        let before = ride(status: .confirmed, members: [me, user("u2")])

        let delta = before.withMemberArrived(publicId: "u9")

        #expect(delta.ride.members.map(\.hasArrived) == [false, false])
        #expect(delta.needsDetail, "목록이 낡았으므로 서버에 다시 물어야 한다")
    }

    @Test("도착 - 빈 publicId 로는 아무도 표시하지 않고 다시 읽지도 않는다")
    func arrivedBlankMarksNobody() {
        // 요약이 없는 멤버(id 가 빈 값)들을 한꺼번에 도착으로 만들면 「빠지는 인원」이 0 으로 보인다.
        // 그 프레임은 데이터 계층이 이미 버리므로(version 구멍 → 다음 프레임이 Resync) 여기서는 조용히 넘긴다.
        let before = ride(status: .confirmed, members: [me, user(""), user("")])

        let delta = before.withMemberArrived(publicId: "")

        #expect(delta.ride.members.map(\.hasArrived) == [false, false, false])
        #expect(!delta.needsDetail)
    }

    // ─── 퇴장 ───────────────────────────────────────────────────────────────

    @Test("퇴장 - publicId 로 그 한 명만 지우고 상태를 바꾼다")
    func leaveRemovesOne() {
        let before = ride(status: .confirmed, members: [me, user("u2"), user("u3")])

        let after = before.withMemberLeft(publicId: "u2", status: .recruiting).ride

        #expect(after.members.map(\.id) == ["me", "u3"])
        #expect(after.status == .recruiting)
    }

    @Test("퇴장 - 모르는 publicId 면 목록은 그대로 두고 상태만 반영한다")
    func leaveUnknownKeepsList() {
        // 그 사람의 입장 신호를 놓쳤다는 뜻이다. 없는 사람을 지우려 상세를 또 읽지는 않는다.
        let before = ride(status: .confirmed, members: [me, user("u2")])

        let after = before.withMemberLeft(publicId: "u9", status: .recruiting).ride

        #expect(after.members.map(\.id) == ["me", "u2"])
        #expect(after.status == .recruiting)
    }

    @Test("퇴장 - 빈 publicId 로는 아무도 지우지 않는다")
    func leaveBlankRemovesNobody() {
        // 요약이 없는 멤버(빈 id)들을 한꺼번에 날리는 사고를 막는다.
        let before = ride(members: [me, user(""), user("")])

        let after = before.withMemberLeft(publicId: "", status: .recruiting).ride

        #expect(after.members.count == 3)
    }

    @Test("들어왔다 나가면 원래 목록으로 돌아온다")
    func joinThenLeaveRestores() {
        let before = ride(members: [me, user("u2")])

        let after = before
            .withMemberJoined(member: user("u3"), status: .recruiting)
            .withMemberLeft(publicId: "u3", status: .recruiting)
            .ride

        #expect(after.members == before.members)
    }

    @Test("증분은 멤버와 상태만 건드린다 - 경로·요금·좌표는 스냅샷 값 그대로다")
    func deltaTouchesOnlyMembersAndStatus() {
        var before = ride()
        before.farePerPerson = 3_500
        before.totalFare = 14_000
        before.originLat = 35.23
        before.originLng = 129.08
        before.routePolyline = "abc"
        before.estimatedFare = 14_000
        before.estimatedMinutes = 21

        let joined = before.withMemberJoined(member: user("u2"), status: .recruiting)
        let left = joined.withMemberLeft(publicId: "u2", status: .recruiting).ride

        #expect(left == before)
    }

    // ─── 방장 승계 (Backend #240) ───────────────────────────────────────────

    /// **이 테스트가 깨지면 방장이 나가도 승계된 사람이 방장 전용 버튼(약속 확정·출발)을 못 본다.**
    ///
    /// 서버는 멤버가 나갈 때마다 남은 멤버 중 `min(joinedAt, memberId)` 를 방장으로 다시 정하고,
    /// 그 결과를 `member-left` 의 `hostPublicId` 로 **한 번만** 알려 준다 — 여기서 버리면 다음
    /// 재연결 스냅샷까지 승계된 사람의 화면이 낡은 채로 남는다.
    @Test("승계 - 방장이 나가면 서버가 지목한 사람이 방장이 된다")
    func successionOnHostLeave() {
        let before = ride(status: .confirmed, members: [user("u1", isHost: true), me, user("u3")])

        let after = before.withMemberLeft(publicId: "u1", status: .recruiting, hostPublicId: "me")

        #expect(after.ride.members.map(\.id) == ["me", "u3"])
        #expect(after.ride.members.map(\.isHost) == [true, false])
        #expect(after.ride.isHostedByMe)
        // 지목된 사람이 목록에 있었으므로 서버에 다시 물을 이유가 없다
        #expect(!after.needsDetail)
    }

    /// 승계가 나에게 오지 않았으면 내 방장 표시는 **지워져야** 한다 — 서버 말이 곧 「방장은 한 명」이다.
    @Test("승계 - 내가 아닌 사람이 방장이 되면 내 표시가 지워진다")
    func successionClearsMine() {
        let before = ride(members: [hostMe, user("u2"), user("u3")])

        let after = before.withMemberLeft(publicId: "u2", status: .recruiting, hostPublicId: "u3")

        #expect(!after.ride.isHostedByMe)
        #expect(after.ride.members.filter(\.isHost).map(\.id) == ["u3"])
        #expect(!after.needsDetail)
    }

    /// 방장이 아닌 사람이 나가면 방장은 그대로다 — 서버가 같은 publicId 를 다시 지목한다.
    @Test("승계 - 방장이 아닌 사람이 나가면 방장은 그대로다")
    func successionUnchanged() {
        let before = ride(members: [hostMe, user("u2"), user("u3")])

        let after = before.withMemberLeft(publicId: "u2", status: .recruiting, hostPublicId: "me")

        #expect(after.ride.isHostedByMe)
        #expect(after.ride.members.filter(\.isHost).count == 1)
        #expect(!after.needsDetail)
    }

    /// 서버가 새 방장을 특정하지 못하면(`hostSummary == null`) 들고 있던 표시를 **그대로 두고**
    /// 방 상세를 다시 받는다 — 서버 Swagger 가 「null 이거나 목록에 없는 publicId 면 host 표시를
    /// 바꾸지 말고 방 상세를 다시 받는다」고 적어 두었다. 모른다고 전부 false 로 밀면 반대로
    /// **진짜 방장의 표시를 지우는** 쪽이 위험하다.
    @Test("승계 - hostPublicId 가 없으면 표시를 손대지 않고 상세를 다시 읽는다")
    func successionNilKeepsAndReads() {
        let before = ride(members: [hostMe, user("u2")])

        let after = before.withMemberLeft(publicId: "u2", status: .recruiting, hostPublicId: nil)

        #expect(after.ride.isHostedByMe)
        #expect(after.needsDetail, "서버가 승계를 말하지 않았으니 상세로 확인해야 한다")

        // 빈 문자열도 같다 — "모름"은 한 가지 모양으로만 다룬다.
        let blank = before.withMemberLeft(publicId: "u2", status: .recruiting, hostPublicId: "")
        #expect(blank.ride.isHostedByMe)
        #expect(blank.needsDetail)
    }

    /// **지목된 publicId 가 목록에 없으면 표시를 바꾸지 않는다** — 서버 계약 그대로다
    /// (「단 null 이거나 목록에 없는 publicId 면 host 표시를 바꾸지 말고 방 상세를 다시 받는다 —
    /// 이벤트 순서 역전 대비」, 백엔드 `PartySseController` Swagger).
    ///
    /// 예전에는 여기서 **전원 false** 가 됐다(아무도 `$0.id == host` 가 아니므로). 그게 서버 계약과
    /// 반대이고, 역전 프레임에서 진짜 방장의 표시를 지웠다 — 아래 역전 테스트가 그 경로다.
    @Test("승계 - 목록에 없는 사람이 지목되면 표시를 손대지 않고 상세를 다시 읽는다")
    func successionUnknownKeepsAndReads() {
        let before = ride(members: [hostMe, user("u2")])

        let after = before.withMemberLeft(publicId: "u2", status: .recruiting, hostPublicId: "u9")

        #expect(after.ride.isHostedByMe, "전원 false 로 밀면 진짜 방장이 버튼을 잃는다")
        #expect(after.ride.members.filter(\.isHost).map(\.id) == ["me"])
        #expect(after.needsDetail, "서버에 다시 물어야 한다")
    }

    /// ### 프레임 순서 역전 ★ — **이 테스트가 깨지면 진짜 방장이 「출발」을 영구히 잃는다**
    ///
    /// 두 멤버가 연달아 나가면 서버는 프레임 둘을 따로 발행하고, 각 프레임의 `hostPublicId` 는
    /// **그 프레임을 반영한 뒤의** 방장이다. 전송 중 순서가 뒤집히면 뒤늦게 온 프레임이
    /// **이미 나간 사람**을 방장으로 지목한다(아래 `u2`).
    ///
    /// 그때 「목록에 없으니 전원 false」로 밀면 그 순간 진짜 방장(나)의 `User.isHost` 가 지워지고
    /// 복구 수단이 없다: `hasMemberDrift` 는 **인원수만** 보므로 못 잡고(목록 길이는 맞다),
    /// SSE 가 살아 있으면 폴백 폴링도 돌지 않는다(`shouldPollFallback`).
    @Test("승계 - 프레임 순서가 역전돼도 진짜 방장은 표시를 잃지 않는다")
    func successionSurvivesReorder() {
        let before = ride(status: .confirmed, capacity: 3, members: [user("u1", isHost: true), user("u2"), me])

        // 나중 프레임(u2 이탈 → 승계 = me)이 먼저 도착했다
        let first = before.withMemberLeft(publicId: "u2", status: .recruiting, hostPublicId: "me")
        #expect(first.ride.isHostedByMe)
        #expect(!first.needsDetail)

        // 앞 프레임(u1 이탈 → 승계 = u2, **이미 나간 사람**)이 뒤늦게 도착했다
        let second = first.ride.withMemberLeft(publicId: "u1", status: .recruiting, hostPublicId: "u2")

        #expect(second.ride.isHostedByMe, "역전 프레임이 진짜 방장의 표시를 지우면 안 된다")
        #expect(second.needsDetail, "표시를 믿을 수 없으니 상세를 다시 읽어야 한다")
        // 이 구멍을 기존 장치로는 메울 수 없다는 근거 — 인원수는 어긋나지 않는다
        #expect(!hasMemberDrift(ride: second.ride))
    }

    /// id 가 빈 멤버(요약 없음)를 방장으로 세우지 않는다 — 빈 문자열끼리 맞아떨어지면 안 된다.
    @Test("승계 - id 가 빈 멤버는 방장이 되지 않는다")
    func successionSkipsBlankIds() {
        let before = ride(members: [me, user(""), user("")])

        let after = before.withMemberLeft(publicId: "u9", status: .recruiting, hostPublicId: "me").ride

        #expect(after.members.filter(\.isHost).map(\.id) == ["me"])
    }

    /// 승계만 반영하는 경로(`member-left` 의 publicId 가 nil 일 때 뷰모델이 쓰는 자리) —
    /// 멤버 목록은 건드리지 않고 방장 표시만 옮긴다.
    @Test("승계 - 목록을 못 고치는 프레임에서도 방장 표시는 옮긴다")
    func successionWithoutListChange() {
        let before = ride(members: [user("u1", isHost: true), me])

        let after = before.withHostSuccession(hostPublicId: "me")

        #expect(after.ride.members.map(\.id) == before.members.map(\.id))
        #expect(after.ride.isHostedByMe)
        #expect(!after.needsDetail)
    }

    /// ### delta 경로와 snapshot 경로가 같은 결과를 낸다 ★
    ///
    /// `connected` 스냅샷은 전체 교체라 서버가 계산한 `host` 가 그대로 들어온다. 증분 경로는 그 값을
    /// 쌓아서 만든다 — 두 경로가 갈리면 "재연결 전에는 방장, 후에는 아님" 같은 어긋남이 생긴다.
    ///
    /// 같을 수 있는 근거: 서버가 싣는 `hostPublicId` 는 **이탈을 반영한 뒤** 읽은 `party.hostId()` 이고,
    /// 스냅샷의 `host` 도 같은 `Party.isHost` 가 만든다. 그리고 합류는 방장을 바꿀 수 없다
    /// (합류자는 가장 늦게 들어온 사람 = `min(joinedAt)` 이 될 수 없다).
    @Test("승계 - 증분으로 만든 방장 표시가 스냅샷과 같다")
    func deltaMatchesSnapshot() {
        let before = ride(status: .confirmed, capacity: 3, members: [user("u1", isHost: true), me, user("u3")])

        // delta: u1(방장) 이탈 → 서버가 me 를 승계로 지목
        let delta = before.withMemberLeft(publicId: "u1", status: .recruiting, hostPublicId: "me").ride

        // snapshot: 같은 시점의 상세를 서버가 통째로 다시 내려 준 모양
        var snapshot = before
        snapshot.members = [hostMe, user("u3")]
        snapshot.status = .recruiting

        #expect(delta == snapshot)
    }

    /// 합류는 방장을 바꾸지 않는다 — 합류자는 `min(joinedAt)` 이 될 수 없다(서버 보장).
    @Test("승계 - 합류는 방장을 바꾸지 않는다")
    func joinKeepsHost() {
        let before = ride(members: [hostMe])

        let after = before.withMemberJoined(member: user("u2"), status: .recruiting)

        #expect(after.isHostedByMe)
        #expect(after.members.filter(\.isHost).count == 1)
    }

    // ─── 약속 확정 프레임 ───────────────────────────────────────────────────

    /// 🔴 ★ **확정 프레임이 방의 출발지를 옮긴다** (2026-11-12 에 새로 생긴 규칙).
    ///
    /// 서버는 확정과 함께 방의 출발지를 만남 장소로 바꾼다(`Party.confirm`:
    /// `departureLocation = plan.departure()`), 그래서 `confirmed` 프레임에 좌표·이름이 실려 온다.
    /// 무시하면 둘이 깨진다:
    ///
    /// | 무시하면 | 결과 |
    /// |---|---|
    /// | 지도가 옛 출발지를 가리킨다 | 보고 넘길 수 있다 |
    /// | **도착 판정이 옛 좌표를 기준으로 돈다** | 약속 장소에 서 있는 사람이 400 `TOO_FAR_FROM_DEPARTURE` → **방을 끝낼 길이 막힌다** |
    ///
    /// 둘째가 본체라 값으로 못 박는다. status 는 그대로 두는 것도 함께 고정한다 — 프레임의 status 는
    /// 서버 enum 이름 **문자열**이라 옮기려면 매퍼를 화면 쪽에 베껴야 한다.
    @Test("확정 - 실려 온 출발지로 덮어쓰고 status 는 건드리지 않는다")
    func confirmedMovesOrigin() {
        let before = rideWithOrigin(status: .recruiting)

        let delta = before.withMeetingConfirmed(
            departureAt: "2026-11-06T06:30:00Z",
            departureLat: 35.1631,
            departureLng: 129.1635,
            departurePlace: "센텀시티역 3번 출구"
        )

        #expect(delta.ride.isConfirmed)
        #expect(delta.ride.departureAt == "2026-11-06T06:30:00Z")
        #expect(delta.ride.origin == "센텀시티역 3번 출구")
        #expect(delta.ride.originLat == 35.1631)
        #expect(delta.ride.originLng == 129.1635)
        // status 는 다음 스냅샷·폴백 상세가 맞춘다 — 화면은 `isConfirmed` 를 보므로 지연이 안 보인다
        #expect(delta.ride.status == .recruiting)
        #expect(!delta.needsDetail, "셋이 다 왔으니 상세를 또 읽을 이유가 없다")
    }

    /// ★ **반쪽만 온 프레임으로는 덮어쓰지 않는다** — 좌표와 이름이 어긋난 출발지를 만들면
    /// 지도와 도착 판정이 **서로 다른 곳**을 가리키고, 그 어긋남은 화면에서 알 수 없다.
    ///
    /// 매퍼가 「셋이 다 있거나 전부 nil」로 보장하지만(`PartySseEvent`) 타입은 셋 다 옵셔널이다 —
    /// 그 보장을 여기서 다시 확인하고, 깨졌으면 **상세를 읽는다**(서버가 지시하는 처방이다).
    @Test("확정 - 출발지가 반쪽만 오면 손대지 않고 상세를 읽는다")
    func confirmedPartialOriginRereads() {
        let before = rideWithOrigin()

        let halves = [
            before.withMeetingConfirmed(departureAt: "2026-11-06T06:30:00Z", departureLat: 35.1631),
            before.withMeetingConfirmed(departureAt: "2026-11-06T06:30:00Z", departureLng: 129.1635),
            before.withMeetingConfirmed(departureAt: "2026-11-06T06:30:00Z", departurePlace: "센텀시티역"),
            before.withMeetingConfirmed(departureAt: "2026-11-06T06:30:00Z", departureLat: 35.1631, departureLng: 129.1635),
        ]

        for delta in halves {
            #expect(delta.needsDetail, "반쪽 프레임인데 상세를 읽지 않는다")
            #expect(delta.ride.origin == "부산대 정문")
            #expect(delta.ride.originLat == 35.2314)
            #expect(delta.ride.originLng == 129.0846)
            // 확정 사실과 시각은 **그래도 반영한다** — 그 둘은 반쪽이 아니다
            #expect(delta.ride.isConfirmed)
            #expect(delta.ride.departureAt == "2026-11-06T06:30:00Z")
        }
    }

    /// 출발지를 **아예 싣지 않은** 프레임(옛 배포)은 정상이다 — 손대지 않고 상세도 읽지 않는다.
    /// 그때 방의 출발지가 곧 만남 장소이고(서버가 옮기지 않았거나 같은 값이다), 읽어도 같은 답이다.
    @Test("확정 - 출발지를 싣지 않은 옛 프레임은 그대로 받는다")
    func confirmedWithoutOriginKeepsOrigin() {
        let before = rideWithOrigin()

        let delta = before.withMeetingConfirmed(departureAt: "2026-11-06T06:30:00Z")

        #expect(delta.ride.isConfirmed)
        #expect(delta.ride.origin == "부산대 정문")
        #expect(!delta.needsDetail)
    }

    /// ★ **약속 시각이 없으면 들고 있던 값을 지우지 않는다** — 지우면 「몇 시에 만나는지」를 잃는다.
    ///
    /// 그런데 **양쪽 다 없으면 상세를 읽는다**: 「확정됐다」는 사실만 알고 **언제**를 모르면
    /// `meetingStage` 가 `confirmedWaiting` 에 영구히 머물러 **도착 버튼이 영영 뜨지 않는다.**
    /// 그 상태는 화면이 「약속 시간이 정해졌어요」만 그리므로 사용자도 개발자도 알아채기 어렵다.
    @Test("확정 - 약속 시각이 없으면 들고 있던 값을 지키고 둘 다 없으면 상세를 읽는다")
    func confirmedMissingTime() {
        var held = ride()
        held.departureAt = "2026-11-06T06:30:00Z"
        for missing in [nil, "", "   "] as [String?] {
            let kept = held.withMeetingConfirmed(departureAt: missing)
            #expect(kept.ride.departureAt == "2026-11-06T06:30:00Z", "들고 있던 약속 시각을 날렸다")
            #expect(!kept.needsDetail)

            let unknown = ride().withMeetingConfirmed(departureAt: missing)
            #expect(unknown.needsDetail, "언제인지 모르는데 상세를 읽지 않는다 — 도착 버튼이 영영 안 뜬다")
            #expect(unknown.ride.isConfirmed)
        }
    }

    // ─── 상세 재조회 판정 (되돌이 방지) ────────────────────────────────────

    /// 변경분 적용 뒤 상세를 읽는 사유는 둘이고 처방이 같다 — 그래서 판정도 하나다.
    ///
    /// **되돌이가 없는 근거**: 이 판정은 **이벤트 프레임에만** 걸린다. 읽어 온 상세는
    /// `MatchWaitingViewModel.readDetail` 이 화면 상태로 직접 세우고 이 판정을 다시 지나지 않으므로,
    /// 프레임 하나당 추가 조회는 최대 1건이고 그 조회가 또 조회를 부르는 길이 없다.
    @Test("재조회 - 지목된 방장을 못 맞춘 프레임은 상세를 읽는다")
    func rereadOnUnknownHost() {
        // 인원은 어긋나지 않는다(정원 4, 1명, 모집 중) — needsDetail 하나만 세워진 경우
        let delta = ride(status: .recruiting, capacity: 4, members: [me])
            .withMemberLeft(publicId: "u9", status: .recruiting, hostPublicId: "u9")

        #expect(delta.needsDetail)
        #expect(!hasMemberDrift(ride: delta.ride))
        #expect(needsDetailAfterDelta(delta: delta))
    }

    @Test("재조회 - 인원이 어긋난 프레임도 상세를 읽는다")
    func rereadOnDrift() {
        // 방장은 맞췄지만(me) 목록이 **정원을 넘었다** — 서버 상태로는 있을 수 없는 모양이다
        // (서버가 `PARTY_FULL` 로 막는다). 즉 내 목록이 부풀었다는 뜻이다(`hasMemberDrift`).
        let delta = ride(status: .recruiting, capacity: 2, members: [me, user("u2"), user("u3")])
            .withMemberLeft(publicId: "u9", status: .recruiting, hostPublicId: "me")

        #expect(!delta.needsDetail)
        #expect(hasMemberDrift(ride: delta.ride))
        #expect(needsDetailAfterDelta(delta: delta))
    }

    @Test("재조회 - 사유가 둘 다여도 판정은 하나다 (상세는 1회)")
    func rereadOnBoth() {
        let delta = ride(status: .recruiting, capacity: 2, members: [me, user("u2"), user("u3")])
            .withMemberLeft(publicId: "u9", status: .recruiting, hostPublicId: "u9")

        #expect(delta.needsDetail)
        #expect(hasMemberDrift(ride: delta.ride))
        #expect(needsDetailAfterDelta(delta: delta))
    }

    @Test("재조회 - 방장도 인원도 멀쩡하면 서버를 부르지 않는다")
    func noReread() {
        let delta = ride(status: .recruiting, capacity: 4, members: [hostMe, user("u2")])
            .withMemberLeft(publicId: "u2", status: .recruiting, hostPublicId: "me")

        #expect(!needsDetailAfterDelta(delta: delta))
    }

    // ─── 어긋남 감지 ────────────────────────────────────────────────────────
    //
    // 🔴 **판정 근거가 바뀐 구역이다** (2026-11-12). 예전에는 **서버가 준 status 와 목록**을 견줬다:
    //
    // ```
    // matched     -> members.count < capacity   // 정원이 찼다는데 목록이 모자라다
    // recruiting  -> members.count >= capacity  // 모집 중인데 목록이 정원을 채웠다
    // ```
    //
    // 두 줄 다 모순이 아니게 됐다 — 서버가 COMPLETED 의 뜻을 「방장이 약속을 확정했다」로 바꾸면서
    // (`b16551b7`) ① 2/3 짜리 확정 방이 정상이고 ② **정원이 찬 방도 ACTIVE** 다. 그 두 테스트는
    // **지금은 정상인 방을 어긋남으로 판정하라고 요구**하므로 아래 둘로 바꿔 적었다.
    //
    // 남은 유일한 참은 **정원 초과**다: 서버가 `PARTY_FULL` 로 막으므로 `members.count > capacity`
    // 는 서버 상태로는 있을 수 없고, 봤다면 내 목록이 부풀었다는 뜻이다(같은 합류를 두 번 얹었거나
    // 이탈 프레임을 놓쳤다).

    /// 🔴 ★ **목록이 정원을 넘으면 어긋남이다** — 서버가 `PARTY_FULL` 로 막으므로 있을 수 없는 모양이다.
    ///
    /// 옛 두 테스트(「정원이 찼다는데 목록이 모자라면」·「모집 중인데 목록이 정원을 채웠으면」)를
    /// 이 하나로 대체했다. 그 둘이 못 박던 사실(「status 와 목록이 모순이면 목록이 틀렸다」)은
    /// **status 가 아예 다른 사실을 말하게 되어** 성립하지 않는다.
    @Test("어긋남 - 목록이 정원을 넘으면 상세로 보정한다")
    func driftOverCapacity() {
        var inflated = ride(status: .recruiting, capacity: 2, members: [me, user("u2"), user("u3")])
        #expect(hasMemberDrift(ride: inflated))
        // status 와 무관하다 — 어느 단계에서도 정원 초과는 있을 수 없다
        inflated.status = .confirmed
        #expect(hasMemberDrift(ride: inflated))
    }

    /// 🔴 ★ **정원이 안 찬 것은 더 이상 모순이 아니다** — 두 status 에서 모두 정상이다.
    ///
    /// 이 테스트가 뒤집힌 쪽을 못 박는다. 옛 식을 되돌리면 **2/3 짜리 확정 방**과 **정원이 찬 미확정
    /// 방**이 매 프레임 어긋남으로 판정되어 상세를 계속 다시 읽는다 — SSE 가 살아 있어 폴백은 돌지
    /// 않는데(`shouldPollFallback`) 변경분마다 상세 1건이 덧붙는 모양이 된다.
    @Test("어긋남 - 정원이 안 찬 것도 꽉 찬 것도 모순이 아니다")
    func noDriftUnderOrAtCapacity() {
        // 2/3 확정 방 — 서버 COMPLETED 는 「정원 충족」이 아니라 「확정」이다
        #expect(!hasMemberDrift(ride: ride(status: .confirmed, capacity: 3, members: [me, user("u2")])))
        // 정원이 꽉 찬 모집 중 방 — 서버는 정원이 차도 ACTIVE 로 둔다
        #expect(!hasMemberDrift(ride: ride(status: .recruiting, capacity: 2, members: [me, user("u2")])))
        #expect(!hasMemberDrift(ride: ride(status: .recruiting, capacity: 4, members: [me])))
    }

    /// **status 를 아예 보지 않는다** — 열거형 전체에서 정원 초과가 참이고 정상 목록이 거짓이다.
    ///
    /// 예전에는 「종료 단계에서는 어긋남을 보지 않는다」였다(Route 가 이미 화면을 떠나므로). 지금
    /// 판정은 status 와 무관하므로 그 가지가 없다 — 대신 **어느 단계에서도 같은 답**이라는 것을
    /// 열거형 전체로 못 박는다. 단계가 늘어도 판정이 조용히 갈리지 않는다.
    @Test("어긋남 - status 를 보지 않는다")
    func driftIgnoresStatus() {
        for status in RideStatus.allCases {
            #expect(
                hasMemberDrift(ride: ride(status: status, capacity: 1, members: [me, user("u2")])),
                "\(status) 에서 정원 초과를 놓쳤다"
            )
            #expect(
                !hasMemberDrift(ride: ride(status: status, capacity: 4, members: [me])),
                "\(status) 에서 멀쩡한 목록을 어긋남으로 봤다"
            )
        }
    }

    /// ★ **정원을 모르는 방(`capacity` 0)은 판단하지 않는다.** 목록·추천 응답으로 만든 `Ride` 가
    /// 그렇고, 0 은 「정원이 0명」이 아니라 「정원을 모른다」다 — 가드가 없으면 **멤버가 한 명이라도
    /// 있는 모든 방**이 정원 초과로 읽혀 매 프레임 상세를 다시 읽는다.
    @Test("어긋남 - 정원을 모르는 방은 판단하지 않는다")
    func noDriftUnknownCapacity() {
        #expect(!hasMemberDrift(ride: ride(status: .recruiting, capacity: 0, members: [])))
        #expect(!hasMemberDrift(ride: ride(status: .recruiting, capacity: 0, members: [me])))
    }

    // ─── 폴링 정책 ──────────────────────────────────────────────────────────

    @Test("폴링 - SSE 가 살아 있고 방이 떠 있으면 한 번도 부르지 않는다")
    func noPollWhenAlive() {
        #expect(!shouldPollFallback(realtimeAlive: true, hasRide: true))
    }

    @Test("폴링 - 끊긴 동안에만 폴백이 돈다")
    func pollWhenDisconnected() {
        #expect(shouldPollFallback(realtimeAlive: false, hasRide: true))
    }

    @Test("폴링 - 화면에 방이 없으면 SSE 가 살아 있어도 읽는다 (에러 화면에 갇히지 않게)")
    func pollWithoutRide() {
        // 변경분은 바탕이 있을 때만 쓸 수 있다 — 첫 조회가 실패한 채로 두면 다음 멤버 변화까지 에러다.
        #expect(shouldPollFallback(realtimeAlive: true, hasRide: false))
        #expect(shouldPollFallback(realtimeAlive: false, hasRide: false))
    }

    /// 대기 단계는 **모집 중과 확정됨** 둘이다 — 「정원 찬 상태」가 아니다(서버 COMPLETED 의 뜻이
    /// 바뀌었다). 통과시키는 값은 그대로고, 이름이 가리키던 사실만 달라졌다.
    @Test("대기 단계는 모집 중과 확정된 상태뿐 - 그 밖이면 폴백을 끝낸다")
    func waitingStages() {
        #expect(isWaitingForMembers(status: .recruiting))
        #expect(isWaitingForMembers(status: .confirmed))
        // 그 밖은 지금 닫힌 방 둘뿐이지만, 열거형 전체를 훑어 단계가 늘어도 폴백이 영원히
        // 돌지 않게 못 박는다 — 끝나지 않는 6초 루프가 이 판정이 막는 것이다.
        for status in RideStatus.allCases where status != .recruiting && status != .confirmed {
            #expect(!isWaitingForMembers(status: status), "\(status) 가 대기 단계로 읽힌다")
        }
    }
}
