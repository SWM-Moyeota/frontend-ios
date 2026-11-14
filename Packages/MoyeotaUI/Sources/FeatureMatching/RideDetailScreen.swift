import Foundation
import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

/// 22 · 탑승 상세 — 모집 중 [S12]
///
/// 이동(디스크립션):
/// - 뒤로 → 21 매칭 대기 (onBack)
/// - 동승자 행 탭 → 23 동승자 프로필 (onPartnerClick)
/// - 「나가기」 → 14 홈, 탑승 이탈 (onLeave). **모집 중(`RideStatus.recruiting`)일 때만 보인다.**
///   그 밖의 단계에서는 버튼 대신 지금 어떤 방인지를 한 줄로 적는다(`stageNotice`).
///
///   ⚠️ 서버는 정원이 찬 방(`RideStatus.matched` = 서버 COMPLETED)에서도 나가기를 **허용한다**
///   (`ensureRecruiting()` 이 ACTIVE·COMPLETED 를 통과시킨다) — 21 매칭 대기는 거기서 「방 나가기」를
///   보여 준다(`canLeaveParty`). 이 화면만 RECRUITING 으로 좁혀 둔 것은 기사 모드 시절의 기준이 남은
///   것이고, 지금은 두 화면이 같은 방에 대해 다른 말을 한다. 의도된 차이가 아니므로 둘 중 하나로
///   모아야 한다 — 다만 그건 문구 정리가 아니라 **동작 변경**이라 이 작업(택시 코드 제거)에서 하지 않았다.
/// - [미연결] 없음
///
/// 도메인 변경(2026-08-30 → 현재): 백엔드에서 **수동 출발**이 사라졌다 — 「이 인원으로 출발」이라는
/// 행위 자체가 없어져 CTA 를 제거했고, 21 매칭 대기와 같은 결정이다. 그 뒤 기사·배차까지 걷어내면서
/// **이 화면이 넘길 다음 화면은 아예 없어졌다**(25 배차 현황·26 운행 중 삭제). 여기서 나가는 길은
/// 뒤로(21) · 동승자 프로필(23) · 나가기(14 홈) 셋이다.
///
/// 방장 표시(2026-10-15): 그때 함께 지웠던 방장 배지는 **되살렸다** — 근거가 달라졌다. 그때는
/// 서버에 방장 개념이 없어 앱이 `joinedAt` 최소값으로 추정하던 것이었고, 지금은 서버가 멤버마다
/// `host` 를 내려 준다(Backend #240). 21 매칭 대기와 **같은 배지·같은 판정**을 쓴다
/// (`User.showsHostBadge`) — 조건 카드 한 번 탭으로 오가는 두 화면에서
/// 같은 사람이 달라 보이면 안 된다. 이 화면은 방장 **전용 동작**은 갖지 않는다(「합승 완료」는 21 에 있다).
///
/// 서버 계약(2026-09): 멤버가 publicId·nickname·rideCount 를 함께 준다. 「나」 판정은 `User.isMe`
/// 하나로 끝난다 — 예전에는 앱이 자기 내부 Long id 를 몰라 고정값 1 과 비교하던 자리였다.
/// 평가 API 는 아직 없어 그 줄은 표시하지 않는다.
///
/// 안내 문구(2026-10-13 → 현재): 정원이 찬 뒤 무슨 일이 일어나는지를 한 줄로 적는다. 한동안 이 줄이
/// 모드(`taxiEnabled`)에 따라 네 갈래로 갈렸는데, 기사·배차를 걷어내면서 **갈릴 것이 없어졌다** —
/// 기사는 오지 않고, 정원이 차면 채팅으로 만날 곳을 정한다. 21 매칭 대기의 안내 배너와 **같은 말**을
/// 써야 한다(조건 카드 한 번 탭으로 오가는 두 화면이다).
///
/// 서버가 주지 않는 값(성별 조건·도착 시각·서비스 요금)은 지어내지 않고 요소를 두지 않는다.
/// 출발 표기는 `Ride.departureLabel` 이 있을 때만, 도착 쪽은 `Ride.estimatedMinutes` 가 있을 때만
/// 「약 N분」으로 보이고, 1인 부담은 서버 매핑 값 `Ride.farePerPerson` 을 그대로 쓴다.
public struct RideDetailScreen: View {
    private let ride: Ride
    private let pickupDistanceMeters: Double?
    private let onBack: () -> Void
    private let onPartnerClick: (User) -> Void
    private let onLeave: () -> Void

