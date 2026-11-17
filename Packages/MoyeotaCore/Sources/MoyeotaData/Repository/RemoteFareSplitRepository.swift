import MoyeotaDomain

/// 택시비 정산 저장소 — 서버가 **보는 사람에 맞춰** 응답을 만들므로 「누가 나인가」를 앱이 판정하지 않는다.
///
/// `RemoteRideRepository`·`RemoteChatRepository` 는 「멤버 중 누가 나인가」를 앱이 판정해야 해서
/// 세션을 받지만, 여기서는 서버가 `myRole`·`myAmount`·`myTransferStatus` 를 **토큰 기준으로 계산해**
/// 내려 준다(`FareSplitRole`). 앱이 같은 판정을 다시 세우면 서버와 어긋날 수 있는 두 번째 진실이 생긴다.
///
/// 예외는 하나다 — 서버가 `myTransferStatus` 를 아직 보내지 않을 때, 보내는 사람의 **자기 송금 상태**를
/// `transfers` 의 자기 행에서 메우는 폴백이다(`session` 주석). 그 판정은 매퍼가 상세를 만들 때 **한 번만**
/// 하고, 화면은 `FareSplitDetail.myTransferStatus` 만 본다 — 화면이 세션으로 `FareSplitDetail.transferOf`
/// 를 따로 부르면 「내 행」이 매퍼가 찍어 둔 값과 화면이 찾은 값 둘로 갈린다.
///
/// 실패는 전부 `FareSplitException` 으로 좁힌다(`fareSplitCall`). 취소는 좁히지 않고 그대로 던진다 —
/// 일반 `catch` 가 취소까지 잡으면 화면 이탈이 에러 문구로 보인다.
public final class RemoteFareSplitRepository: FareSplitRepository {
    private let api: any FareSplitApi
    /// 세션 — **내 송금 상태를 메우는 데만** 쓴다(`FareSplitMappers` 의 `myTransferStatusOf`).
    ///
    /// 서버가 `myTransferStatus` 를 보내 주면(Backend PR #328) 쓸 일이 없다. 그 배포가 닿기 전까지는
    /// 보내는 사람이 `transfers` 에서 **자기 publicId 로 자기 행을 찾는 것이 유일한 길**이고, 그
    /// 판정의 열쇠가 세션 uuid 다. 없어도 앱은 돌아간다 — 그때는 상태를 모른다고 말하고 버튼을 닫는다.
    ///
    /// 기본값을 nil 로 두는 이유: 이 저장소의 나머지 동작은 세션을 **전혀** 쓰지 않는다
    /// (서버가 토큰으로 `myRole`·`myAmount` 를 계산해 준다). 필수로 만들면 쓰지도 않는 의존을
    /// 테스트마다 들려 보내게 된다.
    private let session: (any UserSession)?

    public init(api: any FareSplitApi, session: (any UserSession)? = nil) {
        self.api = api
        self.session = session
    }

    /// ### 409 `FARE_SPLIT_ALREADY_EXISTS` 를 **그냥 올리지 않는다**
    /// 서버 Swagger 가 「이미 정산을 시작한 방(GET 으로 본다)」라고 적어 둔, **복구 경로가 명시된**
    /// 실패다. 그 GET 을 화면마다 시키면 한 곳만 빠뜨려도 사용자는 **이미 존재하는 자기 정산을
    /// 볼 수 없게** 된다(시작도 조회도 막힌 막다른 화면이 된다). 그래서 데이터 계층이 이어서 읽고
    /// `FareSplitException.existing` 에 담아 올린다 — `PartyJoinException.joinedStatus` 와 같은 배치다.
    ///
    /// 성공으로 **바꿔서** 돌려주지는 않는다. 사용자가 방금 입력한 금액·계좌는 **저장되지 않았고**
    /// (서버의 기존 정산이 그대로다), 그것을 성공으로 보여 주면 화면은 입력한 값이 반영된 줄 안다.
    /// 「실패지만 볼 것은 있다」가 사실에 가깝다.
    ///
    /// 이어 읽는 GET 이 실패하면 **그 실패는 삼킨다** — 원래 실패(409)를 네트워크 오류 같은 것으로
    /// 갈아 끼우면 화면이 「다시 시작해 보세요」로 안내하게 되고, 그건 영원히 409 다.
    public func startFareSplit(partyId: Int64, draft: FareSplitDraft) async throws -> FareSplitDetail {
        do {
            return try await api.createFareSplit(partyId: partyId, request: draft.toRequestDto())
                .toFareSplitDetail(requestedPartyId: partyId, currentUserUuid: session?.currentUserUuid)
        } catch where isCancellation(throwable: error) {
            throw error
        } catch {
            let failure = error.toFareSplitException()

            guard failure.isAlreadyExists else { throw failure }
            throw try await withExisting(failure, partyId: partyId)
        }
    }

