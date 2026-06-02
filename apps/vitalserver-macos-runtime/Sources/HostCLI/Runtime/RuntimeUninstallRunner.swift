import Foundation
import Core
import Contracts
import HostInfrastructure

struct RuntimeUninstallCommand: Equatable {
    let clean: Bool
}

struct RuntimeConfiguredExternalVitalFilesDirectoryRead: Equatable {
    let externalDirectory: URL?
    let failure: String?
}

struct RuntimeUninstallPaths {
    let productRoot: URL
    let managerApp: URL
    let defaultVitalFilesDirectory: URL
    let externalVitalFilesDirectory: URL?
    let configuredVitalFilesDirectoryReadFailure: String?
    let launchDaemonPlists: [URL]
    let runtimeTools: [URL]
}

struct RuntimeUninstallRunner {
    var paths: RuntimeUninstallPaths
    var createRedisBackup: () throws -> Void
    var stopRuntimeServices: () throws -> Void
    var serviceStates: () -> [RuntimeManagedService: RuntimeServiceState]
    var vmProcessState: () -> RuntimeVMProcessState
    var fileExists: (URL) -> Bool
    var directoryExists: (URL) -> Bool
    var createDirectory: (URL, Bool) throws -> Void
    var removeItem: (URL) throws -> Void
    var moveItem: (URL, URL) throws -> Void
    var contentsOfDirectory: (URL) throws -> [URL]
    var runProcess: (String, [String]) -> RuntimeProcessResult
    var packageReceiptIdentifiers: [String]
    var forgetPackageReceipt: (String) -> RuntimeProcessResult
    var packageReceiptStates: () -> [RuntimePackageReceiptState]
    var cleanupArtifactStates: (Bool) -> [RuntimeInstallArtifactState]
    var writeState: (RuntimeUninstallState, Bool, String?, [String]) throws -> Void
    var log: (String) -> Void

    func run(_ command: RuntimeUninstallCommand) throws {
        log("uninstall started clean=\(command.clean)")
        try writeState(.started, command.clean, "uninstall started", [])
        if let readFailure = paths.configuredVitalFilesDirectoryReadFailure {
            log("configured vital files directory unavailable reason=\(readFailure)")
        }
        if !command.clean {
            log("step=create-redis-backup status=started")
            try writeState(.redisBackupRequested, command.clean, "redis backup requested", [])
            do {
                try createRedisBackup()
                log("step=create-redis-backup status=completed")
                try writeState(.redisBackupCompleted, command.clean, "redis backup completed", [])
            } catch {
                log("standard uninstall aborted because Redis backup did not complete error=\(error.localizedDescription)")
                try writeState(
                    .failed,
                    command.clean,
                    "redis backup failed",
                    ["redis-backup-failed:reason=\(error.localizedDescription)"]
                )
                throw error
            }
        }

        log("step=stop-launchd-services status=started")
        try writeState(.stopServicesRequested, command.clean, "service stop requested", [])
        do {
            try stopRuntimeServices()
        } catch {
            let blockers = stopBlockers(fallback: error)
            try writeState(.serviceStopBlocked, command.clean, "service stop blocked", blockers)
            throw error
        }
        log("step=stop-launchd-services status=completed")
        try assertRuntimeStoppedBeforeRemovingFiles(clean: command.clean)

        log("step=remove-plists status=started")
        for plist in paths.launchDaemonPlists {
            try removeIfPresent(plist)
        }
        log("step=remove-plists status=completed")

        let preserved = command.clean ? nil : try preserveUserData()
        do {
            log("step=remove-installed-files status=started")
            try writeState(.filesRemovalStarted, command.clean, "file removal started", [])
            try removeInstalledFiles(clean: command.clean)
            log("step=remove-installed-files status=completed")

            log("step=remove-runtime-tools status=started")
            for tool in paths.runtimeTools {
                try removeIfPresent(tool)
            }
            log("step=remove-runtime-tools status=completed")
            try verifyCleanupArtifacts(clean: command.clean)

            if let preserved {
                log("step=restore-preserved-user-data status=started")
                try restorePreservedPaths(preserved)
                log("step=restore-preserved-user-data status=completed")
            }
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

        log("step=forget-package-receipt status=started")
        try writeState(.receiptsForgetStarted, command.clean, "package receipt forget started", [])
        for identifier in packageReceiptIdentifiers {
            log("forget package receipt identifier=\(identifier)")
            let result = forgetPackageReceipt(identifier)
            guard result.exitCode == 0 else {
                let reason = processFailureReason(result)
                let blockers = RuntimeUninstallReadinessPolicy.packageReceiptBlockers([
                    .forgetFailed(identifier: identifier, reason: reason),
                ])
                try writeState(.receiptsForgetBlocked, command.clean, "package receipt forget blocked", blockers)
                throw LauncherError.runtimeOperationFailed(
                    "package receipt forget failed identifier=\(identifier) \(reason)"
                )
            }
        }
        let receiptBlockers = RuntimeUninstallReadinessPolicy.packageReceiptBlockers(packageReceiptStates())
        guard receiptBlockers.isEmpty else {
            try writeState(.receiptsForgetBlocked, command.clean, "package receipt forget blocked", receiptBlockers)
            throw LauncherError.runtimeOperationFailed(
                "package receipt forget verification failed blockers=\(receiptBlockers.joined(separator: ","))"
            )
        }
        log("step=forget-package-receipt status=completed")
        log("uninstall completed")
        try writeState(.completed, command.clean, "uninstall completed", [])
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
            throw LauncherError.runtimeOperationFailed("refusing unsafe removal target=/")
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
            throw LauncherError.runtimeOperationFailed("removal incomplete target=\(target.path)")
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

    private func stopBlockers(fallback error: Error) -> [String] {
        let blockers = RuntimeUninstallReadinessPolicy.blockers(input: RuntimeUninstallReadinessInput(
            serviceStates: serviceStates(),
            vmProcessState: vmProcessState()
        ))
        if blockers.isEmpty {
            return ["stop-runtime-services-failed:reason=\(error.localizedDescription)"]
        }
        return blockers
    }

    private func assertRuntimeStoppedBeforeRemovingFiles(clean: Bool) throws {
        let blockers = RuntimeUninstallReadinessPolicy.blockers(input: RuntimeUninstallReadinessInput(
            serviceStates: serviceStates(),
            vmProcessState: vmProcessState()
        ))
        guard blockers.isEmpty else {
            try writeState(.serviceStopBlocked, clean, "runtime stop state blocked", blockers)
            throw LauncherError.runtimeOperationFailed(
                "runtime stop state blocked blockers=\(blockers.joined(separator: ","))"
            )
        }
    }

    private func verifyCleanupArtifacts(clean: Bool) throws {
        let blockers = RuntimeUninstallReadinessPolicy.cleanupArtifactBlockers(cleanupArtifactStates(clean))
        guard blockers.isEmpty else {
            try writeState(.filesRemovalBlocked, clean, "file removal blocked", blockers)
            throw LauncherError.runtimeOperationFailed(
                "runtime cleanup artifacts remain blockers=\(blockers.joined(separator: ","))"
            )
        }
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
