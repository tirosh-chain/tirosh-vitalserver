import Foundation
import RuntimeControl
import Core
import Contracts
import HostInfrastructure

extension RuntimeBackup {
    static func loadAll(
        latestBackupPath: String? = nil,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore()
    ) -> [RuntimeBackup] {
        let directory = URL(fileURLWithPath: RuntimeAdapterConstants.Paths.backups)
        let discovered = ((try? fileStore.childDirectories(
            at: directory,
            nameContains: "-before-",
            skipsHiddenFiles: true
        )) ?? [])
        .map { RuntimeBackup(path: $0.path, sizeBytes: directorySize($0, fileStore: fileStore)) }

        let merged = discovered + latestBackup(latestBackupPath, excluding: discovered, fileStore: fileStore)
        return merged.sorted { $0.name > $1.name }
    }

    private static func latestBackup(
        _ path: String?,
        excluding backups: [RuntimeBackup],
        fileStore: RuntimeFileStore
    ) -> [RuntimeBackup] {
        guard let path, !path.isEmpty else {
            return []
        }
        let url = URL(fileURLWithPath: path)
        guard !backups.contains(where: { $0.path == path }) else {
            return []
        }
        guard url.lastPathComponent.contains("-before-") else {
            return []
        }
        return [RuntimeBackup(path: path, sizeBytes: directorySize(url, fileStore: fileStore))]
    }

    private static func directorySize(_ url: URL, fileStore: RuntimeFileStore) -> UInt64? {
        try? fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
    }
}
