import Foundation
import Application
import Contracts
import Domain
import Errors

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
    public var stopRuntimeServices: (Bool) throws -> Void
    public var clearLaunchdDisabledOverrides: () throws -> Void
    public var describeError: (Error) -> String
    public var temporaryDirectory: () -> URL
    public var uniqueID: () -> String
    public var createDirectory: (URL, Bool) throws -> Void
    public var pathState: (URL) -> RuntimePathState
    public var removeItem: (URL) throws -> Void
    public var moveItem: (URL, URL) throws -> Void
    public var contentsOfDirectory: (URL, Bool) throws -> [URL]
    public var openFilesInDirectory: (URL) -> RuntimeProcessResult
    public var forgetPackageReceipt: (String) -> RuntimeProcessResult

    public init(
        createRedisBackup: @escaping () throws -> Void,
        stopRuntimeServices: @escaping (Bool) throws -> Void,
        clearLaunchdDisabledOverrides: @escaping () throws -> Void,
        describeError: @escaping (Error) -> String,
        temporaryDirectory: @escaping () -> URL,
        uniqueID: @escaping () -> String,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        pathState: @escaping (URL) -> RuntimePathState,
        removeItem: @escaping (URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        contentsOfDirectory: @escaping (URL, Bool) throws -> [URL],
        openFilesInDirectory: @escaping (URL) -> RuntimeProcessResult,
        forgetPackageReceipt: @escaping (String) -> RuntimeProcessResult
    ) {
        self.createRedisBackup = createRedisBackup
        self.stopRuntimeServices = stopRuntimeServices
        self.clearLaunchdDisabledOverrides = clearLaunchdDisabledOverrides
        self.describeError = describeError
        self.temporaryDirectory = temporaryDirectory
        self.uniqueID = uniqueID
        self.createDirectory = createDirectory
        self.pathState = pathState
        self.removeItem = removeItem
        self.moveItem = moveItem
        self.contentsOfDirectory = contentsOfDirectory
        self.openFilesInDirectory = openFilesInDirectory
        self.forgetPackageReceipt = forgetPackageReceipt
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
            forceClean: command.forceClean,
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
            forceClean: command.forceClean,
            writer: writer,
            effects: effects,
            diagnostics: diagnostics
        )
        let receiptDecision = try forgetReceiptsAndVerifyAbsence(
            approvedBy: cleanupDecision,
            clean: command.clean,
            forceClean: command.forceClean,
            readers: readers,
            writer: writer,
            effects: effects,
            diagnostics: diagnostics,
            packageReceiptIdentifiers: packageReceiptIdentifiers
        )
        try clearLaunchdDisabledOverridesBeforeCompletion(effects: effects, diagnostics: diagnostics)
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
        forceClean: Bool,
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
            try effects.stopRuntimeServices(clean)
        } catch {
            let blockedDecision = try transitionAndPersist(
                from: stopRequestDecision.state,
                event: .stopServicesFailed(
                    input: runtimeStopReadinessInput(readers: readers),
                    commandFailureReason: effects.describeError(error)
                ),
                clean: clean,
                expectedCommands: [],
                writer: writer
            )
            if forceClean {
                return try continueFromBlockedStopDecision(
                    blockedDecision,
                    clean: clean,
                    writer: writer
                )
            }
            throw error
        }
        log(stepLogMessage(step: .stopLaunchdServices, status: .completed), diagnostics: diagnostics)
        return try verifyRuntimeStopped(
            from: stopRequestDecision.state,
            clean: clean,
            forceClean: forceClean,
            readers: readers,
            writer: writer
        )
    }

    private func removeFilesAndVerifyCleanup(
        approvedBy stoppedDecision: RuntimeUninstallTransitionDecision,
        command: RuntimeUninstallCommand,
        paths: RuntimeUninstallPaths,
        readers: RuntimeUninstallStateReaders,
        forceClean: Bool,
        writer: RuntimeUninstallStateWriter,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws -> RuntimeUninstallTransitionDecision {
        let fileRemovalDecision: RuntimeUninstallTransitionDecision
        if stoppedDecision.state == .stoppedVerified {
            try requireCommands([.removeFiles], in: stoppedDecision)
            fileRemovalDecision = try transitionAndPersist(
                from: stoppedDecision.state,
                event: .filesRemovalStarted,
                clean: command.clean,
                expectedCommands: [],
                writer: writer
            )
        } else if stoppedDecision.state == .serviceStopBlocked {
            fileRemovalDecision = try continueFromBlockedStopDecision(
                stoppedDecision,
                clean: command.clean,
                writer: writer
            )
        } else if stoppedDecision.state == .filesRemovalStarted {
            fileRemovalDecision = stoppedDecision
        } else {
            return stoppedDecision
        }
        do {
            try executeFileRemoval(
                paths: paths,
                clean: command.clean,
                effects: effects,
                diagnostics: diagnostics
            )
            return try verifyCleanupArtifacts(
                from: fileRemovalDecision.state,
                clean: command.clean,
                forceClean: forceClean,
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
        forceClean: Bool,
        readers: RuntimeUninstallStateReaders,
        writer: RuntimeUninstallStateWriter,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics,
        packageReceiptIdentifiers: [String]
    ) throws -> RuntimeUninstallTransitionDecision {
        let receiptsStartDecision: RuntimeUninstallTransitionDecision
        if cleanupDecision.state == .cleanupVerified {
            try requireCommands([.forgetPackageReceipts], in: cleanupDecision)
            log(stepLogMessage(step: .forgetPackageReceipt, status: .started), diagnostics: diagnostics)
            receiptsStartDecision = try transitionAndPersist(
                from: cleanupDecision.state,
                event: .receiptsForgetStarted,
                clean: clean,
                expectedCommands: [],
                writer: writer
            )
        } else if cleanupDecision.state == .filesRemovalBlocked {
            return try continueFromBlockedReceiptStepDecision(
                cleanupDecision,
                clean: clean,
                writer: writer
            )
        } else if cleanupDecision.state == .receiptsForgetStarted {
            receiptsStartDecision = cleanupDecision
        } else {
            return cleanupDecision
        }

        let observedReceiptStates = uninstallUseCase().packageReceiptStateMap(readers.packageReceiptStates())
        do {
            try executeReceiptForgetting(
                identifiers: packageReceiptIdentifiers,
                observedReceiptStates: observedReceiptStates,
                effects: effects,
                diagnostics: diagnostics
            )
        } catch let error as RuntimeUninstallReceiptForgetExecutionError {
            let decision = try transitionAndPersist(
                from: receiptsStartDecision.state,
                event: .receiptForgetFailed(identifier: error.identifier, reason: error.reason),
                clean: clean,
                expectedCommands: [],
                writer: writer
            )
            if forceClean {
                return try continueFromBlockedReceiptStepDecision(
                    decision,
                    clean: clean,
                    writer: writer
                )
            }
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
            if forceClean {
                return try continueFromBlockedReceiptStepDecision(
                    receiptDecision,
                    clean: clean,
                    writer: writer
                )
            }
            try requireCommands([], in: receiptDecision)
            try writePersistedState(receiptDecision, clean: clean, writer: writer)
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().packageReceiptVerificationFailedMessage(blockers: receiptDecision.blockers)
            )
        }
        return receiptDecision
    }

    private func clearLaunchdDisabledOverridesBeforeCompletion(
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws {
        log("step=clear-launchd-disabled-overrides status=started", diagnostics: diagnostics)
        try effects.clearLaunchdDisabledOverrides()
        log("step=clear-launchd-disabled-overrides status=completed", diagnostics: diagnostics)
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

    private func executeFileRemoval(
        paths: RuntimeUninstallPaths,
        clean: Bool,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws {
        var preservedPaths: RuntimeUninstallPreservedPaths?
        do {
            try removeFiles(
                paths: paths,
                clean: clean,
                preservedPaths: &preservedPaths,
                effects: effects,
                diagnostics: diagnostics
            )
        } catch {
            let blockers = restorePreservedDataAfterFailureIfNeeded(
                error: error,
                preserved: preservedPaths,
                effects: effects,
                diagnostics: diagnostics
            )
            throw RuntimeUninstallFileRemovalExecutionError(
                underlyingError: error,
                blockers: blockers
            )
        }
    }

    private func removeFiles(
        paths: RuntimeUninstallPaths,
        clean: Bool,
        preservedPaths: inout RuntimeUninstallPreservedPaths?,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws {
        log(stepLogMessage(step: .removePlists, status: .started), diagnostics: diagnostics)
        for plist in paths.launchDaemonPlists {
            try removeIfPresent(plist, effects: effects)
        }
        log(stepLogMessage(step: .removePlists, status: .completed), diagnostics: diagnostics)

        let preserved = clean ? nil : try preserveUserData(paths: paths, effects: effects, diagnostics: diagnostics)
        preservedPaths = preserved

        log(stepLogMessage(step: .removeInstalledFiles, status: .started), diagnostics: diagnostics)
        let removalPlan = uninstallUseCase().removalPlan(
            clean: clean,
            managerApp: paths.managerApp,
            productRoot: paths.productRoot,
            externalVitalFilesDirectory: paths.externalVitalFilesDirectory,
            configuredVitalFilesDirectoryReadFailure: paths.configuredVitalFilesDirectoryReadFailure
        )
        for target in removalPlan.targets {
            try safeRemove(target, effects: effects, diagnostics: diagnostics)
        }
        if let skippedExternalDirectoryLogMessage = removalPlan.skippedExternalDirectoryLogMessage {
            log(skippedExternalDirectoryLogMessage, diagnostics: diagnostics)
        }
        log(stepLogMessage(step: .removeInstalledFiles, status: .completed), diagnostics: diagnostics)

        log(stepLogMessage(step: .removeRuntimeTools, status: .started), diagnostics: diagnostics)
        for tool in paths.runtimeTools {
            try removeIfPresent(tool, effects: effects)
        }
        log(stepLogMessage(step: .removeRuntimeTools, status: .completed), diagnostics: diagnostics)

        if let preserved {
            log(stepLogMessage(step: .restorePreservedUserData, status: .started), diagnostics: diagnostics)
            try restorePreservedPaths(preserved, effects: effects, diagnostics: diagnostics)
            log(stepLogMessage(step: .restorePreservedUserData, status: .completed), diagnostics: diagnostics)
        }
    }

    private func preserveUserData(
        paths: RuntimeUninstallPaths,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws -> RuntimeUninstallPreservedPaths {
        log(stepLogMessage(step: .preserveUserData, status: .started), diagnostics: diagnostics)
        let preserveRoot = uninstallUseCase().preserveRootDirectory(
            temporaryDirectory: effects.temporaryDirectory(),
            uniqueID: effects.uniqueID()
        )
        try effects.createDirectory(preserveRoot, true)

        var items: [RuntimeUninstallPreservedPath] = []
        let plan = uninstallUseCase().preservePlan(
            productRoot: paths.productRoot,
            defaultVitalFilesDirectory: paths.defaultVitalFilesDirectory,
            externalVitalFilesDirectory: paths.externalVitalFilesDirectory,
            configuredVitalFilesDirectoryReadFailure: paths.configuredVitalFilesDirectoryReadFailure
        )
        for candidate in plan.candidates {
            try preservePath(
                candidate.source,
                preserveRoot,
                candidate.token,
                into: &items,
                effects: effects,
                diagnostics: diagnostics
            )
        }
        if let externalDirectoryLogMessage = plan.externalDirectoryLogMessage {
            log(externalDirectoryLogMessage, diagnostics: diagnostics)
        }
        if let configuredDirectoryReadFailureLogMessage = plan.configuredDirectoryReadFailureLogMessage {
            log(configuredDirectoryReadFailureLogMessage, diagnostics: diagnostics)
        }

        log(stepLogMessage(step: .preserveUserData, status: .completed), diagnostics: diagnostics)
        return RuntimeUninstallPreservedPaths(root: preserveRoot, items: items)
    }

    private func preservePath(
        _ source: URL,
        _ preserveRoot: URL,
        _ token: String,
        into items: inout [RuntimeUninstallPreservedPath],
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws {
        guard try pathIsPresent(source, effects: effects) else {
            return
        }
        let destination = preserveRoot.appendingPathComponent(token)
        try removeIfPresent(destination, effects: effects)
        try effects.moveItem(source, destination)
        items.append(RuntimeUninstallPreservedPath(source: source, destination: destination))
        log(uninstallUseCase().preservedSourceLogMessage(path: source.path), diagnostics: diagnostics)
    }

    private func restorePreservedDataAfterFailureIfNeeded(
        error: Error,
        preserved: RuntimeUninstallPreservedPaths?,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) -> [String] {
        var preservedRestoreFailureReason: String?
        if let preserved {
            log(uninstallUseCase().restoringPreservedUserDataAfterFailureLogMessage(), diagnostics: diagnostics)
            do {
                try restorePreservedPaths(preserved, effects: effects, diagnostics: diagnostics)
            } catch {
                let reason = effects.describeError(error)
                log(uninstallUseCase().preservedUserDataRestoreFailedLogMessage(reason: reason), diagnostics: diagnostics)
                preservedRestoreFailureReason = reason
            }
        }
        return uninstallUseCase().fileRemovalBlockers(
            removalFailureReason: effects.describeError(error),
            preservedRestoreFailureReason: preservedRestoreFailureReason
        )
    }

    private func restorePreservedPaths(
        _ preserved: RuntimeUninstallPreservedPaths,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws {
        for item in preserved.items {
            try effects.createDirectory(item.source.deletingLastPathComponent(), true)
            try removeIfPresent(item.source, effects: effects)
            try effects.moveItem(item.destination, item.source)
            log(uninstallUseCase().restoredPreservedLogMessage(path: item.source.path), diagnostics: diagnostics)
        }
        try removeIfPresent(preserved.root, effects: effects)
    }

    private func safeRemove(
        _ target: URL,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws {
        guard target.path != "/" else {
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().unsafeRemovalTargetFailureMessage(path: target.path)
            )
        }
        guard try pathIsPresent(target, effects: effects) else {
            return
        }
        do {
            try effects.removeItem(target)
        } catch {
            logRemovalDiagnostics(target, effects: effects, diagnostics: diagnostics)
            throw error
        }
        if try pathIsPresent(target, effects: effects) {
            logRemovalDiagnostics(target, effects: effects, diagnostics: diagnostics)
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().removalIncompleteFailureMessage(path: target.path)
            )
        }
    }

    private func logRemovalDiagnostics(
        _ target: URL,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) {
        log(uninstallUseCase().removalDiagnosticTargetLogMessage(path: target.path), diagnostics: diagnostics)
        do {
            let items = try effects.contentsOfDirectory(target, false)
            for item in items.prefix(200) {
                log(uninstallUseCase().removalDiagnosticResidualLogMessage(path: item.path), diagnostics: diagnostics)
            }
        } catch {
            log(uninstallUseCase().removalDiagnosticContentsReadFailedLogMessage(
                path: target.path,
                reason: effects.describeError(error)
            ), diagnostics: diagnostics)
        }
        let result = effects.openFilesInDirectory(target)
        if result.exitCode == 0 {
            for line in result.stdout.split(separator: "\n").prefix(200) {
                log(uninstallUseCase().removalDiagnosticOpenFileLogMessage(line: String(line)), diagnostics: diagnostics)
            }
        }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            log(uninstallUseCase().removalDiagnosticOpenFileStderrLogMessage(stderr: stderr), diagnostics: diagnostics)
        }
    }

    private func removeIfPresent(_ url: URL, effects: RuntimeUninstallEffects) throws {
        guard try pathIsPresent(url, effects: effects) else {
            return
        }
        try effects.removeItem(url)
    }

    private func pathIsPresent(_ url: URL, effects: RuntimeUninstallEffects) throws -> Bool {
        let state = effects.pathState(url)
        switch state {
        case .file, .directory, .other:
            return true
        case .missing:
            return false
        case .inspectFailed(let reason):
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().removalTargetPathInspectionFailedMessage(path: url.path, reason: reason)
            )
        case .unknown:
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().removalTargetPathStateUnexpectedMessage(path: url.path, state: state.rawValue)
            )
        }
    }

    private func executeReceiptForgetting(
        identifiers: [String],
        observedReceiptStates: [String: RuntimePackageReceiptState],
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws {
        for identifier in identifiers {
            switch uninstallUseCase().receiptForgetDecision(
                identifier: identifier,
                observedReceiptStates: observedReceiptStates
            ) {
            case .skip(let logMessage):
                log(logMessage, diagnostics: diagnostics)
                continue
            case .forget(let logMessage):
                log(logMessage, diagnostics: diagnostics)
            }
            let result = effects.forgetPackageReceipt(identifier)
            guard result.exitCode == 0 else {
                throw RuntimeUninstallReceiptForgetExecutionError(
                    identifier: identifier,
                    reason: uninstallUseCase().processFailureReason(result)
                )
            }
        }
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
        forceClean: Bool,
        readers: RuntimeUninstallStateReaders,
        writer: RuntimeUninstallStateWriter
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try transition(
            from: state,
            event: .stoppedStateObserved(runtimeStopReadinessInput(readers: readers)),
            expectedCommandsWhenAllowed: [.removeFiles]
        )
        guard decision.blockers.isEmpty else {
            if forceClean {
                return try transitionAndPersist(
                    from: .serviceStopBlocked,
                    event: .forceCleanupContinue,
                    clean: clean,
                    expectedCommands: [],
                    writer: writer
                )
            }
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
        forceClean: Bool,
        readers: RuntimeUninstallStateReaders,
        writer: RuntimeUninstallStateWriter
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try transition(
            from: state,
            event: .cleanupArtifactsObserved(readers.cleanupArtifactStates(clean)),
            expectedCommandsWhenAllowed: [.forgetPackageReceipts]
        )
        guard decision.blockers.isEmpty else {
            if forceClean {
                try writePersistedState(decision, clean: clean, writer: writer)
                return try continueFromBlockedReceiptStepDecision(
                    decision,
                    clean: clean,
                    writer: writer
                )
            }
            try writePersistedState(decision, clean: clean, writer: writer)
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().cleanupArtifactsRemainFailureMessage(blockers: decision.blockers)
            )
        }
        return decision
    }

    private func continueFromBlockedStopDecision(
        _ decision: RuntimeUninstallTransitionDecision,
        clean: Bool,
        writer: RuntimeUninstallStateWriter
    ) throws -> RuntimeUninstallTransitionDecision {
        try writePersistedState(decision, clean: clean, writer: writer)
        return try transitionAndPersist(
            from: .serviceStopBlocked,
            event: .forceCleanupContinue,
            clean: clean,
            expectedCommands: [],
            writer: writer
        )
    }

    private func continueFromBlockedReceiptStepDecision(
        _ decision: RuntimeUninstallTransitionDecision,
        clean: Bool,
        writer: RuntimeUninstallStateWriter
    ) throws -> RuntimeUninstallTransitionDecision {
        try writePersistedState(decision, clean: clean, writer: writer)
        switch decision.state {
        case .filesRemovalBlocked:
            return try transitionAndPersist(
                from: .filesRemovalBlocked,
                event: .forceCleanupContinue,
                clean: clean,
                expectedCommands: [],
                writer: writer
            )
        case .receiptsForgetBlocked:
            return try transitionAndPersist(
                from: .receiptsForgetBlocked,
                event: .forceCleanupContinue,
                clean: clean,
                expectedCommands: [.complete],
                writer: writer
            )
        default:
            throw UninstallRuntimeUseCaseError.operationFailed(
                "force cleanup cannot continue from unexpected state \(decision.state)"
            )
        }
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

private struct RuntimeUninstallPreservedPaths {
    let root: URL
    let items: [RuntimeUninstallPreservedPath]
}

private struct RuntimeUninstallPreservedPath {
    let source: URL
    let destination: URL
}
