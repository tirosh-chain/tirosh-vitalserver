import Foundation
import RuntimeControl

@MainActor
extension RuntimeViewModel {
    var selectedBackup: RuntimeBackup? {
        guard !selectedBackupPath.isEmpty else {
            return nil
        }
        return backups.first { $0.path == selectedBackupPath }
    }

    func rollbackRuntime() async {
        guard controlClient.capabilities.canRollback else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard !selectedBackupPath.isEmpty else {
            message = AppConstants.StatusText.missingBackup
            return
        }
        let backupURL = URL(fileURLWithPath: selectedBackupPath)
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.rollbackPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.rollbackRunning,
            successMessage: AppConstants.StatusText.rollbackCompleted,
            action: { try await self.hostClient.rollbackRuntime(backupURL: backupURL) }
        )
        await refresh()
        await refreshHealthStatus()
    }

    func deleteSelectedBackup() async {
        guard controlClient.capabilities.canRollback else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard !selectedBackupPath.isEmpty else {
            message = AppConstants.StatusText.missingBackup
            return
        }
        let backupURL = URL(fileURLWithPath: selectedBackupPath)
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
            action: { try await self.hostClient.deleteBackup(url: backupURL) }
        )
        if didDelete {
            selectedBackupPath = ""
            await refresh()
        }
    }
}
