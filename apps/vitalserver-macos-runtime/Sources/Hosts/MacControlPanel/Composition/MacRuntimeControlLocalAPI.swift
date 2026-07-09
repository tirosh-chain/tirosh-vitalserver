import Foundation
import InboundAdapters
import OutboundAdapters
import RuntimeControl
import Errors

@MainActor
enum RuntimeControlLocalAPIConstants {
    static let defaultPort = UInt16(RuntimeSettingsInitialValues.runtimeControlPort)
    static let token = RuntimeControlLocalAPIConnectionDefaults.token
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
        client: MacRuntimeControlClient,
        readWorker: MacRuntimeControlReadWorker,
        operationLeaseClient: any RuntimeOperationLeaseMutationClient,
        guestAddressClient: any RuntimeGuestAddressResourceClient,
        vmLifecycleClient: any RuntimeVMLifecycleResourceClient,
        port: Int,
        localAPISettings: RuntimeControlLocalAPISettingsCoordinator,
        servesDevConsole: Bool = GeneratedRelease.testEnabled,
        startedAt: Date = Date(),
        stateHandler: (@Sendable (RuntimeControlLocalHTTPServerState) -> Void)? = nil,
        scheduleHelperRelaunch: @escaping @MainActor () -> Void = {},
        scheduleHelperTermination: @escaping @MainActor () -> Void = {}
    ) -> RuntimeControlLocalHTTPServer {
        let apiHandler = MacRuntimeControlAPIHandler(
                commandClient: client,
                hostClient: client,
                operationLeaseClient: operationLeaseClient,
                guestAddressClient: guestAddressClient,
                vmLifecycleClient: vmLifecycleClient,
            readWorker: readWorker,
            localAPISettings: localAPISettings,
            runtimeControlStartedAt: startedAt,
            scheduleHelperRelaunch: scheduleHelperRelaunch,
            scheduleHelperTermination: scheduleHelperTermination
        )
        let apiRouter = RuntimeControlAPIRouter(
            handler: apiHandler,
            authorization: RuntimeControlAPIAuthorization(token: RuntimeControlLocalAPIConstants.token)
        )
        return RuntimeControlLocalHTTPServer(
            configuration: RuntimeControlLocalHTTPServerConfiguration(
                port: RuntimeControlLocalAPIConstants.validatedPort(port),
                servesDevConsole: servesDevConsole,
                staticFileDirectory: Bundle.main.resourceURL?
                    .appendingPathComponent(RuntimeControlLocalAPIConstants.pwaResourceDirectory, isDirectory: true)
            ),
            router: apiRouter,
            stateHandler: stateHandler
        )
    }
}
