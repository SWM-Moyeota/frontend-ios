import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 40 · 택시비 정산 시작·수정 [신규] — **받는 사람(방장) 전용**
///
/// 세 칸과 한 목록으로 끝난다: 택시비 · 은행 · 계좌번호 · 사람마다 부담 금액.
/// 시작(POST)과 수정(PATCH)이 **같은 모양**을 쓰므로(`FareSplitDraft`) 화면도 하나다 — 글자만
/// `FareSplitEditMode` 로 갈린다.
///
/// ### 이 화면이 조심하는 것 넷
/// 1. **1/N 은 앱의 책임이다**(Swagger 원문: 「1/N 로 미리 채우는 것은 앱이 한다」). 택시비를 적는
///    순간 채워지고, 사용자가 한 칸이라도 손대면 **덮지 않는다**(`FareSplitDraftState.autoSplits`).
/// 2. **합계를 실시간으로 보여 주고 어긋나면 잠근다.** 서버는 400 `PAYMENTS_NOT_EQUAL_FARE` 하나로만
///    답하고 그 답은 **입력을 다 끝낸 뒤에** 온다(`differenceNotice`).
/// 3. **수정은 전원 NOT_SENT 일 때만**. 못 고치는 상태에서는 폼을 열지 않고 왜 못 고치는지 적는다
///    (`editDraftGate`) — 「정산 취소는 없다」(서버 원문)까지 함께 말한다.
/// 4. **계좌번호를 로그에 흘리지 않는다.** 이 파일에 출력 코드가 한 줄도 없다.
///
/// ### 409 `FARE_SPLIT_ALREADY_STARTED` 가 와도 **화면을 닫지 않는다** ★
/// 그 실패는 사용자가 금액을 다 채운 뒤에 온다(그사이 누군가 「보냈어요」를 눌렀다). 닫으면 입력이
/// 통째로 사라진다. 그래서 `readOnlyReason` 으로 **읽기 전용**으로 바꾸고 적은 값은 그대로 남긴다 —
/// 사용자가 숫자를 보며 채팅으로 이야기할 수 있다.
public struct FareSplitEditScreen: View {
    /// 입력 상태. **기본값이 없다** — 예시 값이 프로덕션에 새는 길을 막는다.
    private let state: FareSplitDraftState
    /// 「앱이 예상한 요금은 …」. **칸에 넣지 않는다**(`estimatedFareHint` 주석).
    private let fareHint: String?
    private let submitting: Bool
    /// 서버 실패 사유(`fareSplitFailureMessage`). CTA 위 띠.
    private let errorMessage: String?
    /// nil 이 아니면 **읽기 전용**이다. 409 `FARE_SPLIT_ALREADY_STARTED` 뒤에 채워진다 —
    /// 입력은 그대로 남기고 보내는 길만 닫는다.
    private let readOnlyReason: String?
    private let onBack: () -> Void
    private let onFareChange: (String) -> Void
    private let onBankSelect: (Bank) -> Void
    private let onAccountChange: (String) -> Void
    private let onAmountChange: (String, String) -> Void
    private let onSplitEvenly: () -> Void
    private let onSubmit: () -> Void
    /// **이미 그 방에 정산이 있을 때**만 nil 이 아니다(409 `FARE_SPLIT_ALREADY_EXISTS`).
    ///
    /// 그 실패를 「오류」로만 보여 주고 끝내면 사용자는 **이미 존재하는 자기 정산을 못 보게** 된다 —
    /// 서버 Swagger 가 그 복구 경로를 「GET 으로 본다」라고 적어 둔 실패다. 화면을 저절로 바꾸지
    /// 않는 이유는 입력 때문이다: 사용자가 방금 적은 금액·계좌는 **저장되지 않았고**, 말없이 다른
    /// 화면으로 옮기면 그 값이 사라진 것도, 저장되지 않은 것도 알 수 없다. 그래서 적은 값을 남긴 채
    /// **다음으로 갈 길을 버튼으로** 준다.
    private let onSeeExisting: (() -> Void)?

    @State private var pickingBank = false

