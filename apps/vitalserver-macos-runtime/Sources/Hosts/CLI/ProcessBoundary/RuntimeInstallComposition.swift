import Application
import Bootstrap
import Foundation
import OutboundAdapters
import Contracts
import Domain
import Workflow
import Errors

public struct RuntimeInstallCompositionContext {
    let paths: LauncherPaths
    let installedPaths: InstalledRuntimePaths

    public init(
        paths: LauncherPaths,
        installedPaths: InstalledRuntimePaths
    ) {
        self.paths = paths
        self.installedPaths = installedPaths
    }
}

public struct RuntimeInstallCompositionOperations<Settings> {
    let fileStore: RuntimeFileStore
    let now: () -> Date
    let loadInstallSettings: () throws -> Settings
    let freshInstallPreflight: () -> RuntimeFreshInstallPreflightDocument
    let installProvisionPayload: () -> RuntimeInstallProvisionPayloadDocument
    let writeRuntimeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let writeRuntimeProgress: (RuntimeStepExecutionEvent) throws -> Void
    let prepareInstallDirectories: (Settings) throws -> Void
    let rotateRuntimeLogs: () throws -> Void
    let configureDeployEnvironment: (Settings) throws -> Void
    let prepareInstalledExecutables: () throws -> Void
    let provisionVMDisk: (Settings) throws -> Void
    let configureInstalledVMRuntime: (Settings) throws -> Void
    let createCloudInitSeed: (Settings) throws -> Void
    let writeInstalledRuntimeVersion: () throws -> Void
    let configureInstalledPermissions: (Settings) throws -> Void
    let startInstalledServices: (Settings) throws -> Void
    let applyStartOnBootPolicy: (Settings) throws -> Void
    let waitInstallRuntimeHealth: (Settings) throws -> Void
    let cleanupInstallSettings: () throws -> Void
    let log: (String) -> Void
    let initializeHostStateStore: () throws -> Void
    let migrateLegacyHostSettings: () throws -> Void
    let prepareHostSettings: (Settings) throws -> Void
    let workflowOperationStateRepository: any RuntimeWorkflowOperationStateRepository
    let operationID: () -> String

    public init(
        fileStore: RuntimeFileStore,
        now: @escaping () -> Date,
        loadInstallSettings: @escaping () throws -> Settings,
        freshInstallPreflight: @escaping () -> RuntimeFreshInstallPreflightDocument,
        installProvisionPayload: @escaping () -> RuntimeInstallProvisionPayloadDocument,
        writeRuntimeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeRuntimeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void,
        prepareInstallDirectories: @escaping (Settings) throws -> Void,
        rotateRuntimeLogs: @escaping () throws -> Void,
        configureDeployEnvironment: @escaping (Settings) throws -> Void,
        prepareInstalledExecutables: @escaping () throws -> Void,
        provisionVMDisk: @escaping (Settings) throws -> Void,
        configureInstalledVMRuntime: @escaping (Settings) throws -> Void,
        createCloudInitSeed: @escaping (Settings) throws -> Void,
        writeInstalledRuntimeVersion: @escaping () throws -> Void,
        configureInstalledPermissions: @escaping (Settings) throws -> Void,
        startInstalledServices: @escaping (Settings) throws -> Void,
        applyStartOnBootPolicy: @escaping (Settings) throws -> Void,
        waitInstallRuntimeHealth: @escaping (Settings) throws -> Void,
        cleanupInstallSettings: @escaping () throws -> Void,
        log: @escaping (String) -> Void,
        initializeHostStateStore: @escaping () throws -> Void,
        migrateLegacyHostSettings: @escaping () throws -> Void = {},
        prepareHostSettings: @escaping (Settings) throws -> Void,
        workflowOperationStateRepository: any RuntimeWorkflowOperationStateRepository,
        operationID: @escaping () -> String
    ) {
        self.fileStore = fileStore
        self.now = now
        self.loadInstallSettings = loadInstallSettings
        self.freshInstallPreflight = freshInstallPreflight
        self.installProvisionPayload = installProvisionPayload
        self.writeRuntimeStatus = writeRuntimeStatus
        self.writeRuntimeProgress = writeRuntimeProgress
        self.prepareInstallDirectories = prepareInstallDirectories
        self.rotateRuntimeLogs = rotateRuntimeLogs
        self.configureDeployEnvironment = configureDeployEnvironment
        self.prepareInstalledExecutables = prepareInstalledExecutables
        self.provisionVMDisk = provisionVMDisk
        self.configureInstalledVMRuntime = configureInstalledVMRuntime
        self.createCloudInitSeed = createCloudInitSeed
        self.writeInstalledRuntimeVersion = writeInstalledRuntimeVersion
        self.configureInstalledPermissions = configureInstalledPermissions
        self.startInstalledServices = startInstalledServices
        self.applyStartOnBootPolicy = applyStartOnBootPolicy
        self.waitInstallRuntimeHealth = waitInstallRuntimeHealth
        self.cleanupInstallSettings = cleanupInstallSettings
        self.log = log
        self.initializeHostStateStore = initializeHostStateStore
        self.migrateLegacyHostSettings = migrateLegacyHostSettings
        self.prepareHostSettings = prepareHostSettings
        self.workflowOperationStateRepository = workflowOperationStateRepository
        self.operationID = operationID
    }
}

