/// 경로 기준: `matching/party/PartyController.java`
/// (@RequestMapping("/api/v1") + 메서드별 "/matching/...").
/// 노쇼 두 개만 **다른 컨트롤러**다: `matching/noshow/NoShowController.java`
/// (@RequestMapping("/api/v1/matching") + 메서드별 "/no-shows"·"/rooms/{partyId}/no-show-objection").
/// 프리픽스를 합산한 결과가 같으므로 앱에서는 한 인터페이스에 둔다.
///
/// (경로 메모 수정 2026-11-06: 백엔드에는 `interfaces/` 디렉터리가 **없다** — 이 주석이 오래
/// `matching/interfaces/` 아래의 `PartyController.java` 를 가리키고 있었다. 실제 위치는 도메인별로
/// `matching/party/`·`matching/noshow/` 또는 `…/presentation/` 이다. 파일을 찾으러 간 사람이
/// 「컨트롤러가 사라졌다」로 결론 내리지 않도록 고쳐 둔다.)
///
/// 주의: backend/http/matching.http 의 **앞 세 요청**은 v1 이 없는 옛 경로 + 옛 필드명(hostId)이라
/// 신뢰하지 않는다. 예약·노쇼 요청(4번 이후)은 컨트롤러와 일치한다.
///
/// **여기 전부가 토큰 필수다.** 목록·상세 조회까지 포함해 예외가 없다
/// (Security 가 `/api/v1/auth/` 하위를 뺀 전 경로에 `anyRequest().authenticated()` 를 건다).
/// 미로그인 상태에서 부르면 화면에 데이터 대신 401 에러가 뜨므로,
/// 이 API 를 쓰는 화면은 로그인 뒤에만 열려야 한다.
public protocol MatchingApi: Sendable {
    func getParties() async throws -> PartyListResponse

    /// 지도 화면 범위(남서·북동 모서리) 안의 ACTIVE 방 목록.
    /// 전체 목록과 **경로가 같고** 서버(PartyController.listWithin)가 `params={swLat,swLng,neLat,neLng}`
    /// 유무로 핸들러를 고른다 — 4개 중 하나라도 빠지면 전체 목록 핸들러로 떨어진다.
    /// 응답 아이템에는 departureLat/departureLng 가 포함된다.
    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> PartyListResponse

    /// 방 상세. 멤버 목록·요금·경로 폴리라인까지 전부 담긴다(`PartyController.detail`).
    /// SSE `connected` 이벤트의 data 와 **같은 모양**이라 DTO·매퍼를 공유한다.
    ///
    /// 서버 메서드에 `@CurrentUser` 가 없지만 **토큰은 필수다** — Security 가 `/api/v1/auth/` 밖
    /// 전 경로에 `anyRequest().authenticated()` 를 건다. 참여자 검사는 없다.
    ///
    /// **주기 조회(SSE 가 끊긴 동안의 폴백 폴링)가 부르는 것도 이 호출이다.** 가벼운 전용 상태 조회
    /// `GET /rooms/{partyId}/status` 는 백엔드에서 **삭제됐다**(`04f6be7`) — 지금 부르면 404 다.
    /// 그 호출은 서버 쿼리 1개였고 이건 **3개**(방 + 멤버 요약 + 탑승 횟수)에 route 까지 실으므로,
    /// 부르는 화면은 간격을 벌려야 한다(부하테스트에서 상세 폴링이 전체 요청의 45% — Backend #177).
    func getPartyDetail(partyId: Int64) async throws -> PartyDetailResponse

    /// 방 생성. **방장은 이제 Bearer 토큰이 정한다**
    /// (`PartyController.open(@CurrentUser Long memberId, @RequestBody OpenPartyRequest request)`).
    ///
    /// 서버 record 에 `creatorId` 필드가 남아 있긴 하지만 `toCommand(creatorMemberId)` 가 이를 버리고
    /// 토큰 주체를 쓴다 — 구버전 호환용 잔재다. 그래서 앱은 아예 보내지 않는다
    /// (실측: creatorId 없이 200, 토큰 주체가 방장으로 기록됨).
    /// 리포트 22번 D-5("내가 만든 방에 내가 없는" 상태)는 이것으로 해소됐다.
    ///
    /// **반경도 요청에 없다** — 서버가 `OpenPartyRequest` 에서 빼고 고정값(500m)을 쓴다
    /// (Backend `a668aee`, Swagger 「반경은 서버 고정값(500m)」). 400 목록에서 `INVALID_RADIUS` 도 빠졌다.
    func openParty(request: OpenPartyRequestDto) async throws -> OpenPartyResponse

