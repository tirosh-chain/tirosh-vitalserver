import Foundation

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

    static func loadAll(latestBackupPath: String? = nil) -> [RuntimeBackup] {
        let directory = URL(fileURLWithPath: AppConstants.Paths.backups)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let discovered = contents
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory == true && url.lastPathComponent.contains("-before-")
            }
            .map { RuntimeBackup(path: $0.path, sizeBytes: directorySize($0)) }

        let merged = discovered + latestBackup(latestBackupPath, excluding: discovered)
        return merged.sorted { $0.name > $1.name }
    }

    private static func latestBackup(_ path: String?, excluding backups: [RuntimeBackup]) -> [RuntimeBackup] {
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
        return [RuntimeBackup(path: path, sizeBytes: directorySize(url))]
    }

    private static func directorySize(_ url: URL) -> UInt64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += UInt64(values.fileSize ?? 0)
        }
        return total
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
