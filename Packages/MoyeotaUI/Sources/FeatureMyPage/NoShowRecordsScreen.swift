import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 38 · 노쇼 기록 · 이의 신청 [신규]
///
/// 진입: 35 마이페이지 「노쇼 기록」 행.
///
/// 서버: `GET /api/v1/matching/no-shows` — **노쇼 시각 최신순 최대 20개**(페이징이 없다),
/// `POST /api/v1/matching/rooms/{partyId}/no-show-objection` (201, 본문 없음).
///
/// ```
/// ← 노쇼 기록
///   노쇼 1건마다 그 방 약속 시간부터 24시간 동안 …     ← 제재 계산식
///   ┌───────────────────────────────┐
///   │ 강남역 → 판교역                        │
///   │ 약속 시간   11월 5일 오후 4:15          │
///   │ 노쇼 시각   11월 5일 오후 4:20          │
///   │ ─────────────────────────── │
///   │ [      이의 신청      ]                │  ← 이 상태의 줄에만 생긴다
///   └───────────────────────────────┘
///   ┌───────────────────────────────┐
///   │ 부산대 정문 → 서면역      [이의 검토 중]  │
///   │ …                                     │
///   │ 운영자가 확인한 결과는 이 화면에서 …      │
///   └───────────────────────────────┘
/// ```
///
/// ### 이 화면이 왜 있는가
/// PR #82 로 앱이 노쇼를 **만들** 수 있게 됐다(「출발」을 누르면 도착하지 않은 사람 전원이 노쇼로
/// 찍힌다). 받는 쪽은 비어 있었다 — 제재당한 사용자는 방 만들기·합류가 403 `NO_SHOW_RESTRICTED` 로
/// 막히는 것만 보고 **이유도 기한도 알 수 없었고, 잘못 찍혀도 다툴 길이 없었다.** 이 화면이 그
/// 다투는 길이다.
///
/// ### 이의 신청 버튼이 생기는 줄은 하나다 ★
/// `objectionStatus == nil && !isVoided` — 서버 Swagger 가 그렇게 지시하고, 서버가 201 을 주는
/// 조건도 같다. 판정은 `noShowRowState`·`NoShowItem.allowsObjection` 이 하고 화면은 그 결과만
/// 본다(화면이 다시 두 필드를 보면 두 개의 진실이 생긴다).
///
/// ### 그리지 않는 것과 그 이유
/// - **처리 시한·결과 알림** — 운영 약속이 없고 결과 푸시도 없다. 사용자가 결과를 아는 길은
///   이 화면을 다시 여는 것뿐이라, 문구도 그렇게만 적는다(`noShowNoteText`).
/// - **「제한이 풀렸어요」** — 무효가 된 노쇼 한 건이 곧 제한 해제는 아니다(다른 노쇼가 남아
///   있을 수 있다). 지금 제한 여부는 35 의 배너가 서버 `restrictedUntil` 로만 말한다.
/// - **동승자·방장 이름** — 이 응답에 멤버가 없다. 「누가 출발을 눌렀는지」도 서버가 주지 않는다.
/// - **페이지 더 보기** — 서버가 20건까지만 주고 커서도 개수 파라미터도 없다. 「더 보기」를 달면
///   누를 수 없는 버튼이 된다. 대신 목록이 **꽉 찼을 때만** 「최근 20건만 볼 수 있어요」를 적는다
///   (`noShowHistoryCapNotice`) — 정확히 20건인지 잘린 건지는 응답으로 구분할 수 없지만 그 문구는
///   두 경우 모두 참이고, 아무 말도 없으면 사용자는 그 목록이 전부라고 읽는다.
/// - **요금·탑승 인원** — 34 지난 탑승 기록의 값이고 이 응답에는 없다.
///
/// ### 색은 토큰만 쓴다
/// 34 가 세운 규칙을 따른다 — 파일-로컬 그레이를 만들지 않는다. 상태 색은 디자인시스템의
/// `StatusBadge`·`NoticeBanner` 가 `NoticeKind` 로 들고 있는 네 쌍뿐이고, 그 매핑만 이 파일이 한다
/// (`noShowBadgeKind`) — 판정과 글자는 `NoShowRecordsDisplay.swift` 가 맡는다.
///
/// - Parameter loading: 첫 조회 중. 목록이 비어 있을 때만 전체 스피너를 그린다.
/// - Parameter failed: 조회가 실패했는가. 문구는 하나다 — 사용자가 할 일은 「다시 시도」뿐이다.
/// - Parameter objectionTarget: 이의 신청 시트가 열려 있는 방. nil 이면 닫혀 있다.
/// - Parameter objectionFailure: 직전 이의 신청이 거절된 사유. 시트 안 배너가 된다.
/// - Parameter objectionSent: 201 을 받았다 — 목록 위에 안내를 띄운다.
struct NoShowRecordsScreen: View {
    private let records: [NoShowRecord]
    private let loading: Bool
    private let failed: Bool
    private let objectionTarget: Int64?
    private let reason: String
    private let submitting: Bool
    private let objectionFailure: NoShowObjectionFailure?
    private let objectionSent: Bool
    private let onObjectionOpen: (Int64) -> Void
    private let onObjectionDismiss: () -> Void
    private let onReasonChange: (String) -> Void
    private let onObjectionSubmit: () -> Void
    private let onRetry: () -> Void
    private let onBack: () -> Void

