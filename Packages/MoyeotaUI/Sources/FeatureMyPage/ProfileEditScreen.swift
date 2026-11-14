import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 사진 격자의 열 수. 4 외에는 답이 없다 — 근거는 `ProfileImageGrid` 주석.
private let PROFILE_IMAGE_COLUMNS = 4

/// 셀 사이 · 행 사이 간격. 이 앱이 쓰던 12 간격과 같은 값이다.
private let ProfileImageGap: CGFloat = 12

/// 36 · 프로필 수정 (신규)
///
/// 진입: 35 마이페이지 프로필 카드 / 뒤로 → 35 / 「저장」 성공 → 35 (이름·사진 다시 조회)
///
/// 구성: 상단바 「프로필 수정」 → (로컬 로그인 계정만) 「아이디」 읽기 전용 행 → 닉네임 입력
/// (글자수 · 중복 확인) → 프로필 사진 격자 16장 + 「기본 이미지로 되돌리기」 → 「저장」
///
/// 바꿀 수 있는 값이 **닉네임과 프로필 사진 둘**인 이유: `PATCH /api/v1/users/me` 가 받는 게 그 둘이고,
/// 사진은 서버가 준비한 16장 중에서 고르는 것뿐이다(업로드 경로가 서버에 없다). 실명 · 생년월일 ·
/// 성별 · 휴대폰 · 이메일은 서버에 수정 경로가 아예 없다. 그래서 「수정 불가」 행을 늘어놓는 대신
/// 바꿀 수 있는 것만 둔다(`docs/BACKEND-GAP-CLEANUP.md` 의 원칙).
///
/// ### 「아이디」 행은 그 원칙의 **유일한 예외**다 (2026-11, 오너 승인)
/// 바꿀 수 없는 값인데도 두는 이유는 쓰임이 다르기 때문이다: 실명·생년월일은 사용자가 이미 아는 값이지만,
/// **로그인 아이디는 잊는 값**이고 「내 아이디가 뭐였지」를 확인하러 오는 자리가 바로 여기다. 서버가
/// `GET /local/users/info` 에 `loginId` 를 실어 주면서(Backend PR #330) 보여 줄 근거가 생겼다.
///
/// - **읽기 전용 행**이지 비활성 입력칸이 아니다(`LoginIdRow`) — 흐린 입력칸은 「언젠가 눌러서 바꾼다」로
///   읽히는데 아이디는 바꾸는 서버 경로가 없다. 닉네임 필드와 같은 뼈대에 테두리 없는 채움 면이다.
/// - 로컬 로그인이 없는 계정(서버가 nil)·조회 실패·공백이면 **행을 통째로 숨긴다**(`loginId` 가 nil).
///   빈 값 행을 남기면 「아이디가 지워졌다」로 읽힌다.
///
/// 규칙 · 문구 · 확인 방식은 10 프로필 만들기와 같은 것을 쓴다(`NicknamePolicy`, `NicknameCheckState`,
/// 입력이 멈춘 뒤 자동 중복 확인) — 같은 값을 두 화면이 다른 기준으로 받으면 둘 중 하나는 거짓말이 된다.
///
/// ### 지금 쓰는 사진을 격자에 미리 선택해 두지 않는다 — 열려 있는 결정이다
/// 서버는 내 사진의 **key** 를 알려 주는 창구가 없다 — `GET /api/v1/local/users/info` 는 URL 만 준다.
/// 그래서 격자의 선택 표시는 **「이번에 탭한 것」만** 뜻하고, 아무것도 안 탭했으면 아무 칸도
/// 선택되지 않는다. 지금 쓰는 사진은 35 마이페이지의 프로필 카드가 보여 준다.
///
/// **「역추적이 엉뚱한 칸을 맞힌다」는 근거는 쓰지 말 것 — 사실이 아니다.** 백엔드는 두 URL 을 같은
/// 한 메서드로 만들고(`ProfileImages.toUrl(key) = baseUrl + key`), 목록의 `url` 도 내 `imageUrl` 도
/// 거기서 나온다. 즉 **문자열 완전 일치로 비교하면 빗나갈 수 없고**, base-url 이 바뀌면 양쪽이 함께
/// 바뀐다. 쿼리스트링이 붙어 일치가 깨지면 「선택 없음」이 되는데 그건 지금 동작과 같다.
///
/// 그래서 이건 위험 회피가 아니라 **아직 안 만든 것**이다. 지금의 비용은 「내가 쓰는 사진이 어느 칸인지
/// 화면에서 알 수 없다」이고, 만든다면 `images.first { $0.url == 진입시_imageUrl }?.key` 를
/// **진입 시점의 key** 로 따로 들고 `ImageIntent.pick` 과 구분해야 한다 — 그걸 pick 으로 두면
/// 아무것도 안 바꿨는데 「저장」이 켜지고 불필요한 PATCH 가 나간다.
///
/// - Parameter nickname: 입력 중인 값. 진입 시 서버의 현재 표시 이름으로 채워져 있다.
/// - Parameter currentNickname: 서버가 준 현재 표시 이름. 이 값과 같으면 **닉네임은** 저장할 게 없다
///   — 사진이 바뀌었으면 「저장」 은 켜진다(`canSaveProfile`).
/// - Parameter check: 중복 확인 결과. 입력이 멈춘 뒤 `ProfileEditRoute` 가 서버에 물어 갱신한다.
/// - Parameter images: 고를 수 있는 프리셋. **비어 있으면 사진 섹션을 접는다** — 조회 실패에 문구를 띄우지
///   않는다(사용자가 고칠 게 없다). 닉네임 수정은 그대로 된다.
/// - Parameter imageIntent: 이 화면에서 사진에 내린 결정. 격자의 선택 표시와 「저장」 활성의 근거다.
/// - Parameter usingDefaultImage: 진입 시점의 사진이 기본 이미지인가. 「되돌리기」를 보일지만 정한다.
/// - Parameter errorMessage: 저장 실패 사유. 중복 · 형식 오류는 필드가 말하므로 여기엔 오지 않는다.
///   사진 키 오류(400 `USER112`)는 **여기로** 온다 — 닉네임 필드로 돌리면 거짓이다.
/// - Parameter imagesLoadFailed: 사진 목록 조회가 실패했다. **빈 목록과 다르게** 그린다 — 섞으면 섹션이 통째로 사라진다.
/// - Parameter loginId: 보여 줄 로그인 아이디. **nil 이면 「아이디」 행을 그리지 않는다**
///   (`profileLoginIdOrNull` 이 공백·미조회·로컬 로그인 없음을 모두 nil 로 접어 준다).
public struct ProfileEditScreen: View {
    private let nickname: String
    private let loginId: String?
    private let currentNickname: String?
    private let check: NicknameCheckState
    private let images: [ProfileImage]
    private let imageIntent: ImageIntent
    private let usingDefaultImage: Bool
    private let saving: Bool
    private let errorMessage: String?
    private let onNicknameChange: (String) -> Void
    private let onImagePick: (String) -> Void
    private let imagesLoadFailed: Bool
    private let onRetryImages: () -> Void
    private let onImageReset: () -> Void
    private let onSave: () -> Void
    private let onBack: () -> Void

