import Foundation
import MoyeotaDomain
import Testing
@testable import MoyeotaData

@Suite struct UserMappersTest {

    /// 백엔드 `UserResponse(UUID uuid, String name, String imageUrl)` 모양이고 **실측이다** —
    /// 2026-11-01 로컬 :8080 에서 `POST /api/v1/auth/register` 가
    /// `{"uuid":"01a194d1-…","name":"큐에이일","imageUrl":"https://cdn.moyeota.co.kr/profile/presets/default.png"}`
    /// 로 답했고, 같은 모양을 `GET /api/v1/local/users/info` 도 200 으로 돌려줬다.
    /// 필드가 둘이던 옛 본문을 그대로 두면 `UserProfileResponse.imageUrl` 이 한 번도
    /// 파싱되지 않은 채 통과한다.
    @Test("백엔드 UserResponse 모양을 그대로 파싱한다")
    func decodesUserResponse() throws {
        let body = """
            {"uuid":"01a06145-3caf-7614-a3bd-cee6e25316b1","name":"김성윤",
             "imageUrl":"https://cdn.moyeota.co.kr/profile/presets/01.png"}
            """

        let dto = try decodeJSON(UserProfileResponse.self, body)

        #expect(dto.uuid == "01a06145-3caf-7614-a3bd-cee6e25316b1")
        #expect(dto.name == "김성윤")
        #expect(dto.imageUrl == "https://cdn.moyeota.co.kr/profile/presets/01.png")
        #expect(dto.toDomain().name == "김성윤")
    }

