import Foundation
import Application
import Contracts
import Domain
import Errors

public struct InstallRuntimeExecutionContext: Equatable, Sendable {
    public let runtimeHomePath: String

    public init(runtimeHomePath: String) {
        self.runtimeHomePath = runtimeHomePath
    }
}

public struct InstallRuntimeStateReaders<Settings> {
    public var loadSettings: () throws -> Settings
    public var freshInstallPreflight: () -> RuntimeFreshInstallPreflightDocument
    public var provisionPayload: () -> RuntimeInstallProvisionPayloadDocument

    public init(
        loadSettings: @escaping () throws -> Settings,
        freshInstallPreflight: @escaping () -> RuntimeFreshInstallPreflightDocument,
        provisionPayload: @escaping () -> RuntimeInstallProvisionPayloadDocument
    ) {
        self.loadSettings = loadSettings
        self.freshInstallPreflight = freshInstallPreflight
        self.provisionPayload = provisionPayload
    }
}

public struct InstallRuntimeEffects<Settings> {
    public var log: (String) -> Void
    public var prepareInstallDirectories: (Settings) throws -> Void
    public var rotateRuntimeLogs: () throws -> Void
    public var configureDeployEnvironment: (Settings) throws -> Void
    public var prepareInstalledExecutables: () throws -> Void
    public var provisionVMDisk: (Settings) throws -> Void
    public var configureInstalledVMRuntime: (Settings) throws -> Void
    public var createCloudInitSeed: (Settings) throws -> Void
    public var writeInstalledRuntimeVersion: () throws -> Void
    public var configureInstalledPermissions: (Settings) throws -> Void
    public var startInstalledServices: (Settings) throws -> Void
    public var applyStartOnBootPolicy: (Settings) throws -> Void
    public var waitInstallRuntimeHealth: (Settings) throws -> Void
    public var cleanupInstallSettings: () throws -> Void
    public var describeError: (Error) -> String
    public var prepareHostStateStore: (Settings) throws -> Void

    public init(
        log: @escaping (String) -> Void,
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
        describeError: @escaping (Error) -> String,
        prepareHostStateStore: @escaping (Settings) throws -> Void = { _ in }
    ) {
        self.log = log
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
        self.describeError = describeError
        self.prepareHostStateStore = prepareHostStateStore
    }
}

public struct InstallRuntimeStateWriter {
    public var writeState: (RuntimeInstallState, RuntimeInstallMode, RuntimeWorkflowStep?, String?, [String]) throws -> Void
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var writeProgress: (RuntimeStepExecutionEvent) throws -> Void

    public init(
        writeState: @escaping (RuntimeInstallState, RuntimeInstallMode, RuntimeWorkflowStep?, String?, [String]) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void
    ) {
        self.writeState = writeState
        self.writeStatus = writeStatus
        self.writeProgress = writeProgress
    }
}

public struct InstallRuntimeDiagnostics {
    public var log: (String) -> Void

    public init(log: @escaping (String) -> Void) {
        self.log = log
    }
}

public struct InstallRuntimeOperations<Settings> {
    public var readers: InstallRuntimeStateReaders<Settings>
    public var effects: InstallRuntimeEffects<Settings>
    public var writer: InstallRuntimeStateWriter
    public var diagnostics: InstallRuntimeDiagnostics

    public init(
        readers: InstallRuntimeStateReaders<Settings>,
        effects: InstallRuntimeEffects<Settings>,
        writer: InstallRuntimeStateWriter,
        diagnostics: InstallRuntimeDiagnostics
    ) {
        self.readers = readers
        self.effects = effects
        self.writer = writer
        self.diagnostics = diagnostics
    }
}

public struct RuntimeInstallWorkflow {
    private let useCase: InstallRuntimeUseCase

    public init(useCase: InstallRuntimeUseCase = InstallRuntimeUseCase()) {
        self.useCase = useCase
    }

