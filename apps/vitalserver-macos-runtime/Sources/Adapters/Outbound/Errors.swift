import Foundation
import Contracts


public enum CompositeRuntimeEventRepositoryError: Error, Equatable, CustomStringConvertible {
    case secondaryAppendFailed(eventID: String, error: String)

    public var description: String {
        switch self {
        case .secondaryAppendFailed(let eventID, let error):
            return "runtime event sqlite append failed eventID=\(eventID) error=\(error)"
        }
    }
}


public enum JSONLRuntimeEventRepositoryError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingFileSize(path: String)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .missingFileSize(let path):
            return "runtime event log file size is missing path=\(path)"
        case .pathInspectionFailed(let path, let reason):
            return "runtime event log path inspection failed path=\(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "runtime event log path state is unexpected path=\(path) state=\(state)"
        }
    }
}


public enum MacTestKitControllerError: LocalizedError, Equatable {
    case apiEndpointUnavailable(String)
    case apiUnavailable(String)
    case invalidResponse
    case invalidRequestURL(String)
    case missingSessionID
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .apiEndpointUnavailable(let message):
            return message
        case .apiUnavailable(let apiBaseURL):
            return "TestKit container API is not reachable at \(apiBaseURL)."
        case .invalidResponse:
            return "TestKit API returned an invalid response."
        case .invalidRequestURL(let message):
            return message
        case .missingSessionID:
            return "TestKit session ID is required."
        case .requestFailed(let message):
            return message
        }
    }
}


public enum ProcessStateError: Error, CustomStringConvertible, Equatable {
    case runtimeOperationFailed(String)

    public var description: String {
        switch self {
        case .runtimeOperationFailed(let message):
            return message
        }
    }
}


public enum RuntimeActionEnvironmentError: LocalizedError {
    case invalidAdminPassword
    case adminPasswordFileCreateFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidAdminPassword:
            return "Admin password must be UTF-8."
        case .adminPasswordFileCreateFailed(let path, let reason):
            return "Failed to prepare the admin password file path=\(path) reason=\(reason)."
        }
    }
}


public enum RuntimeArtifactReplacementError: Error, CustomStringConvertible {
    case bundleVerificationFailed(String)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .bundleVerificationFailed(let message):
            return "bundle verification failed: \(message)"
        case .pathInspectionFailed(let path, let reason):
            return "artifact replacement path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "artifact replacement path state is unexpected: \(path) state=\(state)"
        }
    }
}

public enum RuntimeBackupManifestLoaderError: Error, Equatable, CustomStringConvertible {
    case missingFile(path: String)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .missingFile(let path):
            return "missing file: \(path)"
        case .pathInspectionFailed(let path, let reason):
            return "backup manifest path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "backup manifest path state is unexpected: \(path) state=\(state)"
        case .readFailed(let path, let reason):
            return "failed to read backup manifest: \(path) reason=\(reason)"
        case .decodeFailed(let path, let reason):
            return "failed to decode backup manifest: \(path) reason=\(reason)"
        }
    }
}


public enum RuntimeBackupListError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case invalidLatestBackupPath(String)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .invalidLatestBackupPath(let path):
            return "latest backup path is not a backup directory: \(path)"
        case .pathInspectionFailed(let path, let reason):
            return "backup list path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "backup list path state is unexpected: \(path) state=\(state)"
        }
    }

    public var errorDescription: String? {
        description
    }
}


public enum RuntimeBackupStoreError: Error, Equatable, CustomStringConvertible {
    case noBackupsAvailable
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .noBackupsAvailable:
            return "no backups available"
        case .pathInspectionFailed(let path, let reason):
            return "backup store path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "backup store path state is unexpected: \(path) state=\(state)"
        }
    }
}