    public init(
        nickname: String,
        loginId: String? = nil,
        currentNickname: String? = nil,
        check: NicknameCheckState = .idle,
        images: [ProfileImage] = [],
        imageIntent: ImageIntent = .none,
        usingDefaultImage: Bool = true,
        saving: Bool = false,
        errorMessage: String? = nil,
        onNicknameChange: @escaping (String) -> Void = { _ in },
        onImagePick: @escaping (String) -> Void = { _ in },
        imagesLoadFailed: Bool = false,
        onRetryImages: @escaping () -> Void = {},
        onImageReset: @escaping () -> Void = {},
        onSave: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        self.nickname = nickname
        self.loginId = loginId
        self.currentNickname = currentNickname
        self.check = check
        self.images = images
        self.imageIntent = imageIntent
        self.usingDefaultImage = usingDefaultImage
        self.saving = saving
        self.errorMessage = errorMessage
        self.onNicknameChange = onNicknameChange
        self.onImagePick = onImagePick
        self.imagesLoadFailed = imagesLoadFailed
        self.onRetryImages = onRetryImages
        self.onImageReset = onImageReset
        self.onSave = onSave
        self.onBack = onBack
    }

    public var body: some View {
        let fieldError = nicknameEditError(input: nickname, currentNickname: currentNickname, check: check)
        let unchanged = isNicknameUnchanged(input: nickname, currentNickname: currentNickname)
        let canSave = canSaveProfile(
            nickname: nickname,
            currentNickname: currentNickname,
            check: check,
            imageIntent: imageIntent,
            saving: saving
        )
        let canResetImage = canResetProfileImage(usingDefaultImage: usingDefaultImage, imageIntent: imageIntent)
        let helperText: String? = if fieldError != nil {
            nil
        } else if check == .checking {
            "사용할 수 있는지 확인하고 있어요"
        } else if unchanged {
            // 그대로인 닉네임에는 도움말을 달지 않는다 — 칸 안의 값이 이미 말하는 것이다(디자인 QA P2)
            nil
        } else if !nickname.isEmpty {
            "탑승 상대에게는 「\(nickname)」 으로 보여요"
        } else {
            nil
        }

        VStack(spacing: 0) {
            StatusBarSpacer()
            MoyeotaTopBar(title: "프로필 수정", onBack: onBack)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // 제목 줄(「닉네임과 프로필 사진을 바꿀 수 있어요」)은 두지 않는다 — 상단바 「프로필 수정」과
                    // 바로 아래 입력칸이 이미 말하는 것을 한 번 더 읽히는 문장이었다(디자인 QA P2).
                    Spacer().frame(height: 16)
                    // 실명이 공개되지 않는다는 사실을 한 번 더 말해 둔다 — 10 에서 이미 안내했지만,
                    // 이름을 바꾸러 들어온 순간이 그 사실을 가장 확인하고 싶을 때다
                    Text("탑승 상대에게 보이는 유일한 이름이에요. 실명은 공개되지 않아요")
                        .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)

                    // 「아이디」는 닉네임 **위**다 — 계정의 신원(바뀌지 않는 것)이 먼저, 꾸미는 값이 그다음이다.
                    // 공백·nil 이면 행과 그 아래 간격까지 통째로 없다(빈 자리를 남기지 않는다).
                    if let loginId, !loginId.isBlank {
                        Spacer().frame(height: 24)
                        LoginIdRow(loginId: loginId)
                    }

                    Spacer().frame(height: 24)
                    MoyeotaTextField(
                        value: nickname,
                        onValueChange: onNicknameChange,
                        label: "닉네임",
                        placeholder: "2~10자 한글·영문·숫자",
                        errorText: fieldError,
                        helperText: helperText,
                        enabled: !saving
                    ) {
                        // 원본 `String.length` 는 UTF-16 칸 수다. 입력을 자르는 기준과 같아야 카운터가 맞다.
                        Text("\(nickname.utf16.count) / \(NicknamePolicy.MAX_LENGTH)")
                            .moyeotaText(.CaptionMd, color: MoyeotaColor.TextMute)
                    }
                    // 사용 가능 확인만 초록으로 따로 세운다 — 나머지 상태는 필드가 자기 색으로 그린다.
                    // 확인에 실패한 경우(네트워크)는 아무 말도 하지 않는다: 사용자가 고칠 수 있는 게 없다.
                    if fieldError == nil && !unchanged && check == .available {
                        Spacer().frame(height: 6)
                        Text("사용 가능한 닉네임이에요")
                            // Success500 은 흰 바탕 대비 2.5:1 — 12pt 글자에는 한 단계 진한 600(4.1:1)을 쓴다
                            .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.Success600)
                    }

