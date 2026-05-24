import Foundation
import MacHostRuntimeAdapter
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
        let client = MacHostRuntimeClient(releaseInfo: .generated)
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: HealthNotificationCenter(),
            nativeShell: SystemRuntimeNativeShell()
        )
        let apiServer = shouldStartDevelopmentAPIServer()
            ? makeDevelopmentAPIServer(client: client)
            : nil
        return MacRuntimeControlEnvironment(viewModel: viewModel, apiServer: apiServer)
    }

    static func shouldStartDevelopmentAPIServer(testEnabled: Bool = GeneratedRelease.testEnabled) -> Bool {
        testEnabled
    }

    private static func makeDevelopmentAPIServer(client: MacHostRuntimeClient) -> RuntimeControlLocalHTTPServer {
        let apiHandler = RuntimeControlClientAPIReadHandler(client: client, hostClient: client)
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
