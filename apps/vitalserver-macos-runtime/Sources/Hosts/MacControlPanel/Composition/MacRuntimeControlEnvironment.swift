import Foundation
import Application
import InboundAdapters
import OutboundAdapters
import RuntimeControl
import Errors

@MainActor
final class MacRuntimeControlEnvironment: ObservableObject {
    let viewModel: RuntimeViewModel
    private let client: MacRuntimeControlClient
    private let readWorker: MacRuntimeControlReadWorker
    private let localAPISettings: RuntimeControlLocalAPISettingsCoordinator
    private let servesDevConsole: Bool
    private var apiServer: RuntimeControlLocalHTTPServer?
    private var restartAPIServerTask: Task<Void, Never>?
    private var retryAPIServerTask: Task<Void, Never>?
    private var relaunchHelperTask: Task<Void, Never>?
    private var terminateHelperTask: Task<Void, Never>?
    private(set) var apiServerError: Error?
    private var apiServerGeneration = 0
    private var apiServerRetryAttempt = 0

    init(
        viewModel: RuntimeViewModel,
        client: MacRuntimeControlClient,
        readWorker: MacRuntimeControlReadWorker,
        localAPISettings: RuntimeControlLocalAPISettingsCoordinator,
        servesDevConsole: Bool
    ) {
        self.viewModel = viewModel
        self.client = client
        self.readWorker = readWorker
        self.localAPISettings = localAPISettings
        self.servesDevConsole = servesDevConsole
        self.localAPISettings.onPortChanged = { [weak self] port in
            self?.scheduleAPIServerRestart(port: port)
        }
        startAPIServer(port: localAPISettings.runtimeControlPort)
    }

    deinit {
        restartAPIServerTask?.cancel()
        retryAPIServerTask?.cancel()
        relaunchHelperTask?.cancel()
        terminateHelperTask?.cancel()
        apiServer?.stop()
    }

    static func live() -> MacRuntimeControlEnvironment {
        let readWorker = MacRuntimeControlReadWorker(releaseInfo: .generated)
        let commandWorker = MacRuntimeControlCommandWorker(
            guestProductServiceController: RuntimeGuestProductServiceControlUseCase(),
            guestMaintenanceController: RuntimeGuestMaintenanceControlUseCase()
        )
        let client = MacRuntimeControlClient(releaseInfo: .generated, commandWorker: commandWorker)
        let localAPISettings = RuntimeControlLocalAPISettingsCoordinator(
            store: UserDefaultsRuntimeControlLocalAPISettingsStore.shared
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            snapshotReader: readWorker,
            localAPISettings: localAPISettings,
            healthNotifications: HealthNotificationCenter(),
            nativeShell: SystemRuntimeNativeShell(),
            helperMessageLog: FileRuntimeHelperMessageLog()
        )
        return MacRuntimeControlEnvironment(
            viewModel: viewModel,
            client: client,
            readWorker: readWorker,
            localAPISettings: localAPISettings,
            servesDevConsole: GeneratedRelease.testEnabled
        )
    }

    static func shouldStartRuntimeControlAPIServer() -> Bool {
        true
    }

    static func shouldServeRuntimeControlDevConsole(testEnabled: Bool) -> Bool {
        testEnabled
    }

    private func startAPIServer(port: Int) {
        retryAPIServerTask?.cancel()
        retryAPIServerTask = nil
        apiServerGeneration += 1
        let generation = apiServerGeneration
        let startedAt = Date()
        let nextServer = makeAPIServer(port: port, generation: generation, startedAt: startedAt)
        do {
            try nextServer.start()
            apiServer = nextServer
            apiServerError = nil
        } catch {
            apiServerError = error
            viewModel.updateRemoteConsoleStatus(RuntimeControlLocalAPIStatusRead.failed())
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
        let startedAt = Date()
        let nextServer = makeAPIServer(port: port, generation: generation, startedAt: startedAt)
        do {
            try nextServer.start()
            apiServer = nextServer
            previousServer?.stop()
            apiServerError = nil
        } catch {
            apiServerError = error
            viewModel.updateRemoteConsoleStatus(RuntimeControlLocalAPIStatusRead.failed())
        }
    }

    private func makeAPIServer(
        port: Int,
        generation: Int,
        startedAt: Date
    ) -> RuntimeControlLocalHTTPServer {
        MacRuntimeControlLocalAPI.make(
            client: client,
            readWorker: readWorker,
            port: port,
            localAPISettings: localAPISettings,
            servesDevConsole: servesDevConsole,
            startedAt: startedAt,
            stateHandler: { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleAPIServerState(
                        state,
                        port: port,
                        generation: generation,
                        startedAt: startedAt
                    )
                }
            },
            scheduleHelperRelaunch: { [weak self] in
                self?.scheduleHelperRelaunch()
            },
            scheduleHelperTermination: { [weak self] in
                self?.scheduleHelperTermination()
            }
        )
    }

    private func handleAPIServerState(
        _ state: RuntimeControlLocalHTTPServerState,
        port: Int,
        generation: Int,
        startedAt: Date
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
            viewModel.updateRemoteConsoleStatus(
                RuntimeControlLocalAPIStatusRead.reachable(startedAt: Self.timestamp(startedAt))
            )
        case .failed(let reason):
            apiServer = nil
            apiServerError = RuntimeControlLocalAPIServerLifecycleError.failedToListen(
                port: port,
                reason: reason
            )
            viewModel.updateRemoteConsoleStatus(RuntimeControlLocalAPIStatusRead.failed())
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

    private func scheduleHelperTermination() {
        terminateHelperTask?.cancel()
        terminateHelperTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.viewModel.terminateHelper()
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
