import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

extension RuntimeBackup {
    static func loadAll(
        latestBackupPath: String? = nil,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore()
    ) throws -> [RuntimeBackup] {
        let directory = InstalledRuntimePaths.defaultInstalled.backupsDirectory
        let discovered = try fileStore.childDirectories(
            at: directory,
            nameContains: RuntimeManagedBackupPolicy.nameFragment,
            skipsHiddenFiles: true
        )
        .map { RuntimeBackup(path: $0.path, sizeBytes: try directorySize($0, fileStore: fileStore)) }

        let latest = try latestBackup(
            latestBackupPath,
            backupsRoot: directory,
            excluding: discovered,
            fileStore: fileStore
        )
        let merged = discovered + latest
        return merged.sorted { $0.name > $1.name }
    }

    static func loadRedisBackups(fileStore: RuntimeFileStore = SystemRuntimeFileStore()) throws -> [RuntimeBackup] {
        let directory = InstalledRuntimePaths.defaultInstalled.redisBackupsDirectory
        let discovered = try fileStore.contentsOfDirectory(at: directory, skipsHiddenFiles: true)
            .filter { $0.lastPathComponent.hasPrefix("redis-") && $0.lastPathComponent.hasSuffix(".tar.gz") }
            .map { RuntimeBackup(path: $0.path, sizeBytes: try fileSize($0, fileStore: fileStore)) }
        return discovered.sorted { $0.name > $1.name }
    }

    static func loadRuntimeDataBackups(fileStore: RuntimeFileStore = SystemRuntimeFileStore()) throws -> [RuntimeBackup] {
        let directory = InstalledRuntimePaths.defaultInstalled.vitalServerHelperBackupsDirectory
        let directoryState = fileStore.pathState(at: directory)
        switch directoryState {
        case .directory:
            break
        case .missing:
            throw RuntimeBackupListError.unexpectedPathState(path: directory.path, state: directoryState.rawValue)
        case .inspectFailed(let reason):
            throw RuntimeBackupListError.pathInspectionFailed(path: directory.path, reason: reason)
        case .file, .other, .unknown:
            throw RuntimeBackupListError.unexpectedPathState(path: directory.path, state: directoryState.rawValue)
        }
        let discovered = try fileStore.contentsOfDirectory(at: directory, skipsHiddenFiles: true)
            .filter { try runtimeDataBackupEntryIsDirectory($0, fileStore: fileStore) }
            .map { RuntimeBackup(path: $0.path, sizeBytes: try directorySize($0, fileStore: fileStore)) }
        return discovered.sorted { $0.name > $1.name }
    }

    private static func runtimeDataBackupEntryIsDirectory(_ url: URL, fileStore: RuntimeFileStore) throws -> Bool {
        let state = fileStore.pathState(at: url)
        switch state {
        case .directory:
            return true
        case .file, .missing:
            return false
        case .inspectFailed(let reason):
            throw RuntimeBackupListError.pathInspectionFailed(path: url.path, reason: reason)
        case .other, .unknown:
            throw RuntimeBackupListError.unexpectedPathState(path: url.path, state: state.rawValue)
        }
    }

    private static func latestBackup(
        _ path: String?,
        backupsRoot: URL,
        excluding backups: [RuntimeBackup],
        fileStore: RuntimeFileStore
    ) throws -> [RuntimeBackup] {
        guard let path, !path.isEmpty else {
            return []
        }
        let url = URL(fileURLWithPath: path)
        guard !backups.contains(where: { $0.path == path }) else {
            return []
        }
        guard RuntimeManagedBackupPolicy.isManagedBackupURL(url, backupsRoot: backupsRoot) else {
            throw RuntimeBackupListError.invalidLatestBackupPath(path)
        }
        return [RuntimeBackup(path: path, sizeBytes: try directorySize(url, fileStore: fileStore))]
    }

    private static func directorySize(_ url: URL, fileStore: RuntimeFileStore) throws -> UInt64 {
        try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
    }

    private static func fileSize(_ url: URL, fileStore: RuntimeFileStore) throws -> UInt64 {
        try fileStore.fileSize(url)
    }
}
