import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeUninstallCommand: Equatable {
    public let clean: Bool

    public init(clean: Bool) {
        self.clean = clean
    }
}

public struct RuntimeConfiguredExternalVitalFilesDirectoryRead: Equatable {
    public let externalDirectory: URL?
    public let failure: String?

    public init(externalDirectory: URL?, failure: String?) {
        self.externalDirectory = externalDirectory
        self.failure = failure
    }
}

public struct RuntimeUninstallPaths {
    public let productRoot: URL
    public let managerApp: URL
    public let defaultVitalFilesDirectory: URL
    public let externalVitalFilesDirectory: URL?
    public let configuredVitalFilesDirectoryReadFailure: String?
    public let launchDaemonPlists: [URL]
    public let runtimeTools: [URL]

    public init(
        productRoot: URL,
        managerApp: URL,
        defaultVitalFilesDirectory: URL,
        externalVitalFilesDirectory: URL?,
        configuredVitalFilesDirectoryReadFailure: String?,
        launchDaemonPlists: [URL],
        runtimeTools: [URL]
    ) {
        self.productRoot = productRoot
        self.managerApp = managerApp
        self.defaultVitalFilesDirectory = defaultVitalFilesDirectory
        self.externalVitalFilesDirectory = externalVitalFilesDirectory
        self.configuredVitalFilesDirectoryReadFailure = configuredVitalFilesDirectoryReadFailure
        self.launchDaemonPlists = launchDaemonPlists
        self.runtimeTools = runtimeTools
    }
}

public struct RuntimeUninstallStateReaders {
    public var serviceStates: () -> [RuntimeManagedService: RuntimeServiceState]
    public var vmProcessState: () -> RuntimeVMProcessState
    public var packageReceiptStates: () -> [RuntimePackageReceiptState]
    public var cleanupArtifactStates: (Bool) -> [RuntimeInstallArtifactState]

    public init(
        serviceStates: @escaping () -> [RuntimeManagedService: RuntimeServiceState],
        vmProcessState: @escaping () -> RuntimeVMProcessState,
        packageReceiptStates: @escaping () -> [RuntimePackageReceiptState],
        cleanupArtifactStates: @escaping (Bool) -> [RuntimeInstallArtifactState]
    ) {
        self.serviceStates = serviceStates
        self.vmProcessState = vmProcessState
        self.packageReceiptStates = packageReceiptStates
        self.cleanupArtifactStates = cleanupArtifactStates
    }
}

public enum RuntimeUninstallFileRemovalExecutionResult {
    case completed
    case failed(error: Error, blockers: [String])
}

public enum RuntimeUninstallReceiptForgetExecutionResult: Equatable {
    case completed
    case failed(identifier: String, reason: String)
}

public struct RuntimeUninstallEffects {
    public var createRedisBackup: () throws -> Void
    public var stopRuntimeServices: () throws -> Void
    public var describeError: (Error) -> String
    public var executeFileRemoval: (RuntimeUninstallPaths, Bool) -> RuntimeUninstallFileRemovalExecutionResult
    public var executeReceiptForgetting: (
        [String],
        [String: RuntimePackageReceiptState]
    ) -> RuntimeUninstallReceiptForgetExecutionResult

    public init(
        createRedisBackup: @escaping () throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        describeError: @escaping (Error) -> String,
        executeFileRemoval: @escaping (RuntimeUninstallPaths, Bool) -> RuntimeUninstallFileRemovalExecutionResult,
        executeReceiptForgetting: @escaping (
            [String],
            [String: RuntimePackageReceiptState]
        ) -> RuntimeUninstallReceiptForgetExecutionResult
    ) {
        self.createRedisBackup = createRedisBackup
        self.stopRuntimeServices = stopRuntimeServices
        self.describeError = describeError
        self.executeFileRemoval = executeFileRemoval
        self.executeReceiptForgetting = executeReceiptForgetting
    }
}

public struct RuntimeUninstallStateWriter {
    public var writeState: (RuntimeUninstallState, Bool, String?, [String]) throws -> Void

    public init(
        writeState: @escaping (RuntimeUninstallState, Bool, String?, [String]) throws -> Void
    ) {
        self.writeState = writeState
    }
}

public struct RuntimeUninstallDiagnostics {
    public var log: (String) -> Void

    public init(log: @escaping (String) -> Void) {
        self.log = log
    }
}

public struct RuntimeUninstallWorkflow {
    public var paths: RuntimeUninstallPaths
    public var readers: RuntimeUninstallStateReaders
    public var effects: RuntimeUninstallEffects
    public var writer: RuntimeUninstallStateWriter
    public var diagnostics: RuntimeUninstallDiagnostics
    public var packageReceiptIdentifiers: [String]
    private var useCase: UninstallRuntimeUseCase {
        UninstallRuntimeUseCase()
    }

