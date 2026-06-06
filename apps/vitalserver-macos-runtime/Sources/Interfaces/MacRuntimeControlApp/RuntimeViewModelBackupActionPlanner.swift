import Foundation

public struct RuntimeViewModelBackupActionPlan: Equatable {
    public let backupURL: URL

    public init(backupURL: URL) {
        self.backupURL = backupURL
    }
}

public enum RuntimeViewModelBackupActionPlanFailure: Error, Equatable {
    case missingBackup
    case backupsRootNotReported
    case invalidBackup
}

public struct RuntimeViewModelBackupActionPlanner {
    public var backupSelectionPolicy: RuntimeBackupSelectionPolicy

    public init(backupSelectionPolicy: RuntimeBackupSelectionPolicy = RuntimeBackupSelectionPolicy()) {
        self.backupSelectionPolicy = backupSelectionPolicy
    }

    public func rollbackPlan(
        selectedBackupPath: String?
    ) -> Result<RuntimeViewModelBackupActionPlan, RuntimeViewModelBackupActionPlanFailure> {
        guard let selectedBackupPath else {
            return .failure(.missingBackup)
        }
        return .success(RuntimeViewModelBackupActionPlan(
            backupURL: URL(fileURLWithPath: selectedBackupPath)
        ))
    }

    public func deletePlan(
        selectedBackupPath: String?,
        backupsPath: String?
    ) -> Result<RuntimeViewModelBackupActionPlan, RuntimeViewModelBackupActionPlanFailure> {
        guard let selectedBackupPath else {
            return .failure(.missingBackup)
        }
        guard let backupsPath else {
            return .failure(.backupsRootNotReported)
        }
        let backupURL = URL(fileURLWithPath: selectedBackupPath)
        guard backupSelectionPolicy.isManagedBackupURL(
            backupURL,
            backupsRoot: URL(fileURLWithPath: backupsPath)
        ) else {
            return .failure(.invalidBackup)
        }
        return .success(RuntimeViewModelBackupActionPlan(backupURL: backupURL))
    }
}
