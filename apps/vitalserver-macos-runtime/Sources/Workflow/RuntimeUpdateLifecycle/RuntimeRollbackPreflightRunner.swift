import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeRollbackPreflightRunner {
    public var resolveBackupSelection: (RollbackRuntimeBackupSelection) throws -> URL
    public var resolveBackupDirectory: (URL) -> RollbackRuntimeBackupDirectoryDecision
    public var resolveBackupRootfs: (RollbackRuntimeBackupPlan) -> RollbackRuntimeBackupRootfsDecision
    public var loadManifest: (URL) throws -> BackupManifest
    public var serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    public var log: (String) -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        resolveBackupSelection: @escaping (RollbackRuntimeBackupSelection) throws -> URL,
        resolveBackupDirectory: @escaping (URL) -> RollbackRuntimeBackupDirectoryDecision,
        resolveBackupRootfs: @escaping (RollbackRuntimeBackupPlan) -> RollbackRuntimeBackupRootfsDecision,
        loadManifest: @escaping (URL) throws -> BackupManifest,
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy,
        log: @escaping (String) -> Void
    ) {
        self.resolveBackupSelection = resolveBackupSelection
        self.resolveBackupDirectory = resolveBackupDirectory
        self.resolveBackupRootfs = resolveBackupRootfs
        self.loadManifest = loadManifest
        self.serviceRestartPolicy = serviceRestartPolicy
        self.log = log
    }

    public func prepare(_ command: RuntimeRollbackCommand) throws -> RollbackPreflightContext {
        let backup = try resolveBackupSelection(useCase.rollbackBackupSelection(command: command))

        switch resolveBackupDirectory(backup) {
        case .loadManifest:
            break
        case .failed(let message):
            throw RuntimeRollbackWorkflowError.operationFailed(message)
        }

        let manifest = try loadManifest(backup)
        let backupPlan = useCase.rollbackBackupPlan(backup: backup, manifest: manifest)
        let resolvedBackupPlan: RollbackRuntimeBackupPlan
        switch resolveBackupRootfs(backupPlan) {
        case .proceed(let plan):
            resolvedBackupPlan = plan
        case .failed(let message):
            throw RuntimeRollbackWorkflowError.operationFailed(message)
        }

        let restartPolicy = serviceRestartPolicy()
        let preflightPlan = useCase.rollbackPreflightPlan(backup: backup, restartPolicy: restartPolicy)
        log(preflightPlan.serviceRestartLogMessage)

        return RollbackPreflightContext(
            backup: resolvedBackupPlan.backup,
            backupRootfs: resolvedBackupPlan.backupRootfs,
            backupVersion: resolvedBackupPlan.backupVersion,
            restoresRootfsBase: resolvedBackupPlan.restoresRootfsBase,
            restartPolicy: restartPolicy
        )
    }

}
