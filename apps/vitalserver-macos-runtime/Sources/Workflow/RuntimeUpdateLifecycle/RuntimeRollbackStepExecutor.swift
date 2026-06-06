import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeRollbackStepExecutor {
    public var stopRuntimeServices: () throws -> Void
    public var replaceFile: (URL, URL) throws -> Void
    public var fileExists: (URL) -> Bool
    public var writeRuntimeVersion: (String, URL) throws -> Void
    public var restoreBackupPathIfExists: (URL, URL) throws -> Void
    public var restoreRuntimeToolsIfExists: (URL) throws -> Void
    public var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        stopRuntimeServices: @escaping () throws -> Void,
        replaceFile: @escaping (URL, URL) throws -> Void,
        fileExists: @escaping (URL) -> Bool,
        writeRuntimeVersion: @escaping (String, URL) throws -> Void,
        restoreBackupPathIfExists: @escaping (URL, URL) throws -> Void,
        restoreRuntimeToolsIfExists: @escaping (URL) throws -> Void,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void
    ) {
        self.stopRuntimeServices = stopRuntimeServices
        self.replaceFile = replaceFile
        self.fileExists = fileExists
        self.writeRuntimeVersion = writeRuntimeVersion
        self.restoreBackupPathIfExists = restoreBackupPathIfExists
        self.restoreRuntimeToolsIfExists = restoreRuntimeToolsIfExists
        self.startRuntimeServices = startRuntimeServices
        self.waitForHealth = waitForHealth
    }

    public func execute(
        _ step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext,
        rootfsBase: URL,
        runtimeVersion: URL,
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL
    ) throws {
        let backupVersionExists: Bool
        switch useCase.rollbackStepRequiredInput(step: step, preflight: preflight) {
        case .none:
            backupVersionExists = false
        case .backupVersionExists(let backupVersion):
            backupVersionExists = fileExists(backupVersion)
        }
        let executionPlan = useCase.rollbackStepExecutionPlan(
            step: step,
            preflight: preflight,
            rootfsBase: rootfsBase,
            runtimeVersion: runtimeVersion,
            managerAppPath: managerAppPath,
            nginxDirectory: nginxDirectory,
            deployDirectory: deployDirectory,
            backupVersionExists: backupVersionExists
        )

        switch executionPlan {
        case .stopRuntimeServices:
            try stopRuntimeServices()
        case .restoreRootfsBase(let source, let destination):
            try replaceFile(source, destination)
        case .restoreRuntimeVersion(let decision):
            switch decision {
            case .restoreBackupVersion(let source, let destination):
                try replaceFile(source, destination)
            case .writeExplicitRollbackMarker(let version, let destinationDirectory):
                try writeRuntimeVersion(version, destinationDirectory)
            }
        case .restoreUpdateArtifacts(let restorePlan):
            for artifact in restorePlan.directoryRestores {
                try restoreBackupPathIfExists(
                    artifact.backupPath,
                    artifact.restoreDestination
                )
            }
            try restoreRuntimeToolsIfExists(
                restorePlan.runtimeToolsBackup
            )
        case .startRuntimeServices(let restartPolicy):
            try startRuntimeServices(restartPolicy)
        case .waitRuntimeHealth(let restartPolicy):
            try waitForHealth(restartPolicy)
        case .failed(let failureMessage), .unsupported(let failureMessage):
            throw RuntimeRollbackWorkflowError.operationFailed(failureMessage)
        }
    }
}
