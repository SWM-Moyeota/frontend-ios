import MoyeotaDesignSystem
import MoyeotaDomain
import SwiftUI

// 한국어 안내문을 **어절 단위로** 줄바꿈하는 도구 — 「…기록돼 / 요」처럼 마지막 음절 하나가 혼자
// 줄을 차지하는 것을 막는다(16 도착지 확인의 예약 안내에서 실제로 났다, 오너 UX 피드백 2026-11).
//
// ### 원본은 왜 「요」가 혼자 떨어지는가
// 안드로이드 줄바꿈(ICU, UAX #14)은 한글 음절을 **한자처럼** 다룬다 — 음절과 음절 사이 어디서나 끊을 수 있다.
// 그래서 원본은 두 갈래로 웹의 `word-break: keep-all`(띄어쓰기에서만 끊기)을 얻는다.
//
// | 원본 | 방법 |
// |---|---|
// | API 33 이상 | `LineBreak.Heading` — 균형 배치(Balanced) + **구 단위** 줄바꿈. 텍스트 로케일을 한국어로 건다 |
// | 32 이하 | 글자 자체를 바꾼다(`keepKoreanWordsTogether`): 어절 안 글자 사이에 WORD JOINER(U+2060), 마지막 두 어절 사이에 NBSP(U+00A0) |
//
// ### iOS
// iOS 의 `Text` 는 시스템 줄바꿈 전략(`NSParagraphStyle.LineBreakStrategy.standard`, iOS 14 부터)에 이미
// **한글 단어 우선**(`hangulWordPriority` — 한글 음절 사이에서 끊지 않는다)과 **마지막 줄 고아 단어 방지**(`pushOut`)가
// 들어 있다. 원본 API 33 이상 갈래와 같은 처지라 글자를 바꾸지 않고 원문을 그린다(`koreanParagraphDisplayText`).
// 원본의 균형 배치는 iOS 에 없어 `KoreanParagraphText` 가 줄 수를 지키는 가장 좁은 폭을 찾아 그 폭으로 그린다.
// 폴백 규칙(`keepKoreanWordsTogether`)도 원본 그대로 옮겨 둔다 — 원본 KDoc 이 「iOS 에서 꼬리 음절이 남으면 같은 규칙을
// 적용한다」고 적은 자리다(`docs/IOS-DIFFERENCES.md`).

/// U+2060 WORD JOINER — 폭 0, 「이 자리에서 줄을 바꾸지 마라」(UAX #14 LB11).
let WORD_JOINER: Character = "\u{2060}"

/// U+00A0 NO-BREAK SPACE — 보통 띄어쓰기와 같은 폭이지만 그 자리에서 끊지 않는다(UAX #14 GL).
let NO_BREAK_SPACE: Character = "\u{00A0}"

/// 이 글이 한국어라는 표시(원본 `KoreanLocale` — 텍스트 로케일 ko-KR). 기기 로케일이 영어여도 그대로다.
let KoreanLocale = Locale(identifier: "ko-KR")

/// 시스템이 한글을 어절 단위로 끊는가 — 원본 `sdkInt >= PHRASE_LINE_BREAK_MIN_SDK` 의 자리.
///
/// iOS 14 부터 `LineBreakStrategy.standard` 에 `hangulWordPriority` 가 들어 있고 배포 대상이 iOS 17 이라 늘 참이다.
let SYSTEM_KEEPS_HANGUL_WORDS = true

/// 시스템 줄바꿈이 어절 단위가 아닐 때를 위한 **keep-all 흉내** — 띄어쓰기에서만 줄을 바꿀 수 있게, 그리고 마지막 두
/// 어절은 함께 다니게 문자열을 바꾼다.
///
/// 1. **어절 안**의 이웃한 두 글자 사이에 `WORD_JOINER` 를 넣는다 → 한글 음절 사이 줄바꿈 기회가 사라진다
/// 2. **마지막 띄어쓰기**를 `NO_BREAK_SPACE` 로 바꾼다 → 마지막 줄에 어절 하나만 남는 일(고아 어절)이 없다
///
/// 띄어쓰기(공백 문자)가 하나도 없으면 1 만 적용된다. 빈 문자열·한 글자는 그대로 돌려준다.
/// 이미 들어 있는 줄바꿈 문자(`\n`)는 공백으로 보고 건드리지 않는다 — 그 자리는 원래 끊기는 자리다.
///
/// 어절이 한 줄보다 길면 줄바꿈기가 어쩔 수 없이 그 안에서 끊는다(넘쳐서 잘리지는 않는다).
///
/// 원본은 UTF-16 한 칸(`Char`)씩 본다. Swift 문자열은 대리 쌍을 쪼갤 수 없어 유니코드 스칼라 하나씩 본다 —
/// BMP 밖 글자(이모지 등) 안에 표시를 넣지 않는 것만 다르다.
func keepKoreanWordsTogether(_ text: String) -> String {
    let scalars = Array(text.unicodeScalars)
    if scalars.count < 2 { return text }
    let lastSpace = scalars.lastIndex { $0 == " " }
    var out = String.UnicodeScalarView()
    for (index, scalar) in scalars.enumerated() {
        if index > 0 {
            let previous = scalars[index - 1]
            if !previous.isKotlinWhitespace && !scalar.isKotlinWhitespace {
                out.append(contentsOf: WORD_JOINER.unicodeScalars)
            }
        }
        if index == lastSpace {
            out.append(contentsOf: NO_BREAK_SPACE.unicodeScalars)
        } else {
            out.append(scalar)
        }
    }
    return String(out)
}

