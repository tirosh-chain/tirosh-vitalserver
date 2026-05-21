import Foundation
import RuntimeCore
import RuntimeInfrastructure

struct RuntimeBackup: Identifiable, Hashable {
    let path: String
    let sizeBytes: UInt64?

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var sizeText: String {
        guard let sizeBytes else {
            return AppConstants.StatusText.unknown
        }
        return Self.formatBytes(sizeBytes)
    }

    static func loadAll(
        latestBackupPath: String? = nil,
        fileStore: RuntimeFileStore = LocalRuntimeFileStore()
    ) -> [RuntimeBackup] {
        let directory = URL(fileURLWithPath: AppConstants.Paths.backups)
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
        guard !backups.contains(where: { $0.path == path }) else {
            return []
        }
        let url = URL(fileURLWithPath: path)
        guard url.lastPathComponent.contains("-before-") else {
            return []
        }
        return [RuntimeBackup(path: path, sizeBytes: directorySize(url, fileStore: fileStore))]
    }

    private static func directorySize(_ url: URL, fileStore: RuntimeFileStore) -> UInt64? {
        try? fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}