    public func run<Settings>(
        _ installPlan: InstallRuntimePlan,
        context executionContext: InstallRuntimeExecutionContext,
        operations: InstallRuntimeOperations<Settings>
    ) throws {
        let context = RuntimeInstallTransitionContext(mode: installPlan.mode, plan: installPlan.operationPlan)
        let startDecision = try transitionAndPersist(
            from: .notStarted,
            event: .start,
            context: context,
            expectedCommands: [.loadSettings],
            operations: operations
        )
        let startPlan = installUseCase().startPlan(runtimeHomePath: executionContext.runtimeHomePath)
        log(startPlan.logMessage, operations: operations)
        try operations.writer.writeStatus(installPlan.activeStatus, .install, startPlan.statusMessage)

        let settings: Settings
        do {
            settings = try operations.readers.loadSettings()
        } catch {
            let reason = operations.effects.describeError(error)
            _ = try transitionAndPersist(
                from: startDecision.state,
                event: .settingsLoadFailed(reason: reason),
                context: context,
                expectedCommands: [],
                operations: operations
            )
            writeCriticalStatusBestEffort(
                installUseCase().settingsLoadFailedStatusMessage(reason: reason),
                operations: operations
            )
            throw error
        }

        let settingsDecision = try transitionAndPersist(
            from: startDecision.state,
            event: .settingsLoaded,
            context: context,
            operations: operations
        )

        var decision = try verifySetup(
            from: settingsDecision,
            context: context,
            operations: operations
        )

        guard decision.blockers.isEmpty else {
            writeCriticalStatusBestEffort(
                installUseCase().setupBlockedStatusMessage(blockers: decision.blockers),
                operations: operations
            )
            throw InstallRuntimeUseCaseError.operationFailed(
                installUseCase().setupBlockedFailureMessage(blockers: decision.blockers)
            )
        }

        while true {
            guard let nextCommand = decision.commands.first else {
                throw InstallRuntimeUseCaseError.operationFailed(
                    installUseCase().missingCommandMessage(state: decision.state)
                )
            }
            switch nextCommand {
            case .executeStep(let step):
                try installUseCase().requireCommands([.executeStep(step)], in: decision)
                decision = try execute(
                    step,
                    status: installPlan.activeStatus,
                    settings: settings,
                    from: decision.state,
                    context: context,
                    operations: operations
                )
            case .complete:
                try installUseCase().requireCommands([.complete], in: decision)
                try operations.writer.writeStatus(installPlan.completionStatus, .install, installPlan.completionMessage)
                log(
                    installUseCase().completionLogMessage(
                        plan: installPlan,
                        runtimeHomePath: executionContext.runtimeHomePath
                    ),
                    operations: operations
                )
                return
            case .loadSettings, .readFreshInstallPreflight, .readProvisionPayload:
                throw InstallRuntimeUseCaseError.operationFailed(
                    installUseCase().postSetupCommandFailureMessage(nextCommand)
                )
            }
        }
    }

    private func verifySetup<Settings>(
        from decision: RuntimeInstallTransitionDecision,
        context: RuntimeInstallTransitionContext,
        operations: InstallRuntimeOperations<Settings>
    ) throws -> RuntimeInstallTransitionDecision {
        let setupCommand = try installUseCase().setupReadCommand(from: decision)
        switch setupCommand {
        case .readFreshInstallPreflight:
            let preflight = operations.readers.freshInstallPreflight()
            return try transitionAndPersist(
                from: decision.state,
                event: .freshInstallPreflightObserved(preflight),
                context: context,
                operations: operations
            )
        case .readProvisionPayload:
            let payload = operations.readers.provisionPayload()
            return try transitionAndPersist(
                from: decision.state,
                event: .provisionPayloadObserved(payload),
                context: context,
                operations: operations
            )
        case .loadSettings, .executeStep, .complete:
            throw InstallRuntimeUseCaseError.operationFailed(
                installUseCase().setupReadCommandFailureMessage(setupCommand)
            )
        }
    }

    private func execute<Settings>(
        _ step: RuntimeWorkflowStep,
        status: RuntimeStatusLevel,
        settings: Settings,
        from state: RuntimeInstallWorkflowState,
        context: RuntimeInstallTransitionContext,
        operations: InstallRuntimeOperations<Settings>
    ) throws -> RuntimeInstallTransitionDecision {
        let startedDecision = try transitionAndPersist(
            from: state,
            event: .stepStarted(step),
            context: context,
            expectedCommands: [],
            operations: operations
        )
        writeProgressBestEffort(
            installUseCase().stepProgressEvent(
                step: step,
                status: status,
                stepStatus: .started,
                phase: .running,
                message: installUseCase().stepStartedMessage(step)
            ),
            operations: operations
        )
        do {
            try executeStepPlan(
                installUseCase().stepExecutionPlan(step),
                settings: settings,
                effects: operations.effects
            )
            writeProgressBestEffort(
                installUseCase().stepProgressEvent(
                    step: step,
                    status: status,
                    stepStatus: .completed,
                    phase: .running,
                    message: installUseCase().stepCompletedMessage(step)
                ),
                operations: operations
            )
            let decision = try transitionAndPersist(
                from: startedDecision.state,
                event: .stepSucceeded(step),
                context: context,
                operations: operations
            )
            log(installUseCase().stepCompletedLogMessage(step), operations: operations)
            return decision
        } catch {
            let reason = operations.effects.describeError(error)
            writeProgressBestEffort(
                installUseCase().stepProgressEvent(
                    step: step,
                    status: status,
                    stepStatus: .failed,
                    phase: .failed,
                    message: installUseCase().stepFailedMessage(step, reason: reason)
                ),
                operations: operations
            )
            _ = try transitionAndPersist(
                from: startedDecision.state,
                event: .stepFailed(step, reason: reason),
                context: context,
                expectedCommands: [],
                operations: operations
            )
            writeCriticalStatusBestEffort(
                installUseCase().installFailedStatusMessage(reason: reason),
                operations: operations
            )
            throw error
        }
    }

