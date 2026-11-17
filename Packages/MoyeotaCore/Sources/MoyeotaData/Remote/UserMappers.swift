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
    /// ### 제재 두 필드는 **DTO 에서부터 없다** (2026-11-12)
    /// 서버가 `noShowCount`·`restrictedUntil` 키를 아직 싣지만 값이 영원히 0·nil 로 고정이라
    /// `UserProfileResponse` 가 받지 않는다 — 근거는 그쪽 주석에 있다. 그래서 이 매퍼에 옮길 자리도
    /// 없고, **다시 만들지 마라**: 고정값을 올리면 도메인에 「제재 없음」만 영원히 참인 분기가 생긴다.
    ///
    /// ### `UserProfileInfo.loginId` 는 이름과 **같은 공백 정규화**를 건다
    /// 이쪽의 「없음」은 사실 판정이 아니라 **「보여 줄 아이디가 없다」**이고, 화면이 하는 일도
    /// 하나(행을 숨긴다)다. 빈 문자열을 그대로 넘기면 36 이 라벨만 있고 값이 빈 「아이디」 행을 그린다 —
    /// 그래서 이름·사진과 같이 도메인의 없음을 `nil` 하나로 모은다.
    func toDomain() -> UserProfileInfo {
        UserProfileInfo(
            uuid: uuid,
            name: name?.takeIfNotBlank(),
            imageUrl: imageUrl?.takeIfNotBlank(),
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
