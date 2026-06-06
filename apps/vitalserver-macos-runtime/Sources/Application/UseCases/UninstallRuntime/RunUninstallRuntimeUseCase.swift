import Foundation
import Contracts
import Domain
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

public struct RuntimeUninstallEffects {
    public var createRedisBackup: () throws -> Void
    public var stopRuntimeServices: () throws -> Void
    public var describeError: (Error) -> String
    public var executeFileRemoval: (RuntimeUninstallPaths, Bool) throws -> Void
    public var executeReceiptForgetting: (
        [String],
        [String: RuntimePackageReceiptState]
    ) throws -> Void

    public init(
        createRedisBackup: @escaping () throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        describeError: @escaping (Error) -> String,
        executeFileRemoval: @escaping (RuntimeUninstallPaths, Bool) throws -> Void,
        executeReceiptForgetting: @escaping (
            [String],
            [String: RuntimePackageReceiptState]
        ) throws -> Void
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

public struct RunUninstallRuntimeUseCase {
    public init() {}

    public func run(
        _ command: RuntimeUninstallCommand,
        paths: RuntimeUninstallPaths,
        readers: RuntimeUninstallStateReaders,
        effects: RuntimeUninstallEffects,
        writer: RuntimeUninstallStateWriter,
        diagnostics: RuntimeUninstallDiagnostics,
        packageReceiptIdentifiers: [String]
    ) throws {
        let startedState = try start(
            command,
            paths: paths,
            writer: writer,
            diagnostics: diagnostics
        )
        let readyForStopState = try backupIfNeeded(
            command,
            from: startedState,
            writer: writer,
            effects: effects,
            diagnostics: diagnostics
        )
        let stoppedDecision = try stopAndVerifyRuntime(
            from: readyForStopState,
            clean: command.clean,
            readers: readers,
            writer: writer,
            effects: effects,
            diagnostics: diagnostics
        )
        let cleanupDecision = try removeFilesAndVerifyCleanup(
            approvedBy: stoppedDecision,
            command: command,
            paths: paths,
            readers: readers,
            writer: writer,
            effects: effects
        )
        let receiptDecision = try forgetReceiptsAndVerifyAbsence(
            approvedBy: cleanupDecision,
            clean: command.clean,
            readers: readers,
            writer: writer,
            effects: effects,
            diagnostics: diagnostics,
            packageReceiptIdentifiers: packageReceiptIdentifiers
        )
        try complete(
            approvedBy: receiptDecision,
            clean: command.clean,
            writer: writer,
            diagnostics: diagnostics
        )
    }

    private func start(
        _ command: RuntimeUninstallCommand,
        paths: RuntimeUninstallPaths,
        writer: RuntimeUninstallStateWriter,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws -> RuntimeUninstallWorkflowState {
        let plan = uninstallUseCase().startPlan(
            clean: command.clean,
            configuredDirectoryReadFailure: paths.configuredVitalFilesDirectoryReadFailure
        )
        log(plan.startedLogMessage, diagnostics: diagnostics)
        let startDecision = try transitionAndPersist(
            from: .notStarted,
            event: .start(clean: command.clean),
            clean: command.clean,
            expectedCommands: [],
            writer: writer
        )
        if let configuredDirectoryReadFailureLogMessage = plan.configuredDirectoryReadFailureLogMessage {
            log(configuredDirectoryReadFailureLogMessage, diagnostics: diagnostics)
        }
        return startDecision.state
    }

    private func backupIfNeeded(
        _ command: RuntimeUninstallCommand,
        from state: RuntimeUninstallWorkflowState,
        writer: RuntimeUninstallStateWriter,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws -> RuntimeUninstallWorkflowState {
        guard uninstallUseCase().shouldCreateRedisBackup(clean: command.clean) else {
            return state
        }

        log(stepLogMessage(step: .createRedisBackup, status: .started), diagnostics: diagnostics)
        let backupRequestDecision = try transitionAndPersist(
            from: state,
            event: .redisBackupRequested,
            clean: command.clean,
            expectedCommands: [.createRedisBackup],
            writer: writer
        )
        do {
            try effects.createRedisBackup()
            log(stepLogMessage(step: .createRedisBackup, status: .completed), diagnostics: diagnostics)
            let backupCompletedDecision = try transitionAndPersist(
                from: backupRequestDecision.state,
                event: .redisBackupSucceeded,
                clean: command.clean,
                expectedCommands: [],
                writer: writer
            )
            return backupCompletedDecision.state
        } catch {
            let reason = effects.describeError(error)
            log(uninstallUseCase().redisBackupAbortLogMessage(reason: reason), diagnostics: diagnostics)
            let decision = try transitionAndPersist(
                from: backupRequestDecision.state,
                event: .redisBackupFailed(reason: reason),
                clean: command.clean,
                expectedCommands: [],
                writer: writer
            )
            try requireCommands([], in: decision)
            throw error
        }
    }

    private func stopAndVerifyRuntime(
        from state: RuntimeUninstallWorkflowState,
        clean: Bool,
        readers: RuntimeUninstallStateReaders,
        writer: RuntimeUninstallStateWriter,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws -> RuntimeUninstallTransitionDecision {
        log(stepLogMessage(step: .stopLaunchdServices, status: .started), diagnostics: diagnostics)
        let stopRequestDecision = try transitionAndPersist(
            from: state,
            event: .stopServicesRequested,
            clean: clean,
            expectedCommands: [.stopRuntimeServices],
            writer: writer
        )
        do {
            try effects.stopRuntimeServices()
        } catch {
            _ = try transitionAndPersist(
                from: stopRequestDecision.state,
                event: .stopServicesFailed(
                    input: runtimeStopReadinessInput(readers: readers),
                    commandFailureReason: effects.describeError(error)
                ),
                clean: clean,
                expectedCommands: [],
                writer: writer
            )
            throw error
        }
        log(stepLogMessage(step: .stopLaunchdServices, status: .completed), diagnostics: diagnostics)
        return try verifyRuntimeStopped(from: stopRequestDecision.state, clean: clean, readers: readers, writer: writer)
    }

    private func removeFilesAndVerifyCleanup(
        approvedBy stoppedDecision: RuntimeUninstallTransitionDecision,
        command: RuntimeUninstallCommand,
        paths: RuntimeUninstallPaths,
        readers: RuntimeUninstallStateReaders,
        writer: RuntimeUninstallStateWriter,
        effects: RuntimeUninstallEffects
    ) throws -> RuntimeUninstallTransitionDecision {
        try requireCommands([.removeFiles], in: stoppedDecision)
        let fileRemovalDecision = try transitionAndPersist(
            from: stoppedDecision.state,
            event: .filesRemovalStarted,
            clean: command.clean,
            expectedCommands: [],
            writer: writer
        )
        do {
            try effects.executeFileRemoval(paths, command.clean)
            return try verifyCleanupArtifacts(
                from: fileRemovalDecision.state,
                clean: command.clean,
                readers: readers,
                writer: writer
            )
        } catch let error as RuntimeUninstallFileRemovalExecutionError {
            try writer.writeState(
                .filesRemovalBlocked,
                command.clean,
                uninstallUseCase().fileRemovalBlockedMessage(),
                error.blockers
            )
            throw error.underlyingError
        }
    }

    private func forgetReceiptsAndVerifyAbsence(
        approvedBy cleanupDecision: RuntimeUninstallTransitionDecision,
        clean: Bool,
        readers: RuntimeUninstallStateReaders,
        writer: RuntimeUninstallStateWriter,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics,
        packageReceiptIdentifiers: [String]
    ) throws -> RuntimeUninstallTransitionDecision {
        try requireCommands([.forgetPackageReceipts], in: cleanupDecision)
        log(stepLogMessage(step: .forgetPackageReceipt, status: .started), diagnostics: diagnostics)
        let receiptsStartDecision = try transitionAndPersist(
            from: cleanupDecision.state,
            event: .receiptsForgetStarted,
            clean: clean,
            expectedCommands: [],
            writer: writer
        )

        let observedReceiptStates = uninstallUseCase().packageReceiptStateMap(readers.packageReceiptStates())
        do {
            try effects.executeReceiptForgetting(packageReceiptIdentifiers, observedReceiptStates)
        } catch let error as RuntimeUninstallReceiptForgetExecutionError {
            _ = try transitionAndPersist(
                from: receiptsStartDecision.state,
                event: .receiptForgetFailed(identifier: error.identifier, reason: error.reason),
                clean: clean,
                expectedCommands: [],
                writer: writer
            )
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().packageReceiptForgetFailureMessage(identifier: error.identifier, reason: error.reason)
            )
        }
        let receiptDecision = try transition(
            from: receiptsStartDecision.state,
            event: .packageReceiptsObserved(readers.packageReceiptStates()),
            expectedCommandsWhenAllowed: [.complete]
        )
        guard receiptDecision.blockers.isEmpty else {
            try requireCommands([], in: receiptDecision)
            try writePersistedState(receiptDecision, clean: clean, writer: writer)
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().packageReceiptVerificationFailedMessage(blockers: receiptDecision.blockers)
            )
        }
        return receiptDecision
    }

    private func complete(
        approvedBy receiptDecision: RuntimeUninstallTransitionDecision,
        clean: Bool,
        writer: RuntimeUninstallStateWriter,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws {
        try requireCommands([.complete], in: receiptDecision)
        log(stepLogMessage(step: .forgetPackageReceipt, status: .completed), diagnostics: diagnostics)
        log(uninstallUseCase().completedLogMessage(), diagnostics: diagnostics)
        try writePersistedState(receiptDecision, clean: clean, writer: writer)
    }

    private func runtimeStopReadinessInput(readers: RuntimeUninstallStateReaders) -> RuntimeUninstallReadinessInput {
        RuntimeUninstallReadinessInput(
            serviceStates: readers.serviceStates(),
            vmProcessState: readers.vmProcessState()
        )
    }

    private func verifyRuntimeStopped(
        from state: RuntimeUninstallWorkflowState,
        clean: Bool,
        readers: RuntimeUninstallStateReaders,
        writer: RuntimeUninstallStateWriter
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try transition(
            from: state,
            event: .stoppedStateObserved(runtimeStopReadinessInput(readers: readers)),
            expectedCommandsWhenAllowed: [.removeFiles]
        )
        guard decision.blockers.isEmpty else {
            try writePersistedState(decision, clean: clean, writer: writer)
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().runtimeStopBlockedFailureMessage(blockers: decision.blockers)
            )
        }
        return decision
    }

    private func verifyCleanupArtifacts(
        from state: RuntimeUninstallWorkflowState,
        clean: Bool,
        readers: RuntimeUninstallStateReaders,
        writer: RuntimeUninstallStateWriter
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try transition(
            from: state,
            event: .cleanupArtifactsObserved(readers.cleanupArtifactStates(clean)),
            expectedCommandsWhenAllowed: [.forgetPackageReceipts]
        )
        guard decision.blockers.isEmpty else {
            try writePersistedState(decision, clean: clean, writer: writer)
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().cleanupArtifactsRemainFailureMessage(blockers: decision.blockers)
            )
        }
        return decision
    }

    private func transitionAndPersist(
        from state: RuntimeUninstallWorkflowState,
        event: RuntimeUninstallWorkflowEvent,
        clean: Bool,
        expectedCommands: [RuntimeUninstallWorkflowCommand],
        writer: RuntimeUninstallStateWriter
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try uninstallUseCase().transition(
            from: state,
            event: event,
            expectedCommands: expectedCommands
        )
        try writePersistedState(decision, clean: clean, writer: writer)
        return decision
    }

    private func transition(
        from state: RuntimeUninstallWorkflowState,
        event: RuntimeUninstallWorkflowEvent,
        expectedCommandsWhenAllowed: [RuntimeUninstallWorkflowCommand]
    ) throws -> RuntimeUninstallTransitionDecision {
        try uninstallUseCase().transition(
            from: state,
            event: event,
            expectedCommandsWhenAllowed: expectedCommandsWhenAllowed
        )
    }

    private func requireCommands(
        _ expectedCommands: [RuntimeUninstallWorkflowCommand],
        in decision: RuntimeUninstallTransitionDecision
    ) throws {
        try uninstallUseCase().requireCommands(expectedCommands, in: decision)
    }

    private func writePersistedState(
        _ decision: RuntimeUninstallTransitionDecision,
        clean: Bool,
        writer: RuntimeUninstallStateWriter
    ) throws {
        guard let state = decision.persistedState else {
            return
        }
        try writer.writeState(state, clean, decision.message, decision.blockers)
    }

    private func stepLogMessage(
        step: UninstallRuntimeWorkflowLogStep,
        status: UninstallRuntimeWorkflowLogStepStatus
    ) -> String {
        uninstallUseCase().stepLogMessage(step: step, status: status)
    }

    private func log(_ message: String, diagnostics: RuntimeUninstallDiagnostics) {
        diagnostics.log(message)
    }

    private func uninstallUseCase() -> UninstallRuntimeUseCase {
        UninstallRuntimeUseCase()
    }
}