public struct RuntimeInstallComposition<Settings> {
    let context: RuntimeInstallCompositionContext
    let operations: RuntimeInstallCompositionOperations<Settings>

    public init(
        context: RuntimeInstallCompositionContext,
        operations: RuntimeInstallCompositionOperations<Settings>
    ) {
        self.context = context
        self.operations = operations
    }

    public func install() throws {
        let plan = installRuntimeUseCase().plan(for: InstallRuntimeRequest(
            mode: .full
        ))
        let preflight = operations.freshInstallPreflight()
        try operations.initializeHostStateStore()
        let operationID = operations.operationID()
        try RuntimeInstallWorkflow().run(
            plan,
            context: InstallRuntimeExecutionContext(runtimeHomePath: context.paths.home.path),
            operations: installRuntimeOperations(
                operationID: operationID,
                freshInstallPreflight: { preflight },
                provisionPayload: operations.installProvisionPayload
            )
        )
    }

    public func installProvision(mode: RuntimePackageInstallMode) throws {
        let plan = installRuntimeUseCase().plan(for: InstallRuntimeRequest(
            mode: .provision
        ))
        let provisionPayload = operations.installProvisionPayload()
        try operations.initializeHostStateStore()
        if mode == .reinstall {
            try operations.migrateLegacyHostSettings()
        }
        let operationID = operations.operationID()
        try RuntimeInstallWorkflow().run(
            plan,
            context: InstallRuntimeExecutionContext(runtimeHomePath: context.paths.home.path),
            operations: installRuntimeOperations(
                operationID: operationID,
                freshInstallPreflight: operations.freshInstallPreflight,
                provisionPayload: { provisionPayload }
            )
        )
    }

    private func installRuntimeUseCase() -> InstallRuntimeUseCase {
        InstallRuntimeUseCase()
    }

    private func installRuntimeOperations(
        operationID: String,
        freshInstallPreflight: @escaping () -> RuntimeFreshInstallPreflightDocument,
        provisionPayload: @escaping () -> RuntimeInstallProvisionPayloadDocument
    ) -> InstallRuntimeOperations<Settings> {
        let statePersistence = PersistRuntimeWorkflowOperationStateUseCase()
        return InstallRuntimeOperations(
            readers: InstallRuntimeStateReaders(
                loadSettings: operations.loadInstallSettings,
                freshInstallPreflight: freshInstallPreflight,
                provisionPayload: provisionPayload
            ),
            effects: InstallRuntimeEffects(
                log: operations.log,
                prepareInstallDirectories: operations.prepareInstallDirectories,
                rotateRuntimeLogs: operations.rotateRuntimeLogs,
                configureDeployEnvironment: operations.configureDeployEnvironment,
                prepareInstalledExecutables: operations.prepareInstalledExecutables,
                provisionVMDisk: operations.provisionVMDisk,
                configureInstalledVMRuntime: operations.configureInstalledVMRuntime,
                createCloudInitSeed: operations.createCloudInitSeed,
                writeInstalledRuntimeVersion: operations.writeInstalledRuntimeVersion,
                configureInstalledPermissions: operations.configureInstalledPermissions,
                startInstalledServices: operations.startInstalledServices,
                applyStartOnBootPolicy: operations.applyStartOnBootPolicy,
                waitInstallRuntimeHealth: operations.waitInstallRuntimeHealth,
                cleanupInstallSettings: operations.cleanupInstallSettings,
                describeError: RuntimeErrorDescription.describe,
                prepareHostStateStore: operations.prepareHostSettings
            ),
            writer: InstallRuntimeStateWriter(
                writeState: { state, mode, currentStep, message, blockers in
                    let occurredAt = ISO8601DateFormatter().string(from: operations.now())
                    let event = try RuntimeInstallWorkflowOperationStateProjectionPolicy.event(
                        operationID: operationID,
                        state: state,
                        currentStep: currentStep,
                        message: message,
                        blockers: blockers
                    )
                    try statePersistence.transition(
                        repository: operations.workflowOperationStateRepository,
                        operationID: operationID,
                        event: event,
                        occurredAt: occurredAt
                    )
                    do {
                        try RuntimeInstallWorkflowStateArtifactStore(
                        url: context.installedPaths.runtimeInstallState,
                        fileStore: operations.fileStore,
                        now: operations.now
                        ).write(
                            state: state,
                            mode: mode,
                            currentStep: currentStep,
                            message: message,
                            blockers: blockers
                        )
                    } catch {
                        operations.log(
                            "runtime install diagnostic snapshot write failed operationId=\(operationID) path=\(context.installedPaths.runtimeInstallState.path) reason=\(RuntimeErrorDescription.describe(error))"
                        )
                    }
                },
                writeStatus: operations.writeRuntimeStatus,
                writeProgress: operations.writeRuntimeProgress
            ),
            diagnostics: InstallRuntimeDiagnostics(log: operations.log)
        )
    }
}
