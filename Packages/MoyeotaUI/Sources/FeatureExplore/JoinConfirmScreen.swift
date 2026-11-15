import Foundation
import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 원본 `"%,d원".format(amount)` — 천 단위 구분은 원본처럼 기기 로케일을 따른다.
func won(amount: Int, locale: Locale = .current) -> String {
    "\(amount.formatted(.number.locale(locale).grouping(.automatic)))원"
}

/// 지도 스트립 높이.
private let JoinMapHeight: CGFloat = 172

/// 시트가 시작하는 높이 — 지도 아래 12 를 덮는다(그 겹침이 카메라 여백에 더해진다).
private let JoinSheetTop: CGFloat = 160

/// 지도 위 소요 시간 칩의 바깥 여백과 높이 — 카메라 위쪽 여백이 이 둘을 더한 만큼 커진다.
private let EtaChipMargin: CGFloat = 16
private let EtaChipHeight: CGFloat = 30

/// 방 좌표를 하나도 못 쓸 때 20 의 지도가 보여 줄 곳 — **내 위치**, 없으면 **앱 기본 카메라**.
///
/// 반드시 값을 준다(nil 을 돌려주지 않는다): `RouteStripMap` 은 이 값이 nil 이고 도착지도 없으면
/// 자리표시자를 그리는데, 20 은 「어디서 타는 방인가」를 보는 화면이라 빈 회색 상자보다 지도가 낫다.
/// 그리고 끝까지 물러나도 **SDK 기본 카메라(서울)가 아니다**.
func joinMapFallback(userPosition: LatLng?) -> LatLng {
    guard let userPosition, isUsableMapCoordinate(latitude: userPosition.latitude, longitude: userPosition.longitude) else {
        return MoyeotaDefaultCamera
    }
    return userPosition
}

/// 20 · 합류 확인 [신규]
///
/// 진입: 18·19 목록/마커의 「합류」
///
/// 이동(디스크립션):
/// - 「닫기」 / 뒤로가기 → 직전 목록(18/19)으로 복귀 (onDismiss)
/// - 「이 탑승에 합류하기」 → 22 탑승 상세 (onConfirmJoin, 제출 중 loading)
/// - 동승자 행 탭 → 23 동승자 프로필 (onMemberClick)
///
/// 표시 값은 전부 방 상세(`Ride`)에서 나온다. 서버가 주지 않는 값(성별 조건·탑승 시각·서비스 요금)은
/// 지어내지 않고 그 요소를 아예 두지 않는다 — 출발 표기는 `Ride.departureLabel` 이 있을 때만,
/// 도착 쪽은 `Ride.estimatedMinutes` 가 있을 때만 「약 N분」으로 보이고, 1인 부담은 `Ride.farePerPerson` 그대로다.
///
/// 검증·상태 — **판정은 `joinGate` 하나**이고 배지·배너·CTA 가 모두 그 결과를 따른다:
/// - 상태 배지는 `Ride.status` 를 그대로 읽는다(`joinStatusBadge`) — 예전에는 문자열 리터럴이라
///   **취소된 방에도 「모집 중」**이 떠 있었다. 17 목록은 15초 주기라 방을 고르는 사이에 마지막 멤버가
///   나가 방이 닫힐 수 있다(`Party.leave` → `members.isEmpty()` → `cancel()`)
/// - 모집 중이 아니거나 정원이 찼으면 CTA 비활성 + CTA 위 NoticeBanner(ERROR) **한 줄**
///   (배너는 **하나만** 띄운다 — 예전에는 「방금 인원이 찼어요」와 서버 실패 문구가 거의 같은 말을
///   두 번 했다: `refreshQuietly()` 가 성공하면 둘이 함께 떴다)
/// - 내가 이미 그 방 멤버면 「이미 참여 중인 방이에요」 + CTA 는 그 방으로 돌아가기(`onOpenJoinedRide`)
/// - 서버 합류 실패(엔드포인트 부재 포함) 시 joinErrorMessage 를 같은 자리에 그대로 노출
public struct JoinConfirmScreen: View {
    private let ride: Ride
    private let pickupDistanceMeters: Double?
    private let userPosition: LatLng?
    private let joining: Bool
    private let joinErrorMessage: String?
    private let onDismiss: () -> Void
    private let onConfirmJoin: (Ride) -> Void
    private let onOpenJoinedRide: (Ride) -> Void
    private let onMemberClick: (User) -> Void