    /// **404 `FARE_SPLIT_NOT_FOUND` 만 nil 로 접는다** — 「아직 아무도 시작하지 않았다」는 끝난 방의
    /// 정상 상태이고, 그걸 예외로 올리면 모든 호출자가 「정상인 404」와 「진짜 실패」를 가리려고
    /// do/catch 를 쓰게 된다(한 곳만 빠뜨리면 멀쩡한 방에 빨간 에러가 뜬다).
    ///
    /// **상태 코드만으로 판별하지 않는다.** 같은 404 에 `PARTY_NOT_FOUND`(방이 없다)와
    /// `FARE_SPLIT_TRANSFER_NOT_FOUND` 도 있다 — 앞쪽을 「정산이 없다」로 접으면 사라진 방에
    /// 「정산 시작하기」가 떠서, 눌렀을 때 또 404 를 받는다. `code` 를 보고 가른다.
    /// (전체 삭제의 404 를 `code` 없이 상태로만 삼키는 `RemotePlaceRepository` 와 다른 이유가 이것이다 —
    /// 그쪽 경로의 404 는 한 종류뿐이었다.)
    ///
    /// 403 `NOT_FARE_SPLIT_PARTICIPANT` 는 **그대로 올린다.** 「정산이 없다」와 「정산은 있는데 내가
    /// 당사자가 아니다」는 화면이 할 말이 다르고, nil 로 접으면 도착을 누르지 않은 사람에게
    /// 「정산 시작하기」가 떠서 눌렀을 때 403 `NOT_A_RIDER` 를 받는다.
    public func getFareSplit(partyId: Int64) async throws -> FareSplitDetail? {
        do {
            return try await api.getFareSplit(partyId: partyId)
                .toFareSplitDetail(requestedPartyId: partyId, currentUserUuid: session?.currentUserUuid)
        } catch where isCancellation(throwable: error) {
            throw error
        } catch {
            let failure = error.toFareSplitException()

            if failure.isFareSplitNotFound { return nil }
            throw failure
        }
    }

    /// 수정은 **전부 다시 보낸다**(부분 수정이 아니다 — `FareSplitDraft` 네 필드가 모두 필수다).
    /// 응답이 고친 상세이므로 화면은 **그것으로 갈아 끼우고** 따로 재조회하지 않는다.
    public func editFareSplit(partyId: Int64, draft: FareSplitDraft) async throws -> FareSplitDetail {
        try await fareSplitCall {
            try await api.editFareSplit(partyId: partyId, request: draft.toRequestDto())
                .toFareSplitDetail(requestedPartyId: partyId, currentUserUuid: session?.currentUserUuid)
        }
    }

    /// **멱등 204 는 성공으로만 다룬다.** 이미 SENT·CONFIRMED 였는지 지금 바뀌었는지 서버가
    /// 구분해 주지 않으므로(응답이 같다) 앱이 그 차이를 알 길이 없다 — 알아낸 척하는 반환값
    /// (`Bool` 같은 것)을 만들지 않는다. 화면이 그 값으로 문구를 갈라 쓰면 **틀린 문구**가 뜬다.
    ///
    /// 돌려줄 것이 없으므로 성공 뒤 상세·배너 재조회는 **호출자 몫**이다
    /// (`FareSplitRepository` 주석의 표).
    public func markSent(partyId: Int64) async throws {
        try await fareSplitCall {
            try await api.markSent(partyId: partyId)
        }
    }

