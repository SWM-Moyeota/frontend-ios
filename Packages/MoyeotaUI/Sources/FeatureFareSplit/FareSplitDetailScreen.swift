import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 39 · 택시비 정산 상세 [신규]
///
/// ### 한 라우트인데 **역할마다 다른 화면**이다 ★
///
/// | | PAYER(받는 사람 = 방장) | SENDER(보내는 사람) |
/// |---|---|---|
/// | 보는 것 | 보낼 사람별 금액·상태·**가린 실명** | 내가 보낼 금액·받을 계좌 |
/// | 누르는 것 | 「받았어요」/「아직 안 들어왔어요」 | **토스로 보내기** + 「보냈어요」 |
/// | 수정 | 가능(`FareSplitDetail.canEdit`) | 없다 |
///
/// 화면을 둘로 쪼개지 않는 이유: 서버가 **같은 엔드포인트**로 두 모양을 주고(`myRole` 로 갈린다)
/// 둘 다 같은 `partyId` 로만 열린다. 쪼개면 들어오기 전에 역할을 알아야 하는데, 그건 GET 을 해 봐야
/// 알 수 있다 — 라우트가 둘이면 **먼저 조회한 뒤 어느 라우트로 갈지 정하는 중간 화면**이 필요해진다.
///
/// ### 이 화면이 조심하는 것들
/// 1. **「받았어요」와 「아직 안 들어왔어요」를 뚜렷하게 가른다.** 둘 다 204 로 성공해 보이는데
///    한쪽은 되돌릴 수 없다. 그래서 **생김새를 전부 다르게** 둔다 — 모양(알약 vs 글자), 색
///    (Primary vs Danger), 크기, **줄이 다르다**(같은 줄에 나란히 두지 않는다). 글자도
///    「못 받았어요」가 아니라 「아직 안 들어왔어요」다: 「받았어요/못 받았어요」는 두 글자 차이라
///    같은 자리에 있으면 손이 기억한 위치로 누른다.
/// 2. **본문 없는 204 뒤에는 반드시 재조회한다.** 그 일은 Route 가 한다(`FareSplitDetailViewModel`) —
///    이 화면은 콜백만 부르고 낙관적으로 한 행도 고치지 않는다. 한 행만 고치면 **마지막 확인이
///    정산 전체를 닫는 것**을 놓쳐, 닫힌 정산에 계좌번호가 남아 보인다.
/// 3. **토스 딥링크가 nil 이거나 `supertoss` 가 아니면 버튼이 없다.** 앱이 조립하지 않는다(`showsTossButton`).
///    열지 못했을 때는 복사 버튼을 가리킨다 — 복사는 선택이 아니라 그 실패의 짝이다.
/// 4. **계좌번호를 로그에 흘리지 않는다.** 이 파일에 출력 코드가 한 줄도 없다(`FareSplitActions.swift` 주석).
/// 5. **내 송금 상태를 세션 uuid 로 찾지 않는다.** 서버가 `FareSplitDetail.myTransferStatus` 로 직접
///    주고(Backend PR #328) 「보냈어요」의 권한은 `FareSplitDetail.canMarkSent` 한 곳에 있다 —
///    그래서 이 화면은 내 publicId 를 **받지 않는다.** `FareSplitDetail.transferOf` 는 받는 사람이
///    「받았어요」를 누를 대상을 고르는 자리에만 남아 있다.
///
/// 이동:
/// - 뒤로가기 → 들어온 자리(끝난 방 상세 · 탑승 기록 · 홈 배너)
/// - 「금액·계좌 고치기」 → 40 정산 고치기(`onEdit`) — `FareSplitDetail.canEdit` 일 때만 그린다
/// - 「채팅으로 물어보기」 → 채팅(`onOpenChat`). **nil 이면 그리지 않는다** — 정산은 방이
///   지워진 뒤에도 남으므로 열 채팅방이 없을 수 있고, 눌러도 열 것이 없는 버튼을 두지 않는다
public struct FareSplitDetailScreen: View {
    /// 그릴 정산. **기본값이 없다** — 예시 값이 프로덕션에 새는 길을 막는다(21 의 `waitingRideDummy` 교훈).
    private let detail: FareSplitDetail
    private let actionInProgress: Bool
    /// 마지막 동작이 실패한 사유(`fareSplitFailureMessage`). CTA 위 띠로 보여 준다.
    private let actionErrorMessage: String?
    private let onBack: () -> Void
    private let onEdit: () -> Void
    private let onMarkSent: () -> Void
    /// 「받았어요」 — 확인 다이얼로그 **뒤에만** 불린다.
    private let onConfirmReceived: (String) -> Void
    /// 「아직 안 들어왔어요」 — 확인 다이얼로그 **뒤에만** 불린다.
    private let onMarkNotReceived: (String) -> Void
    /// 토스를 연다. **열지 못하면 false** — 그때 화면이 복사 안내로 바뀐다(`TOSS_OPEN_FAILED_NOTICE`).
    private let onOpenToss: (String) async -> Bool
    /// 클립보드 복사. 확인은 토스트가 한다(`copyToPasteboard`).
    private let onCopy: (FareSplitCopyTarget, String) -> Void
    private let onOpenChat: (() -> Void)?

