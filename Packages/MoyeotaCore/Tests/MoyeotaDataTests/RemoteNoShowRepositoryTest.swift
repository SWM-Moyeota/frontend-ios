import Foundation
import MoyeotaDomain
import Testing
@testable import MoyeotaData

@Suite struct RemoteNoShowRepositoryTest {

    /// 조회가 **서버 순서 그대로** 올라오고, 무효가 된 건도 **걸러지지 않는다**.
    ///
    /// 걸러내고 싶어지는 줄이 바로 그 무효 건인데, 그 줄이 「이의가 받아들여졌다」는 **유일한 증거**다
    /// — 빼면 사용자가 결과를 확인할 길이 없다(프로필의 `restrictedUntil` 은 「지금 막혀 있나」만 말한다).
    @Test("노쇼 기록을 서버 순서 그대로 올리고 무효 건도 남긴다")
    func keepsServerOrderAndVoided() async throws {
        let api = FakeNoShowApi(
            noShows: [
                NoShowItemDto(
                    partyId: 7,
                    departure: "서울시청",
                    destination: "강남역",
                    meetingAt: "2026-11-03T08:30:00Z",
                    noShowAt: "2026-11-03T08:40:00Z",
                    voided: false,
                    objectionStatus: nil
                ),
                NoShowItemDto(partyId: 5, voided: true, objectionStatus: "ACCEPTED"),
            ]
        )

        let records = try await RemoteNoShowRepository(api: api).getMyNoShows()

        #expect(records.map(\.partyId) == [7, 5])
        #expect(records.map(\.isVoided) == [false, true])
        #expect(records.map(\.objectionStatus) == [nil, .accepted])
        #expect(records.first?.meetingAt == "2026-11-03T08:30:00Z")
    }

    /// 기록이 없으면 **빈 목록**이다 — 서버가 404 가 아니라 `{"noShows":[]}` 를 준다.
    @Test("기록이 없으면 빈 목록이다")
    func emptyRecords() async throws {
        #expect(try await RemoteNoShowRepository(api: FakeNoShowApi()).getMyNoShows().isEmpty)
    }

    /// **조회 실패는 감싸지 않는다**(맨몸으로 던진다). 이 조회의 서버 실패는 401 하나뿐이고 화면의
    /// 대응도 하나다 — `RemoteRideRecordRepository` 와 같은 결이고, 감싸면 쓰지 않을 구분이 생긴다.
    /// (그 `do`/`catch` 가 없는 것 자체가 취소 보존 장치이기도 하다.)
    @Test("조회 실패는 전용 예외로 감싸지 않는다")
    func listFailureIsNotWrapped() async throws {
        let api = FakeNoShowApi(noShowsFailure: unauthorized())

        // HttpException 이 아닌 것(NoShowObjectionException 등)이 오면 그대로 흘러 테스트가 실패한다.
        let error = try await thrownError(HttpException.self) {
            _ = try await RemoteNoShowRepository(api: api).getMyNoShows()
        }

        #expect(error.code() == 401)
    }

    /// 이의 신청은 방 id 와 사유만 보낸다 — 주체는 Bearer 토큰이 정한다.
    @Test("이의 신청은 방 id 와 사유만 보낸다")
    func objectionSendsPartyIdAndReason() async throws {
        let api = FakeNoShowApi()

        try await RemoteNoShowRepository(api: api).submitObjection(partyId: 7, reason: "병원에 있었어요")

        #expect(api.objectionCall.value == 7)
        #expect(api.objectionRequest.value?.reason == "병원에 있었어요")
    }

    /// **앞뒤 공백을 떼고 보낸다.** 서버 검증(`@NotBlank` + `@Size(max = 500)`)이 **다듬기 전**
    /// 문자열에 걸리기 때문이다 — 공백으로 패딩된 501자는 다듬으면 500자 이하여도 400 이다.
    /// 여기서 먼저 다듬으면 사용자 입장에서 「같은 글인데 결과가 다른」 상황이 사라진다.
    @Test("사유의 앞뒤 공백을 떼고 보낸다")
    func trimsReason() async throws {
        let api = FakeNoShowApi()

        try await RemoteNoShowRepository(api: api).submitObjection(partyId: 7, reason: "  병원에 있었어요\n ")

        #expect(api.objectionRequest.value?.reason == "병원에 있었어요")
    }

    /// 반대로 **빈 값·길이 초과를 앱이 끊지는 않는다.** 그 판정을 들면 서버가 상한을 바꿀 때 앱만
    /// 뒤처지고, 무엇보다 「앱이 막은 실패」와 「서버가 막은 실패」가 같은 예외로 섞여 원인을 가릴 수
    /// 없게 된다(`confirmMeeting` 이 약속 시간을 검사하지 않는 것과 같은 정책).
    @Test("빈 사유도 서버로 보낸다 — 판정은 서버가 한다")
    func sendsBlankReason() async throws {
        let api = FakeNoShowApi()

        try await RemoteNoShowRepository(api: api).submitObjection(partyId: 7, reason: "   ")

        #expect(api.objectionCall.value == 7, "앱이 빈 사유를 먼저 끊었다 — 판정은 서버 몫이다")
        #expect(api.objectionRequest.value?.reason == "")
    }