                    // 사진 섹션은 닉네임 입력 **아래**다. 위에 두면 격자 높이가 콘텐츠 폭과 같아져
                    // 닉네임 입력칸이 접힌선 아래로 밀려 작은 화면에서 보이지 않는다
                    // — 이 화면에 들어오는 가장 흔한 이유가 닉네임 변경인데 그게 안 보이게 된다.
                    //
                    // 목록도 없고 되돌릴 것도 없으면 섹션 자체를 접는다. 빈 자리에 「프로필 사진」 머리말만
                    // 남으면 고를 것이 있는 것처럼 읽힌다.
                    //
                    // **단 「조회 실패」는 접지 않는다.** 접으면 사진을 바꾸러 들어온 사용자에게 섹션이
                    // 흔적 없이 사라져 「이 앱에는 사진 기능이 없다」로 읽힌다 — 고장인지 아닌지도 알 수 없고
                    // 다시 받을 손잡이도 없다. 그래서 실패는 섹션을 **남기고** 그 자리에서 말한다.
                    if !images.isEmpty || canResetImage || imagesLoadFailed {
                        Spacer().frame(height: 24)
                        Text("프로필 사진")
                            .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        if images.isEmpty && imagesLoadFailed {
                            Spacer().frame(height: 4)
                            Text("사진 목록을 불러오지 못했어요")
                                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                            // 글자 앞 8 안쪽 여백만큼 밖으로 당겨 글자 시작을 화면 여백에 맞춘다
                            TextLinkButton(
                                text: "다시 시도",
                                onClick: onRetryImages,
                                enabled: !saving
                            )
                            .offset(x: -8)
                        }
                        if !images.isEmpty {
                            // 「준비된 그림 중에서 고를 수 있어요」 한 줄은 두지 않는다 — 바로 아래 격자가 그 말을
                            // 그림으로 보여 준다(디자인 QA P2). 업로드 칸이 없다는 것도 격자만 있는 모양이 말한다.
                            Spacer().frame(height: ProfileImageGap)
                            ProfileImageGrid(
                                images: images,
                                // 선택 표시는 「이번에 탭한 것」만 뜻한다 — 함수 주석의 역추적 금지 참조.
                                selectedKey: selectedKey,
                                enabled: !saving,
                                onPick: onImagePick
                            )
                        }
                        if canResetImage {
                            Spacer().frame(height: 4)
                            ProfileImageResetAction(enabled: !saving, onClick: onImageReset)
                        }
                    }

