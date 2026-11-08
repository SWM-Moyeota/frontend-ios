import Foundation
import MoyeotaDomain
import Testing
@testable import FeatureMyPage

/// 38 노쇼 기록·이의 신청과 35 제재 배너의 판정 규칙.
///
/// **여기서 테스트가 꼭 필요한 이유 — 틀려도 화면에 보이지 않는다.**
/// 이 파일이 지키는 1급 규칙은 「`objectionStatus == nil && !isVoided` 인 줄에만 이의 신청 버튼을
/// 보여 준다」다. 한 칸 잘못 잡은 화면은 **스크린샷으로 구분할 수 없고**, 틀렸다는 사실은 사용자가
/// 그 버튼을 눌러 409 `NOT_NO_SHOW`·`ALREADY_OBJECTED` 를 받는 순간에만 드러난다 — 사유를 다 쓴
/// 뒤에. 눈으로 확인하려면 **무효 처리된 노쇼를 가진 계정**을 서버에 만들어야 한다(운영자 API 로만
/// 가능하다). 값으로 넣어 본다.
///
/// 시계도 같은 이유다. 제재 배너의 「언제까지」는 `restrictedUntil` 이 **지금보다 뒤인가**로
/// 갈리는데, 24시간짜리 제한이라 그 경계를 실기로 밟으려면 하루를 기다려야 한다.
@Suite struct NoShowRecordsRulesTest {

    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    /// 테스트 기준 시각 — 2026-11-06 00:00 KST(2026-11-05T15:00:00Z). 어느 함수도 `Date()` 를 안에서 부르지 않는다.
    private let now = Date(timeIntervalSince1970: 1_793_890_800)

    /// 원본 `Instant.toString()` 자리 — 초 단위면 `2026-11-05T15:00:00Z` 꼴이다.
    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func record(
        partyId: Int64 = 1,
        departure: String = "강남역",
        destination: String = "판교역",
        meetingAt: String? = "2026-11-05T07:15:00Z",
        noShowAt: String? = "2026-11-05T07:20:00Z",
        isVoided: Bool = false,
        objectionStatus: ObjectionStatus? = nil
    ) -> NoShowRecord {
        NoShowRecord(
            partyId: partyId,
            departure: departure,
            destination: destination,
            meetingAt: meetingAt,
            noShowAt: noShowAt,
            isVoided: isVoided,
            objectionStatus: objectionStatus
        )
    }

    // ─────────────────────────── 줄 상태 ───────────────────────────

    /// ★ 이 저장소에서 가장 비싼 한 줄. 서버가 201 을 주는 조건과 **한 글자도 달라서는 안 된다.**
    @Test("이의를 낸 적 없는 살아 있는 노쇼만 이의 신청을 허용한다")
    func onlyOpenAllowsObjection() {
        #expect(noShowRowState(isVoided: false, objectionStatus: nil) == .open)
        #expect(noShowRowState(isVoided: false, objectionStatus: nil).allowsObjection)
    }

    @Test("이미 이의를 낸 줄에는 버튼이 없다")
    func objectedRowsHaveNoButton() {
        for status in [ObjectionStatus.pending, .accepted, .rejected] {
            let state = noShowRowState(isVoided: false, objectionStatus: status)
            #expect(!state.allowsObjection, "\(status) 에 이의 신청 버튼이 생겼다")
        }
    }

    /// **`isVoided` 가 `objectionStatus` 를 이긴다.** 운영자가 이의 없이 무효로 돌린 기록
    /// (`isVoided && objectionStatus == nil`)이 실제로 올 수 있고, 거기에 버튼을 달면 409
    /// `NOT_NO_SHOW` 가 확정이다(서버는 「노쇼가 아니거나 이미 무효」를 같은 코드로 준다).
    @Test("무효가 된 노쇼에는 어떤 조합에서도 버튼이 없다")
    func voidedNeverAllowsObjection() {
        let statuses: [ObjectionStatus?] = [nil, .pending, .accepted, .rejected]
        for status in statuses {
            let state = noShowRowState(isVoided: true, objectionStatus: status)
            #expect(state == .voided, "무효인데 상태가 \(String(describing: status)) 라고 갈렸다")
            #expect(!state.allowsObjection)
        }
    }

