import Foundation


public enum CompositeRuntimeEventRepositoryError: Error, Equatable, CustomStringConvertible {
    case secondaryAppendFailed(eventID: String, error: String)

    public var description: String {
        switch self {
        case .secondaryAppendFailed(let eventID, let error):
            return "runtime event sqlite append failed eventID=\(eventID) error=\(error)"
        }
    }
}


public enum JSONLRuntimeEventRepositoryError: Error, Equatable, Sendable {
    case missingFileSize(path: String)
}


public enum MacTestKitControllerError: LocalizedError, Equatable {
    case apiEndpointUnavailable(String)
    case apiUnavailable(String)
    case invalidResponse
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .apiEndpointUnavailable(let message):
            return message
        case .apiUnavailable(let apiBaseURL):
            return "TestKit container API is not reachable at \(apiBaseURL)."
        case .invalidResponse:
            return "TestKit API returned an invalid response."
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
    case adminPasswordFileCreateFailed

    public var errorDescription: String? {
        switch self {
        case .invalidAdminPassword:
            return "Admin password must be UTF-8."
        case .adminPasswordFileCreateFailed:
            return "Failed to prepare the admin password file."
        }
    }
}


public enum RuntimeArtifactReplacementError: Error, CustomStringConvertible {
    case bundleVerificationFailed(String)

    public var description: String {
        switch self {
        case .bundleVerificationFailed(let message):
            return "bundle verification failed: \(message)"
        }
    }
}

public enum RuntimeBackupManifestLoaderError: Error, Equatable, CustomStringConvertible {
    case missingFile(path: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .missingFile(let path):
            return "missing file: \(path)"
        case .readFailed(let path, let reason):
            return "failed to read backup manifest: \(path) reason=\(reason)"
        case .decodeFailed(let path, let reason):
            return "failed to decode backup manifest: \(path) reason=\(reason)"
        }
    }
}


public enum RuntimeBackupStoreError: Error, Equatable, CustomStringConvertible {
    case noBackupsAvailable

    public var description: String {
        switch self {
        case .noBackupsAvailable:
            return "no backups available"
        }
    }
}


public enum RuntimeClientError: LocalizedError {
    case missingLauncher
    case missingUninstaller
    case logExportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingLauncher:
            return "vitalserver-vm launcher is missing. Reinstall the app or package."
        case .missingUninstaller:
            return "Uninstaller is missing. Reinstall the package before uninstalling."
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


public enum RuntimeGuestConfigDocumentReadError: Error, Equatable {
    case missingFile(String)
}


public enum RuntimeHostFileReaderError: LocalizedError, Equatable {
    case invalidUTF8(path: String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8(let path):
            return "Log file is not valid UTF-8: \(path)"
        }
    }
}


public enum RuntimeHostProxyPortCleanerError: Error, CustomStringConvertible, Equatable {
    case runtimeOperationFailed(String)

    public var description: String {
        switch self {
        case .runtimeOperationFailed(let message):
            return message
        }
    }
}


public enum RuntimeInstallVMDiskProvisioningError: Error, CustomStringConvertible {
    case missingFile(String)

    public var description: String {
        switch self {
        case .missingFile(let path):
            return "missing file: \(path)"
        }
    }
}


public enum RuntimeLogExporterError: LocalizedError, Equatable {
    case missingPOSIXPermissions(path: String)

    public var errorDescription: String? {
        switch self {
        case .missingPOSIXPermissions(let path):
            return "POSIX permissions are missing for \(path)"
        }
    }
}


public enum RuntimeMigrationRunnerError: Error, CustomStringConvertible {
    case bundleVerificationFailed(String)

    public var description: String {
        switch self {
        case .bundleVerificationFailed(let message):
            return "bundle verification failed: \(message)"
        }
    }
}


public enum RuntimeOperationLeaseRepositoryError: Error, Equatable, CustomStringConvertible {
    case existingOperation(operationId: String, operation: String)
    case readFailed(String)
    case createFailed(String)
    case operationIdMismatch(expected: String, actual: String)

    public var description: String {
        switch self {
        case .existingOperation(let operationId, let operation):
            return "runtime operation lease already exists operationId=\(operationId) operation=\(operation)"
        case .readFailed(let reason):
            return "runtime operation lease read failed: \(reason)"
        case .createFailed(let path):
            return "runtime operation lease create failed path=\(path)"
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


public enum RuntimeStorageMaintenanceError: Error, CustomStringConvertible, Equatable {
    case freeSpaceUnavailable(path: String)
    case insufficientFreeSpace(operation: String, required: UInt64, available: UInt64)

    public var description: String {
        switch self {
        case .freeSpaceUnavailable(let path):
            return "could not determine free space for \(path)"
        case let .insufficientFreeSpace(operation, required, available):
            return "insufficient free space for \(operation): required \(formatBytes(required)), available \(formatBytes(available))"
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


public enum SQLiteRuntimeObservabilityStoreError: Error, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case decodeFailed(String)
    case missingColumn(table: String, column: String)
    case invalidColumnValue(table: String, column: String, value: String)
}


public enum SystemRuntimeFileStoreError: Error, Equatable, Sendable {
    case missingFileSize(path: String)
    case missingModificationDate(path: String)
    case missingDirectoryFlag(path: String)
    case missingRegularFileFlag(path: String)
    case missingFileSystemFreeSize(path: String)
}


public enum VMConfigurationFactoryError: Error, Equatable {
    case invalidMacAddress(String)
    case missingBridgedInterface
    case noBridgedInterfaces
    case bridgedInterfaceUnavailable(String)
}


public enum VMRuntimeBootFileValidationError: Error, Equatable {
    case missingFile(String)
}


public enum VMRuntimeConfigReadError: Error, Equatable {
    case missingConfig(String)
}
