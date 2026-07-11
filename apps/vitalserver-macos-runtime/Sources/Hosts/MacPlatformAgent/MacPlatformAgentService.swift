import Application
import Darwin
import Foundation
import InboundAdapters
import OutboundAdapters
import RuntimeControl

@MainActor
public final class MacPlatformAgentService {
    private let server: RuntimeControlLocalHTTPServer

    private init(server: RuntimeControlLocalHTTPServer) {
        self.server = server
    }

    public static func live(
        installedPaths: InstalledRuntimePaths = .defaultInstalled,
        servesDevConsole: Bool = GeneratedRelease.testEnabled,
        port: Int? = nil,
        automationToken: String? = nil
    ) throws -> MacPlatformAgentService {
        let operationLeaseOwner = JSONFileRuntimeOperationLeaseRepository(
            url: installedPaths.runtimeOperationLease
        )
        let operationLeaseController = RuntimeControlOperationLeaseController(
            owner: operationLeaseOwner
        )
        let runtimeEndpointStore = FileRuntimeGuestAddressResourceStore(
            documentURL: installedPaths.runtimeEndpoint
        )
        let guestAddressController = RuntimeControlGuestAddressController(
            reader: runtimeEndpointStore,
            writer: runtimeEndpointStore
        )
        let vmLifecycleController = RuntimeControlVMLifecycleController(
            documentURL: installedPaths.vmLifecycle
        )
        let readWorker = MacRuntimeControlReadWorker(
            releaseInfo: .generated,
            operationLeaseReader: operationLeaseController,
            guestAddressProvider: runtimeEndpointStore,
            vmLifecycleResourceReader: vmLifecycleController
        )
        let commandWorker = MacRuntimeControlCommandWorker(
            guestProductServiceController: RuntimeGuestProductServiceControlUseCase(),
            guestMaintenanceController: RuntimeGuestMaintenanceControlUseCase(),
            guestAddressProvider: runtimeEndpointStore
        )
        let client = MacRuntimeControlClient(
            releaseInfo: .generated,
            operationLeaseReader: operationLeaseController,
            guestAddressProvider: runtimeEndpointStore,
            vmLifecycleResourceReader: vmLifecycleController,
            commandWorker: commandWorker
        )
        let selectedPort: Int
        if let port {
            selectedPort = port
        } else {
            selectedPort = try RuntimeControlLocalAPISettingsReader(
                documentURL: installedPaths.runtimeControlSettings
            ).loadPort()
        }
        let selectedAutomationToken: String
        if let automationToken {
            selectedAutomationToken = automationToken
        } else {
            selectedAutomationToken = try RuntimeControlAPIAutomationTokenStore(
                tokenURL: installedPaths.runtimeControlAPIToken
            ).loadOrCreate()
        }
        let pwaDirectory = installedPaths.managerApp
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent(RuntimeControlLocalAPIConstants.pwaResourceDirectory, isDirectory: true)
        let server = MacRuntimeControlLocalAPI.make(
            client: client,
            readWorker: readWorker,
            operationLeaseClient: operationLeaseController,
            guestAddressClient: guestAddressController,
            vmLifecycleClient: vmLifecycleController,
            automationToken: selectedAutomationToken,
            port: selectedPort,
            servesDevConsole: servesDevConsole,
            staticFileDirectory: pwaDirectory
        )
        return MacPlatformAgentService(server: server)
    }

    public func run() throws -> Never {
        try start()
        RunLoop.main.run()
        fatalError("Platform Agent run loop exited unexpectedly")
    }

    public var activePort: UInt16? {
        server.activePort
    }

    public func start() throws {
        try server.start()
    }

    public func stop() {
        server.stop()
    }
}
