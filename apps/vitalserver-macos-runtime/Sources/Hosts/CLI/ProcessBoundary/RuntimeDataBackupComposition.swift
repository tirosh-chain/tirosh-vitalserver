import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import Workflow
import Errors

struct RuntimeDataBackupComposition {
    let lifecycle: RuntimeLifecycle

    func createBackup() throws -> URL {
        try createBackup(reason: "manual")
    }

    func createAutomaticBackup() throws -> String {
        let settings = try loadGuestRuntimeSettings()
        guard settings.automaticBackupEnabled else {
            lifecycle.log("automatic backup skipped because automaticBackupEnabled=false")
            return "automatic backup skipped: disabled"
        }
        guard RuntimeBackupSchedulePolicy.isValidRetentionCount(settings.backupRetentionCount) else {
            throw LauncherError.runtimeOperationFailed(
                "automatic backup retention is invalid value=\(settings.backupRetentionCount)"
            )
        }

        let operationID = UUID().uuidString
        let startedAt = lifecycle.isoTimestamp()
        let expiresAt = ISO8601DateFormatter().string(
            from: lifecycle.clock.now.addingTimeInterval(Constants.Runtime.runtimeOperationLeaseDurationSeconds)
        )
        let lease = RuntimeOperationLeaseDocument(
            operationId: operationID,
            operation: .automaticBackup,
            ownerPID: Int(ProcessInfo.processInfo.processIdentifier),
            startedAt: startedAt,
            heartbeatAt: startedAt,
            expiresAt: expiresAt,
            message: "automatic VitalServer Helper backup"
        )
        let leaseOwner = lifecycle.runtimeOperationLeaseOwner()
        do {
            try leaseOwner.acquire(lease)
        } catch RuntimeOperationLeaseOwnerError.existingOperation(_, let operation) {
            lifecycle.log("automatic backup skipped during active runtime operation operation=\(operation)")
            return "automatic backup skipped: active operation \(operation)"
        }
        defer {
            try? leaseOwner.release(operationId: operationID)
        }

        let backup = try createBackup(reason: "automatic")
        try pruneVitalServerHelperBackups(retentionCount: settings.backupRetentionCount)
        lifecycle.log("automatic backup completed backup=\(backup.path)")
        return "automatic backup completed: \(backup.path)"
    }

    func createBackup(reason: String) throws -> URL {
        let redisOperation = try lifecycle.createRedisBackupThroughGuestControl()
        guard let redisArchivePath = redisOperation.result?.archive?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !redisArchivePath.isEmpty else {
            throw LauncherError.runtimeOperationFailed("runtime data backup requires a redis archive")
        }
        let postgresOperation = try lifecycle.createPostgresBackupThroughGuestControl()
        guard let postgresArchivePath = postgresOperation.result?.archive?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !postgresArchivePath.isEmpty else {
            throw LauncherError.runtimeOperationFailed(
                "runtime data backup requires a PostgreSQL archive"
            )
        }
        let redisArchive = try hostSharedDataURL(
            forGuestArchivePath: redisArchivePath,
            label: "Redis backup"
        )
        let postgresArchive = try hostSharedDataURL(
            forGuestArchivePath: postgresArchivePath,
            label: "PostgreSQL backup"
        )
        let backup = try runtimeDataBackupStore().createBackup(
            reason: reason,
            redisArchive: redisArchive,
            postgresArchive: postgresArchive,
            startOnBootState: try startOnBootStateData()
        )
        try validateManifest(backup)
        return backup
    }

