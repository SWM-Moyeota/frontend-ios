import MoyeotaDesignSystem
import MoyeotaDomain
import Observation
import PresentationCore
import SwiftUI

/// 14 홈의 **「아직 보내지 않은 택시비」 배너** — 서버 Swagger 가 이 용도를 직접 적어 둔 목록이다
/// (`GET /users/me/fare-splits?status=NOT_SENT`: 「홈 배너(아직 보내지 않은 택시비)에 쓴다.
/// 항목을 누르면 partyId 로 정산 상세를 연다」).
///
/// ### 비어 있으면 **아무것도 그리지 않는다** ★
/// 「보낼 택시비가 없어요」라는 빈 상태를 두지 않는다. 이 배너가 서는 자리는 홈 **지도 위**이고,
/// 평상시(보낼 돈이 없는 날)가 압도적으로 많다 — 그때마다 한 칸을 차지하면 **지도를 가리는 상설
/// 안내문**이 된다. 진행 중인 방 배너(`ActiveRideBanner`)가 같은 규칙으로 서 있다.
///
/// ### 조회 실패도 **아무것도 그리지 않는다**
/// 배너에 「불러오지 못했어요」를 띄우지 않는다. 사용자가 그 자리에서 할 수 있는 일이 없고
/// (재시도 버튼은 배너를 두 줄로 만든다), 보낼 돈이 실제로 있으면 **다음 복귀에서 다시 나타난다**
/// (`onScreenStart`). 34 기록이 반대로 하는 것(실패를 말한다)과 어긋나 보이지만 사정이 다르다 — 그쪽은
/// **사용자가 보러 간 화면**이라 빈 목록이 「기록이 사라졌다」로 읽히고, 이쪽은 **불러 주지 않은 알림**이라
/// 없을 때가 정상이다.
///
/// ### 「받는 사람」 배너는 이 목록으로 만들 수 없다
/// 서버가 **내가 보내는 사람인 정산만** 준다. 방장의 「정산을 시작하세요」 배너를 이 목록으로 만들면
/// **영구히 비어 있다**(`FareSplitRepository.getMyFareSplits` 주석). 그 진입점은 탑승 기록 쪽이다.
///
/// ### 조회는 **화면 시작 한 곳에서만**, 그리고 **늘 마지막 요청이 이긴다** (Android PR #106 리뷰 반영)
/// 원본은 `init` 과 화면 시작이 **둘 다** 조회를 걸었다 — 첫 진입에서 같은 요청이 두 번 나가고, 둘의 응답
/// 순서가 바뀌면 **먼저 보낸(더 낡은) 응답이 나중에 도착해 새 목록을 덮는다.** 여기서는 `init` 이 조회하지
/// 않고, 조회 태스크를 하나만 들고 새로 걸 때 앞의 것을 취소한다. 취소된 태스크는 응답이 와도 목록에 쓰지 않는다.
@MainActor
@Observable
public final class FareSplitBannerViewModel {
    public private(set) var items: [MyFareSplit] = []

    @ObservationIgnored private let repository: any FareSplitRepository
    @ObservationIgnored private let scope = ViewModelScope()

    /// 지금 도는 조회. 새로 걸면 이것부터 취소한다 — 테스트가 조회가 끝나기를 기다리는 손잡이이기도 하다.
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?

    /// **조회하지 않는다** — 위 「화면 시작 한 곳에서만」. 첫 조회는 홈이 보이는 순간의 `onScreenStart` 다.
    public init(repository: any FareSplitRepository) {
        self.repository = repository
    }