                    // 저장 실패 사유는 화면을 갈아엎지 않고 입력·격자 아래에 남긴다 — 고칠 곳이 위에 있기
                    // 때문 (04a 로그인과 같은 표기 방식)
                    if let errorMessage {
                        Spacer().frame(height: 16)
                        NoticeBanner(kind: .error, text: errorMessage)
                    }
                    Spacer().frame(height: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            // 원본 `verticalScroll` 은 자기 칸에서 잘린다.
            .clipped()
            // 원본 `verticalScroll` 은 스크롤해도 키보드를 내리지 않는다 — 입력하다 사진 격자로 내려가도 입력이 이어진다.
            .scrollDismissesKeyboard(.never)

            PrimaryCtaButton(
                text: "저장",
                onClick: onSave,
                enabled: canSave,
                loading: saving
            )
            .padding(.horizontal, 16)
            Spacer().frame(height: 16)
            NavigationBarSpacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 흰 바탕(디자인 QA G2·P1). 예전 SurfaceSoft 바탕 위에서는 비활성 「저장」이 바탕과 1.01:1 이라
        // 버튼 모양이 사라졌고, 「아이디」 행의 SurfaceSoft 채움도 바탕에 묻혀 보이지 않았다.
        .background(MoyeotaColor.SurfaceCanvas)
    }

    private var selectedKey: String? {
        if case .pick(let key) = imageIntent { key } else { nil }
    }
}