    /// 합류. 요청 본문은 없다.
    ///
    /// **응답이 방 상세에서 `PartyStatusResponse{status, currentMembers}` 로 바뀌었다**
    /// (Backend #213, `PartyController.join` 의 반환 타입). 즉 **동승자 목록이 오지 않는다** —
    /// 필요하면 `getPartyDetail` 을 따로 불러야 한다(서버 Swagger 는 "동승자 목록은 SSE 구독(/events)의
    /// connected 로 받는다" 로 갱신됐다 — `04f6be7`).
    ///
    /// 그 `04f6be7` 에서 **`fingerprint` 필드도 빠졌다** — 응답은 이제 두 값뿐이다. 서버가 아직 옛
    /// 버전이라 지문을 실어 보내도 디코더가 모르는 키를 흘린다(`MoyeotaJSON`).
    ///
    /// 응답의 `status` 는 합류 **직후**의 방 상태다 — 내가 마지막 자리를 채웠으면 서버가 그 자리에서 정원 충족
    /// 처리까지 끝내고 `COMPLETED` 를 돌려준다(기사 모드의 `MATCHING` 은 서버에서 사라졌다).
    ///
    /// 합류자는 **Bearer 토큰에서 추출**된다(`PartyController.join(@PathVariable Long partyId, @CurrentUser Long memberId)`)
    /// — 경로의 memberId 는 사라졌다. 토큰 없이 호출하면 401 `{"code":"USER005","message":"로그인이 필요합니다."}`.
    func joinParty(partyId: Int64) async throws -> PartyStatusResponse

    /// 나가기. 204 No Content — 응답 본문이 없다. 나가는 주체는 Bearer 토큰이 정한다.
    ///
    /// 이전에 붙어 있던 더미 `/0` 세그먼트는 **사라졌다** — 백엔드가 매핑을
    /// `@DeleteMapping("/matching/leave/{partyId}")` 로 정리했다.
    /// 실측: `/leave/{id}` → 204, `/leave/{id}/0` → 404. 옛 형태를 되살리면 조용히 404 다.
    func leaveParty(partyId: Int64) async throws

    /// 합승 종료. 204. `PartyController.finish`.
    /// COMPLETED(정원 참) 방에서만 되고, 참여자 누구든 한 명이 부르면 방 전체가 FINISHED 다.
    /// 예전에는 「기사 없이 끝내는 1차 배포 모드 전용」이었지만, 기사가 운행을 끝내는 길이
    /// 서버에서 사라져 지금은 방을 닫는 유일한 길이다.
    func finishParty(partyId: Int64) async throws

    /// 약속 시간 확정. 204. `PartyController.confirm`.
    ///
    /// **방을 끝내는 정식 경로의 첫 단계다.** 서버 Swagger 가 `finishParty` 를 「구버전 앱용 이전 경로」로
    /// 적어 두었고, 확정된 방에 그걸 부르면 409 `USE_DEPART_FOR_CONFIRMED_PARTY` 로 거절한다 —
    /// 확정 → `arrive` → `depart` 가 지금의 정식 경로다.
    ///
    /// 방장만, **실시간 방만**, 멤버 2명 이상, 모집 중(ACTIVE 또는 COMPLETED), 한 번만.
    /// 본문은 `{"departureAt": "<ISO-8601 instant>"}` 하나다 — 약속 장소는 **늘 방의 출발지**라
    /// 서버가 받지 않는다. 시간 형식의 함정은 `ConfirmMeetingRequestDto` 에 적어 두었다.
    ///
    /// 성공하면 모집이 끝나고(ACTIVE→COMPLETED) **아무도 나갈 수 없다**(409
    /// `CANNOT_LEAVE_CONFIRMED_PARTY`). 그 사실은 SSE `confirmed` 로 모든 멤버에게 전해진다.
    func confirmMeeting(partyId: Int64, request: ConfirmMeetingRequestDto) async throws

