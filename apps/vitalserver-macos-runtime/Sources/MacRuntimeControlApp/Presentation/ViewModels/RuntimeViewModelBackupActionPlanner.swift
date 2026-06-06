import Interfaces

typealias RuntimeViewModelBackupActionPlan = Interfaces.RuntimeViewModelBackupActionPlan
typealias RuntimeViewModelBackupActionPlanFailure = Interfaces.RuntimeViewModelBackupActionPlanFailure
typealias RuntimeViewModelBackupActionPlanner = Interfaces.RuntimeViewModelBackupActionPlanner

extension RuntimeViewModelBackupActionPlanFailure {
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