    /// 홈이 보일 때마다 다시 읽는다 — **이 목록을 갱신하는 다른 수단이 없다.**
    ///
    /// 「보냈어요」가 성공하면 그 방은 `NOT_SENT` 목록에서 빠져야 하는데, 그 사실을 알려 주는
    /// 신호(SSE·푸시)가 없다. 39 에서 보낸 뒤 홈으로 돌아오면 여기서 다시 읽혀 배너가 줄어든다.
    /// 주기 폴링을 두지 않는 이유: 홈은 이미 지도·즐겨찾기로 요청이 많고, 이 목록은 **사용자가
    /// 움직였을 때만** 바뀐다(남이 바꿀 수 있는 값이 아니다).
    public func onScreenStart() {
        refresh()
    }

    /// 실패를 **삼킨다**. 들고 있던 목록을 지우지도 않는다 — 한 번 실패했다고 보낼 돈이 사라진 것은
    /// 아니고, 배너가 깜빡이며 사라졌다 나타나면 홈이 불안해 보인다(17 탐색의 `markStale` 과 같은 결의
    /// 판단이지만, 배너에는 「낡음」을 말할 자리가 없어 그냥 유지한다).
    func refresh() {
        refreshTask?.cancel()
        let repository = self.repository
        refreshTask = scope.launch { [weak self] in
            do {
                let fetched = try await repository.getMyFareSplits(status: .notSent)
                // 뒤에 건 조회가 이 태스크를 취소했다면 이 응답은 더 낡았다 — 쓰지 않는다.
                guard !Task.isCancelled, let self else { return }
                self.items = fetched
            } catch {
                // 아무것도 하지 않는다 — 위 주석 참고. 로그도 남기지 않는다(계좌·금액이 섞인 응답이다).
            }
        }
    }
}

/// 홈에 **꽂는 자리** — 조회 시점(화면 시작)과 「비면 그리지 않기」를 안에서 끝낸다.
///
/// 호출부(14 홈)가 뷰모델과 이동만 넘기면 되도록 만든 이유: 홈이 배너용 상태를 직접 들면 **홈이 정산을
/// 알아야** 한다. 원본의 `FareSplitBannerHost` 와 같은 자리다.
///
/// ### 원본과 모양이 다른 점 — 배너를 **슬롯으로 돌려준다**
/// 원본은 빈 목록이면 Composable 이 아무것도 그리지 않아, 홈의 배너 묶음이 저절로 줄어든다. iOS 홈은 배너 묶음
/// 높이로 지도의 안쪽 여백(줌 버튼·카메라 중심)을 정하므로, **보낼 정산이 없는 날 배너 자리가 남아 있으면** 지도가
/// 상태바 높이만큼 내려앉는다. 그래서 「그릴 것이 있는가」를 이 자리에서 판정해 **없으면 nil** 을 넘기고, 홈은
/// nil 이면 묶음 자체를 만들지 않는다(진행 중 방이 없는 날의 지금 모습 그대로다).
///
/// 뷰모델을 밖에서 받는 이유: 탭을 옮겼다 돌아와도 받아 둔 목록이 남아야 배너가 깜빡이지 않는다 —
/// 홈의 다른 뷰모델처럼 그 칸에 맡겨 둔 인스턴스를 넘긴다(`MoyeotaNavController.retained`).
public struct FareSplitBannerHost<Content: View>: View {
    private let viewModel: FareSplitBannerViewModel
    private let onOpen: (Int64) -> Void
    private let content: (AnyView?) -> Content

    /// - Parameters:
    ///   - onOpen: 항목을 눌렀다 — `partyId` 로 39 정산 상세를 연다.
    ///   - content: 배너(없으면 nil)를 받아 홈을 그린다.
    public init(
        viewModel: FareSplitBannerViewModel,
        onOpen: @escaping (Int64) -> Void,
        @ViewBuilder content: @escaping (AnyView?) -> Content
    ) {
        self.viewModel = viewModel
        self.onOpen = onOpen
        self.content = content
    }

    public var body: some View {
        let viewModel = self.viewModel
        let items = viewModel.items
        content(items.isEmpty ? nil : AnyView(FareSplitBanner(items: items, onItemClick: onOpen)))
            // 홈이 보일 때마다(다른 화면에서 돌아올 때·앱을 다시 앞으로 가져올 때) 다시 읽는다.
            .lifecycleEffect(onStart: { viewModel.onScreenStart() })
    }
}