    // 확인 다이얼로그 대상. 세 개를 **따로** 들고 있는 이유: 하나로 합치면 「받았어요」와
    // 「아직 안 들어왔어요」가 같은 상태 변수를 쓰게 되고, 그게 바로 두 동작이 섞이는 길이다.
    @State private var confirming: FareSplitTransfer?
    @State private var reverting: FareSplitTransfer?
    @State private var sending = false
    // 토스를 열지 못했다. 한 번 실패하면 복사 안내를 띄운 채 둔다 — 다시 눌러 봐야 같은 결과다.
    @State private var tossFailed = false

    public init(
        detail: FareSplitDetail,
        actionInProgress: Bool = false,
        actionErrorMessage: String? = nil,
        onBack: @escaping () -> Void = {},
        onEdit: @escaping () -> Void = {},
        onMarkSent: @escaping () -> Void = {},
        onConfirmReceived: @escaping (String) -> Void = { _ in },
        onMarkNotReceived: @escaping (String) -> Void = { _ in },
        onOpenToss: @escaping (String) async -> Bool = { _ in false },
        onCopy: @escaping (FareSplitCopyTarget, String) -> Void = { _, _ in },
        onOpenChat: (() -> Void)? = nil
    ) {
        self.detail = detail
        self.actionInProgress = actionInProgress
        self.actionErrorMessage = actionErrorMessage
        self.onBack = onBack
        self.onEdit = onEdit
        self.onMarkSent = onMarkSent
        self.onConfirmReceived = onConfirmReceived
        self.onMarkNotReceived = onMarkNotReceived
        self.onOpenToss = onOpenToss
        self.onCopy = onCopy
        self.onOpenChat = onOpenChat
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                StatusBarSpacer()
                MoyeotaTopBar(title: "택시비 정산", onBack: onBack)
            }
            .background(MoyeotaColor.SurfaceCanvas)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: MoyeotaSpacing.Sm) {
                    StatusCard(detail: detail)

                    if detail.isPayer {
                        PayerBlock(
                            detail: detail,
                            actionInProgress: actionInProgress,
                            onCopy: onCopy,
                            onConfirmClick: { confirming = $0 },
                            onRevertClick: { reverting = $0 }
                        )
                    } else {
                        SenderBlock(
                            detail: detail,
                            stage: senderStageOf(detail: detail),
                            tossFailed: tossFailed,
                            onCopy: onCopy,
                            onTossClick: openToss
                        )
                    }

                    // 보낼 계좌가 사라졌거나(탈퇴) 정산이 기간으로 닫힌 자리에서는 **앱 안에 길이 없다.**
                    // 그때만 채팅을 가리킨다 — 멀쩡한 정산에 「채팅으로 물어보기」를 두면 할 일이 흐려진다.
                    if let onOpenChat, showsChatFallback(detail: detail) {
                        SecondaryButton(text: "채팅으로 물어보기", onClick: onOpenChat)
                    }

                    FareSplitHint(text: APP_DOES_NOT_MOVE_MONEY)
                    if detail.isOpen {
                        FareSplitHint(text: EXPIRY_NOTICE)
                    }
                }
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                .padding(.vertical, MoyeotaSpacing.Md)
            }
            .scrollBounceBehavior(.basedOnSize)
            // 원본 `verticalScroll` 은 자기 칸에서 잘린다.
            .clipped()

            // 하단 고정 영역 — 역할마다 **딱 하나의 채워진 버튼**만 둔다.
            VStack(spacing: 0) {
                HorizontalDivider(color: MoyeotaColor.Hairline)
                VStack(spacing: MoyeotaSpacing.Xs) {
                    if let actionErrorMessage {
                        NoticeBanner(kind: .error, text: actionErrorMessage)
                    }
                    if detail.isPayer {
                        PayerFooter(detail: detail, actionInProgress: actionInProgress, onEdit: onEdit)
                    } else {
                        SenderFooter(
                            detail: detail,
                            tossFailed: tossFailed,
                            actionInProgress: actionInProgress,
                            onTossClick: openToss,
                            onMarkSentClick: { sending = true }
                        )
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
        // ─── 확인 다이얼로그 셋. 세 개가 **서로 다른 글자와 다른 버튼 색**을 쓴다 ───
        .overlay {
            if let target = confirming {
                MoyeotaConfirmDialog(
                    title: "받았다고 확인할까요?",
                    confirmText: "받았어요",
                    onConfirm: {
                        confirming = nil
                        onConfirmReceived(target.senderPublicId)
                    },
                    onDismiss: { confirming = nil },
                    body: confirmReceivedDialogMessage(detail: detail, transfer: target),
                    dismissText: "아니요"
                )
            } else if let target = reverting {
                MoyeotaConfirmDialog(
                    title: "「보냈어요」를 되돌릴까요?",
                    confirmText: "되돌리기",
                    onConfirm: {
                        reverting = nil
                        onMarkNotReceived(target.senderPublicId)
                    },
                    onDismiss: { reverting = nil },
                    body: markNotReceivedDialogMessage(transfer: target),
                    dismissText: "그대로 두기",
                    // 되돌리기는 Danger 색이다 — 확인(Primary)과 **색까지** 갈라 둔다.
                    destructive: true
                )
            } else if sending {
                MoyeotaConfirmDialog(
                    title: "보냈다고 알릴까요?",
                    confirmText: "보냈어요",
                    onConfirm: {
                        sending = false
                        onMarkSent()
                    },
                    onDismiss: { sending = false },
                    body: markSentDialogMessage(detail: detail),
                    dismissText: "아직이에요"
                )
            }
        }
        // 원본 `remember` 는 화면이 컴포지션에서 빠지면 사라진다. `@State` 는 스택에 있는 동안 남으므로 직접 비운다.
        .onDisappear {
            confirming = nil
            reverting = nil
            sending = false
        }
    }

    /// 토스를 연다. 열지 못하면(스킴이 다르거나 받아 줄 앱이 없다) **복사 안내로 바뀐다** — 다시 눌러도 같은 결과다.
    private func openToss(_ deeplink: String) {
        Task { @MainActor in
            let opened = await onOpenToss(deeplink)
            if !opened { tossFailed = true }
        }
    }
}

// ─────────────────────────── 공통 ───────────────────────────

/// 상태 요약. 총 택시비와 상태 배지를 함께 둔다 — **상태를 모르면 왜 버튼이 없는지 알 수 없다.**
///
/// 경로(출발→도착)를 적지 않는다: 정산 상세 응답에 그 값이 **없다**(홈 배너 쪽에만 있다).
/// 방 상세를 따로 불러 채우면 요청이 하나 늘고, 방이 지워진 정산에서는 그마저 실패한다.
private struct StatusCard: View {
    let detail: FareSplitDetail

    var body: some View {
        let badge = fareSplitBadge(status: detail.status)
        FareSplitCard {
            HStack(alignment: .center, spacing: MoyeotaSpacing.Xs) {
                Text("총 택시비")
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                    .frame(maxWidth: .infinity, alignment: .leading)
                FareSplitBadgeChip(badge: badge)
            }
            Text(fareWonLabel(amount: detail.totalFare))
                .moyeotaText(MoyeotaType.DisplayMd.tabularNums().hangulTrimmed, color: MoyeotaColor.InkPrimary)
            if let notice = fareSplitStatusNotice(status: detail.status) {
                FareSplitNotice(badge: FareSplitBadge(tone: badge.tone, label: notice))
            }
        }
    }
}

// ─────────────────────────── 받는 사람 ───────────────────────────

private struct PayerBlock: View {
    let detail: FareSplitDetail
    let actionInProgress: Bool
    let onCopy: (FareSplitCopyTarget, String) -> Void
    let onConfirmClick: (FareSplitTransfer) -> Void
    let onRevertClick: (FareSplitTransfer) -> Void

    var body: some View {
        let summary = payerSummaryOf(detail: detail)

        FareSplitCard {
            FareSplitSectionTitle(text: "내가 받을 돈")
            FareSplitKeyValueRow(label: "아직 못 받은 돈", value: fareWonLabel(amount: summary.outstanding), strong: true)
            FareSplitKeyValueRow(label: "받을 돈 전체", value: fareWonLabel(amount: summary.toReceive))
            // 「내 부담」을 함께 보여 주는 이유: 받을 돈(12,466원)이 총 택시비(18,700원)보다 적은 것이
            // 버그처럼 보인다. 빠진 금액이 내 몫임을 그 자리에서 말한다.
            FareSplitKeyValueRow(label: "내가 부담한 몫", value: fareWonLabel(amount: summary.myAmount))
            FareSplitHint(text: confirmedProgressLabel(summary: summary))
        }

        // 내가 적어 둔 계좌 — **고치기 전에 맞는지 확인하는 용도**다. 닫힌 정산에서는 서버가 지워
        // nil 로 오므로 블록 자체가 사라진다(「불러오지 못했어요」가 아니다).
        if let manual = detail.manualTransfer {
            FareSplitCard {
                FareSplitSectionTitle(text: "받을 계좌")
                CopyableValueRow(
                    label: manual.bankDisplayName,
                    display: manual.accountNumber,
                    copyValue: manual.accountNumber,
                    target: .accountNumber,
                    onCopy: onCopy
                )
                FareSplitHint(text: "동승자에게 보이는 계좌예요. 틀렸다면 아래 「금액·계좌 고치기」로 바꿔 주세요")
            }
        }

        FareSplitCard {
            FareSplitSectionTitle(text: "보낼 분들")
            // 가린 실명이 하나라도 오면 그 칸의 **쓸모**를 한 번만 적는다.
            if detail.transfers.contains(where: { depositorHintOrNull(transfer: $0) != nil }) {
                FareSplitHint(text: DEPOSITOR_HINT_PURPOSE)
            }
            // publicId 가 빈 행이 겹칠 수 있어(서버가 설명하지 못한 멤버) id 가 아니라 자리로 구별한다.
            ForEach(Array(detail.transfers.enumerated()), id: \.offset) { index, transfer in
                if index > 0 {
                    HorizontalDivider(color: MoyeotaColor.Hairline)
                }
                TransferRow(
                    detail: detail,
                    transfer: transfer,
                    actionInProgress: actionInProgress,
                    onConfirmClick: onConfirmClick,
                    onRevertClick: onRevertClick
                )
            }
        }
    }
}

/// 송금 한 행.
///
/// ### 두 버튼의 생김새를 전부 갈라 둔다 ★
///
/// | | 받았어요 | 아직 안 들어왔어요 |
/// |---|---|---|
/// | 모양 | 채워진 알약 버튼(전체 너비) | **글자만**(테두리·배경 없음) |
/// | 색 | Primary | Danger |
/// | 자리 | 행 아래 **첫째 줄** | 그 **아래 줄**, 오른쪽 끝 |
/// | 글자 | 「받았어요」 | 「아직 안 들어왔어요」 |
///
/// 같은 줄에 나란히 두지 않는 것이 핵심이다. 나란히 두면 손이 **위치로** 기억하고, 행마다 한쪽만
/// 있을 때(NOT_SENT) 그 위치가 밀려 **되돌리려던 손가락이 확인을 누른다.** 그 오탭은 되돌릴 수 없다.
private struct TransferRow: View {
    let detail: FareSplitDetail
    let transfer: FareSplitTransfer
    let actionInProgress: Bool
    let onConfirmClick: (FareSplitTransfer) -> Void
    let onRevertClick: (FareSplitTransfer) -> Void

    var body: some View {
        let actions = transferActionsOf(detail: detail, transfer: transfer)

        VStack(alignment: .leading, spacing: MoyeotaSpacing.Xs) {
            HStack(alignment: .center, spacing: MoyeotaSpacing.Sm) {
                FareSplitInitialCircle(name: transfer.displayName)
                VStack(alignment: .leading, spacing: 0) {
                    Text(transfer.displayName)
                        .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let hint = depositorHintOrNull(transfer: transfer) {
                        Text(hint)
                            .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                    }
                    Text(fareWonLabel(amount: transfer.amount))
                        .moyeotaText(MoyeotaType.BodySm.tabularNums().hangulTrimmed, color: MoyeotaColor.TextBody)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                FareSplitBadgeChip(badge: transferStatusLabel(status: transfer.status))
            }

            if let reason = actions.lockReason {
                FareSplitHint(text: reason)
            }

            if actions.canConfirm {
                PrimaryCtaButton(
                    text: "받았어요",
                    onClick: { onConfirmClick(transfer) },
                    enabled: !actionInProgress
                )
            }
            if actions.canMarkNotReceived {
                // 글자만. 전체 너비를 차지하지 않고 오른쪽 끝에 둔다 — 위의 알약과 **무게가 다르다**.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    TextLinkButton(
                        text: "아직 안 들어왔어요",
                        onClick: { onRevertClick(transfer) },
                        color: MoyeotaColor.Danger600,
                        style: MoyeotaType.ButtonMd,
                        enabled: !actionInProgress
                    )
                }
            }
        }
        .padding(.vertical, MoyeotaSpacing.Xxs)
    }
}

