import Foundation
import MoyeotaDomain
import Testing
@testable import FeatureHome

/// 15 목적지의 **★ 담기가 실패했을 때 무슨 말을 하는가.**
///
/// 등록 실패는 **409 두 가지**이고 상태 코드로는 안 갈린다 —
/// `FAVORITE_PLACE_DUPLICATED` 와 `FAVORITE_PLACE_LIMIT_EXCEEDED`.
/// 예전에는 둘을 「자주 가는 곳에 담지 못했어요 (중복이거나 10개를 넘었을 수 있어요)」 하나로 뭉갰다.
/// 그게 나쁜 까닭은 **사용자가 할 일이 정반대**라는 것이다:
///
/// | | 중복 | 상한 초과 |
/// |---|---|---|
/// | 사실 | 원한 상태가 이미 참이다 | 자리가 없다 |
/// | 할 일 | 없다 | 하나를 뺀다 |
///
/// 뭉개면 이미 담아 둔 사용자는 「10개를 넘었나?」 싶어 목록을 열어 세어 보고, 10칸이 찬 사용자는
/// 「이미 담았나?」 싶어 같은 ★ 를 다시 누른다. 둘 다 서버가 이미 가려 준 것을 화면이 숨겨서 생긴다.
///
/// 원본 `advanceUntilIdle()` 자리는 뷰모델이 돌려주는 태스크의 `.value` 를 기다리는 것이다.
@MainActor
@Suite struct FavoriteAddFailureTest {

    /// 상한 초과는 **할 일이 있는 실패**다 — 하나를 빼면 담긴다. 그 길을 말해 주지 않으면 사용자는
    /// 다시 누르기만 반복한다. 수는 `FavoritePlacePolicy.MAX_COUNT` 에서 온다(서버 원문과 같은 값임을
    /// data 쪽 `RemotePlaceRepositoryTest` 가 못 박는다).
    @Test("상한 초과는 몇 개까지인지와 할 일을 함께 말한다")
    func limitExceededSaysCountAndAction() async {
        let repository = FakePlaceRepository(addError: limitExceeded())
        let viewModel = DestinationViewModel(repository: repository)
        await viewModel.initialLoad?.value

        await viewModel.addFavorite(place("판교역"))?.value

        let message = viewModel.uiState.favoriteActionMessage
        #expect(
            message
                == "자주 가는 곳은 \(FavoritePlacePolicy.MAX_COUNT)개까지만 담을 수 있어요. 하나를 빼고 다시 담아 주세요"
        )
    }

    /// 중복은 **할 일이 없는 실패**다 — 「다시」·「하나를 빼고」 같은 말을 붙이지 않는다.
    @Test("중복은 할 일을 시키지 않는다")
    func duplicatedAsksNothing() async throws {
        let repository = FakePlaceRepository(addError: duplicated())
        let viewModel = DestinationViewModel(repository: repository)
        await viewModel.initialLoad?.value

        await viewModel.addFavorite(place("판교역"))?.value

        let message = try #require(viewModel.uiState.favoriteActionMessage)
        #expect(message == "이미 담아 둔 곳이에요")
        #expect(!message.contains("개"), "할 일이 없는데 개수를 말하면 사용자가 목록을 세어 본다")
    }

    /// ★ 이 묶음의 요지 — 같은 409 두 개가 서로 다른 말을 한다.
    @Test("같은 409 두 가지가 서로 다른 말을 한다")
    func same409SaysDifferentThings() async {
        func messageFor(_ error: any Error) async -> String? {
            let viewModel = DestinationViewModel(repository: FakePlaceRepository(addError: error))
            await viewModel.initialLoad?.value
            await viewModel.addFavorite(place("판교역"))?.value
            return viewModel.uiState.favoriteActionMessage
        }

        let limitMessage = await messageFor(limitExceeded())
        let duplicatedMessage = await messageFor(duplicated())
        #expect(limitMessage != duplicatedMessage)
    }

    /// 못 박는 것: **응답을 못 받은 실패는 할 일을 말한다.**
    ///
    /// 담기가 `favoritePlaceCall` 경계를 쓰게 되면서 비로소 닿는 경우다 — 그 전에는 raw 전송 오류라
    /// 화면이 가릴 수 없었다. 일반 문구(「담지 못했어요」)는 재시도를 말하지 않으므로, 비행기모드인
    /// 사용자는 왜인지 모른 채 ★ 를 계속 누른다.
    @Test("네트워크 실패는 연결을 확인하라고 말한다")
    func networkFailureSaysCheckConnection() async {
        let offline = FavoritePlaceException(code: nil, serverMessage: nil, isNetwork: true)
        let repository = FakePlaceRepository(addError: offline)
        let viewModel = DestinationViewModel(repository: repository)
        await viewModel.initialLoad?.value

        await viewModel.addFavorite(place("판교역"))?.value

        #expect(viewModel.uiState.favoriteActionMessage == FavoriteNetworkFailureMessage)
        #expect(
            viewModel.uiState.favoriteActionMessage != "자주 가는 곳에 담지 못했어요",
            "네트워크 실패가 일반 문구로 떨어졌다 — 할 일을 말하지 않는다"
        )
    }

    /// 모르는 코드는 일반 문구다 — 서버가 `PlaceErrorCode` 를 늘려도 앱이 틀린 말을 하지 않는다
    /// (409 라고 「10개를 넘었어요」로 **추측하지 않는다**).
    @Test("모르는 실패는 사유를 지어내지 않는다")
    func unknownFailureInventsNoReason() async {
        let general = "자주 가는 곳에 담지 못했어요"
        let unknown409 = FavoritePlaceException(code: "PLACE_SOMETHING_NEW", serverMessage: nil, httpStatus: 409)
        let repository = FakePlaceRepository(addError: unknown409)
        let viewModel = DestinationViewModel(repository: repository)
        await viewModel.initialLoad?.value

        await viewModel.addFavorite(place("판교역"))?.value

        #expect(viewModel.uiState.favoriteActionMessage == general)
    }

    /// `FavoritePlaceException` 이 아닌 실패(데이터 계층의 경계가 비는 경우)도 일반 문구로 떨어진다.
    @Test("예외 종류를 가리지 못해도 문구는 선다")
    func unclassifiedFailureStillHasMessage() async {
        let repository = FakePlaceRepository(addError: Boom())
        let viewModel = DestinationViewModel(repository: repository)
        await viewModel.initialLoad?.value

        await viewModel.addFavorite(place("판교역"))?.value

        #expect(viewModel.uiState.favoriteActionMessage == "자주 가는 곳에 담지 못했어요")
    }

    /// 못 박는 것: **취소는 실패가 아니다.**
    ///
    /// 실패를 한데 받으면 취소까지 삼켜 화면을 떠난 것이 「담지 못했어요」로 보인다. 빼기 쪽은 처음부터
    /// 취소를 실패로 치지 않았는데(`removeFavorite`) 담기 쪽만 빠져 있었다 — 같은 규칙으로 맞춘다.
    ///
    /// 원본은 살아 있는 코루틴에 던져진 `CancellationException` 을 되던진다. Swift 에서 조용히 끝내도 되는 것은
    /// **정말 취소된 태스크**뿐이므로(PORTING §6) 태스크를 취소한 채로 같은 상황을 만든다.
    @Test("취소는 실패 문구로 바뀌지 않는다")
    func cancellationIsNotFailure() async {
        let repository = FakePlaceRepository(addError: CancellationError())
        let viewModel = DestinationViewModel(repository: repository)
        await viewModel.initialLoad?.value

        let task = viewModel.addFavorite(place("판교역"))
        task?.cancel()
        await task?.value

        #expect(viewModel.uiState.favoriteActionMessage == nil, "취소가 실패 문구로 섰다")
        #expect(!viewModel.uiState.favoriteActionLoading, "취소 뒤에도 잠겨 있으면 ★ 를 다시 못 누른다")
    }

    /// 성공 경로는 그대로다 — 목록을 다시 받아야 ★ 가 채워진다(낙관적 갱신을 하지 않는다).
    @Test("담기에 성공하면 목록을 다시 받는다")
    func successReloads() async {
        let repository = FakePlaceRepository()
        let viewModel = DestinationViewModel(repository: repository)
        await viewModel.initialLoad?.value
        let loadsBefore = await repository.loadCalls

        await viewModel.addFavorite(place("판교역"))?.value

        #expect(viewModel.uiState.favoriteActionMessage == "판교역을(를) 자주 가는 곳에 담았어요")
        #expect(await repository.loadCalls == loadsBefore + 1, "성공했는데 목록을 다시 받지 않았다")
    }

    /// 실패했으면 목록이 바뀐 게 없다 — 재조회로 사용자를 기다리게 하지 않는다.
    @Test("담기에 실패하면 목록을 다시 받지 않는다")
    func failureDoesNotReload() async {
        let repository = FakePlaceRepository(addError: duplicated())
        let viewModel = DestinationViewModel(repository: repository)
        await viewModel.initialLoad?.value
        let loadsBefore = await repository.loadCalls

        await viewModel.addFavorite(place("판교역"))?.value

        #expect(await repository.loadCalls == loadsBefore)
    }
}

