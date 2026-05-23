import Foundation
import MacHostRuntimeAdapter
import RuntimeControlAPI

@MainActor
final class MacRuntimeControlEnvironment: ObservableObject {
    let viewModel: RuntimeViewModel
    private let apiServer: RuntimeControlLocalHTTPServer
    private(set) var apiServerError: Error?

    init(viewModel: RuntimeViewModel, apiServer: RuntimeControlLocalHTTPServer) {
        self.viewModel = viewModel
        self.apiServer = apiServer
        startAPIServer()
    }

    deinit {
        apiServer.stop()
    }

    static func live() -> MacRuntimeControlEnvironment {
        let client = MacHostRuntimeClient(releaseInfo: .generated)
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: HealthNotificationCenter(),
            nativeShell: SystemRuntimeNativeShell()
        )
        let apiHandler = RuntimeControlClientAPIReadHandler(client: client)
        let apiRouter = RuntimeControlAPIRouter(
            handler: apiHandler,
            authorization: RuntimeControlAPIAuthorization(token: AppConstants.RuntimeControlAPI.developmentToken)
        )
        let apiServer = RuntimeControlLocalHTTPServer(
            configuration: RuntimeControlLocalHTTPServerConfiguration(port: AppConstants.RuntimeControlAPI.port),
            router: apiRouter
        )
        return MacRuntimeControlEnvironment(viewModel: viewModel, apiServer: apiServer)
    }

    private func startAPIServer() {
        do {
            try apiServer.start()
        } catch {
            apiServerError = error
        }
    }
}