/// 「아이디」 읽기 전용 행 — 닉네임 필드와 **같은 뼈대**(라벨 위 · 8 · 52 줄 · 안쪽 16)에
/// **테두리 없는 `SurfaceSoft` 채움**을 얹는다(디자인 QA 4-1).
///
/// ### 왜 비활성 `MoyeotaTextField` 가 아닌가
/// 회색으로 죽은 입력칸(흐린 글자 + 테두리)은 「지금은 막혔지만 원래는 고치는 칸」으로 읽힌다 — 사용자는
/// 어딘가에 잠금을 푸는 길이 있다고 생각하고 찾는다. 아이디는 바꾸는 서버 경로 자체가 없다. 그래서
/// 이 행은 입력칸의 표지(테두리·포커스·커서)를 하나도 갖지 않고, 값은 **흐리게 하지 않는다**(`BodyMd`
/// · `InkPrimary` — 비활성처럼 보이는 낮은 대비를 쓰지 않는다). 채움 면은 「값을 담은 칸」이라는 것만
/// 말한다. 자물쇠·꺾쇠·도움말 글은 두지 않는다 — 누를 것이 없는 줄에 누를 것처럼 보이는 표지를 달지 않는다.
///
/// 뼈대를 닉네임 필드와 맞추는 이유는 두 줄이 **같은 목록의 항목**으로 읽혀야 해서다(높이·여백이 다르면
/// 서로 다른 종류의 요소로 보인다).
///
/// VoiceOver 에는 「아이디, hong123」 한 문장으로 읽힌다 — 따로 읽히면 라벨과 값이 무엇의 짝인지
/// 끊긴다. 누를 수 있는 것이 없으므로 버튼 특성은 싣지 않는다. 원본처럼 길게 눌러 복사하는 동작도 없다
/// (원본 주석이 iOS 에 `.textSelection(.enabled)` 를 대안으로 적어 두었지만, 원본 화면도 복사를 받지 않아 옮기지 않았다).
private struct LoginIdRow: View {
    let loginId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("아이디")
                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
            Spacer().frame(height: 8)
            // 아이디는 공백 없는 한 덩어리다 — 길면 줄을 바꾸기보다 끝을 줄인다(전체는 VoiceOver 가 읽는다).
            // 한글이 없는 값이라 한글 글자 상자(`hangulTrimmed`)를 쓰지 않는다.
            Text(loginId)
                .moyeotaText(.BodyMd, color: MoyeotaColor.InkPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 52)
                .background(MoyeotaColor.SurfaceSoft, in: MoyeotaShape.Card)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("아이디, \(loginId)")
    }
}

/// 프리셋 사진 격자.
///
/// ### `LazyVGrid` 를 쓰지 않는다
/// 이 본문은 이미 `ScrollView` 안이고 목록은 수가 작고 고정(16장)이라 Lazy 로 아낄 것도 없다.
/// 원본과 같게 네 칸씩 잘라 `HStack` 으로 직접 깐다.
///
/// ### 4열이 유일한 답이다
/// 셀 폭 = (화면폭 − 좌우 16 둘 − 간격 12 셋) / 4 → 320 에서 63, 360 에서 73, 412 에서 86.
/// 8열은 전 구간에서 48 터치 타깃에 못 미치고, 3열·5열은 16을 나누지 못해 마지막 행이 깨진다.
///
/// 마지막 행에 남는 칸은 빈 칸으로 채워 **왼쪽 정렬을 유지한다.** Repository 계약이 「수를 가정하지
/// 말라」고 적어 둔 대로 서버가 16장이 아닌 수를 줄 수 있는데, 빈 칸을 안 채우면 그 행의 사진만
/// 커져 격자가 무너진다.
private struct ProfileImageGrid: View {
    let images: [ProfileImage]
    let selectedKey: String?
    let enabled: Bool
    let onPick: (String) -> Void

