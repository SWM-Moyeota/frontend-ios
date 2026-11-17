import MoyeotaDomain

// 택시비 정산(39)으로 들어가는 **진입 판정** — 원본 `FareSplitDisplay.kt` 의 「진입 판정」 절.
//
// 원본은 정산 표시 규칙 파일 하나에 둔다. 여기로 옮긴 이유는 모듈 경계 하나뿐이다: 22 탑승 상세(FeatureMatching)가
// 이 판정으로 버튼을 그리는데 기능 모듈끼리는 서로 import 하지 않는다(`Package.swift` 의 기능 모듈은
// PresentationCore·디자인시스템만 본다). 정산 모듈(FeatureFareSplit)도 같은 함수를 쓴다 — 두 곳이 같은 판정을
// 각자 들면 「버튼은 떴는데 상세가 403」인 화면이 생긴다.

/// 이 방에서 **정산 화면으로 갈 수 있는가** — 끝난 방 + 내가 탑승자(= 도착을 눌렀다).
///
/// ### 「방 멤버」가 아니라 「탑승자」다 ★
/// 도착을 누르지 않은 사람은 서버 `riderIds` 에 없어 정산의 당사자가 아니고, 상세를 열면 403
/// `NOT_FARE_SPLIT_PARTICIPANT` 다(`Ride.fareSplitRiders`). 멤버 전원에게 진입점을 띄우면 그 사람들은
/// **열 수 없는 화면으로 가는 버튼**을 보게 된다.
///
/// 「정산이 실제로 있는가」는 **묻지 않는다** — 그건 GET 을 해 봐야 알고(404 = 아직 없다), 그 판정은
/// 상세 화면이 한다(`FareSplitDetailRoute`). 진입점에서 미리 조회하면 끝난 방 카드마다 요청이 하나씩 붙는다.
public func canOpenFareSplit(ride: Ride) -> Bool {
    ride.status == .completed && ride.fareSplitRiders.contains(where: \.isMe)
}

/// 진입점에 적을 글자. 갈 수 없으면 nil 이다 — **버튼을 그리지 않는다.**
///
/// 방장과 그 밖을 가르는 이유: 방장이 누를 버튼은 **만드는** 버튼이고(없으면 시작 화면이 열린다)
/// 나머지가 누를 버튼은 **보는** 버튼이다(없으면 「아직 시작되지 않았다」가 뜬다). 같은 글자를 쓰면
/// 한쪽이 거짓이 된다.
public func fareSplitEntryLabel(ride: Ride) -> String? {
    guard canOpenFareSplit(ride: ride) else { return nil }
    return ride.isHostedByMe ? "택시비 정산하기" : "내 택시비 보내기"
}