    /// 출발지 도착. 204. `PartyController.arrive`.
    ///
    /// 본문은 **지금 내 위치**(`latitude`/`longitude`)다 — 서버가 방 출발지와의 거리를 PostGIS
    /// `ST_DWithin` 으로 재서 100m 안인지 본다(`ArriveRequestDto` 에 왜 방 좌표를 보내면 안 되는지 적었다).
    ///
    /// 열리는 시점은 **약속 시간 10분 전부터**다(서버 `Party.arrive` 의
    /// `now < departureAt − ARRIVAL_OPENS_BEFORE(10분)` 검사는 409 `ARRIVAL_NOT_OPEN` — 백엔드 PR #307 전의
    /// 「정각부터 · `MEETING_NOT_STARTED`」가 아니다). **멱등이다**: 이미 도착한 사람이 다시
    /// 불러도 204 이고 시각·version·SSE 가 모두 그대로다.
    func arriveAtDeparture(partyId: Int64, request: ArriveRequestDto) async throws

    /// 출발 — 방을 끝낸다. 204, **요청 본문 없다**. `PartyController.depart`.
    ///
    /// **방장이 아니어도 된다**(`finishParty` 와 다른 점이다) — 도착한 멤버면 누구나. 조건은 약속 시간
    /// **뒤**일 것, 멤버 2명 이상일 것, 부른 사람이 도착해 있을 것.
    ///
    /// ⚠️ 그 순간 **도착하지 않은 멤버는 전부 노쇼로 기록된다**(노쇼 횟수 × 24시간 이용 제한).
    /// 앱에는 되돌릴 길이 없다 — 본문이 없어 "실수로 호출"을 막아 주는 것도 없으므로, 화면 쪽에서
    /// 확인을 받고 부를 것.
    ///
    /// 성공 뒤 서버가 `closed` 를 보내고 **그 방의 SSE 연결을 끊는다**.
    func departParty(partyId: Int64) async throws

    /// 방을 만들기 전 출발·도착 좌표만으로 예상 요금·소요시간·경로를 미리 본다.
    ///
    /// 백엔드가 `@PostMapping` + `@RequestBody RouteRequest` 로 바뀌어 열린 엔드포인트다
    /// (이전 `@GetMapping` + body 조합은 요청 자체를 만들 수 없어 호출 불가였다).
    /// 응답 폴리라인 필드명이 **path** 다 — 방 상세/생성 응답의 `route` 와 이름이 다르니 주의.
    func previewRoute(request: RouteRequestDto) async throws -> RouteEstimateResponse

    /// 내 출발·도착 좌표로 **걸어서 가까운 방**을 추천받는다(서버가 양쪽 300m 안에서 고르고 OSRM
    /// 도보 시간 합으로 정렬해 최대 5개).
    ///
    /// **조회인데 POST 다** — 좌표 4개를 바디로 받는 서버 설계라 캐시되지 않는다.
    /// 응답 **최상위가 배열**이고 빈 배열이 정상이다.
    ///
    /// 실패는 넷이다: 400 `OUT_OF_SERVICE_AREA`(좌표가 서비스 지역 밖 **또는 요청 필드명 오타**),
    /// 401, 409 `ALREADY_JOINED_OTHER_PARTY`(이미 방에 들어가 있으면 추천 자체가 막힌다),
    /// 502 `ROUTE_SEARCH_FAILED`(OSRM 실패).
    func getRealtimeCandidates(request: RealTimeMatchingRequestDto) async throws -> [MatchCandidateResponse]

    /// **내 노쇼 기록**. 200. 기준: `matching/noshow/NoShowController.java`
    /// (`@RequestMapping("/api/v1/matching")` + `@GetMapping("/no-shows")`).
    ///
    /// 조회 주체는 토큰이 정한다(`@CurrentUser`) — 경로·쿼리에 식별자가 없다. 쿼리 파라미터가
    /// **하나도 없다**: 커서도, 개수도, 필터도 없다. 서버가 최신순 **최대 20건**으로 잘라 주고
    /// (`NoShowRepositoryDefaults.HISTORY_LIMIT`) 그게 전부다 —
    /// 탑승 기록(`users/me/parties`)처럼 `size`·`cursor` 를 붙이면 **400 이 아니라 조용히 무시**된다
    /// (그쪽 주석의 `status` 함정과 같다). 「더 보기」를 만들 수 없는 이유가 이것이다.
    ///
    /// **엔벨로프 키가 `noShows` 다**(예약·방 목록의 `list` 와 다르다 — `MyNoShowListResponse` 주석).
    ///
    /// 실패는 **401 하나뿐이다.** 서버가 이 조회에 업무 에러 코드를 두지 않았고(컨트롤러의
    /// `@ApiResponses` 에 200 만 있다) 기록이 없어도 404 가 아니라 `{"noShows":[]}` 다.
    /// 그래서 저장소도 전용 예외로 좁히지 않는다.
    func getMyNoShows() async throws -> MyNoShowListResponse

