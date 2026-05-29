import Foundation
import MacHostRuntimeAdapter
import RuntimeControl
import RuntimeControlAPI

@MainActor
final class MacRuntimeControlEnvironment: ObservableObject {
    let viewModel: RuntimeViewModel
    private let client: MacHostRuntimeClient
    private let readWorker: MacHostRuntimeReadWorker
    private let testKitController: any RuntimeTestKitControlling
    private let localAPISettings: RuntimeControlLocalAPISettingsCoordinator
    private let servesTestTools: Bool
    private var apiServer: RuntimeControlLocalHTTPServer?
    private var restartAPIServerTask: Task<Void, Never>?
    private var retryAPIServerTask: Task<Void, Never>?
    private var relaunchHelperTask: Task<Void, Never>?
    private(set) var apiServerError: Error?
    private var apiServerGeneration = 0
    private var apiServerRetryAttempt = 0

    init(
        viewModel: RuntimeViewModel,
        client: MacHostRuntimeClient,
        readWorker: MacHostRuntimeReadWorker,
        testKitController: any RuntimeTestKitControlling,
        localAPISettings: RuntimeControlLocalAPISettingsCoordinator,
        servesTestTools: Bool
    ) {
        self.viewModel = viewModel
        self.client = client
        self.readWorker = readWorker
        self.testKitController = testKitController
        self.localAPISettings = localAPISettings
        self.servesTestTools = servesTestTools
        self.localAPISettings.onPortChanged = { [weak self] port in
            self?.scheduleAPIServerRestart(port: port)
        }
        startAPIServer(port: localAPISettings.runtimeControlPort)
    }

    deinit {
        restartAPIServerTask?.cancel()
        retryAPIServerTask?.cancel()
        relaunchHelperTask?.cancel()
        apiServer?.stop()
    }

    static func live() -> MacRuntimeControlEnvironment {
        let readWorker = MacHostRuntimeReadWorker(releaseInfo: .generated)
        let commandWorker = MacHostRuntimeCommandWorker()
        let client = MacHostRuntimeClient(releaseInfo: .generated, commandWorker: commandWorker)
        let localAPISettings = RuntimeControlLocalAPISettingsCoordinator(
            store: UserDefaultsRuntimeControlLocalAPISettingsStore.shared
        )
        let testKitController = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: GeneratedRelease.testEnabled && GeneratedRelease.testkitContainerIncluded
            ),
            statusProvider: {
                await readWorker.loadStatus(settings: RuntimeSettings())
            }
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKitController,
            readWorker: readWorker,
            initialSettings: localAPISettings.settingsWithLocalAPIPort(RuntimeSettings()),
            localAPISettings: localAPISettings,
            healthNotifications: HealthNotificationCenter(),
            nativeShell: SystemRuntimeNativeShell()
        )
        return MacRuntimeControlEnvironment(
            viewModel: viewModel,
            client: client,
            readWorker: readWorker,
            testKitController: testKitController,
            localAPISettings: localAPISettings,
            servesTestTools: GeneratedRelease.testEnabled
        )
    }

    static func shouldStartRuntimeControlAPIServer() -> Bool {
        true
    }

    static func shouldServeRuntimeControlTestTools(testEnabled: Bool) -> Bool {
        testEnabled
    }

    private func startAPIServer(port: Int) {
        retryAPIServerTask?.cancel()
        retryAPIServerTask = nil
        apiServerGeneration += 1
        let generation = apiServerGeneration
        let nextServer = makeAPIServer(port: port, generation: generation)
        do {
            try nextServer.start()
            apiServer = nextServer
            apiServerError = nil
        } catch {
            apiServerError = error
            scheduleAPIServerRetry(port: port)
        }
    }

    private func scheduleAPIServerRestart(port: Int) {
        restartAPIServerTask?.cancel()
        retryAPIServerTask?.cancel()
        retryAPIServerTask = nil
        apiServerRetryAttempt = 0
        restartAPIServerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self?.restartAPIServer(port: port)
        }
    }

    private func restartAPIServer(port: Int) {
        retryAPIServerTask?.cancel()
        retryAPIServerTask = nil
        let previousServer = apiServer
        apiServerGeneration += 1
        let generation = apiServerGeneration
        let nextServer = makeAPIServer(port: port, generation: generation)
        do {
            try nextServer.start()
            apiServer = nextServer
            previousServer?.stop()
            apiServerError = nil
        } catch {
            apiServerError = error
        }
    }

    private func makeAPIServer(port: Int, generation: Int) -> RuntimeControlLocalHTTPServer {
        MacRuntimeControlLocalAPI.make(
            client: client,
            readWorker: readWorker,
            testKitController: testKitController,
            port: port,
            localAPISettings: localAPISettings,
            servesTestTools: servesTestTools,
            stateHandler: { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleAPIServerState(state, port: port, generation: generation)
                }
            },
            scheduleHelperRelaunch: { [weak self] in
                self?.scheduleHelperRelaunch()
            }
        )
    }

    private func handleAPIServerState(
        _ state: RuntimeControlLocalHTTPServerState,
        port: Int,
        generation: Int
    ) {
        guard generation == apiServerGeneration else {
            return
        }

        switch state {
        case .ready:
            retryAPIServerTask?.cancel()
            retryAPIServerTask = nil
            apiServerRetryAttempt = 0
            apiServerError = nil
        case .failed(let reason):
            apiServer = nil
            apiServerError = RuntimeControlLocalAPIServerLifecycleError.failedToListen(
                port: port,
                reason: reason
            )
            scheduleAPIServerRetry(port: port)
        case .stopped:
            break
        }
    }

    private func scheduleAPIServerRetry(port: Int) {
        retryAPIServerTask?.cancel()
        apiServerRetryAttempt += 1
        let delayNanoseconds = UInt64(min(apiServerRetryAttempt, 5)) * 1_000_000_000
        retryAPIServerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            self?.startAPIServer(port: port)
        }
    }

    private func scheduleHelperRelaunch() {
        relaunchHelperTask?.cancel()
        relaunchHelperTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.viewModel.relaunchHelper()
        }
    }
}

private enum RuntimeControlLocalAPIServerLifecycleError: LocalizedError, Equatable {
    case failedToListen(port: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .failedToListen(let port, let reason):
            return "Remote Console API server failed to listen on port \(port): \(reason)"
        }
    }
}
