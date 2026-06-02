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

public struct RuntimeUninstallWorkflow {
    public var paths: RuntimeUninstallPaths
    public var createRedisBackup: () throws -> Void
    public var stopRuntimeServices: () throws -> Void
    public var serviceStates: () -> [RuntimeManagedService: RuntimeServiceState]
    public var vmProcessState: () -> RuntimeVMProcessState
    public var fileExists: (URL) -> Bool
    public var directoryExists: (URL) -> Bool
    public var createDirectory: (URL, Bool) throws -> Void
    public var removeItem: (URL) throws -> Void
    public var moveItem: (URL, URL) throws -> Void
    public var contentsOfDirectory: (URL) throws -> [URL]
    public var runProcess: (String, [String]) -> RuntimeProcessResult
    public var packageReceiptIdentifiers: [String]
    public var forgetPackageReceipt: (String) -> RuntimeProcessResult
    public var packageReceiptStates: () -> [RuntimePackageReceiptState]
    public var cleanupArtifactStates: (Bool) -> [RuntimeInstallArtifactState]
    public var writeState: (RuntimeUninstallState, Bool, String?, [String]) throws -> Void
    public var log: (String) -> Void

    public init(
        paths: RuntimeUninstallPaths,
        createRedisBackup: @escaping () throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        serviceStates: @escaping () -> [RuntimeManagedService: RuntimeServiceState],
        vmProcessState: @escaping () -> RuntimeVMProcessState,
        fileExists: @escaping (URL) -> Bool,
        directoryExists: @escaping (URL) -> Bool,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removeItem: @escaping (URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        contentsOfDirectory: @escaping (URL) throws -> [URL],
        runProcess: @escaping (String, [String]) -> RuntimeProcessResult,
        packageReceiptIdentifiers: [String],
        forgetPackageReceipt: @escaping (String) -> RuntimeProcessResult,
        packageReceiptStates: @escaping () -> [RuntimePackageReceiptState],
        cleanupArtifactStates: @escaping (Bool) -> [RuntimeInstallArtifactState],
        writeState: @escaping (RuntimeUninstallState, Bool, String?, [String]) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.paths = paths
        self.createRedisBackup = createRedisBackup
        self.stopRuntimeServices = stopRuntimeServices
        self.serviceStates = serviceStates
        self.vmProcessState = vmProcessState
        self.fileExists = fileExists
        self.directoryExists = directoryExists
        self.createDirectory = createDirectory
        self.removeItem = removeItem
        self.moveItem = moveItem
        self.contentsOfDirectory = contentsOfDirectory
        self.runProcess = runProcess
        self.packageReceiptIdentifiers = packageReceiptIdentifiers
        self.forgetPackageReceipt = forgetPackageReceipt
        self.packageReceiptStates = packageReceiptStates
        self.cleanupArtifactStates = cleanupArtifactStates
        self.writeState = writeState
        self.log = log
    }

    public func run(_ command: RuntimeUninstallCommand) throws {
        log("uninstall started clean=\(command.clean)")
        let startDecision = try RuntimeUninstallTransitionPolicy.transition(
            from: .notStarted,
            event: .start(clean: command.clean)
        )
        try writePersistedState(startDecision, clean: command.clean)
        var workflowState = startDecision.state
        if let readFailure = paths.configuredVitalFilesDirectoryReadFailure {
            log("configured vital files directory unavailable reason=\(readFailure)")
        }
        if !command.clean {
            log("step=create-redis-backup status=started")
            let backupRequestDecision = try RuntimeUninstallTransitionPolicy.transition(
                from: workflowState,
                event: .redisBackupRequested
            )
            try writePersistedState(backupRequestDecision, clean: command.clean)
            workflowState = backupRequestDecision.state
            do {
                try createRedisBackup()
                log("step=create-redis-backup status=completed")
                let backupCompletedDecision = try RuntimeUninstallTransitionPolicy.transition(
                    from: workflowState,
                    event: .redisBackupSucceeded
                )
                try writePersistedState(backupCompletedDecision, clean: command.clean)
                workflowState = backupCompletedDecision.state
            } catch {
                log("standard uninstall aborted because Redis backup did not complete error=\(error.localizedDescription)")
                let decision = try RuntimeUninstallTransitionPolicy.transition(
                    from: workflowState,
                    event: .redisBackupFailed(reason: error.localizedDescription)
                )
                try writePersistedState(decision, clean: command.clean)
                throw error
            }
        }

        log("step=stop-launchd-services status=started")
        let stopRequestDecision = try RuntimeUninstallTransitionPolicy.transition(
            from: workflowState,
            event: .stopServicesRequested
        )
        try writePersistedState(stopRequestDecision, clean: command.clean)
        workflowState = stopRequestDecision.state
        do {
            try stopRuntimeServices()
        } catch {
            let decision = try RuntimeUninstallTransitionPolicy.transition(
                from: workflowState,
                event: .stopServicesFailed(
                    input: runtimeStopReadinessInput(),
                    commandFailureReason: error.localizedDescription
                )
            )
            try writePersistedState(decision, clean: command.clean)
            throw error
        }
        log("step=stop-launchd-services status=completed")
        let stoppedDecision = try assertRuntimeStoppedBeforeRemovingFiles(clean: command.clean)

        log("step=remove-plists status=started")
        for plist in paths.launchDaemonPlists {
            try removeIfPresent(plist)
        }
        log("step=remove-plists status=completed")

        let preserved = command.clean ? nil : try preserveUserData()
        do {
            log("step=remove-installed-files status=started")
            let fileRemovalDecision = try RuntimeUninstallTransitionPolicy.transition(
                from: stoppedDecision.state,
                event: .filesRemovalStarted
            )
            try writePersistedState(fileRemovalDecision, clean: command.clean)
            try removeInstalledFiles(clean: command.clean)
            log("step=remove-installed-files status=completed")

            log("step=remove-runtime-tools status=started")
            for tool in paths.runtimeTools {
                try removeIfPresent(tool)
            }
            log("step=remove-runtime-tools status=completed")
            let cleanupDecision = try verifyCleanupArtifacts(clean: command.clean)

            if let preserved {
                log("step=restore-preserved-user-data status=started")
                try restorePreservedPaths(preserved)
                log("step=restore-preserved-user-data status=completed")
            }

            log("step=forget-package-receipt status=started")
            let receiptsStartDecision = try RuntimeUninstallTransitionPolicy.transition(
                from: cleanupDecision.state,
                event: .receiptsForgetStarted
            )
            try writePersistedState(receiptsStartDecision, clean: command.clean)
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
            try writeState(
                .filesRemovalBlocked,
                command.clean,
                "file removal blocked",
                blockers
            )
            throw error
        }

        for identifier in packageReceiptIdentifiers {
            log("forget package receipt identifier=\(identifier)")
            let result = forgetPackageReceipt(identifier)
            guard result.exitCode == 0 else {
                let reason = processFailureReason(result)
                let decision = try RuntimeUninstallTransitionPolicy.transition(
                    from: .receiptsForgetStarted,
                    event: .receiptForgetFailed(identifier: identifier, reason: reason)
                )
                try writePersistedState(decision, clean: command.clean)
                throw RuntimeWorkflowError.operationFailed(
                    "package receipt forget failed identifier=\(identifier) \(reason)"
                )
            }
        }
        let receiptDecision = try RuntimeUninstallTransitionPolicy.transition(
            from: .receiptsForgetStarted,
            event: .packageReceiptsObserved(packageReceiptStates())
        )
        guard receiptDecision.blockers.isEmpty else {
            try writePersistedState(receiptDecision, clean: command.clean)
            throw RuntimeWorkflowError.operationFailed(
                "package receipt forget verification failed blockers=\(receiptDecision.blockers.joined(separator: ","))"
            )
        }
        log("step=forget-package-receipt status=completed")
        log("uninstall completed")
        try writePersistedState(receiptDecision, clean: command.clean)
    }

    private func preserveUserData() throws -> RuntimeUninstallPreservedPaths {
        log("step=preserve-user-data status=started")
        let preserveRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tirosh-vitalserver-uninstall-\(UUID().uuidString)")
        try createDirectory(preserveRoot, true)

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
        try moveItem(source, destination)
        items.append(RuntimeUninstallPreservedPath(source: source, destination: destination))
        log("preserved source=\(source.path)")
    }

    private func restorePreservedPaths(_ preserved: RuntimeUninstallPreservedPaths) throws {
        for item in preserved.items {
            try createDirectory(item.source.deletingLastPathComponent(), true)
            try removeIfPresent(item.source)
            try moveItem(item.destination, item.source)
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
            try removeItem(target)
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
        if let items = try? contentsOfDirectory(target) {
            for item in items.prefix(200) {
                log("removal diagnostic residual path=\(item.path)")
            }
        }
        let result = runProcess("/usr/sbin/lsof", ["+D", target.path])
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
        try removeItem(url)
    }

    private func exists(_ url: URL) -> Bool {
        fileExists(url) || directoryExists(url)
    }

    private func runtimeStopReadinessInput() -> RuntimeUninstallReadinessInput {
        RuntimeUninstallReadinessInput(
            serviceStates: serviceStates(),
            vmProcessState: vmProcessState()
        )
    }

    private func assertRuntimeStoppedBeforeRemovingFiles(clean: Bool) throws -> RuntimeUninstallTransitionDecision {
        let decision = try RuntimeUninstallTransitionPolicy.transition(
            from: .stopServicesRequested,
            event: .stoppedStateObserved(runtimeStopReadinessInput())
        )
        guard decision.blockers.isEmpty else {
            try writePersistedState(decision, clean: clean)
            throw RuntimeWorkflowError.operationFailed(
                "runtime stop state blocked blockers=\(decision.blockers.joined(separator: ","))"
            )
        }
        return decision
    }

    private func verifyCleanupArtifacts(clean: Bool) throws -> RuntimeUninstallTransitionDecision {
        let decision = try RuntimeUninstallTransitionPolicy.transition(
            from: .filesRemovalStarted,
            event: .cleanupArtifactsObserved(cleanupArtifactStates(clean))
        )
        guard decision.blockers.isEmpty else {
            try writePersistedState(decision, clean: clean)
            throw RuntimeWorkflowError.operationFailed(
                "runtime cleanup artifacts remain blockers=\(decision.blockers.joined(separator: ","))"
            )
        }
        return decision
    }

    private func writePersistedState(
        _ decision: RuntimeUninstallTransitionDecision,
        clean: Bool
    ) throws {
        guard let state = decision.persistedState else {
            return
        }
        try writeState(state, clean, decision.message, decision.blockers)
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
