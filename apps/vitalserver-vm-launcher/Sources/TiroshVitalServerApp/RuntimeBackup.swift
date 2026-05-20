import Foundation

struct RuntimeBackup: Identifiable, Hashable {
    let path: String

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }

    static func loadAll() -> [RuntimeBackup] {
        let directory = URL(fileURLWithPath: AppConstants.Paths.backups)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory == true && url.lastPathComponent.contains("-before-")
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { RuntimeBackup(path: $0.path) }
    }
}
