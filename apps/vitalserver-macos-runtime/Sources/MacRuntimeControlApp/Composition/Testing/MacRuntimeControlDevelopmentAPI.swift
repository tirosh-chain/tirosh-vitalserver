import Foundation
import MacHostRuntimeAdapter
import RuntimeControl
import RuntimeControlAPI

enum RuntimeDevelopmentAPIConstants {
    static let port: UInt16 = 18321
    static let token = "vitalserver-helper-dev"
    static var devConsoleURL: String {
        "http://127.0.0.1:\(port)/dev/runtime-control"
    }
}

@MainActor
enum MacRuntimeControlDevelopmentAPI {
    static func makeIfEnabled(
        client: MacHostRuntimeClient,
        readWorker: MacHostRuntimeReadWorker,
        testKitController: any RuntimeTestKitControlling,
        testEnabled: Bool = GeneratedRelease.testEnabled
    ) -> RuntimeControlLocalHTTPServer? {
        guard testEnabled else {
            return nil
        }
        return makeServer(
            client: client,
            readWorker: readWorker,
            testKitController: testKitController
        )
    }

    private static func makeServer(
        client: MacHostRuntimeClient,
        readWorker: MacHostRuntimeReadWorker,
        testKitController: any RuntimeTestKitControlling
    ) -> RuntimeControlLocalHTTPServer {
        let apiHandler = MacRuntimeControlAPIHandler(
            commandClient: client,
            hostClient: client,
            readWorker: readWorker
        )
        let apiRouter = RuntimeControlAPIRouter(
            handler: apiHandler,
            authorization: RuntimeControlAPIAuthorization(token: RuntimeDevelopmentAPIConstants.token)
        )
        let testKitRouter = RuntimeTestKitAPIRouter(
            controller: testKitController,
            authorization: RuntimeControlAPIAuthorization(token: RuntimeDevelopmentAPIConstants.token)
        )
        return RuntimeControlLocalHTTPServer(
            configuration: RuntimeControlLocalHTTPServerConfiguration(
                port: RuntimeDevelopmentAPIConstants.port,
                servesDevConsole: true
            ),
            router: apiRouter,
            testKitRouter: testKitRouter
        )
    }
}
