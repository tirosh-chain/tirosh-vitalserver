import Foundation
import Management

@MainActor
extension RuntimeController {
    var selectedBackup: RuntimeBackup? {
        guard let selectedBackupURL else {
            return nil
        }
        return backups.first { $0.url == selectedBackupURL }
    }

    func rollbackRuntime() async {
        guard runtimeClient.capabilities.canRollback else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let backupURL = selectedBackupURL else {
            message = AppConstants.StatusText.missingBackup
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.rollbackPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.rollbackRunning,
            successMessage: AppConstants.StatusText.rollbackCompleted,
            action: { try await self.runtimeClient.rollbackRuntime(backupURL: backupURL) }
        )
        await refresh()
        await refreshHealthStatus()
    }

    func deleteSelectedBackup() async {
        guard runtimeClient.capabilities.canRollback else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let backupURL = selectedBackupURL else {
            message = AppConstants.StatusText.missingBackup
            return
        }
        guard backupSelectionPolicy.isManagedBackupURL(
            backupURL,
            backupsRoot: URL(fileURLWithPath: installationInfo.backupsPath)
        ) else {
            message = AppConstants.StatusText.invalidBackup
            return
        }
        let didDelete = await runClientAction(
            preparingMessage: AppConstants.StatusText.backupDeletePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.backupDeleteRunning,
            successMessage: AppConstants.StatusText.backupDeleted,
            action: { try await self.runtimeClient.deleteBackup(url: backupURL) }
        )
        if didDelete {
            selectedBackupURL = nil
            await refresh()
        }
    }
}
