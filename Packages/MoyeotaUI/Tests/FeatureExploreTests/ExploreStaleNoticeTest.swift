@testable import FeatureExplore
import Testing

/// 17 탐색의 **낡은 목록 알림** 판정.
///
/// 왜 테스트가 필요한가: 고치기 전의 주기 갱신은 실패를 `runCatching{}.getOrNull() ?: continue` 로
/// **조용히 버렸다.** 목록을 남기는 판단 자체는 맞지만(지도를 통째로 에러 화면으로 바꾸지 않는다)
/// **연속 실패 상한이 없어** 낡은 마커가 영구히 남을 수 있었다 — 사용자는 이미 사라진 방의 「합류」를
/// 누르고 20 에서야 「사라진 방이에요」를 본다. 화면에는 아무 증상이 없어(목록이 멀쩡히 보인다)
/// 실기 QA 로도 드러나지 않는 종류의 결함이라, 판정을 순수 함수로 떼어 여기서 고정한다.
///
/// `ExplorePollGateTest` 와 같은 모양이다 — 루프는 판정 결과만 따르고, 무엇을 세는지와 임계값의 근거는
/// `STALE_NOTICE_FAILURES` 설명에 적혀 있다.
///
/// ### 카운트다운을 지도와 떼어 낸 뒤(2026-11, 오너 UX 피드백 2차)
/// 지도 이동은 더 이상 패스를 새로 열지 않는다. 그래서 카운터는 **무엇이 부른 조회든**(자동 갱신·지도 이동·버튼·
/// 복귀) 마지막 성공부터 이어 센다 — 지도 이동 실패는 「화면의 목록이 지금 보는 동네의 것이 아니다」라는 가장
/// 분명한 낡음이다. 실제 조회 순서로 센 결과는 `ExploreRefreshTest` 의 「지도 이동 조회의 실패와 자동 갱신의
/// 실패를 함께 센다」가 본다. 여기서는 판정과 그 시간 상한만 본다.
struct ExploreStaleNoticeTest {
    /// 한 번의 실패로는 알리지 않는다 — 터널·엘리베이터처럼 금방 복구되는 끊김이 흔하다.
    @Test("한 번 실패에는 알리지 않는다")
    func oneFailureDoesNotNotify() {
        #expect(!staleAfterPollFailures(consecutiveFailures: 0))
        #expect(!staleAfterPollFailures(consecutiveFailures: 1))
    }

    /// 연속 2회부터 알린다(자동 갱신만 실패하면 15초 주기 × 2 = 30초). 그 뒤로는 계속 알린 상태를 유지한다 —
    /// 복구될 때까지 사실이 그대로다.
    ///
    /// 4초 주기 시절에는 3회(12초)였다. 주기를 15초로 늘리며 같은 두 조건(「한 번의 끊김은 넘긴다」·
    /// 「1~2분 터널보다 짧다」)을 다시 맞춘 값이 2회다(`STALE_NOTICE_FAILURES` 설명의 표).
    @Test("연속 두 번 실패하면 알린다")
    func twoFailuresNotify() {
        #expect(staleAfterPollFailures(consecutiveFailures: 2))
        #expect(staleAfterPollFailures(consecutiveFailures: 3))
        #expect(staleAfterPollFailures(consecutiveFailures: 30))
    }

    /// 알리기까지 걸리는 시간이 터널 하나(약 1분)보다 짧다 — 진짜 끊김은 반드시 드러난다.
    ///
    /// 시계가 지도와 떨어진 뒤에도 상한은 같다: 보이는 동안 자동 갱신이 `NEARBY_POLL_INTERVAL_MS` 마다 **반드시**
    /// 한 번 읽으므로(지도 이동이 그 0 을 미루지 않는다) 첫 실패부터 길어야 15초 × 2 다. 지도 이동은 그 사이에
    /// 시도를 더할 뿐이라 알림을 앞당길 수는 있어도 늦추지 않는다.
    @Test("알리기까지 1분이 걸리지 않는다")
    func noticeWithinAMinute() {
        #expect(STALE_NOTICE_FAILURES * NEARBY_POLL_INTERVAL_MS < 60_000)
        #expect(STALE_NOTICE_FAILURES >= 2, "한 번의 실패만으로 알리면 일시 끊김마다 깜빡인다")
    }

    /// 임계값이 **상수 하나**로만 정해진다는 것 — 루프 쪽에 숫자가 흘러 들어가면 근거를 적어 둔
    /// 자리와 실제 동작이 갈린다.
    @Test("임계값은 상수가 정한다")
    func thresholdComesFromConstant() {
        #expect(STALE_NOTICE_FAILURES == 2)
        #expect(!staleAfterPollFailures(consecutiveFailures: STALE_NOTICE_FAILURES - 1))
        #expect(staleAfterPollFailures(consecutiveFailures: STALE_NOTICE_FAILURES))
    }

    /// **성공 한 번이 알림을 끈다**는 규약을 문서화한다. 카운터를 0 으로 되돌리는 건 호출부(루프)이고,
    /// 이 함수는 「지금까지 연속 몇 번」만 본다 — 되돌림을 깜빡하면 성공한 뒤에도 경고가 남는다.
    @Test("성공하면 카운터가 0 으로 돌아가 알림이 꺼진다")
    func successResetsNotice() {
        #expect(staleAfterPollFailures(consecutiveFailures: 5))
        #expect(!staleAfterPollFailures(consecutiveFailures: 0), "성공 뒤에도 경고가 남는다")
    }
}
