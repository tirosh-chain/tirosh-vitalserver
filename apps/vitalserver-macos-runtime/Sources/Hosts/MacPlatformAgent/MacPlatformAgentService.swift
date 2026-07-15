import Application
import Darwin
import Foundation
import InboundAdapters
import OutboundAdapters
import RuntimeControl

@MainActor
public final class MacPlatformAgentService {
    private let server: RuntimeControlLocalHTTPServer
    private let endpointSynchronizationLoop: RuntimeEndpointSynchronizationLoop

    private init(
        server: RuntimeControlLocalHTTPServer,
        endpointSynchronizationLoop: RuntimeEndpointSynchronizationLoop
    ) {
        self.server = server
        self.endpointSynchronizationLoop = endpointSynchronizationLoop
    }

    public static func live(
        installedPaths: InstalledRuntimePaths = .defaultInstalled,
        servesDevConsole: Bool = GeneratedRelease.testEnabled,
        port: Int? = nil,
        automationToken: String? = nil,
        endpointSynchronizationInterval: TimeInterval = 2
    ) throws -> MacPlatformAgentService {
        let hostStateDatabase = SQLiteHostRuntimeStateDatabase(
            url: installedPaths.runtimeStateDatabase
        )
        switch hostStateDatabase.loadHostStateStoreReadiness() {
        case .loaded:
            break
        case .missing:
            throw RuntimeHostStateStoreStartupError.missing(
                path: installedPaths.runtimeStateDatabase.path
            )
        case .failed(let failure):
            throw RuntimeHostStateStoreStartupError.failed(
                path: installedPaths.runtimeStateDatabase.path,
                stage: failure.stage.rawValue,
                reason: failure.message
            )
        }
        let operationLeaseOwner = SQLiteRuntimeOperationLeaseRepository(
            databaseURL: installedPaths.runtimeStateDatabase
        )
        let operationLeaseController = RuntimeControlOperationLeaseController(
            owner: operationLeaseOwner
        )
        let workflowOperationStateRepository = SQLiteRuntimeWorkflowOperationStateRepository(
            databaseURL: installedPaths.runtimeStateDatabase
        )
        let runtimeEndpointStore = SQLiteRuntimeGuestAddressResourceStore(
            databaseURL: installedPaths.runtimeStateDatabase,
            lifecycleTransitionDecider: RuntimeVMLifecycleTransitionUseCase()
        )
        let endpointSynchronizationLoop = RuntimeEndpointSynchronizationLoop(
            bootstrapReader: FileRuntimeGuestAddressBootstrapReader(
                url: installedPaths.vmIPFile
            ),
            lifecycleReader: SQLiteRuntimeVMLifecycleStateRepository(
                databaseURL: installedPaths.runtimeStateDatabase,
                transitionDecider: RuntimeVMLifecycleTransitionUseCase()
            ),
            endpointRepository: SQLiteRuntimeEndpointStateRepository(
                databaseURL: installedPaths.runtimeStateDatabase
            ),
            useCase: SynchronizeRuntimeEndpointUseCase(),
            interval: endpointSynchronizationInterval
        )
        let guestAddressController = RuntimeControlGuestAddressController(
            reader: runtimeEndpointStore,
            writer: runtimeEndpointStore
        )
        let vmLifecycleController = RuntimeControlVMLifecycleController(
            databaseURL: installedPaths.runtimeStateDatabase
        )
        let hostSettingsRepository = SQLiteRuntimeHostSettingsRepository(
            databaseURL: installedPaths.runtimeStateDatabase,
            transitionDecider: RuntimeHostSettingsActivationUseCase()
        )
        let readWorker = MacRuntimeControlReadWorker(
            releaseInfo: .generated,
            operationLeaseReader: operationLeaseController,
            workflowOperationStateReader: workflowOperationStateRepository,
            guestAddressProvider: runtimeEndpointStore,
            vmLifecycleResourceReader: vmLifecycleController,
            hostSettingsReader: hostSettingsRepository
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
            hostSettingsReader: hostSettingsRepository,
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
            guestMaintenanceClient: commandWorker,
            operationLeaseClient: operationLeaseController,
            guestAddressClient: guestAddressController,
            vmLifecycleClient: vmLifecycleController,
            automationToken: selectedAutomationToken,
            port: selectedPort,
            servesDevConsole: servesDevConsole,
            staticFileDirectory: pwaDirectory
        )
        return MacPlatformAgentService(
            server: server,
            endpointSynchronizationLoop: endpointSynchronizationLoop
        )
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
        endpointSynchronizationLoop.start()
    }

    public func stop() {
        endpointSynchronizationLoop.stop()
        server.stop()
    }
}
