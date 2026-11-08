@testable import FeatureExplore
import Foundation
import MoyeotaDomain
import Testing

// 원본에는 없는 테스트다. 원본은 요청·재시도를 `combine` + `flatMapLatest` 에 맡겨 따로 시험하지 않는데,
// iOS 는 그 자리(같은 요청 무시·앞 조회 끊기·늦은 응답 버리기)를 직접 쓰므로 여기서 본다.

private struct TestFailure: Error {}

private func reservation(_ id: String) -> Ride {
    Ride(
        id: id,
        origin: "부산대 정문",
        destination: "서면역",
        departureLabel: "",
        capacity: 3,
        members: [],
        farePerPerson: 0,
        totalFare: 0,
        status: .recruiting,
        departureAt: "2026-11-09T09:30:00Z",
        isConfirmed: true,
        roomType: .reservation
    )
}

/// 시험이 열어 줄 때까지 응답을 붙잡는다. **취소를 모른다** — URLSession 처럼 끊긴 호출도 값을 돌려줄 수 있는
/// 자리를 흉내 낸다(그 값을 버리는 것이 뷰모델의 몫이다).
private final class Latch: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?
    private var opened = false

    var isWaiting: Bool { lock.withLock { waiter != nil } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if opened { return true }
                waiter = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let continuation = lock.withLock {
            opened = true
            defer { waiter = nil }
            return waiter
        }
        continuation?.resume()
    }
}

/// 예약 조회 두 가지만 쓴다. 나머지는 이 뷰모델이 부르지 않으므로 부르면 던진다.
///
/// 응답 줄을 조회마다 따로 둔다 — 한 줄이면 앞 조회와 새 조회 중 어느 쪽이 먼저 꺼내 가는지가 실행 순서에 달린다.
private final class FakeRideRepository: RideRepository, @unchecked Sendable {
    enum Call: Equatable {
        case soon(MapBounds)
        case search(departureLat: Double, departureLng: Double, date: String, destination: ReservationDestination?)
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var soonResults: [@Sendable () async throws -> [Ride]] = []
    private var searchResults: [@Sendable () async throws -> [Ride]] = []

    var calls: [Call] { lock.withLock { recorded } }

    func enqueueSoon(_ result: @escaping @Sendable () async throws -> [Ride]) {
        lock.withLock { soonResults.append(result) }
    }

    func enqueueSearch(_ result: @escaping @Sendable () async throws -> [Ride]) {
        lock.withLock { searchResults.append(result) }
    }

    func getReservationsSoon(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] {
        let result: (@Sendable () async throws -> [Ride])? = lock.withLock {
            recorded.append(.soon(MapBounds(swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng)))
            return soonResults.isEmpty ? nil : soonResults.removeFirst()
        }
        return try await result?() ?? []
    }

    func searchReservations(
        departureLat: Double,
        departureLng: Double,
        date: String,
        destination: ReservationDestination?
    ) async throws -> [ReservationSearchResult] {
        let result: (@Sendable () async throws -> [Ride])? = lock.withLock {
            recorded.append(
                .search(departureLat: departureLat, departureLng: departureLng, date: date, destination: destination)
            )
            return searchResults.isEmpty ? nil : searchResults.removeFirst()
        }
        // 도착지를 보낸 검색에만 근접 여부가 온다(서버 계약) — 받은 값이 카드까지 가는지 보려고 true 로 둔다
        return try await (result?() ?? []).map {
            ReservationSearchResult(ride: $0, destinationNearby: destination != nil ? true : nil)
        }
    }

    func createReservation(request: NewReservation) async throws -> Ride { throw TestFailure() }
    func getReservations(from: String, to: String) async throws -> [Ride] { throw TestFailure() }
    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> [Ride] { throw TestFailure() }
    func getNearbyParties() -> [Ride] { [] }
    func getParties() async throws -> [Ride] { throw TestFailure() }
    func getPartyDetail(partyId: Int64) async throws -> Ride { throw TestFailure() }
    func getPartyDetailWithVersion(partyId: Int64) async throws -> PartyDetail { throw TestFailure() }
    func findRealtimeCandidates(
        departureLat: Double,
        departureLng: Double,
        destinationLat: Double,
        destinationLng: Double
    ) async throws -> [MatchCandidate] { throw TestFailure() }
    func observePartyEvents(partyId: Int64) -> AsyncThrowingStream<PartyEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: TestFailure()) }
    }
    func createParty(request: NewParty) async throws -> Ride { throw TestFailure() }
    func joinParty(partyId: Int64) async throws -> PartyStatus { throw TestFailure() }
    func leaveParty(partyId: Int64) async throws { throw TestFailure() }
    func finishParty(partyId: Int64) async throws { throw TestFailure() }
    func confirmMeeting(partyId: Int64, departureAt: String) async throws { throw TestFailure() }
    func arriveAtDeparture(partyId: Int64, latitude: Double, longitude: Double) async throws { throw TestFailure() }
    func departParty(partyId: Int64) async throws { throw TestFailure() }
    func previewRoute(
        departureLat: Double,
        departureLng: Double,
        destinationLat: Double,
        destinationLng: Double
    ) async throws -> RouteEstimate { throw TestFailure() }
}