    var body: some View {
        let rows = stride(from: 0, to: images.count, by: PROFILE_IMAGE_COLUMNS).map { start in
            Array(images[start..<min(start + PROFILE_IMAGE_COLUMNS, images.count)])
        }
        VStack(spacing: ProfileImageGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowImages in
                HStack(spacing: ProfileImageGap) {
                    ForEach(Array(rowImages.enumerated()), id: \.offset) { columnIndex, image in
                        ProfileImageCell(
                            image: image,
                            // 서버가 key 외에 이름을 주지 않아 번호로 읽어 준다.
                            number: rowIndex * PROFILE_IMAGE_COLUMNS + columnIndex + 1,
                            selected: image.key == selectedKey,
                            enabled: enabled,
                            onClick: { onPick(image.key) }
                        )
                    }
                    ForEach(0..<(PROFILE_IMAGE_COLUMNS - rowImages.count), id: \.self) { _ in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        // 격자 전체가 **한 묶음**이라는 사실을 VoiceOver 에 싣는다. iOS 에는 라디오 그룹 역할이 없어
        // 컨테이너로 묶고, 칸마다 선택 상태를 싣는다.
        .accessibilityElement(children: .contain)
    }
}

/// 격자의 한 칸.
///
/// **색만으로 선택을 표시하지 않는다.** 이 앱에는 그런 자리가 한 곳도 없고, 항상 (테두리 또는 채움) +
/// (굵기 또는 그림자)가 함께 바뀐다 — 성별 칩 `SignupChoiceChip` 과 `MoyeotaChip` 이 쓰는 문법이다.
/// 여기서는 배경(`SurfaceCanvas` → `Primary50`)과 테두리(1 `Hairline` → 2 `Primary500`)가
/// 같이 바뀐다. 인원수 칩의 솔리드 채움은 **쓸 수 없다 — 그림을 덮는다.**
///
/// 안쪽 4 여백 덕에 선택 링이 그림 위에 겹치지 않는다. 프리셋은 투명 배경 위 원형 아트워크라
/// (알파 0 이 20.6%) 꽉 채우면 원 테두리와 그림의 외곽선이 맞붙어 지저분해진다.
private struct ProfileImageCell: View {
    let image: ProfileImage
    let number: Int
    let selected: Bool
    let enabled: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            // `MoyeotaAsyncImage` 는 내용이 나타날 때 요청을 시작한다. 사진 전에도 뷰가 있어야 하므로
            // `Color.clear` 위에 얹는다. 크기도 칸이 정하고, 기본값이 원 안의 레터박스가 되지 않게 채워서 자른다.
            MoyeotaAsyncImage(url: image.url) { uiImage in
                Color.clear.overlay {
                    if let uiImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
            .clipShape(Circle())
            .padding(4)
            .background(selected ? MoyeotaColor.Primary50 : MoyeotaColor.SurfaceCanvas, in: Circle())
            .overlay(
                Circle().strokeBorder(
                    selected ? MoyeotaColor.Primary500 : MoyeotaColor.Hairline,
                    lineWidth: selected ? 2 : 1
                )
            )
            .contentShape(Circle())
        }
        // 눌림 표시도 원 안에만 칠한다 — 원 바깥 네 모서리에는 페이지 배경이 보인다.
        .buttonStyle(PressOverlayStyle(shape: Circle()))
        .disabled(!enabled)
        .aspectRatio(1, contentMode: .fit)
        // 「지금 어느 칸이 골라져 있는가」가 VoiceOver 에 전달돼야 한다.
        .accessibilityLabel("프로필 이미지 \(number)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 「기본 이미지로 되돌리기」.
///
/// 화면 본문의 글자 행동은 디자인시스템 `TextLinkButton` 하나로 그린다(디자인 QA G12) — 보이는 건 글자
/// 한 줄이지만 터치 영역이 48 이다. 14pt 글자 한 줄은 터치 영역이 25 도 안 되어
/// 「저장」 바로 위에서 오타처럼 눌린다.
///
/// 누르면 **로컬 선택만 바뀐다.** 이 화면의 커밋 지점은 「저장」 하나다 — 되돌리기만 즉시 서버로
/// 나가면 「저장을 안 눌렀는데 사진이 바뀜」이 생긴다.
private struct ProfileImageResetAction: View {
    let enabled: Bool
    let onClick: () -> Void

    var body: some View {
        TextLinkButton(
            text: "기본 이미지로 되돌리기",
            onClick: onClick,
            enabled: enabled
        )
        // 글자 앞 8 안쪽 여백만큼 밖으로 당겨 글자 시작을 화면 여백에 맞춘다
        .offset(x: -8)
    }
}
