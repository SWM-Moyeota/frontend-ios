public protocol RideRepository: Sendable {
    func getNearbyParties() -> [Ride]

    // 조회 — GET /api/v1/matching/rooms, /rooms/{partyId}
    /// 목록 응답에는 좌표·요금·경로가 없다(partyId/출발/도착/인원/정원/상태만). 상세는 `getPartyDetail`.
    func getParties() async throws -> [Ride]

    /// 지도 범위(남서 `swLat`/`swLng` ~ 북동 `neLat`/`neLng`) 안의 모집 중 방 목록.
    /// GET /api/v1/matching/rooms?swLat=&swLng=&neLat=&neLng=
    ///
    /// `getParties` 와 같은 `Ride` 목록을 돌려주되, **출발 좌표(originLat/originLng)가 채워져 있다**
    /// — 지도 핀을 찍는 데 쓴다. 도착 좌표·요금·경로는 여전히 없으니 `getPartyDetail` 로 받는다.
    func getPartiesWithin(
        swLat: Double,
        swLng: Double,
        neLat: Double,
        neLng: Double
    ) async throws -> [Ride]

    /// GET /api/v1/matching/rooms/{partyId} — 방 상세. 참여자가 아니어도 되고(403 없음),
    /// 방이 없으면 404 PARTY_NOT_FOUND.
    ///
    /// **주기 조회가 필요한 화면은 이걸 부른다.** 예전에는 상태·인원·지문만 담은 가벼운
    /// `GET /rooms/{id}/status` 를 읽고 지문이 달라진 주기에만 상세를 읽었지만, 그 엔드포인트가
    /// 백엔드에서 사라졌다(Backend `04f6be7` — 매칭방 변화는 SSE 가 유일한 전달 경로가 되면서
    /// 폴링용으로 만든 상태 조회와 지문이 쓰이지 않게 됐다).
    ///
    /// 그래서 **이 호출은 비싸다**: 서버가 쿼리 3개(방 + 멤버 요약 + 탑승 횟수)를 돌리고 경로 폴리라인까지
    /// 실어 온다. 부하테스트에서 방 상세 폴링이 전체 요청의 45% 였다(Backend #177). 주기 조회에 쓰는
    /// 화면은 **간격을 충분히 벌리고**, 받은 `Ride` 가 들고 있던 것과 `==` 로 같으면
    /// 화면 상태를 갱신하지 않아야 한다(불필요한 화면 갱신 방지). 지금 주기 조회가 남아 있는
    /// 자리는 `observePartyEvents` 가 끊긴 동안의 **폴백** 하나뿐이다.
    func getPartyDetail(partyId: Int64) async throws -> Ride

    /// `getPartyDetail` 과 **같은 요청**이되 방 순번(`PartyDetail.version`)까지 돌려준다.
    ///
    /// 왜 따로 두는가: 상세를 읽는 곳은 8군데인데 순번이 필요한 건 **SSE 변경분을 병합하는 21 대기
    /// 화면 하나**다. 반환 타입을 바꾸면 나머지 일곱 곳이 쓰지도 않을 `.ride` 를 붙여야 한다.
    /// 순번은 방의 성질이 아니라 **프레임의 순서 표식**이라 `Ride` 안에 넣을 수도 없다 — 넣으면
    /// 25·26 이 "바뀌었나"를 보는 `Ride` 끼리의 `==` 비교가 순번 때문에 매번 달라진다.
    ///
    /// 쓰는 곳은 `PartyEvent` 의 틈(gap) 메우기다. 변경분이 `PartyEvent.snapshot` 보다 먼저 왔거나
    /// 중간 프레임을 놓쳤을 때 이걸로 다시 읽고, 읽어 온 순번을 기준으로 삼는다.
    func getPartyDetailWithVersion(partyId: Int64) async throws -> PartyDetail

    /// 내 출발·도착 좌표로 **걸어서 가까운 방**을 추천받는다(`POST /matching/rooms/realtime`).
    ///
    /// `getPartiesWithin` 과 목적이 다르다 — 저쪽은 "지도에 보이는 방 전부"(뷰포트), 이쪽은
    /// "양쪽에서 걸어갈 만한 방 몇 개"다. 서버가 출발지·도착지 **각각** 300m 안에서 고른 뒤
    /// 도보 시간 합으로 정렬해 **0~5개**를 준다.
    ///
    /// - **빈 목록은 정상이다.** 양쪽 300m 를 동시에 만족해야 해서 초기에는 그게 기본 상태다.
    ///   에러로 다루지 말 것.
    /// - **재정렬하지 말 것.** 받은 순서가 서버의 도보 시간 순이다.
    /// - **주기 조회에 쓰지 말 것.** 후보마다 서버가 OSRM 을 2번 부른다. 좌표가 확정된 순간 1회다.
    ///
    /// 실패는 `RealtimeMatchException` 으로 좁혀 던진다 — 사유마다 화면이
    /// 달라야 하기 때문이다(엔진 장애는 방 만들기로 흘리고, 이미 방이 있으면 섹션 자체를 숨긴다).
    func findRealtimeCandidates(
        departureLat: Double,
        departureLng: Double,
        destinationLat: Double,
        destinationLng: Double
    ) async throws -> [MatchCandidate]

    /// 이 방의 **변경분(delta) 스트림**(SSE `GET /api/v1/matching/rooms/{partyId}/events`).
    ///
    /// 수집하는 동안만 연결되고, 끊기면 알아서 다시 붙는다. 멤버가 아니거나(403) 방이 없으면(404)
    /// 스트림이 끝난다(재시도하지 않는다). 방이 닫히면 `PartyEvent.closed` 뒤에 끝난다.
    ///
    /// **받는 순서는 늘 `PartyEvent.snapshot` → 그 뒤의 변경분이다.** 구독하자마자 서버가 방 상세 전체를
    /// 스냅샷으로 주고, 그 뒤로 `PartyEvent.memberJoined`·`PartyEvent.memberLeft` 만 온다. 끊겨 다시
    /// 붙을 때도 **스냅샷이 먼저** 오므로, 그동안 놓친 변화는 거기서 전부 보정된다.
    ///
    /// 그래서 **화면은 평상시 폴링도, 재연결 직후의 catch-up 조회도 하지 않아야 한다** — 이번 설계의 핵심이다.
    /// 신호마다 `getPartyDetail` 을 다시 읽던 예전 구조(서버 `changed` 이벤트)는 **없어졌다**:
    /// 대기 화면의 상세 폴링이 서버 요청의 45% 였고(Backend #177), 변경분이 오는 지금은 그 재조회가
    /// 같은 내용을 다시 받는 낭비다. 폴링은 `PartyEvent.disconnected` 동안의 **폴백**으로만 남긴다
    /// (채팅 소켓과 같은 정책 — 살아 있으면 0회, 죽었을 때만).
    ///
    /// 다시 읽어야 하는 경우는 하나뿐이다: `PartyEvent.memberLeft` 의 publicId 가 null 일 때
    /// (누가 나갔는지 서버도 모른다).
    ///
    /// ⚠️ **같은 방을 두 곳에서 동시에 수집하지 말 것.** 서버가 구독을 받을 때 **같은 사용자의 기존 연결을
    /// 먼저 끊는다**(`PartySseRegistry.closeMember`) — 한 화면이 두 번 수집하면 두 연결이 서로를 끊고
    /// 번갈아 재연결하는 무한 루프가 된다. 수집은 화면(ViewModel)당 **정확히 한 번**이다.
    ///
    /// ⚠️ **이 스트림은 best-effort 다.** 서버가 커밋 후 단일 스레드 큐로 발행하고 **실패하면 재발행하지
    /// 않는다**(Redis Pub/Sub 도 at-most-once). 그래서 "SSE 가 유일한 근거"인 화면은 만들지 않는다 —
    /// 끊김 동안의 폴백 폴링과, 재연결 `PartyEvent.snapshot` 의 전체 보정이 반드시 함께 있어야 한다.
    ///
    /// 발행처는 **참여·퇴장·종료 셋뿐**이다. 예전에는 그 뒤로 배차·운행 전이
    /// (`MATCHING`→`DRIVER_ASSIGNED`→`IN_RIDE`)가 있었고 그 전이에는 신호가 없어 화면이 폴링으로
    /// 메웠지만, 서버가 기사·배차를 걷어내면서 그 상태들을 **보낼 수 없게 됐다**(서버 `PartyStatus`
    /// 에서 삭제). 지금 남은 전이는 전부 이 스트림에 실려 온다.
    ///
    /// **흐름은 SSE 403 `NOT_PARTY_MEMBER` 에서 `PartyMembershipLostException` 으로 예외 종료한다.**
    /// 「스트림이 끝났다」와 반드시 구분해야 한다 — 전자는 호출부가 **화면을 떠나야** 하고, 후자는
    /// 폴백 폴링으로 넘어가면 된다. 둘을 뭉개면 내가 멤버가 아닌 방을 「같이 탈 사람을 찾고 있어요」로
    /// 영원히 그린다(상세 조회에는 참여자 검사가 없어 계속 성공한다).
    ///
    /// ⚠️ **수집을 취소해도 `for try await` 는 오류 없이 끝난다.** 원본 `collect` 는
    /// `CancellationException` 을 던져 다음 줄을 지나지 않지만, 여기서는 루프 뒤로 그대로 내려가 종결과 똑같아
    /// 보인다. 루프 뒤의 코드가 「스트림이 종결로 끝났다」를 뜻하면 먼저 `try Task.checkCancellation()` 을 부른다.
    /// 안 그러면 대기 화면이 가려질 때마다 `streamEnded` 가 서서 복귀해도 SSE 를 다시 붙이지 않고 폴백 폴링에 머문다.
    ///
    /// 기본 구현은 아무것도 내지 않는다(더미·테스트 저장소).
    func observePartyEvents(partyId: Int64) -> AsyncThrowingStream<PartyEvent, any Error>

    // 액션 — 성공 후 화면이 갱신해야 하는 대상은 아래 주석 참고.
    /// POST /api/v1/matching/rooms. 생성된 방을 그대로 돌려주므로 MatchWaiting 으로 바로 넘길 수 있다.
    ///
    /// 생성자는 **로그인 토큰이 정한다**(@CurrentUser) — 합류·나가기와 같다. 요청 본문에 사용자 id 를
    /// 싣지 않는다. 생성 응답에는 멤버 목록이 없어 인원 수만큼 자리 표시용 멤버가 채워지므로,
    /// 실제 멤버 식별자가 필요하면 `getPartyDetail` 로 다시 읽는다.
    ///
    /// 앱이 정하는 조건은 **좌표·라벨·정원뿐**이다(`NewParty`) — 반경은 서버가 고정값으로 정한다.
    ///
    /// 실패는 모두 `PartyOpenException` 으로 올라온다(409 `ALREADY_JOINED_OTHER_PARTY`·
    /// `PARTY_TIME_CONFLICT` / 400 `SAME_DEPARTURE_DESTINATION`·`OUT_OF_SERVICE_AREA`·`INVALID_CAPACITY`·
    /// `INVALID_ROUTE_ESTIMATE` / **403 `NO_SHOW_RESTRICTED`** / 502 `ROUTE_SEARCH_FAILED` / 네트워크).
    /// 화면은 그 프로퍼티로 분기한다 — **한 문구로 뭉개면 안 된다.** 409 는 「잠시 후 다시 시도」가
    /// **영구히 거짓**이고(아무도 합류하지 않은 ACTIVE 방은 서버 스윕 대상이 아니라 계정이 계속 막힌다),
    /// 400 좌표·정원은 사용자가 **고쳐야** 하는 값이다. 403 은 **기다리면 풀리지만 몇 시간 단위**라 그 역시
    /// 「잠시」가 아니고, 기한을 말하려면 프로필을 함께 읽어야 한다(`PartyOpenException.isNoShowRestricted`).
    /// 409 `PARTY_TIME_CONFLICT` 는 지금 전후 2시간 안에 내 다른 예약이 있을 때다
    /// (`PartyOpenException.isPartyTimeConflict` — 실시간 문구 표에는 그 갈래가 없다).
    func createParty(request: NewParty) async throws -> Ride

    /// 합류. POST /api/v1/matching/rooms/{partyId}/join.
    /// 합류자는 **로그인 토큰이 정한다**(@CurrentUser) — memberId 를 넘기지 않는다.
    ///
    /// **돌려주는 것은 방 상세가 아니라 합류 직후의 `PartyStatus`(상태·인원)다**(Backend #213).
    /// 예전엔 응답이 곧 방 상세라 그대로 다음 화면에 넘길 수 있었지만, 이제 **동승자 목록이 오지 않는다** —
    /// 목록이 필요하면 `getPartyDetail` 을 따로 불러야 한다. 다만 합류 후 바로 대기 화면(21)으로 가는
    /// 흐름이라면 그 화면이 구독하는 `observePartyEvents` 의 첫 `PartyEvent.snapshot` 이 상세 전체를
    /// 주므로, 재조회를 거기에 맡기는 선택도 가능하다.
    ///
    /// 돌려주는 `PartyStatus.status` 로 "내가 마지막 자리를 채웠는지"를 알 수 있다 — 정원이 차면 서버가
    /// 그 자리에서 정원 충족 처리까지 끝낸다(`COMPLETED`). 앱은 트리거하지 않는다.
    ///
    /// **예약 방에 합류하는 길도 이것이다** — 서버에 예약 전용 합류 엔드포인트가 없다
    /// (`createReservation`). 다만 예약은 합류한 순간부터 확정이라 **나갈 수 없고**(`leaveParty` 가
    /// 409 `CANNOT_LEAVE_CONFIRMED_PARTY`), 출발 시각이 지난 예약은 409 `PARTY_CLOSED` 다.
    ///
    /// 실패는 모두 `PartyJoinException` 으로 올라온다(401 미로그인 / 409 `ALREADY_JOINED_OTHER_PARTY`·
    /// `PARTY_FULL`·`PARTY_CLOSED`·`PARTY_TIME_CONFLICT` / 404 `PARTY_NOT_FOUND` /
    /// **403 `NO_SHOW_RESTRICTED`** / 네트워크). 화면은 그 프로퍼티로 분기한다. 403 은 「이 방이 안 된다」가
    /// 아니라 「**내가** 지금 아무 방에도 못 들어간다」라서 목록으로 되돌려 보내면 누르는 족족 같은 403 이다
    /// (`PartyJoinException.isNoShowRestricted`).
    ///
    /// 409 `PARTY_TIME_CONFLICT` 는 기준 시각 전후 2시간 안에 내 다른 예약이 있을 때다 — 기준은 예약 방이면
    /// 그 방의 출발 시각, 실시간 방이면 지금이다(서버 `PartyService.join` → `checkTimeConflict`).
    /// `PartyJoinException` 에는 그 프로퍼티가 없어 원본처럼 화면은 일반 합류 실패 문구
    /// (`JOIN_FAILED_MESSAGE`)로 떨어진다.
    ///
    /// **그중 하나는 실패가 아니다.** `PartyJoinException.isAlreadyInThisParty` 가 true 면 **서버에는
    /// 내가 이미 그 방 멤버로 들어가 있다** — 데이터 계층이 방 상세로 확인한 결과이고,
    /// `PartyJoinException.joinedStatus` 에 그 방의 현재 상태가 담겨 온다. 화면은 이 경우를
    /// **합류 성공과 같은 길로** 보내야 한다. 그러지 않으면 그 계정은 재시도도 409, 다른 방도 409 라
    /// 30분 스윕 전까지 아무 방에도 못 들어간다(합류는 서버가 멤버 추가를 먼저 커밋한다).
    func joinParty(partyId: Int64) async throws -> PartyStatus

    /// 나가기. DELETE /api/v1/matching/leave/{partyId}. 나가는 주체는 토큰이 정한다.
    /// 성공 시 Explore 목록 재조회 필요.
    ///
    /// 마지막 멤버가 나가면 방은 CANCELED 로 닫힌다(실측).
    ///
    /// 그 방의 멤버가 아니면 서버는 403 `NOT_PARTY_MEMBER` 를 주는데, **그 403 은 실패로 올라오지
    /// 않는다** — 데이터 계층이 성공으로 되돌린다. 「이미 나갔다」와 「나가기 성공」은 사용자가 할 일이
    /// 같기 때문이다(204 응답이 터널에서 유실되고 재시도하면 바로 이 경우가 된다). `joinParty` 의
    /// `PartyJoinException.isAlreadyInThisParty` 복구와 대칭이다.
    ///
    /// 나머지 실패는 `PartyLeaveException` 이다(409 `PARTY_NOT_RECRUITING` — 매칭이 시작돼 나갈 수 없다 /
    /// 404 `PARTY_NOT_FOUND` / 네트워크).
    func leaveParty(partyId: Int64) async throws

    /// POST /api/v1/matching/rooms/{partyId}/finish (204) — 합승을 끝낸다.
    /// 정원이 찬(`COMPLETED`) 방을 닫는 **유일한 길**이다 — 한 명이 닫으면 **모두의** 방이
    /// `FINISHED` 가 된다. (예전에는 기사가 운행을 끝내는 길이 따로 있어 이쪽이 「1차 배포 모드 전용」
    /// 이었지만, 기사·배차가 사라져 이제 분기가 없다.)
    ///
    /// **방장 전용이다**: Backend #237 이 이 API 를 방장에게만 허용했고, 2026-10-15 **운영에 배포됐다**.
    /// 방장은 저장되는 값이 아니라 **지금 멤버 중 가장 먼저 합류한 사람**이고(`Party.hostId()` =
    /// `min(joinedAt, memberId)`), 방장이 나가면 자동 승계된다.
    ///
    /// **앱은 방장을 식별할 수 있다** — 서버가 멤버마다 `members[].host` 를 내려 준다(Backend #240,
    /// 반영 완료). 내부 PK `hostId` 는 응답에서 제거됐다. 그래서 호출부는 **버튼 노출을 먼저 막고**
    /// (`canFinishParty` = 손으로 닫는 단계 && `Ride.isHostedByMe`), 실패 사유 안내는 그 뒤에 남는
    /// 틈을 받는다 — 승계 신호를 놓치거나 순서가 역전돼 **내 스냅샷이 낡았을** 때 403 이 온다.
    /// **「앱은 방장을 알 수 없다」로 되돌리지 말 것**: 그 서술은 `host` 가 붙기 전의 사실이고,
    /// 그대로 믿으면 방장 게이팅이 근거 없는 추정으로 읽혀 지워진다.
    ///
    /// 실패는 모두 `PartyFinishException` 으로 올라온다 — **403 이 두 가지 뜻**이라
    /// (`NOT_PARTY_HOST`·`NOT_PARTY_MEMBER`, 그리고 409 `PARTY_NOT_COMPLETED`) 화면은 상태 코드가
    /// 아니라 그 예외의 프로퍼티로 분기한다. 모르는 코드·본문 없음은 code = null 이고 화면이 일반
    /// 문구로 떨어진다.
    func finishParty(partyId: Int64) async throws

    /// POST /api/v1/matching/rooms/{partyId}/confirm (204) — 방장이 **약속 시간을 확정한다**.
    /// 본문은 `{"departureAt": "..."}` 하나이고, 장소는 싣지 않는다 — 약속 장소는 **늘 방의 출발지**다.
    ///
    /// 이게 방을 끝내는 **정식 경로의 첫 단계**다: 확정 → 각자 「출발지 도착」 → 누군가 「출발」.
    /// `finishParty` 는 **확정 전 방에만** 남는다 — 확정된 방에 부르면 서버가 409
    /// `USE_DEPART_FOR_CONFIRMED_PARTY` 로 거절한다.
    ///
    /// ### `departureAt` 의 모양이 곧 성패다 ★
    /// ISO-8601 **순간**(instant) 문자열이어야 한다 — `"2026-11-03T08:30:00Z"` 처럼 `Z` 로 끝나거나
    /// `+09:00` 같은 오프셋이 붙어야 하고, `ISO8601DateFormatter` 의 기본 출력(UTC, `Z`)을 그대로 넣으면 맞다.
    /// **오프셋 없는 로컬 시각(`"2026-11-03T17:30:00"`)은 400 이다** — 서버가 `Instant` 로 읽지 못한다.
    /// 그 400 은 `PartyConfirmException` 의 어느 사유도 아니라
    /// (code 는 `INVALID_REQUEST`) 화면에 일반 문구로 떨어진다 — 원인을 찾기 가장 어려운 실패다.
    ///
    /// 서버가 받는 범위는 **지금부터 1시간 안**이고 과거 쪽으로는 1분의 시계 오차만 봐준다. 그래서
    /// 화면은 프리셋(10·20·30·45·60분 후)으로만 고르게 한다 — 자유 입력은 사용자가 만들 수 있는 400 이다.
    ///
    /// 성공하면 **방의 성질이 바뀐다**: 모집이 끝나고(ACTIVE→COMPLETED) 아무도 나갈 수 없다
    /// (409 `CANNOT_LEAVE_CONFIRMED_PARTY`). 화면 갱신은 따로 읽지 않아도 된다 —
    /// SSE `PartyEvent.confirmed` 가 상태와 약속 시간을 싣고 온다(`observePartyEvents`).
    ///
    /// 실패는 모두 `PartyConfirmException` 으로 올라온다
    /// (403 `NOT_PARTY_HOST`·`NOT_PARTY_MEMBER` / 409 `NOT_REALTIME_PARTY`·`ALREADY_CONFIRMED`·
    /// `PARTY_NOT_RECRUITING`·`NOT_ENOUGH_MEMBERS` / 400 `INVALID_MEETING_TIME` / 404 / 네트워크).
    /// **한 문구로 뭉개면 안 된다** — 사유마다 다음 행동이 다르고, 그 근거는 그 예외 주석의 표에 있다.
    func confirmMeeting(partyId: Int64, departureAt: String) async throws

    /// POST /api/v1/matching/rooms/{partyId}/arrive (204) — **출발지에 도착했다**고 알린다.
    /// 본문은 `{"latitude": …, "longitude": …}`, **지금 내 위치**다(방의 출발지 좌표가 아니다 —
    /// 서버가 그 둘의 거리를 재서 100m 안인지 판정한다).
    ///
    /// 받아 주는 조건은 둘이다: 약속이 확정된 방일 것, 그리고 **약속 시간 10분 전부터**일 것.
    /// (서버 `Party.arrive` 는 `now < departureAt − 10분`(`ARRIVAL_OPENS_BEFORE`) 이면 409
    /// `ARRIVAL_NOT_OPEN` 이다. 「약속 시간 정각부터」·`MEETING_NOT_STARTED` 는 백엔드 PR #307 전의
    /// 규칙이고, 지금 `MEETING_NOT_STARTED` 는 출발에서만 온다 — `PartyArriveException` 주석.)
    ///
    /// **멱등이다.** 이미 도착한 사람이 다시 불러도 204 이고, 최초 도착 시각이 유지되며 version 도
    /// SSE 도 움직이지 않는다 — 응답을 놓쳐 다시 보내도 안전하다.
    ///
    /// 성공하면 SSE `PartyEvent.memberArrived` 가 **그 한 명의** publicId 를 싣고 온다
    /// (내 도착도 나에게 온다). 화면은 그 사람의 `User.hasArrived` 만 켜면 된다.
    ///
    /// 실패는 모두 `PartyArriveException` 으로 올라온다
    /// (400 `TOO_FAR_FROM_DEPARTURE`·`OUT_OF_SERVICE_AREA` / 403 `NOT_PARTY_MEMBER` /
    /// 409 `PARTY_CLOSED`·`PARTY_NOT_CONFIRMED`·`ARRIVAL_NOT_OPEN` / 404 / 네트워크).
    /// 「멀다」와 「아직 시간 전이다」를 뭉개면 **이미 출발지에 서 있는 사람에게 더 가까이 가라**고 말한다.
    func arriveAtDeparture(partyId: Int64, latitude: Double, longitude: Double) async throws

    /// POST /api/v1/matching/rooms/{partyId}/depart (204, 본문 없음) — **출발한다 = 방을 끝낸다.**
    ///
    /// ⚠️ **되돌릴 수 없고, 남에게 제재를 남긴다.** 이 호출이 성공한 순간 방은 FINISHED 가 되고,
    /// 그때까지 도착을 누르지 않은 멤버는 **전부 노쇼로 기록된다**(노쇼 횟수 × 24시간 이용 제한,
    /// 약속 시간부터 센다). 앱에는 취소하는 길이 없다 — 화면은 누르기 전에 반드시 확인을 받아야 한다.
    /// 서버가 `restrictedUntil` 로 알려 주는 그 제재를, 만드는 쪽이 바로 이 호출이다.
    ///
    /// **방장 전용이 아니다** — 도착한 멤버면 누구나 누를 수 있다(`finishParty` 와 다른 점이다).
    /// 조건은 약속 시간 **뒤**일 것, 멤버 2명 이상일 것, 그리고 **내가 도착해 있을 것**.
    ///
    /// 성공하면 SSE `PartyEvent.closed` 가 오고 **서버가 그 방의 구독을 끊는다** — 화면은 그 신호로
    /// 닫으면 된다(이 호출의 반환을 기다릴 필요가 없다). 다른 멤버가 먼저 눌렀다면 내 호출은 409
    /// `PARTY_CLOSED` 인데, 그건 실패가 아니라 **종료**로 보여 주는 쪽이 맞다.
    ///
    /// 실패는 모두 `PartyDepartException` 으로 올라온다
    /// (409 `PARTY_CLOSED`·`PARTY_NOT_CONFIRMED`·`NOT_ENOUGH_MEMBERS`·`MEETING_NOT_STARTED`·
    /// `NOT_ARRIVED` / 403 `NOT_PARTY_MEMBER` / 404 / 네트워크).
    func departParty(partyId: Int64) async throws

    // 기사 요약 조회(`GET /rooms/{partyId}/driver`)와 긴급 신고 두 개
    // (`POST /api/v1/reports`·`PATCH /api/v1/reports/call-result`)는 **지웠다** — 기사·배차가
    // 사라지면서 부를 화면(25 배차 상태·26 운행 중·긴급)이 함께 없어졌다. 채팅 메시지 신고
    // (`ChatRepository.reportMessage`)는 **다른 기능이고 그대로 남아 있다**.

    // ───────────────────────── 예약 방 ─────────────────────────
    //
    // 예약은 **같은 저장소에 둔다.** 서버가 「참여·나가기·상세·SSE 는 기존 방 API 를 쓴다」라고
    // 못 박았고(`PartyController.reserve` 의 Swagger), 그 말대로면 예약만 다루는 저장소는 **조회 셋과
    // 생성 하나**를 들고 나머지는 전부 이쪽으로 위임하는 얇은 껍데기가 된다 — 호출부가
    // 「방 id 를 어느 저장소에 물어야 하나」를 매번 되묻게 되는 구조다. 돌려주는 것도 같은 `Ride` 다.
    //
    // 노쇼(`NoShowRepository`)를 따로 뺀 것과 **반대 방향의 판단**이고
    // 기준은 하나다: **같은 모델로 같은 동작을 하는가.** 예약은 방이라 그렇고, 노쇼는 끝난 방에
    // 남은 제재라 아니다.

    /// **예약 방 생성.** POST /api/v1/matching/reservations (200, 생성된 방).
    ///
    /// `createParty` 와 **응답이 같아** 그대로 다음 화면에 넘길 수 있다. 다른 점은 셋이다:
    /// 정원이 **2~3**(`NewReservation.capacity`), 출발 시각이 **필수**, 그리고 **경로·요금·시간이
    /// 비어 있다**(서버가 예약 방의 경로를 추정하지 않는다 — `Ride.estimatedFare`·
    /// `Ride.estimatedMinutes`·`Ride.routePolyline` 이 null 이고 `Ride.farePerPerson` 은 0 이다).
    /// 그 0 을 「공짜」로 그리지 말 것.
    ///
    /// 돌려주는 방은 **처음부터 확정**이다(`Ride.isConfirmed` true, `Ride.roomType`
    /// `RoomType.reservation`) — 즉 「약속 시간 정하기」를 띄우면 안 되고
    /// (`confirmMeeting` 이 409 `NOT_REALTIME_PARTY`), **「그만 찾기」도 띄우면 안 된다**
    /// (`leaveParty` 가 409 `CANNOT_LEAVE_CONFIRMED_PARTY`). 예약을 만든 사람에게는 방을 벗어날 길이
    /// 없는 셈이라, 화면은 **만들기 전에** 확인을 받는 쪽이 맞다.
    ///
    /// 성공 뒤 갱신 대상: 홈·탐색의 진행 중 방 배너(진행 중인 방이 하나 생겼다)와, 예약 목록·검색을
    /// 보여 주는 화면(새 방이 그 목록에 들어간다 — 서버 필터가 `ACTIVE` 라 바로 보인다).
    ///
    /// 실패는 `createParty` 와 **같은 `PartyOpenException`** 으로 올라온다(403 `NO_SHOW_RESTRICTED` /
    /// 409 `ALREADY_JOINED_OTHER_PARTY`·`PARTY_TIME_CONFLICT` / 400 `INVALID_DEPARTURE_TIME`·
    /// `INVALID_CAPACITY`·`INVALID_REQUEST`·`SAME_DEPARTURE_DESTINATION`·`OUT_OF_SERVICE_AREA` /
    /// 네트워크). 실시간 표에 갈래가 없는 둘은 `PartyOpenException.isPartyTimeConflict`·
    /// `PartyOpenException.isInvalidDepartureTime` 이고(앞의 것은 실시간 생성에도 오고, 예약 전용은
    /// 뒤의 것 하나다 — 기준 시각이 여기서는 출발 시각이다), 경로 세 코드는 **오지 않는다**
    /// (서버가 예약 방의 경로를 추정하지 않는다). 한 예외로 둔 근거는 그 주석에 있다.
    ///
    /// ⚠️ **`PartyOpenException.isInvalidCapacity` 의 문구만은 호출부가 갈라야 한다** — 범위가
    /// 실시간 1~3, 예약 2~3 이라 공통 문구를 쓰면 예약에서 400 을 맞은 사람에게 **고를 수 없는 1 을
    /// 고르라고** 말하게 된다. 그리고 예약의 정원 1 은 그 코드로도 오지 않는다(400 `INVALID_REQUEST`).
    func createReservation(request: NewReservation) async throws -> Ride

    /// **기간으로 보는 예약 목록.** GET /api/v1/matching/reservations?from=&to=
    ///
    /// `from`·`to` 는 **ISO-8601 instant 문자열**이고 둘 다 필수다(`"2026-11-13T00:00:00Z"`).
    /// `from >= to` 면 400 `INVALID_TIME_RANGE` — 같은 시각도 거절된다.
    ///
    /// 돌려주는 `Ride` 는 `getParties` 의 것과 **같은 모델이되 채워진 자리가 다르다**:
    /// 출발·도착 좌표가 **둘 다** 있고(`getParties` 는 출발만), `Ride.departureAt` 이 채워져 있고,
    /// `Ride.roomType` 이 `RoomType.reservation` 이며
    /// `Ride.isConfirmed` 가 true 다. 요금·경로는 없다(상세를 읽어도 없다 — 서버가 추정하지 않는다).
    ///
    /// **뷰포트와 무관하다** — 지도에 보이는 것만 거르려면 `getReservationsSoon` 다.
    ///
    /// 실패를 전용 예외로 감싸지 않는다(조회의 관례). 400 두 가지는 **앱이 만드는 실패**라
    /// 화면 문구로 가릴 값이 아니고, `from`·`to` 를 앱이 만드므로 애초에 나지 않아야 한다.
    func getReservations(from: String, to: String) async throws -> [Ride]

    /// **곧 출발하는 예약** — 지도 범위 안, 지금부터 **30분 내** 출발.
    /// GET /api/v1/matching/reservations/soon?swLat=&swLng=&neLat=&neLng=
    ///
    /// `getPartiesWithin` 과 **파라미터 이름·순서가 같고 뜻도 같다**(남서 → 북동). 다른 점은 돌려주는
    /// 방이 예약뿐이라는 것 하나다. 뷰포트 검사도 같다 — 서버가 두 조회 모두 **엄격 비교**로 보고
    /// `swLat >= neLat || swLng >= neLng` 면 400 `INVALID_MAP_BOUNDS` 라 **남서·북동이 같은 점인
    /// 뷰포트도 거절된다**(완전히 줌인했을 때 생길 수 있다). 즉 **같은 좌표를 넘기면 두 호출이 함께
    /// 400 으로 실패한다.** 화면은 뷰포트가 0 폭일 때 어느 쪽도 부르지 않아야 한다.
    ///
    /// 30분은 서버 상수라 앱이 바꿀 수 없다. 최대 100건. 빈 목록은 정상이다.
    ///
    /// **`searchReservations` 와 달리 `Ride` 를 그대로 돌려준다** — 이 응답에는 `destinationNearby`
    /// 가 **없다**(도착지를 물은 적이 없다). 세 조회의 반환 타입을 억지로 맞추려고 여기까지
    /// `ReservationSearchResult` 로 감싸면, 늘 null 인 필드를 들고 다니며 화면이 「이 null 은 어느
    /// null 인가」를 되묻게 된다 — 「물어보지 않았다」와 「도착지가 멀다」를 가르려고 둔 구분이
    /// 그 자리에서 무의미해진다. 타입이 **무엇을 물었는지**를 말해 주는 쪽을 택했다.
    func getReservationsSoon(
        swLat: Double,
        swLng: Double,
        neLat: Double,
        neLng: Double
    ) async throws -> [Ride]

    /// **예약 검색** — 출발지 **1km** 안에서 고른 **하루**의 예약, 최대 100건.
    /// GET /api/v1/matching/reservations/search?depLat=&depLng=&date=&destLat=&destLng=
    ///
    /// ### `date` 는 **한국 달력 날짜**다 — instant 가 아니다 ★
    /// 모양은 `yyyy-MM-dd`(`"2026-11-13"`)이고, 서버가 `Asia/Seoul` 기준으로 하루를 자른다.
    /// 그래서 호출부는 **KST 달력의 날짜**를 만들어 넘겨야 한다 — 기기 시간대가 KST 가 아닌
    /// 사용자(해외 체류·수동 설정)가 기기 로컬 날짜를 넘기면 **하루 밀린 결과**를 보고, 그게
    /// 「오늘인데 왜 비어 있지」로 나타난다. ISO instant 를 넘기면 400 `INVALID_REQUEST` 다.
    ///
    /// 허용 범위는 **오늘 ~ 7일 뒤(양 끝 포함)**, 벗어나면 400 `INVALID_SEARCH_DATE`.
    /// 화면은 날짜 피커를 그 범위로 가두는 쪽으로 책임을 진다 — 그러면 이 400 이 나지 않는다.
    /// 오늘을 고르면 **이미 출발한 방은 빠진다**(서버가 하루의 시작을 `max(지금, 자정)` 으로 잡는다).
    ///
    /// ### `destination` 은 선택이고, **타입이 그 선택을 강제한다**
    /// 서버는 좌표 두 개를 **둘 다 받거나 둘 다 빼야** 하고 하나만 오면 400
    /// `INCOMPLETE_DESTINATION` 이다. 그래서 파라미터를 `Double?` 두 개로 두지 않았다 —
    /// 근거는 `ReservationDestination` 주석에 있다.
    ///
    /// 넘기면 각 결과에 `ReservationSearchResult.destinationNearby` 가 채워지고
    /// **true 가 먼저** 정렬된다(그 안에서 출발 시각 순). 빼면 출발 시각 순이고 그 값은 **null** 이다
    /// — null 을 false 로 읽어 「도착지가 멀어요」를 그리면 **묻지 않은 것에 답하는** 꼴이 된다.
    ///
    /// **재정렬하지 말 것.** 받은 순서가 서버의 정렬이다(`MatchCandidate` 와 같은 규약).
    /// 빈 목록은 정상이다(1km 안에 그날 예약이 없다).
    func searchReservations(
        departureLat: Double,
        departureLng: Double,
        date: String,
        destination: ReservationDestination?
    ) async throws -> [ReservationSearchResult]

    /// POST /api/v1/matching/routes — 방을 만들기 전 좌표만으로 보는 경로 미리보기.
    ///
    /// 예상 요금·소요시간과 인코딩 폴리라인(`RouteEstimate.encodedPath`)을 돌려준다.
    /// 이미 만들어진 방의 경로는 `getPartyDetail` 의 `routePolyline` 으로 얻는다.
    func previewRoute(
        departureLat: Double,
        departureLng: Double,
        destinationLat: Double,
        destinationLng: Double
    ) async throws -> RouteEstimate
}

// Kotlin 인터페이스의 기본 구현 자리.
extension RideRepository {
    public func observePartyEvents(partyId: Int64) -> AsyncThrowingStream<PartyEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    // Kotlin 기본 인자 `destination: ReservationDestination? = null` 의 자리 — 도착지 없는 검색.
    public func searchReservations(
        departureLat: Double,
        departureLng: Double,
        date: String
    ) async throws -> [ReservationSearchResult] {
        try await searchReservations(departureLat: departureLat, departureLng: departureLng, date: date, destination: nil)
    }
}
