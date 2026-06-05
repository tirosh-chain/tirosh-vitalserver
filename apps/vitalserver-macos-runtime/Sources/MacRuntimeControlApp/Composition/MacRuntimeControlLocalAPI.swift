import Foundation
import MacHostRuntimeAdapter
import RuntimeControl
import RuntimeControlAPI

@MainActor
enum RuntimeControlLocalAPIConstants {
    static let defaultPort: UInt16 = 18_321
    static let token = "vitalserver-helper-dev"
    static let pwaResourceDirectory = "runtime-control-pwa"
    static var port: UInt16 {
        validatedPort(UserDefaultsRuntimeControlLocalAPISettingsStore.shared.runtimeControlPort)
    }
    static var devConsoleURL: String {
        devConsoleURL(port: Int(port))
    }
    static var pwaURL: String {
        pwaURL(port: Int(port))
    }
    static func devConsoleURL(port: Int) -> String {
        "http://127.0.0.1:\(port)/dev/runtime-control"
    }
    static func pwaURL(port: Int) -> String {
        "http://127.0.0.1:\(port)/"
    }
    static func validatedPort(_ port: Int) -> UInt16 {
        UInt16(exactly: port) ?? defaultPort
    }
}

@MainActor
enum MacRuntimeControlLocalAPI {
    static func make(
        client: MacHostRuntimeClient,
        readWorker: MacHostRuntimeReadWorker,
        testKitController: any RuntimeTestKitControlling,
        port: Int,
        localAPISettings: RuntimeControlLocalAPISettingsCoordinator,
        servesTestTools: Bool = GeneratedRelease.testEnabled,
        startedAt: Date = Date(),
        stateHandler: (@Sendable (RuntimeControlLocalHTTPServerState) -> Void)? = nil,
        scheduleHelperRelaunch: @escaping @MainActor () -> Void = {},
        scheduleHelperTermination: @escaping @MainActor () -> Void = {}
    ) -> RuntimeControlLocalHTTPServer {
        let apiHandler = MacRuntimeControlAPIHandler(
            commandClient: client,
            hostClient: client,
            readWorker: readWorker,
            localAPISettings: localAPISettings,
            servesTestTools: servesTestTools,
            runtimeControlStartedAt: startedAt,
            scheduleHelperRelaunch: scheduleHelperRelaunch,
            scheduleHelperTermination: scheduleHelperTermination
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
                port: RuntimeControlLocalAPIConstants.validatedPort(port),
                servesDevConsole: servesTestTools,
                staticFileDirectory: Bundle.main.resourceURL?
                    .appendingPathComponent(RuntimeControlLocalAPIConstants.pwaResourceDirectory, isDirectory: true)
            ),
            router: apiRouter,
            testKitRouter: testKitRouter,
            stateHandler: stateHandler
        )
    }
}
