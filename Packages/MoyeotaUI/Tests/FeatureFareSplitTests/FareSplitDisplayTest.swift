import Foundation
import MoyeotaDomain
import PresentationCore
import Testing
@testable import FeatureFareSplit

/// 정산 화면의 **표기와 하지 않는 약속들**.
///
/// 이 테스트의 절반은 「무엇이 보이는가」가 아니라 **「무엇을 말하지 않는가」**다. 이 저장소는 거짓
/// 문구 19건을 들어낸 이력이 있고(`ProductClaimsTest`), 돈이 움직이는 화면에서 지어낸 사실은
/// 오해가 아니라 **되돌릴 수 없는 송금**으로 이어진다.
@Suite struct FareSplitDisplayTest {

    // ─────────────────── 금액·이름 ───────────────────

    @Test("금액은 세 자리마다 끊어 원을 붙인다")
    func wonLabel() {
        #expect(fareWonLabel(amount: 18_700) == "18,700원")
        #expect(fareWonLabel(amount: 0) == "0원")
        #expect(fareWonLabel(amount: 1_234_567) == "1,234,567원")
        #expect(fareWonLabel(amount: 999) == "999원")
    }

    @Test("이름이 비어 있으면 자리값을 쓴다")
    func blankNameFallsBack() {
        #expect(FareSplitParticipant(publicId: "", nickname: "").displayName == WithdrawnMemberNames.NO_SUMMARY)
        #expect(FareSplitParticipant(publicId: PAYER_ID, nickname: "방장").displayName == "방장")
        // 서버가 직접 넣은 「탈퇴한 사용자」는 **그대로 쓴다** — publicId 가 살아 있어 부를 수 있다.
        #expect(transfer(SENDER_A, WithdrawnMemberNames.SERVER_DELETED).displayName == WithdrawnMemberNames.SERVER_DELETED)
    }

    // ─────────────────── 가린 실명 ───────────────────

    /// 쓸모가 화면에서 읽혀야 한다 — 은행 앱 입금 내역과 맞춰 보는 용도다.
    @Test("가린 실명은 입금자명으로 보여 주고 그 쓸모를 적는다")
    func depositorHint() {
        #expect(depositorHintOrNull(transfer: transfer(maskedRealName: "홍*동")) == "입금자명 홍*동")
        #expect(DEPOSITOR_HINT_PURPOSE.contains("입금 내역"))
    }

    /// 보내는 사람에게는 **늘 nil** 이고 그게 정상이다 — 「실명이 없는 사용자」가 아니다.
    @Test("가린 실명이 없으면 입금자명 칸을 만들지 않는다")
    func noDepositorHintWithoutName() {
        #expect(depositorHintOrNull(transfer: transfer(maskedRealName: nil)) == nil)
        #expect(depositorHintOrNull(transfer: transfer(maskedRealName: "  ")) == nil)
    }

    // ─────────────────── 상태 표기 ───────────────────

    /// COMPLETED 와 EXPIRED 를 **같은 톤·같은 문구로 뭉개지 않는다.** 뭉개면 만료된 정산을 본 사람이
    /// 「정산이 끝났다」로 읽고 자기 몫을 영영 보내지 않는다 — 다시 시작하는 길은 없다.
    @Test("정산 완료와 기간 지남은 글자도 톤도 다르다")
    func completedAndExpiredDiffer() {
        let done = fareSplitBadge(status: .completed)
        let expired = fareSplitBadge(status: .expired)

        #expect(done.label != expired.label)
        #expect(done.tone != expired.tone)
        #expect(done.tone == .done)
        #expect(expired.tone == .warn)
    }

    @Test("기간이 지난 정산을 끝났다고 말하지 않는다")
    func expiredIsNotDone() throws {
        let notice = try #require(fareSplitStatusNotice(status: .expired))

        #expect(!notice.contains("정산이 끝났"))
        // 돈을 옮기는 길은 앱 밖에 있다 — 남은 수단을 가리킨다.
        #expect(notice.contains("채팅"))
    }

    @Test("진행 중인 정산에는 상태 설명을 붙이지 않는다")
    func openHasNoNotice() {
        #expect(fareSplitStatusNotice(status: .open) == nil)
    }

    /// ### 만료 경계는 「1일」이 아니라 「1일 + 최대 30분」이다 ★
    /// 서버 스윕이 30분 cron 이라 24시간 1분이 지난 정산이 열려 있는 것도, 24시간 29분에 닫히는 것도
    /// 정상이다. 분 단위 약속을 하면 **어느 모습도 화면과 맞지 않는다.**
    @Test("만료 안내는 정확한 시각을 약속하지 않는다")
    func expiryNoticeMakesNoExactPromise() {
        #expect(EXPIRY_NOTICE.contains("하루"))
        #expect(EXPIRY_NOTICE.contains("늦을 수 있"))
        for forbidden in ["24시간", "분 뒤", "오늘까지", "자정", "정확히"] {
            #expect(!EXPIRY_NOTICE.contains(forbidden), "만료 안내가 「\(forbidden)」을 약속하면 안 된다")
        }
    }

