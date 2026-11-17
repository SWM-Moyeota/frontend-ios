@testable import FeatureMatching
import MoyeotaDomain
import Testing

/// 21 「그만 찾기」·「방 나가기」의 실패 안내.
///
/// 예전에는 모든 실패가 「방에서 나가지 못했어요」 하나였다. 그게 특히 나쁜 까닭은 **이미 나간
/// 상태가 영구 실패로 보였다**는 것이다: 서버가 204 로 처리했는데 응답이 유실되면(터널·타임아웃)
/// 앱은 그 문구를 띄우고, 다시 누르면 403 `NOT_PARTY_MEMBER` → **같은 문구**다. 로컬 기억과 홈 배너는
/// 그 방을 계속 들고 있으니 화면상 나는 아직 그 방에 있고, 벗어날 길이 없다.
///
/// 그래서 **그 403 은 이 함수에 오지 않는다** — 데이터 계층이 성공으로 되돌려 나가기 성공과 같은
/// 길(홈)로 보낸다(`RemoteRideRepository.leaveParty`, 합류의 409 복구와 대칭).
///
/// ### 🔴 두 409 의 이름과 뜻이 바뀌었다 (2026-11-12) ★
/// | 옛 코드 | 지금 | 사용자 문구가 바뀌었나 |
/// |---|---|---|
/// | `PARTY_NOT_RECRUITING` | `PARTY_CLOSED` | **아니다** — 어느 이름이든 「이미 끝난 방」이다 |
/// | `CANNOT_LEAVE_CONFIRMED_PARTY` | `ARRIVED_MEMBER_CANNOT_LEAVE` | **그렇다** — 막는 사유 자체가 달라졌다 |
///
/// 둘째 줄이 본체다. 「약속이 정해진 방은 나갈 수 없다」를 **서버가 버렸고**(`b16551b7`), 지금 막는
/// 것은 **내가 도착을 눌렀는가**다. 그래서 문구가 「약속 시간에 출발지에서 만나 주세요」에서
/// 「방장이 출발하면 방이 끝나요」로 바뀐다 — 그 사람은 **이미 출발지에 서 있다.**
struct LeaveFailureMessageTest {
    private func failure(_ code: String?, httpStatus: Int? = 409) -> PartyLeaveException {
        PartyLeaveException(code: code, serverMessage: nil, httpStatus: httpStatus)
    }

    /// 409 `PARTY_CLOSED` — 이미 닫힌 방이다. **「잠시 후 다시」를 붙이지 않는다**: 닫힌 방이 다시
    /// 열리는 길이 없어 다시 눌러도 같은 409 다. 대신 **왜** 못 나가는지 말한다.
    ///
    /// 코드 이름이 `PARTY_NOT_RECRUITING` 이었다 — 서버가 `Party` 의 단계 검사를 `validateOpen()`
    /// 하나로 묶으면서 통일했다(`b16551b7`). **사용자 문구는 그대로다**: 어느 이름이든 사실은
    /// 「이미 끝난 방」이고, 그 전에 쓰였던 「매칭이 시작돼 지금은 나갈 수 없어요」는 기사·배차가
    /// 있던 시절 이야기라 이미 지워져 있었다.
    @Test("닫힌 방이면 왜 못 나가는지 말한다")
    func partyClosed() {
        let message = leaveFailureMessage(e: failure(PartyLeaveException.PARTY_CLOSED))

        #expect(message == "이미 끝난 방이에요. 홈으로 돌아가 주세요")
    }