    /// **노쇼 이의 신청**. 기준: `matching/noshow/NoShowController.java`
    /// (`@PostMapping("/rooms/{partyId}/no-show-objection")`).
    ///
    /// ### 이 도메인에서 **유일하게 201** 인 액션이다 ★
    /// 나머지 액션은 204(확정·도착·출발·나가기·완료)거나 200(생성)인데 이것만
    /// `ResponseEntity.status(CREATED)` 이고 **본문이 비어 있다**(`Location` 헤더도 없다).
    /// 반환 타입을 붙이면 디코더가 빈 본문에서 터지므로 **반환값이 없다**(`RestClient.callUnit`) —
    /// 성공의 증거는 상태 코드뿐이고, 접수된 내용은 `getMyNoShows` 를 다시 읽어 확인한다.
    ///
    /// 경로가 `/rooms/{partyId}/…` 라 방 액션들과 **같은 가지에 있는데 컨트롤러가 다르다.** 오타는
    /// 404 가 아니라 **401** 로 떨어져 세션 만료로 오인하기 쉬운 자리다(이 파일의 다른 주석과 같은
    /// 함정) — 값은 `AuthenticatedPathContractTest` 가 못 박는다.
    ///
    /// 방마다 **한 번만** 된다(서버 유니크 제약). 실패 사유는 다섯이고 전부
    /// `NoShowObjectionException` 으로 좁혀 올린다 — 그중 둘은 409 라
    /// 상태 코드로는 갈리지 않는다.
    func submitNoShowObjection(partyId: Int64, request: NoShowObjectionRequestDto) async throws

    /// **예약 방 생성**. `PartyController.reserve`.
    ///
    /// ### 응답이 `openParty` 와 **같은 record 이고, 201 이 아니라 200 이다**
    /// 서버가 `ResponseEntity.ok(OpenPartyResponse…)` 를 돌려주므로 생성 응답 DTO·매퍼를 그대로
    /// 재사용한다. 「생성이니 201」이라고 가정하지 말 것 — 같은 PR 의 이의 신청만 201 이다.
    ///
    /// **경로·예상 요금·예상 시간이 전부 null 로 온다**(서버 `Party.reserve` 가 `null, null, null` 을
    /// 박는다). 결함이 아니라 계약이다 — 예약 방은 서버가 경로를 추정하지 않는다. 그래서 이 액션에는
    /// `ROUTE_SEARCH_FAILED` 류 실패가 **없고**, 응답의 `roomType` 은 늘 `"RESERVED"`,
    /// `departureAt` 은 요청한 시각이다.
    ///
    /// **참여·나가기·상세·SSE 는 전용 엔드포인트가 없다** — 기존 방 API 를 그대로 쓴다
    /// (`joinParty`·`leaveParty`·`getPartyDetail`, SSE). 서버 Swagger 가 그렇게 못 박았다.
    /// ⚠️ 다만 **예약 방에서 `leaveParty` 는 언제나 409 `CANNOT_LEAVE_CONFIRMED_PARTY` 다**:
    /// 예약은 합류한 순간부터 확정 상태라(`confirmed = true`) 나갈 수 없다. 화면은 예약 방에
    /// 「그만 찾기」를 **띄우면 안 된다** — 누를 수 없는 버튼이다.
    /// ⚠️ 출발 시각이 지난 예약에 합류하면 409 `PARTY_CLOSED` 다.
    ///
    /// 실패는 `PartyController.reserve` 의 `@ApiResponses` 기준으로
    /// 400 `SAME_DEPARTURE_DESTINATION`·`INVALID_CAPACITY`·`OUT_OF_SERVICE_AREA`·
    /// `INVALID_DEPARTURE_TIME`·`INVALID_REQUEST` / 403 `NO_SHOW_RESTRICTED` /
    /// 409 `ALREADY_JOINED_OTHER_PARTY`·`PARTY_TIME_CONFLICT` 다 —
    /// `PartyOpenException` 으로 좁힌다 — 방 생성과 **같은 예외**이고,
    /// 실시간 표에 갈래가 없는 둘은 그 예외의 `isPartyTimeConflict`·`isInvalidDepartureTime` 이다
    /// (`PARTY_TIME_CONFLICT` 는 실시간 생성에도 오고, 예약 전용은 `INVALID_DEPARTURE_TIME` 하나다).
    func createReservation(request: OpenReservationRequestDto) async throws -> OpenPartyResponse

