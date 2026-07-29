import Application
import Darwin
import Domain
import Foundation
import InboundAdapters
import OutboundAdapters
import RuntimeControl

@MainActor
public final class MacPlatformAgentService {
    private let server: RuntimeControlLocalHTTPServer
    private let endpointSynchronizationLoop: RuntimeEndpointSynchronizationLoop
    private let hostNTPController: RuntimeHostNTPController

    private init(
        server: RuntimeControlLocalHTTPServer,
        endpointSynchronizationLoop: RuntimeEndpointSynchronizationLoop,
        hostNTPController: RuntimeHostNTPController
    ) {
        self.server = server
        self.endpointSynchronizationLoop = endpointSynchronizationLoop
        self.hostNTPController = hostNTPController
    }

    public static func live(
        installedPaths: InstalledRuntimePaths = .defaultInstalled,
        servesDevConsole: Bool = GeneratedRelease.testEnabled,
        port: Int? = nil,
        automationToken: String? = nil,
        endpointSynchronizationInterval: TimeInterval = 2,
        ntpServerPort: UInt16 = 123
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
        let hostNTPController = RuntimeHostNTPController(
            guestAddress: runtimeEndpointStore.readGuestAddress,
            interfaces: SystemRuntimeIPv4InterfaceProvider().read,
            writeContract: RuntimeTimeAuthorityContractWriter(
                destination: installedPaths.timeAuthority
            ).write,
            interval: endpointSynchronizationInterval,
            serverPort: ntpServerPort
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
        let installedProductReleaseReader = SQLiteInstalledProductReleaseReader(
            databaseURL: installedPaths.runtimeStateDatabase,
            validate: ValidateInstalledProductReleaseUseCase().validate
        )
        let stableUpdateJournalReader = SQLiteUpdateBootstrapJournalRepository(
            databaseURL: installedPaths.runtimeStateDatabase,
            validate: ValidateUpdateBootstrapJournalUseCase().validate,
            validateRelease: InstalledProductReleasePolicy.validate,
            validateSettlement: InstalledProductReleasePolicy.validate
        )
        let readWorker = MacRuntimeControlReadWorker(
            releaseInfo: .generated,
            operationLeaseReader: operationLeaseController,
            workflowOperationStateReader: workflowOperationStateRepository,
            stableUpdateJournalReader: stableUpdateJournalReader,
            guestAddressProvider: runtimeEndpointStore,
            vmLifecycleResourceReader: vmLifecycleController,
            installedProductReleaseReader: installedProductReleaseReader,
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
            installedProductReleaseReader: installedProductReleaseReader,
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
            endpointSynchronizationLoop: endpointSynchronizationLoop,
            hostNTPController: hostNTPController
        )
    }

    public static func runtimeSmoke(
        runtimeHome: URL,
        runtimeControlPort: Int,
        automationToken: String,
        ntpServerPort: UInt16
    ) throws -> MacPlatformAgentService {
        try live(
            installedPaths: InstalledRuntimePaths(runtimeHome: runtimeHome),
            servesDevConsole: false,
            port: runtimeControlPort,
            automationToken: automationToken,
            ntpServerPort: ntpServerPort
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
        hostNTPController.start()
    }

    public func stop() {
        hostNTPController.stop()
        endpointSynchronizationLoop.stop()
        server.stop()
    }
}
