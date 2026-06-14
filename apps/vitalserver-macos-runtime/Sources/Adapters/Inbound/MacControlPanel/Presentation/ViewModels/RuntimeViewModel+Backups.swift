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

    var selectedRedisBackup: RuntimeBackup? {
        guard let selectedRedisBackupPath else {
            return nil
        }
        return redisBackups.first { $0.path == selectedRedisBackupPath }
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

    func importRedisBackup() async {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let redisBackupsPath = installationInfo.redisBackupsPath else {
            message = AppConstants.StatusText.notReported
            return
        }
        guard let sourceURL = nativeShell.chooseRedisBackupArchive(prompt: AppConstants.Actions.importBackups) else {
            return
        }

        let redisBackupsRoot = URL(fileURLWithPath: redisBackupsPath, isDirectory: true)
        if !ensureRedisBackupImportRootExists(redisBackupsRoot) {
            return
        }

        let destinationURL = redisBackupsRoot.appendingPathComponent(sourceURL.lastPathComponent)
        let plan: RuntimeBackupImportPlan
        switch RuntimeBackupActionPlanner().importRedisBackupPlan(
            sourceBackupURL: sourceURL,
            redisBackupsRoot: redisBackupsRoot,
            sourcePathState: nativeShell.pathState(sourceURL),
            destinationPathState: nativeShell.pathState(destinationURL)
        ) {
        case .success(let importPlan):
            plan = importPlan
        case .failure(let failure):
            message = failure.message
            return
        }

        do {
            isBusy = true
            isImportingRedisBackup = true
            message = AppConstants.StatusText.redisBackupImportPreparing
            operationDetail = AppConstants.StatusText.redisBackupImportPreparing
            defer {
                isBusy = false
                isImportingRedisBackup = false
                operationDetail = ""
            }
            await Task.yield()
            message = AppConstants.StatusText.redisBackupImportRunning
            operationDetail = AppConstants.StatusText.redisBackupImportRunning
            try nativeShell.copyFile(plan.sourceURL, to: plan.destinationURL)
            selectedRedisBackupPath = plan.destinationURL.path
            message = AppConstants.StatusText.redisBackupImported
            operationDetail = AppConstants.StatusText.redisBackupImported
            await refresh()
        } catch {
            message = AppConstants.StatusText.redisBackupImportFailed(error.localizedDescription)
            operationDetail = message
        }
    }

    func importRuntimeDataBackup() async {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let runtimeDataBackupsPath = installationInfo.runtimeDataBackupsPath else {
            message = AppConstants.StatusText.notReported
            return
        }
        guard let sourceURL = nativeShell.chooseDirectory(prompt: AppConstants.Actions.importBackups) else {
            return
        }

        let runtimeDataBackupsRoot = URL(fileURLWithPath: runtimeDataBackupsPath, isDirectory: true)
        if !ensureRuntimeDataBackupImportRootExists(runtimeDataBackupsRoot) {
            return
        }

        let destinationURL = runtimeDataBackupsRoot.appendingPathComponent(
            sourceURL.lastPathComponent,
            isDirectory: true
        )
        let plan: RuntimeBackupImportPlan
        switch RuntimeBackupActionPlanner().importRuntimeDataBackupPlan(
            sourceBackupURL: sourceURL,
            runtimeDataBackupsRoot: runtimeDataBackupsRoot,
            sourcePathState: nativeShell.pathState(sourceURL),
            destinationPathState: nativeShell.pathState(destinationURL)
        ) {
        case .success(let importPlan):
            plan = importPlan
        case .failure(let failure):
            message = failure.message
            return
        }

        do {
            isBusy = true
            isImportingRuntimeDataBackup = true
            message = AppConstants.StatusText.runtimeDataBackupImportPreparing
            operationDetail = AppConstants.StatusText.runtimeDataBackupImportPreparing
            defer {
                isBusy = false
                isImportingRuntimeDataBackup = false
                operationDetail = ""
            }
            await Task.yield()
            message = AppConstants.StatusText.runtimeDataBackupImportRunning
            operationDetail = AppConstants.StatusText.runtimeDataBackupImportRunning
            try nativeShell.copyDirectory(plan.sourceURL, to: plan.destinationURL)
            selectedRuntimeDataBackupPath = plan.destinationURL.path
            message = AppConstants.StatusText.runtimeDataBackupImported
            operationDetail = AppConstants.StatusText.runtimeDataBackupImported
            await refresh()
        } catch {
            message = AppConstants.StatusText.runtimeDataBackupImportFailed(error.localizedDescription)
            operationDetail = message
        }
    }

    func restoreRedisBackup() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        let plan: RuntimeBackupActionPlan
        switch RuntimeBackupActionPlanner().restoreRedisBackupPlan(
            selectedBackupPath: selectedRedisBackupPath,
            redisBackupsPath: installationInfo.redisBackupsPath
        ) {
        case .success(let actionPlan):
            plan = actionPlan
        case .failure(let failure):
            message = failure.message
            return
        }
        isRestoringRedisBackup = true
        defer {
            isRestoringRedisBackup = false
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.redisRestorePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.redisRestoreRunning,
            successMessage: AppConstants.StatusText.redisRestoreCompleted,
            action: { try await self.hostClient.restoreRedisBackup(backupURL: plan.backupURL) }
        )
        await refresh()
        await refreshHealthStatus()
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
        isRestoringRuntimeDataBackup = true
        defer {
            isRestoringRuntimeDataBackup = false
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
        isRollingBackRuntime = true
        defer {
            isRollingBackRuntime = false
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

    private func ensureRuntimeDataBackupImportRootExists(_ root: URL) -> Bool {
        let state = nativeShell.pathState(root)
        switch state {
        case .directory:
            return true
        case .missing:
            do {
                try nativeShell.createDirectory(root)
                return true
            } catch {
                message = AppConstants.StatusText.folderCreateFailed(error.localizedDescription)
                return false
            }
        case .file, .other, .unknown:
            message = AppConstants.StatusText.runtimeDataBackupImportPathInvalid(state.rawValue)
            return false
        case .inspectFailed(let reason):
            message = AppConstants.StatusText.runtimeDataBackupImportFailed(reason)
            return false
        }
    }

    private func ensureRedisBackupImportRootExists(_ root: URL) -> Bool {
        let state = nativeShell.pathState(root)
        switch state {
        case .directory:
            return true
        case .missing:
            do {
                try nativeShell.createDirectory(root)
                return true
            } catch {
                message = AppConstants.StatusText.folderCreateFailed(error.localizedDescription)
                return false
            }
        case .file, .other, .unknown:
            message = AppConstants.StatusText.redisBackupImportPathInvalid(state.rawValue)
            return false
        case .inspectFailed(let reason):
            message = AppConstants.StatusText.redisBackupImportFailed(reason)
            return false
        }
    }
}