    /// **기간으로 보는 예약 목록**. `PartyController.listReservations`.
    ///
    /// 두 파라미터 모두 **ISO-8601 instant 문자열이고 필수다**(서버가 `@RequestParam Instant`).
    /// `from >= to` 면 400 `INVALID_TIME_RANGE`, 모양이 깨지면 400 `INVALID_REQUEST` 다.
    ///
    /// ⚠️ **둘 중 하나를 빼면 응답 본문이 `{code, message}` 가 아니다.** 서버
    /// `GlobalExceptionHandler` 에 누락 파라미터 핸들러가 없어 스프링 기본 에러 JSON 이 온다 —
    /// 즉 `readApiError` 가 code 를 못 찾고 화면은 일반 문구로 떨어진다.
    /// 그래서 파라미터를 **non-null 로 둔다**: nil 이면 `RestClient` 가 그 쿼리 키를 아예 빼 버려
    /// (탑승 기록의 `cursor` 처럼) 추적하기 어려운 400 을 만든다.
    ///
    /// 뷰포트와 무관하다 — 지도 범위로 거르는 쪽은 `getReservationsSoon` 다.
    func getReservations(from: String, to: String) async throws -> ReservationListResponse

    /// **곧 출발하는 예약** — 지도 범위 안, 지금부터 **30분 내** 출발. `PartyController.listSoonReservations`.
    ///
    /// 파라미터 이름과 검사가 방 목록의 뷰포트 조회(`getPartiesWithin`)와 **같다**(`swLat`·`swLng`·
    /// `neLat`·`neLng`, 전부 필수). 다른 점은 경로(`/reservations/soon`) 하나다. 두 엔드포인트 모두
    /// 서버가 **엄격 비교**로 검사한다 — `swLat >= neLat || swLng >= neLng` 면 400 `INVALID_MAP_BOUNDS`
    /// 라(`PartyService.findActivePartiesWithin`·`findSoonReservationsWithin`) **남서·북동이 같은 점인
    /// 뷰포트도 거절**된다(지도를 완전히 줌인했을 때 생길 수 있다).
    ///
    /// 30분은 서버 상수(`SOON_WINDOW`)이고 앱이 바꿀 수 없다. 최대 100건.
    func getReservationsSoon(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> ReservationListResponse

    /// **예약 검색** — 출발지 1km 안에서, 고른 **하루**의 예약. `PartyController.searchReservations`.
    ///
    /// ### 파라미터 이름이 이 레포에서 가장 틀리기 쉽다 ★
    /// **출발지가 `depLat`/`depLng` 로 줄어 있는 유일한 자리다.** 예약 생성 본문은
    /// `departureLat`/`departureLng` + `destinationLat`/`destinationLng`, 실시간 후보 본문은
    /// `departureLat`/`departureLng` + `destLat`/`destLng`, 그리고 이 검색만 **네 개가 전부 줄어
    /// 있다**(`depLat`·`depLng`·`destLat`·`destLng`). 전체 표는 `OpenReservationRequestDto` 주석에 있다.
    /// 틀리면 필수 파라미터 누락이라 스프링 기본 400(본문 모양이 다른 400 — `getReservations` 참고)이다.
    ///
    /// ### `date` 는 **한국 달력 날짜**다 — instant 가 아니다 ★
    /// 서버가 `@DateTimeFormat(iso = DATE) LocalDate` 로 받으므로 와이어 모양은 `yyyy-MM-dd`
    /// (`date=2026-11-06`)이고, 해석은 **`Asia/Seoul` 기준**이다(서버가 `date.atStartOfDay(KST)` 로
    /// 하루를 자른다). 즉 호출부는 **KST 달력의 날짜**를 만들어 보내야 한다 — 기기 시간대가 KST 가
    /// 아닌 사용자(해외 체류·수동 설정)가 UTC 날짜를 보내면 **하루 밀린 결과**를 보게 되고, 그게
    /// 「오늘인데 왜 비어 있지」로 나타난다. ISO instant 를 그대로 넣으면 400 `INVALID_REQUEST` 다.
    ///
    /// 허용 범위는 **오늘 ~ 7일 뒤(양 끝 포함)**, 벗어나면 400 `INVALID_SEARCH_DATE`.
    /// 오늘을 고르면 **이미 출발한 방은 빠진다**(서버가 하루의 시작을 `max(지금, 자정)` 으로 잡는다).
    ///
    /// ### 도착지는 **둘 다 보내거나 둘 다 뺀다**
    /// 하나만 보내면 400 `INCOMPLETE_DESTINATION` 이다. `RestClient` 는 쿼리의 nil 을 **키째 생략**
    /// 하므로(Retrofit `@Query` 와 같다) 둘을 함께 nil 로 두면 올바르게 빠진다 — 그 「둘 다 또는 둘 다
    /// 아님」을 호출부에서 타입으로 보장하는 쪽은 저장소다
    /// (`ReservationDestination` 의 존재 이유).
    ///
    /// 보내면 응답 항목에 `destinationNearby` 가 붙고 **true 가 먼저** 정렬된다. 빼면 출발 시각 순이고
    /// 그 키 자체가 없다. 최대 100건.
    func searchReservations(
        depLat: Double,
        depLng: Double,
        date: String,
        destLat: Double?,
        destLng: Double?
    ) async throws -> ReservationListResponse

    // 삭제된 엔드포인트: matching/ready(POST·DELETE), matching/start(POST) —
    // 정원이 차면 서버가 스스로 마감하므로 앱이 트리거하지 않는다.
    // 배정된 기사 요약(`GET matching/rooms/{partyId}/driver`)도 지웠다 — 서버가 기사·배차를
    // 걷어내면서(Backend #297~#302) 응답을 만들 재료가 없어졌고, 부르던 화면도 함께 사라졌다.
}

enum MatchingApiRoute: String, CaseIterable, ApiRouteSet {
    case getParties, getPartiesWithin, getPartyDetail, openParty, joinParty, leaveParty, finishParty
    case confirmMeeting, arriveAtDeparture, departParty
    case previewRoute, getRealtimeCandidates
    case getMyNoShows, submitNoShowObjection
    case createReservation, getReservations, getReservationsSoon, searchReservations

