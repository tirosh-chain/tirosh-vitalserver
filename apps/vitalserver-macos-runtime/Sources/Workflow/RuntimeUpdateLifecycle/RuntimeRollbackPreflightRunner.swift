import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeRollbackPreflightRunner {
    public var requireLatestBackup: () throws -> URL
    public var directoryExists: (URL) -> Bool
    public var fileExists: (URL) -> Bool
    public var loadManifest: (URL) throws -> BackupManifest
    public var serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    public var log: (String) -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        requireLatestBackup: @escaping () throws -> URL,
        directoryExists: @escaping (URL) -> Bool,
        fileExists: @escaping (URL) -> Bool,
        loadManifest: @escaping (URL) throws -> BackupManifest,
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy,
        log: @escaping (String) -> Void
    ) {
        self.requireLatestBackup = requireLatestBackup
        self.directoryExists = directoryExists
        self.fileExists = fileExists
        self.loadManifest = loadManifest
        self.serviceRestartPolicy = serviceRestartPolicy
        self.log = log
    }

    public func prepare(_ command: RuntimeRollbackCommand) throws -> RollbackPreflightContext {
        let backup = try backupURL(for: command)

        switch useCase.rollbackBackupDirectoryDecision(backup: backup, directoryExists: directoryExists(backup)) {
        case .loadManifest:
            break
        case .failed(let message):
            throw RuntimeRollbackWorkflowError.operationFailed(message)
        }

        let manifest = try loadManifest(backup)
        let backupPlan = useCase.rollbackBackupPlan(backup: backup, manifest: manifest)
        let backupRootfsExists: Bool?
        switch useCase.rollbackBackupRootfsObservationRequirement(backupPlan: backupPlan) {
        case .none:
            backupRootfsExists = nil
        case .fileExists(let backupRootfs):
            backupRootfsExists = fileExists(backupRootfs)
        }
        let resolvedBackupPlan: RollbackRuntimeBackupPlan
        switch useCase.rollbackBackupRootfsDecision(
            backupPlan: backupPlan,
            backupRootfsExists: backupRootfsExists
        ) {
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

    private func backupURL(for command: RuntimeRollbackCommand) throws -> URL {
        switch useCase.rollbackBackupSelection(command: command) {
        case .latestBackup:
            return try requireLatestBackup()
        case .specificBackup(let url):
            return url
        }
    }
}
