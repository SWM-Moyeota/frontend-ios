import MoyeotaDesignSystem
import PresentationCore
import SwiftUI

// 39·40 정산 화면의 공용 조각들 — **두 화면에서만** 쓰이므로 디자인시스템으로 올리지 않는다
// (2개 이상 **기능**에서 쓰이는 새 UI 요소만 승격한다. 여기 있는 것들은 정산 두 화면 전용이고
// 「복사」 버튼처럼 이 도메인에만 있는 개념을 담는다).
//
// 색·글자·간격·모양은 전부 토큰(`MoyeotaColor`·`MoyeotaType`·`MoyeotaSpacing`·`MoyeotaShape`)에서 가져온다 —
// 이 모듈에 숫자로 정한 크기는 한 줄도 없다. 크기가 필요한 자리는 그 크기를 아는 디자인시스템 부품을 쓴다
// (`AvatarCircle`·`CompactPillButton`·`HorizontalDivider`).

/// 정산 화면의 뜻(`FareSplitTone`) → 디자인 시스템의 색 종류. **여기가 둘을 잇는 유일한 자리다.**
func noticeKindOf(_ tone: FareSplitTone) -> NoticeKind {
    switch tone {
    case .info: .info
    case .warn: .waiting
    case .done: .success
    case .danger: .error
    }
}

/// 배지 하나. 글자와 색을 함께 든 `FareSplitBadge` 를 그대로 받는다 — 호출부가 색을 고르지 않는다.
struct FareSplitBadgeChip: View {
    let badge: FareSplitBadge

    var body: some View {
        StatusBadge(kind: noticeKindOf(badge.tone), text: badge.label)
            .fixedSize()
    }
}

/// 안내 한 줄. `FareSplitBadge` 를 띠로 그린다.
struct FareSplitNotice: View {
    let badge: FareSplitBadge

    var body: some View {
        NoticeBanner(kind: noticeKindOf(badge.tone), text: badge.label)
    }
}

/// 흰 카드 한 장. 이 화면들의 모든 블록이 같은 모양이라 한 곳에 둔다.
///
/// 원본은 1dp 헤어라인 테두리를 두르지만 여기서는 두르지 않는다 — 회색 바탕(`SurfaceSoft`) 위의 흰 카드는
/// 면만으로 갈리고, 34 지난 탑승 기록의 카드가 같은 모양이다(디자인 QA G4: 흰 면 위가 아니면 선을 더하지 않는다).
struct FareSplitCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MoyeotaSpacing.Sm) {
            content()
        }
        .padding(MoyeotaSpacing.Md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoyeotaColor.SurfaceCard, in: MoyeotaShape.Card)
    }
}

/// 카드 안의 소제목.
struct FareSplitSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// `라벨 ────── 값` 한 줄. 값을 **강조할지**(`strong`) 고를 수 있다 — 같은 카드 안에서 「아직 못 받은 돈」과
/// 「받을 돈 전체」의 무게가 달라야 한다.
struct FareSplitKeyValueRow: View {
    let label: String
    let value: String
    var strong = false

    var body: some View {
        HStack(alignment: .center, spacing: MoyeotaSpacing.Xs) {
            Text(label)
                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .moyeotaText(
                    strong ? MoyeotaType.HeadingLg.tabularNums().hangulTrimmed : MoyeotaType.BodyMd.tabularNums().hangulTrimmed,
                    color: strong ? MoyeotaColor.Primary600 : MoyeotaColor.InkPrimary
                )
        }
        .accessibilityElement(children: .combine)
    }
}

/// 이름 자리의 이니셜 원.
///
/// `MemberDisplay.MemberAvatar` 를 쓰지 않는 이유: 그쪽은 `User` 를 받아 **프로필 사진**을 그리고
/// 실패하면 이니셜로 떨어지는데, 정산 응답에는 `User` 도 `imageUrl` 도 없다(서버가 정산에
/// 프로필 사진을 싣지 않는다). 즉 사진을 그릴 거리가 **애초에 없어서** 그 폴백 장치 전체가
/// 쓸모가 없다 — 디자인시스템의 `AvatarCircle` 에 글자만 넘긴다(사진 주소가 없으면 요청도 만들지 않는다).
struct FareSplitInitialCircle: View {
    let name: String

    var body: some View {
        AvatarCircle(label: name.first.map(String.init) ?? "?")
            .accessibilityHidden(true)
    }
}

/// 보조 설명 한 줄(작고 회색). 「왜 이 칸이 있는가」를 적는 자리다.
struct FareSplitHint: View {
    let text: String

    var body: some View {
        Text(text)
            .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 계좌·금액 한 줄 + **복사 버튼** — 토스가 열리지 않는 기기에서 유일하게 남는 길이다.
///
/// ### 이 버튼은 선택이 아니라 요구사항이다 ★
/// 서버 주석 원문: 「비공식 규격이라 열리지 않을 수 있어 계좌·금액 복사 버튼을 함께 둔다」.
/// 토스 버튼 **옆**이 아니라 계좌·금액 **바로 옆**에 두는 이유: 토스가 열리지 않는 것을 확인한
/// 사용자가 다음으로 보는 곳이 숫자 그 자체다.
///
/// **복사되는 값과 보이는 값을 따로 받는다**(`display` · `copyValue`). 계좌번호는 사람이 읽기 쉽게
/// 끊어 보여 줄 수 있지만 **복사되는 값은 숫자만**이어야 한다 — 은행 앱 붙여넣기 칸이 하이픈을
/// 거절하는 경우가 있다(`ManualTransfer` 주석).
///
/// 눌렀을 때의 확인은 버튼이 아니라 토스트가 한다(`copyToPasteboard` 주석 — iOS 는 복사할 때 OS 가
/// 아무것도 보여 주지 않는다). 그래서 이 줄은 상태를 들지 않는다.
struct CopyableValueRow: View {
    let label: String
    let display: String
    let copyValue: String
    let target: FareSplitCopyTarget
    let onCopy: (FareSplitCopyTarget, String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: MoyeotaSpacing.Xs) {
            VStack(alignment: .leading, spacing: MoyeotaSpacing.Xxs) {
                Text(label)
                    .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                Text(display)
                    .moyeotaText(MoyeotaType.HeadingMd.tabularNums().hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            // 은행 줄의 라벨은 은행 이름이라 「카카오뱅크 복사」로 읽히면 무엇을 복사하는지 모른다 — 대상으로 읽는다.
            CompactPillButton(text: "복사", onClick: { onCopy(target, copyValue) })
                .accessibilityLabel(target == .accountNumber ? "계좌번호 복사" : "금액 복사")
        }
    }
}