    init(
        records: [NoShowRecord] = [],
        loading: Bool = false,
        failed: Bool = false,
        objectionTarget: Int64? = nil,
        reason: String = "",
        submitting: Bool = false,
        objectionFailure: NoShowObjectionFailure? = nil,
        objectionSent: Bool = false,
        onObjectionOpen: @escaping (Int64) -> Void = { _ in },
        onObjectionDismiss: @escaping () -> Void = {},
        onReasonChange: @escaping (String) -> Void = { _ in },
        onObjectionSubmit: @escaping () -> Void = {},
        onRetry: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        self.records = records
        self.loading = loading
        self.failed = failed
        self.objectionTarget = objectionTarget
        self.reason = reason
        self.submitting = submitting
        self.objectionFailure = objectionFailure
        self.objectionSent = objectionSent
        self.onObjectionOpen = onObjectionOpen
        self.onObjectionDismiss = onObjectionDismiss
        self.onReasonChange = onReasonChange
        self.onObjectionSubmit = onObjectionSubmit
        self.onRetry = onRetry
        self.onBack = onBack
    }

    var body: some View {
        let items = records.map { $0.toNoShowItem() }

        ZStack {
            VStack(spacing: 0) {
                StatusBarSpacer()
                MoyeotaTopBar(title: "노쇼 기록", onBack: onBack)

                // 첫 조회가 끝나기 전에는 빈 상태 문구를 그리지 않는다 — 노쇼가 있는 사용자에게
                // 「기록된 적이 없어요」가 한 번 스쳐 보이면 그건 거짓말이 한 프레임 보인 것이다.
                if loading && items.isEmpty {
                    CenteredPane { CircularProgressIndicator() }
                } else if failed && items.isEmpty {
                    CenteredPane {
                        VStack(spacing: 0) {
                            Text(NO_SHOW_ERROR_TEXT)
                                .moyeotaText(.BodyMd, color: MoyeotaColor.TextMute)
                                .multilineTextAlignment(.center)
                            Spacer().frame(height: 16)
                            SecondaryButton(text: "다시 시도", onClick: onRetry)
                        }
                    }
                } else if items.isEmpty {
                    // 노쇼가 0건인 사용자가 보는 화면. **제재 계산식을 여기서는 적지 않는다** —
                    // 겪지도 않은 사람에게 24시간 제한을 설명하는 것은 안내가 아니라 경고다.
                    CenteredPane {
                        Text(NO_SHOW_EMPTY_TEXT)
                            .moyeotaText(.BodyMd, color: MoyeotaColor.TextMute)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    recordList(items: items)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MoyeotaColor.SurfaceSoft)

            // 이의 신청 시트. 목록 위에 겹쳐 띄운다 — 사유를 쓰는 동안에도 어느 방에 대한 것인지
            // 카드가 뒤에 남아 있어야 한다(시트 안에도 경로를 한 번 더 인용한다).
            if let objectionTarget {
                let target = items.first { $0.partyId == objectionTarget }
                ObjectionSheet(
                    routeLabel: target?.routeLabel,
                    reason: reason,
                    submitting: submitting,
                    failure: objectionFailure,
                    onReasonChange: onReasonChange,
                    onSubmit: onObjectionSubmit,
                    onDismiss: onObjectionDismiss
                )
            }
        }
    }

    private func recordList(items: [NoShowItem]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                if objectionSent {
                    NoticeBanner(kind: .success, text: OBJECTION_SENT_TEXT)
                }
                // 기록이 **있는** 사람에게만 계산식을 보여 준다. 자기 제한이 언제 풀리는지
                // 셀 수 있는 유일한 근거다(약속 시간 + 24시간 × 건수).
                Text(NO_SHOW_RULE_TEXT)
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                // 목록을 들고 있는데 조회가 실패한 상태(새로 받기 실패) — 조용히 옛 목록을
                // 보여 주면 사용자는 방금 낸 이의가 반영됐는지 알 수 없다.
                if failed {
                    NoticeBanner(kind: .error, text: NO_SHOW_ERROR_TEXT)
                }
                ForEach(items, id: \.partyId) { item in
                    NoShowCard(item: item, onObject: { onObjectionOpen(item.partyId) })
                }
                // 목록이 꽉 찼을 때만 「전체가 아니다」를 말한다 — 「더 보기」는 달 수 없다
                // (커서도 개수 파라미터도 없다). 판정은 `noShowHistoryCapNotice`.
                if let notice = noShowHistoryCapNotice(size: items.count) {
                    Text(notice)
                        // 읽어야 하는 사실(「최근 N건만 보여요」)이라 장식 회색이 아니라 보조 글자색이다
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        // 원본 `LazyColumn` 은 자기 칸에서 잘린다. SwiftUI `ScrollView` 는 안전 영역까지 그린다.
        .clipped()
    }
}

private struct CenteredPane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 상태 → 배지·부연의 색. **글자는 `NoShowRecordsDisplay.swift` 가 만든다**(그 파일은 색을 모른다).
private func noShowBadgeKind(state: NoShowRowState) -> NoticeKind {
    switch state {
    // 배지를 그리지 않는 상태지만 switch 를 빠짐없이 갈라 둔다 — 상태가 늘면 여기서 컴파일이 막힌다.
    case .open: .info
    case .pending: .waiting
    // 「무효」와 「이의 인정됨」은 사용자에게 좋은 소식이다 — 성공 색이 맞다.
    case .accepted, .voided: .success
    // 거절은 빨강이다. 다툼이 끝났다는 사실의 무게가 그만큼이고, 이 화면에서 빨간 배지는
    // 이것 하나뿐이라 눈에 걸린다(35 의 탈퇴 행이 카드 안 유일한 빨강인 것과 같은 규칙).
    case .rejected: .error
    }
}

/// 노쇼 한 장. **눌러도 갈 곳이 없어 카드 자체에는 탭 동작과 꺾쇠를 두지 않았다**
/// (34 지난 탑승 기록과 같은 판단 — 끝난 방의 상세 화면은 진행 중 방을 전제로 쓰여 있다).
/// 이 카드에서 유일하게 눌리는 것은 이의 신청 버튼이고, 그래서 그 버튼이 곧 상태 표시가 된다.
private struct NoShowCard: View {
    let item: NoShowItem
    let onObject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                if let routeLabel = item.routeLabel {
                    Text(routeLabel)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // 경로를 둘 다 모르는 응답. 빈 화살표를 그리지 않되 배지 자리는 지킨다.
                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                }
                if let badgeText = item.badgeText {
                    Spacer().frame(width: 8)
                    // 원본 `Row` 는 무게 없는 배지를 먼저 재고 남은 폭을 경로에 준다 — 배지는 줄지 않는다.
                    StatusBadge(kind: noShowBadgeKind(state: item.state), text: badgeText)
                        .fixedSize()
                }
            }

            if item.meetingLabel != nil || item.markedLabel != nil {
                Spacer().frame(height: 12)
                // 두 시각을 **이름을 붙여** 나란히 둔다. 날짜만 두 줄 있으면 어느 쪽이 내 약속이었고
                // 어느 쪽이 찍힌 때인지 알 수 없는데, 제한은 **약속 시간부터** 세므로 그 구분이
                // 사용자가 자기 제한 기한을 계산하는 근거다.
                if let meetingLabel = item.meetingLabel {
                    TimeRow(label: NO_SHOW_FIELD_MEETING, value: meetingLabel)
                }
                if let markedLabel = item.markedLabel {
                    if item.meetingLabel != nil { Spacer().frame(height: 4) }
                    TimeRow(label: NO_SHOW_FIELD_MARKED, value: markedLabel)
                }
            }

            if let note = item.note {
                Spacer().frame(height: 8)
                Text(note)
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
            }

            // ★ 이 줄이 이 화면의 1급 규칙이다 — 서버가 201 을 주는 조건과 같은 조건에서만 그린다.
            if item.allowsObjection {
                Spacer().frame(height: 12)
                HorizontalDivider(color: MoyeotaColor.Hairline)
                Spacer().frame(height: 12)
                SecondaryButton(text: "이의 신청", onClick: onObject)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoyeotaColor.SurfaceCard, in: MoyeotaShape.Card)
    }
}

private struct TimeRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(label)
                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextBody)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 원본 `it.take(OBJECTION_REASON_HARD_LIMIT)` 자리 — **UTF-16 단위**로 자른다(원본 `String.length` 의 단위,
/// 카운터도 같은 단위로 센다). 다만 서로게이트 쌍은 가르지 않는다: Swift 문자열은 홀로 남은 서로게이트를
/// 담지 못해(U+FFFD 로 바뀐다) 경계에 걸린 이모지는 반쪽 대신 통째로 빠진다.
private func takeUtf16KeepingSurrogates(_ text: String, _ limit: Int) -> String {
    guard text.utf16.count > limit else { return text }
    var kept = String.UnicodeScalarView()
    var count = 0
    for scalar in text.unicodeScalars {
        let width = scalar.utf16.count
        if count + width > limit { break }
        kept.append(scalar)
        count += width
    }
    return String(kept)
}

/// 이의 사유를 쓰는 시트.
///
/// ### 보낼 수 없는 글을 보내게 두지 않는다
/// 서버는 `reason` 을 **trim 한 뒤 1~500자**로만 받고 벗어나면 400 `INVALID_REQUEST` 다. 그 응답
/// 문구로는 무엇을 고쳐야 하는지 알 수 없으므로, 카운터를 **처음부터** 보여 주고 버튼을 잠근다
/// (`objectionReasonUi` — 잠긴 이유가 카운터에 이미 적혀 있다).
///
/// ### 되돌릴 수 없는 한 번이다
/// 방마다 한 번뿐이라 보내고 나면 고칠 수 없다. 그래서 확인 다이얼로그를 또 겹치지 않는 대신
/// **시트 안에 그 사실을 적고**(`OBJECTION_SHEET_NOTICE`) 보내기 버튼을 유일한 Primary 로 둔다.
///
/// ### 실패가 끝인지 아닌지를 버튼으로 말한다
/// 403·409·404 는 다시 눌러도 같은 답이다(`NoShowObjectionFailure.isTerminal`) — 그때는 보내기를
/// 잠그고 「닫기」만 남긴다. 문구에 「다시 시도」류를 넣지 않는 것과 같은 규칙을 버튼에도 적용한
/// 것이다(`FinishFailureMessageTest` 의 바). 연결 실패(unknown)만 다시 누를 수 있다.
///
/// 디자인시스템의 `MoyeotaTextField` 를 쓰지 않은 이유는 24 채팅의 신고 상세 칸과 같다 — 그
/// 컴포넌트는 입력 박스를 52pt 고정 높이로 그려서 500자를 받는 칸에서는 글이 잘려 보인다.
private struct ObjectionSheet: View {
    let routeLabel: String?
    let reason: String
    let submitting: Bool
    let failure: NoShowObjectionFailure?
    let onReasonChange: (String) -> Void
    let onSubmit: () -> Void
    let onDismiss: () -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let shape = MoyeotaShape.Dialog
        ZStack {
            MoyeotaColor.Scrim
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            // 시트 안을 눌렀을 때 바깥(닫기)으로 새지 않는다 — 시트가 스크림 위의 형제라 탭이 스크림까지 내려가지 않는다.
            //
            // 키보드가 올라오면 시트가 그만큼 올라와야 한다 — 없으면 500자를 다 쓴 사용자가 키보드 뒤에
            // 숨은 보내기 버튼을 누를 수 없다(원본 `imePadding`). SwiftUI 기본 키보드 회피가 이 시트를 감싼
            // 칸을 줄여 가운데 정렬이 키보드 위로 옮겨 간다 — 24 채팅 신고 시트가 같은 처리를 한다. 그래서
            // `ignoresSafeArea(.keyboard)` 를 걸지 않는다.
            //
            // 작은 폰에서 내용이 화면을 넘길 수 있어 스크롤을 둔다. `ScrollView` 는 남는 높이를 다 차지하므로
            // 내용 높이까지만 쓰게 묶는다(원본 `verticalScroll` 은 내용만큼이고 넘칠 때만 스크롤된다).
            ScrollView {
                sheetContent
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            // 원본 `verticalScroll` 은 키보드를 건드리지 않는다 — 보내기까지 내리는 동안에도 계속 쓸 수 있다.
            .scrollDismissesKeyboard(.never)
            .frame(maxHeight: contentHeight)
            .background(MoyeotaColor.SurfaceCanvas)
            .clipShape(shape)
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        let input = objectionReasonUi(reason: reason, submitting: submitting)
        // 끝난 실패는 다시 보낼 수 없다 — 잠그는 판단은 enum 이 들고 있고 화면은 묻기만 한다.
        let terminal = failure?.isTerminal == true
        VStack(alignment: .leading, spacing: 0) {
            Text(OBJECTION_SHEET_TITLE)
                .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
            if let routeLabel {
                Spacer().frame(height: 8)
                // 홑낫표로 인용한다 — 공통 규칙(인용값은 「」). 어느 방에 대한 이의인지
                // 보여 주지 않으면 20개 목록에서 누른 카드가 맞는지 확인할 길이 없다.
                Text(verbatim: "「\(routeLabel)」")
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
            }

            Spacer().frame(height: 16)
            ZStack(alignment: .topLeading) {
                BasicTextField(
                    value: reason,
                    // 한도의 2배에서 자른다 — 붙여넣기 폭주만 막고, 「넘었다」는 카운터가 말한다.
                    onValueChange: { onReasonChange(takeUtf16KeepingSurrogates($0, OBJECTION_REASON_HARD_LIMIT)) },
                    textStyle: MoyeotaType.BodyMd.copy(color: MoyeotaColor.InkPrimary),
                    // 여러 줄로 받는다 — 상황을 적는 칸이라 한 줄로 가로 스크롤되면 쓴 글을
                    // 다시 읽을 수가 없다.
                    singleLine: false,
                    enabled: !submitting
                )
                if reason.isEmpty {
                    Text(OBJECTION_INPUT_PLACEHOLDER)
                        .moyeotaText(.BodyMd, color: MoyeotaColor.TextPlaceholder)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(MoyeotaColor.SurfaceSoft, in: MoyeotaShape.Card)
            Spacer().frame(height: 6)
            Text(input.counter)
                .moyeotaText(
                    MoyeotaType.CaptionMd.hangulTrimmed,
                    color: input.overLimit ? MoyeotaColor.Danger600 : MoyeotaColor.TextMute
                )

            Spacer().frame(height: 12)
            Text(OBJECTION_SHEET_NOTICE)
                .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)

            if let failure {
                Spacer().frame(height: 12)
                NoticeBanner(kind: .error, text: noShowObjectionFailureMessage(failure: failure))
            }

            Spacer().frame(height: 20)
            HStack(spacing: 8) {
                SecondaryButton(
                    text: terminal ? "닫기" : "취소",
                    onClick: onDismiss,
                    enabled: !submitting
                )
                PrimaryCtaButton(
                    text: submitting ? OBJECTION_SUBMITTING_LABEL : OBJECTION_SUBMIT_LABEL,
                    onClick: onSubmit,
                    enabled: input.submitEnabled && !terminal,
                    loading: submitting
                )
            }
        }
    }
}
