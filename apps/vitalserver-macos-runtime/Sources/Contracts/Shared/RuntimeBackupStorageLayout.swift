import Foundation

public enum RuntimeBackupStorageLayout {
    public static let rootDirectoryName = "backups"
    public static let vitalServerHelperDirectoryName = "vitalserver-helper"
    public static let redisOnlyDirectoryName = "redis-only"
    public static let updateRollbackDirectoryName = "update-rollback"
    public static let vmDiskRepairDirectoryName = "vm-disk-repair"

    public static func vitalServerHelperBackupsDirectory(under backupsDirectory: URL) -> URL {
        backupsDirectory.appendingPathComponent(vitalServerHelperDirectoryName)
    }

    public static func redisOnlyBackupsDirectory(under backupsDirectory: URL) -> URL {
        backupsDirectory.appendingPathComponent(redisOnlyDirectoryName)
    }

    public static func updateRollbackBackupsDirectory(under backupsDirectory: URL) -> URL {
        backupsDirectory.appendingPathComponent(updateRollbackDirectoryName)
    }

    public static func vmDiskRepairBackupsDirectory(under backupsDirectory: URL) -> URL {
        backupsDirectory.appendingPathComponent(vmDiskRepairDirectoryName)
    }
}