public enum RuntimeVersionStoreError: Error, CustomStringConvertible, Equatable {
    case versionPathInspectionFailed(path: String, reason: String)
    case unexpectedVersionPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .versionPathInspectionFailed(let path, let reason):
            return "runtime version path inspection failed: \(path) reason=\(reason)"
        case .unexpectedVersionPathState(let path, let state):
            return "runtime version path state is unexpected: \(path) state=\(state)"
        }
    }
}


public enum RuntimeClientError: LocalizedError {
    case missingLauncher
    case missingUninstaller
    case launcherInspectionFailed(path: String, reason: String)
    case uninstallerInspectionFailed(path: String, reason: String)
    case launcherNotExecutable(path: String, state: String)
    case uninstallerNotExecutable(path: String, state: String)
    case invalidBackupDeletionTarget(path: String, backupsRoot: String)
    case logExportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingLauncher:
            return "vitalserver-vm launcher is missing. Reinstall the app or package."
        case .missingUninstaller:
            return "Uninstaller is missing. Reinstall the package before uninstalling."
        case .launcherInspectionFailed(let path, let reason):
            return "vitalserver-vm launcher inspection failed path=\(path) reason=\(reason)."
        case .uninstallerInspectionFailed(let path, let reason):
            return "Uninstaller inspection failed path=\(path) reason=\(reason)."
        case .launcherNotExecutable(let path, let state):
            return "vitalserver-vm launcher is not executable path=\(path) state=\(state)."
        case .uninstallerNotExecutable(let path, let state):
            return "Uninstaller is not executable path=\(path) state=\(state)."
        case .invalidBackupDeletionTarget(let path, let backupsRoot):
            return "Backup deletion target is outside the managed backup directory path=\(path) backupsRoot=\(backupsRoot)."
        case .logExportFailed(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Log export failed." : trimmed
        }
    }
}


public enum RuntimeCommandExecutionError: Error, CustomStringConvertible, Equatable {
    case commandFailed(String)

    public var description: String {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}


public enum RuntimeCloudInitSeedWriterError: Error, CustomStringConvertible, Equatable {
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .pathInspectionFailed(let path, let reason):
            return "cloud-init seed path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "cloud-init seed path state is unexpected: \(path) state=\(state)"
        }
    }
}


public enum RuntimeGuestConfigDocumentReadError: Error, Equatable {
    case missingFile(String)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
}


public enum RuntimeGuestLogCollectorError: Error, CustomStringConvertible, Equatable {
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .pathInspectionFailed(let path, let reason):
            return "guest log collection path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "guest log collection path state is unexpected: \(path) state=\(state)"
        }
    }
}


public enum RuntimeHostFileReaderError: LocalizedError, Equatable {
    case invalidUTF8(path: String)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8(let path):
            return "Log file is not valid UTF-8: \(path)"
        case .pathInspectionFailed(let path, let reason):
            return "file path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "file path state is unexpected: \(path) state=\(state)"
        }
    }
}


public enum RuntimeInstallVMDiskProvisioningError: Error, CustomStringConvertible {
    case missingFile(String)
    case fileInspectionFailed(path: String, reason: String)
    case unexpectedFileState(path: String, state: String)
    case runtimeDataDiskTooSmall(path: String, actualBytes: UInt64, requiredBytes: UInt64)

    public var description: String {
        switch self {
        case .missingFile(let path):
            return "missing file: \(path)"
        case .fileInspectionFailed(let path, let reason):
            return "file inspection failed: \(path) reason=\(reason)"
        case .unexpectedFileState(let path, let state):
            return "unexpected file state: \(path) state=\(state)"
        case .runtimeDataDiskTooSmall(let path, let actualBytes, let requiredBytes):
            return "runtime data disk is too small: \(path) actualBytes=\(actualBytes) requiredBytes=\(requiredBytes)"
        }
    }
}


public enum RuntimeBundleStagingError: Error, CustomStringConvertible, Equatable {
    case destinationInspectionFailed(path: String, reason: String)
    case unexpectedDestinationState(path: String, state: String)