/// 배너 본체(상태 없음). **`items` 가 비면 아무것도 그리지 않는다.**
public struct FareSplitBanner: View {
    private let items: [MyFareSplit]
    private let onItemClick: (Int64) -> Void

    public init(items: [MyFareSplit], onItemClick: @escaping (Int64) -> Void) {
        self.items = items
        self.onItemClick = onItemClick
    }

    public var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: MoyeotaSpacing.Xxs) {
                HStack(alignment: .center, spacing: MoyeotaSpacing.Xs) {
                    Text("아직 보내지 않은 택시비")
                        .moyeotaText(MoyeotaType.HeadingMd.hangulTrimmed, color: MoyeotaColor.InkPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    // 건수를 적는다 — 세 건이 쌓였을 때 한 건만 보내고 끝난 줄 알기 쉽다.
                    Text("\(items.count)건")
                        .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                }
                ForEach(Array(items.enumerated()), id: \.element.partyId) { index, item in
                    if index > 0 {
                        HorizontalDivider(color: MoyeotaColor.Hairline)
                    }
                    FareSplitBannerRow(item: item, onClick: { onItemClick(item.partyId) })
                }
            }
            .padding(.horizontal, MoyeotaSpacing.Md)
            .padding(.vertical, MoyeotaSpacing.Sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MoyeotaColor.SurfaceCanvas, in: MoyeotaShape.Card)
            // 지도 위에 뜨는 배너라 그림자를 남긴다 — 진행 중 방 배너(`ActiveRideBanner`)와 같은 높이·색이다(디자인 QA G4 예외).
            .mapOverlayShadow(MoyeotaShape.Card)
        }
    }
}

/// 한 줄: 금액이 가장 크고, 받는 사람과 경로가 그 아래 보조로 붙는다.
///
/// 금액을 앞세우는 이유: 이 배너를 누르는 판단은 「얼마를 보내야 하나」이고, 경로는 **어느 날의
/// 탑승인지 떠올리는** 보조 정보다. 경로가 없는 줄도 있으므로(방이 지워진 뒤에도 정산은 남는다)
/// 경로를 앞세우면 **어떤 줄은 머리가 비어 보인다**(`myFareSplitRouteLabel`).
///
/// 마감을 적지 않는다 — 만료 경계가 「1일 + 최대 30분」이라 배너 한 줄로 약속할 수 있는 값이 아니다
/// (`EXPIRY_NOTICE`). 그 안내는 상세 화면이 한다.
private struct FareSplitBannerRow: View {
    let item: MyFareSplit
    let onClick: () -> Void

    var body: some View {
        let actionType = MoyeotaType.BodySm.copy(fontWeight: .semibold).hangulTrimmed
        Button(action: onClick) {
            HStack(alignment: .center, spacing: MoyeotaSpacing.Xs) {
                VStack(alignment: .leading, spacing: MoyeotaSpacing.Xxs) {
                    Text(fareWonLabel(amount: item.myAmount))
                        .moyeotaText(MoyeotaType.HeadingMd.tabularNums().hangulTrimmed, color: MoyeotaColor.InkPrimary)
                    Text("\(item.payer.displayName)님에게")
                        .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let route = myFareSplitRouteLabel(item: item) {
                        Text(route)
                            .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 「›」 글자 대신 그린 꺾쇠 — 진행 중 방 배너의 「보기」와 같은 모양이다(G10)
                Text("보내기")
                    .moyeotaText(actionType, color: MoyeotaColor.Primary600)
                    .fixedSize(horizontal: true, vertical: false)
                ChevronIcon(size: MoyeotaIconSize.Sm, tint: MoyeotaColor.Primary600)
            }
            .padding(.vertical, MoyeotaSpacing.Xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("택시비 정산을 열어요")
    }
}