    @Test("이의 상태가 그대로 줄 상태가 된다")
    func objectionStatusMapsToRowState() {
        #expect(noShowRowState(isVoided: false, objectionStatus: .pending) == .pending)
        #expect(noShowRowState(isVoided: false, objectionStatus: .accepted) == .accepted)
        #expect(noShowRowState(isVoided: false, objectionStatus: .rejected) == .rejected)
    }

    // ─────────────────────────── 배지·부연 문구 ───────────────────────────

    /// 다섯 상태가 **서로 구분돼야** 한다. 같은 글자가 두 상태에 쓰이면 상태를 가른 의미가 없다.
    /// `NoShowRowState.open` 만 배지가 없고, 그 줄을 가르는 것은 이의 신청 버튼이다.
    @Test("상태마다 다른 배지 글자를 쓰고 이의 전에는 배지가 없다")
    func badgesDistinctAndNoneBeforeObjection() {
        #expect(noShowBadgeText(state: .open) == nil, "이의를 내기 전에는 말할 상태가 없다")

        let badges = NoShowRowState.allCases
            .filter { $0 != .open }
            .map { noShowBadgeText(state: $0) }
        #expect(badges.allSatisfy { !($0 ?? "").isBlank }, "배지가 빈 상태가 있다: \(badges)")
        #expect(badges.count == Set(badges).count, "같은 배지 글자가 두 상태에 쓰였다: \(badges)")
    }

    /// ★ **검토 중 문구가 이 화면에서 가장 위험한 자리다.**
    ///
    /// 이의 결과를 알리는 푸시가 **서버에 없다.** 사용자가 결과를 아는 길은 이 화면을 다시 여는 것
    /// 하나뿐이라, 「알려 드려요」·「며칠 안에」·「풀어 드려요」는 전부 지킬 수 없는 말이 된다.
    /// 이 저장소는 그런 문구 19건을 들어낸 이력이 있다(`ProductClaimsTest` 주석).
    @Test("검토 중 문구는 알림도 시한도 결과도 약속하지 않는다")
    func pendingNoteMakesNoPromise() throws {
        let note = try #require(noShowNoteText(state: .pending))

        // 사용자가 실제로 할 수 있는 일을 말해야 한다 — 이 화면을 다시 보는 것.
        #expect(note.contains("이 화면"), "\(note)")
        let forbiddenWords = [
            "알려 드려요", "알림", "푸시",
            "시간 안에", "시간 내", "분 안에", "일 안에", "영업일",
            "곧", "빠르게", "즉시",
            "풀어 드려요", "해제해", "인정돼요",
        ]
        for forbidden in forbiddenWords {
            #expect(!note.contains(forbidden), "지킬 수 없는 약속이다: \(note) (\(forbidden))")
        }
    }

    /// 무효 문구는 **횟수에서 빠졌다**까지만 말한다. 「제한이 풀렸어요」는 거짓일 수 있다 —
    /// 다른 노쇼가 남아 있으면 제한은 그대로다. 지금 제한 여부는 35 배너가 서버 값으로만 말한다.
    @Test("무효 문구는 제한 해제를 말하지 않는다")
    func voidedNoteDoesNotClaimRelease() throws {
        let note = try #require(noShowNoteText(state: .voided))

        #expect(note.contains("횟수"), "\(note)")
        for forbidden in ["제한이 풀", "이용할 수 있어요", "해제"] {
            #expect(!note.contains(forbidden), "한 건의 무효가 제한 해제는 아니다: \(note)")
        }
    }

    /// 거절 뒤에 할 수 있는 일이 없다는 것을 말해 줘야 한다 — 빼면 같은 방의 버튼을 계속 찾는다.
    @Test("거절 문구는 다시 낼 수 없다고 말한다")
    func rejectedNoteSaysNoRetry() throws {
        let note = try #require(noShowNoteText(state: .rejected))

        #expect(note.contains("다시 이의를 낼 수 없"), "\(note)")
    }

    /// 버튼이 바로 아래 있는 줄에는 설명을 두지 않는다 — 같은 말을 두 번 하게 된다.
    @Test("이의를 낼 수 있는 줄에는 부연이 없다")
    func openRowHasNoNote() {
        #expect(noShowNoteText(state: .open) == nil)
    }

    // ─────────────────────────── 카드 한 장 ───────────────────────────