    public var description: String {
        switch self {
        case .destinationInspectionFailed(let path, let reason):
            return "bundle staging destination inspection failed: \(path) reason=\(reason)"
        case .unexpectedDestinationState(let path, let state):
            return "bundle staging destination state is unexpected: \(path) state=\(state)"
        }
    }
}


public enum RuntimeLogExporterError: LocalizedError, Equatable {
    case missingPOSIXPermissions(path: String)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var errorDescription: String? {
        switch self {
        case .missingPOSIXPermissions(let path):
            return "POSIX permissions are missing for \(path)"
        case .pathInspectionFailed(let path, let reason):
            return "log export path inspection failed for \(path): \(reason)"
        case .unexpectedPathState(let path, let state):
            return "log export path state is unexpected for \(path): \(state)"
        }
    }
}


public enum RuntimeControlLogCollectorError: Error, CustomStringConvertible, Equatable {
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
    case metadataWriteUnsupported(path: String)

    public var description: String {
        switch self {
        case .pathInspectionFailed(let path, let reason):
            return "runtime control log collection path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "runtime control log collection path state is unexpected: \(path) state=\(state)"
        case .metadataWriteUnsupported(let path):
            return "runtime control log collection metadata write is unsupported: \(path)"
        }
    }
}


public enum RuntimeLogRotatorError: Error, CustomStringConvertible, Equatable {
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .pathInspectionFailed(let path, let reason):
            return "runtime log rotation path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "runtime log rotation path state is unexpected: \(path) state=\(state)"
        }
    }
}


public enum RuntimeMigrationRunnerError: Error, CustomStringConvertible {
    case bundleVerificationFailed(String)
    case missingMigration(path: String)
    case migrationInspectionFailed(path: String, reason: String)
    case migrationNotExecutable(path: String, state: String)

    public var description: String {
        switch self {
        case .bundleVerificationFailed(let message):
            return "bundle verification failed: \(message)"
        case .missingMigration(let path):
            return "migration is missing: \(path)"
        case .migrationInspectionFailed(let path, let reason):
            return "migration path inspection failed: \(path) reason=\(reason)"
        case .migrationNotExecutable(let path, let state):
            return "migration is not executable: \(path) state=\(state)"
        }
    }
}


public enum RuntimeOperationLeaseRepositoryError: Error, Equatable, CustomStringConvertible {
    case existingOperation(operationId: String, operation: String)
    case readFailed(String)
    case createFailed(String)
    case lockFailed(path: String, reason: String)
    case operationIdMismatch(expected: String, actual: String)

    public var description: String {
        switch self {
        case .existingOperation(let operationId, let operation):
            return "runtime operation lease already exists operationId=\(operationId) operation=\(operation)"
        case .readFailed(let reason):
            return "runtime operation lease read failed: \(reason)"
        case .createFailed(let path):
            return "runtime operation lease create failed path=\(path)"
        case .lockFailed(let path, let reason):
            return "runtime operation lease lock failed path=\(path) reason=\(reason)"
        case .operationIdMismatch(let expected, let actual):
            return "runtime operation lease operationId mismatch expected=\(expected) actual=\(actual)"
        }
    }
}


public enum RuntimeServiceControllerError: Error, CustomStringConvertible, Equatable {
    case runtimeOperationFailed(String)
    case missingArgument(String)

    public var description: String {
        switch self {
        case .runtimeOperationFailed(let message), .missingArgument(let message):
            return message
        }
    }
}


public enum RuntimeStatusReporterError: Error, Equatable {
    case missingStatusDocumentForProgress
    case statusDocumentReadFailed(String)
}

public enum RuntimeStatusRepositoryError: Error, Equatable, CustomStringConvertible {
    case missingRequiredRoot(path: String)
    case requiredRootInspectionFailed(path: String, reason: String)
    case unexpectedRequiredRootState(path: String, state: String)

