import Contracts
import Foundation

public struct RollbackPreflightContext: Equatable, Sendable {
    public let backup: URL
    public let backupRootfs: URL?
    public let backupVersion: URL
    public let restoresRootfsBase: Bool
    public let restartPolicy: RuntimeServiceRestartPolicy

    public init(
        backup: URL,
        backupRootfs: URL?,
        backupVersion: URL,
        restoresRootfsBase: Bool,
        restartPolicy: RuntimeServiceRestartPolicy
    ) {
        self.backup = backup
        self.backupRootfs = backupRootfs
        self.backupVersion = backupVersion
        self.restoresRootfsBase = restoresRootfsBase
        self.restartPolicy = restartPolicy
    }
}
