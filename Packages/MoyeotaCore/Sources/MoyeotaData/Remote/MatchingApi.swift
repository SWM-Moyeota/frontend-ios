/// 경로 기준: `matching/party/PartyController.java`
/// (@RequestMapping("/api/v1") + 메서드별 "/matching/...").
/// 지금은 **이 인터페이스 전부가 그 한 컨트롤러**다 — 예전에 따로 있던 `matching/noshow/` 는
/// 서버에서 사라졌다.
///
/// (경로 메모 수정 2026-11-06: 백엔드에는 `interfaces/` 디렉터리가 **없다** — 이 주석이 오래
/// `matching/interfaces/` 아래의 `PartyController.java` 를 가리키고 있었다. 실제 위치는 도메인별로
/// `matching/party/` 또는 `…/presentation/` 이다. 파일을 찾으러 간 사람이
/// 「컨트롤러가 사라졌다」로 결론 내리지 않도록 고쳐 둔다.)
///
/// ⚠️ **택시비 정산은 여기 없다** — `faresplit/FareSplitController.java` 가 경로를
/// `/api/v1/matching/rooms/{partyId}/fare-split…` 로 **같은 가지에 걸지만** 다른 모듈이고 앱에서도
/// 다른 인터페이스(`FareSplitApi`)다. 프리픽스가 같다고 여기 끼워 넣지 말 것.
///
/// 주의: backend/http/matching.http 의 **앞 세 요청**은 v1 이 없는 옛 경로 + 옛 필드명(hostId)이라
/// 신뢰하지 않는다. 예약 요청(4번 이후)은 컨트롤러와 일치한다.
///
/// **여기 전부가 토큰 필수다.** 목록·상세 조회까지 포함해 예외가 없다
/// (Security 가 `/api/v1/auth/` 하위를 뺀 전 경로에 `anyRequest().authenticated()` 를 건다).
/// 미로그인 상태에서 부르면 화면에 데이터 대신 401 에러가 뜨므로,
/// 이 API 를 쓰는 화면은 로그인 뒤에만 열려야 한다.
public protocol MatchingApi: Sendable {
    /// 지도 화면 범위(남서·북동 모서리) 안의 방 목록.
    ///
    /// **좌표 없이 부르는 전체 목록은 더 이상 없다**(서버 `2732cc75` 가 지웠다 — 「앱이 부르지 않는
    /// GET /matching/rooms(좌표 없는 전체 목록)」). 네 쿼리가 전부 필수이고, 하나라도 빠지면
    /// 400 이다. 예전에는 같은 경로의 무파라미터 핸들러로 조용히 떨어졌으니 **빈 목록처럼 보이지 않고
    /// 에러로 보인다** — 바뀐 쪽이 낫다.
    ///
    /// 서버가 **정원이 찬 방을 뺀다**(`b16551b7`: 「근처 방·지도·예약 목록은 정원이 찬 방을 뺀다」).
    /// 즉 여기 실려 온 방은 **지금 들어갈 수 있는 방**이다 — 목록에서 「모집 마감」을 그릴 일이 없다.
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
    /// 응답의 `status` 는 합류 **직후**의 방 상태다. ⚠️ **정원을 채워도 `ACTIVE` 다**(`b16551b7` —
    /// 서버 `COMPLETED` 는 이제 「방장이 약속을 확정한 실시간 방」만 뜻한다). 내가 마지막 자리를 채웠는지는
    /// `currentMembers` 와 그 방의 정원을 직접 비교해야 안다(`PartyStatus` 주석).
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

    // 「합승 종료」(`POST /matching/rooms/{partyId}/finish`)는 **서버에서 지워졌다**
    // (`b16551b7`: 「구버전 종료 경로(/finish)…를 지운다」). 방을 끝내는 길은 `departParty` 하나다.
    // 되살리면 404 이고, 404 는 이 앱에서 「없는 방」과 같은 문구로 보여 원인을 가린다.