    // 예약 방의 「오늘 오후 6:30」을 셈하는 기준 시각. **한 번만 읽는다** — 그릴 때마다
    // 시계를 읽을 이유가 없고(날짜 경계를 넘길 만큼 머무는 화면이 아니다), 읽으면 같은 방이
    // 프레임마다 다른 글자를 갖는다. 「한 번」은 화면이 보일 때마다 한 번이다(`body` 끝의 `.onAppear`).
    @State private var now = Date()

    /// - Parameters:
    ///   - pickupDistanceMeters: 내 위치 → 이 방의 탑승 위치 거리(m). 모르면 nil 이고 그 줄을 감춘다.
    ///     「도보 N분」은 쓰지 않는다 — 보행 속도를 지어내야 하고, 거리와 달리 잰 값이 아니다.
    ///   - userPosition: 내 현재 위치. 지도가 방 좌표를 하나도 못 쓸 때(누락·(0,0)·NaN) 「내 주변」으로 물러나는 자리다.
    ///     모르면 nil — 그때는 앱 기본 카메라다(`joinMapFallback`).
    ///   - onOpenJoinedRide: 내가 이미 이 방 멤버일 때의 CTA — 호출부가 그 방의 진행 화면(21)으로 보낸다.
    ///     Route 는 합류 성공과 **같은 길**(`JoinConfirmRoute` 의 onJoined)로 넘긴다: 서버가 409
    ///     `ALREADY_JOINED` 를 돌려줄 때 이미 그렇게 처리하고 있어서
    ///     (`PartyJoinException.isAlreadyInThisParty`) 새 네비게이션이 필요 없다.
    ///     기본값은 방어용 빈 클로저다 — 연결하지 않은 호출부에서는 버튼이 아무 일도 하지 않는다.
    public init(
        ride: Ride,
        pickupDistanceMeters: Double? = nil,
        userPosition: LatLng? = nil,
        joining: Bool = false,
        joinErrorMessage: String? = nil,
        onDismiss: @escaping () -> Void = {},
        onConfirmJoin: @escaping (Ride) -> Void = { _ in },
        onOpenJoinedRide: @escaping (Ride) -> Void = { _ in },
        onMemberClick: @escaping (User) -> Void = { _ in }
    ) {
        self.ride = ride
        self.pickupDistanceMeters = pickupDistanceMeters
        self.userPosition = userPosition
        self.joining = joining
        self.joinErrorMessage = joinErrorMessage
        self.onDismiss = onDismiss
        self.onConfirmJoin = onConfirmJoin
        self.onOpenJoinedRide = onOpenJoinedRide
        self.onMemberClick = onMemberClick
    }

