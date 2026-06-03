import Core
import Contracts
import Foundation

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

public enum RuntimeWorkflowError: Error, CustomStringConvertible {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }
}

public struct RuntimeUninstallStateReaders {
    public var serviceStates: () -> [RuntimeManagedService: RuntimeServiceState]
    public var vmProcessState: () -> RuntimeVMProcessState
    public var fileExists: (URL) -> Bool
    public var directoryExists: (URL) -> Bool
    public var packageReceiptStates: () -> [RuntimePackageReceiptState]
    public var cleanupArtifactStates: (Bool) -> [RuntimeInstallArtifactState]

    public init(
        serviceStates: @escaping () -> [RuntimeManagedService: RuntimeServiceState],
        vmProcessState: @escaping () -> RuntimeVMProcessState,
        fileExists: @escaping (URL) -> Bool,
        directoryExists: @escaping (URL) -> Bool,
        packageReceiptStates: @escaping () -> [RuntimePackageReceiptState],
        cleanupArtifactStates: @escaping (Bool) -> [RuntimeInstallArtifactState]
    ) {
        self.serviceStates = serviceStates
        self.vmProcessState = vmProcessState
        self.fileExists = fileExists
        self.directoryExists = directoryExists
        self.packageReceiptStates = packageReceiptStates
        self.cleanupArtifactStates = cleanupArtifactStates
    }
}

public struct RuntimeUninstallEffects {
    public var createRedisBackup: () throws -> Void
    public var stopRuntimeServices: () throws -> Void
    public var createDirectory: (URL, Bool) throws -> Void
    public var removeItem: (URL) throws -> Void
    public var moveItem: (URL, URL) throws -> Void
    public var forgetPackageReceipt: (String) -> RuntimeProcessResult