    public init(
        state: FareSplitDraftState,
        fareHint: String? = nil,
        submitting: Bool = false,
        errorMessage: String? = nil,
        readOnlyReason: String? = nil,
        onBack: @escaping () -> Void = {},
        onFareChange: @escaping (String) -> Void = { _ in },
        onBankSelect: @escaping (Bank) -> Void = { _ in },
        onAccountChange: @escaping (String) -> Void = { _ in },
        onAmountChange: @escaping (String, String) -> Void = { _, _ in },
        onSplitEvenly: @escaping () -> Void = {},
        onSubmit: @escaping () -> Void = {},
        onSeeExisting: (() -> Void)? = nil
    ) {
        self.state = state
        self.fareHint = fareHint
        self.submitting = submitting
        self.errorMessage = errorMessage
        self.readOnlyReason = readOnlyReason
        self.onBack = onBack
        self.onFareChange = onFareChange
        self.onBankSelect = onBankSelect
        self.onAccountChange = onAccountChange
        self.onAmountChange = onAmountChange
        self.onSplitEvenly = onSplitEvenly
        self.onSubmit = onSubmit
        self.onSeeExisting = onSeeExisting
    }

    public var body: some View {
        let editable = readOnlyReason == nil && !submitting
        let block = submitBlockOf(state: state)
        // 서버가 보낸 실패가 1순위다 — 앱이 미리 보지 못한 사유이므로 더 새 정보다.
        let notice = errorMessage ?? submitBlockMessage(block: block)

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                StatusBarSpacer()
                MoyeotaTopBar(title: editTitle(mode: state.mode), onBack: onBack)
            }
            .background(MoyeotaColor.SurfaceCanvas)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: MoyeotaSpacing.Sm) {
                    if let readOnlyReason {
                        NoticeBanner(kind: .error, text: readOnlyReason)
                    }

                    FareSplitCard {
                        FareSplitSectionTitle(text: "실제로 낸 택시비")
                        MoyeotaTextField(
                            value: state.fareInput,
                            onValueChange: onFareChange,
                            placeholder: "0",
                            helperText: fareHint,
                            keyboardOptions: KeyboardOptions(keyboardType: .number),
                            enabled: editable
                        ) {
                            WonSuffix()
                        }
                    }

                    FareSplitCard {
                        FareSplitSectionTitle(text: "받을 계좌")
                        BankSelectRow(label: state.bankLabel, enabled: editable, onClick: { pickingBank = true })
                        MoyeotaTextField(
                            value: state.accountInput,
                            onValueChange: onAccountChange,
                            label: "계좌번호",
                            placeholder: "숫자 10~16자리",
                            errorText: accountErrorText(state: state),
                            // 하이픈을 떼는 일은 보내기 직전에 매퍼가 한다 — 사용자가 은행 앱에서 복사한
                            // 모양을 그대로 붙여넣을 수 있다는 사실을 알려 준다.
                            helperText: "은행 앱에서 복사한 하이픈(-)이 있어도 괜찮아요",
                            keyboardOptions: KeyboardOptions(keyboardType: .number),
                            enabled: editable
                        )
                    }

                    FareSplitCard {
                        HStack(alignment: .center, spacing: MoyeotaSpacing.Xs) {
                            FareSplitSectionTitle(text: "사람마다 부담 금액")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if editable && state.canSplitEvenly() {
                                TextLinkButton(text: "똑같이 나누기", onClick: onSplitEvenly)
                            }
                        }
                        if let remainder = evenSplitRemainderNotice(state: state) {
                            FareSplitHint(text: remainder)
                        }

                        ForEach(Array(state.riders.enumerated()), id: \.element.publicId) { index, rider in
                            if index > 0 {
                                HorizontalDivider(color: MoyeotaColor.Hairline)
                            }
                            AmountRow(
                                rider: rider,
                                value: state.amountInputs[rider.publicId] ?? "",
                                enabled: editable,
                                onValueChange: { raw in onAmountChange(rider.publicId, raw) }
                            )
                        }

                        HorizontalDivider(color: MoyeotaColor.Hairline)
                        Text(sumLabel(state: state))
                            .moyeotaText(MoyeotaType.BodyMd.tabularNums().hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        // 서버 400 을 **입력하는 동안** 대신 말하는 줄이다. 아래 경고 띠와 중복으로 적지 않는다
                        // (`submitBlockMessage` 가 `sumNotEqualFare` 에 nil 을 주는 근거).
                        if let difference = differenceNotice(state: state) {
                            FareSplitNotice(badge: difference)
                        }
                    }

                    if state.mode == .start {
                        FareSplitHint(text: START_IRREVERSIBLE_NOTICE)
                    }
                    FareSplitHint(text: APP_DOES_NOT_MOVE_MONEY)
                }
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                .padding(.vertical, MoyeotaSpacing.Md)
            }
            .scrollBounceBehavior(.basedOnSize)
            .clipped()
            // 원본 `verticalScroll` 은 스크롤해도 키보드를 내리지 않는다 — 금액을 적으며 합계 줄을 보러 내려가도
            // 입력이 이어진다(36·37 과 같은 약속, `ScrollKeyboardTest`).
            .scrollDismissesKeyboard(.never)

            VStack(spacing: 0) {
                HorizontalDivider(color: MoyeotaColor.Hairline)
                VStack(spacing: MoyeotaSpacing.Xs) {
                    if let notice {
                        NoticeBanner(kind: .error, text: notice)
                    }
                    PrimaryCtaButton(
                        text: editCtaLabel(mode: state.mode),
                        onClick: onSubmit,
                        enabled: editable && block == nil,
                        loading: submitting
                    )
                    if let onSeeExisting {
                        SecondaryButton(text: "지금 있는 정산 보기", onClick: onSeeExisting)
                    }
                }
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                .padding(.vertical, MoyeotaSpacing.Sm)
                NavigationBarSpacer()
            }
            .background(MoyeotaColor.SurfaceCanvas)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceSoft)
        .overlay {
            if pickingBank {
                BankPickerDialog(
                    selectedCode: state.bankCode,
                    onPick: { bank in
                        pickingBank = false
                        onBankSelect(bank)
                    },
                    onDismiss: { pickingBank = false }
                )
            }
        }
        // 읽기 전용으로 바뀌면(409) 열려 있던 은행 창을 닫는다 — 고를 수 없는 목록이 떠 있으면 안 된다.
        .onChange(of: editable) { _, isEditable in
            if !isEditable { pickingBank = false }
        }
        .onDisappear { pickingBank = false }
    }
}