    var route: ApiRoute {
        switch self {
        case .getParties: .GET("api/v1/matching/rooms")
        case .getPartiesWithin: .GET("api/v1/matching/rooms", query: ["swLat", "swLng", "neLat", "neLng"])
        case .getPartyDetail: .GET("api/v1/matching/rooms/{partyId}")
        case .openParty: .POST("api/v1/matching/rooms")
        case .joinParty: .POST("api/v1/matching/rooms/{partyId}/join")
        case .leaveParty: .DELETE("api/v1/matching/leave/{partyId}")
        case .finishParty: .POST("api/v1/matching/rooms/{partyId}/finish")
        case .confirmMeeting: .POST("api/v1/matching/rooms/{partyId}/confirm")
        case .arriveAtDeparture: .POST("api/v1/matching/rooms/{partyId}/arrive")
        case .departParty: .POST("api/v1/matching/rooms/{partyId}/depart")
        case .previewRoute: .POST("api/v1/matching/routes")
        case .getRealtimeCandidates: .POST("api/v1/matching/rooms/realtime")
        case .getMyNoShows: .GET("api/v1/matching/no-shows")
        case .submitNoShowObjection: .POST("api/v1/matching/rooms/{partyId}/no-show-objection")
        case .createReservation: .POST("api/v1/matching/reservations")
        case .getReservations: .GET("api/v1/matching/reservations", query: ["from", "to"])
        case .getReservationsSoon: .GET("api/v1/matching/reservations/soon", query: ["swLat", "swLng", "neLat", "neLng"])
        case .searchReservations:
            .GET("api/v1/matching/reservations/search", query: ["depLat", "depLng", "date", "destLat", "destLng"])
        }
    }
}

struct RestMatchingApi: MatchingApi {
    let rest: RestClient

