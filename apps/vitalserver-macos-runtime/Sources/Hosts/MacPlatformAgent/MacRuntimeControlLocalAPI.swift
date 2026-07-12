import Foundation
import Application
import InboundAdapters
import OutboundAdapters
import RuntimeControl
import Errors

@MainActor
public enum RuntimeControlLocalAPIConstants {
    public static let defaultPort = UInt16(RuntimeSettingsInitialValues.runtimeControlPort)
    public static let pwaResourceDirectory = "runtime-control-pwa"
    public static func devConsoleURL(port: Int) -> String {
        "http://127.0.0.1:\(port)/dev/runtime-control"
    }
    public static func pwaURL(port: Int) -> String {
        "http://127.0.0.1:\(port)/"
    }
    public static func validatedPort(_ port: Int) -> UInt16 {
        UInt16(exactly: port) ?? defaultPort
    }
}

@MainActor
public enum MacRuntimeControlLocalAPI {
    public static func make(
        client: MacRuntimeControlClient,
        readWorker: MacRuntimeControlReadWorker,
        guestMaintenanceClient: any RuntimeGuestMaintenanceOperationClient,
        operationLeaseClient: any RuntimeOperationLeaseMutationClient,
        guestAddressClient: any RuntimeGuestAddressResourceClient,
        vmLifecycleClient: any RuntimeVMLifecycleResourceClient,
        automationToken: String,
        port: Int,
        servesDevConsole: Bool = GeneratedRelease.testEnabled,
        staticFileDirectory: URL? = nil,
        startedAt: Date = Date(),
        stateHandler: (@Sendable (RuntimeControlLocalHTTPServerState) -> Void)? = nil,
        scheduleHelperRelaunch: @escaping @MainActor () -> Void = {},
        scheduleHelperTermination: @escaping @MainActor () -> Void = {}
    ) -> RuntimeControlLocalHTTPServer {
        let apiHandler = MacRuntimeControlAPIHandler(
                commandClient: client,
                hostClient: client,
                guestMaintenanceClient: guestMaintenanceClient,
                operationLeaseClient: operationLeaseClient,
                guestAddressClient: guestAddressClient,
                vmLifecycleClient: vmLifecycleClient,
            readWorker: readWorker,
            runtimeControlStartedAt: startedAt,
            scheduleHelperRelaunch: scheduleHelperRelaunch,
            scheduleHelperTermination: scheduleHelperTermination
        )
        let browserSession = RuntimeControlLoopbackBrowserSession()
        let apiRouter = RuntimeControlAPIRouter(
            handler: apiHandler,
            authorization: RuntimeControlAPIAuthorization(
                token: automationToken,
                browserSession: browserSession
            )
        )
        return RuntimeControlLocalHTTPServer(
            configuration: RuntimeControlLocalHTTPServerConfiguration(
                port: RuntimeControlLocalAPIConstants.validatedPort(port),
                servesDevConsole: servesDevConsole,
                staticFileDirectory: staticFileDirectory ?? Bundle.main.resourceURL?
                    .appendingPathComponent(RuntimeControlLocalAPIConstants.pwaResourceDirectory, isDirectory: true),
                bindsToLoopbackOnly: true,
                browserSession: browserSession
            ),
            router: apiRouter,
            stateHandler: stateHandler
        )
    }
}