/// 금액 칸 끝의 「원」.
private struct WonSuffix: View {
    var body: some View {
        Text("원")
            .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.TextMute)
            .accessibilityHidden(true)
    }
}

/// 은행 선택 줄. 고르기 전에는 「은행 선택」이고 고른 뒤에는 그 이름이다.
///
/// 22개를 칩으로 펼치지 않는 이유: 여덟 줄을 차지해 **아래의 금액 목록이 화면에서 밀려난다** —
/// 합계를 보면서 금액을 고치는 것이 이 화면의 중심 동작이다. 목록은 창으로 뺀다(`BankPickerDialog`).
///
/// 모양은 아래 계좌번호 칸(`MoyeotaTextField`)과 같은 테두리·모서리다 — 두 칸이 한 묶음으로 읽혀야 한다.
private struct BankSelectRow: View {
    let label: String?
    let enabled: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(alignment: .center, spacing: MoyeotaSpacing.Xs) {
                Text(label ?? "은행 선택")
                    .moyeotaText(
                        MoyeotaType.BodyMd.hangulTrimmed,
                        color: label == nil ? MoyeotaColor.TextPlaceholder : MoyeotaColor.InkPrimary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("바꾸기")
                    .moyeotaText(
                        MoyeotaType.ButtonSm.hangulTrimmed,
                        color: enabled ? MoyeotaColor.Primary600 : MoyeotaColor.TextPlaceholder
                    )
            }
            .padding(.horizontal, MoyeotaSpacing.Md)
            .padding(.vertical, MoyeotaSpacing.Md)
            .frame(maxWidth: .infinity)
            .overlay(MoyeotaShape.Card.strokeBorder(MoyeotaColor.BorderStrong))
            .contentShape(MoyeotaShape.Card)
        }
        .buttonStyle(PressOverlayStyle(shape: MoyeotaShape.Card))
        .disabled(!enabled)
        .accessibilityLabel(label.map { "은행 \($0)" } ?? "은행 선택")
        .accessibilityHint("받을 은행을 골라요")
    }
}