    /// 서버가 UTC 로 주는 시각을 **기기 시간대로** 바꿔 쓴다. 문자열을 자르면 KST 오후 4시가
    /// 오전 7시로 보인다(채팅에서 실제로 났던 결함). 34 지난 탑승 기록과 같은 함수를 쓴다.
    @Test("두 시각을 기기 시간대로 바꿔 적는다")
    func timesInDeviceZone() {
        let item = record().toNoShowItem(now: now, zone: seoul)

        #expect(item.routeLabel == "강남역 → 판교역")
        #expect(item.meetingLabel == "11월 5일 오후 4:15")
        #expect(item.markedLabel == "11월 5일 오후 4:20")
        #expect(item.allowsObjection)
        #expect(item.badgeText == nil)
    }

    /// 파싱할 수 없거나 아예 없는 시각은 nil — **틀린 날짜보다 없는 편이 낫다**(34 와 같은 규칙).
    @Test("시각을 모르면 그 줄을 비운다")
    func unknownTimesAreEmpty() {
        let missing = record(meetingAt: nil, noShowAt: nil).toNoShowItem(now: now, zone: seoul)
        #expect(missing.meetingLabel == nil)
        #expect(missing.markedLabel == nil)

        let broken = record(meetingAt: "2026-11-05", noShowAt: "어제").toNoShowItem(now: now, zone: seoul)
        #expect(broken.meetingLabel == nil)
        #expect(broken.markedLabel == nil)
    }

    /// 한쪽만 있으면 있는 쪽만, 둘 다 없으면 nil — 빈 화살표를 그리지 않는다.
    @Test("경로는 있는 쪽만 적는다")
    func routeUsesPresentSide() {
        #expect(record(destination: " ").toNoShowItem(now: now, zone: seoul).routeLabel == "강남역")
        #expect(record(departure: "").toNoShowItem(now: now, zone: seoul).routeLabel == "판교역")
        #expect(record(departure: "", destination: "").toNoShowItem(now: now, zone: seoul).routeLabel == nil)
    }

    /// 카드가 들고 있는 상태·배지·부연이 판정 함수와 어긋나지 않는다(화면이 다시 판정하지 않는다).
    @Test("카드는 같은 판정을 그대로 들고 있다")
    func cardCarriesSameJudgement() {
        let voided = record(isVoided: true, objectionStatus: .accepted).toNoShowItem(now: now, zone: seoul)

        #expect(voided.state == .voided)
        #expect(voided.badgeText == noShowBadgeText(state: .voided))
        #expect(voided.note == noShowNoteText(state: .voided))
        #expect(!voided.allowsObjection)
    }

    // ─────────────────────────── 35 제재 배너 ───────────────────────────

    @Test("노쇼가 없고 제한도 없으면 배너를 그리지 않는다")
    func noSanctionNoBanner() {
        #expect(noShowSanction(noShowCount: 0, restrictedUntil: nil, now: now, zone: seoul) == nil)
        #expect(noShowSanction(noShowCount: 0, restrictedUntil: "", now: now, zone: seoul) == nil)
    }

    /// 제한 중 — **횟수와 기한을 함께** 말하고, 이의를 낼 수 있는 길을 가리킨다.
    @Test("제한 중이면 기한과 횟수를 말한다")
    func restrictedSaysDeadlineAndCount() throws {
        let sanction = try #require(
            noShowSanction(
                noShowCount: 2,
                restrictedUntil: iso(now.addingTimeInterval(20 * 3_600)),
                now: now,
                zone: seoul
            )
        )

