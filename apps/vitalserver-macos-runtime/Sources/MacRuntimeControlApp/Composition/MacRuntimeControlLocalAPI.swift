import Foundation
import MacHostRuntimeAdapter
import RuntimeControl
import RuntimeControlAPI

enum RuntimeControlLocalAPIConstants {
    static let port: UInt16 = 18321
    static let token = "vitalserver-helper-dev"
    static let pwaResourceDirectory = "runtime-control-pwa"
    static var devConsoleURL: String {
        "http://127.0.0.1:\(port)/dev/runtime-control"
    }
    static var pwaURL: String {
        "http://127.0.0.1:\(port)/"
    }
}

@MainActor
enum MacRuntimeControlLocalAPI {
    static func make(
        client: MacHostRuntimeClient,
        readWorker: MacHostRuntimeReadWorker,
        testKitController: any RuntimeTestKitControlling,
        servesTestTools: Bool = GeneratedRelease.testEnabled
    ) -> RuntimeControlLocalHTTPServer {
        let apiHandler = MacRuntimeControlAPIHandler(
            commandClient: client,
            hostClient: client,
            readWorker: readWorker,
            servesTestTools: servesTestTools
        )
        let apiRouter = RuntimeControlAPIRouter(
            handler: apiHandler,
            authorization: RuntimeControlAPIAuthorization(token: RuntimeControlLocalAPIConstants.token)
        )
        let testKitRouter = servesTestTools
            ? RuntimeTestKitAPIRouter(
                controller: testKitController,
                authorization: RuntimeControlAPIAuthorization(token: RuntimeControlLocalAPIConstants.token)
            )
            : nil
        return RuntimeControlLocalHTTPServer(
            configuration: RuntimeControlLocalHTTPServerConfiguration(
                port: RuntimeControlLocalAPIConstants.port,
                servesDevConsole: servesTestTools,
                staticFileDirectory: Bundle.main.resourceURL?
                    .appendingPathComponent(RuntimeControlLocalAPIConstants.pwaResourceDirectory, isDirectory: true)
            ),
            router: apiRouter,
            testKitRouter: testKitRouter
        )
    }
}