    @State private var routeMemo = Remembered<String?, [LatLng]>()

    /// - Parameters:
    ///   - pickupDistanceMeters: 내 위치 → 탑승 위치 거리(m). 모르면 nil 이고 그 줄을 감춘다
    public init(
        ride: Ride,
        pickupDistanceMeters: Double? = nil,
        onBack: @escaping () -> Void = {},
        onPartnerClick: @escaping (User) -> Void = { _ in },
        onLeave: @escaping () -> Void = {}
    ) {
        self.ride = ride
        self.pickupDistanceMeters = pickupDistanceMeters
        self.onBack = onBack
        self.onPartnerClick = onPartnerClick
        self.onLeave = onLeave
    }

    public var body: some View {
        // 지도 값 — 방 상세에서 나온다. 못 쓸 좌표면 latLngOrNull 이 nil 을 돌려 자리표시자로 떨어진다
        let originPosition = latLngOrNull(latitude: ride.originLat, longitude: ride.originLng)
        let destinationPosition = latLngOrNull(latitude: ride.destinationLat, longitude: ride.destinationLng)
        let routePath = routeMemo.value(key: ride.routePolyline) {
            ride.routePolyline.map { decodePolyline(encoded: $0) } ?? []
        }
        let routeMeters = polylineDistanceMeters(points: routePath)
        let routeKm = routeMeters > 0.0 ? routeMeters / 1000.0 : nil
        let etaLabel = buildRouteChipLabel(estimatedMinutes: ride.estimatedMinutes, routeKm: routeKm)

        let partners = ride.members.filter { !$0.isMe }
        let departureLabel = ride.departureLabel.isBlank ? nil : ride.departureLabel
        let durationLabel = ride.estimatedMinutes.map { "약 \($0)분" }

        VStack(spacing: 0) {
            // 상단 헤더 — 하위 화면 공용 앱바(디자인 QA G7·J3, 가운데 제목 18/600)
            StatusBarSpacer()
            MoyeotaTopBar(title: "탑승 상세", onBack: onBack)

            // 지도 + 예상 시간 칩 — 16·20 과 같은 실지도 스트립(높이만 이 화면에 맞춘다)
            ZStack(alignment: .topLeading) {
                RouteStripMap(
                    originPosition: originPosition,
                    destinationPosition: destinationPosition,
                    routePath: routePath
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 지도 위 공용 흰 알약 — 20 합류 확인의 소요 시간 칩과 같은 모양·그림자
                if let etaLabel {
                    MapOverlayPill {
                        Text(etaLabel)
                            .moyeotaText(
                                MoyeotaType.BodySm.copy(fontWeight: .semibold).hangulTrimmed,
                                color: MoyeotaColor.InkPrimary
                            )
                    }
                    .padding(.leading, 16)
                    .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)

            // 바텀시트 — 모서리 20 · 그림자 8(디자인 QA G3·G4, 모든 시트 공통)
            VStack(spacing: 0) {
                SheetHandle()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 12)

                        // 상태 배지 행
                        HStack(spacing: 0) {
                            StatusBadge(kind: .success, text: "모집 중")
                                .fixedSize()
                            Spacer().frame(width: 8)
                            Text("\(ride.members.count)명 참여 · 목표 \(ride.capacity)명")
                                .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Spacer().frame(height: 16)

                        // Group A · 경로 / Group B · 요금 — **판 없이** 시트 위에 바로 놓는다(디자인 QA J1). 예전엔 옅은 파란
                        // 판(경로) + 회색 판 안의 파란 판(1인 부담, 19 파란 숫자)이 겹친 "카드 더미"였다.
                        // 20 합류 확인과 같은 공용 조각이다 — 한 번 탭으로 오가는 두 화면이 같은 모양으로 읽힌다.
                        RouteSummary(
                            origin: ride.origin,
                            destination: ride.destination,
                            originMeta: departureLabel,
                            destinationMeta: durationLabel,
                            // 내 위치를 모르면 이 줄은 비운다 — 보행 시간 같은 지어낸 값을 채우지 않는다
                            connectorNote: pickupDistanceMeters.map { "내 위치에서 \(pickupDistanceLabel(meters: $0))" }
                        )
                        Spacer().frame(height: 16)
                        FareSummary(
                            total: wonLabel(amount: ride.totalFare),
                            perPerson: wonLabel(amount: ride.farePerPerson),
                            capacity: ride.capacity
                        )
                        Spacer().frame(height: MoyeotaSpacing.SectionGap)

                        // 함께 타는 사람
                        SectionLabel(text: "함께 타는 사람 · \(partners.count)명")
                        // 나까지 포함해 전원을 보여준다 — 위 개수는 나를 뺀 값이라 목록에 내 줄이 없으면
                        // "나는 이 방에 있나"를 확인할 곳이 사라진다. 대신 내 줄은 배지로 구분하고 탭을 막는다.
                        // 빈 id 멤버가 겹칠 수 있어(요약 없음) id 가 아니라 자리로 구별한다 — 원본 forEach 도 키가 없다.
                        ForEach(Array(ride.members.enumerated()), id: \.offset) { _, member in
                            DetailMemberRow(member: member, onClick: { onPartnerClick(member) })
                        }
                        Spacer().frame(height: 16)

                        // 정원이 찬 뒤 무슨 일이 일어나는지 (21 매칭 대기의 안내 배너와 **짝인 문구**) —
                        // 한쪽만 고치면 조건 카드 한 번 탭으로 오가는 두 화면이 다른 말을 한다.
                        Text(rideDetailNotice(isFull: ride.members.count >= ride.capacity))
                            .moyeotaText(MoyeotaType.CaptionMd.hangulTrimmed, color: MoyeotaColor.TextMute)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Spacer().frame(height: 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity)

                // 남은 액션은 나가기 하나뿐 — 수동 출발 버튼은 도메인에서 사라졌다.
                // 매칭이 시작된 뒤에는 서버가 나가기를 막으므로 버튼 대신 현재 단계를 적는다.
                //
                // 바탕 없는 빨간 글자 알약이다(디자인 QA G5·J3, 디자인 문서 button-danger) — 예전 회색 r16 상자는
                // 앱의 다른 버튼과 모양이 달랐고, 회색은 「방에서 빠진다」는 무게를 말하지 못했다.
                if ride.status == .recruiting {
                    DangerTextButton(text: "나가기", onClick: onLeave)
                        .padding(.horizontal, 16)
                } else {
                    Text(stageNotice(status: ride.status))
                        .moyeotaText(MoyeotaType.BodySm.hangulTrimmed, color: MoyeotaColor.TextMute)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                }
                Spacer().frame(height: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MoyeotaColor.SurfaceCanvas)
            .clipShape(MoyeotaShape.Sheet)
            .sheetShadow(MoyeotaShape.Sheet)

            NavigationBarSpacer()
                .frame(maxWidth: .infinity)
                .background(MoyeotaColor.SurfaceCanvas)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoyeotaColor.SurfaceCanvas)
    }
}

private struct DetailMemberRow: View {
    let member: User
    let onClick: () -> Void

    var body: some View {
        // 탈퇴 회원과 나는 열어 볼 프로필이 없어 탭을 막는다.
        if !member.isMe && !member.isWithdrawn {
            Button(action: onClick) {
                content(clickable: true)
            }
            .buttonStyle(PressOverlayStyle(shape: MoyeotaShape.Card))
        } else {
            content(clickable: false)
        }
    }

    private func content(clickable: Bool) -> some View {
        HStack(spacing: 0) {
            MemberAvatar(user: member, size: 40)
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(member.displayNickname)
                        .moyeotaText(
                            MoyeotaType.BodyStrong.hangulTrimmed,
                            color: member.isWithdrawn ? MoyeotaColor.TextMute : MoyeotaColor.InkPrimary
                        )
                    if member.isMe {
                        Spacer().frame(width: 6)
                        MeBadge()
                            .fixedSize()
                    }
                    // 「방장」 — 21 매칭 대기와 같은 판정. 서버가 멤버마다 내려 주는
                    // 값이고(추정이 아니다), 폴백 때문에 내 줄에는 붙지 않는다.
                    if member.showsHostBadge {
                        Spacer().frame(width: 6)
                        HostBadge()
                            .fixedSize()
                    }
                }
                // 평가 수치는 평가 API 가 생길 때까지 쓰지 않는다 — 없는 수치를 지어내면
                // 사용자가 그걸 근거로 사람을 고른다
                // 21 멤버 줄과 같은 이유로 숫자 폭을 고정한다
                Text(member.isWithdrawn ? "탈퇴한 회원" : member.rideCountLabel)
                    .moyeotaText(MoyeotaType.BodySm.tabularNums().hangulTrimmed, color: MoyeotaColor.TextMute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if clickable {
                ChevronIcon()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }
}

/// 원본 `"%,d원".format(amount)` — 천 단위 구분은 원본처럼 기기 로케일을 따른다.
func wonLabel(amount: Int, locale: Locale = .current) -> String {
    "\(amount.formatted(.number.locale(locale).grouping(.automatic)))원"
}

/// 정원 안내 문구 — 21 의 안내 배너와 짝이다.
func rideDetailNotice(isFull: Bool) -> String {
    if isFull { return "같이 탈 사람이 다 모였어요. 채팅으로 만날 곳을 정해요" }
    return "정원이 차면 채팅으로 만날 곳을 정해요"
}

/// 나가기 버튼 자리에 대신 적는 현재 단계.
///
/// 「왜 나갈 수 없는지」를 사용자가 알 수 있어야 한다 — 버튼만 사라지면 앱이 고장 난 것처럼 보인다.
///
/// 기사·배차를 걷어내면서 `DISPATCHING`(「기사님을 찾는 중이라 나갈 수 없어요」)·`ONGOING`
/// (「운행 중이에요」) 두 줄이 사라졌다 — 서버가 그 status 를 보낼 수 없다.
///
/// `RideStatus.matched` 는 **「나갈 수 없다」고 말하지 않는다.** 서버는 정원이 찬 방에서도 나가기를
/// 허용하고(`ensureRecruiting` = ACTIVE·COMPLETED), 21 매칭 대기가 실제로 그 버튼을 띄운다 — 여기서
/// 못 나간다고 적으면 거짓이 된다. 이 화면이 그 길을 갖지 않는 것은 사실이므로, 그 사실만 적어
/// **나갈 수 있는 곳을 가리킨다**(이 화면은 21 의 조건 카드에서 한 번 탭으로 들어온 자리라
/// 「매칭 대기 화면」은 뒤로 한 번이다).
///
/// `switch` 에 `default` 를 두지 않는다 — 단계가 늘면 여기서 컴파일이 막혀야 한다. RECRUITING 은
/// 버튼이 보이는 경로라 호출부가 부르지 않지만, 분기를 빼면 그 보장을 잃으므로 함께 적어 둔다.
func stageNotice(status: RideStatus) -> String {
    switch status {
    case .matched: "정원이 다 찼어요. 나가려면 매칭 대기 화면에서 「방 나가기」를 눌러 주세요"
    case .canceled: "취소된 탑승이에요"
    case .completed: "완료된 탑승이에요"
    // 호출부가 RECRUITING 에서는 나가기 버튼을 그리므로 여기 오지 않는다
    case .recruiting: "지금은 나갈 수 없어요"
    }
}
