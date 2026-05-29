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
    private(set) var apiServerError: Error?

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
        let nextServer = makeAPIServer(port: port)
        do {
            try nextServer.start()
            apiServer = nextServer
            apiServerError = nil
        } catch {
            apiServerError = error
        }
    }

    private func scheduleAPIServerRestart(port: Int) {
        restartAPIServerTask?.cancel()
        restartAPIServerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self?.restartAPIServer(port: port)
        }
    }

    private func restartAPIServer(port: Int) {
        let previousServer = apiServer
        let nextServer = makeAPIServer(port: port)
        do {
            try nextServer.start()
            apiServer = nextServer
            previousServer?.stop()
            apiServerError = nil
        } catch {
            apiServerError = error
        }
    }

    private func makeAPIServer(port: Int) -> RuntimeControlLocalHTTPServer {
        MacRuntimeControlLocalAPI.make(
            client: client,
            readWorker: readWorker,
            testKitController: testKitController,
            port: port,
            localAPISettings: localAPISettings,
            servesTestTools: servesTestTools
        )
    }
}
