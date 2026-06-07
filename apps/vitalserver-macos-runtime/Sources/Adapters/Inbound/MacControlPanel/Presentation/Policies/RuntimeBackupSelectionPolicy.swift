import Foundation
import Contracts
import RuntimeControl
import Errors

public struct RuntimeBackupSelectionPolicy {
    public init() {}

    public func selectedBackupPath(from backups: [RuntimeBackup], currentSelection: String?) -> String? {
        let backupPaths = Set(backups.map(\.path))
        if let currentSelection, backupPaths.contains(currentSelection) {
            return currentSelection
        }
        return backups.first?.path
    }

    public func isManagedBackupURL(_ url: URL, backupsRoot: URL) -> Bool {
        RuntimeManagedBackupPolicy.isManagedBackupURL(url, backupsRoot: backupsRoot)
    }
}