    /// 🔴 409 `ARRIVED_MEMBER_CANNOT_LEAVE` — **내가 출발지 도착을 눌렀다.**
    ///
    /// 예전 이 자리는 `CANNOT_LEAVE_CONFIRMED_PARTY`(「약속이 정해진 방이다」)였고 문구는 「약속
    /// 시간에 출발지에서 만나 주세요」였다. 서버가 그 규칙과 코드를 **함께 지웠다**(`b16551b7`) —
    /// 확정은 나가기를 막지 않고, **도착**이 막는다(도착한 멤버가 곧 탑승자이고 택시비 정산
    /// 대상이라 장부에서 빠질 수 없다). 그래서 할 말이 달라진다: 그 사람은 **이미 출발지에 서 있다.**
    ///
    /// 못 박는 것: **`PartyLeaveException.PARTY_CLOSED` 와 다른 말을 한다.** 같은 409 지만 그쪽은
    /// 이미 끝난 방이라 홈으로 보내는 게 맞고, 이쪽은 **아직 살아 있고 내가 묶인 방**이다 — 홈으로
    /// 돌아가라고 하면 약속 장소에 서 있는 사람을 떠나게 만들고, 그러면 그 사람이 탑승 기록·정산에서
    /// 빠진다. 되돌릴 길이 없으므로(도착 취소 API 가 없다) 할 수 있는 말은 **무엇을 기다리면
    /// 되는가**뿐이다.
    @Test("도착을 누른 뒤의 409 는 끝난 방과 다른 말을 한다")
    func arrivedMemberCannotLeave() {
        let arrived = leaveFailureMessage(e: failure(PartyLeaveException.ARRIVED_MEMBER_CANNOT_LEAVE))

        #expect(arrived == "도착을 알린 뒤에는 나갈 수 없어요. 방장이 출발하면 방이 끝나요")
        #expect(
            leaveFailureMessage(e: failure(PartyLeaveException.PARTY_CLOSED)) != arrived,
            "끝난 방과 도착해 묶인 방을 같은 문구로 뭉갰다 — 전자는 떠나야 하고 후자는 머물러야 한다"
        )
    }

    @Test("사라진 방 - 코드가 없는 404 도 같게 다룬다")
    func partyNotFound() {
        let expected = "이미 사라진 방이에요. 홈으로 돌아가 주세요"

        #expect(leaveFailureMessage(e: failure(PartyLeaveException.PARTY_NOT_FOUND, httpStatus: 404)) == expected)
        #expect(leaveFailureMessage(e: failure(nil, httpStatus: 404)) == expected)
    }

    /// 모르는 코드·네트워크 실패는 일반 문구다 — 서버가 `MatchingErrorCode` 를 늘려도 앱이 틀린 말을
    /// 하지 않는다(409 라고 「매칭이 시작됐어요」로 **추측하지 않는다**).
    @Test("모르는 코드와 네트워크 실패는 일반 문구로 떨어진다")
    func unknownCode() {
        let general = "방에서 나가지 못했어요"

        #expect(leaveFailureMessage(e: failure("PARTY_SOMETHING_NEW")) == general)
        #expect(leaveFailureMessage(e: failure(nil, httpStatus: nil)) == general)
        #expect(leaveFailureMessage(e: failure(nil, httpStatus: 409)) == general)
        #expect(leaveFailureMessage(e: failure(nil, httpStatus: 500)) == general)
    }

    /// **403 이 일반 문구로 떨어지는 것 자체는 괜찮다** — 거기까지 오지 않는 것이 계약이기 때문이다
    /// (데이터 계층이 성공으로 되돌린다). 혹시 되돌림이 빠져 올라오더라도 「매칭이 시작됐어요」 같은
    /// 거짓말은 하지 않는다는 것만 못 박는다.
    @Test("멤버 아님 403 은 사유를 지어내지 않는다")
    func notMember() {
        let message = leaveFailureMessage(e: failure(PartyLeaveException.NOT_PARTY_MEMBER, httpStatus: 403))

        #expect(message == "방에서 나가지 못했어요")
    }

    @Test("실패마다 다른 말을 한다")
    func distinctMessages() {
        let messages = [
            failure(PartyLeaveException.PARTY_CLOSED),
            failure(PartyLeaveException.ARRIVED_MEMBER_CANNOT_LEAVE),
            failure(PartyLeaveException.PARTY_NOT_FOUND, httpStatus: 404),
            failure(nil, httpStatus: nil),
        ].map { leaveFailureMessage(e: $0) }

        #expect(Set(messages).count == messages.count)
    }
}