/// 받는 사람의 하단. 고칠 수 있으면 버튼, 못 고치면 **왜 못 고치는지**(`editBlockReason`).
///
/// 버튼을 그냥 숨기지 않는 이유: 방장은 금액을 잘못 넣었다는 것을 알고 이 화면에 왔다. 고치는 길이
/// 아무 말 없이 사라져 있으면 **정산을 취소하려 하고**, 그 길은 서버에 없다.
private struct PayerFooter: View {
    let detail: FareSplitDetail
    let actionInProgress: Bool
    let onEdit: () -> Void

    var body: some View {
        if detail.canEdit {
            SecondaryButton(text: "금액·계좌 고치기", onClick: onEdit, enabled: !actionInProgress)
        } else if let reason = editBlockReason(detail: detail) {
            FareSplitHint(text: reason)
        }
    }
}

// ─────────────────────────── 보내는 사람 ───────────────────────────

private struct SenderBlock: View {
    let detail: FareSplitDetail
    let stage: SenderStage
    let tossFailed: Bool
    let onCopy: (FareSplitCopyTarget, String) -> Void
    let onTossClick: (String) -> Void

    var body: some View {
        FareSplitCard {
            FareSplitSectionTitle(text: "내가 보낼 금액")
            Text(fareWonLabel(amount: detail.myAmount))
                .moyeotaText(MoyeotaType.DisplayLg.tabularNums().hangulTrimmed, color: MoyeotaColor.Primary600)
            FareSplitKeyValueRow(label: "받는 분", value: detail.payer.displayName)
            if let notice = senderStageNotice(stage: stage) {
                FareSplitNotice(badge: FareSplitBadge(tone: senderStageTone(stage: stage), label: notice))
            }
        }

        // 계좌·금액 복사 — **토스가 열리지 않는 기기에서 유일하게 남는 길**이다(서버 주석의 요구사항).
        // 닫힌 정산·탈퇴한 받는 사람에게는 계좌가 nil 이라 이 블록이 통째로 사라진다.
        if let manual = detail.manualTransfer {
            FareSplitCard {
                FareSplitSectionTitle(text: "보낼 곳")
                CopyableValueRow(
                    label: manual.bankDisplayName,
                    display: manual.accountNumber,
                    copyValue: manual.accountNumber,
                    target: .accountNumber,
                    onCopy: onCopy
                )
                HorizontalDivider(color: MoyeotaColor.Hairline)
                CopyableValueRow(
                    label: "금액",
                    display: fareWonLabel(amount: manual.amount),
                    // 금액은 **숫자만** 복사한다 — 은행 앱 금액 칸에 「6,233원」을 붙이면 거절된다.
                    copyValue: String(manual.amount),
                    target: .amount,
                    onCopy: onCopy
                )
                if tossFailed {
                    FareSplitNotice(badge: FareSplitBadge(tone: .warn, label: TOSS_OPEN_FAILED_NOTICE))
                }
            }
        }

        // 토스 버튼을 카드 아래에도 둔다 — 계좌 바로 아래가 「보내러 간다」의 자연스러운 자리다.
        // 하단 고정 CTA 와 중복이 아니다: 저쪽은 스크롤과 무관하게 늘 보이는 자리다.
        if showsTossButton(detail: detail) && !tossFailed, let deeplink = detail.tossDeeplink {
            SecondaryButton(text: "토스로 보내기", onClick: { onTossClick(deeplink) })
        }
    }
}