    public init(
        paths: RuntimeUninstallPaths,
        readers: RuntimeUninstallStateReaders,
        effects: RuntimeUninstallEffects,
        writer: RuntimeUninstallStateWriter,
        diagnostics: RuntimeUninstallDiagnostics,
        packageReceiptIdentifiers: [String]
    ) {
        self.paths = paths
        self.readers = readers
        self.effects = effects
        self.writer = writer
        self.diagnostics = diagnostics
        self.packageReceiptIdentifiers = packageReceiptIdentifiers
    }

    public func run(_ command: RuntimeUninstallCommand) throws {
        let startedState = try start(command)
        let readyForStopState = try backupIfNeeded(command, from: startedState)
        let stoppedDecision = try stopAndVerifyRuntime(from: readyForStopState, clean: command.clean)
        let cleanupDecision = try removeFilesAndVerifyCleanup(approvedBy: stoppedDecision, command: command)
        let receiptDecision = try forgetReceiptsAndVerifyAbsence(approvedBy: cleanupDecision, clean: command.clean)
        try complete(approvedBy: receiptDecision, clean: command.clean)
    }

    private func start(_ command: RuntimeUninstallCommand) throws -> RuntimeUninstallWorkflowState {
        let plan = useCase.startPlan(
            clean: command.clean,
            configuredDirectoryReadFailure: paths.configuredVitalFilesDirectoryReadFailure
        )
        log(plan.startedLogMessage)
        let startDecision = try transitionAndPersist(
            from: .notStarted,
            event: .start(clean: command.clean),
            clean: command.clean,
            expectedCommands: []
        )
        if let configuredDirectoryReadFailureLogMessage = plan.configuredDirectoryReadFailureLogMessage {
            log(configuredDirectoryReadFailureLogMessage)
        }
        return startDecision.state
    }

    private func backupIfNeeded(
        _ command: RuntimeUninstallCommand,
        from state: RuntimeUninstallWorkflowState
    ) throws -> RuntimeUninstallWorkflowState {
        guard useCase.shouldCreateRedisBackup(clean: command.clean) else {
            return state
        }

        log(useCase.stepLogMessage(step: .createRedisBackup, status: .started))
        let backupRequestDecision = try transitionAndPersist(
            from: state,
            event: .redisBackupRequested,
            clean: command.clean,
            expectedCommands: [.createRedisBackup]
        )
        do {
            try effects.createRedisBackup()
            log(useCase.stepLogMessage(step: .createRedisBackup, status: .completed))
            let backupCompletedDecision = try transitionAndPersist(
                from: backupRequestDecision.state,
                event: .redisBackupSucceeded,
                clean: command.clean,
                expectedCommands: []
            )
            return backupCompletedDecision.state
        } catch {
            let reason = effects.describeError(error)
            log(useCase.redisBackupAbortLogMessage(reason: reason))
            let decision = try transitionAndPersist(
                from: backupRequestDecision.state,
                event: .redisBackupFailed(reason: reason),
                clean: command.clean,
                expectedCommands: []
            )
            try requireCommands([], in: decision)
            throw error
        }
    }

    private func stopAndVerifyRuntime(
        from state: RuntimeUninstallWorkflowState,
        clean: Bool
    ) throws -> RuntimeUninstallTransitionDecision {
        log(useCase.stepLogMessage(step: .stopLaunchdServices, status: .started))
        let stopRequestDecision = try transitionAndPersist(
            from: state,
            event: .stopServicesRequested,
            clean: clean,
            expectedCommands: [.stopRuntimeServices]
        )
        do {
            try effects.stopRuntimeServices()
        } catch {
            _ = try transitionAndPersist(
                from: stopRequestDecision.state,
                event: .stopServicesFailed(
                    input: runtimeStopReadinessInput(),
                    commandFailureReason: effects.describeError(error)
                ),
                clean: clean,
                expectedCommands: []
            )
            throw error
        }
        log(useCase.stepLogMessage(step: .stopLaunchdServices, status: .completed))
        return try verifyRuntimeStopped(from: stopRequestDecision.state, clean: clean)
    }

    private func removeFilesAndVerifyCleanup(
        approvedBy stoppedDecision: RuntimeUninstallTransitionDecision,
        command: RuntimeUninstallCommand
    ) throws -> RuntimeUninstallTransitionDecision {
        try requireCommands([.removeFiles], in: stoppedDecision)
        let fileRemovalDecision = try transitionAndPersist(
            from: stoppedDecision.state,
            event: .filesRemovalStarted,
            clean: command.clean,
            expectedCommands: []
        )
        switch effects.executeFileRemoval(paths, command.clean) {
        case .completed:
            let cleanupDecision = try verifyCleanupArtifacts(from: fileRemovalDecision.state, clean: command.clean)
            return cleanupDecision
        case .failed(let error, let blockers):
            try writer.writeState(
                .filesRemovalBlocked,
                command.clean,
                useCase.fileRemovalBlockedMessage(),
                blockers
            )
            throw error
        }
    }

