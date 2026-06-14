import Foundation
import Contracts
import Errors

public struct RuntimeBackupActionPlan: Equatable {
    public let backupURL: URL

    public init(backupURL: URL) {
        self.backupURL = backupURL
    }
}

public struct RuntimeBackupImportPlan: Equatable {
    public let sourceURL: URL
    public let destinationURL: URL

    public init(sourceURL: URL, destinationURL: URL) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
    }
}

public enum RuntimeBackupActionPlanFailure: Error, Equatable {
    case missingBackup
    case backupsRootNotReported
    case invalidBackup
}

public enum RuntimeBackupImportPlanFailure: Error, Equatable {
    case missingBackup
    case backupsRootNotReported
    case sourceIsNotDirectory
    case sourcePathInspectionFailed(String)
    case sourcePathUnavailable(String)
    case invalidBackup
    case destinationAlreadyExists
    case destinationPathInspectionFailed(String)
    case destinationPathUnavailable(String)
}

public enum RuntimeRedisBackupImportPlanFailure: Error, Equatable {
    case missingBackup
    case backupsRootNotReported
    case sourceIsNotFile
    case sourcePathInspectionFailed(String)
    case sourcePathUnavailable(String)
    case invalidBackup
    case destinationAlreadyExists
    case destinationPathInspectionFailed(String)
    case destinationPathUnavailable(String)
}

public struct RuntimeBackupActionPlanner {
    public var backupSelectionPolicy: RuntimeBackupSelectionPolicy

    public init(backupSelectionPolicy: RuntimeBackupSelectionPolicy = RuntimeBackupSelectionPolicy()) {
        self.backupSelectionPolicy = backupSelectionPolicy
    }

    public func rollbackPlan(
        selectedBackupPath: String?
    ) -> Result<RuntimeBackupActionPlan, RuntimeBackupActionPlanFailure> {
        guard let selectedBackupPath else {
            return .failure(.missingBackup)
        }
        return .success(RuntimeBackupActionPlan(
            backupURL: URL(fileURLWithPath: selectedBackupPath)
        ))
    }

    public func deletePlan(
        selectedBackupPath: String?,
        backupsPath: String?
    ) -> Result<RuntimeBackupActionPlan, RuntimeBackupActionPlanFailure> {
        deleteUpdateBackupPlan(
            selectedBackupPath: selectedBackupPath,
            backupsPath: backupsPath
        )
    }

    public func deleteUpdateBackupPlan(
        selectedBackupPath: String?,
        backupsPath: String?
    ) -> Result<RuntimeBackupActionPlan, RuntimeBackupActionPlanFailure> {
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
        return .success(RuntimeBackupActionPlan(backupURL: backupURL))
    }

    public func deleteRuntimeDataBackupPlan(
        selectedBackupPath: String?,
        runtimeDataBackupsPath: String?
    ) -> Result<RuntimeBackupActionPlan, RuntimeBackupActionPlanFailure> {
        guard let selectedBackupPath else {
            return .failure(.missingBackup)
        }
        guard let runtimeDataBackupsPath else {
            return .failure(.backupsRootNotReported)
        }
        let backupURL = URL(fileURLWithPath: selectedBackupPath)
        guard RuntimeManagedBackupPolicy.isRuntimeDataBackupURL(
            backupURL,
            runtimeDataBackupsRoot: URL(fileURLWithPath: runtimeDataBackupsPath)
        ) else {
            return .failure(.invalidBackup)
        }
        return .success(RuntimeBackupActionPlan(backupURL: backupURL))
    }

    public func restoreRedisBackupPlan(
        selectedBackupPath: String?,
        redisBackupsPath: String?
    ) -> Result<RuntimeBackupActionPlan, RuntimeBackupActionPlanFailure> {
        guard let selectedBackupPath else {
            return .failure(.missingBackup)
        }
        guard let redisBackupsPath else {
            return .failure(.backupsRootNotReported)
        }
        let backupURL = URL(fileURLWithPath: selectedBackupPath)
        guard isRedisBackupURL(
            backupURL,
            redisBackupsRoot: URL(fileURLWithPath: redisBackupsPath)
        ) else {
            return .failure(.invalidBackup)
        }
        return .success(RuntimeBackupActionPlan(backupURL: backupURL))
    }

    public func importRuntimeDataBackupPlan(
        sourceBackupURL: URL?,
        runtimeDataBackupsRoot: URL?,
        sourcePathState: RuntimePathState,
        destinationPathState: RuntimePathState
    ) -> Result<RuntimeBackupImportPlan, RuntimeBackupImportPlanFailure> {
        guard let sourceBackupURL else {
            return .failure(.missingBackup)
        }
        guard let runtimeDataBackupsRoot else {
            return .failure(.backupsRootNotReported)
        }
        switch sourcePathState {
        case .directory:
            break
        case .file, .other:
            return .failure(.sourceIsNotDirectory)
        case .missing, .unknown:
            return .failure(.sourcePathUnavailable(sourcePathState.rawValue))
        case .inspectFailed(let reason):
            return .failure(.sourcePathInspectionFailed(reason))
        }
        let destinationURL = runtimeDataBackupsRoot.appendingPathComponent(
            sourceBackupURL.lastPathComponent,
            isDirectory: true
        )
        guard RuntimeManagedBackupPolicy.isRuntimeDataBackupURL(
            destinationURL,
            runtimeDataBackupsRoot: runtimeDataBackupsRoot
        ) else {
            return .failure(.invalidBackup)
        }
        switch destinationPathState {
        case .missing:
            return .success(RuntimeBackupImportPlan(
                sourceURL: sourceBackupURL,
                destinationURL: destinationURL
            ))
        case .inspectFailed(let reason):
            return .failure(.destinationPathInspectionFailed(reason))
        case .file, .directory, .other:
            return .failure(.destinationAlreadyExists)
        case .unknown:
            return .failure(.destinationPathUnavailable(destinationPathState.rawValue))
        }
    }

