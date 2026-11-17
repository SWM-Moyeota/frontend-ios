import MoyeotaDesignSystem
import PresentationCore
import SwiftUI

// 06 · 학교 이메일 [S02]
//
// ⚠️ 현재 어떤 그래프에도 등록되어 있지 않다 — 가입 필수 경로에서 05~08 을 걷어냈다.
// 가입 API 에 학교 인증 개념이 없고, 인증은 마이페이지에서 나중에 붙이는 컨셉이다.
// 그때 이 화면을 그대로 재사용하기 위해 파일은 남겨 둔다(MainNavGraph 의 C 절 주석 참고).
//
// (원래 배선) 진입: 05에서 「학생」 선택 / 뒤로 → 05 / 「인증 메일 보내기」 → 07 인증 코드
let SupportedDomains = ["@pusan.ac.kr", "@pukyong.ac.kr", "@donga.ac.kr"]

// 유효값 검증: 로컬파트 — 영문·숫자·. _ - 만 허용, 2~64자, 공백 불가
let LocalPartRegex = JavaRegex("^[A-Za-z0-9._-]{2,64}$")

public struct SchoolEmailScreen: View {
    private let onBack: () -> Void
    private let onSendMail: (_ email: String) -> Void

    @State private var localPart = ""
    @State private var domain = SupportedDomains[0]
    @State private var domainMenuOpen = false
    @State private var submitting = false

    public init(
        onBack: @escaping () -> Void = {},
        onSendMail: @escaping (_ email: String) -> Void = { _ in }
    ) {
        self.onBack = onBack
        self.onSendMail = onSendMail
    }

    public var body: some View {
        let localPartValid = LocalPartRegex.matches(localPart)
        let fieldError: String? = !localPart.isEmpty && !localPartValid
            ? "영문·숫자·. _ - 만 2~64자로 입력할 수 있어요"
            : nil

        VStack(spacing: 0) {
            StatusBarSpacer()
            MoyeotaTopBar(title: "", onBack: onBack) {
                Text("1 / 5")
                    .moyeotaText(.BodySm, color: MoyeotaColor.TextMute)
            }
            SchoolEmailProgressBar(progress: 1.0 / 5.0)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 24)
                    Text("학교 이메일을 알려주세요")
                        .moyeotaText(.DisplayMd, color: MoyeotaColor.InkPrimary)
                    Spacer().frame(height: 12)
                    Text(verbatim: "\(domain) 메일로 인증 코드를 보내드려요")
                        .moyeotaText(.BodySm, color: MoyeotaColor.TextMute)
                    Spacer().frame(height: 32)

                    MoyeotaTextField(
                        value: localPart,
                        onValueChange: { localPart = withoutWhitespace($0) },
                        label: "학교 이메일",
                        placeholder: "moyeota",
                        errorText: fieldError,
                        helperText: "인증 메일은 5분 안에 도착해요",
                        keyboardOptions: KeyboardOptions(keyboardType: .email),
                        enabled: !submitting
                    ) {
                        // 도메인 고르기 — 글자만 눌리던 자리를 48 터치 + 눌림 표시로(디자인 QA G12)
                        // 도메인 셀렉트 → @pusan.ac.kr / @pukyong.ac.kr / @donga.ac.kr — 지원 3개 외 선택 불가.
                        // 메뉴는 원본처럼 링크를 감싼 상자(밀기 전 자리)에 붙는다
                        ZStack {
                            TextLinkButton(
                                text: domain,
                                onClick: { domainMenuOpen = true },
                                color: MoyeotaColor.TextMute,
                                style: .BodyMd
                            )
                            .offset(x: 8)
                        }
                        .anchorPreference(key: DomainMenuAnchorKey.self, value: .bounds) { $0 }
                    }

                    Spacer().frame(height: 24)

                    // 이렇게 보호해요 — 파란 상자를 걷고 머리말 + 체크 목록으로 화면에 바로 놓는다(디자인 QA G8).
                    // 세 줄짜리라 한 문장용 NoticeBanner 에는 담기지 않고, 04 시작 화면의 신뢰 불릿(A1)과 같은 모양이다.
                    SectionLabel(text: "이렇게 보호해요")
                    VStack(alignment: .leading, spacing: 8) {
                        SchoolEmailProtectRow(text: "이름과 학번은 저장하지 않아요")
                        SchoolEmailProtectRow(text: "메일 주소는 암호화해 보관해요")
                        SchoolEmailProtectRow(text: "다른 이용자에게 공개하지 않아요")
                    }

                    Spacer().frame(height: 24)

                    // 다른 학교 메일 안내 → 도메인 셀렉트 열기. 흰 화면 위라 그림자 대신 Border 선(디자인 QA G4)
                    otherSchoolRow
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                PrimaryCtaButton(
                    text: "인증 메일 보내기",
                    onClick: {
                        submitting = true
                        onSendMail(localPart + domain)
                    },
                    enabled: localPartValid,
                    loading: submitting
                )
                Spacer().frame(height: 12)
                // 미연결: 학생증 인증 — 클릭해도 동작 없음 (대체 인증 플로우 필요)
                Text("학생증으로 인증하기")
                    .moyeotaText(MoyeotaType.BodySm.copy(fontWeight: .semibold), color: MoyeotaColor.Primary600)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer().frame(height: 8)
                // 11pt 는 배지 전용이다(G3) — 읽혀야 하는 안내라 CaptionMd · TextMute 로 올린다
                Text("인증 정보는 매칭 확인 외에 쓰이지 않아요")
                    .moyeotaText(.CaptionMd, color: MoyeotaColor.TextMute)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            NavigationBarSpacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
        .overlayPreferenceValue(DomainMenuAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if domainMenuOpen, let anchor {
                    DomainDropdownMenu(
                        anchor: geometry[anchor],
                        container: geometry.size,
                        onSelect: { candidate in
                            domain = candidate
                            domainMenuOpen = false
                        },
                        onDismiss: { domainMenuOpen = false }
                    )
                }
            }
        }
        .moyeotaBackHandler(enabled: domainMenuOpen) { domainMenuOpen = false }
        // 원본 `remember` 는 화면이 컴포지션에서 빠지면 사라진다. `@State` 는 스택에 있는 동안 남으므로 직접 비운다.
        .onDisappear {
            localPart = ""
            domain = SupportedDomains[0]
            domainMenuOpen = false
            submitting = false
        }
    }

    private var otherSchoolRow: some View {
        let shape = MoyeotaShape.Card
        return Button {
            domainMenuOpen = true
        } label: {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("다른 학교 메일을 쓰나요?")
                        .moyeotaText(.BodyStrong, color: MoyeotaColor.InkPrimary)
                    Spacer().frame(height: 4)
                    Text("부산대 · 부경대 · 동아대 메일을 지원해요")
                        .moyeotaText(.BodySm, color: MoyeotaColor.TextMute)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ChevronIcon()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressOverlayStyle(shape: shape))
        .overlay { shape.strokeBorder(MoyeotaColor.Border, lineWidth: 1) }
    }
}