/// 보내는 사람의 하단 — **채워진 버튼은 늘 하나**다.
///
/// 토스 딥링크가 있으면 「토스로 보내기」가 그 하나이고(먼저 할 일이 송금이다) 「보냈어요」는
/// 테두리 버튼으로 그 아래 선다. 딥링크가 없거나 **열리지 않았으면**(`tossFailed`) 할 일이
/// 「보냈어요」 하나라 그것이 채워진 버튼이 된다. 채워진 버튼이 둘이면 **무엇을 먼저 할지** 알 수 없다.
///
/// `tossFailed` — 토스를 한 번 열지 못했으면 **채워진 버튼이 「보냈어요」로 옮겨 간다.** 실패한 버튼을 그 자리에
/// 남겨 두지 않는 이유: 다시 눌러도 같은 결과이고(받아 줄 앱이 없다), 그 사이 위쪽 카드는 이미 「복사해서 은행
/// 앱에서 보내 주세요」로 바뀌어 있다(`TOSS_OPEN_FAILED_NOTICE`). 두 영역이 서로 다른 다음 단계를 가리키면 안 된다.
private struct SenderFooter: View {
    let detail: FareSplitDetail
    let tossFailed: Bool
    let actionInProgress: Bool
    let onTossClick: (String) -> Void
    let onMarkSentClick: () -> Void

