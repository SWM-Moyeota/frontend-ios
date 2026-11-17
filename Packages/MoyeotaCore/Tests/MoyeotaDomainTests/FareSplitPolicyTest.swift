import Foundation
import Testing
@testable import MoyeotaDomain

/// 서버가 **앱에 맡긴 두 가지**를 못 박는다 — 1/N 미리 채우기와 계좌번호 정규화.
///
/// 서버는 금액을 **검사만** 한다(「1/N 로 미리 채우는 것은 앱이 한다」 — Swagger 원문). 즉 나누는
/// 규칙이 앱에만 있어서, 규칙이 흔들리면 **같은 택시비·같은 인원인데 화면마다 다른 금액**이 뜨고
/// 서버는 그중 합이 맞는 것만 받는다. 그 흔들림을 컴파일러가 못 잡으므로 여기서 고정한다.
@Suite struct FareSplitPolicyTest {
    private let payer = "11111111-1111-1111-1111-111111111111"
    private let senderA = "22222222-2222-2222-2222-222222222222"
    private let senderB = "33333333-3333-3333-3333-333333333333"

    // ─── 1원 배분 ───

    /// **이 테스트가 1원 배분 규칙의 정의다.** 18,700원 / 3명 = 몫 6,233원 + 나머지 1원이고,
    /// 그 1원은 **받는 사람(방장)** 이 가져간다 — 보내는 사람끼리는 금액이 **같아야** 하기 때문이다
    /// (「왜 나만 1원 더 내나」를 설명할 방법이 없다).
    @Test("18700원을 3명이 나누면 방장이 1원을 더 낸다")
    func payerAbsorbsRemainder() throws {
        let shares = try FareSplitPolicy.splitEvenly(
            totalFare: 18_700, payerPublicId: payer, riderPublicIds: [payer, senderA, senderB]
        )

        #expect(
            shares == [
                FareShare(riderPublicId: payer, amount: 6_234),
                FareShare(riderPublicId: senderA, amount: 6_233),
                FareShare(riderPublicId: senderB, amount: 6_233),
            ]
        )
        #expect(
            shares.map(\.amount).reduce(0, +) == 18_700,
            "합이 택시비와 달라지면 서버가 400 PAYMENTS_NOT_EQUAL_FARE 로 막는다"
        )
    }

    /// 나머지가 0이면 아무도 더 내지 않는다 — 「방장이 흡수」가 **늘 +1** 이 아니라는 확인이다.
    @Test("나누어떨어지면 전원이 같은 금액이다")
    func evenSplitIsEqual() throws {
        let shares = try FareSplitPolicy.splitEvenly(
            totalFare: 18_000, payerPublicId: payer, riderPublicIds: [payer, senderA, senderB]
        )

        #expect(shares.map(\.amount) == [6_000, 6_000, 6_000])
    }

    /// 나머지는 최대 `인원 - 1` 원이고 **전부** 방장이 가져간다(둘로 쪼개 흩지 않는다).
    @Test("나머지가 2원이면 방장이 2원을 전부 가져간다")
    func payerTakesWholeRemainder() throws {
        let shares = try FareSplitPolicy.splitEvenly(
            totalFare: 18_701, payerPublicId: payer, riderPublicIds: [payer, senderA, senderB]
        )

        #expect(shares.filter { $0.riderPublicId == payer }.map(\.amount) == [6_235])
        #expect(shares.filter { $0.riderPublicId != payer }.map(\.amount) == [6_233, 6_233])
    }

    /// **결정론의 핵심.** 「목록 앞쪽부터 1원씩」으로 정했다면 이 테스트가 깨진다 — 앱이 멤버 목록을
    /// 어디서 받았는지(방 상세·SSE·목록)에 따라 순서가 달라질 수 있어 **같은 입력에 다른 금액**이
    /// 나온다. 방장 기준은 정산마다 정확히 한 명이라 순서와 무관하다.
    @Test("탑승자 순서를 바꿔도 사람마다 금액이 같다")
    func orderDoesNotChangeAmounts() throws {
        let a = try FareSplitPolicy.splitEvenly(totalFare: 18_700, payerPublicId: payer, riderPublicIds: [payer, senderA, senderB])
        let b = try FareSplitPolicy.splitEvenly(totalFare: 18_700, payerPublicId: payer, riderPublicIds: [senderB, payer, senderA])

        #expect(
            Dictionary(uniqueKeysWithValues: a.map { ($0.riderPublicId, $0.amount) })
                == Dictionary(uniqueKeysWithValues: b.map { ($0.riderPublicId, $0.amount) })
        )
        // 돌려주는 순서는 넘긴 순서를 따른다 — 화면이 방 화면과 같은 순서로 그릴 수 있게.
        #expect(b.map(\.riderPublicId) == [senderB, payer, senderA])
    }

    /// 서버가 거절할 금액 조합이 **하나도** 만들어지지 않는지 범위로 훑는다
    /// (합 == 택시비, 전원 1원 이상). 한 건씩 고정하는 것보다 이쪽이 규칙을 바꿀 때 먼저 깨진다.
    @Test("어떤 택시비와 인원이어도 합이 택시비와 같고 전원이 1원 이상이다")
    func everySplitIsServerValid() throws {
        let riders = [payer, senderA, senderB, "44444444-4444-4444-4444-444444444444"]

        for count in FareSplitPolicy.MIN_RIDERS...riders.count {
            let target = Array(riders.prefix(count))
            for fare in count...(count + 40) {
                let shares = try FareSplitPolicy.splitEvenly(totalFare: fare, payerPublicId: payer, riderPublicIds: target)

                #expect(shares.map(\.amount).reduce(0, +) == fare, "\(fare) 원 / \(count)명 의 합이 어긋났다")
                #expect(
                    shares.allSatisfy { $0.amount >= FareSplitPolicy.MIN_SHARE },
                    "\(fare) 원 / \(count)명 에 1원 미만이 생겼다"
                )
                #expect(shares.count == count)
            }
        }
    }

    /// 택시비가 인원보다 적으면 **누군가 0원**이 되어 서버가 400 으로 막는다. 실제 기본요금에서는
    /// 일어나지 않지만 **사용자가 금액을 직접 입력**하므로 「2」를 넣을 수 있다 — 그때 앱이 터지지
    /// 않고 「택시비를 다시 확인해 주세요」로 끝내게 하는 것이 `FareSplitPolicy.canSplitEvenly` 다.
    @Test("택시비가 인원보다 적으면 나눌 수 없다")
    func fareBelowRiderCountCannotSplit() {
        #expect(!FareSplitPolicy.canSplitEvenly(totalFare: 2, riderCount: 3))
        #expect(FareSplitPolicy.canSplitEvenly(totalFare: 3, riderCount: 3))
        #expect(throws: IllegalArgumentException.self) {
            try FareSplitPolicy.splitEvenly(totalFare: 2, payerPublicId: payer, riderPublicIds: [payer, senderA, senderB])
        }
    }

    /// 혼자 탄 방은 나눌 상대가 없다 — 서버도 409 `NOT_ENOUGH_RIDERS` 로 막는다.
    @Test("탑승자가 혼자면 나눌 수 없다")
    func singleRiderCannotSplit() {
        #expect(!FareSplitPolicy.canSplitEvenly(totalFare: 10_000, riderCount: 1))
        #expect(throws: IllegalArgumentException.self) {
            try FareSplitPolicy.splitEvenly(totalFare: 10_000, payerPublicId: payer, riderPublicIds: [payer])
        }
    }

    /// 방장이 탑승자 목록에 없으면 **나머지를 얹을 사람이 없다** — 조용히 아무에게나 얹으면
    /// 보내는 사람의 금액이 달라지고, 그게 어느 화면에서 나온 값인지 추적할 수 없게 된다.
    /// (서버도 그 방을 403 `NOT_A_RIDER` 로 막는다.)
    @Test("방장이 탑승자 목록에 없으면 거절한다")
    func payerMustBeRider() {
        #expect(throws: IllegalArgumentException.self) {
            try FareSplitPolicy.splitEvenly(totalFare: 18_700, payerPublicId: payer, riderPublicIds: [senderA, senderB])
        }
    }

    /// 중복·빈 publicId 는 **서버가 400 `PAYMENT_TARGET_MISMATCH` 로 막는 조합**이다. 앱이 먼저
    /// 거절하는 이유: 그 400 은 「빠졌다」·「아니다」·「두 번 있다」 세 경우가 **같은 코드**라
    /// 서버 응답만으로는 원인을 알 수 없다.
    @Test("중복이나 빈 publicId 가 섞이면 거절한다")
    func duplicateOrBlankIdsAreRejected() {
        #expect(throws: IllegalArgumentException.self) {
            try FareSplitPolicy.splitEvenly(totalFare: 18_700, payerPublicId: payer, riderPublicIds: [payer, senderA, senderA])
        }
        #expect(throws: IllegalArgumentException.self) {
            try FareSplitPolicy.splitEvenly(totalFare: 18_700, payerPublicId: payer, riderPublicIds: [payer, senderA, ""])
        }
    }

    // ─── 계좌번호 ───

    /// 사용자는 은행 앱이 복사해 준 모양(`3333-01-2345678`)을 그대로 붙여넣는다.
    @Test("하이픈과 공백을 뗀 숫자만 서버로 나간다")
    func stripsHyphensAndWhitespace() {
        #expect(FareSplitPolicy.normalizeAccountNumber(raw: "3333-01-2345678") == "3333012345678")
        #expect(FareSplitPolicy.normalizeAccountNumber(raw: " 3333 01 2345678 ") == "3333012345678")
        #expect(FareSplitPolicy.isAccountNumberValid(raw: "3333-01-2345678"))
    }

    /// **숫자가 아닌 문자를 전부 지우지 않는다.** 지우면 「3333.01.2345678」이 조용히 통과해,
    /// 사용자가 확인하지 않은 계좌번호로 송금 안내가 나간다 — 송금은 앱이 아니라 사용자가 직접
    /// 하므로 **앱이 고친 값이 틀려도 되돌릴 수 없다.** 틀렸다고 말하는 쪽이 맞다.
    @Test("하이픈 공백이 아닌 문자가 남으면 거절한다")
    func otherCharactersAreRejected() {
        #expect(FareSplitPolicy.normalizeAccountNumber(raw: "3333.01.2345678") == "3333.01.2345678")
        #expect(!FareSplitPolicy.isAccountNumberValid(raw: "3333.01.2345678"))
        #expect(!FareSplitPolicy.isAccountNumberValid(raw: "3333012345678(국민)"))
    }

    /// 서버 `AccountNumber` 와 **같은 자릿수**다 — 어기면 400 `INVALID_ACCOUNT_NUMBER`.
    @Test("숫자 10자리 미만과 16자리 초과를 거절한다")
    func digitCountBounds() {
        #expect(!FareSplitPolicy.isAccountNumberValid(raw: String(repeating: "1", count: 9)))
        #expect(FareSplitPolicy.isAccountNumberValid(raw: String(repeating: "1", count: 10)))
        #expect(FareSplitPolicy.isAccountNumberValid(raw: String(repeating: "1", count: 16)))
        #expect(!FareSplitPolicy.isAccountNumberValid(raw: String(repeating: "1", count: 17)))
        #expect(!FareSplitPolicy.isAccountNumberValid(raw: ""))
        // 하이픈을 떼고 나서 센다 — 「110-123-456789」는 12자리다
        #expect(FareSplitPolicy.isAccountNumberValid(raw: "110-123-456789"))
    }

    // ─── 보내기 전 사전 검증 ───

    /// 수정 화면에서 받는 사람이 금액을 손으로 고치면 합이 가장 쉽게 어긋난다. 그 실패
    /// (400 `PAYMENTS_NOT_EQUAL_FARE`)는 **입력을 다 끝낸 뒤에** 오므로 앱이 먼저 잡는다.
    @Test("합이 택시비와 다르면 보내지 않는다")
    func sumMismatchIsCaught() {
        let problem = FareSplitPolicy.problemOf(
            totalFare: 18_700,
            riderPublicIds: [payer, senderA, senderB],
            shares: [
                FareShare(riderPublicId: payer, amount: 6_233),
                FareShare(riderPublicId: senderA, amount: 6_233),
                FareShare(riderPublicId: senderB, amount: 6_233),
            ]
        )

        #expect(problem == .sumNotEqualFare)
    }

    /// 탑승자가 어긋난 것과 합이 어긋난 것은 **처방이 정반대**다 — 앞은 금액을 아무리 고쳐도 풀리지
    /// 않고(방 상세를 다시 받아야 한다) 뒤는 금액 칸을 고치면 풀린다. 그래서 한 값으로 뭉치지 않는다.
    @Test("탑승자가 빠지거나 끼면 금액과 다른 문제로 가른다")
    func targetMismatchIsSeparate() {
        let missing = FareSplitPolicy.problemOf(
            totalFare: 12_466,
            riderPublicIds: [payer, senderA, senderB],
            shares: [FareShare(riderPublicId: payer, amount: 6_233), FareShare(riderPublicId: senderA, amount: 6_233)]
        )
        #expect(missing == .targetMismatch)

        let stranger = FareSplitPolicy.problemOf(
            totalFare: 18_699,
            riderPublicIds: [payer, senderA, senderB],
            shares: [
                FareShare(riderPublicId: payer, amount: 6_233),
                FareShare(riderPublicId: senderA, amount: 6_233),
                FareShare(riderPublicId: "99999999-9999-9999-9999-999999999999", amount: 6_233),
            ]
        )
        #expect(stranger == .targetMismatch)
    }

    /// 서버 `FarePayment` 는 0원 이하를 거절한다. 0원 칸은 사용자가 비워 둔 칸의 모양이다.
    @Test("1원 미만인 금액이 있으면 보내지 않는다")
    func shareBelowMinimumIsCaught() {
        let problem = FareSplitPolicy.problemOf(
            totalFare: 12_466,
            riderPublicIds: [payer, senderA, senderB],
            shares: [
                FareShare(riderPublicId: payer, amount: 12_466),
                FareShare(riderPublicId: senderA, amount: 0),
                FareShare(riderPublicId: senderB, amount: 0),
            ]
        )

        #expect(problem == .shareBelowMinimum)
    }

    /// publicId 가 빈 탑승자는 **지목할 수 없다** — 서버 `riderIds` 에는 들어 있으므로 조용히 빼면
    /// 탑승자가 하나 모자란 요청이 되어 같은 400 을 받는다. 정산을 시작할 수 없는 상태임을
    /// 화면에 알려야 한다.
    @Test("publicId 가 없는 탑승자가 있으면 지목할 수 없다고 알린다")
    func unidentifiedRiderIsReported() {
        let problem = FareSplitPolicy.problemOf(
            totalFare: 10_000,
            riderPublicIds: [payer, ""],
            shares: [FareShare(riderPublicId: payer, amount: 5_000), FareShare(riderPublicId: "", amount: 5_000)]
        )

        #expect(problem == .riderNotIdentified)
    }

    /// 1/N 결과는 **늘** 문제가 없다 — 두 함수가 같은 규칙을 보고 있는지 묶어 두는 테스트다.
    @Test("1 N 으로 채운 결과에는 보낼 수 없는 이유가 없다")
    func evenSplitHasNoProblem() throws {
        let riders = [payer, senderA, senderB]

        for fare in 3...60 {
            let shares = try FareSplitPolicy.splitEvenly(totalFare: fare, payerPublicId: payer, riderPublicIds: riders)
            #expect(
                FareSplitPolicy.problemOf(totalFare: fare, riderPublicIds: riders, shares: shares) == nil,
                "\(fare) 원이 사전 검증에 걸렸다"
            )
        }
    }

    // ─── 정산 대상 고르기 ───

    /// **정산 대상은 방 멤버 전원이 아니다** — 출발지 도착을 누른 사람(서버 `riderIds`)만이다.
    /// 멤버 전원으로 채우면 400 `PAYMENT_TARGET_MISMATCH` 인데, 빠뜨렸을 때도 **같은 코드**라
    /// 응답만으로는 어느 쪽인지 알 수 없다.
    @Test("정산 대상은 출발지 도착을 누른 멤버뿐이다")
    func ridersAreArrivedMembersOnly() {
        let ride = ride(
            member(payer, hasArrived: true),
            member(senderA, hasArrived: true),
            member(senderB, hasArrived: false)
        )

        #expect(ride.fareSplitRiders.map(\.id) == [payer, senderA])
    }

    /// publicId 가 빈 멤버도 **거르지 않는다.** 그 사람은 서버 `riderIds` 에 들어 있으므로 빼면
    /// 탑승자가 모자란 요청이 되고, 그 실패는 금액을 고쳐서는 풀리지 않는다 —
    /// `FareSplitDraftProblem.riderNotIdentified` 로 드러나야 한다.
    @Test("publicId 가 없는 탑승자도 목록에서 빼지 않는다")
    func unidentifiedRiderStaysInList() {
        let ride = ride(
            member(payer, hasArrived: true),
            member("", hasArrived: true)
        )

        #expect(ride.fareSplitRiders.count == 2)
        #expect(
            FareSplitPolicy.problemOf(
                totalFare: 10_000,
                riderPublicIds: ride.fareSplitRiders.map(\.id),
                shares: ride.fareSplitRiders.map { FareShare(riderPublicId: $0.id, amount: 5_000) }
            ) == .riderNotIdentified
        )
    }

    private func member(_ id: String, hasArrived: Bool) -> User {
        User(id: id, nickname: "닉", verifiedLabel: "", rating: 0.0, rideCount: 0, hasArrived: hasArrived)
    }

    private func ride(_ members: User...) -> Ride {
        Ride(
            id: "1",
            origin: "서울시청",
            destination: "강남역",
            departureLabel: "지금 출발",
            capacity: 4,
            members: members,
            farePerPerson: 0,
            totalFare: 0,
            status: .completed
        )
    }
}