    /// 약속 시간·만남 장소 확정. 204. `PartyController.confirm`.
    ///
    /// **방을 끝내는 정식 경로의 첫 단계다** — 확정 → `arriveAtDeparture` → `departParty`.
    ///
    /// 조건: 방장만 · **실시간 방만**(예약 방은 409 `NOT_REALTIME_PARTY`) · 멤버 **2명 이상**
    /// (`NOT_ENOUGH_MEMBERS`) · 열린 방 · 한 번만(`ALREADY_CONFIRMED`).
    /// **정원이 찼는지는 보지 않는다** — 3인 방에 2명이어도 받는다.
    ///
    /// ### 본문이 한 필드에서 네 필드로 늘었다 (`2732cc75`)
    /// 「약속 확정은 만남 장소(위도·경도·이름)를 늘 받는다. 바꾸지 않으면 앱이 지금 출발지를 그대로 보낸다」
    /// — `departureAt`·`departureLat`·`departureLng`·`departure` 가 **전부 필수**다
    /// (`@NotNull`/`@NotBlank`). 옛 한 필드 본문을 보내면 **400 `INVALID_REQUEST`** 이고, 그건
    /// `MatchingErrorCode` 의 어느 사유도 아니라서 화면에는 일반 문구로만 보인다 —
    /// 「확정이 안 된다」는 신고가 들어와도 원인을 짚을 단서가 없다. `ConfirmMeetingRequestDto` 참고.
    ///
    /// ### 확정이 방의 출발지를 **옮긴다**
    /// 서버 `Party.confirm` 이 `departureLocation = plan.departure()` 로 덮어쓴다. 도착 판정(반경)이
    /// 실제 만나는 곳을 기준으로 돌게 하려는 것이다. 그래서 장소를 바꾸지 않을 때도 지금 출발지를
    /// 그대로 실어야 한다 — 빈 값을 보내면 방의 출발지가 빈 값으로 바뀐다.
    ///
    /// ### 약속 시간은 **지금부터 5분 뒤 ~ 1시간** 사이여야 한다
    /// 벗어나면 400 `INVALID_MEETING_TIME`. 사용자가 다이얼로그를 열어 둔 채 시간을 끌면 하한에
    /// 걸릴 수 있다 — 프리셋을 **누른 순간의 `now`** 로 계산해야 하는 이유다.
    ///
    /// 성공하면 ACTIVE→COMPLETED 이고 **참여만 막힌다 — 나가기는 된다**
    /// (서버 `Party.leave` 는 확정 방을 거절하지 않는다. 막는 것은 「도착을 누른 사람」뿐:
    /// 409 `ARRIVED_MEMBER_CANNOT_LEAVE`). 그 사실은 SSE `confirmed` 로 모든 멤버에게 전해지고,
    /// 그 프레임에 **바뀐 출발지 셋이 함께 실려 온다**(`PartyConfirmedPayload`).
    func confirmMeeting(partyId: Int64, request: ConfirmMeetingRequestDto) async throws

    /// 출발지 도착. 204. `PartyController.arrive`.
    ///
    /// 본문은 **지금 내 위치**(`latitude`/`longitude`)다 — 서버가 방 출발지와의 거리를 PostGIS
    /// `ST_DWithin` 으로 재서 반경 안인지 본다(`ArriveRequestDto` 에 왜 방 좌표를 보내면 안 되는지 적었다).
    ///
    /// ### 반경이 방 종류로 갈린다 (`2732cc75`)
    /// | 방 | 반경 | 왜 |
    /// |---|---|---|
    /// | 실시간 | **100m** | 만남 장소를 확정 때 채팅으로 정한 곳으로 옮기므로 좁아도 된다 |
    /// | 예약 | **400m** | 출발지가 장소 검색 결과의 **중심점**(큰 역이면 역 한가운데)이고 확정으로 옮길 수 없다 — 실제로 만나는 출구까지 들어오게 넓게 잡는다 |
    ///
    /// 벗어나면 400 `TOO_FAR_FROM_DEPARTURE`. 숫자를 화면 문구에 박을 때 **100 하나로 말하면
    /// 예약 방 사용자에게 거짓**이 된다(서버 `Party.arrivalRadiusMeters`).
    ///
    /// 열리는 시점은 **약속 시간 10분 전부터**다(서버 `Party.arrive` 의
    /// `now < departureAt − ARRIVAL_OPENS_BEFORE(10분)` 검사는 409 `ARRIVAL_NOT_OPEN` — 백엔드 PR #307 전의
    /// 「정각부터 · `MEETING_NOT_STARTED`」가 아니다). **멱등이다**: 이미 도착한 사람이 다시
    /// 불러도 204 이고 시각·version·SSE 가 모두 그대로다.
    func arriveAtDeparture(partyId: Int64, request: ArriveRequestDto) async throws

