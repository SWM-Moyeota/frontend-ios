/// 파티 참여자를 화면에 그리기 위한 표시용 모델. 서버 `PartyDetailResult.MemberInfo` 가 출처다.
///
/// `id` 는 서버 `publicId`(UUID v7, JWT `sub` 와 같은 값)다. **탈퇴 등으로 유저 요약이 없으면
/// 서버가 publicId·nickname·imageUrl 을 전부 null 로 내리므로 그때는 빈 문자열이다**
/// — 화면은 빈 id 를 "탭 불가"로 다뤄야 한다(프로필로 넘어갈 대상이 없다).
///
/// `rating` 은 지금 항상 0.0 이다. 평가 API 자체가 서버에 없다 —
/// 화면은 0.0 을 "평가 없음"으로 표시해야 하며, 4.9·매너 98% 같은 가짜 값을 지어내면 안 된다.
/// `verifiedLabel` 도 같은 처지다: 서버 `badgeId` 가 TODO 라 항상 null 이므로 빈 문자열이 온다.
public struct User: Hashable, Sendable {
    public var id: String
    public var nickname: String
    public var verifiedLabel: String // 예: "성결대 인증", "직장 인증"
    public var rating: Double
    public var rideCount: Int
    /// 프로필 이미지 URL(전체 주소). `MemberAvatar` 가 이것을 그리고, 못 그리면 닉네임 첫 글자 원으로
    /// 되돌아간다.
    ///
    /// **null 을 "이미지 없음"으로 읽지 말 것.** 2026-10-15 배포(Backend #235)부터 서버는 고른 적
    /// 없는 사용자에게도 **기본 이미지의 전체 URL** 을 준다. 여기가 null 인 경우는 사실상 하나뿐인데,
    /// 그건 유저 요약 자체가 없는 멤버(탈퇴 등)라 publicId·nickname 과 **함께** null 로 오는 경우다.
    /// 그 판정은 `id` 가 비었는지로 한다(`User.isWithdrawn`) — 이 필드로 하지 마라.
    public var imageUrl: String?
    /// 이 멤버가 로그인한 본인인가. `publicId == UserSession.currentUserUuid` 로 판정한다.
    ///
    /// 기본값이 false 인 건 **식별자가 없는 응답**(목록·방 생성) 때문이다 — 그쪽 자리 표시용 멤버는
    /// 누가 나인지 알 방법이 없다. 상세/합류 응답에서만 실제로 채워진다.
    public var isMe: Bool
    /// 이 멤버가 방장인가. 서버 `PartyDetailResult.MemberInfo.host` 가 출처다(Backend #240).
    ///
    /// **앱이 추정하지 않는다.** 서버의 방장은 *저장값이 아니라 파생값*이다 — `Party.hostId()` =
    /// 현재 멤버 중 `min(joinedAt, memberId)`. 그래서 멤버 구성이 바뀔 때마다 달라지고, 판별의 단일
    /// 창구는 서버 `Party.isHost(memberId)` 뿐이다. 앱이 입장 순서나 목록 첫째 원소로 흉내 내면
    /// 서버가 거부하는 사람에게 방장 권한을 보여 준다(예전 `joinedAt` 추정이 지워진 이유다).
    ///
    /// 기본값이 false 인 건 **서버가 멤버를 설명해 주지도 않은 자리** 때문이다 — 목록·방 생성 응답의
    /// 자리 표시용 멤버가 그렇다. 그쪽은 식별자조차 없어 `isMe` 도 false 라 이 값을 읽는 쪽이 없다.
    /// 서버가 멤버는 설명했지만 `host` 만 빠뜨린 경우의 처리는 **다르다** —
    /// `PartyMappers` 의 `toUser` 에 근거와 함께 적어 두었다.
    ///
    /// 화면이 「내가 방장인가」를 물을 때는 이 필드를 직접 훑지 말고 `Ride.isHostedByMe` 를 쓴다.
    public var isHost: Bool
    /// 이 멤버가 **출발지에 도착했다고 눌렀는가**. 서버 `PartyDetailResult.MemberInfo.arrived` 가 출처다.
    ///
    /// 약속이 정해지기 전에는 서버가 **늘 false** 를 준다(도착을 받지 않는 방이다). 약속이 확정된 뒤에는
    /// 이 값이 곧 **노쇼 판정의 근거**다 — 누군가 「출발」을 누르는 그 순간 false 인 멤버가 전부 노쇼로
    /// 기록되고(노쇼 횟수 × 24시간 이용 제한), 그 기록은 앱이 되돌릴 수 없다.
    ///
    /// 서버가 말해 주지 않은 경우(옛 배포·필드 누락)의 기본값은 false 이고, `isHost` 와 달리 **`isMe` 로
    /// 폴백하지 않는다.** 대가가 반대 방향으로 기울어 있기 때문이다:
    ///
    /// | 누락 시 선택 | 나에 대해 틀리면 |
    /// |---|---|
    /// | false | 「출발지 도착했어요」가 한 번 더 보인다 — 그 호출은 **멱등**이라(이미 도착했으면 서버가 204 로 받고 아무것도 바꾸지 않는다) 눌러도 손해가 없다 |
    /// | true | 「출발」 버튼이 열리는데 서버는 409 `NOT_ARRIVED` 로 막는다 — **누를 수 없는 버튼**이고, 사용자는 도착을 누르는 길을 잃는다 |
    ///
    /// 즉 방장 표시와 달리 여기서는 **false 쪽이 복구 가능한 오답**이다.
    public var hasArrived: Bool