    public init(
        createRedisBackup: @escaping () throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removeItem: @escaping (URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        forgetPackageReceipt: @escaping (String) -> RuntimeProcessResult
    ) {
        self.createRedisBackup = createRedisBackup
        self.stopRuntimeServices = stopRuntimeServices
        self.createDirectory = createDirectory
        self.removeItem = removeItem
        self.moveItem = moveItem
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
    public var contentsOfDirectory: (URL) throws -> [URL]
    public var runProcess: (String, [String]) -> RuntimeProcessResult
    public var log: (String) -> Void

    public init(
        contentsOfDirectory: @escaping (URL) throws -> [URL],
        runProcess: @escaping (String, [String]) -> RuntimeProcessResult,
        log: @escaping (String) -> Void
    ) {
        self.contentsOfDirectory = contentsOfDirectory
        self.runProcess = runProcess
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
        log("uninstall started clean=\(command.clean)")
        let startDecision = try transitionAndPersist(
            from: .notStarted,
            event: .start(clean: command.clean),
            clean: command.clean,
            expectedCommands: []
        )
        if let readFailure = paths.configuredVitalFilesDirectoryReadFailure {
            log("configured vital files directory unavailable reason=\(readFailure)")
        }
        return startDecision.state
    }

    private func backupIfNeeded(
        _ command: RuntimeUninstallCommand,
        from state: RuntimeUninstallWorkflowState
    ) throws -> RuntimeUninstallWorkflowState {
        guard !command.clean else {
            return state
        }

        log("step=create-redis-backup status=started")
        let backupRequestDecision = try transitionAndPersist(
            from: state,
            event: .redisBackupRequested,
            clean: command.clean,
            expectedCommands: [.createRedisBackup]
        )
        do {
            try effects.createRedisBackup()
            log("step=create-redis-backup status=completed")
            let backupCompletedDecision = try transitionAndPersist(
                from: backupRequestDecision.state,
                event: .redisBackupSucceeded,
                clean: command.clean,
                expectedCommands: []
            )
            return backupCompletedDecision.state
        } catch {
            log("standard uninstall aborted because Redis backup did not complete error=\(error.localizedDescription)")
            let decision = try transitionAndPersist(
                from: backupRequestDecision.state,
                event: .redisBackupFailed(reason: error.localizedDescription),
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
        log("step=stop-launchd-services status=started")
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
                    commandFailureReason: error.localizedDescription
                ),
                clean: clean,
                expectedCommands: []
            )
            throw error
        }
        log("step=stop-launchd-services status=completed")
        return try verifyRuntimeStopped(from: stopRequestDecision.state, clean: clean)
    }

    private func removeFilesAndVerifyCleanup(
        approvedBy stoppedDecision: RuntimeUninstallTransitionDecision,
        command: RuntimeUninstallCommand
    ) throws -> RuntimeUninstallTransitionDecision {
        try requireCommands([.removeFiles], in: stoppedDecision)
        log("step=remove-plists status=started")
        for plist in paths.launchDaemonPlists {
            try removeIfPresent(plist)
        }
        log("step=remove-plists status=completed")

        let preserved = command.clean ? nil : try preserveUserData()
        do {
            log("step=remove-installed-files status=started")
            let fileRemovalDecision = try transitionAndPersist(
                from: stoppedDecision.state,
                event: .filesRemovalStarted,
                clean: command.clean,
                expectedCommands: []
            )
            try removeInstalledFiles(clean: command.clean)
            log("step=remove-installed-files status=completed")

            log("step=remove-runtime-tools status=started")
            for tool in paths.runtimeTools {
                try removeIfPresent(tool)
            }
            log("step=remove-runtime-tools status=completed")
            let cleanupDecision = try verifyCleanupArtifacts(from: fileRemovalDecision.state, clean: command.clean)

            if let preserved {
                log("step=restore-preserved-user-data status=started")
                try restorePreservedPaths(preserved)
                log("step=restore-preserved-user-data status=completed")
            }

            return cleanupDecision
        } catch {
            var blockers = ["file-removal-failed:reason=\(error.localizedDescription)"]
            if let preserved {
                log("restoring preserved user data after uninstall failure")
                do {
                    try restorePreservedPaths(preserved)
                } catch {
                    log("preserved user data restore failed error=\(error.localizedDescription)")
                    blockers.append("restore-preserved-user-data-failed:reason=\(error.localizedDescription)")
                }
            }
            try writer.writeState(
                .filesRemovalBlocked,
                command.clean,
                "file removal blocked",
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
        log("step=forget-package-receipt status=started")
        let receiptsStartDecision = try transitionAndPersist(
            from: cleanupDecision.state,
            event: .receiptsForgetStarted,
            clean: clean,
            expectedCommands: []
        )

        for identifier in packageReceiptIdentifiers {
            log("forget package receipt identifier=\(identifier)")
            let result = effects.forgetPackageReceipt(identifier)
            guard result.exitCode == 0 else {
                let reason = processFailureReason(result)
                _ = try transitionAndPersist(
                    from: receiptsStartDecision.state,
                    event: .receiptForgetFailed(identifier: identifier, reason: reason),
                    clean: clean,
                    expectedCommands: []
                )
                throw RuntimeWorkflowError.operationFailed(
                    "package receipt forget failed identifier=\(identifier) \(reason)"
                )
            }
        }
        let receiptDecision = try transition(
            from: receiptsStartDecision.state,
            event: .packageReceiptsObserved(readers.packageReceiptStates()),
            expectedCommandsWhenAllowed: [.complete]
        )
        guard receiptDecision.blockers.isEmpty else {
            try requireCommands([], in: receiptDecision)
            try writePersistedState(receiptDecision, clean: clean)
            throw RuntimeWorkflowError.operationFailed(
                "package receipt forget verification failed blockers=\(receiptDecision.blockers.joined(separator: ","))"
            )
        }
        return receiptDecision
    }

    private func complete(
        approvedBy receiptDecision: RuntimeUninstallTransitionDecision,
        clean: Bool
    ) throws {
        try requireCommands([.complete], in: receiptDecision)
        log("step=forget-package-receipt status=completed")
        log("uninstall completed")
        try writePersistedState(receiptDecision, clean: clean)
    }

    private func preserveUserData() throws -> RuntimeUninstallPreservedPaths {
        log("step=preserve-user-data status=started")
        let preserveRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tirosh-vitalserver-uninstall-\(UUID().uuidString)")
        try effects.createDirectory(preserveRoot, true)

        var items: [RuntimeUninstallPreservedPath] = []
        try preservePath(paths.productRoot.appendingPathComponent("logs"), preserveRoot, "logs", into: &items)
        try preservePath(paths.productRoot.appendingPathComponent("backups"), preserveRoot, "backups", into: &items)
        try preservePath(
            paths.productRoot.appendingPathComponent("vm/data/backups/redis"),
            preserveRoot,
            "redis-backups",
            into: &items
        )
        if let externalVitalFilesDirectory = paths.externalVitalFilesDirectory {
            log("preserved external vital files directory=\(externalVitalFilesDirectory.path)")
        } else {
            if let readFailure = paths.configuredVitalFilesDirectoryReadFailure {
                log("preserving default vital files directory because configured external directory is unavailable reason=\(readFailure)")
            }
            try preservePath(paths.defaultVitalFilesDirectory, preserveRoot, "vital-files", into: &items)
        }

        log("step=preserve-user-data status=completed")
        return RuntimeUninstallPreservedPaths(root: preserveRoot, items: items)
    }

    private func preservePath(
        _ source: URL,
        _ preserveRoot: URL,
        _ token: String,
        into items: inout [RuntimeUninstallPreservedPath]
    ) throws {
        guard exists(source) else {
            return
        }
        let destination = preserveRoot.appendingPathComponent(token)
        try removeIfPresent(destination)
        try effects.moveItem(source, destination)
        items.append(RuntimeUninstallPreservedPath(source: source, destination: destination))
        log("preserved source=\(source.path)")
    }

    private func restorePreservedPaths(_ preserved: RuntimeUninstallPreservedPaths) throws {
        for item in preserved.items {
            try effects.createDirectory(item.source.deletingLastPathComponent(), true)
            try removeIfPresent(item.source)
            try effects.moveItem(item.destination, item.source)
            log("restored preserved=\(item.source.path)")
        }
        try removeIfPresent(preserved.root)
    }

    private func removeInstalledFiles(clean: Bool) throws {
        try safeRemove(paths.managerApp)
        try safeRemove(paths.productRoot)
        if clean, let externalVitalFilesDirectory = paths.externalVitalFilesDirectory {
            try safeRemove(externalVitalFilesDirectory)
        } else if clean, let readFailure = paths.configuredVitalFilesDirectoryReadFailure {
            log("skipping external vital files directory cleanup because configured path is unavailable reason=\(readFailure)")
        }
    }

    private func safeRemove(_ target: URL) throws {
        guard target.path != "/" else {
            throw RuntimeWorkflowError.operationFailed("refusing unsafe removal target=/")
        }
        guard exists(target) else {
            return
        }
        do {
            try effects.removeItem(target)
        } catch {
            logRemovalDiagnostics(target)
            throw error
        }
        if exists(target) {
            logRemovalDiagnostics(target)
            throw RuntimeWorkflowError.operationFailed("removal incomplete target=\(target.path)")
        }
    }

    private func logRemovalDiagnostics(_ target: URL) {
        log("removal diagnostic target=\(target.path)")
        do {
            let items = try diagnostics.contentsOfDirectory(target)
            for item in items.prefix(200) {
                log("removal diagnostic residual path=\(item.path)")
            }
        } catch {
            log("removal diagnostic contents read failed target=\(target.path) error=\(error.localizedDescription)")
        }
        let result = diagnostics.runProcess("/usr/sbin/lsof", ["+D", target.path])
        if result.exitCode == 0 {
            for line in result.stdout.split(separator: "\n").prefix(200) {
                log("removal diagnostic open file \(line)")
            }
        }
        if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log("removal diagnostic lsof stderr=\(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        guard exists(url) else {
            return
        }
        try effects.removeItem(url)
    }

    private func exists(_ url: URL) -> Bool {
        readers.fileExists(url) || readers.directoryExists(url)
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
            throw RuntimeWorkflowError.operationFailed(
                "runtime stop state blocked blockers=\(decision.blockers.joined(separator: ","))"
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
            throw RuntimeWorkflowError.operationFailed(
                "runtime cleanup artifacts remain blockers=\(decision.blockers.joined(separator: ","))"
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
        let decision = try RuntimeUninstallTransitionPolicy.transition(
            from: state,
            event: event
        )
        try requireCommands(expectedCommands, in: decision)
        try writePersistedState(decision, clean: clean)
        return decision
    }

    private func transition(
        from state: RuntimeUninstallWorkflowState,
        event: RuntimeUninstallWorkflowEvent,
        expectedCommandsWhenAllowed: [RuntimeUninstallWorkflowCommand]
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try RuntimeUninstallTransitionPolicy.transition(
            from: state,
            event: event
        )
        try requireCommands(
            decision.blockers.isEmpty ? expectedCommandsWhenAllowed : [],
            in: decision
        )
        return decision
    }

    private func requireCommands(
        _ expectedCommands: [RuntimeUninstallWorkflowCommand],
        in decision: RuntimeUninstallTransitionDecision
    ) throws {
        guard decision.commands == expectedCommands else {
            throw RuntimeWorkflowError.operationFailed(
                "unexpected uninstall workflow commands state=\(decision.state) expected=\(expectedCommands) actual=\(decision.commands)"
            )
        }
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

    private func processFailureReason(_ result: RuntimeProcessResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return "exitCode=\(result.exitCode) stderr=\(stderr)"
        }
        if !stdout.isEmpty {
            return "exitCode=\(result.exitCode) stdout=\(stdout)"
        }
        return "exitCode=\(result.exitCode)"
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
