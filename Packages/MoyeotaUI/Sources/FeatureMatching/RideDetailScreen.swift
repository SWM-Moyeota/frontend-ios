import Foundation
import MoyeotaDesignSystem
import MoyeotaDomain
import PresentationCore
import SwiftUI

// 와이어프레임 그레이 (core token 미정의 색 — 화면 재현용)
private let CanvasBg = Color(argb: 0xFFF5F7FA)
private let GraySlate = Color(argb: 0xFF4B5563)
private let GrayMute = Color(argb: 0xFF8A93A0)
private let GrayAsh = Color(argb: 0xFF9AA1AC)
private let ChipBg = Color(argb: 0xFFF1F5FD)
private let CardSoft = Color(argb: 0xFFF6F8FB)
private let GrayButtonBg = Color(argb: 0xFFEEF1F6)
private let DashGray = Color(argb: 0xFFB9C3D6)

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
        let sheetShape = UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .circular)

        VStack(spacing: 0) {
            // 상단 흰색 헤더
            VStack(spacing: 0) {
                StatusBarSpacer()
                HStack(spacing: 0) {
                    MatchingBackButton(onBack: onBack)
                    Text("탑승 상세")
                        .moyeotaText(inlineType(18, .bold), color: MoyeotaColor.InkPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .background(MoyeotaColor.SurfaceCanvas)

            // 지도 + 예상 시간 칩 — 16·20 과 같은 실지도 스트립(높이만 이 화면에 맞춘다)
            ZStack(alignment: .topLeading) {
                RouteStripMap(
                    originPosition: originPosition,
                    destinationPosition: destinationPosition,
                    routePath: routePath
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let etaLabel {
                    Text(etaLabel)
                        .moyeotaText(inlineType(13, .bold), color: MoyeotaColor.InkPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(MoyeotaColor.SurfaceCanvas, in: Capsule(style: .circular))
                        .moyeotaShadow(elevation: 4, shape: Capsule(style: .circular), spotColor: Color(argb: 0x141B2A4A))
                        .padding(.leading, 16)
                        .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)

            // 바텀시트
            VStack(spacing: 0) {
                SheetHandle()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 10)

                        // 상태 배지 행
                        HStack(spacing: 0) {
                            StatusBadge(kind: .success, text: "모집 중")
                                .fixedSize()
                            Spacer().frame(width: 10)
                            Text("\(ride.members.count)명 참여 · 목표 \(ride.capacity)명")
                                .moyeotaText(inlineType(13, .medium), color: GrayMute)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Spacer().frame(height: 16)

                        // Group A · 경로
                        RouteCard(
                            origin: ride.origin,
                            destination: ride.destination,
                            departureLabel: departureLabel,
                            pickupDistanceMeters: pickupDistanceMeters,
                            durationLabel: durationLabel
                        )
                        Spacer().frame(height: 16)

                        // Group B · 요금
                        FareCard(ride: ride)
                        Spacer().frame(height: 14)

                        // 함께 타는 사람
                        Text("함께 타는 사람 · \(partners.count)명")
                            .moyeotaText(inlineType(13, .medium), color: GrayMute)
                        Spacer().frame(height: 8)
                        // 나까지 포함해 전원을 보여준다 — 위 개수는 나를 뺀 값이라 목록에 내 줄이 없으면
                        // "나는 이 방에 있나"를 확인할 곳이 사라진다. 대신 내 줄은 배지로 구분하고 탭을 막는다.
                        // 빈 id 멤버가 겹칠 수 있어(요약 없음) id 가 아니라 자리로 구별한다 — 원본 forEach 도 키가 없다.
                        ForEach(Array(ride.members.enumerated()), id: \.offset) { _, member in
                            DetailMemberRow(member: member, onClick: { onPartnerClick(member) })
                        }
                        Spacer().frame(height: 14)

                        // 정원이 찬 뒤 무슨 일이 일어나는지 (21 매칭 대기의 안내 배너와 **짝인 문구**) —
                        // 한쪽만 고치면 조건 카드 한 번 탭으로 오가는 두 화면이 다른 말을 한다.
                        Text(rideDetailNotice(isFull: ride.members.count >= ride.capacity))
                            .moyeotaText(inlineType(12, .medium), color: GrayAsh)
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
                if ride.status == .recruiting {
                    GrayActionButton(text: "나가기", onClick: onLeave)
                        .padding(.horizontal, 16)
                } else {
                    Text(stageNotice(status: ride.status))
                        .moyeotaText(inlineType(13, .medium), color: GrayMute)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                }
                Spacer().frame(height: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MoyeotaColor.SurfaceCanvas)
            .clipShape(sheetShape)
            .moyeotaShadow(elevation: 14, shape: sheetShape, spotColor: Color(argb: 0x141B2A4A))

            NavigationBarSpacer()
                .frame(maxWidth: .infinity)
                .background(MoyeotaColor.SurfaceCanvas)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBg)
    }
}

private struct RouteCard: View {
    let origin: String
    let destination: String
    let departureLabel: String?
    let pickupDistanceMeters: Double?
    let durationLabel: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Spacer().frame(height: 5)
                Circle()
                    .fill(MoyeotaColor.MarkerOrigin)
                    .frame(width: 11, height: 11)
                DashedRouteLine()
                    .padding(.vertical, 3)
                Circle()
                    .fill(MoyeotaColor.MarkerDestination)
                    .frame(width: 11, height: 11)
            }
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(origin)
                        .moyeotaText(inlineType(15, .bold), color: MoyeotaColor.InkPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let departureLabel {
                        Text(departureLabel)
                            .moyeotaText(inlineType(15, .bold), color: MoyeotaColor.InkPrimary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                // 내 위치를 모르면 이 줄은 비운다 — 보행 시간 같은 지어낸 값을 채우지 않는다
                if let pickupDistanceMeters {
                    Text("내 위치에서 \(pickupDistanceLabel(meters: pickupDistanceMeters))")
                        .moyeotaText(inlineType(12, .medium), color: GrayMute)
                }
                Spacer().frame(height: 12)
                HStack(spacing: 0) {
                    Text(destination)
                        .moyeotaText(inlineType(15, .bold), color: MoyeotaColor.InkPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let durationLabel {
                        Text(durationLabel)
                            .moyeotaText(inlineType(15, .bold), color: MoyeotaColor.InkPrimary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(ChipBg, in: RoundedRectangle(cornerRadius: 16, style: .circular))
    }
}

private struct FareCard: View {
    let ride: Ride

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FareRow(label: "총 예상 요금", value: wonLabel(amount: ride.totalFare))
            Spacer().frame(height: 14)
            HStack(spacing: 0) {
                Text("1인 부담")
                    .moyeotaText(inlineType(15, .bold), color: MoyeotaColor.Primary600)
                Spacer(minLength: 0)
                Text(wonLabel(amount: ride.farePerPerson))
                    .moyeotaText(inlineType(19, .bold), color: MoyeotaColor.Primary500)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(MoyeotaColor.Primary50, in: RoundedRectangle(cornerRadius: 14, style: .circular))
            Spacer().frame(height: 6)
            HStack(spacing: 0) {
                CheckSmallIcon(tint: MoyeotaColor.Success500)
                Spacer().frame(width: 5)
                Text("총 예상 요금을 정원 \(ride.capacity)명으로 나눈 금액이에요")
                    .moyeotaText(inlineType(12, .medium), color: GrayMute)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(CardSoft, in: RoundedRectangle(cornerRadius: 16, style: .circular))
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
            .buttonStyle(PressOverlayStyle(shape: RoundedRectangle(cornerRadius: 12, style: .circular)))
        } else {
            content(clickable: false)
        }
    }

    private func content(clickable: Bool) -> some View {
        HStack(spacing: 0) {
            MemberAvatar(user: member, size: 40)
            Spacer().frame(width: 10)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(member.displayNickname)
                        .moyeotaText(
                            inlineType(15, .bold),
                            color: member.isWithdrawn ? GrayMute : MoyeotaColor.InkPrimary
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
                    .monospacedDigit()
                    .moyeotaText(inlineType(13, .medium), color: GrayMute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if clickable {
                ChevronRightIcon()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }
}

private struct FareRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .moyeotaText(inlineType(15, .medium), color: MoyeotaColor.TextMute)
            Spacer(minLength: 0)
            Text(value)
                .moyeotaText(inlineType(15, .bold), color: MoyeotaColor.InkPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 원본 `"%,d원".format(amount)` — 천 단위 구분은 원본처럼 기기 로케일을 따른다.
func wonLabel(amount: Int, locale: Locale = .current) -> String {
    "\(amount.formatted(.number.locale(locale).grouping(.automatic)))원"
}

/// 원본의 점선 간격 `5f, 7f` 는 dp 가 아니라 **픽셀**이다. 기준 기기(2.625배)의 물리 길이로 옮긴다.
/// 같은 픽셀 수를 3배 화면에 그리면 주기가 4.57 에서 4.0 으로 줄어 같은 높이에 점이 하나 더 들어간다.
///
/// 둥근 끝은 위아래로 굵기 절반씩 칸을 벗어나는데 Compose `Canvas` 는 넘쳐 그리고 SwiftUI `Canvas` 는
/// 잘라 내므로, 그만큼 큰 캔버스에 그리고 레이아웃은 24 로 둔다(원본 높이 30 − 위아래 여백 3).
private struct DashedRouteLine: View {
    private static let width: CGFloat = 3
    private static let height: CGFloat = 24
    private static let lineWidth: CGFloat = 2

    private static let on: CGFloat = 5 / 2.625
    private static let off: CGFloat = 7 / 2.625

    var body: some View {
        Canvas { context, size in
            let overflow = Self.lineWidth / 2
            var path = Path()
            path.move(to: CGPoint(x: size.width / 2, y: overflow))
            path.addLine(to: CGPoint(x: size.width / 2, y: overflow + Self.height))
            context.stroke(
                path,
                with: .color(DashGray),
                style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, dash: [Self.on, Self.off])
            )
        }
        .frame(width: Self.width, height: Self.height + Self.lineWidth)
        .frame(width: Self.width, height: Self.height)
    }
}

// ─── 아이콘 (머티리얼 아이콘 미사용 — Canvas 직접 드로잉) ─────────────────────

private struct CheckSmallIcon: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: w * 0.12, y: h * 0.55))
            path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.82))
            path.move(to: CGPoint(x: w * 0.42, y: h * 0.82))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.2))
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        .frame(width: 14, height: 14)
    }
}

private struct ChevronRightIcon: View {
    var tint: Color = GrayAsh

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: w * 0.38, y: h * 0.24))
            path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.5))
            path.move(to: CGPoint(x: w * 0.38, y: h * 0.76))
            path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.5))
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 18, height: 18)
    }
}

// 와이어프레임의 회색 보조 버튼 (나가기)
private struct GrayActionButton: View {
    let text: String
    let onClick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        Button(action: onClick) {
            Text(text)
                .moyeotaText(inlineType(15, .bold), color: GraySlate)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(GrayButtonBg, in: shape)
        }
        .buttonStyle(PressOverlayStyle(shape: shape))
    }
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

/// 머티리얼 `IconButton` 자리 — 레이아웃 크기는 최소 터치 영역인 48dp 다.
struct MatchingBackButton: View {
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            BackArrowIcon()
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(IconPressStyle())
    }
}
