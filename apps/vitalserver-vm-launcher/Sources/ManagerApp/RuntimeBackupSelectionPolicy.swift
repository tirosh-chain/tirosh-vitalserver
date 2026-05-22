import Foundation

struct RuntimeBackupSelectionPolicy {
    func selectedBackupURL(from backups: [RuntimeBackup], currentSelection: URL?) -> URL? {
        let backupURLs = Set(backups.map(\.url))
        if let currentSelection, backupURLs.contains(currentSelection) {
            return currentSelection
        }
        return backups.first?.url
    }

    func isManagedBackupURL(_ url: URL, backupsRoot: URL = URL(fileURLWithPath: AppConstants.Paths.backups)) -> Bool {
        let backupURL = url.standardizedFileURL
        let backupsRootURL = backupsRoot.standardizedFileURL
        guard backupURL.lastPathComponent.contains("-before-") else {
            return false
        }
        return backupURL.path.hasPrefix(backupsRootURL.path + "/")
    }
}