    /// 출발 — 방을 끝낸다. 204, **요청 본문 없다**. `PartyController.depart`.
    ///
    /// **방을 끝내는 유일한 길이다** — `/finish` 가 서버에서 사라졌다.
    ///
    /// 조건을 전부 만족해야 한다(서버 `Party.depart`):
    /// 1. **방장만** — `b16551b7` 이 바꿨다(「출발은 도착한 방장만 누른다」). 예전에는 도착한 멤버면
    ///    누구나였다. 방장이 아니면 403 `NOT_PARTY_HOST`
    /// 2. 확정된 방 — 아니면 409 `PARTY_NOT_CONFIRMED`
    /// 3. 멤버 2명 이상 — 아니면 409 `NOT_ENOUGH_MEMBERS`
    /// 4. `now >= departureAt` — 아니면 409 `MEETING_NOT_STARTED`
    /// 5. **방장 자신이 도착해 있을 것** — 아니면 409 `NOT_ARRIVED`
    ///
    /// ⚠️ **도착하지 않은 멤버는 그 방의 탑승자에서 빠진다.** 노쇼 제재는 없어졌지만(`b16551b7` 이
    /// 기록·제재·이의 신청을 전부 지웠다) 대가가 사라진 건 아니다: 탑승 횟수·탑승 기록·**택시비 정산
    /// 대상**이 모두 「도착을 누른 멤버」 기준이라, 아직 오는 중인 사람을 두고 누르면 그 사람은 같이
    /// 탔는데도 정산에서 빠진다. 본문이 없어 "실수로 호출"을 막아 주는 것도 없으므로 화면 쪽에서
    /// **도착하지 않은 인원을 세어 보여 주고** 확인을 받고 부를 것.
    ///
    /// 성공 뒤 서버가 `closed`(status `FINISHED`)를 보내고 **그 방의 SSE 연결을 끊는다**.
    /// FINISHED 가 된 방은 방장이 택시비 정산을 시작할 수 있는 유일한 상태다.
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

