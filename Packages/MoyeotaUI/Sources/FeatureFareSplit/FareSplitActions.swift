import Foundation
import PresentationCore
import UIKit

// 정산 화면이 **앱 밖으로 나가는** 두 가지 — 토스 송금과 클립보드 복사.
//
// 화면이 아니라 여기 모아 둔 이유는 `ExternalIntents.swift` 와 같다: 받아 줄 앱이 없으면 열기가 실패하고,
// 그 처리를 행마다 되풀이하면 한 곳만 빠뜨려도 눌러도 아무 일이 없는 버튼이 생긴다.
// 다만 **같은 파일에 두지는 않았다** — 그쪽은 실패를 토스트로 삼키고 끝내는데, 이쪽의 실패는
// 화면이 **다음 길을 가리켜야 하는** 사실이라 호출부로 돌려줘야 한다(`TOSS_OPEN_FAILED_NOTICE`).
//
// ### 로그를 한 줄도 남기지 않는다 ★
// 두 함수가 다루는 값은 **계좌번호와 송금 딥링크**다(딥링크 쿼리에 `accountNo` 가 그대로 들어 있다).
// 실패를 디버깅하려고 `print(deeplink)` 를 한 줄 넣으면 그 계좌번호가 콘솔·기기 로그로 새어 나가고,
// 서버는 같은 값을 **암호화해 저장하며 정산이 끝나면 지운다.** 서버가 지키는 것을 앱이 흘리면
// 그 보호가 무의미해진다. 그래서 여기서는 성공/실패 불리언만 돌려주고, 무엇이 실패했는지는
// 화면이 자기 문맥으로 말한다. (그 값을 든 모델의 `description` 도 가려 두었다 — `FareSplitRedaction`.)

/// 앱이 여는 유일한 딥링크 스킴.
let TOSS_DEEPLINK_SCHEME = "supertoss"

/// 서버가 준 딥링크를 **열어도 되는 URL** 로 바꾼다. 열면 안 되면 nil — 화면은 그때 열기 실패와 똑같이
/// 복사 버튼을 가리킨다(`TOSS_OPEN_FAILED_NOTICE`).
///
/// ### 왜 스킴을 보는가 (iOS) ★
/// 이 문자열은 **서버가 준 그대로** 연다 — 앱이 조립하지 않는다(`FareSplitDetail.tossDeeplink` 주석).
/// 그런데 `UIApplication.open` 은 스킴을 가리지 않는다: `https` 면 브라우저가, `tel` 이면 전화가, 다른 앱의
/// 스킴이면 그 앱이 열린다. 「토스로 보내기」 버튼이 서버 문자열 하나로 **아무 곳이나 열 수 있는 버튼**이 되면
/// 안 된다 — 사용자는 그 버튼을 송금 화면으로 믿고 누른다. 그래서 `supertoss` 가 아니면 열지 않는다.
/// 공백뿐이거나 URL 로 읽히지 않는 문자열도 같다.
func tossDeeplinkURL(_ deeplink: String) -> URL? {
    if deeplink.isBlank { return nil }
    guard let url = URL(string: deeplink), url.scheme?.lowercased() == TOSS_DEEPLINK_SCHEME else { return nil }
    return url
}

/// 토스 송금 화면을 연다. **열지 못했으면 false** — 그때 화면은 복사 버튼을 가리킨다.
///
/// ### 실패가 정상 경로다
/// 서버 주석 원문: 「비공식 규격이라 열리지 않을 수 있어 계좌·금액 복사 버튼을 함께 둔다」.
/// `supertoss://` 를 받아 줄 앱이 없는 기기(토스 미설치·시뮬레이터)가 흔하고, 토스가 스킴을 바꿔도
/// 같은 결과가 된다. 그래서 이 false 는 「오류」가 아니라 **분기**다.
///
/// `canOpenURL` 로 미리 묻지 않는 이유: 그러려면 `Info.plist` 의 `LSApplicationQueriesSchemes` 에 스킴을
/// 적어야 하고, 적지 않으면 **설치돼 있어도 false** 를 준다(원본 Android 의 `resolveActivity` 함정과 같은 모양).
/// `open` 의 완료 결과가 실제로 열렸는지를 그대로 알려 주므로 그것 하나로 가른다.
@MainActor
func openTossTransfer(deeplink: String) async -> Bool {
    guard let url = tossDeeplinkURL(deeplink) else { return false }
    return await UIApplication.shared.open(url)
}

/// 무엇을 복사했는가 — 확인 토스트의 문구가 갈린다.
///
/// 원본은 클립보드 항목 설명(「계좌번호」·「금액」)을 함께 넘겼다. iOS 클립보드에는 그 설명 자리가 없어
/// 토스트 문구로만 쓴다 — **값을 문구에 넣지 않는다**(계좌번호가 화면 아래 토스트·VoiceOver 로 다시 읽힌다).
///
/// `public` 인 이유는 공개 화면(`FareSplitDetailScreen`)의 복사 콜백 파라미터 타입이기 때문이다.
public enum FareSplitCopyTarget: Equatable, Sendable {
    case accountNumber
    case amount
}

/// 복사 뒤의 확인 문구. 실패하면 「복사하지 못했어요」 — 「복사했어요」를 띄우고 붙여넣기가 비어 있는 것이 최악이다.
func copyToastMessage(target: FareSplitCopyTarget, copied: Bool) -> String {
    guard copied else { return "복사하지 못했어요" }
    switch target {
    case .accountNumber: return "계좌번호를 복사했어요"
    case .amount: return "금액을 복사했어요"
    }
}

/// 클립보드에 한 줄 복사하고 **확인 토스트**를 띄운다. 복사하지 못했으면 false다.
///
/// ### 토스트를 띄우는 이유 (iOS)
/// 원본은 Android 13 부터 **OS 가 스스로 복사 확인 UI** 를 띄우므로 앱 토스트를 생략하고 버튼 글자만 바꿨다.
/// iOS 는 복사할 때 아무것도 보여 주지 않는다(붙여넣을 때만 알린다). 앱이 말하지 않으면 사용자는 눌렸는지
/// 알 수 없어, 앱의 다른 일회성 안내와 같은 토스트(`MoyeotaToast`)로 알린다.
///
/// 빈 값은 복사하지 않는다 — 계좌번호가 사라진 정산에서 빈 칸을 복사하고 「복사했어요」라고 말하면 거짓이다.
@MainActor
@discardableResult
func copyToPasteboard(_ text: String, target: FareSplitCopyTarget) -> Bool {
    let copied = !text.isEmpty
    if copied { UIPasteboard.general.string = text }
    MoyeotaToast.show(copyToastMessage(target: target, copied: copied))
    return copied
}
