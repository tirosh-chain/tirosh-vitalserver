import Foundation

public enum RuntimeManagedBackupPolicy {
    public static let nameFragment = "-before-"

    public static func isManagedBackupURL(_ url: URL, backupsRoot: URL) -> Bool {
        let backupURL = url.standardizedFileURL
        let backupsRootURL = backupsRoot.standardizedFileURL
        guard backupURL.lastPathComponent.contains(nameFragment) else {
            return false
        }
        return backupURL.path.hasPrefix(backupsRootURL.path + "/")
    }
}