    var body: some View {
        let deeplink = (showsTossButton(detail: detail) && !tossFailed) ? detail.tossDeeplink : nil

        if let deeplink {
            PrimaryCtaButton(text: "토스로 보내기", onClick: { onTossClick(deeplink) }, enabled: !actionInProgress)
            if showsMarkSentButton(detail: detail) {
                SecondaryButton(text: "보냈어요", onClick: onMarkSentClick, enabled: !actionInProgress)
            }
        } else if showsMarkSentButton(detail: detail) {
            PrimaryCtaButton(
                text: "보냈어요",
                onClick: onMarkSentClick,
                enabled: !actionInProgress,
                loading: actionInProgress
            )
        }
    }
}

// ─────────────────────────── 정산이 아직 없을 때 ───────────────────────────

/// 39 의 **정상 상태 하나** — 이 방에 아직 정산이 없다.
///
/// ### 「불러오지 못했어요」가 아니다 ★
/// 서버 404 `FARE_SPLIT_NOT_FOUND` 는 「아직 아무도 시작하지 않았다」는 뜻이고, 그건 끝난 방의
/// 정상 상태다(저장소가 그 404 를 nil 로 접어 준다). 빨간 오류 화면으로 그리면 방장은 **자기가
/// 시작해야 한다는 것을 모르고**, 동승자는 돈을 못 보낸 것을 앱 탓으로 읽는다.
///
/// - `canStart`: 내가 시작할 수 있는가. false 면 「정산 시작하기」를 **그리지 않는다** —
///   누르면 403 으로만 끝나는 버튼을 두지 않는다.
/// - `blockedReason`: 왜 시작할 수 없는지. **nil 이면 「알 수 없다」**다(방 상세 조회 실패) —
///   그때는 단정하지 않고 다시 불러오기만 둔다.
public struct FareSplitAbsentScreen: View {
    private let canStart: Bool
    private let blockedReason: String?
    private let onBack: () -> Void
    private let onStart: () -> Void
    private let onRetry: () -> Void

