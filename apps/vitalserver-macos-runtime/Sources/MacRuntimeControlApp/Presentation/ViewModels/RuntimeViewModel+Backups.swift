import Foundation
import RuntimeControl

@MainActor
extension RuntimeViewModel {
    func openBackups() {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let backupsPath = installationInfo.backupsPath else {
            message = AppConstants.StatusText.notReported
            return
        }
        openFolder(backupsPath)
    }

    func openRedisBackups() {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let redisBackupsPath = installationInfo.redisBackupsPath else {
            message = AppConstants.StatusText.notReported
            return
        }
        openFolder(redisBackupsPath)
    }

    func createRedisBackup() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        isCreatingRedisBackup = true
        defer {
            isCreatingRedisBackup = false
        }
        let didCreateBackup = await runClientAction(
            preparingMessage: AppConstants.StatusText.redisBackupPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.redisBackupRunning,
            successMessage: AppConstants.StatusText.redisBackupCompleted,
            refreshCommandLog: false,
            action: { try await self.controlClient.createRedisBackup() }
        )
        if didCreateBackup {
            await refresh()
            await refreshHealthStatus()
        }
    }

    var selectedBackup: RuntimeBackup? {
        guard let selectedBackupPath else {
            return nil
        }
        return backups.first { $0.path == selectedBackupPath }
    }

    func rollbackRuntime() async {
        guard controlClient.capabilities.canRollback else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        let plan: RuntimeViewModelBackupActionPlan
        switch RuntimeViewModelBackupActionPlanner().rollbackPlan(selectedBackupPath: selectedBackupPath) {
        case .success(let actionPlan):
            plan = actionPlan
        case .failure(let failure):
            message = failure.message
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.rollbackPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.rollbackRunning,
            successMessage: AppConstants.StatusText.rollbackCompleted,
            action: { try await self.hostClient.rollbackRuntime(backupURL: plan.backupURL) }
        )
        await refresh()
        await refreshHealthStatus()
    }

    func deleteSelectedBackup() async {
        guard controlClient.capabilities.canRollback else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        let plan: RuntimeViewModelBackupActionPlan
        switch RuntimeViewModelBackupActionPlanner().deletePlan(
            selectedBackupPath: selectedBackupPath,
            backupsPath: installationInfo.backupsPath
        ) {
        case .success(let actionPlan):
            plan = actionPlan
        case .failure(let failure):
            message = failure.message
            return
        }
        let didDelete = await runClientAction(
            preparingMessage: AppConstants.StatusText.backupDeletePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.backupDeleteRunning,
            successMessage: AppConstants.StatusText.backupDeleted,
            action: { try await self.hostClient.deleteBackup(url: plan.backupURL) }
        )
        if didDelete {
            self.selectedBackupPath = nil
            await refresh()
        }
    }
}
