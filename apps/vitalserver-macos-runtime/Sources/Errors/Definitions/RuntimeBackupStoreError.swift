import Foundation

public enum RuntimeBackupStoreError: Error, Equatable, CustomStringConvertible {
    case noBackupsAvailable

    public var description: String {
        switch self {
        case .noBackupsAvailable:
            return "no backups available"
        }
    }
}