@MainActor
private func eventually(
    _ what: Comment,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async {
    for _ in 0..<2_000 {
        if condition() { return }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("시간 안에 일어나지 않았다: \(what)", sourceLocation: sourceLocation)
}

@MainActor
@Suite(.serialized)
struct ReservationFinderViewModelTest {
    private let repository = FakeRideRepository()
    private let bounds = MapBounds(swLat: 35.2, swLng: 129.0, neLat: 35.3, neLng: 129.1)
    private let destination = ReservationDestination(latitude: 35.16, longitude: 129.06)

    private var byDate: ReservationQuery {
        .byDate(departureLat: 35.23, departureLng: 129.08, date: "2026-11-11", destination: destination)
    }

    @Test("요청이 없으면 조회하지 않고 비어 있다")
    func nilQueryIsIdle() async {
        let viewModel = ReservationFinderViewModel(repository: repository)
        await viewModel.request(nil)?.value
        await viewModel.retry()?.value

        #expect(viewModel.uiState == .idle)
        #expect(repository.calls.isEmpty)
    }

    /// 화면은 다시 그릴 때마다 같은 요청을 올린다 — 그때마다 서버를 때리면 안 된다.
    /// 같은 입력으로 다시 읽는 길은 `retry` 하나다.
    @Test("같은 요청은 다시 조회하지 않고 다시 시도만 다시 읽는다")
    func sameQueryIgnoredRetryRefetches() async {
        let viewModel = ReservationFinderViewModel(repository: repository)
        repository.enqueueSoon { [reservation("1")] }
        await viewModel.request(.soon(bounds: bounds))?.value
        #expect(viewModel.request(.soon(bounds: bounds)) == nil)
        #expect(repository.calls.count == 1)

        repository.enqueueSoon { [reservation("2")] }
        await viewModel.retry()?.value

        #expect(repository.calls.count == 2)
        #expect(viewModel.uiState == .success(items: [ReservationCardUi(ride: reservation("2"))]))
    }

    /// 「곧 출발」은 실시간 목록과 같은 이유로 넓힌 범위를 묻고, 날짜 검색은 도착지를 **함께** 싣는다.
    @Test("곧 출발은 넓힌 범위로, 날짜 검색은 도착지와 함께 묻는다")
    func fetchParameters() async {
        let viewModel = ReservationFinderViewModel(repository: repository)
        repository.enqueueSoon { [reservation("1")] }
        await viewModel.request(.soon(bounds: bounds))?.value
        repository.enqueueSearch { [reservation("2")] }
        await viewModel.request(byDate)?.value

        #expect(
            repository.calls == [
                .soon(bounds.expanded()),
                .search(departureLat: 35.23, departureLng: 129.08, date: "2026-11-11", destination: destination),
            ]
        )
        // 도착지 근접 여부는 카드로 그대로 옮긴다 — 접지 않는다
        #expect(
            viewModel.uiState == .success(items: [ReservationCardUi(ride: reservation("2"), destinationNearby: true)])
        )
    }

    /// ★ 모드를 바꾸는 순간 앞 조회를 끊는다 — 늦게 끝난 「곧 출발」 응답이 「날짜로 찾기」 목록을
    /// 덮으면 다른 영역의 방이 섞여 보인다(`ReservationFinder.swift` 의 1급 사실).
    @Test("새 요청이 오면 앞 조회의 늦은 응답을 버린다")
    func staleResponseIsDropped() async {
        let viewModel = ReservationFinderViewModel(repository: repository)
        let latch = Latch()
        repository.enqueueSoon {
            await latch.wait()
            return [reservation("soon")]
        }
        let first = viewModel.request(.soon(bounds: bounds))
        #expect(viewModel.uiState == .loading)
        await eventually("앞 조회가 응답을 기다린다") { latch.isWaiting }

        repository.enqueueSearch { [reservation("date")] }
        await viewModel.request(byDate)?.value
        // 끊긴 앞 조회가 그 뒤에 값을 들고 돌아온다
        latch.open()
        await first?.value

        #expect(
            viewModel.uiState == .success(items: [ReservationCardUi(ride: reservation("date"), destinationNearby: true)])
        )
    }

    /// 실패는 「예약이 없다」와 다른 상태다. 태스크가 살아 있는 `URLError(.cancelled)` 도 원본에서는 OkHttp
    /// `IOException` 이라 실패다 — 끊긴 요청으로 보고 상태를 안 쓰면 「불러오는 중」에 머문다.
    @Test("조회 실패는 실패 상태이고 다시 시도로 회복한다")
    func failureThenRetry() async {
        let viewModel = ReservationFinderViewModel(repository: repository)
        repository.enqueueSoon { throw URLError(.cancelled) }
        await viewModel.request(.soon(bounds: bounds))?.value
        #expect(viewModel.uiState == .failed)

        repository.enqueueSoon { [] }
        await viewModel.retry()?.value
        #expect(viewModel.uiState == .success(items: []), "빈 목록은 성공이다")

        await viewModel.request(nil)?.value
        #expect(viewModel.uiState == .idle, "요청이 빠지면 목록을 비운다")
    }
}
