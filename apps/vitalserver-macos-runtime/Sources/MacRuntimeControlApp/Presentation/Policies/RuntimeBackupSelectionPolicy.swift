import Foundation
import RuntimeControl

struct RuntimeBackupSelectionPolicy {
    func selectedBackupPath(from backups: [RuntimeBackup], currentSelection: String) -> String {
        let backupPaths = Set(backups.map(\.path))
        if !currentSelection.isEmpty, backupPaths.contains(currentSelection) {
            return currentSelection
        }
        return backups.first?.path ?? ""
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
