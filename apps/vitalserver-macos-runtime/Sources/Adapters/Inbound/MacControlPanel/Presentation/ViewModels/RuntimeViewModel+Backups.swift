import Foundation
import RuntimeControl
import Errors

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

    func openRuntimeDataBackups() {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let runtimeDataBackupsPath = installationInfo.runtimeDataBackupsPath else {
            message = AppConstants.StatusText.notReported
            return
        }
        openFolder(runtimeDataBackupsPath)
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
        ).isSuccess
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

    var selectedRuntimeDataBackup: RuntimeBackup? {
        guard let selectedRuntimeDataBackupPath else {
            return nil
        }
        return runtimeDataBackups.first { $0.path == selectedRuntimeDataBackupPath }
    }

    func createRuntimeDataBackup() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        isCreatingRuntimeDataBackup = true
        defer {
            isCreatingRuntimeDataBackup = false
        }
        let didCreateBackup = await runClientAction(
            preparingMessage: AppConstants.StatusText.runtimeDataBackupPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.runtimeDataBackupRunning,
            successMessage: AppConstants.StatusText.runtimeDataBackupCompleted,
            action: { try await self.hostClient.createRuntimeDataBackup() }
        ).isSuccess
        if didCreateBackup {
            await refresh()
            await refreshHealthStatus()
        }
    }

    func restoreRuntimeDataBackup() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        let plan: RuntimeBackupActionPlan
        switch RuntimeBackupActionPlanner().rollbackPlan(selectedBackupPath: selectedRuntimeDataBackupPath) {
        case .success(let actionPlan):
            plan = actionPlan
        case .failure(let failure):
            message = failure.message
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.runtimeDataRestorePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.runtimeDataRestoreRunning,
            successMessage: AppConstants.StatusText.runtimeDataRestoreCompleted,
            action: { try await self.hostClient.restoreRuntimeDataBackup(backupURL: plan.backupURL) }
        )
        await refresh()
        await refreshHealthStatus()
    }

    func rollbackRuntime() async {
        guard controlClient.capabilities.canRollback else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        let plan: RuntimeBackupActionPlan
        switch RuntimeBackupActionPlanner().rollbackPlan(selectedBackupPath: selectedBackupPath) {
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
        let plan: RuntimeBackupActionPlan
        switch RuntimeBackupActionPlanner().deletePlan(
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
        ).isSuccess
        if didDelete {
            self.selectedBackupPath = nil
            await refresh()
        }
    }

    func deleteSelectedRuntimeDataBackup() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        let plan: RuntimeBackupActionPlan
        switch RuntimeBackupActionPlanner().deleteRuntimeDataBackupPlan(
            selectedBackupPath: selectedRuntimeDataBackupPath,
            runtimeDataBackupsPath: installationInfo.runtimeDataBackupsPath
        ) {
        case .success(let actionPlan):
            plan = actionPlan
        case .failure(let failure):
            message = failure.message
            return
        }
        let didDelete = await runClientAction(
            preparingMessage: AppConstants.StatusText.runtimeDataBackupDeletePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.runtimeDataBackupDeleteRunning,
            successMessage: AppConstants.StatusText.runtimeDataBackupDeleted,
            action: { try await self.hostClient.deleteBackup(url: plan.backupURL) }
        ).isSuccess
        if didDelete {
            self.selectedRuntimeDataBackupPath = nil
            await refresh()
        }
    }
}
