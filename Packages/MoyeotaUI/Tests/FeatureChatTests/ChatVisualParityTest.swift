import CoreText
import MoyeotaDesignSystem
import SwiftUI
import Testing
import UIKit
@testable import FeatureChat

// 원본에 없는 테스트. 원본 렌더(UI 트리·스크린샷)에서 잰 값과 관찰한 동작을 지킨다.
//
// 디자인 다듬기(2026-11)로 이 화면의 글자가 모두 토큰(`MoyeotaType`)이 되어, 예전 원본 렌더에서 잰 `bodyLargeText`
// (머티리얼 bodyLarge 상속 + 한글 자간 보정)의 줄 상자·잉크·폭 시험은 걷었다. 다듬은 원본은 아직 렌더해 재지 않았다.

@Suite struct CharacterWrapTest {

    @Test("한글 사이와 한글·숫자 사이에 폭 없는 공백이 들어가고 원문은 그대로 복원된다")
    func marksBreaks() {
        let text = "5분이면 될 것 같아요"
        let marked = text.characterWrapped
        #expect(marked == "5\u{200B}분\u{200B}이\u{200B}면 될 것 같\u{200B}아\u{200B}요")
        #expect(marked.replacingOccurrences(of: "\u{200B}", with: "") == text)
    }

    @Test("문장부호 앞과 영문 단어 안은 꺾지 않는다")
    func keepsPunctuationAndWords() {
        #expect("요?".characterWrapped == "요?")
        #expect("hello world".characterWrapped == "hello world")
        #expect("「가」".characterWrapped == "「가」")
    }

    @Test("한 줄에 들어가면 그대로이고 폭은 줄지 않는다")
    func shortTextStaysOneLine() {
        let wrap = BubbleTextType.softWrappedLines("네 반갑습니다 :)", width: BubbleTextMaxWidth)
        #expect(wrap == SoftWrappedText(text: "네 반갑습니다 :)", wrapped: false))
    }

    /// 원본 `Text` 처럼 줄 끝까지 채운다 — 첫 줄은 폭 안에 들고, 다음 줄의 첫 덩이(사이 공백 포함)까지 붙이면 넘친다.
    /// 덩이는 꺾을 수 없는 글자 묶음이다(「요?」는 문장부호 앞에서 꺾지 않아 함께 넘어간다).
    /// 예전엔 원본 렌더의 줄 끝(「…챙기셨어 / 요?」)을 그대로 못 박았는데, 다듬기로 말풍선 글자가 `BodyMd` 가 되어 그 값이 맞지 않는다.
    @Test("줄 끝까지 채우고 마지막 한 글자도 다음 줄로 넘긴다", arguments: [
        "오늘 비 온다고 하던데 우산 챙기셨어요? 저는 깜빡하고 그냥 나왔어요",
        "저도 곧 도착해요. 5분이면 될 것 같아요 조금만 기다려 주세요",
    ])
    func fillsLineGreedily(text: String) {
        let wrap = BubbleTextType.softWrappedLines(text, width: BubbleTextMaxWidth)
        #expect(wrap.wrapped)
        let firstLine = wrap.text.components(separatedBy: "\n")[0]
        #expect(text.hasPrefix(firstLine))
        let rest = text.dropFirst(firstLine.count)
        let spaces = rest.prefix(while: { $0 == " " })
        let next = String(rest.dropFirst(spaces.count)).characterWrapped.prefix { $0 != "\u{200B}" && $0 != " " }
        #expect(!next.isEmpty, "둘째 줄이 없다: \(wrap.text)")
        #expect(typographicWidth(firstLine) <= BubbleTextMaxWidth, "\(firstLine)")
        #expect(typographicWidth(firstLine + spaces + next) > BubbleTextMaxWidth, "\(firstLine) + \(next)")
    }

    @Test("말풍선은 디자인 문서 chat-bubble 의 BodyMd 토큰을 쓴다")
    func bubbleUsesBodyMd() {
        #expect(BubbleTextType == MoyeotaType.BodyMd.hangulTrimmed)
    }

    private func typographicWidth(_ text: String) -> CGFloat {
        let string = NSAttributedString(
            string: text,
            attributes: [.font: BubbleTextType.uiFont, .kern: BubbleTextType.letterSpacing]
        )
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil))
    }

    @Test("글 안의 줄바꿈은 꺾인 줄로 세지 않는다")
    func hardBreaksAreNotSoftWraps() {
        let wrap = BubbleTextType.softWrappedLines("가\n나\n", width: BubbleTextMaxWidth)
        #expect(wrap == SoftWrappedText(text: "가\n나\n", wrapped: false))
    }
}

@MainActor
@Suite struct ChatScrollTrackerOpenTest {

    @Test("탭에서 연 방은 처음부터 바닥을 따라간다")
    func tabFollows() {
        let tracker = ChatScrollTracker()
        #expect(tracker.shouldFollow(maxScroll: 0))
        #expect(tracker.shouldFollow(maxScroll: 2_000))
    }

    @Test("독립 목적지는 넘치는 첫 내용에서 움직이지 않고 따라가기를 끈다")
    func destinationDetaches() {
        let tracker = ChatScrollTracker(followsBottomOnOpen: false)
        #expect(!tracker.shouldFollow(maxScroll: 0), "첫 내용 전에는 움직일 이유가 없다")
        #expect(!tracker.shouldFollow(maxScroll: 2_000))
        #expect(!tracker.shouldFollow(maxScroll: 2_060), "새 메시지가 와도 그대로다")
    }

    @Test("독립 목적지도 슬롭 안으로 넘치면 바닥을 따라간다")
    func destinationFollowsWhenShort() {
        let tracker = ChatScrollTracker(followsBottomOnOpen: false)
        #expect(tracker.shouldFollow(maxScroll: 100))
        #expect(tracker.shouldFollow(maxScroll: 2_000))
    }

    @Test("독립 목적지에서 바닥까지 내려가 멈추면 다시 따라간다")
    func destinationReattaches() async {
        let tracker = ChatScrollTracker(followsBottomOnOpen: false)
        tracker.viewportHeight = 500
        #expect(!tracker.shouldFollow(maxScroll: 2_000))
        tracker.scrolled(to: ChatScrollMetrics(top: 0, bottom: 2_500))
        tracker.scrolled(to: ChatScrollMetrics(top: -2_000, bottom: 500))
        try? await Task.sleep(for: .milliseconds(400))
        #expect(tracker.shouldFollow(maxScroll: 2_060))
    }
}