    private func loadGuestRuntimeSettings() throws -> GuestRuntimeSettingsDocument {
        let url = lifecycle.installedPaths.guestRuntimeSettings
        switch lifecycle.fileStore.pathState(at: url) {
        case .file:
            break
        case .missing:
            throw LauncherError.missingFile(url.path)
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "guest runtime settings path inspection failed path=\(url.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "guest runtime settings path state is unexpected path=\(url.path) state=\(lifecycle.fileStore.pathState(at: url).rawValue)"
            )
        }
        return try JSONDecoder().decode(GuestRuntimeSettingsDocument.self, from: lifecycle.fileStore.readData(url))
    }

    private func pruneVitalServerHelperBackups(retentionCount: Int) throws {
        guard RuntimeBackupSchedulePolicy.isValidRetentionCount(retentionCount) else {
            throw LauncherError.runtimeOperationFailed(
                "automatic backup retention is invalid value=\(retentionCount)"
            )
        }
        let root = lifecycle.installedPaths.vitalServerHelperBackupsDirectory
        guard case .directory = lifecycle.fileStore.pathState(at: root) else {
            return
        }
        let backups = try lifecycle.fileStore.contentsOfDirectory(at: root, skipsHiddenFiles: true)
            .filter { url in
                RuntimeManagedBackupPolicy.isRuntimeDataBackupURL(url, runtimeDataBackupsRoot: root)
                    && lifecycle.fileStore.pathState(at: url) == .directory
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let removeCount = backups.count - retentionCount
        guard removeCount > 0 else {
            return
        }
        for backup in backups.prefix(removeCount) {
            try lifecycle.fileStore.removeItem(at: backup)
            lifecycle.log("automatic backup retention removed backup=\(backup.path)")
        }
    }

    func restoreBackup(_ backup: URL) throws {
        let restore = try runtimeDataBackupStore().restoreBackup(backup)
        let stagedRedisArchive = try stageRedisArchiveForGuestRestore(restore.redisArchive)
        let stagedPostgresArchive = try stagePostgresArchiveForGuestRestore(
            restore.postgresArchive
        )
        defer {
            try? lifecycle.fileStore.removeItem(at: stagedRedisArchive.hostURL)
            try? lifecycle.fileStore.removeItem(at: stagedPostgresArchive.hostURL)
        }
        try restoreStartOnBootState(restore.startOnBootState)
        let postgresOperation = try lifecycle.restorePostgresBackupThroughGuestControl(
            guestArchivePath: stagedPostgresArchive.guestPath,
            restartRuntime: false
        )
        try requireRestoredArchiveResult(
            postgresOperation,
            label: "PostgreSQL",
            expectedRuntimeRestarted: false
        )
        let redisOperation = try lifecycle.restoreRedisBackupThroughGuestControl(
            guestArchivePath: stagedRedisArchive.guestPath
        )
        try requireRestoredArchiveResult(redisOperation, label: "Redis")
        lifecycle.log("runtime data backup restored backup=\(backup.path)")
    }

    func restoreRedisBackup(_ archive: URL) throws {
        let stagedRedisArchive = try stageRedisArchiveForGuestRestore(archive)
        defer {
            try? lifecycle.fileStore.removeItem(at: stagedRedisArchive.hostURL)
        }
        let operation = try lifecycle.restoreRedisBackupThroughGuestControl(
            guestArchivePath: stagedRedisArchive.guestPath
        )
        try requireRestoredArchiveResult(operation, label: "Redis")
        lifecycle.log("redis backup restored archive=\(archive.path)")
    }

    private func runtimeDataBackupStore() -> RuntimeDataBackupStore {
        RuntimeDataBackupStore(
            paths: RuntimeDataBackupStorePaths(
                backupsDirectory: lifecycle.installedPaths.backupsDirectory,
                runtimeHome: lifecycle.installedPaths.runtimeHome,
                runtimeVersion: lifecycle.runtimeVersion,
                vmConfig: lifecycle.installedPaths.vmConfig,
                guestRuntimeConfig: lifecycle.installedPaths.guestRuntimeConfig,
                guestRuntimeSettings: lifecycle.installedPaths.guestRuntimeSettings,
                proxyLaunchDaemon: lifecycle.installedPaths.proxyLaunchDaemon,
                runtimeStatus: lifecycle.installedPaths.runtimeStatus,
                runtimeEvents: lifecycle.installedPaths.runtimeEvents,
                runtimeObservabilityDatabase: lifecycle.installedPaths.runtimeObservabilityDB
            ),
            metadata: RuntimeDataBackupStoreMetadata(
                productIdentifier: Constants.Product.identifier,
                manifestName: RuntimePackageArtifactFileNames.backupManifest,
                redisVolumeName: "vitalserver_redis-data",
                postgresVolumeName: "vitalserver_postgres-data"
            ),
            timestamp: lifecycle.backupTimestamp,
            isoTimestamp: lifecycle.isoTimestamp,
            fileStore: lifecycle.fileStore
        )
    }

    func stageRedisArchiveForGuestRestore(_ archive: URL) throws -> (hostURL: URL, guestPath: String) {
        let fileName = "redis-restore-\(lifecycle.backupTimestamp()).tar.gz"
        let destination = lifecycle.installedPaths.redisBackupsDirectory.appendingPathComponent(fileName)
        try removeFileIfPresent(destination, label: "redis restore staging archive")
        try lifecycle.fileStore.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try lifecycle.fileStore.copyItem(at: archive, to: destination)
        let relative = destination.path.dropFirst(lifecycle.installedPaths.dataDirectory.path.count)
        return (destination, "/mnt/tirosh\(relative)")
    }

    func stagePostgresArchiveForGuestRestore(
        _ archive: URL
    ) throws -> (hostURL: URL, guestPath: String) {
        let fileName = "postgres-restore-\(lifecycle.backupTimestamp()).tar.gz"
        let destination = lifecycle.installedPaths.postgresBackupsDirectory
            .appendingPathComponent(fileName)
        try removeFileIfPresent(destination, label: "PostgreSQL restore staging archive")
        try lifecycle.fileStore.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try lifecycle.fileStore.copyItem(at: archive, to: destination)
        let relative = destination.path.dropFirst(
            lifecycle.installedPaths.dataDirectory.path.count
        )
        return (destination, "/mnt/tirosh\(relative)")
    }

    private func requireRestoredArchiveResult(
        _ operation: RuntimeGuestControlServiceOperation,
        label: String,
        expectedRuntimeRestarted: Bool? = nil
    ) throws {
        guard let restoredArchive = operation.result?.restoredArchive?.trimmingCharacters(in: .whitespacesAndNewlines),
              !restoredArchive.isEmpty else {
            throw LauncherError.runtimeOperationFailed(
                "runtime data restore requires a restored \(label) archive"
            )
        }
        if let expectedRuntimeRestarted,
           operation.result?.runtimeRestarted != expectedRuntimeRestarted {
            throw LauncherError.runtimeOperationFailed(
                "\(label) restore did not preserve the required runtime restart state"
            )
        }
    }

    private func hostSharedDataURL(
        forGuestArchivePath archive: String,
        label: String
    ) throws -> URL {
        let guestDataPrefix = "/mnt/tirosh/"
        guard archive.hasPrefix(guestDataPrefix) else {
            throw LauncherError.runtimeOperationFailed(
                "\(label) archive path is outside guest shared data mount archive=\(archive)"
            )
        }

        let relativePath = String(archive.dropFirst(guestDataPrefix.count))
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains("..") else {
            throw LauncherError.runtimeOperationFailed(
                "\(label) archive path is invalid archive=\(archive)"
            )
        }

        return components.reduce(lifecycle.installedPaths.dataDirectory) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private func restoreStartOnBootState(_ document: RuntimeDataBackupStartOnBootStateDocument) throws {
        for service in document.services {
            let action = service.disabled ? "disable" : "enable"
            try lifecycle.runRequired(
                Constants.Commands.launchctl,
                arguments: [action, "system/\(service.label)"]
            )
        }
    }

    private func removeFileIfPresent(_ url: URL, label: String) throws {
        switch lifecycle.fileStore.pathState(at: url) {
        case .file:
            try lifecycle.fileStore.removeItem(at: url)
        case .missing:
            return
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed("\(label) inspection failed path=\(url.path) reason=\(reason)")
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "\(label) path state is unexpected path=\(url.path) state=\(lifecycle.fileStore.pathState(at: url).rawValue)"
            )
        }
    }

    private func startOnBootStateData() throws -> Data {
        let result = lifecycle.runProcess(
            Constants.Commands.launchctl,
            arguments: ["print-disabled", "system"]
        )
        guard result.exitCode == 0 else {
            throw LauncherError.runtimeOperationFailed(
                result.stderr.isEmpty ? "launchctl print-disabled failed" : result.stderr
            )
        }
        let document = RuntimeDataBackupStartOnBootStateDocument(
            schemaVersion: 1,
            capturedAt: lifecycle.isoTimestamp(),
            services: RuntimeManagedService.startOrder.map { service in
                RuntimeDataBackupStartOnBootServiceState(
                    label: service.label,
                    disabled: result.stdout.contains("\"\(service.label)\" => true")
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private func validateManifest(_ backup: URL) throws {
        let manifestURL = backup.appendingPathComponent(RuntimePackageArtifactFileNames.backupManifest)
        let manifestData = try lifecycle.fileStore.readData(manifestURL)
        let manifest = try JSONDecoder().decode(RuntimeDataBackupManifest.self, from: manifestData)
        switch RuntimeDataBackupPolicy.validateCompletedBackup(manifest, expectedProduct: Constants.Product.identifier) {
        case .valid:
            return
        case .invalid(let errors):
            throw LauncherError.runtimeOperationFailed(
                "runtime data backup manifest is invalid: \(errors.joined(separator: "; "))"
            )
        }
    }
}

extension RuntimeLifecycle {
    func runtimeDataBackupComposition() -> RuntimeDataBackupComposition {
        RuntimeDataBackupComposition(lifecycle: self)
    }
}
