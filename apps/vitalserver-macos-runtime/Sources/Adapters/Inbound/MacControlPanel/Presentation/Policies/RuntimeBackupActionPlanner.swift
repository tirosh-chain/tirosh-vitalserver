import Foundation
import Contracts
import Errors

public struct RuntimeBackupActionPlan: Equatable {
    public let backupURL: URL

    public init(backupURL: URL) {
        self.backupURL = backupURL
    }
}

public enum RuntimeBackupActionPlanFailure: Error, Equatable {
    case missingBackup
    case backupsRootNotReported
    case invalidBackup
}

public struct RuntimeBackupActionPlanner {
    public var backupSelectionPolicy: RuntimeBackupSelectionPolicy

    public init(backupSelectionPolicy: RuntimeBackupSelectionPolicy = RuntimeBackupSelectionPolicy()) {
        self.backupSelectionPolicy = backupSelectionPolicy
    }

    public func rollbackPlan(
        selectedBackupPath: String?
    ) -> Result<RuntimeBackupActionPlan, RuntimeBackupActionPlanFailure> {
        guard let selectedBackupPath else {
            return .failure(.missingBackup)
        }
        return .success(RuntimeBackupActionPlan(
            backupURL: URL(fileURLWithPath: selectedBackupPath)
        ))
    }

    public func deletePlan(
        selectedBackupPath: String?,
        backupsPath: String?
    ) -> Result<RuntimeBackupActionPlan, RuntimeBackupActionPlanFailure> {
        deleteUpdateBackupPlan(
            selectedBackupPath: selectedBackupPath,
            backupsPath: backupsPath
        )
    }

    public func deleteUpdateBackupPlan(
        selectedBackupPath: String?,
        backupsPath: String?
    ) -> Result<RuntimeBackupActionPlan, RuntimeBackupActionPlanFailure> {
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
        return .success(RuntimeBackupActionPlan(backupURL: backupURL))
    }

    public func deleteRuntimeDataBackupPlan(
        selectedBackupPath: String?,
        runtimeDataBackupsPath: String?
    ) -> Result<RuntimeBackupActionPlan, RuntimeBackupActionPlanFailure> {
        guard let selectedBackupPath else {
            return .failure(.missingBackup)
        }
        guard let runtimeDataBackupsPath else {
            return .failure(.backupsRootNotReported)
        }
        let backupURL = URL(fileURLWithPath: selectedBackupPath)
        guard RuntimeManagedBackupPolicy.isRuntimeDataBackupURL(
            backupURL,
            runtimeDataBackupsRoot: URL(fileURLWithPath: runtimeDataBackupsPath)
        ) else {
            return .failure(.invalidBackup)
        }
        return .success(RuntimeBackupActionPlan(backupURL: backupURL))
    }
}

extension RuntimeBackupActionPlanFailure {
    var message: String {
        switch self {
        case .missingBackup:
            return AppConstants.StatusText.missingBackup
        case .backupsRootNotReported:
            return AppConstants.StatusText.notReported
        case .invalidBackup:
            return AppConstants.StatusText.invalidBackup
        }
    }
}