    private func executeStepPlan<Settings>(
        _ plan: InstallRuntimeStepExecutionPlan,
        settings: Settings,
        effects: InstallRuntimeEffects<Settings>
    ) throws {
        switch plan {
        case .log(let message):
            effects.log(message)
        case .prepareInstallDirectories:
            try effects.prepareInstallDirectories(settings)
        case .prepareHostStateStore:
            try effects.prepareHostStateStore(settings)
        case .rotateRuntimeLogs:
            try effects.rotateRuntimeLogs()
        case .configureDeployEnvironment:
            try effects.configureDeployEnvironment(settings)
        case .prepareInstalledExecutables:
            try effects.prepareInstalledExecutables()
        case .provisionVMDisk:
            try effects.provisionVMDisk(settings)
        case .configureInstalledVMRuntime:
            try effects.configureInstalledVMRuntime(settings)
        case .createCloudInitSeed:
            try effects.createCloudInitSeed(settings)
        case .writeInstalledRuntimeVersion:
            try effects.writeInstalledRuntimeVersion()
        case .configureInstalledPermissions:
            try effects.configureInstalledPermissions(settings)
        case .startInstalledServices:
            try effects.startInstalledServices(settings)
        case .applyStartOnBootPolicy:
            try effects.applyStartOnBootPolicy(settings)
        case .waitInstallRuntimeHealth:
            try effects.waitInstallRuntimeHealth(settings)
        case .cleanupInstallSettings:
            try effects.cleanupInstallSettings()
        case .unsupported(let message):
            throw RuntimeInstallStepExecutionError(message)
        }
    }

    private func transitionAndPersist<Settings>(
        from state: RuntimeInstallWorkflowState,
        event: RuntimeInstallWorkflowEvent,
        context: RuntimeInstallTransitionContext,
        expectedCommands: [RuntimeInstallWorkflowCommand]? = nil,
        operations: InstallRuntimeOperations<Settings>
    ) throws -> RuntimeInstallTransitionDecision {
        let decision = try installUseCase().transition(
            from: state,
            event: event,
            context: context,
            expectedCommands: expectedCommands
        )
        try persist(decision, mode: context.mode, operations: operations)
        return decision
    }

    private func persist<Settings>(
        _ decision: RuntimeInstallTransitionDecision,
        mode: RuntimeInstallMode,
        operations: InstallRuntimeOperations<Settings>
    ) throws {
        guard let persistedState = decision.persistedState else {
            return
        }
        try operations.writer.writeState(
            persistedState,
            mode,
            decision.currentStep,
            decision.message,
            decision.blockers
        )
    }

    private func writeProgressBestEffort<Settings>(
        _ event: RuntimeStepExecutionEvent,
        operations: InstallRuntimeOperations<Settings>
    ) {
        do {
            try operations.writer.writeProgress(event)
        } catch {
            log(installUseCase().progressWriteFailedLogMessage(
                event: event,
                reason: operations.effects.describeError(error)
            ), operations: operations)
        }
    }

    private func writeCriticalStatusBestEffort<Settings>(
        _ message: String,
        operations: InstallRuntimeOperations<Settings>
    ) {
        do {
            try operations.writer.writeStatus(.critical, .install, message)
        } catch {
            log(
                installUseCase().criticalStatusWriteFailedLogMessage(reason: operations.effects.describeError(error)),
                operations: operations
            )
        }
    }

    private func log<Settings>(_ message: String, operations: InstallRuntimeOperations<Settings>) {
        operations.diagnostics.log(message)
    }

    private func installUseCase() -> InstallRuntimeUseCase {
        useCase
    }
}
