import MoyeotaDomain

extension UserProfileResponse {
    /// `MyProfileResponse` → `UserProfileInfo`.
    ///
    /// 서버의 `name` 은 "닉네임 → 실명 → null" 폴백의 결과라 **빈 문자열도 없음으로 취급한다** —
    /// 화면이 빈 값과 null 을 따로 다루게 두면 폴백 표시가 두 갈래로 갈라진다.
    /// 도메인에서 없음은 오직 `null` 하나다.
    ///
    /// `UserProfileInfo.imageUrl` 에도 **같은 규칙**을 쓴다. 두 필드가 서로 다른 "없음"을 가지면
    /// 화면이 폴백을 두 갈래로 만들게 된다.
    ///
    /// ### 제재 두 필드는 **손대지 않고 그대로 옮긴다** ★
    /// `UserProfileInfo.restrictedUntil` 에 이름·이미지와 같은 공백 정규화(`takeIfNotBlank`)를
    /// 걸지 않는다. 걸어도 지금은 결과가 같지만(서버는 빈 문자열을 보내지 않는다) **이 필드의 「없음」은
    /// 뜻이 다르다**: 이름의 null 은 「표시할 이름이 없다」라 폴백 문구로 메우면 되고, 이쪽의 null 은
    /// **「제한이 없다」는 사실 판정**이다. 정규화를 끼우면 「서버가 뭔가 보냈지만 비어 있었다」가
    /// 「제한 없음」으로 조용히 접히고, 화면은 막힌 사용자에게 아무 안내도 하지 않는다.
    /// 그래서 이 자리는 **변환이 없는 것이 설계**다 — 모양 판정(파싱 가능한 instant 인가)은 화면이 한다.
    ///
    /// `UserProfileInfo.noShowCount` 도 같다 — 음수 방어(`max(0, …)`) 같은 걸 넣지 않는다.
    /// 서버 record 가 `count(*)` 결과의 원시 `int` 라 음수가 나올 길이 없고, 넣으면 서버가 틀렸을 때
    /// **틀린 값을 그럴듯한 값으로 가려** 원인을 찾을 수 없게 된다.
    ///
    /// ### `UserProfileInfo.loginId` 는 이름과 **같은 공백 정규화**를 건다
    /// 이쪽의 「없음」은 제재와 달리 사실 판정이 아니라 **「보여 줄 아이디가 없다」**이고, 화면이 하는 일도
    /// 하나(행을 숨긴다)다. 빈 문자열을 그대로 넘기면 36 이 라벨만 있고 값이 빈 「아이디」 행을 그린다 —
    /// 그래서 이름·사진과 같이 도메인의 없음을 `nil` 하나로 모은다.
    func toDomain() -> UserProfileInfo {
        UserProfileInfo(
            uuid: uuid,
            name: name?.takeIfNotBlank(),
            imageUrl: imageUrl?.takeIfNotBlank(),
            noShowCount: noShowCount,
            restrictedUntil: restrictedUntil,
            loginId: loginId?.takeIfNotBlank()
        )
    }
}

extension ProfileImageResponse {
    /// `ProfileImageResponse` → `ProfileImage`.
    ///
    /// 필드를 **뒤집지 않는 것**이 이 매퍼의 전부다 — `ProfileImage.key` 는 서버에 보내는 값이고
    /// `ProfileImage.url` 은 그리는 값이라, 바뀌면 PATCH 가 400 `USER112` 로 거절된다
    /// (그리고 격자에는 아무것도 안 그려진다). 이름 인자를 쓰는 이유가 그것이다.
    func toDomain() -> ProfileImage {
        ProfileImage(
            key: key,
            url: url
        )
    }
}