    public func importRedisBackupPlan(
        sourceBackupURL: URL?,
        redisBackupsRoot: URL?,
        sourcePathState: RuntimePathState,
        destinationPathState: RuntimePathState
    ) -> Result<RuntimeBackupImportPlan, RuntimeRedisBackupImportPlanFailure> {
        guard let sourceBackupURL else {
            return .failure(.missingBackup)
        }
        guard let redisBackupsRoot else {
            return .failure(.backupsRootNotReported)
        }
        switch sourcePathState {
        case .file:
            break
        case .directory, .other:
            return .failure(.sourceIsNotFile)
        case .missing, .unknown:
            return .failure(.sourcePathUnavailable(sourcePathState.rawValue))
        case .inspectFailed(let reason):
            return .failure(.sourcePathInspectionFailed(reason))
        }
        let destinationURL = redisBackupsRoot.appendingPathComponent(sourceBackupURL.lastPathComponent)
        guard isRedisBackupURL(destinationURL, redisBackupsRoot: redisBackupsRoot) else {
            return .failure(.invalidBackup)
        }
        switch destinationPathState {
        case .missing:
            return .success(RuntimeBackupImportPlan(
                sourceURL: sourceBackupURL,
                destinationURL: destinationURL
            ))
        case .inspectFailed(let reason):
            return .failure(.destinationPathInspectionFailed(reason))
        case .file, .directory, .other:
            return .failure(.destinationAlreadyExists)
        case .unknown:
            return .failure(.destinationPathUnavailable(destinationPathState.rawValue))
        }
    }

    private func isRedisBackupURL(_ url: URL, redisBackupsRoot: URL) -> Bool {
        let backupURL = url.standardizedFileURL
        let backupsRootURL = redisBackupsRoot.standardizedFileURL
        guard backupURL.deletingLastPathComponent().path == backupsRootURL.path else {
            return false
        }
        let name = backupURL.lastPathComponent
        guard name.hasPrefix("redis-"), name.hasSuffix(".tar.gz") else {
            return false
        }
        return backupURL.path.hasPrefix(backupsRootURL.path + "/")
    }
}

extension RuntimeBackupActionPlanFailure {
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

extension RuntimeBackupImportPlanFailure {
    var message: String {
        switch self {
        case .missingBackup:
            return AppConstants.StatusText.runtimeDataBackupImportSourceInvalid
        case .backupsRootNotReported:
            return AppConstants.StatusText.notReported
        case .sourceIsNotDirectory:
            return AppConstants.StatusText.runtimeDataBackupImportSourceInvalid
        case .sourcePathInspectionFailed(let reason):
            return AppConstants.StatusText.runtimeDataBackupImportFailed(reason)
        case .sourcePathUnavailable(let state):
            return AppConstants.StatusText.runtimeDataBackupImportSourcePathInvalid(state)
        case .invalidBackup:
            return AppConstants.StatusText.invalidBackup
        case .destinationAlreadyExists:
            return AppConstants.StatusText.runtimeDataBackupImportDestinationExists
        case .destinationPathInspectionFailed(let reason):
            return AppConstants.StatusText.runtimeDataBackupImportFailed(reason)
        case .destinationPathUnavailable(let state):
            return AppConstants.StatusText.runtimeDataBackupImportPathInvalid(state)
        }
    }
}

extension RuntimeRedisBackupImportPlanFailure {
    var message: String {
        switch self {
        case .missingBackup:
            return AppConstants.StatusText.redisBackupImportSourceInvalid
        case .backupsRootNotReported:
            return AppConstants.StatusText.notReported
        case .sourceIsNotFile:
            return AppConstants.StatusText.redisBackupImportSourceInvalid
        case .sourcePathInspectionFailed(let reason):
            return AppConstants.StatusText.redisBackupImportFailed(reason)
        case .sourcePathUnavailable(let state):
            return AppConstants.StatusText.redisBackupImportSourcePathInvalid(state)
        case .invalidBackup:
            return AppConstants.StatusText.invalidBackup
        case .destinationAlreadyExists:
            return AppConstants.StatusText.redisBackupImportDestinationExists
        case .destinationPathInspectionFailed(let reason):
            return AppConstants.StatusText.redisBackupImportFailed(reason)
        case .destinationPathUnavailable(let state):
            return AppConstants.StatusText.redisBackupImportPathInvalid(state)
        }
    }
}