    /// 서버가 아는 것은 **버튼이 눌렸다**는 사실뿐이다. 「입금됨」으로 적으면 은행 앱을 안 보고 확인한다.
    @Test("보냈다고 알린 상태를 입금됨이라고 적지 않는다")
    func sentIsNotDeposited() {
        let sent = transferStatusLabel(status: .sent)

        #expect(sent.label == "보냈다고 알림")
        #expect(!sent.label.contains("입금"))
    }

    @Test("세 송금 상태의 글자가 서로 다르다")
    func transferLabelsAreDistinct() {
        let labels = TransferStatus.allCases.map { transferStatusLabel(status: $0).label }

        #expect(labels.count == Set(labels).count)
    }

    @Test("앱이 돈을 옮기지 않는다는 사실을 적는다")
    func appDoesNotMoveMoney() {
        #expect(APP_DOES_NOT_MOVE_MONEY.contains("돈을 옮기지 않아요"))
    }

    // ─────────────────── 받는 사람 요약 ───────────────────

    @Test("받을 돈은 보내는 사람들의 합이고 내 부담은 빠져 있다")
    func payerSummary() {
        let summary = payerSummaryOf(detail: detail())

        #expect(summary.totalFare == 18_700)
        #expect(summary.myAmount == 6_234)
        #expect(summary.toReceive == 12_466)
    }

    /// SENT 는 **아직 못 받은 돈**이다 — 눌렸다는 사실이 입금을 뜻하지 않는다.
    @Test("보냈다고 알린 금액도 아직 못 받은 돈으로 센다")
    func sentCountsAsOutstanding() {
        let summary = payerSummaryOf(
            detail: detail(transfers: [
                transfer(SENDER_A, "동승자A", 6_233, status: .sent),
                transfer(SENDER_B, "동승자B", 6_233, status: .confirmed),
            ])
        )

        #expect(summary.outstanding == 6_233)
        #expect(summary.confirmedCount == 1)
        #expect(confirmedProgressLabel(summary: summary) == "2명 중 1명 확인")
    }

    /// ### 금액은 1/N 이 아니다 ★
    /// 방장이 사람마다 적은 값이라 **같은 방을 보는 두 사람이 다른 값을 본다**(백엔드 `fe6ba35a`).
    /// 「1인당 N원」이라고 단정하는 문구가 이 화면에 들어오면 안 된다.
    @Test("어느 문구도 1인당 금액이라고 단정하지 않는다")
    func noPerPersonClaims() {
        var everyCopy = [
            APP_DOES_NOT_MOVE_MONEY,
            EXPIRY_NOTICE,
            DEPOSITOR_HINT_PURPOSE,
            TOSS_OPEN_FAILED_NOTICE,
            START_IRREVERSIBLE_NOTICE,
        ]
        everyCopy += FareSplitStatus.allCases.map { fareSplitBadge(status: $0).label }
        everyCopy += FareSplitStatus.allCases.compactMap { fareSplitStatusNotice(status: $0) }
        everyCopy += TransferStatus.allCases.map { transferStatusLabel(status: $0).label }
        everyCopy += SenderStage.allCases.compactMap { senderStageNotice(stage: $0) }
        everyCopy += FareSplitAction.allCases.map { fareSplitGenericFailure(action: $0) }
        everyCopy += FareSplitSubmitBlock.allCases.compactMap { submitBlockMessage(block: $0) }
        everyCopy.append(confirmedProgressLabel(summary: payerSummaryOf(detail: detail())))

        for copy in everyCopy {
            for forbidden in ["1인당", "1/N", "똑같이 나눠", "n분의 1"] {
                #expect(!copy.contains(forbidden), "「\(forbidden)」이라고 단정하면 안 된다: \(copy)")
            }
        }
    }

    /// 멱등 204 는 「이미 그 상태였다」와 「지금 바뀌었다」를 구분할 수 없다 — 「이미 보냈습니다」류를
    /// 지어내면 **틀릴 수 있다.** 어느 문구에도 없어야 한다.
    @Test("이미 그 상태였다고 지어내는 문구가 없다")
    func noFabricatedAlreadyClaims() {
        var everyCopy = SenderStage.allCases.compactMap { senderStageNotice(stage: $0) }
        everyCopy += FareSplitStatus.allCases.compactMap { fareSplitStatusNotice(status: $0) }
        everyCopy += FareSplitAction.allCases.map { fareSplitGenericFailure(action: $0) }

        for copy in everyCopy {
            for forbidden in ["이미 보냈", "이미 알렸", "이미 확인했어요"] {
                #expect(!copy.contains(forbidden), "「\(forbidden)」은 서버 응답으로 알 수 없는 사실이다: \(copy)")
            }
        }
    }

    // ─────────────────── 보내는 사람 안내 ───────────────────

    @Test("보낼 단계에는 안내 대신 버튼이 말한다")
    func sendReadyHasNoNotice() {
        #expect(senderStageNotice(stage: .sendReady) == nil)
    }

