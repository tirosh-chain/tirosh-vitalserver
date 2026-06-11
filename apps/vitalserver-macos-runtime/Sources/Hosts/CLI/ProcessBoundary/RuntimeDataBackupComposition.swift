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
        let redisBackup = try redisBackupCompositionWithoutStatusMutation().createBackup()
        guard let archive = redisBackup.archive, !archive.isEmpty else {
            throw LauncherError.runtimeOperationFailed("runtime data backup requires a redis archive")
        }
        let redisArchive = try hostSharedDataURL(forGuestArchivePath: archive)
        let backup = try runtimeDataBackupStore().createBackup(
            reason: "manual",
            redisArchive: redisArchive,
            startOnBootState: try startOnBootStateData()
        )
        try validateManifest(backup)
        return backup
    }

    func restoreBackup(_ backup: URL) throws {
        let restore = try runtimeDataBackupStore().restoreBackup(backup)
        let stagedRedisArchive = try stageRedisArchiveForGuestRestore(restore.redisArchive)
        defer {
            try? lifecycle.fileStore.removeItem(at: stagedRedisArchive.hostURL)
        }
        try restoreStartOnBootState(restore.startOnBootState)
        try restoreRedisArchive(stagedRedisArchive.guestPath)
        lifecycle.log("runtime data backup restored backup=\(backup.path)")
    }

    func restoreRedisBackup(_ archive: URL) throws {
        let stagedRedisArchive = try stageRedisArchiveForGuestRestore(archive)
        defer {
            try? lifecycle.fileStore.removeItem(at: stagedRedisArchive.hostURL)
        }
        try restoreRedisArchive(stagedRedisArchive.guestPath)
        lifecycle.log("redis backup restored archive=\(archive.path)")
    }

    private func redisBackupCompositionWithoutStatusMutation() -> RuntimeRedisBackupComposition {
        RuntimeRedisBackupComposition(
            context: RuntimeRedisBackupCompositionContext(
                guestRunDirectory: lifecycle.guestRunDirectory,
                redisBackupsDirectory: lifecycle.installedPaths.redisBackupsDirectory
            ),
            operations: RuntimeRedisBackupCompositionOperations(
                fileStore: lifecycle.fileStore,
                requireCapability: {
                    try lifecycle.requireGuestCapability(.redisBackup)
                },
                writeRuntimeStatus: { _, _, _ in },
                requestID: {
                    UUID().uuidString
                },
                timestamp: lifecycle.isoTimestamp,
                isVMServiceLoaded: {
                    lifecycle.isLaunchdLoaded(.vm)
                },
                startVMService: {
                    try lifecycle.startVMServiceForGuestOperation()
                },
                sleep: { seconds in
                    lifecycle.sleeper.sleep(forTimeInterval: seconds)
                },
                log: lifecycle.log
            )
        )
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
                manifestName: RuntimeFileNames.backupManifest,
                redisVolumeName: "vitalserver_redis-data"
            ),
            timestamp: lifecycle.backupTimestamp,
            isoTimestamp: lifecycle.isoTimestamp,
            fileStore: lifecycle.fileStore
        )
    }

    private func stageRedisArchiveForGuestRestore(_ archive: URL) throws -> (hostURL: URL, guestPath: String) {
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

    private func restoreRedisArchive(_ guestArchivePath: String) throws {
        try lifecycle.requireGuestCapability(.redisRestore)
        try lifecycle.guestGateway.removeRedisRestoreResult()
        let requestID = UUID().uuidString
        try lifecycle.guestGateway.writeRedisRestoreRequest(RedisRestoreRequestDocument(
            requestId: requestID,
            requestedAt: lifecycle.isoTimestamp(),
            archive: guestArchivePath
        ))
        if !lifecycle.isLaunchdLoaded(.vm) {
            try lifecycle.startVMServiceForGuestOperation()
        }
        try waitForRedisRestoreResult(requestID: requestID)
    }

    private func hostSharedDataURL(forGuestArchivePath archive: String) throws -> URL {
        let guestDataPrefix = "/mnt/tirosh/"
        guard archive.hasPrefix(guestDataPrefix) else {
            throw LauncherError.runtimeOperationFailed(
                "redis backup archive path is outside guest shared data mount archive=\(archive)"
            )
        }

        let relativePath = String(archive.dropFirst(guestDataPrefix.count))
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains("..") else {
            throw LauncherError.runtimeOperationFailed(
                "redis backup archive path is invalid archive=\(archive)"
            )
        }

        return components.reduce(lifecycle.installedPaths.dataDirectory) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private func waitForRedisRestoreResult(requestID: String) throws {
        let pollInterval = 3.0
        let attempts = Int(ceil(Constants.Runtime.redisBackupWaitTimeoutSeconds / pollInterval))
        for attempt in 0..<attempts {
            switch lifecycle.guestGateway.loadRedisRestoreResultDocument() {
            case .loaded(let result):
                if let resultRequestID = result.requestId, resultRequestID != requestID {
                    throw LauncherError.runtimeOperationFailed("stale redis restore result ignored")
                }
                if result.status == .completed {
                    lifecycle.log(result.message ?? "redis restore completed")
                    return
                }
                if result.status == .failed {
                    throw LauncherError.runtimeOperationFailed(result.message ?? "redis restore failed")
                }
            case .missing:
                break
            case .failed(let message):
                throw LauncherError.runtimeOperationFailed("failed to read redis restore result: \(message)")
            }
            if attempt < attempts - 1 {
                lifecycle.sleeper.sleep(forTimeInterval: pollInterval)
            }
        }
        throw LauncherError.runtimeOperationFailed("redis restore timed out")
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
        let manifestURL = backup.appendingPathComponent(RuntimeFileNames.backupManifest)
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