    public init(
        id: String,
        nickname: String,
        verifiedLabel: String,
        rating: Double,
        rideCount: Int,
        imageUrl: String? = nil,
        isMe: Bool = false,
        isHost: Bool = false,
        hasArrived: Bool = false
    ) {
        self.id = id
        self.nickname = nickname
        self.verifiedLabel = verifiedLabel
        self.rating = rating
        self.rideCount = rideCount
        self.imageUrl = imageUrl
        self.isMe = isMe
        self.isHost = isHost
        self.hasArrived = hasArrived
    }
}

/// 멤버의 이름 자리에 **사람 이름이 아닌 것**이 들어오는 두 경우의 문자열 — 한 곳에 모아 둔다.
///
/// 흩어 놓으면 둘 중 하나를 못 걸러 안내문이 **지킬 수 없는 약속**을 한다(「다 타면 방장 탈퇴한
/// 사용자님이 「합승 완료」를 눌러…」 — 그 사람은 영원히 누를 수 없다). 그래서 넣는 쪽(데이터 매퍼)과
/// 거르는 쪽(화면)이 **같은 상수**를 본다.
///
/// | 상수 | 넣는 쪽 | 서버 쪽 사실 |
/// |---|---|---|
/// | `SERVER_DELETED` | **서버** (`user/users/domain/User.DELETED_DISPLAY_NAME`) | **soft delete** 다 — `publicId` 는 **살아 있고** 닉네임만 이 상수로 가려진다(`isDeleted() ? DELETED_DISPLAY_NAME : nickname`) |
/// | `NO_SUMMARY` | **앱 매퍼** (`PartyMappers.toUser`) | 서버가 유저 요약 자체를 못 찾아 `MemberInfo` 의 publicId·nickname·imageUrl 을 **전부 null** 로 내린 경우 |
///
/// **두 경우를 하나로 접지 말 것.** 모양이 다르다: 앞은 식별자가 있어 프로필로 들어갈 수 있고(배지도
/// 붙는다), 뒤는 식별자가 없어 탭조차 막아야 한다(`User.isWithdrawn` = `id` 가 빈 값). 겹치는 것은
/// **이름으로 부를 수 없다**는 한 가지뿐이고, 그 판정만 `ALL` 로 함께 한다.
public enum WithdrawnMemberNames {