/// 이 기기에서 실제로 그릴 문자열 — 시스템이 한글을 어절 단위로 끊으면 원문 그대로, 아니면 `keepKoreanWordsTogether`
/// 를 적용한 값.
///
/// 판정을 **인자로** 받는다 — 순수 함수로 두어야 두 갈래를 단위 테스트에서 함께 고정할 수 있다(원본은 API 레벨을 받는다).
func koreanParagraphDisplayText(_ text: String, systemKeepsHangulWords: Bool = SYSTEM_KEEPS_HANGUL_WORDS) -> String {
    systemKeepsHangulWords ? text : keepKoreanWordsTogether(text)
}

/// 가운데 정렬 + 어절 단위 줄바꿈 + 균형 배치로 그리는 한국어 안내문. 글자 자체는 바꾸지 않는다(파일 머리말).
///
/// `style` 의 색·크기·굵기는 호출부 것을 그대로 쓰고, 정렬·줄바꿈만 덮어쓴다.
/// 정렬을 가운데로 고정하는 이유: 두 줄짜리 안내가 버튼 위에 놓일 때 왼쪽 정렬이면 둘째 줄이 짧아
/// 비뚤어 보이고, 가운데면 균형 배치와 함께 두 줄이 한 덩어리로 읽힌다.
///
/// 크기는 그린 글의 크기다(원본 `Text` 처럼). 원본 호출부의 `fillMaxWidth()` 자리에는 `.frame(maxWidth: .infinity)` 를 준다.
public struct KoreanParagraphText: View {
    private let text: String
    private let style: MoyeotaType
    private let maxLines: Int

    public init(text: String, style: MoyeotaType, maxLines: Int = Int.max) {
        self.text = text
        self.style = style
        self.maxLines = maxLines
    }

    public var body: some View {
        let display = koreanParagraphDisplayText(text)
        let lineLimit = maxLines == Int.max ? nil : maxLines
        BalancedLinesLayout {
            Text(display)
                .moyeotaText(style)
                .multilineTextAlignment(.center)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
            // 줄 수를 재기만 하는 같은 글(줄 수 제한 없음). 보이지 않는다.
            Text(display)
                .moyeotaText(style)
                .multilineTextAlignment(.center)
                .hidden()
                .accessibilityHidden(true)
        }
        .environment(\.locale, KoreanLocale)
        .modifier(OriginalTextLabel(text: text, display: display))
    }
}

/// 폴백 문자열(U+2060·U+00A0 포함)이 아니라 **원문**을 읽게 한다.
private struct OriginalTextLabel: ViewModifier {
    let text: String
    let display: String

    func body(content: Content) -> some View {
        if display == text {
            content
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
        }
    }
}

/// 원본 균형 배치(`BREAK_STRATEGY_BALANCED`)의 자리 — **줄 수는 그대로 두고 가장 좁은 폭**으로 글을 그린다.
/// 두 줄의 길이가 비슷해져 짧은 꼬리 줄이 덜 생긴다.
///
/// 첫째 자식은 보이는 글(줄 수 제한), 둘째는 같은 글의 제한 없는 사본이다. 줄 수는 사본으로 잰다 — 제한된 글은 잘려도
/// 높이가 같아 줄 수를 알 수 없다. 받은 폭에서 한 줄이거나 줄 수 제한을 넘어 잘리면 균형을 맞추지 않는다.
private struct BalancedLinesLayout: Layout {
    /// 받은 폭마다 찾은 폭. 재는 일(글자 배치)이 여러 번이라 같은 배치 안에서 다시 하지 않는다. 자식이 바뀌면 새로 만든다.
    final class Cache {
        var widths: [CGFloat: CGFloat] = [:]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard let visible = subviews.first else { return .zero }
        let width = balancedWidth(proposal.width, subviews: subviews, cache: cache)
        return visible.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard let visible = subviews.first else { return }
        let width = balancedWidth(bounds.width, subviews: subviews, cache: cache)
        visible.place(
            at: CGPoint(x: bounds.midX, y: bounds.minY),
            anchor: .top,
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
        for measuring in subviews.dropFirst() {
            measuring.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: 0, height: 0))
        }
    }

    private func balancedWidth(_ proposed: CGFloat?, subviews: Subviews, cache: Cache) -> CGFloat? {
        guard let maxWidth = proposed, maxWidth.isFinite, maxWidth > 0, subviews.count > 1 else { return proposed }
        if let known = cache.widths[maxWidth] { return known }
        let found = searchBalancedWidth(maxWidth: maxWidth, visible: subviews[0], measuring: subviews[1])
        cache.widths[maxWidth] = found
        return found
    }

    private func searchBalancedWidth(maxWidth: CGFloat, visible: LayoutSubview, measuring: LayoutSubview) -> CGFloat {
        func height(_ width: CGFloat?, _ subview: LayoutSubview) -> CGFloat {
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        let target = height(maxWidth, measuring)
        // 한 줄에 들어가면 맞출 것이 없다. 줄 수 제한에 걸려 잘리면(보이는 글이 사본보다 낮다) 원본처럼 받은 폭에서 자른다.
        guard target > height(nil, measuring) + 0.5, height(maxWidth, visible) >= target - 0.5 else { return maxWidth }
        var low: CGFloat = 1
        var high = maxWidth
        while high - low > 0.5 {
            let mid = (low + high) / 2
            if height(mid, measuring) > target + 0.5 {
                low = mid
            } else {
                high = mid
            }
        }
        return min(high.rounded(.up), maxWidth)
    }
}