    /// 「받았어요」. 마지막 확인이 정산을 닫고 계좌번호를 지우므로 성공 뒤 재조회가 필수다.
    ///
    /// ### 🔴 멱등이 **끝까지** 가지 않는다 — 실측으로 알아냈다 ★
    /// 서버 Swagger 는 「이미 CONFIRMED 면 아무것도 바꾸지 않고 204」라고 적어 두었다. 사실이 아니다.
    /// 마지막 송금을 확인하면 정산이 `COMPLETED` 로 닫히고, 그다음부터는 **닫힘 검사가 먼저 걸려**
    /// 409 `FARE_SPLIT_CLOSED` 가 온다(원본 로컬 실측 2026-11-12, partyId 4143):
    ///
    /// | 호출 | 서버 | 뜻 |
    /// |---|---|---|
    /// | 1회 | 204 | 확인됐다 → 정산이 닫혔다 |
    /// | 2회 | **409 `FARE_SPLIT_CLOSED`** | 「이미 CONFIRMED」가 아니라 「닫힌 정산」으로 답한다 |
    ///
    /// 그래서 **그 409 를 성공으로 접는다.** 접지 않으면 204 응답이 터널에서 유실된 뒤 다시 누른
    /// 받는 사람에게 「이미 끝난 정산입니다」가 뜬다 — 자기가 방금 닫은 정산인데 실패로 보이고,
    /// 화면을 새로 읽을 때까지 무엇이 참인지 알 수 없다. 「확인했다」와 「이미 확인돼 닫혔다」는
    /// 사용자가 할 일이 **같다**(아무것도 없다).
    ///
    /// 그 대가는 하나다: **한 번도 확인하지 않은 송금을 닫힌 정산에서 누르면** 그것도 성공으로 보인다.
    /// 그럴 수가 없다 — 정산이 닫히는 조건이 **모든 송금이 CONFIRMED** 인 것이기 때문이다. 즉
    /// 닫힌 정산에 남은 미확인 송금은 존재하지 않는다.
    ///
    /// `markSent` 쪽은 접지 않는다. 보내는 사람에게 닫힌 정산의 409 는 「내가 보낼 필요가 없어졌다」는
    /// **새 정보**이고(받는 사람이 현금으로 받고 닫았을 수 있다), 그때 화면은 상세를 다시 읽어
    /// 「정산이 끝났어요」로 바꿔야 한다 — 성공으로 접으면 보냈다는 표시만 남고 끝난 사실을 놓친다.
    public func confirmReceived(partyId: Int64, senderPublicId: String) async throws {
        do {
            try await fareSplitCall {
                try await api.confirmReceived(partyId: partyId, senderPublicId: senderPublicId)
            }
        } catch let failure as FareSplitException where failure.isClosed {
            // 닫힘 409 만 성공이다 — 나머지 실패(그리고 취소)는 이 catch 에 걸리지 않고 그대로 올라간다.
            return
        }
    }

    /// **멱등이 아니다** — SENT 인 송금에서만 되고, 아니면 409 `TRANSFER_NOT_SENT` 다
    /// (`FareSplitException.isTransferNotSent`). 그 실패를 삼키지 않는 이유: 「되돌렸다」와
    /// 「되돌릴 것이 없었다」는 받는 사람이 보고 있는 목록이 서버와 어긋났다는 뜻이라
    /// **재조회가 필요한 신호**다.
    public func markNotReceived(partyId: Int64, senderPublicId: String) async throws {
        try await fareSplitCall {
            try await api.markNotReceived(partyId: partyId, senderPublicId: senderPublicId)
        }
    }

    /// 상태는 **늘 명시해 보낸다** — 서버에 `defaultValue = "NOT_SENT"` 가 있지만, 기본값을 서버에
    /// 맡기면 서버가 그 값을 바꿀 때 홈 배너가 조용히 다른 목록을 그린다(에러로 드러나지 않는다).
    ///
    /// 빈 목록은 **정상**이고 에러가 아니다. 다만 「내가 보낼 돈이 없다」는 뜻일 뿐이라
    /// 「정산이 없다」로 읽으면 안 된다 — 받는 사람인 정산은 이 목록에 **절대** 나타나지 않는다.
    public func getMyFareSplits(status: TransferStatus) async throws -> [MyFareSplit] {
        try await fareSplitCall {
            try await api.getMyFareSplits(status: status.name).toMyFareSplits()
        }
    }

    /// 409 `FARE_SPLIT_ALREADY_EXISTS` 에 **이미 있는 정산**을 덧붙인다. 이어 읽는 GET 이 실패하면
    /// 원래 예외를 그대로 돌려준다(그 실패로 갈아 끼우지 않는다 — `startFareSplit` 주석).
    ///
    /// 취소는 삼키지 않는다 — 삼키면 화면을 떠나는 순간의 취소가 「409 였다」로 바뀌어 올라간다
    /// (이탈이 에러 문구로 보이는 그 버그다).
    private func withExisting(_ failure: FareSplitException, partyId: Int64) async throws -> FareSplitException {
        let existing: FareSplitDetail?
        do {
            existing = try await getFareSplit(partyId: partyId)
        } catch where isCancellation(throwable: error) {
            throw error
        } catch {
            existing = nil
        }

        guard let existing else { return failure }
        return failure.toFareSplitException(existing: existing)
    }
}
