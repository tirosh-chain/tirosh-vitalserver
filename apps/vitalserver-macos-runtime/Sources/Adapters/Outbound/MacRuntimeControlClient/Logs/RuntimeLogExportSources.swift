import Foundation
import Contracts
import RuntimeControl

struct RuntimeLogExportSupplementalSource {
    let source: URL
    let relativeDestination: String

    init(source: URL, relativeDestination: String) {
        self.source = source
        self.relativeDestination = relativeDestination
    }

    static func defaultItems() -> [RuntimeLogExportSupplementalSource] {
        RuntimeLogExportSourceContract.supplementalDestinations().map { contract in
            RuntimeLogExportSupplementalSource(
                source: sourceURL(for: contract.sourceID),
                relativeDestination: contract.relativeDestination
            )
        }
    }

    private static func sourceURL(for sourceID: RuntimeLogExportSupplementalSourceID) -> URL {
        let installed = InstalledRuntimePaths.defaultInstalled
        switch sourceID {
        case .bootstrapLog:
            return installed.bootstrapLog
        case .containerLog:
            return installed.containerLogs
        case .updateActivationLog:
            return installed.updateActivationLog
        case .updateShutdownLog:
            return installed.updateShutdownLog
        case .datastoreRepairLog:
            return installed.datastoreRepairLog
        case .redisBackupLog:
            return installed.redisBackupLog
        case .guestObservability:
            return installed.guestObservabilityDirectory
        case .commandLog:
            return installed.managerCommandLog
        case .helperMessageLog:
            return installed.managerHelperMessageLog
        case .runtimeStatus:
            return installed.runtimeStatus
        case .hostRuntimeStateEvents:
            return installed.hostRuntimeStateEvents
        case .hostRuntimeStateSnapshot:
            return installed.hostRuntimeStateSnapshot
        case .hostRuntimeStateDatabase:
            return installed.runtimeStateDatabase
        case .hostRuntimeStateDatabaseWAL:
            return URL(fileURLWithPath: "\(installed.runtimeStateDatabase.path)-wal")
        case .hostRuntimeStateDatabaseSHM:
            return URL(fileURLWithPath: "\(installed.runtimeStateDatabase.path)-shm")
        case .runtimeEvents:
            return installed.runtimeEvents
        case .runtimeObservabilityDB:
            return installed.runtimeObservabilityDB
        case .runtimeObservabilityDBWAL:
            return URL(fileURLWithPath: "\(installed.runtimeObservabilityDB.path)-wal")
        case .runtimeObservabilityDBSHM:
            return URL(fileURLWithPath: "\(installed.runtimeObservabilityDB.path)-shm")
        case .runtimeObservation:
            return installed.runtimeObservation
        case .vmIP:
            return installed.vmIPFile
        case .vmConfig:
            return installed.vmConfig
        case .runtimeVersion:
            return installed.runtimeDirectory.appendingPathComponent(RuntimePackageArtifactFileNames.runtimeVersion)
        case .guestRuntimeConfig:
            return installed.guestRuntimeConfig
        case .timeAuthority:
            return installed.timeAuthority
        case .proxyLaunchDaemon:
            return installed.proxyLaunchDaemon
        case .proxyNginxConfig:
            return installed.nginxDirectory.appendingPathComponent("vitalserver.conf")
        case .proxyNginxPid:
            return installed.proxyNginxPID
        }
    }
}

struct RuntimeLogExportRotatedSupplementalSet {
    let sourceDirectory: URL
    let sourceFilePrefix: String
    let relativeDestinationDirectory: String
    let destinationFilePrefix: String

    init(
        sourceDirectory: URL,
        sourceFilePrefix: String,
        relativeDestinationDirectory: String,
        destinationFilePrefix: String
    ) {
        self.sourceDirectory = sourceDirectory
        self.sourceFilePrefix = sourceFilePrefix
        self.relativeDestinationDirectory = relativeDestinationDirectory
        self.destinationFilePrefix = destinationFilePrefix
    }

    var manifestKey: String {
        [
            sourceDirectory.path,
            sourceFilePrefix,
            relativeDestinationDirectory,
            destinationFilePrefix,
        ].joined(separator: "\u{1F}")
    }

    static func defaultSets() -> [RuntimeLogExportRotatedSupplementalSet] {
        RuntimeLogExportSourceContract.rotatedSupplementalDestinations().map { contract in
            RuntimeLogExportRotatedSupplementalSet(
                sourceDirectory: sourceDirectory(for: contract.sourceID),
                sourceFilePrefix: contract.sourceFilePrefix,
                relativeDestinationDirectory: contract.relativeDestinationDirectory,
                destinationFilePrefix: contract.destinationFilePrefix
            )
        }
    }

    private static func sourceDirectory(for sourceID: RuntimeLogExportRotatedSupplementalSourceID) -> URL {
        switch sourceID {
        case .containerLogs:
            return InstalledRuntimePaths.defaultInstalled.guestRunDirectory
        case .runtimeEvents:
            return InstalledRuntimePaths.defaultInstalled.runtimeEvents.deletingLastPathComponent()
        }
    }
}
