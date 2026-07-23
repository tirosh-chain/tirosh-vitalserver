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
    public let runtimeStateDatabase: URL
    public let managerApp: URL
    public let defaultVitalFilesDirectory: URL
    public let externalVitalFilesDirectory: URL?
    public let configuredVitalFilesDirectoryReadFailure: String?
    public let launchDaemonPlists: [URL]
    public let runtimeTools: [URL]

    public init(
        productRoot: URL,
        runtimeStateDatabase: URL,
        managerApp: URL,
        defaultVitalFilesDirectory: URL,
        externalVitalFilesDirectory: URL?,
        configuredVitalFilesDirectoryReadFailure: String?,
        launchDaemonPlists: [URL],
        runtimeTools: [URL]
    ) {
        self.productRoot = productRoot
        self.runtimeStateDatabase = runtimeStateDatabase
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

public enum RuntimeUninstallRemoveItemResult: Equatable, Sendable {
    case removed(path: String)
    case alreadyAbsent(path: String)
}

private struct RuntimeUninstallRemovalResult {
    let decision: RuntimeUninstallTransitionDecision
    let relocatedProductRoot: URL?
}

public struct RuntimeUninstallEffects {
    public var createVitalServerBackup: () throws -> Void
    public var stopRuntimeServices: (Bool, Bool) throws -> Void
    public var clearLaunchdDisabledOverrides: () throws -> Void
    public var describeError: (Error) -> String
    public var temporaryDirectory: () -> URL
    public var uniqueID: () -> String
    public var createDirectory: (URL, Bool) throws -> Void
    public var pathState: (URL) -> RuntimePathState
    public var removeItem: (URL) throws -> RuntimeUninstallRemoveItemResult
    public var moveItem: (URL, URL) throws -> Void
    public var contentsOfDirectory: (URL, Bool) throws -> [URL]
    public var openFilesInDirectory: (URL) -> RuntimeProcessResult
    public var forgetPackageReceipt: (String) -> RuntimeProcessResult

    public init(
        createVitalServerBackup: @escaping () throws -> Void,
        stopRuntimeServices: @escaping (Bool, Bool) throws -> Void,
        clearLaunchdDisabledOverrides: @escaping () throws -> Void,
        describeError: @escaping (Error) -> String,
        temporaryDirectory: @escaping () -> URL,
        uniqueID: @escaping () -> String,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        pathState: @escaping (URL) -> RuntimePathState,
        removeItem: @escaping (URL) throws -> RuntimeUninstallRemoveItemResult,
        moveItem: @escaping (URL, URL) throws -> Void,
        contentsOfDirectory: @escaping (URL, Bool) throws -> [URL],
        openFilesInDirectory: @escaping (URL) -> RuntimeProcessResult,
        forgetPackageReceipt: @escaping (String) -> RuntimeProcessResult
    ) {
        self.createVitalServerBackup = createVitalServerBackup
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
    public var acquireOperationLease: () throws -> Void
    public var releaseOperationLease: () throws -> Void
    public var writeState: (RuntimeUninstallState, Bool, String?, [String]) throws -> Void
    public var relocateProductRoot: (URL, URL) throws -> Void

    public init(
        acquireOperationLease: @escaping () throws -> Void,
        releaseOperationLease: @escaping () throws -> Void,
        writeState: @escaping (RuntimeUninstallState, Bool, String?, [String]) throws -> Void,
        relocateProductRoot: @escaping (URL, URL) throws -> Void
    ) {
        self.acquireOperationLease = acquireOperationLease
        self.releaseOperationLease = releaseOperationLease
        self.writeState = writeState
        self.relocateProductRoot = relocateProductRoot
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
        let removal = try removeFilesAndVerifyCleanup(
            approvedBy: stoppedDecision,
            command: command,
            paths: paths,
            readers: readers,
            writer: writer,
            effects: effects,
            diagnostics: diagnostics
        )
        let receiptDecision = try forgetReceiptsAndVerifyAbsence(
            approvedBy: removal.decision,
            clean: command.clean,
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
        try writer.releaseOperationLease()
        try disposeRelocatedProductRoot(
            removal.relocatedProductRoot,
            effects: effects,
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
        guard uninstallUseCase().shouldCreateVitalServerBackup(clean: command.clean) else {
            return state
        }

        log(stepLogMessage(step: .createVitalServerBackup, status: .started), diagnostics: diagnostics)
        let backupRequestDecision = try transitionAndPersist(
            from: state,
            event: .vitalServerBackupRequested,
            clean: command.clean,
            expectedCommands: [.createVitalServerBackup],
            writer: writer
        )
        do {
            try effects.createVitalServerBackup()
            log(stepLogMessage(step: .createVitalServerBackup, status: .completed), diagnostics: diagnostics)
            let backupCompletedDecision = try transitionAndPersist(
                from: backupRequestDecision.state,
                event: .vitalServerBackupSucceeded,
                clean: command.clean,
                expectedCommands: [],
                writer: writer
            )
            return backupCompletedDecision.state
        } catch {
            let reason = effects.describeError(error)
            log(uninstallUseCase().vitalServerBackupAbortLogMessage(reason: reason), diagnostics: diagnostics)
            let decision = try transitionAndPersist(
                from: backupRequestDecision.state,
                event: .vitalServerBackupFailed(reason: reason),
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
            try effects.stopRuntimeServices(clean, forceClean)
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
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().runtimeStopBlockedFailureMessage(blockers: blockedDecision.blockers)
            )
        }
        log(stepLogMessage(step: .stopLaunchdServices, status: .completed), diagnostics: diagnostics)
        return try verifyRuntimeStopped(
            from: stopRequestDecision.state,
            clean: clean,
            readers: readers,
            writer: writer
        )
    }

    private func removeFilesAndVerifyCleanup(
        approvedBy stoppedDecision: RuntimeUninstallTransitionDecision,
        command: RuntimeUninstallCommand,
        paths: RuntimeUninstallPaths,
        readers: RuntimeUninstallStateReaders,
        writer: RuntimeUninstallStateWriter,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws -> RuntimeUninstallRemovalResult {
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
        } else if stoppedDecision.state == .filesRemovalStarted {
            fileRemovalDecision = stoppedDecision
        } else {
            return RuntimeUninstallRemovalResult(
                decision: stoppedDecision,
                relocatedProductRoot: nil
            )
        }
        do {
            let relocatedProductRoot = try executeFileRemoval(
                paths: paths,
                clean: command.clean,
                writer: writer,
                effects: effects,
                diagnostics: diagnostics
            )
            let decision = try verifyCleanupArtifacts(
                from: fileRemovalDecision.state,
                clean: command.clean,
                readers: readers,
                writer: writer
            )
            return RuntimeUninstallRemovalResult(
                decision: decision,
                relocatedProductRoot: relocatedProductRoot
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
        writer: RuntimeUninstallStateWriter,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws -> URL? {
        var preservedPaths: RuntimeUninstallPreservedPaths?
        do {
            return try removeFiles(
                paths: paths,
                clean: clean,
                preservedPaths: &preservedPaths,
                writer: writer,
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
        writer: RuntimeUninstallStateWriter,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws -> URL? {
        log(stepLogMessage(step: .removePlists, status: .started), diagnostics: diagnostics)
        for plist in paths.launchDaemonPlists {
            try removeIfPresent(plist, effects: effects, diagnostics: diagnostics)
        }
        log(stepLogMessage(step: .removePlists, status: .completed), diagnostics: diagnostics)

        let preserved = clean ? nil : try preserveUserData(paths: paths, effects: effects, diagnostics: diagnostics)
        preservedPaths = preserved

        log(stepLogMessage(step: .removeInstalledFiles, status: .started), diagnostics: diagnostics)
        let relocatedProductRoot = try relocateProductRoot(
            paths: paths,
            writer: writer,
            effects: effects,
            diagnostics: diagnostics
        )
        let removalPlan = uninstallUseCase().removalPlan(
            clean: clean,
            managerApp: paths.managerApp,
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
            try removeIfPresent(tool, effects: effects, diagnostics: diagnostics)
        }
        log(stepLogMessage(step: .removeRuntimeTools, status: .completed), diagnostics: diagnostics)

        if let preserved {
            log(stepLogMessage(step: .restorePreservedUserData, status: .started), diagnostics: diagnostics)
            try restorePreservedPaths(preserved, effects: effects, diagnostics: diagnostics)
            log(stepLogMessage(step: .restorePreservedUserData, status: .completed), diagnostics: diagnostics)
        }
        return relocatedProductRoot
    }

    private func relocateProductRoot(
        paths: RuntimeUninstallPaths,
        writer: RuntimeUninstallStateWriter,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws -> URL? {
        guard try pathIsPresent(paths.productRoot, effects: effects) else {
            return nil
        }
        let relocatedProductRoot = uninstallUseCase().relocatedProductRoot(
            productRoot: paths.productRoot,
            uniqueID: effects.uniqueID()
        )
        guard try pathIsPresent(relocatedProductRoot, effects: effects) == false else {
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().relocatedProductRootAlreadyPresentMessage(
                    path: relocatedProductRoot.path
                )
            )
        }
        do {
            try effects.moveItem(paths.productRoot, relocatedProductRoot)
        } catch {
            logRemovalDiagnostics(paths.productRoot, effects: effects, diagnostics: diagnostics)
            throw error
        }
        try writer.relocateProductRoot(paths.productRoot, relocatedProductRoot)
        log(
            uninstallUseCase().relocatedProductRootLogMessage(
                source: paths.productRoot.path,
                destination: relocatedProductRoot.path
            ),
            diagnostics: diagnostics
        )
        return relocatedProductRoot
    }

    private func disposeRelocatedProductRoot(
        _ relocatedProductRoot: URL?,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws {
        guard let relocatedProductRoot else {
            return
        }
        log("step=dispose-uninstall-state-store status=started", diagnostics: diagnostics)
        do {
            try safeRemove(relocatedProductRoot, effects: effects, diagnostics: diagnostics)
        } catch {
            throw UninstallRuntimeUseCaseError.operationFailed(
                uninstallUseCase().relocatedProductRootDisposalFailedMessage(
                    path: relocatedProductRoot.path,
                    reason: effects.describeError(error)
                )
            )
        }
        log("step=dispose-uninstall-state-store status=completed", diagnostics: diagnostics)
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
        try removeIfPresent(destination, effects: effects, diagnostics: diagnostics)
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
            try removeIfPresent(item.source, effects: effects, diagnostics: diagnostics)
            try effects.moveItem(item.destination, item.source)
            log(uninstallUseCase().restoredPreservedLogMessage(path: item.source.path), diagnostics: diagnostics)
        }
        try removeIfPresent(preserved.root, effects: effects, diagnostics: diagnostics)
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
            let result = try effects.removeItem(target)
            logRemovalResultIfNeeded(result, diagnostics: diagnostics)
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

    private func removeIfPresent(
        _ url: URL,
        effects: RuntimeUninstallEffects,
        diagnostics: RuntimeUninstallDiagnostics
    ) throws {
        guard try pathIsPresent(url, effects: effects) else {
            return
        }
        let result = try effects.removeItem(url)
        logRemovalResultIfNeeded(result, diagnostics: diagnostics)
    }

    private func logRemovalResultIfNeeded(
        _ result: RuntimeUninstallRemoveItemResult,
        diagnostics: RuntimeUninstallDiagnostics
    ) {
        switch result {
        case .removed:
            return
        case .alreadyAbsent(let path):
            log(uninstallUseCase().removalTargetAlreadyAbsentLogMessage(path: path), diagnostics: diagnostics)
        }
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

private struct RuntimeUninstallPreservedPaths {
    let root: URL
    let items: [RuntimeUninstallPreservedPath]
}

private struct RuntimeUninstallPreservedPath {
    let source: URL
    let destination: URL
}