    private func forgetReceiptsAndVerifyAbsence(
        approvedBy cleanupDecision: RuntimeUninstallTransitionDecision,
        clean: Bool
    ) throws -> RuntimeUninstallTransitionDecision {
        try requireCommands([.forgetPackageReceipts], in: cleanupDecision)
        log(useCase.stepLogMessage(step: .forgetPackageReceipt, status: .started))
        let receiptsStartDecision = try transitionAndPersist(
            from: cleanupDecision.state,
            event: .receiptsForgetStarted,
            clean: clean,
            expectedCommands: []
        )

        let observedReceiptStates = useCase.packageReceiptStateMap(readers.packageReceiptStates())
        switch effects.executeReceiptForgetting(packageReceiptIdentifiers, observedReceiptStates) {
        case .completed:
            break
        case .failed(let identifier, let reason):
            _ = try transitionAndPersist(
                from: receiptsStartDecision.state,
                event: .receiptForgetFailed(identifier: identifier, reason: reason),
                clean: clean,
                expectedCommands: []
            )
            throw RuntimeUninstallWorkflowError.operationFailed(
                useCase.packageReceiptForgetFailureMessage(identifier: identifier, reason: reason)
            )
        }
        let receiptDecision = try transition(
            from: receiptsStartDecision.state,
            event: .packageReceiptsObserved(readers.packageReceiptStates()),
            expectedCommandsWhenAllowed: [.complete]
        )
        guard receiptDecision.blockers.isEmpty else {
            try requireCommands([], in: receiptDecision)
            try writePersistedState(receiptDecision, clean: clean)
            throw RuntimeUninstallWorkflowError.operationFailed(
                useCase.packageReceiptVerificationFailedMessage(blockers: receiptDecision.blockers)
            )
        }
        return receiptDecision
    }

    private func complete(
        approvedBy receiptDecision: RuntimeUninstallTransitionDecision,
        clean: Bool
    ) throws {
        try requireCommands([.complete], in: receiptDecision)
        log(useCase.stepLogMessage(step: .forgetPackageReceipt, status: .completed))
        log(useCase.completedLogMessage())
        try writePersistedState(receiptDecision, clean: clean)
    }

    private func runtimeStopReadinessInput() -> RuntimeUninstallReadinessInput {
        RuntimeUninstallReadinessInput(
            serviceStates: readers.serviceStates(),
            vmProcessState: readers.vmProcessState()
        )
    }

    private func verifyRuntimeStopped(
        from state: RuntimeUninstallWorkflowState,
        clean: Bool
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try transition(
            from: state,
            event: .stoppedStateObserved(runtimeStopReadinessInput()),
            expectedCommandsWhenAllowed: [.removeFiles]
        )
        guard decision.blockers.isEmpty else {
            try writePersistedState(decision, clean: clean)
            throw RuntimeUninstallWorkflowError.operationFailed(
                useCase.runtimeStopBlockedFailureMessage(blockers: decision.blockers)
            )
        }
        return decision
    }

    private func verifyCleanupArtifacts(
        from state: RuntimeUninstallWorkflowState,
        clean: Bool
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try transition(
            from: state,
            event: .cleanupArtifactsObserved(readers.cleanupArtifactStates(clean)),
            expectedCommandsWhenAllowed: [.forgetPackageReceipts]
        )
        guard decision.blockers.isEmpty else {
            try writePersistedState(decision, clean: clean)
            throw RuntimeUninstallWorkflowError.operationFailed(
                useCase.cleanupArtifactsRemainFailureMessage(blockers: decision.blockers)
            )
        }
        return decision
    }

    private func transitionAndPersist(
        from state: RuntimeUninstallWorkflowState,
        event: RuntimeUninstallWorkflowEvent,
        clean: Bool,
        expectedCommands: [RuntimeUninstallWorkflowCommand]
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try useCase.transition(
            from: state,
            event: event,
            expectedCommands: expectedCommands
        )
        try writePersistedState(decision, clean: clean)
        return decision
    }

    private func transition(
        from state: RuntimeUninstallWorkflowState,
        event: RuntimeUninstallWorkflowEvent,
        expectedCommandsWhenAllowed: [RuntimeUninstallWorkflowCommand]
    ) throws -> RuntimeUninstallTransitionDecision {
        try useCase.transition(
            from: state,
            event: event,
            expectedCommandsWhenAllowed: expectedCommandsWhenAllowed
        )
    }

    private func requireCommands(
        _ expectedCommands: [RuntimeUninstallWorkflowCommand],
        in decision: RuntimeUninstallTransitionDecision
    ) throws {
        try useCase.requireCommands(expectedCommands, in: decision)
    }

    private func writePersistedState(
        _ decision: RuntimeUninstallTransitionDecision,
        clean: Bool
    ) throws {
        guard let state = decision.persistedState else {
            return
        }
        try writer.writeState(state, clean, decision.message, decision.blockers)
    }

    private func log(_ message: String) {
        diagnostics.log(message)
    }

}