    /// 길이 초과도 **자르지 않는다** — 서버가 400 `INVALID_REQUEST` 로 판정한다. 앱이 몰래 자르면
    /// 사용자가 쓴 글의 뒷부분이 조용히 사라진 채 접수된다(실패보다 나쁘다).
    /// 500자 상한을 아는 곳은 입력란(화면)이고, 그 값은 이 도메인 상수를 함께 쓴다.
    @Test("길이 초과 사유도 자르지 않고 보낸다")
    func sendsTooLongReason() async throws {
        let api = FakeNoShowApi()
        let tooLong = String(repeating: "가", count: NoShowObjectionException.MAX_REASON_LENGTH + 1)

        try await RemoteNoShowRepository(api: api).submitObjection(partyId: 7, reason: tooLong)

        #expect(api.objectionRequest.value?.reason == tooLong)
        #expect(NoShowObjectionException.MAX_REASON_LENGTH == 500)
    }

    /// ### 다섯 사유가 하나씩 갈린다 ★
    /// **409 가 두 가지 뜻**이라(`NOT_NO_SHOW`·`ALREADY_OBJECTED`) 상태 코드로는 안내 문구를 가를 수
    /// 없다. 그리고 두 사유의 다음 행동이 정반대다: 앞은 「낼 이유가 없다(좋은 소식)」, 뒤는
    /// 「심사를 기다린다」다.
    @Test("이의 신청 실패는 사유마다 다른 프로퍼티로 갈린다")
    func failuresSplitByReason() async throws {
        let invalid = try await objectionError(400, "INVALID_REQUEST")
        #expect(invalid.isInvalidReason)
        #expect(!invalid.isAlreadyObjected)

        let notMember = try await objectionError(403, "NOT_PARTY_MEMBER")
        #expect(notMember.isNotMember)
        #expect(!notMember.isNotNoShow)

        let notFound = try await objectionError(404, "PARTY_NOT_FOUND")
        #expect(notFound.isPartyNotFound)

        // 같은 409 두 개 — 뜻이 다르고, 사용자가 할 일도 다르다.
        let notNoShow = try await objectionError(409, "NOT_NO_SHOW")
        #expect(notNoShow.isNotNoShow)
        #expect(!notNoShow.isAlreadyObjected)

        let already = try await objectionError(409, "ALREADY_OBJECTED")
        #expect(already.isAlreadyObjected)
        #expect(!already.isNotNoShow)
        #expect(already.httpStatus == 409)
        // 서버 원문을 그대로 들고 온다 — 화면 문구는 화면이 정한다.
        #expect(already.serverMessage == "message-ALREADY_OBJECTED")
    }

    /// **모르는 코드와 본문 없는 실패는 사유를 추측하지 않는다** — `code` 가 nil 이거나 모르는 값이면
    /// 어느 프로퍼티도 참이 아니라 화면이 일반 문구로 떨어진다.
    ///
    /// 특히 **상태 코드로 폴백하지 않는 것**이 중요하다: 409 를 「이미 이의를 냈어요」로 뭉개면
    /// 서버가 409 코드를 하나 더 늘리는 날 **낼 수 있는 사람에게 이미 냈다고** 말한다.
    @Test("모르는 코드와 빈 본문은 사유를 추측하지 않는다")
    func unknownAndBodylessDoNotGuess() async throws {
        let unknown = try await objectionError(409, "SOMETHING_NEW")
        #expect(unknown.code == "SOMETHING_NEW")
        #expect(!unknown.isAlreadyObjected)
        #expect(!unknown.isNotNoShow)

        let bodyless = try await failedObjection(FakeNoShowApi(objectionFailure: bodylessError(409)))
        #expect(bodyless.code == nil)
        #expect(bodyless.serverMessage == nil)
        #expect(!bodyless.isAlreadyObjected)
        #expect(bodyless.httpStatus == 409)
    }

    /// 네트워크 실패도 같은 예외로 좁힌다 — code 는 nil 이라 화면은 일반 문구를 쓴다.
    @Test("네트워크 실패도 같은 예외로 좁힌다")
    func networkFailureIsWrapped() async throws {
        let error = try await failedObjection(FakeNoShowApi(objectionFailure: IOException("연결 거부")))

        #expect(error.code == nil)
        #expect(error.httpStatus == nil)
    }

    /// **취소는 에러가 아니다.** 일반 `catch` 가 취소까지 잡으므로 저장소가 되던진다 — 안 그러면 화면을
    /// 떠나는 동작이 「이의를 신청하지 못했습니다」로 보인다
    /// (이 저장소 전반의 규칙이고, `RemoteRideRecordRepositoryTest` 가 같은 것을 확인한다).
    @Test("취소는 그대로 전파된다", .timeLimit(.minutes(1)))
    func cancellationPropagates() async {
        let entered = AsyncSignal()
        let repository = RemoteNoShowRepository(api: FakeNoShowApi(objectionGate: entered))

        let job = Task { try await repository.submitObjection(partyId: 7, reason: "사유") }
        await entered.wait()
        job.cancel()

        switch await job.result {
        case .success:
            Issue.record("취소됐는데 성공으로 끝났다")
        case .failure(let error):
            #expect(error is CancellationError, "취소가 \(type(of: error)) 로 바뀌었다")
        }
    }