    public init(
        canStart: Bool,
        blockedReason: String?,
        onBack: @escaping () -> Void = {},
        onStart: @escaping () -> Void = {},
        onRetry: @escaping () -> Void = {}
    ) {
        self.canStart = canStart
        self.blockedReason = blockedReason
        self.onBack = onBack
        self.onStart = onStart
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                StatusBarSpacer()
                MoyeotaTopBar(title: "택시비 정산", onBack: onBack)
            }
            .background(MoyeotaColor.SurfaceCanvas)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: MoyeotaSpacing.Sm) {
                    FareSplitCard {
                        FareSplitSectionTitle(text: "아직 택시비 정산이 없어요")
                        FareSplitHint(
                            text: canStart
                                ? "택시비를 낸 분이 정산을 시작하면 함께 탄 분들에게 송금 요청이 가요"
                                : "방장이 정산을 시작하면 보낼 금액과 계좌가 여기에 보여요"
                        )
                        if let blockedReason {
                            FareSplitNotice(badge: FareSplitBadge(tone: .warn, label: blockedReason))
                        }
                    }
                    FareSplitHint(text: APP_DOES_NOT_MOVE_MONEY)
                }
                .padding(.horizontal, MoyeotaSpacing.ScreenGutter)
                .padding(.vertical, MoyeotaSpacing.Md)
            }
            .scrollBounceBehavior(.basedOnSize)
            .clipped()

            VStack(spacing: 0) {
                HorizontalDivider(color: MoyeotaColor.Hairline)
                VStack(spacing: MoyeotaSpacing.Xs) {
                    if canStart {
                        PrimaryCtaButton(text: "택시비 정산 시작하기", onClick: onStart)
                    } else {
                        // 「시작할 수 있는가」를 알 수 없었던 경우까지 여기로 온다 — 다시 읽는 길은 남긴다.
                        SecondaryButton(text: "다시 불러오기", onClick: onRetry)
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
    }
}