    /// 서버가 soft delete 된 사용자의 닉네임 자리에 직접 넣는 값. publicId 는 살아 있다.
    public static let SERVER_DELETED = "탈퇴한 사용자"

    /// 유저 요약이 없는 멤버(전 필드 null)에 **앱이** 채우는 자리값.
    public static let NO_SUMMARY = "탈퇴한 회원"

    /// 어느 쪽이든 **사람 이름이 아니다** — 이름으로 부르는 문구에서 걸러야 한다.
    public static let ALL: Set<String> = [SERVER_DELETED, NO_SUMMARY]
}

/// 로그인한 본인의 서버 기준 신원. GET /api/v1/local/users/info 의 결과다.
///
/// 같은 파일의 `User` 와는 쓰임이 다르다 — `User` 는 파티 참여자를 화면에 그리기 위한 표시용 모델이고,
/// 이쪽은 **서버가 확인해 준 "나"** 다. 별점·인증 라벨 같은 건 이 엔드포인트가 주지 않는다.
///
/// `name` 이 nullable 인 이유: 서버가 "닉네임 → 프로필 실명 → null" 순으로 폴백하기 때문이다.
/// 현재 서버에는 닉네임을 설정하는 경로가 없어 사실상 항상 실명이 오지만, 프로필이 비어 있으면 null 이다.
/// **화면은 null 을 반드시 처리해야 한다** — "이름 없음" 폴백 문구든, 이름 영역 숨김이든.
///
/// `uuid` 는 `AuthState.authenticated.userUuid` 와 같은 값이다(액세스 토큰 `sub`). 즉 uuid 만 필요하면
/// 이 호출은 필요 없다 — 이 엔드포인트를 부르는 이유는 `name`·`imageUrl`, 그리고 **제재**
/// (`noShowCount`·`restrictedUntil`)다.
///
/// ### 제재는 이 호출로만 알 수 있다 ★
/// 노쇼 제한에 걸린 사용자는 방 만들기·합류·예약 생성이 **403 `NO_SHOW_RESTRICTED` 로 막힌다.**
/// 그 403 은 「막혔다」까지만 말하고 **언제까지인지는 말하지 않는다** — 그 답이 `restrictedUntil`
/// 하나뿐이다. 그래서 화면은 그 403 을 받았을 때(그리고 제재를 안내해야 할 때) 이 조회를 함께
/// 해야 한다. 둘을 짝지어 쓰는 법은 `PartyOpenException.isNoShowRestricted` 에 적어 두었다.
public struct UserProfileInfo: Hashable, Sendable {
    public var uuid: String
    public var name: String?
    /// 내 프로필 이미지 URL(전체 주소). **서버는 이 값을 비워 보내지 않는다** —
    /// 한 번도 고른 적 없는 사용자에게는 기본 이미지의 전체 주소를 준다
    /// (서버 `ProfileImages.toUrl` 이 key 가 null 이면 `default-key` 를 붙인다).
    ///
    /// 그래서 여기가 null 이면 "이미지가 없다"가 아니라 **응답을 못 받았거나 서버가 구버전**이라는 뜻이다.
    /// 화면은 그때 기존 이니셜/회색 원으로 떨어뜨린다.
    ///
    /// **끝이 `default.png` 인지로 「아직 안 고름」을 구분할 수 있다** — 기본 키는
    /// `GET /api/v1/users/profile-images` 목록(16장)에 들어 있지 않기 때문이다
    /// (`ProfileImage` 주석). 「기본 이미지로 되돌리기」를 켤지 끌지가 이 구분에 달려 있다.
    public var imageUrl: String?
    /// 지금 내 노쇼 횟수. **지금까지의 총합이 아니다** — 서버가 건마다 그 방 **약속 시간부터 30일**이
    /// 지나면 세기를 멈추고, 이의가 인정돼 무효가 된 건(`NoShowRecord.isVoided`)은 애초에 세지 않는다.
    /// 즉 가만히 있어도 줄어드는 값이고, 화면이 「누적 N회」라고 쓰면 거짓이 된다.
    ///
    /// **이 값으로 제한을 셈하지 말 것.** 0 보다 크다고 제한 중인 것도 아니고(30일 창 안이지만
    /// 24시간은 지났다), 0 이라고 자유인 것도 아니다(겹친 제재의 끝이 아직 안 왔을 수 있다) —
    /// 그 판정은 `restrictedUntil` 하나로만 한다.
    ///
    /// 기본값 0 은 구버전 서버 대비용이다(이 필드가 없던 배포). 「노쇼가 없다」와 「서버가 말해 주지
    /// 않았다」를 가르지 않는 건 **화면이 할 일이 같기** 때문이다 — 둘 다 횟수를 내세우지 않는다.
    public var noShowCount: Int
    /// **이 시각까지 방 만들기·합류·예약 생성이 막힌다**(ISO-8601 instant 문자열). 제한이 없으면 null.
    ///
    /// **「걸어서 가까운 방」 추천은 막히지 않는다** — 서버 `PartyService.realtimeMatch` 에는
    /// 제재 검사(`ensureNotRestricted`)가 **없다**(호출처는 `open`·`reserve`·`join` 셋뿐). 즉 제재당한
    /// 사용자도 후보를 둘러볼 수 있고, 합류를 누르는 순간에만 403 이다. 그래서 그 섹션을 이 값으로
    /// 숨기지 말 것 — 숨기면 서버가 허용하는 탐색을 앱이 임의로 막는다.
    ///
    /// 화면이 「왜 막혔는지」와 「언제 풀리는지」를 말할 수 있는 **유일한 근거**다. 403
    /// `NO_SHOW_RESTRICTED` 는 사유만 주고 기한을 주지 않으므로, 그 403 을 안내할 때 이 값이 함께
    /// 있어야 문장이 완성된다(`PartyOpenException.isNoShowRestricted`).
    ///
    /// **앱이 계산하지 않는다.** 노쇼 1건당 24시간이고 약속 시간부터 세지만, 여러 건이 겹칠 때의
    /// 합산과 무효 처리 반영은 서버 규칙이다 — `NoShowRecord` 를 훑어 같은 식을 다시 세우면 서버가
    /// 규칙을 바꿀 때 앱만 뒤처진다. 그리고 그 목록은 **최대 20건**이라 재료 자체가 부족하다.
    ///
    /// **문자열을 파싱해 「지났는지」를 판정할 때는 기기 시계를 믿는다는 점을 기억할 것.** 앞당겨진
    /// 시계는 풀리지 않은 제한을 풀린 것으로 보여 주고, 그 상태에서 누른 버튼은 다시 403 이다 —
    /// 그래서 화면은 이 값으로 **안내만** 하고, 버튼을 열 근거로는 서버 응답을 쓴다.
    public var restrictedUntil: String?
    /// 로그인 아이디(Backend PR #330). **로컬 로그인(아이디·비밀번호)이 없는 계정이면 nil** 이다
    /// — 그때 36 프로필 수정은 「아이디」 행을 통째로 숨긴다.
    ///
    /// **표시 전용이다.** 아이디를 바꾸는 서버 경로가 없고, 이 값으로 인증·식별을 하지 않는다
    /// (식별은 `uuid` 다). 공백뿐인 값은 매퍼가 nil 로 접어 온다 — 도메인의 「없음」은 nil 하나다.
    /// 기본값 nil 은 PR #330 이전 서버(키 자체가 없다) 대비용이다.
    public var loginId: String?

    public init(
        uuid: String,
        name: String?,
        imageUrl: String? = nil,
        noShowCount: Int = 0,
        restrictedUntil: String? = nil,
        loginId: String? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.imageUrl = imageUrl
        self.noShowCount = noShowCount
        self.restrictedUntil = restrictedUntil
        self.loginId = loginId
    }
}
