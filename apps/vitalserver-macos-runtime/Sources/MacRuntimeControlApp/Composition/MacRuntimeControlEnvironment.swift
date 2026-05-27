import Foundation
import MacHostRuntimeAdapter
import RuntimeControl
import RuntimeControlAPI

@MainActor
final class MacRuntimeControlEnvironment: ObservableObject {
    let viewModel: RuntimeViewModel
    private let apiServer: RuntimeControlLocalHTTPServer?
    private(set) var apiServerError: Error?

    init(viewModel: RuntimeViewModel, apiServer: RuntimeControlLocalHTTPServer?) {
        self.viewModel = viewModel
        self.apiServer = apiServer
        startAPIServer()
    }

    deinit {
        apiServer?.stop()
    }

    static func live() -> MacRuntimeControlEnvironment {
        let readWorker = MacHostRuntimeReadWorker(releaseInfo: .generated)
        let commandWorker = MacHostRuntimeCommandWorker()
        let client = MacHostRuntimeClient(releaseInfo: .generated, commandWorker: commandWorker)
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
            initialSettings: RuntimeSettings(),
            healthNotifications: HealthNotificationCenter(),
            nativeShell: SystemRuntimeNativeShell()
        )
        let apiServer = MacRuntimeControlDevelopmentAPI.makeIfEnabled(
            client: client,
            readWorker: readWorker,
            testKitController: testKitController
        )
        return MacRuntimeControlEnvironment(viewModel: viewModel, apiServer: apiServer)
    }

    private func startAPIServer() {
        guard let apiServer else {
            return
        }
        do {
            try apiServer.start()
        } catch {
            apiServerError = error
        }
    }
}