        #expect(sanction.kind == .restricted)
        #expect(sanction.text.contains("노쇼 2건"), "\(sanction.text)")
        #expect(sanction.text.contains("11월 6일 오후 8:00"), "\(sanction.text)")
        #expect(sanction.text.contains("방·예약을 만들거나 참여할 수 없어요"), "\(sanction.text)")
        // 막힌 사람이 다음에 갈 곳 — 35 에 있는 행 이름을 그대로 인용한다.
        #expect(sanction.text.contains("「노쇼 기록」"), "\(sanction.text)")
    }

    /// **이미 지난 `restrictedUntil` 을 「지금 막혀 있어요」로 말하지 않는다.**
    ///
    /// 서버는 제한이 없으면 null 을 주지만 응답은 몇 분 전 값일 수 있고, 24시간짜리 제한은 그 사이에
    /// 끝난다. nil 여부만 보면 실제로는 되는 방 만들기를 사용자가 시도조차 하지 않는다.
    @Test("기한이 지났으면 제한으로 말하지 않는다")
    func pastDeadlineIsNotRestricted() throws {
        let sanction = try #require(
            noShowSanction(
                noShowCount: 1,
                restrictedUntil: iso(now.addingTimeInterval(-60)),
                now: now,
                zone: seoul
            )
        )

        #expect(sanction.kind == .counted)
        #expect(!sanction.text.contains("참여할 수 없어요"), "\(sanction.text)")
    }

    /// 제한이 풀렸고 횟수만 남은 상태 — 30일 만료를 말한다(제한 기간과 다른 수다).
    @Test("횟수만 남으면 30일 만료를 말한다")
    func countedSaysThirtyDays() throws {
        let sanction = try #require(noShowSanction(noShowCount: 1, restrictedUntil: nil, now: now, zone: seoul))

        #expect(sanction.kind == .counted)
        #expect(sanction.text.contains("노쇼 1건"), "\(sanction.text)")
        #expect(sanction.text.contains("30일"), "\(sanction.text)")
    }

    /// 기한을 **읽을 수 없을 때도 제한 자체는 숨기지 않는다.** 값이 비어 있지 않다는 건 서버가
    /// 제한을 걸었다는 뜻이다 — 「제한 없음」으로 접으면 막힌 이유를 설명할 유일한 배너가 사라진다.
    /// 대신 **틀린 시각을 쓰지 않는다**(「까지」가 없어야 한다).
    @Test("기한을 못 읽어도 제한은 말하고 시각은 지어내지 않는다")
    func unreadableDeadlineStillRestricted() throws {
        let sanction = try #require(
            noShowSanction(noShowCount: 1, restrictedUntil: "2026년 11월 7일", now: now, zone: seoul)
        )

        #expect(sanction.kind == .restricted)
        #expect(sanction.text.contains("지금은"), "\(sanction.text)")
        #expect(!sanction.text.contains("까지"), "읽지 못한 기한을 적었다: \(sanction.text)")
    }

    /// 「노쇼 0건으로 제한됐어요」는 그 자체로 모순이다 — 횟수는 1 이상일 때만 문구에 넣는다.
    @Test("횟수가 0 이면 제한 문구에 횟수를 넣지 않는다")
    func zeroCountNotInRestrictedText() throws {
        let sanction = try #require(
            noShowSanction(
                noShowCount: 0,
                restrictedUntil: iso(now.addingTimeInterval(3 * 3_600)),
                now: now,
                zone: seoul
            )
        )

        #expect(sanction.kind == .restricted)
        #expect(!sanction.text.contains("노쇼 0"), "\(sanction.text)")
    }

    @Test("제한 여부 판정은 시각으로만 한다")
    func restrictionJudgedByTimeOnly() {
        #expect(isNoShowRestricted(restrictedUntil: iso(now.addingTimeInterval(1)), now: now))
        #expect(!isNoShowRestricted(restrictedUntil: iso(now), now: now))
        #expect(!isNoShowRestricted(restrictedUntil: iso(now.addingTimeInterval(-1)), now: now))
        #expect(!isNoShowRestricted(restrictedUntil: nil, now: now))
        #expect(!isNoShowRestricted(restrictedUntil: "  ", now: now))
        #expect(!isNoShowRestricted(restrictedUntil: "내일", now: now), "읽을 수 없는 값을 미래로 보지 않는다")
    }

    /// 제한 기한 표기는 **시·분을 절대 생략하지 않는다.** 34 의 날짜 표기는 다른 해의 기록에서
    /// 시각을 떼는데, 여기서 그러면 연말에 걸린 제한이 「1월 1일」로만 보이고 그날 하루 종일 못
    /// 쓰는 것처럼 읽힌다.
    @Test("제한 기한은 해가 달라도 시각을 남긴다")
    func deadlineKeepsClockAcrossYears() {
        let label = noShowRestrictionLabel(isoTime: "2027-01-01T01:30:00Z", now: now, zone: seoul)

        #expect(label == "2027년 1월 1일 오전 10:30")
    }

    /// 자정이 「오전 0:05」로 찍히지 않는다(`hour % 12` 만 쓰면 그렇게 된다).
    @Test("자정과 정오를 12로 적는다")
    func midnightAndNoonAreTwelve() {
        #expect(noShowRestrictionLabel(isoTime: "2026-11-05T15:05:00Z", now: now, zone: seoul) == "11월 6일 오전 12:05")
        #expect(noShowRestrictionLabel(isoTime: "2026-11-06T03:05:00Z", now: now, zone: seoul) == "11월 6일 오후 12:05")
    }

    @Test("읽을 수 없는 기한은 null 이다")
    func unreadableDeadlineIsNil() {
        #expect(noShowRestrictionLabel(isoTime: "2026-11-07", now: now, zone: seoul) == nil)
        #expect(
            noShowRestrictionLabel(isoTime: "2026-11-07T09:00:00+09:00", now: now, zone: seoul) != nil,
            "오프셋 표기는 읽어야 한다"
        )
    }

    // ─────────────────────────── 이의 사유 입력 ───────────────────────────

    /// ★ **공백만 쓴 글은 보낼 수 없다.** 서버가 `reason.trim()` 을 1~500자로 검사하므로 trim 전
    /// 길이로 재면 스페이스 세 개를 쓴 사용자에게 버튼이 열리고 400 `INVALID_REQUEST` 가 돌아온다 —
    /// 앱이 막을 수 있었던 거절이고, 그 응답 문구로는 무엇을 고칠지 알 수 없다.
    @Test("공백만 있는 사유는 보낼 수 없다")
    func blankReasonCannotBeSent() {
        for blank in ["", " ", "   ", "\n", " \n\t "] {
            let ui = objectionReasonUi(reason: blank)
            #expect(!ui.submitEnabled, "공백만 있는 사유로 버튼이 열렸다: 「\(blank)」")
            // 잠긴 이유를 카운터가 말한다 — 0자다.
            #expect(ui.counter == "0/500자")
        }
    }

    @Test("한 글자부터 보낼 수 있다")
    func oneCharacterCanBeSent() {
        let ui = objectionReasonUi(reason: "늦")

        #expect(ui.submitEnabled)
        #expect(!ui.overLimit)
        #expect(ui.counter == "1/500자")
    }

    /// 서버 한도와 같은 경계여야 한다 — 500 은 통과, 501 은 막힌다.
    @Test("500자는 보내고 501자는 막는다")
    func boundaryAtFiveHundred() {
        let max = objectionReasonUi(reason: String(repeating: "가", count: OBJECTION_REASON_MAX))
        #expect(max.submitEnabled)
        #expect(!max.overLimit)
        #expect(max.counter == "500/500자")

        let over = objectionReasonUi(reason: String(repeating: "가", count: OBJECTION_REASON_MAX + 1))
        #expect(!over.submitEnabled)
        #expect(over.overLimit)
    }

    /// 앞뒤 공백은 서버가 떼므로 길이에 세지 않는다 — 공백 때문에 501자가 되는 일이 없어야 한다.
    @Test("앞뒤 공백은 길이에 세지 않는다")
    func surroundingWhitespaceNotCounted() {
        let ui = objectionReasonUi(reason: "  " + String(repeating: "가", count: OBJECTION_REASON_MAX) + "\n ")

        #expect(ui.submitEnabled, "trim 하면 500자인데 막혔다")
        #expect(ui.counter == "500/500자")
    }

    /// 넘겼을 때 **몇 자를 줄여야 하는지**까지 적는다. 「500자를 넘었어요」만 적으면 517자를 쓴
    /// 사람이 얼마를 지워야 하는지 직접 세야 한다.
    @Test("한도를 넘기면 몇 자를 줄여야 하는지 말한다")
    func overLimitSaysHowMuchToCut() {
        let ui = objectionReasonUi(reason: String(repeating: "가", count: OBJECTION_REASON_MAX + 17))

        #expect(ui.counter == "517/500자 — 17자 줄여야 보낼 수 있어요")
    }

    /// 보내는 중에는 두 번 보낼 수 없다 — 방마다 한 번뿐이라 두 번째는 409 다.
    @Test("보내는 중에는 버튼이 잠긴다")
    func submittingLocksButton() {
        #expect(!objectionReasonUi(reason: "늦었어요", submitting: true).submitEnabled)
    }

    /// 입력창은 한도의 2배까지 받아 준다 — 500자에서 입력이 멈추는 칸은 고장으로 읽힌다.
    @Test("입력창의 하드 리밋은 한도보다 넉넉하다")
    func hardLimitExceedsMax() {
        #expect(OBJECTION_REASON_HARD_LIMIT > OBJECTION_REASON_MAX)
    }

    // ─────────────────────────── 고정 문구 ───────────────────────────

    /// 시트·성공 안내가 **운영 처리를 약속하지 않는다.** 이의는 사람이 보고, 결과 푸시는 없다.
    /// 「접수됐습니다」로 끝내면 사용자는 오지 않는 알림을 기다린다 — 결과를 보는 길을 같은
    /// 문장에서 알려 줘야 한다.
    @Test("이의 안내 문구는 시한도 알림도 결과도 약속하지 않는다")
    func objectionCopyMakesNoPromise() {
        let copy = [
            OBJECTION_SHEET_TITLE,
            OBJECTION_SHEET_NOTICE,
            OBJECTION_SENT_TEXT,
            OBJECTION_INPUT_PLACEHOLDER,
        ].joined(separator: " ")

        let forbiddenWords = [
            "알려 드려요", "알림", "푸시",
            "시간 안에", "시간 내", "분 안에", "일 안에", "영업일",
            "곧", "즉시", "빠르게",
            "풀어 드려요", "해제", "인정돼요", "취소돼요",
        ]
        for forbidden in forbiddenWords {
            #expect(!copy.contains(forbidden), "지킬 수 없는 약속이다: \(forbidden)")
        }

        // 서버 계약으로 참인 둘은 **남아야** 한다
        #expect(OBJECTION_SHEET_NOTICE.contains("한 번만"), "\(OBJECTION_SHEET_NOTICE)")
        #expect(OBJECTION_SENT_TEXT.contains("이 화면"), "\(OBJECTION_SENT_TEXT)")
    }

    /// 제재 계산식은 **「약속 시간부터」**를 빼면 안 된다. 사용자가 노쇼로 찍힌 시각(= 누군가
    /// 출발을 누른 때)부터 센다고 읽으면 자기 제한이 언제 풀리는지 계산이 어긋난다.
    @Test("제재 계산식은 기준 시각과 24시간을 함께 말한다")
    func ruleTextNamesBaseAndDuration() {
        #expect(NO_SHOW_RULE_TEXT.contains("약속 시간부터"), "\(NO_SHOW_RULE_TEXT)")
        #expect(NO_SHOW_RULE_TEXT.contains("24시간"), "\(NO_SHOW_RULE_TEXT)")
        // 24시간 제한과 30일 만료는 다른 수다 — 한 문장에 넣으면 「30일 동안 못 쓴다」로 읽힌다.
        #expect(!NO_SHOW_RULE_TEXT.contains("30일"), "\(NO_SHOW_RULE_TEXT)")
        #expect(NO_SHOW_EXPIRY_TEXT.contains("30일"), "\(NO_SHOW_EXPIRY_TEXT)")
    }

    /// 서버가 **최신 20건에서 자르고** 커서를 주지 않는다. 아무 말도 없으면 사용자는 그 목록이
    /// 전부라고 읽는다 — 20건을 넘는 노쇼가 있는 사용자에게는 거짓이다. 「더 보기」는 달 수 없으니
    /// (누를 수 없는 버튼이 된다) **꽉 찼을 때만** 사실을 적는다.
    @Test("목록이 꽉 찼을 때만 전체가 아니라고 말한다")
    func capNoticeOnlyWhenFull() {
        #expect(noShowHistoryCapNotice(size: 0) == nil)
        #expect(noShowHistoryCapNotice(size: 19) == nil)
        #expect(noShowHistoryCapNotice(size: 20) == "최근 20건만 볼 수 있어요")
        // 서버가 상한을 넘겨 보내도 같은 말이 참이다.
        #expect(noShowHistoryCapNotice(size: 21) == "최근 20건만 볼 수 있어요")
    }

    /// 기록이 없는 사용자에게 겪지도 않은 제재를 설명하지 않는다 — 「없어요」까지가 사실이다.
    @Test("빈 목록 문구는 훈계하지 않는다")
    func emptyTextDoesNotLecture() {
        #expect(NO_SHOW_EMPTY_TEXT == "노쇼로 기록된 적이 없어요")
        for forbidden in ["24시간", "제한", "주의"] {
            #expect(!NO_SHOW_EMPTY_TEXT.contains(forbidden), "\(NO_SHOW_EMPTY_TEXT)")
        }
    }
}