    public var description: String {
        switch self {
        case .missingRequiredRoot(let path):
            return "runtime status required root is missing path=\(path)"
        case .requiredRootInspectionFailed(let path, let reason):
            return "runtime status required root inspection failed path=\(path) reason=\(reason)"
        case .unexpectedRequiredRootState(let path, let state):
            return "runtime status required root state is unexpected path=\(path) state=\(state)"
        }
    }
}


public enum RuntimeStorageMaintenanceError: Error, CustomStringConvertible, Equatable {
    case freeSpaceUnavailable(path: String)
    case insufficientFreeSpace(operation: String, required: UInt64, available: UInt64)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
    case directoryListingFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .freeSpaceUnavailable(let path):
            return "could not determine free space for \(path)"
        case let .insufficientFreeSpace(operation, required, available):
            return "insufficient free space for \(operation): required \(formatBytes(required)), available \(formatBytes(available))"
        case .pathInspectionFailed(let path, let reason):
            return "runtime storage path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "runtime storage path state is unexpected: \(path) state=\(state)"
        case .directoryListingFailed(let path, let reason):
            return "runtime storage directory listing failed: \(path) reason=\(reason)"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}


public enum RuntimeInstallDirectoryPreparationError: Error, CustomStringConvertible, Equatable {
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .pathInspectionFailed(let path, let reason):
            return "install directory preparation path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "install directory preparation path state is unexpected: \(path) state=\(state)"
        }
    }
}


public enum RuntimeInstallSettingsCleanupError: Error, CustomStringConvertible, Equatable {
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .pathInspectionFailed(let path, let reason):
            return "install settings cleanup path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "install settings cleanup path state is unexpected: \(path) state=\(state)"
        }
    }
}


public enum JSONFileRuntimeGuestGatewayError: Error, CustomStringConvertible, Equatable {
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .pathInspectionFailed(let path, let reason):
            return "runtime guest gateway path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "runtime guest gateway path state is unexpected: \(path) state=\(state)"
        }
    }
}


public enum RuntimeVMLifecycleStoreError: Error, Equatable, CustomStringConvertible {
    case readFailed(String)
    case invalidStartedAt(String)
    case missingDocumentForState(RuntimeVMLifecycleState)

    public var description: String {
        switch self {
        case .readFailed(let reason):
            return "VM lifecycle document read failed: \(reason)"
        case .invalidStartedAt(let value):
            return "VM lifecycle document startedAt is invalid: \(value)"
        case .missingDocumentForState(let state):
            return "VM lifecycle document is missing for state transition: \(state.rawValue)"
        }
    }
}


public enum SQLiteRuntimeObservabilityStoreError: Error, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case decodeFailed(payload: String, reason: String)
    case missingColumn(table: String, column: String)
    case invalidColumnValue(table: String, column: String, value: String)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
    case relationshipProjectionProviderMissing
    case transactionRollbackFailed(original: String, rollback: String)
}


public enum SystemRuntimeFileStoreError: Error, Equatable, Sendable {
    case missingFileSize(path: String)
    case missingModificationDate(path: String)
    case missingDirectoryFlag(path: String)
    case missingRegularFileFlag(path: String)
    case missingFileSystemFreeSize(path: String)
    case partialReadReturnedNil(path: String, offset: UInt64)
}


public enum VMConfigurationFactoryError: Error, Equatable {
    case invalidMacAddress(String)
    case missingBridgedInterface
    case noBridgedInterfaces
    case bridgedInterfaceUnavailable(String)
    case storagePathInspectionFailed(path: String, reason: String)
    case unexpectedStoragePathState(path: String, state: String)
    case missingStorageFile(String)
    case missingRootDiskPath
    case missingRuntimeDataDiskPath
}


public enum VMRuntimeBootFileValidationError: Error, Equatable {
    case missingFile(String)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
}


public enum VMRuntimeConfigReadError: Error, Equatable {
    case missingConfig(String)
    case configInspectionFailed(path: String, reason: String)
    case unexpectedConfigPathState(path: String, state: String)
}