private struct Boom: Error {}

/// 실측 본문의 코드·원문 그대로.
private func limitExceeded() -> FavoritePlaceException {
    FavoritePlaceException(
        code: "FAVORITE_PLACE_LIMIT_EXCEEDED",
        serverMessage: "자주가는 장소는 최대 10개까지만 등록할 수 있습니다.",
        httpStatus: 409
    )
}

private func duplicated() -> FavoritePlaceException {
    FavoritePlaceException(
        code: "FAVORITE_PLACE_DUPLICATED",
        serverMessage: "이미 등록된 장소입니다.",
        httpStatus: 409
    )
}

private func place(_ name: String) -> Place {
    Place(name: name, roadName: "경기 성남시 분당구 판교역로 160", latitude: 37.3947, longitude: 127.1112)
}

private actor FakePlaceRepository: PlaceRepository {
    private let addError: (any Error)?
    private(set) var loadCalls = 0

    init(addError: (any Error)? = nil) {
        self.addError = addError
    }

    func searchPlaces(query: String) async throws -> [Place] { [] }

    func reverseGeocode(latitude: Double, longitude: Double) async throws -> ReverseAddress? { nil }

    func addFavoritePlace(place: Place) async throws {
        if let addError { throw addError }
    }

    func getFavoritePlaces() async throws -> [FavoritePlace] {
        loadCalls += 1
        return []
    }

    func deleteFavoritePlace(id: Int64) async throws {}

    func deleteFavoritePlaces(ids: [Int64]) async throws {}

    func deleteAllFavoritePlaces() async throws {}
}