    /// 닫힌 정산의 설명은 상태 문구가 **COMPLETED 와 EXPIRED 를 갈라서** 한다 — 여기서 또 적지 않는다.
    @Test("닫힌 단계의 안내는 상태 문구에 맡긴다")
    func closedStageDefersToStatus() {
        #expect(senderStageNotice(stage: .closed) == nil)
    }

    @Test("막힌 단계는 위험 톤이다")
    func blockedStagesAreDanger() {
        #expect(senderStageTone(stage: .accountLost) == .danger)
        #expect(senderStageTone(stage: .unknownMyTransfer) == .danger)
        #expect(senderStageTone(stage: .confirmed) == .done)
    }

    /// 토스 실패는 「오류」가 아니라 **이미 아래에 있는 길**을 가리킨다(서버 주석의 근거 그대로).
    @Test("토스 실패 안내는 복사 버튼을 가리킨다")
    func tossFailurePointsToCopy() {
        #expect(TOSS_OPEN_FAILED_NOTICE.contains("복사"))
        #expect(TOSS_OPEN_FAILED_NOTICE.contains("은행 앱"))
    }

    // ─────────────────── 진입 판정 (PresentationCore) ───────────────────

    @Test("끝난 방에서 도착을 누른 사람만 정산 화면을 열 수 있다")
    func entryGate() {
        #expect(canOpenFareSplit(ride: ride()))
        // 아직 끝나지 않은 방
        #expect(!canOpenFareSplit(ride: ride(status: .confirmed)))
        // 도착을 누르지 않았다 = 탑승자가 아니다 → 상세는 403 NOT_FARE_SPLIT_PARTICIPANT 다
        #expect(
            !canOpenFareSplit(
                ride: ride(members: [
                    member(PAYER_ID, "방장", isHost: true),
                    member(SENDER_A, "나", isMe: true, arrived: false),
                ])
            )
        )
    }

    /// 방장이 누르는 버튼은 **만드는** 버튼이고 나머지가 누르는 버튼은 **보는** 버튼이다.
    @Test("진입점 글자가 방장과 그 밖으로 갈린다")
    func entryLabelByRole() {
        #expect(fareSplitEntryLabel(ride: ride()) == "택시비 정산하기")

        let asSender = ride(members: [
            member(PAYER_ID, "방장", isHost: true),
            member(SENDER_A, "나", isMe: true),
        ])
        #expect(fareSplitEntryLabel(ride: asSender) == "내 택시비 보내기")
    }

    @Test("갈 수 없으면 진입점을 그리지 않는다")
    func noEntryWhenClosedOff() {
        #expect(fareSplitEntryLabel(ride: ride(status: .canceled)) == nil)
    }

    // ─────────────────── 홈 배너 ───────────────────

    @Test("배너 경로는 있는 쪽만 적고 둘 다 없으면 줄을 만들지 않는다")
    func bannerRouteLabel() {
        #expect(myFareSplitRouteLabel(item: myFareSplit()) == "센텀시티역 → 서면역")
        #expect(myFareSplitRouteLabel(item: myFareSplit(destination: nil)) == "센텀시티역")
        #expect(myFareSplitRouteLabel(item: myFareSplit(departure: nil)) == "서면역")
        // 방이 지워지면 서버가 둘을 **함께** nil 로 준다 — 자리값을 넣지 않는다.
        #expect(myFareSplitRouteLabel(item: myFareSplit(departure: nil, destination: nil)) == nil)
        #expect(myFareSplitRouteLabel(item: myFareSplit(departure: "  ", destination: "")) == nil)
    }

    @Test("잠긴 행에는 이유가 있고 열린 행에는 없다")
    func lockReasonOnlyWhenLocked() {
        let sent = transfer(status: .sent)
        #expect(transferActionsOf(detail: detail(transfers: [sent]), transfer: sent).lockReason == nil)

        let anonymous = transfer("", status: .sent)
        #expect(transferActionsOf(detail: detail(transfers: [anonymous]), transfer: anonymous).lockReason != nil)
    }

    // ─────────────────── 복사 토스트 (iOS) ───────────────────

    /// 토스트에 **값을 넣지 않는다** — 계좌번호가 화면 아래 토스트와 VoiceOver 로 한 번 더 읽힌다.
    /// 그리고 실패를 「복사했어요」로 덮지 않는다(붙여넣기가 비어 있는 것이 최악이다).
    @Test("복사 확인 문구는 무엇을 복사했는지만 말하고 실패를 숨기지 않는다")
    func copyToastCopy() {
        #expect(copyToastMessage(target: .accountNumber, copied: true) == "계좌번호를 복사했어요")
        #expect(copyToastMessage(target: .amount, copied: true) == "금액을 복사했어요")
        #expect(copyToastMessage(target: .accountNumber, copied: false) == "복사하지 못했어요")
        #expect(copyToastMessage(target: .amount, copied: false) == "복사하지 못했어요")
    }
}