    // **노쇼 기록·이의 신청(`GET /matching/no-shows`, `POST /matching/rooms/{partyId}/no-show-objection`)은
    // 서버에서 지워졌다** (`b16551b7`: 「노쇼 기록·제재·이의 신청…을 지운다」, DB 마이그레이션 V37 이
    // 테이블까지 DROP). 되살리면 404 다. `MyProfileResponse` 의 `noShowCount`·`restrictedUntil` 키는
    // 출시 앱 호환용으로 남아 있지만 **값이 늘 0·null 로 고정**이라 읽어도 아무것도 알 수 없다.

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
    /// ⚠️ 예약 방은 **합류한 순간부터 확정 상태다**(서버 `Party.isConfirmed()` 가
    /// `isReservation() || departureAt != null` 이다) — 그래서 `confirmMeeting` 은 409
    /// `NOT_REALTIME_PARTY` 로 막힌다. 하지만 **나가기는 된다**: 확정을 이유로 거절하던
    /// `CANNOT_LEAVE_CONFIRMED_PARTY` 는 서버에서 사라졌다(`b16551b7`: 「확정 방에서도 나갈 수 있고」).
    /// 지금 나가기를 막는 유일한 사유는 **도착을 누른 뒤**다(409 `ARRIVED_MEMBER_CANNOT_LEAVE`).
    /// ⚠️ 출발 시각이 지난 예약에 합류하면 409 `PARTY_CLOSED` 다.
    ///
    /// 실패는 `PartyController.reserve` 의 `@ApiResponses` 기준으로
    /// 400 `SAME_DEPARTURE_DESTINATION`·`INVALID_CAPACITY`·`OUT_OF_SERVICE_AREA`·
    /// `INVALID_DEPARTURE_TIME`·`INVALID_REQUEST` /
    /// 409 `ALREADY_JOINED_OTHER_PARTY`·`PARTY_TIME_CONFLICT` 다
    /// (403 `NO_SHOW_RESTRICTED` 는 노쇼 제재와 함께 사라졌다) —
    /// `PartyOpenException` 으로 좁힌다 — 방 생성과 **같은 예외**이고,
    /// 실시간 표에 갈래가 없는 둘은 그 예외의 `isPartyTimeConflict`·`isInvalidDepartureTime` 이다
    /// (`PARTY_TIME_CONFLICT` 는 실시간 생성에도 오고, 예약 전용은 `INVALID_DEPARTURE_TIME` 하나다).
    func createReservation(request: OpenReservationRequestDto) async throws -> OpenPartyResponse

    // **기간으로 보는 예약 목록(`GET /matching/reservations?from&to`)은 서버에서 지워졌다**
    // (`2732cc75`: 「앱이 부르지 않는 … GET /matching/reservations?from&to 와 INVALID_TIME_RANGE 삭제」).
    // 화면이 쓰는 두 경로는 `getReservationsSoon`(지도 범위 + 30분 내)과
    // `searchReservations`(출발지 1km + 하루)다. `INVALID_TIME_RANGE` 에러 코드도 함께 사라졌다.

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
    /// 틀리면 필수 파라미터 누락이라 **본문 모양이 다른 400** 이다 — 서버 `GlobalExceptionHandler` 에
    /// 누락 파라미터 핸들러가 없어 `{code, message}` 가 아닌 스프링 기본 에러 JSON 이 오고,
    /// `readApiError` 가 code 를 못 찾아 화면은 일반 문구로 떨어진다.
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
    case getPartiesWithin, getPartyDetail, openParty, joinParty, leaveParty
    case confirmMeeting, arriveAtDeparture, departParty
    case previewRoute, getRealtimeCandidates
    case createReservation, getReservationsSoon, searchReservations

    var route: ApiRoute {
        switch self {
        case .getPartiesWithin: .GET("api/v1/matching/rooms", query: ["swLat", "swLng", "neLat", "neLng"])
        case .getPartyDetail: .GET("api/v1/matching/rooms/{partyId}")
        case .openParty: .POST("api/v1/matching/rooms")
        case .joinParty: .POST("api/v1/matching/rooms/{partyId}/join")
        case .leaveParty: .DELETE("api/v1/matching/leave/{partyId}")
        case .confirmMeeting: .POST("api/v1/matching/rooms/{partyId}/confirm")
        case .arriveAtDeparture: .POST("api/v1/matching/rooms/{partyId}/arrive")
        case .departParty: .POST("api/v1/matching/rooms/{partyId}/depart")
        case .previewRoute: .POST("api/v1/matching/routes")
        case .getRealtimeCandidates: .POST("api/v1/matching/rooms/realtime")
        case .createReservation: .POST("api/v1/matching/reservations")
        case .getReservationsSoon: .GET("api/v1/matching/reservations/soon", query: ["swLat", "swLng", "neLat", "neLng"])
        case .searchReservations:
            .GET("api/v1/matching/reservations/search", query: ["depLat", "depLng", "date", "destLat", "destLng"])
        }
    }
}

struct RestMatchingApi: MatchingApi {
    let rest: RestClient

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

    func createReservation(request: OpenReservationRequestDto) async throws -> OpenPartyResponse {
        try await rest.call(MatchingApiRoute.createReservation.route, body: request)
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
