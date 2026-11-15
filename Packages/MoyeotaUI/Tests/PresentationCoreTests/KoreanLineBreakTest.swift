import MoyeotaDesignSystem
import SwiftUI
import Testing
import UIKit
@testable import PresentationCore

/// 한국어 안내문의 **어절 단위 줄바꿈 폴백** — `keepKoreanWordsTogether`.
///
/// 화면에서는 「요」가 혼자 떨어지느냐로만 보이는 결함이라 스크린샷 없이는 잡히지 않는다. 그래서
/// 「어디서 끊을 수 있는가」를 문자열 수준에서 고정한다: 띄어쓰기가 아닌 자리에는 WORD JOINER 가
/// 있어야 하고, 마지막 두 어절은 NBSP 로 묶여야 한다. 그리고 **보이는 글자는 원문과 같아야** 한다.
@Suite struct KoreanLineBreakTest {
    /// 보이지 않는 표시를 걷어내면 원문이 돌아와야 한다 — 글자를 바꾸면 안 된다.
    private func visible(_ text: String) -> String {
        text.replacingOccurrences(of: String(WORD_JOINER), with: "")
            .replacingOccurrences(of: String(NO_BREAK_SPACE), with: " ")
    }

    private func count(_ character: Character, in text: String) -> Int {
        text.unicodeScalars.filter { String($0) == String(character) }.count
    }

    @Test("보이는 글자는 원문과 같다")
    func visibleTextUnchanged() {
        let notice = reservationCommitmentNotice(joining: false)

        #expect(visible(keepKoreanWordsTogether(notice)) == notice)
    }

    @Test("어절 안 글자 사이에는 줄바꿈을 막는 표시가 들어간다")
    func wordJoinersInsideWord() {
        let result = keepKoreanWordsTogether("기록돼요")

        #expect(result == "기\u{2060}록\u{2060}돼\u{2060}요")
    }

    @Test("마지막 두 어절은 끊기지 않는 공백으로 묶인다")
    func lastTwoWordsBound() {
        let result = keepKoreanWordsTogether("노쇼로 기록돼요")

        // 「노쇼로」와 「기록돼요」 사이가 NBSP — 마지막 줄에 어절 하나만 남는 일이 없다
        #expect(result == "노\u{2060}쇼\u{2060}로\u{00A0}기\u{2060}록\u{2060}돼\u{2060}요")
    }

    @Test("마지막이 아닌 띄어쓰기는 줄바꿈 자리로 남는다")
    func earlierSpacesStayBreakable() {
        let result = keepKoreanWordsTogether("출발 시각에 안 가면")

        // 공백은 셋, 그중 마지막 하나만 NBSP 다
        #expect(count(" ", in: result) == 2)
        #expect(count(NO_BREAK_SPACE, in: result) == 1)
        // 띄어쓰기 바로 옆에는 WORD JOINER 를 넣지 않는다(그 자리는 끊을 수 있어야 한다)
        #expect(!result.unicodeScalars.map(String.init).joined().contains(" \u{2060}"))
        #expect(!result.unicodeScalars.map(String.init).joined().contains("\u{2060} "))
    }

    @Test("마침표는 앞 어절에 붙어 다닌다")
    func periodStaysWithWord() {
        // 「없어요.」 의 마침표가 다음 줄 첫 글자가 되지 않는다(마침표도 어절의 일부다)
        #expect(keepKoreanWordsTogether("없어요. 출발").hasPrefix("없\u{2060}어\u{2060}요\u{2060}."))
    }

    @Test("짧거나 빈 문자열은 그대로다")
    func shortStringsUnchanged() {
        #expect(keepKoreanWordsTogether("") == "")
        #expect(keepKoreanWordsTogether("요") == "요")
    }

    /// 원본은 「API 33 이상은 원문을 그대로 그리고 그 아래만 폴백한다」를 본다. iOS 의 갈림은 API 레벨이 아니라
    /// 「시스템이 한글을 어절 단위로 끊는가」이고, 배포 대상(iOS 17)에서는 늘 그렇다.
    @Test("시스템이 어절 단위로 끊으면 원문을 그대로 그리고 아니면 폴백한다")
    func displayTextBranches() {
        let notice = reservationCommitmentNotice(joining: false)

        #expect(koreanParagraphDisplayText(notice, systemKeepsHangulWords: true) == notice)
        #expect(koreanParagraphDisplayText(notice) == notice, "iOS 17 이상은 늘 원문이다")
        #expect(koreanParagraphDisplayText(notice, systemKeepsHangulWords: false) == keepKoreanWordsTogether(notice))
    }
}

// ─── 원본에 없는 테스트: 균형 배치를 창에 올려 잰다 ───

@MainActor
private final class ParagraphProbe {
    var size: CGSize?
}

@MainActor
private func measureParagraph(width: CGFloat, maxLines: Int = Int.max) async -> CGSize? {
    let probe = ParagraphProbe()
    let view = KoreanParagraphText(
        text: reservationCommitmentNotice(joining: false),
        style: MoyeotaType.BodySm.copy(color: MoyeotaColor.TextMute),
        maxLines: maxLines
    )
    .onGeometryChange(for: CGSize.self) { $0.size } action: { probe.size = $0 }
    .frame(width: width)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    window.rootViewController = UIHostingController(rootView: view)
    window.isHidden = false
    defer { window.isHidden = true }
    for _ in 0..<20 {
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(25))
    }
    return probe.size
}

@MainActor
@Suite(.serialized) struct KoreanParagraphLayoutTest {
    /// 16 시트 푸터의 안내 폭(iPhone 17 에서 약 338)보다 조금 좁게 잡아 확실히 두 줄이 되게 한다. 원본 균형 배치처럼
    /// 줄 수는 그대로 두고 폭을 줄여 두 줄의 길이를 맞춘다.
    @Test("두 줄 안내는 줄 수를 지키는 가장 좁은 폭으로 그린다")
    func balancesTwoLines() async throws {
        let size = try #require(await measureParagraph(width: 300))
        let natural = UIHostingController(
            rootView: Text(reservationCommitmentNotice(joining: false)).moyeotaText(.BodySm)
        ).sizeThatFits(in: CGSize(width: 300, height: 5_000))

        #expect(abs(size.height - natural.height) < 1, "줄 수가 같아야 한다: \(size.height) 대 \(natural.height)")
        #expect(natural.height > 30, "이 폭에서 두 줄이어야 시험이 된다: \(natural.height)")
        #expect(size.width < natural.width - 20, "균형 배치는 폭이 줄어든다: \(size.width) 대 \(natural.width)")
    }

    @Test("한 줄에 들어가면 그대로 그린다")
    func singleLineUntouched() async throws {
        let size = try #require(await measureParagraph(width: 1_000))
        let natural = UIHostingController(
            rootView: Text(reservationCommitmentNotice(joining: false)).moyeotaText(.BodySm)
        ).sizeThatFits(in: CGSize(width: 1_000, height: 5_000))

        #expect(abs(size.width - natural.width) < 1)
        #expect(abs(size.height - natural.height) < 1)
    }
}
