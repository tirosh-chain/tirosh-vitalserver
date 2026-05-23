import Foundation
import RuntimeControl

struct RuntimeBackupSelectionPolicy {
    func selectedBackupURL(from backups: [RuntimeBackup], currentSelection: URL?) -> URL? {
        let backupURLs = Set(backups.map(\.url))
        if let currentSelection, backupURLs.contains(currentSelection) {
            return currentSelection
        }
        return backups.first?.url
    }

    func isManagedBackupURL(_ url: URL, backupsRoot: URL) -> Bool {
        let backupURL = url.standardizedFileURL
        let backupsRootURL = backupsRoot.standardizedFileURL
        guard backupURL.lastPathComponent.contains("-before-") else {
            return false
        }
        return backupURL.path.hasPrefix(backupsRootURL.path + "/")
    }
}