/// 은행 목록 창 — `Bank` 22종을 **서버 enum 순서 그대로** 그린다.
///
/// 순서를 바꾸지 않는 이유: 서버 `Bank` 가 많이 쓰는 은행부터 늘어놓은 순서이고, 앱이 가나다순으로
/// 다시 정렬하면 **자주 쓰는 은행이 아래로 내려간다.** 검색 칸을 두지 않는 것도 같은 판단이다
/// (22개는 한 번 훑어 찾을 수 있는 길이다).
///
/// 지금 고른 은행이 **목록에 없을 수 있다** — 서버가 추가한 23번째 은행의 정산을 고치는 경우다.
/// 그때 아무 줄도 선택 표시가 되지 않는 것이 정상이고, 사용자가 아무것도 고르지 않으면
/// `FareSplitDraftState.bankCode` 가 그대로 남아 **모르는 은행의 정산도 금액만 고쳐 저장된다.**
///
/// 원본은 머티리얼 `AlertDialog` 다. 앱의 확인 창(`MoyeotaConfirmDialog`)은 글 한 줄만 담으므로, 같은 겹침 모양
/// (어두운 바탕 · 흰 카드 · 바깥 누르면 닫힘 · 스와이프 뒤로가기로 닫힘)으로 목록을 담는 창을 따로 둔다.
private struct BankPickerDialog: View {
    let selectedCode: String?
    let onPick: (Bank) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            MoyeotaColor.Scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                StatusBarSpacer()
                VStack(alignment: .leading, spacing: MoyeotaSpacing.Sm) {
                    Text("은행 선택")
                        .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(Bank.allCases, id: \.self) { bank in
                                BankPickerRow(bank: bank, selected: bank.code == selectedCode, onPick: onPick)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        TextLinkButton(text: "닫기", onClick: onDismiss, color: MoyeotaColor.TextMute)
                    }
                }
                .padding(MoyeotaSpacing.Lg)
                .background(MoyeotaColor.SurfaceCanvas, in: MoyeotaShape.Dialog)
                .modalShadow(MoyeotaShape.Dialog)
                .padding(.horizontal, MoyeotaSpacing.Lg)
                .padding(.vertical, MoyeotaSpacing.Xl)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, onDismiss)
                NavigationBarSpacer()
            }
        }
        .moyeotaBackHandler { onDismiss() }
    }
}

private struct BankPickerRow: View {
    let bank: Bank
    let selected: Bool
    let onPick: (Bank) -> Void

    var body: some View {
        Button(action: { onPick(bank) }) {
            HStack(alignment: .center, spacing: MoyeotaSpacing.Xs) {
                Text(bank.displayName)
                    .moyeotaText(
                        MoyeotaType.BodyMd.hangulTrimmed,
                        color: selected ? MoyeotaColor.Primary600 : MoyeotaColor.InkPrimary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Text("선택됨")
                        .moyeotaText(MoyeotaType.ButtonSm.hangulTrimmed, color: MoyeotaColor.Primary600)
                }
            }
            .padding(.vertical, MoyeotaSpacing.Sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 한 사람의 금액 줄.
///
/// 「받는 분」 표시를 붙이는 이유: 1/N 의 나머지 1원을 그 사람이 흡수해 **금액이 혼자 다르다**
/// (`evenSplitRemainderNotice` 가 그 이유를 설명한다). 표시가 없으면 버그로 보인다.
///
/// 원본은 금액 칸을 140dp 로 고정한다. 여기서는 숫자로 폭을 정하지 않고 이름과 칸이 줄을 반씩 나눈다 —
/// 일곱 자리(`MAX_AMOUNT_DIGITS`)와 「원」이 들어가기에 충분하고, 큰 글씨 설정에서도 이름이 먼저 말줄임된다.
private struct AmountRow: View {
    let rider: FareSplitRider
    let value: String
    let enabled: Bool
    let onValueChange: (String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: MoyeotaSpacing.Xs) {
            VStack(alignment: .leading, spacing: 0) {
                Text(rider.displayName)
                    .moyeotaText(MoyeotaType.BodyMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if rider.isPayer {
                    Text("받는 분")
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MoyeotaTextField(
                value: value,
                onValueChange: onValueChange,
                placeholder: "0",
                keyboardOptions: KeyboardOptions(keyboardType: .number),
                enabled: enabled
            ) {
                WonSuffix()
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(rider.displayName) 부담 금액")
        }
        .padding(.vertical, MoyeotaSpacing.Xxs)
    }
}