extension SchoolEmailScreen {
    /// 테스트가 CTA 를 누른 뒤의 상태를 만드는 입구. 창에 올린 화면이라도 코드로는 SwiftUI 버튼을 누를 수 없다.
    func seeded(submitting: Bool) -> Self {
        var copy = self
        copy._submitting = State(initialValue: submitting)
        return copy
    }
}

private struct DomainMenuAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// 머티리얼 3 `DropdownMenu` 의 자리. 값은 머티리얼 1.4.0 그대로다 — 모서리 4, 위아래 여백 8, 고도 3,
/// 항목 높이 최소 48·폭 112~280·좌우 여백 12.
///
/// 배경만 다르다: 원본은 이 테마가 지정하지 않은 머티리얼 기본 `surfaceContainer`(#F3EDF7)를 그대로 쓰는데,
/// 그 값은 디자인 토큰이 아니고 화면 코드는 색을 직접 정의하지 않는다(`DesignTokenGuardTest`).
/// 가장 가까운 토큰인 `MoyeotaColor.SurfaceSoft`(#F4F6FA)로 칠한다.
private struct DomainDropdownMenu: View {
    let anchor: CGRect
    let container: CGSize
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    /// 원본 `MenuVerticalMargin`. 위아래로 이만큼은 비우고 놓는다.
    private let verticalMargin: CGFloat = 48

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .circular)
        ZStack(alignment: .topLeading) {
            // 메뉴 밖을 누르면 닫는다
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SupportedDomains, id: \.self) { candidate in
                    Button {
                        onSelect(candidate)
                    } label: {
                        Text(candidate)
                            .moyeotaText(.BodySm, color: MoyeotaColor.InkPrimary)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 112, maxWidth: 280, minHeight: 48, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressOverlayStyle(shape: Rectangle()))
                }
            }
            .padding(.vertical, 8)
            .background(MoyeotaColor.SurfaceSoft, in: shape)
            .moyeotaShadow(elevation: 3, shape: shape)
            .fixedSize()
            // 원본 위치 규칙: 앵커 왼쪽에 맞추되 넘치면 오른쪽에 맞추고, 앵커 아래에 놓되 넘치면 위에 놓는다.
            .alignmentGuide(.leading) { size in
                let fitsFromLeft = anchor.minX + size.width <= container.width
                return -(fitsFromLeft ? anchor.minX : anchor.maxX - size.width)
            }
            .alignmentGuide(.top) { size in
                let fitsBelow = anchor.maxY + size.height <= container.height - verticalMargin
                return -(fitsBelow ? anchor.maxY : anchor.minY - size.height)
            }
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
    }
}

private struct SchoolEmailProgressBar: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                MoyeotaShape.Small.fill(MoyeotaColor.Hairline)
                MoyeotaShape.Small
                    .fill(MoyeotaColor.Primary500)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 16)
    }
}

// 체크 + 안내 한 줄 — 체크는 「확인된 사실」 표시라 회색 선 아이콘이다(04 신뢰 불릿과 같은 모양)
private struct SchoolEmailProtectRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CheckIcon(size: MoyeotaIconSize.Sm, tint: MoyeotaColor.TextMute)
            Text(text)
                .moyeotaText(.BodySm, color: MoyeotaColor.TextBody)
        }
    }
}