    public var body: some View {
        let joinedCount = ride.members.count
        // 내가 이미 이 방의 멤버인가. 「나」 판정의 근거는 서버가 멤버마다 실어 주는 publicId 와 세션
        // uuid 의 비교 하나다(`PartyMappers` 의 `toUser` — 방장 판정과 달리 **폴백이 없어** 한쪽으로
        // 기울지 않는다). 20 은 방 상세를 읽어 그리므로 이 비교가 성립한다 — 식별자가 없는 목록·생성
        // 응답의 자리 표시용 멤버는 늘 false 다. 로그인 복원 전이면 세션 uuid 가 nil 이라 false 로
        // 떨어지는데, 그때 눌러도 서버 409 를 「이미 합류됨」으로 받아 21 로 보낸다
        // (JoinConfirmViewModel.join) — 문구는 덜 정확해지지만 갈 곳은 같다.
        let iAmMember = ride.members.contains { $0.isMe }
        // 배지·배너·CTA 를 **한 판정**에서 뽑는다 — 세 자리가 제각각 다른 조건을 보면 「모집 중」 배지 +
        // 활성 CTA + 「모집이 끝났어요」 배너처럼 서로 모순되는 화면이 나온다.
        let gate = joinGate(
            status: ride.status,
            joinedCount: joinedCount,
            capacity: ride.capacity,
            iAmMember: iAmMember
        )
        let badge = joinStatusBadge(status: ride.status)
        // 배너는 한 줄만 — 막힌 이유가 있으면 그것을, 없으면 서버가 돌려준 실패 문구를 보여 준다.
        let noticeMessage = joinGateMessage(gate: gate) ?? joinErrorMessage

        // 지도에 그릴 값 — 전부 방 상세(Ride)에서 나온다. 좌표가 못 쓸 값이면(서버 위경도 전치, QA D-1)
        // latLngOrNull 이 nil 을 돌려주고 지도는 자리표시자로 떨어진다.
        let originPosition = latLngOrNull(latitude: ride.originLat, longitude: ride.originLng)
        let destinationPosition = latLngOrNull(latitude: ride.destinationLat, longitude: ride.destinationLng)
        let routePath = ride.routePolyline.map { decodePolyline(encoded: $0) } ?? []
        // 거리는 서버가 주지 않아 **경로선에서 직접 잰다**. 경로가 없으면 거리 표기를 생략한다 —
        // 출발·도착 직선거리로 대체하면 실제 주행 거리보다 짧아 요금과 어긋나 보인다.
        let routeMeters = polylineDistanceMeters(points: routePath)
        let routeKm = routeMeters > 0.0 ? routeMeters / 1000.0 : nil
        let etaLabel = buildRouteChipLabel(estimatedMinutes: ride.estimatedMinutes, routeKm: routeKm)
        let fare = joinFareOrNull(totalFare: ride.totalFare, farePerPerson: ride.farePerPerson)

        let sheetShape = MoyeotaShape.Sheet

        VStack(spacing: 0) {
            // 상단 헤더 — 하위 화면 공용 앱바(디자인 QA G7·J3). 예전엔 왼쪽 정렬 18 Bold 를 손으로 그렸고
            // 뒤로가기는 화살표 그림만 눌렸다(48 이 안 됐다)
            StatusBarSpacer()
            MoyeotaTopBar(title: "합류할까요?", onBack: onDismiss)

            ZStack(alignment: .top) {
                // 경로 지도 스트립 — 카메라는 출발·도착(+경로선)이 **가리지 않는 영역**에 다 들어오게 맞춘다
                // (2026-11, 오너 UX 피드백: 「가끔 엉뚱한 곳, 심지어 해외가 보인다」). 원인은 둘이었다:
                // ① (0,0) 같은 못 쓸 좌표가 카메라 범위에 섞여 바다 한가운데를 비췄고 ② 지도가 준비된 뒤에야
                // 카메라를 옮겨 SDK 기본 카메라(서울)가 먼저 보였다. ①은 `routeCameraTarget` 이 좌표를 걸러
                // 정해진 순서(출발지 → 도착지 → 내 주변 → 앱 기본)로 물러나 막고, ②는 `NaverMapView` 가 첫
                // 카메라를 생성 옵션으로 걸어 막는다. 방을 다시 읽어 좌표가 바뀌면 그때 다시 맞춘다.
                //
                // 여백(디자인 QA 4-7): 좌우 48, 위는 소요 시간 칩(16 + 30)만큼 더(칩이 있을 때만),
                // 아래는 시트가 덮는 12 만큼 더 — 마커 머리·캡션 높이는 `RouteStripMap` 이 얹는다. 최대 줌 16.
                ZStack(alignment: .topLeading) {
                    RouteStripMap(
                        originPosition: originPosition,
                        destinationPosition: destinationPosition,
                        routePath: routePath,
                        fallbackPosition: joinMapFallback(userPosition: userPosition),
                        obscuredTop: etaLabel != nil ? EtaChipMargin + EtaChipHeight : 0,
                        obscuredBottom: JoinMapHeight - JoinSheetTop,
                        sidePadding: 48
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 시간·거리 둘 다 없으면 칩을 통째로 감춘다 — 틀린 값보다 없는 편이 낫다.
                    // 지도 위 공용 흰 알약(`MapOverlayPill`, 30 = `EtaChipHeight`)이다 — 16·21 의 요약 칩과 같은 그림자·모양
                    if let etaLabel {
                        MapOverlayPill {
                            Text(etaLabel)
                                .moyeotaText(
                                    MoyeotaType.BodySm.copy(fontWeight: .semibold).hangulTrimmed,
                                    color: MoyeotaColor.InkPrimary
                                )
                        }
                        .padding(EtaChipMargin)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: JoinMapHeight)

                // 바텀시트
                VStack(spacing: 0) {
                    Spacer().frame(height: 12)
                    SheetHandle()
                        .frame(maxWidth: .infinity)

                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer().frame(height: 12)

                            // 상태 행
                            HStack(spacing: 0) {
                                StatusBadge(kind: badge.kind, text: badge.text)
                                    .fixedSize()
                                Spacer().frame(width: 8)
                                Text(
                                    joinHeadcountLine(
                                        joinedCount: joinedCount,
                                        capacity: ride.capacity,
                                        iAmMember: iAmMember
                                    )
                                )
                                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Spacer().frame(height: 16)
                            // 경로·요금은 **판 없이** 시트 위에 바로 놓는다(디자인 QA J1) — 예전엔 옅은 파란 판(경로) 아래
                            // 회색 판 안에 또 파란 판(1인 부담)이 있는 "카드 더미"였다. 22 탑승 상세와 같은 공용 조각이다.
                            RouteSummary(
                                origin: ride.origin,
                                destination: ride.destination,
                                // 예약 방은 **언제 출발하는지가 합류 판단의 전부**다(사흘 뒤 오전 9시 방에
                                // 들어가는 일이다). 서버가 주는 `departureLabel` 이 비어 올 수 있어
                                // 약속 시각에서 직접 만든다 — 실시간 방은 예전 표기를 그대로 둔다
                                // (그쪽 라벨에는 거리가 함께 들어 있다).
                                originMeta: joinDepartureLabel(ride: ride, now: now)
                                    ?? (ride.departureLabel.isBlank ? nil : ride.departureLabel),
                                destinationMeta: ride.estimatedMinutes.map { "약 \($0)분" },
                                // 내 위치를 모르면 점선만 남는다 — 보행 시간 같은 지어낸 값을 채우지 않는다
                                connectorNote: pickupDistanceMeters.map { "내 위치에서 \(pickupDistanceLabel(meters: $0))" }
                            )

                            Spacer().frame(height: 16)
                            // **요금을 모르는 방에는 요금 요약을 그리지 않는다**(`joinFareOrNull`) —
                            // 예전에는 예약 방에서 「총 예상 요금 0원 · 합류 시 1인 부담 0원」을 그렸다.
                            if let fare {
                                // 계산 근거 한 줄(「총 예상 요금을 정원 N명으로 나눈 금액이에요」)은 FareSummary 가 맡는다 —
                                // 아래 안내 줄이 같은 말을 한 번 더 하던 것은 지웠다(디자인 QA J2)
                                FareSummary(
                                    total: won(amount: fare.totalFare),
                                    perPerson: won(amount: fare.farePerPerson),
                                    capacity: ride.capacity,
                                    perPersonLabel: "합류 시 1인 부담"
                                )
                            } else {
                                // 요금 요약과 **같은 자리·같은 구분선** 아래 한 줄 — 회색 판을 깔지 않는다
                                HorizontalDivider(color: MoyeotaColor.Hairline)
                                Spacer().frame(height: 16)
                                Text(joinFareAbsentNotice(roomType: ride.roomType))
                                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Spacer().frame(height: MoyeotaSpacing.SectionGap)
                            // 인원 수는 머리말에 다시 적지 않는다 — 맨 위 상태 행이 이미 「N명 참여」라고 말한다(디자인 QA J2)
                            SectionLabel(text: "이미 참여한 사람")
                            // 대표로 한 명만 노출한다 — 첫 멤버라는 것 외에 특별한 지위는 없다.
                            // 탈퇴 회원이 앞에 있으면 볼 것도 눌러 볼 것도 없어 실재하는 멤버를 앞세운다.
                            if let representative = ride.members.first(where: { !$0.isWithdrawn }) ?? ride.members.first {
                                MemberRow(
                                    member: representative,
                                    othersCount: joinedCount - 1,
                                    onClick: { onMemberClick(representative) } // → 23 동승자 프로필
                                )
                            }

                            // ★ **예약 방은 합류하면 나갈 수 없다.** 누르기 **전에** 말해야 하는 사실이라
                            // 안내 줄보다 눈에 들게 적는다(`reservationCommitmentNotice` 주석의 근거):
                            // 실시간 방은 「그만 찾기」로 빠져나올 수 있어서 사용자는 합류를 되돌릴 수 있는
                            // 선택으로 배워 왔고, 이 버튼은 같은 모양으로 전혀 다른 약속을 하게 만든다.
                            //
                            // 공용 안내 배너(INFO)다(디자인 QA G8·J3) — INFO 는 이제 **회색**이라, CTA 바로 위의 막힘·실패
                            // 배너(빨강, 이 화면의 「배너 하나」 자리)와 색으로도 자리로도 갈린다. 이 줄은 스크롤 본문에 있고
                            // 그 배너는 CTA 위에 고정이다. 오류가 아니므로 빨강을 쓰지 않는 것은 그대로다.
                            if ride.roomType == .reservation {
                                Spacer().frame(height: 12)
                                NoticeBanner(kind: .info, text: reservationCommitmentNotice(joining: true))
                            }

                            Spacer().frame(height: 12)
                            // 1인 부담금의 계산 방식은 바로 위 요금 요약이 이미 말한다 — 여기서 다시 쓰지 않는다(디자인 QA J2)
                            Text("합류하면 바로 채팅방에 들어가요")
                                .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                            Spacer().frame(height: 16)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: .infinity)

                    // 막힌 사유든 서버 실패든 **배너는 하나**다 (스펙 20). 전에는 「방금 인원이 찼어요」와
                    // 서버가 돌려준 「방이 가득 찼어요」가 거의 같은 말을 두 번 했다 — 합류 실패 뒤
                    // `refreshQuietly()` 가 성공하면 두 조건이 동시에 참이 된다.
                    if let noticeMessage {
                        NoticeBanner(
                            // 「이미 참여 중」은 실패가 아니라 안내다 — 빨간 배너로 띄우면 뭔가 잘못된
                            // 것처럼 보여 「방으로 돌아가기」 CTA 와 모순된다.
                            kind: gate == .alreadyJoined ? .info : .error,
                            text: noticeMessage
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }

                    HStack(spacing: 12) {
                        SecondaryButton(text: "닫기", onClick: onDismiss)
                            .frame(width: 112)
                        // 이미 멤버면 합류가 아니라 **그 방으로 돌아가는** 버튼이다 — 서버는 재합류를
                        // 409 로 막고, 그 409 는 이미 「이미 합류됨」으로 다뤄 21 로 보내고 있다
                        // (JoinConfirmViewModel.join). 같은 곳으로 가는 길을 버튼으로 당겨 둔 것뿐이다.
                        if gate == .alreadyJoined {
                            PrimaryCtaButton(
                                text: "방으로 돌아가기",
                                onClick: { onOpenJoinedRide(ride) }
                            )
                        } else {
                            PrimaryCtaButton(
                                text: "이 탑승에 합류하기",
                                onClick: { onConfirmJoin(ride) }, // 성공 시 → 22 탑승 상세
                                // 모집 중이 아니거나 정원이 찬 방은 **눌러도 409 뿐**이다. 전에는 상태를
                                // 보지 않아 취소된 방에서도 활성이었고, 누른 뒤에야 사유를 알 수 있었다.
                                enabled: gate == .joinable,
                                loading: joining
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    NavigationBarSpacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MoyeotaColor.SurfaceCanvas)
                .clipShape(sheetShape)
                .sheetShadow(sheetShape)
                .padding(.top, JoinSheetTop)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
        // 기준 시각도 원본은 `remember` 라 23 동승자 프로필에 덮였다 돌아오면 다시 읽힌다 — 덮인 동안의
        // 낡은 기준이 남으면 자정을 넘긴 뒤에도 「내일 …」로 보여 출발일이 하루 밀린다. 처음 뜰 때도
        // 불리지만 init 직후의 값이다.
        .onAppear { now = Date() }
    }
}

// ─── 단계·CTA 판정 (순수 함수 — 화면 없이 테스트한다) ───────────────────────

/// `joinStatusBadge` 가 돌려주는 배지 하나. 색과 문구는 항상 짝지어 움직인다.
struct JoinStatusBadge: Equatable {
    var kind: NoticeKind
    var text: String
}

/// 방 단계(`RideStatus`) → 상태 배지.
///
/// enum 을 **포괄하지 않으면 컴파일되지 않는** `switch` 다 — 새 단계가 도메인에 생길 때 「모집 중」이
/// 조용히 남는 일을 막아 주는 것이 여기 분기를 다 적어 둔 이유다.
///
/// 20 은 모집 중인 방을 고르려고 여는 화면이라, 다른 단계는 모두 **들어갈 수 없는 방**이라는 뜻이다
/// (17 목록이 15초 주기라 고르는 사이에 바뀐다). 그래서 문구를 「… 방」으로 적었다 — 지금 내가 들어갈
/// 수 있는 상황이 아니라는 사실이 배지에서 읽혀야 한다.
func joinStatusBadge(status: RideStatus) -> JoinStatusBadge {
    switch status {
    case .recruiting: JoinStatusBadge(kind: .success, text: "모집 중")
    case .matched: JoinStatusBadge(kind: .waiting, text: "모집 마감된 방")
    case .completed: JoinStatusBadge(kind: .info, text: "합승이 끝난 방")
    case .canceled: JoinStatusBadge(kind: .error, text: "취소된 방")
    }
}

/// 20 의 배너·CTA 를 정하는 판정 결과 — `joinGate`.
enum JoinGate {
    /// 지금 합류할 수 있다
    case joinable

    /// 이미 내가 이 방의 멤버다 — 합류가 아니라 돌아갈 자리다
    case alreadyJoined

    /// 모집 중이 아닌 방(모집 마감·종료·취소)
    case notRecruiting

    /// 상태는 모집 중인데 자리가 없다
    case full
}

/// 지금 합류할 수 있는가 — 20 의 **단일 판정**이다(배지 문구만 `joinStatusBadge` 가 따로 맡는다).
///
/// 위에서부터 읽는다 — 앞의 조건이 뒤를 가린다.
///
/// | 판정 | 조건 | 이 순서인 이유 |
/// |---|---|---|
/// | `alreadyJoined` | `iAmMember` | 서버 목록은 **내 방을 빼지 않는다.** 17 은 이제 `exploreList` 로 걸러내지만, 목록이 낡았을 때·알림으로 20 에 바로 들어올 때는 여전히 닿는다 — **그 경우의 방어로 남긴다**(걸러내기가 사라져도 20 이 거짓을 말하지 않게 하는 안전망이다). 그때 「내가 N+1번째」는 거짓이고 합류를 시도해도 409 뿐이다 |
/// | `notRecruiting` | 상태가 모집 중이 아니다 | **정원 비교보다 앞**이다: 취소된 방은 멤버가 0명이라 정원만 보면 「자리 있음」으로 읽힌다 |
/// | `full` | 인원 ≥ 정원 | 상태는 아직 ACTIVE 인데 목록이 낡아 자리가 없는 경우(기존 동작 그대로) |
/// | `joinable` | 그 밖 | |
///
/// - Parameters:
///   - status: 방 상세의 단계(`Ride.status`)
///   - joinedCount: 방 상세의 멤버 수 — **나도 포함된 수**다
///   - capacity: 방 정원(방장 포함)
///   - iAmMember: 멤버 중 `User.isMe` 가 있는가
func joinGate(
    status: RideStatus,
    joinedCount: Int,
    capacity: Int,
    iAmMember: Bool
) -> JoinGate {
    if iAmMember { return .alreadyJoined }
    if status != .recruiting { return .notRecruiting }
    if joinedCount >= capacity { return .full }
    return .joinable
}

/// 막힌 이유 한 줄. `joinable` 이면 nil — 띄울 배너가 없다는 뜻이다.
///
/// 문구를 서버 실패 문구(`joinFailureMessage`)와 일부러 같은 말로 적었다 — 같은 사정을 **눈으로 보고
/// 막히는 것**과 **눌러서 알게 되는 것**이 다른 말로 보이면, 사용자는 사정이 두 가지 있는 줄로 읽는다.
func joinGateMessage(gate: JoinGate) -> String? {
    switch gate {
    case .joinable: nil
    case .alreadyJoined: "이미 참여 중인 방이에요"
    case .notRecruiting: "모집이 끝난 방이에요. 목록에서 다른 동승을 선택해 주세요"
    case .full: "방금 인원이 찼어요. 목록에서 다른 동승을 선택해 주세요"
    }
}

/// 상태 행의 인원 문구.
///
/// 「내가 N번째」는 **내가 아직 멤버가 아닐 때만** 쓴다. `joinedCount` 는 방 상세의 멤버 수라 **나를
/// 포함**하므로, 내 방을 열었을 때도 +1 을 더하면 「1명 참여 · 목표 3명 · 내가 2번째」처럼 한 칸 밀린
/// 거짓이 된다(실제로는 내가 1번째다). 그 경우에는 순서를 고쳐 쓰지 않고 **이미 들어와 있다는 사실**만
/// 쓴다 — 「내가 1번째」로 바꿔 쓰면 지금 새로 합류하는 것처럼 읽힌다.
func joinHeadcountLine(joinedCount: Int, capacity: Int, iAmMember: Bool) -> String {
    let base = "\(joinedCount)명 참여 · 목표 \(capacity)명"
    return iAmMember ? "\(base) · 이미 참여 중" : "\(base) · 내가 \(joinedCount + 1)번째"
}

/// 요금 카드가 그릴 두 금액. 하나라도 알 때만 만들어지고, 모르면 아예 없다(`joinFareOrNull`).
struct JoinFare: Equatable {
    var totalFare: Int
    var farePerPerson: Int
}

/// 요금을 **말할 수 있는 방인가** — 말할 수 없으면 nil 이고 호출부가 카드를 그리지 않는다.
///
/// ### 왜 필요해졌나 — 예약 방이 「0원」이었다 ★
/// 서버는 예약 방(`POST /matching/reservations`)에 **요금·경로·소요 시간을 넣지 않는다.** 도메인
/// `Ride.totalFare`·`Ride.farePerPerson` 은 옵셔널이 아닌 `Int` 라 그 방은 0 으로 와서, 이 화면이
/// 「총 예상 요금 0원」·「합류 시 1인 부담 0원」을 **금액으로** 그렸다. 0원은 「모른다」가 아니라
/// **「공짜로 탄다」**로 읽히고, 그건 합류 직전에 보여 주는 가장 나쁜 거짓이다.
///
/// 0 을 「모른다」로 읽는 것은 이 저장소의 기존 관례다(`headcountLabel` 의 `joined <= 0`,
/// `RideHistoryDisplay.fareOrNull` 의 둘 다 nil). 실제로 0원인 택시 요금은 없으므로 이 판정이
/// 참값을 가리는 경우도 없다.
///
/// 한쪽만 아는 응답은 실측에서 본 적이 없지만(서버가 같은 값에서 둘을 만든다) **있는 쪽만** 그리지
/// 않고 둘 다 그린다 — 0 쪽은 어차피 「모른다」라서, 둘 중 하나라도 알면 카드를 세우고 모르는 칸은
/// 0원으로 보이는 것보다 서버가 준 값을 그대로 보여 주는 편이 낫다(그 조합은 지금 오지 않는다).
func joinFareOrNull(totalFare: Int, farePerPerson: Int) -> JoinFare? {
    totalFare <= 0 && farePerPerson <= 0 ? nil : JoinFare(totalFare: totalFare, farePerPerson: farePerPerson)
}

/// 요금 카드가 있던 자리의 한 줄 — **자리를 비워 두지 않는다**(빈 자리는 로딩 실패로 읽힌다).
///
/// 예약 방은 **왜 없는지**를 말할 수 있다(서버가 그 방에 요금을 넣지 않는다). 실시간 방에서 요금이
/// 0 인 경우는 사유를 모르므로 **모른다고만** 한다 — 「예약이라서」라고 쓰면 틀린 설명이 된다.
/// 16 도착지 확인이 예약 모드에서 쓰는 문구와 **같은 사실**을 말하지만 문장이 다른 이유는 그쪽은
/// 만들기 전(요금이 생기지 않을 것이다)이고 이쪽은 만들어진 뒤(그 방에 요금이 없다)이기 때문이다.
func joinFareAbsentNotice(roomType: RoomType) -> String {
    switch roomType {
    case .reservation: "예약 방은 예상 요금이 없어요. 요금은 탈 때 미터기로 정해져요"
    case .realtime: "예상 요금을 받지 못했어요"
    }
}

/// 20 합류 확인의 출발 표기 — **예약 방일 때만** 약속 시각에서 만든다. 실시간 방은 nil 이고
/// 호출부가 서버 `departureLabel` 을 그대로 쓴다(그 라벨에는 거리가 함께 들어 있다).
///
/// 예약에서 이 줄이 비면 사용자는 **언제 출발하는지 모르고 합류**한다 — 사흘 뒤 오전 9시 방에
/// 들어가는 일인데 목록에서 본 시각이 이 화면에는 없게 된다. 서버 `departureLabel` 을 믿지 않는
/// 이유: 그 값은 목록·상세 응답에 따라 비어 올 수 있고, 약속 시각(`departureAt`)이 **원본**이다.
///
/// 읽을 수 없으면 nil 이다 — 「시간 미정」 같은 자리값을 두면 확정된 방을 미정으로 보여 준다.
func joinDepartureLabel(ride: Ride, now: Date) -> String? {
    guard ride.roomType == .reservation else { return nil }
    return reservationDepartureLabel(departureAt: ride.departureAt, now: now).map { "\($0) 출발" }
}

// ─── 조각 ───────────────────────────────────────────────────────────────────

private struct MemberRow: View {
    let member: User
    let othersCount: Int
    let onClick: () -> Void

    var body: some View {
        // 탈퇴 회원은 열어 볼 프로필이 없다 — 탭을 막는다
        if member.isWithdrawn {
            content(clickable: false)
        } else {
            Button(action: onClick) {
                content(clickable: true)
            }
            .buttonStyle(PressOverlayStyle(shape: MoyeotaShape.Card))
        }
    }

    private func content(clickable: Bool) -> some View {
        // 매너 %(별점 환산)는 지웠다 — 평가 API 가 없어 rating 은 항상 0.0 이고,
        // 그걸 환산하면 "매너 0%" 라는 없는 사실을 사람에 붙이게 된다.
        let othersLabel = othersCount > 0 ? " · 외 \(othersCount)명" : ""
        return HStack(spacing: 0) {
            MemberAvatar(user: member, size: 40)
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(member.displayNickname)
                        .moyeotaText(
                            MoyeotaType.BodyStrong.hangulTrimmed,
                            color: clickable ? MoyeotaColor.InkPrimary : MoyeotaColor.TextMute
                        )
                    Spacer().frame(width: 8)
                    Group {
                        if member.isMe {
                            MeBadge()
                        } else {
                            PartnerBadge()
                        }
                    }
                    .fixedSize()
                }
                Text(clickable ? "\(member.rideCountLabel)\(othersLabel)" : "탈퇴한 회원\(othersLabel)")
                    .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if clickable {
                ChevronIcon()
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }
}

/// 「동승자」 — 옆에 서는 「나」(`MeBadge`)·「방장」 배지와 **같은 크기**(CaptionSm 세미볼드 · 8/2)로 둔다.
/// 예전엔 옅은 파란 바탕에 11 Bold 로 혼자 컸다. 사실을 붙이는 것이라 회색이다.
private struct PartnerBadge: View {
    var body: some View {
        Text("동승자")
            .moyeotaText(MoyeotaType.CaptionSm.copy(fontWeight: .semibold).hangulTrimmed, color: MoyeotaColor.TextBody)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(MoyeotaColor.SurfaceSoft, in: Capsule(style: .circular))
    }
}