    private func objectionError(_ status: Int, _ code: String) async throws -> NoShowObjectionException {
        try await failedObjection(FakeNoShowApi(objectionFailure: httpError(status, code)))
    }

    private func failedObjection(_ api: FakeNoShowApi) async throws -> NoShowObjectionException {
        try await thrownError(NoShowObjectionException.self) {
            try await RemoteNoShowRepository(api: api).submitObjection(partyId: 7, reason: "사유")
        }
    }

    private func httpError(_ status: Int, _ code: String) -> HttpException {
        HttpException(Response<Void>.error(status, #"{"code":"\#(code)","message":"message-\#(code)"}"#))
    }

    /// 본문 없는 실패 — 게이트웨이·프록시가 가로챈 응답이 이렇게 온다(서버 코드가 없다).
    private func bodylessError(_ status: Int) -> HttpException {
        HttpException(Response<Void>.error(status, ""))
    }

    private func unauthorized() -> HttpException {
        HttpException(Response<Void>.error(401, #"{"code":"USER005","message":"로그인이 필요합니다."}"#))
    }
}

/// 노쇼 두 호출만 응답하는 `MatchingApi`. **나머지는 끊어 둔다** — 조용히 기본값을 돌려주면
/// 「저장소가 다른 호출을 섞지 않는다」가 검증되지 않는다(이 저장소는 세션도, 방 조회도 쓰지 않는다).
private final class FakeNoShowApi: MatchingApi {
    private let noShows: [NoShowItemDto]
    private let noShowsFailure: (any Error)?
    private let objectionFailure: (any Error)?
    /// 호출이 **들어왔음**을 알리고 그대로 멈춰 선다 — 취소 전파를 보기 위한 장치다.
    private let objectionGate: AsyncSignal?

    let objectionCall = Locked<Int64?>(nil)
    let objectionRequest = Locked<NoShowObjectionRequestDto?>(nil)

    init(
        noShows: [NoShowItemDto] = [],
        noShowsFailure: (any Error)? = nil,
        objectionFailure: (any Error)? = nil,
        objectionGate: AsyncSignal? = nil
    ) {
        self.noShows = noShows
        self.noShowsFailure = noShowsFailure
        self.objectionFailure = objectionFailure
        self.objectionGate = objectionGate
    }

    func getMyNoShows() async throws -> MyNoShowListResponse {
        if let noShowsFailure { throw noShowsFailure }
        return MyNoShowListResponse(noShows: noShows)
    }

    func submitNoShowObjection(partyId: Int64, request: NoShowObjectionRequestDto) async throws {
        objectionCall.value = partyId
        objectionRequest.value = request
        if let objectionGate {
            objectionGate.complete()
            // 영원히 기다린다 — 깨우는 것은 취소뿐이다(취소되면 `CancellationError` 를 던진다).
            try await Task.sleep(for: .seconds(3_600))
        }
        if let objectionFailure { throw objectionFailure }
    }

    func getParties() async throws -> PartyListResponse { throw unused() }

    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> PartyListResponse {
        throw unused()
    }

    func getPartyDetail(partyId: Int64) async throws -> PartyDetailResponse { throw unused() }

    func openParty(request: OpenPartyRequestDto) async throws -> OpenPartyResponse { throw unused() }

    func joinParty(partyId: Int64) async throws -> PartyStatusResponse { throw unused() }

    func finishParty(partyId: Int64) async throws { throw unused() }

    func leaveParty(partyId: Int64) async throws { throw unused() }

    func confirmMeeting(partyId: Int64, request: ConfirmMeetingRequestDto) async throws { throw unused() }

    func arriveAtDeparture(partyId: Int64, request: ArriveRequestDto) async throws { throw unused() }

    func departParty(partyId: Int64) async throws { throw unused() }

    func previewRoute(request: RouteRequestDto) async throws -> RouteEstimateResponse { throw unused() }

    func getRealtimeCandidates(request: RealTimeMatchingRequestDto) async throws -> [MatchCandidateResponse] {
        throw unused()
    }

    func createReservation(request: OpenReservationRequestDto) async throws -> OpenPartyResponse { throw unused() }

    func getReservations(from: String, to: String) async throws -> ReservationListResponse { throw unused() }

    func getReservationsSoon(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> ReservationListResponse {
        throw unused()
    }

    func searchReservations(
        depLat: Double,
        depLng: Double,
        date: String,
        destLat: Double?,
        destLng: Double?
    ) async throws -> ReservationListResponse {
        throw unused()
    }

    private func unused() -> IllegalStateException {
        IllegalStateException("쓰이지 않는다")
    }
}
