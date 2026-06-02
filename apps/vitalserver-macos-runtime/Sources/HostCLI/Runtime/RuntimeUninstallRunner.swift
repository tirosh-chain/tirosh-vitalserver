import Foundation
import Core
import Contracts
import HostInfrastructure

struct RuntimeUninstallCommand: Equatable {
    let clean: Bool
}

struct RuntimeUninstallPaths {
    let productRoot: URL
    let managerApp: URL
    let defaultVitalFilesDirectory: URL
    let configuredVitalFilesDirectory: URL
    let launchDaemonPlists: [URL]
    let runtimeTools: [URL]

    var vitalFilesDirectory: URL {
        configuredVitalFilesDirectory
    }

    var usesDefaultVitalFilesDirectory: Bool {
        configuredVitalFilesDirectory.path == defaultVitalFilesDirectory.path
    }
}

struct RuntimeUninstallRunner {
    var paths: RuntimeUninstallPaths
    var createRedisBackup: () throws -> Void
    var stopRuntimeServices: () throws -> Void
    var fileExists: (URL) -> Bool
    var directoryExists: (URL) -> Bool
    var createDirectory: (URL, Bool) throws -> Void
    var removeItem: (URL) throws -> Void
    var moveItem: (URL, URL) throws -> Void
    var contentsOfDirectory: (URL) throws -> [URL]
    var runProcess: (String, [String]) -> RuntimeProcessResult
    var packageReceiptIdentifiers: [String]
    var forgetPackageReceipt: (String) -> Void
    var log: (String) -> Void

    func run(_ command: RuntimeUninstallCommand) throws {
        log("uninstall started clean=\(command.clean)")
        if !command.clean {
            log("step=create-redis-backup status=started")
            do {
                try createRedisBackup()
                log("step=create-redis-backup status=completed")
            } catch {
                log("standard uninstall aborted because Redis backup did not complete error=\(error.localizedDescription)")
                throw error
            }
        }

        log("step=stop-launchd-services status=started")
        try stopRuntimeServices()
        log("step=stop-launchd-services status=completed")

        log("step=remove-plists status=started")
        for plist in paths.launchDaemonPlists {
            try removeIfPresent(plist)
        }
        log("step=remove-plists status=completed")

        let preserved = command.clean ? nil : try preserveUserData()
        do {
            log("step=remove-installed-files status=started")
            try removeInstalledFiles(clean: command.clean)
            log("step=remove-installed-files status=completed")

            log("step=remove-runtime-tools status=started")
            for tool in paths.runtimeTools {
                try removeIfPresent(tool)
            }
            log("step=remove-runtime-tools status=completed")

            if let preserved {
                log("step=restore-preserved-user-data status=started")
                try restorePreservedPaths(preserved)
                log("step=restore-preserved-user-data status=completed")
            }
        } catch {
            if let preserved {
                log("restoring preserved user data after uninstall failure")
                try? restorePreservedPaths(preserved)
            }
            throw error
        }

        log("step=forget-package-receipt status=started")
        for identifier in packageReceiptIdentifiers {
            log("forget package receipt identifier=\(identifier)")
            forgetPackageReceipt(identifier)
        }
        log("step=forget-package-receipt status=completed")
        log("uninstall completed")
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
        if paths.usesDefaultVitalFilesDirectory {
            try preservePath(paths.defaultVitalFilesDirectory, preserveRoot, "vital-files", into: &items)
        } else {
            log("preserved external vital files directory=\(paths.vitalFilesDirectory.path)")
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
        if clean, !paths.usesDefaultVitalFilesDirectory {
            try safeRemove(paths.vitalFilesDirectory)
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
}

private struct RuntimeUninstallPreservedPaths {
    let root: URL
    let items: [RuntimeUninstallPreservedPath]
}

private struct RuntimeUninstallPreservedPath {
    let source: URL
    let destination: URL
}
