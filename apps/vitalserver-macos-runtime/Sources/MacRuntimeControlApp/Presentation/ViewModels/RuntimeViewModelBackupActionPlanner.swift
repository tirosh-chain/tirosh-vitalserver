import Foundation

struct RuntimeViewModelBackupActionPlan: Equatable {
    let backupURL: URL
}

enum RuntimeViewModelBackupActionPlanFailure: Error, Equatable {
    case missingBackup
    case backupsRootNotReported
    case invalidBackup

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

struct RuntimeViewModelBackupActionPlanner {
    var backupSelectionPolicy = RuntimeBackupSelectionPolicy()

    func rollbackPlan(selectedBackupPath: String?) -> Result<RuntimeViewModelBackupActionPlan, RuntimeViewModelBackupActionPlanFailure> {
        guard let selectedBackupPath else {
            return .failure(.missingBackup)
        }
        return .success(RuntimeViewModelBackupActionPlan(
            backupURL: URL(fileURLWithPath: selectedBackupPath)
        ))
    }

    func deletePlan(
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