    /// 닉네임도 프로필 실명도 없으면 서버가 `orElse(null)` 로 null 을 내려보낸다.
    /// Jackson 이 null 을 지우지 않으므로 **키는 남고 값만 null** 이다 — 논-널 선언이면 여기서 터진다.
    @Test("이름이 null 이어도 파싱된다")
    func nullName() throws {
        let dto = try decodeJSON(UserProfileResponse.self, #"{"uuid":"u-1","name":null}"#)

        #expect(dto.name == nil)
        #expect(dto.toDomain().uuid == "u-1")
        #expect(dto.toDomain().name == nil)
    }

    // 서버가 나중에 null 필드를 빼도록 바뀌어도 살아남아야 한다.
    @Test("이름 키가 아예 없어도 파싱된다")
    func missingName() throws {
        let dto = try decodeJSON(UserProfileResponse.self, #"{"uuid":"u-1"}"#)

        #expect(dto.toDomain().name == nil)
    }

    /// 빈 문자열도 도메인에서는 null 이다 — 화면이 "없음"을 두 가지 방식으로 판정하게 두지 않는다.
    @Test("공백뿐인 이름은 없음으로 정규화한다")
    func blankName() {
        #expect(UserProfileResponse(uuid: "u-1", name: "").toDomain().name == nil)
        #expect(UserProfileResponse(uuid: "u-1", name: "   ").toDomain().name == nil)
    }

    /// 프로필 이미지 주소가 도메인까지 **그대로** 흘러야 아바타가 사진으로 그려진다.
    /// 매퍼가 이 필드를 떨어뜨리면 응답은 멀쩡한데 화면만 이니셜로 떨어져, 원인이 서버·CDN·이미지 로더
    /// 어디에도 없는 상태가 된다.
    @Test("imageUrl 이 도메인까지 흐른다")
    func imageUrlFlows() {
        let dto = UserProfileResponse(
            uuid: "u-1",
            name: "김성윤",
            imageUrl: "https://cdn.moyeota.co.kr/profile/presets/07.png"
        )

        #expect(dto.toDomain().imageUrl == "https://cdn.moyeota.co.kr/profile/presets/07.png")
    }

    /// 이름과 **같은 규칙**이다 — 두 필드가 서로 다른 "없음"을 가지면 화면이 폴백을 두 갈래로 만든다.
    /// 빈 문자열을 그대로 넘기면 이미지 로더가 그 주소를 실제로 요청해 실패한 뒤에야 이니셜로 떨어진다.
    @Test("공백뿐인 imageUrl 은 없음으로 정규화한다")
    func blankImageUrl() {
        #expect(UserProfileResponse(uuid: "u-1", imageUrl: "").toDomain().imageUrl == nil)
        #expect(UserProfileResponse(uuid: "u-1", imageUrl: "   ").toDomain().imageUrl == nil)
    }

    /// 구버전 서버(2026-10-15 배포 이전)에는 이 키가 없다. 논-널로 선언하면 그 서버를 붙인 순간
    /// 내 정보 조회가 통째로 터져 로그인 직후 화면이 열리지 않는다.
    @Test("imageUrl 키가 아예 없어도 파싱된다")
    func missingImageUrl() throws {
        let dto = try decodeJSON(UserProfileResponse.self, #"{"uuid":"u-1","name":"김성윤"}"#)

        #expect(dto.toDomain().imageUrl == nil)
    }

    /// ★ **서버는 두 제재 키를 아직 보내고, 앱은 그걸 받지 않는다.** 2026-11-12 에
    /// `UserProfileResponse` 에서 `noShowCount`·`restrictedUntil` 자리를 지웠다 — 백엔드가 노쇼
    /// 기능을 통째로 없애면서(`b16551b7`, V37 이 테이블 DROP) 두 값을 **늘 0·null 로 박았기**
    /// 때문이다(서버 주석: 「출시 앱 호환용으로 키만 남김」).
    ///
    /// 이 테스트가 못 박는 것은 **지운 쪽이 안전하다**는 사실이다: 서버가 계속 보내는 키를
    /// 받는 자리 없이 맞아도 디코더가 흘려보내므로(`MoyeotaJSON`) 내 정보 조회가 터지지 않는다.
    /// 이게 깨지면 증상은 「마이페이지가 안 열린다」가 아니라 **로그인 직후 전 화면에서 이름·사진이
    /// 사라지는 것**이다 — 조회가 통째로 실패한다.
    ///
    /// 아래 본문은 실제 서버 응답 모양 그대로다(`MyProfileResponse` record 5필드).
    ///
    /// (이 자리에 있던 제재 테스트 다섯 — 도메인까지 흐른다·null 이면 제한 없음·키가 없으면 기본값·
    /// 마이크로초·공백 정규화 안 함 — 은 받는 자리와 함께 지웠다.)
    @Test("서버가 보내는 제재 두 키를 받지 않아도 파싱이 깨지지 않는다")
    func sanctionKeysAreIgnored() throws {
        let body = """
            {"uuid":"u-1","name":"김성윤","imageUrl":"https://cdn.moyeota.co.kr/profile/presets/01.png",
             "noShowCount":0,"restrictedUntil":null}
            """

        let info = try decodeJSON(UserProfileResponse.self, body).toDomain()

        #expect(info.uuid == "u-1")
        #expect(info.name == "김성윤")
        #expect(info.imageUrl == "https://cdn.moyeota.co.kr/profile/presets/01.png")
        // 받는 자리가 되살아나지 않는다 — 고정값을 올리면 도메인에 「제재 없음」만 영원히 참인
        // 분기가 생긴다(`UserProfileResponse` 주석).
        let labels = Mirror(reflecting: info).children.compactMap(\.label)
        #expect(!labels.contains("noShowCount"), "UserProfileInfo 에 noShowCount 가 되살아났다")
        #expect(!labels.contains("restrictedUntil"), "UserProfileInfo 에 restrictedUntil 이 되살아났다")
    }

    /// 0·null 이 아닌 값이 실려 와도(롤백된 서버, 캐시된 응답) 받는 자리가 없으니 그대로 흘러야 한다 —
    /// 위 테스트가 0·null 만 넣으면 「값이 비어 있어서 통과한 것」과 구별되지 않는다.
    @Test("제재 키에 값이 실려 와도 흘려보낸다")
    func sanctionValuesAreIgnored() throws {
        let body = #"{"uuid":"u-1","name":"김성윤","noShowCount":2,"restrictedUntil":"2026-11-04T08:30:00Z"}"#

        #expect(try decodeJSON(UserProfileResponse.self, body).toDomain().name == "김성윤")
    }

    @Test("모르는 필드가 늘어나도 파싱이 깨지지 않는다")
    func unknownFields() throws {
        // DTO 가 가진 필드를 여기 쓰면 "모르는 필드"가 아니게 되어 아무것도 검사하지 않는 테스트가 된다.
        let body = #"{"uuid":"u-1","name":"김성윤","badgeId":3,"mannerScore":4.5}"#

        #expect(try decodeJSON(UserProfileResponse.self, body).toDomain().name == "김성윤")
    }

    // 원본에는 없는 테스트다 — 이슈 #35 §3. 프로필 DTO 는 호환 키(`badgeId`·`taxiEnabled`·`taxiDriverId`)를
    // 하나도 받지 않는다. 서버가 그 키들을 지우는 날에도 프로필이 그대로 읽히는지 가장 작은 본문으로 본다
    // (위 테스트는 반대로 키가 **있을 때** 흘리는 쪽이다).
    @Test("호환 키 없이도 프로필이 디코딩된다")
    func decodesWithoutCompatKeys() throws {
        let info = try decodeJSON(UserProfileResponse.self, #"{"uuid":"u-1","name":"김성윤"}"#).toDomain()

        #expect(info.uuid == "u-1")
        #expect(info.name == "김성윤")
    }

    // ─────────────────────────── loginId (Backend PR #330) ───────────────────────────

    /// 로컬 로그인 계정이면 서버가 **로그인 아이디**를 실어 준다 — 36 프로필 수정의 읽기 전용
    /// 「아이디」 행이 이 값 하나로 그려진다. 매퍼가 떨어뜨리면 응답은 멀쩡한데 행만 사라진다.
    @Test("loginId 가 있으면 도메인까지 흐른다")
    func loginIdFlowsToDomain() throws {
        let body = """
            {"uuid":"u-1","name":"김성윤","imageUrl":"https://cdn.moyeota.co.kr/profile/presets/01.png",
             "noShowCount":0,"restrictedUntil":null,"loginId":"hong123"}
            """

        let dto = try decodeJSON(UserProfileResponse.self, body)

        #expect(dto.loginId == "hong123")
        #expect(dto.toDomain().loginId == "hong123")
    }

    /// 로컬 로그인이 없는 계정은 **키는 남기고 값만 null** 이다(Jackson 기본 `ALWAYS`). 논-널로
    /// 선언했다면 그 계정의 내 정보 조회가 통째로 터져 로그인 직후 화면이 열리지 않는다.
    @Test("loginId 가 null 이면 아이디 없음으로 읽는다")
    func nullLoginId() throws {
        let dto = try decodeJSON(UserProfileResponse.self, #"{"uuid":"u-1","name":"김성윤","loginId":null}"#)

        #expect(dto.toDomain().loginId == nil)
    }

    /// PR #330 이전 배포에는 키 자체가 없다 — 기본값 nil 로 떨어져야 한다.
    @Test("loginId 키가 아예 없어도 파싱된다")
    func missingLoginIdKey() throws {
        let dto = try decodeJSON(UserProfileResponse.self, #"{"uuid":"u-1","name":"김성윤"}"#)

        #expect(dto.loginId == nil)
        #expect(dto.toDomain().loginId == nil)
    }

    /// 이름·사진과 같은 규칙 — 공백뿐인 아이디도 도메인에서는 없음이다(빈 값 행을 그리지 않게).
    @Test("공백뿐인 loginId 는 없음으로 정규화한다")
    func blankLoginIdNormalized() {
        #expect(UserProfileResponse(uuid: "u-1", loginId: "").toDomain().loginId == nil)
        #expect(UserProfileResponse(uuid: "u-1", loginId: "   ").toDomain().loginId == nil)
    }

    /// 목록 본문은 **엔벨로프 없는 벗은 배열**이다. 그리고 `ProfileImage.key` 는 서버에 보내는 값,
    /// `ProfileImage.url` 은 그리는 값이라 **두 필드가 뒤집히면** PATCH 가 400 `USER112` 로 거절되고
    /// 격자에는 아무것도 안 그려진다 — 원인이 응답 파싱이라 추적이 어려워 여기서 따로 못 박는다.
    ///
    /// 값 형태는 백엔드 `ProfileImages` 설정 기준이다(실서버 미호출): key 는 제로패딩된
    /// `profile/presets/NN.png`, url 은 그 key 를 CDN 주소에 붙인 값이다.
    @Test("프로필 이미지 항목은 key 와 url 이 뒤집히지 않는다")
    func profileImageKeyAndUrl() throws {
        let body = #"[{"key":"profile/presets/01.png","url":"https://cdn.moyeota.co.kr/profile/presets/01.png"}]"#

        let images = try decodeJSON([ProfileImageResponse].self, body).map { $0.toDomain() }

        #expect(
            images == [
                ProfileImage(key: "profile/presets/01.png", url: "https://cdn.moyeota.co.kr/profile/presets/01.png"),
            ]
        )
        // 같은 것을 다른 각도로 — 뒤집히면 key 에 주소가, url 에 S3 키가 들어온다.
        let image = try #require(images.first)
        #expect(images.count == 1)
        #expect(image.key.hasPrefix("profile/presets/"), "key 에 CDN 주소가 들어왔다 — 두 필드가 뒤집혔다")
        #expect(image.url.hasPrefix("https://"), "url 에 S3 키가 들어왔다 — 두 필드가 뒤집혔다")
    }

    /// 설정이 비면 서버는 `[]` 를 준다. 이것도 정상 응답이라 파싱·매핑이 빈 목록으로 끝나야 한다
    /// — 예외로 바꾸면 같은 화면의 닉네임 수정까지 막힌다.
    @Test("빈 이미지 목록도 정상 파싱된다")
    func emptyImageList() throws {
        let images = try decodeJSON([ProfileImageResponse].self, "[]").map { $0.toDomain() }

        #expect(images.isEmpty)
    }
}
