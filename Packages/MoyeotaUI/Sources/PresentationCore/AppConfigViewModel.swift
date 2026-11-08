import MoyeotaDomain
import Observation
import os

private let logger = Logger(subsystem: "com.moyeota.presentation", category: "AppConfig")

/// 시작 시 조회가 실패했을 때의 재시도 간격. 서버 재기동·네트워크 복구 정도를 기다린다.
private let RETRY_DELAYS_MS: [Int64] = [2_000, 5_000, 15_000]

/// 서버 운영 설정(`GET /api/v1/config`). 내비게이션 스택 바깥(앱 루트)에 두어 화면들이 한 값을 공유한다
/// (`UserProfileViewModel` 과 같은 이유).
///
/// 지금 이 설정이 정하는 것은 **강제 업데이트 게이트 하나뿐**이다
/// (`AppConfig.minVersionCode`·`AppConfig.recommendedVersionCode` → `updateRequirement`).
///
/// - 시작 시 한 번 읽고, 실패하면 `RETRY_DELAYS_MS` 간격으로 몇 번 더 시도한다. 그래도 못 받으면
///   `AppConfig.Default` 로 간다 — 두 기준이 **nil 이라 아무도 막히지 않는다.**
/// - 앱이 다시 앞으로 올 때 아직 못 받았으면 다시 시도한다(`loadIfUnresolved`).
///
/// **디버그 강제값(`setDebugOverride`)은 지웠다.** 그 장치는 `taxiEnabled` 하나를 뒤집어 동승/택시
/// 화면을 골라 보기 위한 것이었는데, 기사·배차를 걷어내면서 서버가 그 값을 보내지 않게 되고
/// 도메인에서도 필드가 사라졌다 — 덮어쓸 값이 없다. 되살릴 이유가 생긴다면(새 운영 플래그) 그때
/// **그 플래그에 맞춰** 다시 세우는 쪽이 맞다. 「서버가 준 값」(`serverConfig`)과 「화면이 따를 값」
/// (`config`)을 갈라 두었던 것도 같은 이유로 하나로 합쳤다 — 이제 둘이 같은 값이다.
@MainActor
@Observable
public final class AppConfigViewModel {
    /// 화면이 따를 설정 — 서버가 준 그대로다(덮어쓰는 장치가 없다).
    public private(set) var config: AppConfig = .Default

    /// 서버 응답을 한 번이라도 받았는가. false 면 지금 값은 기본값이다.
    public private(set) var resolved = false

    @ObservationIgnored private let repository: any AppConfigRepository
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let scope = ViewModelScope()
    /// 진행 중인 조회. 끝나면 nil 이다(`Job.isActive` 의 자리).
    @ObservationIgnored private(set) var loading: Task<Void, Never>?

    public init(
        repository: any AppConfigRepository,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.repository = repository
        self.sleep = sleep
        load()
    }

    /// 서버 값을 다시 읽는다. 이미 읽는 중이면 겹쳐 띄우지 않는다.
    public func load() {
        if loading != nil { return }
        let repository = self.repository
        let sleep = self.sleep
        loading = scope.launch { [weak self] in
            defer { self?.loading = nil }
            var attempt = 0
            while true {
                let failure: any Error
                do {
                    let config = try await repository.getConfig()
                    guard !Task.isCancelled, let self else { return }
                    self.config = config
                    self.resolved = true
                    let min = config.minVersionCode.map { String($0) } ?? "null"
                    let recommended = config.recommendedVersionCode.map { String($0) } ?? "null"
                    logger.info("서버 설정 수신 — 최소=\(min, privacy: .public) 권장=\(recommended, privacy: .public)")
                    return
                } catch {
                    // 살아 있는 태스크의 `URLError(.cancelled)` 는 원본 `runCatching` 처럼 실패로 쳐서 다시 시도한다.
                    if Task.isCancelled { return }
                    failure = error
                }
                guard attempt < RETRY_DELAYS_MS.count else {
                    logger.warning(
                        "설정 조회 실패(재시도 소진) — 기본값으로 진행(게이트 없음): \(failure.localizedDescription, privacy: .public)"
                    )
                    return
                }
                let wait = RETRY_DELAYS_MS[attempt]
                attempt += 1
                logger.warning(
                    "설정 조회 실패 — \(wait / 1000)초 뒤 재시도: \(failure.localizedDescription, privacy: .public)"
                )
                do {
                    try await sleep(.milliseconds(wait))
                } catch {
                    return
                }
            }
        }
    }

    /// 복귀(onResume)마다 부른다. 아직 서버 값을 못 받았을 때만 다시 시도한다.
    public func loadIfUnresolved() {
        if !resolved { load() }
    }
}