    func getParties() async throws -> PartyListResponse {
        try await rest.call(MatchingApiRoute.getParties.route)
    }

    func getPartiesWithin(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> PartyListResponse {
        try await rest.call(
            MatchingApiRoute.getPartiesWithin.route,
            query: [
                "swLat": queryValue(swLat),
                "swLng": queryValue(swLng),
                "neLat": queryValue(neLat),
                "neLng": queryValue(neLng),
            ]
        )
    }

    func getPartyDetail(partyId: Int64) async throws -> PartyDetailResponse {
        try await rest.call(MatchingApiRoute.getPartyDetail.route, path: ["partyId": partyId])
    }

    func openParty(request: OpenPartyRequestDto) async throws -> OpenPartyResponse {
        try await rest.call(MatchingApiRoute.openParty.route, body: request)
    }

    func joinParty(partyId: Int64) async throws -> PartyStatusResponse {
        try await rest.call(MatchingApiRoute.joinParty.route, path: ["partyId": partyId])
    }

    func leaveParty(partyId: Int64) async throws {
        try await rest.callUnit(MatchingApiRoute.leaveParty.route, path: ["partyId": partyId])
    }

    func finishParty(partyId: Int64) async throws {
        try await rest.callUnit(MatchingApiRoute.finishParty.route, path: ["partyId": partyId])
    }

    func confirmMeeting(partyId: Int64, request: ConfirmMeetingRequestDto) async throws {
        try await rest.callUnit(MatchingApiRoute.confirmMeeting.route, path: ["partyId": partyId], body: request)
    }

    func arriveAtDeparture(partyId: Int64, request: ArriveRequestDto) async throws {
        try await rest.callUnit(MatchingApiRoute.arriveAtDeparture.route, path: ["partyId": partyId], body: request)
    }

    func departParty(partyId: Int64) async throws {
        try await rest.callUnit(MatchingApiRoute.departParty.route, path: ["partyId": partyId])
    }

    func previewRoute(request: RouteRequestDto) async throws -> RouteEstimateResponse {
        try await rest.call(MatchingApiRoute.previewRoute.route, body: request)
    }

    func getRealtimeCandidates(request: RealTimeMatchingRequestDto) async throws -> [MatchCandidateResponse] {
        try await rest.call(MatchingApiRoute.getRealtimeCandidates.route, body: request)
    }

    func getMyNoShows() async throws -> MyNoShowListResponse {
        try await rest.call(MatchingApiRoute.getMyNoShows.route)
    }

    // 201 + 빈 본문이라 `call<T>` 를 쓰면 빈 본문을 디코딩하다 터진다.
    func submitNoShowObjection(partyId: Int64, request: NoShowObjectionRequestDto) async throws {
        try await rest.callUnit(MatchingApiRoute.submitNoShowObjection.route, path: ["partyId": partyId], body: request)
    }

    func createReservation(request: OpenReservationRequestDto) async throws -> OpenPartyResponse {
        try await rest.call(MatchingApiRoute.createReservation.route, body: request)
    }

    func getReservations(from: String, to: String) async throws -> ReservationListResponse {
        try await rest.call(MatchingApiRoute.getReservations.route, query: ["from": from, "to": to])
    }

    func getReservationsSoon(swLat: Double, swLng: Double, neLat: Double, neLng: Double) async throws -> ReservationListResponse {
        try await rest.call(
            MatchingApiRoute.getReservationsSoon.route,
            query: [
                "swLat": queryValue(swLat),
                "swLng": queryValue(swLng),
                "neLat": queryValue(neLat),
                "neLng": queryValue(neLng),
            ]
        )
    }

    func searchReservations(
        depLat: Double,
        depLng: Double,
        date: String,
        destLat: Double?,
        destLng: Double?
    ) async throws -> ReservationListResponse {
        try await rest.call(
            MatchingApiRoute.searchReservations.route,
            query: [
                "depLat": queryValue(depLat),
                "depLng": queryValue(depLng),
                "date": date,
                // nil 은 키째 빠진다(Retrofit `@Query` 와 같다) — 둘이 함께 nil 이면 둘 다 빠진다.
                "destLat": destLat.map(queryValue),
                "destLng": destLng.map(queryValue),
            ]
        )
    }
}
