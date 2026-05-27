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
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            readWorker: readWorker,
            initialSettings: RuntimeSettings(),
            healthNotifications: HealthNotificationCenter(),
            nativeShell: SystemRuntimeNativeShell()
        )
        let apiServer = shouldStartDevelopmentAPIServer()
            ? makeDevelopmentAPIServer(client: client, readWorker: readWorker)
            : nil
        return MacRuntimeControlEnvironment(viewModel: viewModel, apiServer: apiServer)
    }

    static func shouldStartDevelopmentAPIServer(testEnabled: Bool = GeneratedRelease.testEnabled) -> Bool {
        testEnabled
    }

    private static func makeDevelopmentAPIServer(
        client: MacHostRuntimeClient,
        readWorker: MacHostRuntimeReadWorker
    ) -> RuntimeControlLocalHTTPServer {
        let apiHandler = MacRuntimeControlAPIHandler(
            commandClient: client,
            hostClient: client,
            readWorker: readWorker
        )
        let apiRouter = RuntimeControlAPIRouter(
            handler: apiHandler,
            authorization: RuntimeControlAPIAuthorization(token: AppConstants.RuntimeControlAPI.developmentToken)
        )
        return RuntimeControlLocalHTTPServer(
            configuration: RuntimeControlLocalHTTPServerConfiguration(
                port: AppConstants.RuntimeControlAPI.port,
                servesDevConsole: true
            ),
            router: apiRouter
        )
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
