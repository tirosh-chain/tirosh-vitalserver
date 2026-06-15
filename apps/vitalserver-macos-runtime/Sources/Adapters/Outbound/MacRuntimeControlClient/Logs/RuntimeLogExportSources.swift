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
        switch sourceID {
        case .bootstrapLog:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.bootstrapLogSource)
        case .containerLog:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.containerLogSource)
        case .updateActivationLog:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.updateActivationLogSource)
        case .updateShutdownLog:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.updateShutdownLogSource)
        case .datastoreRepairLog:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.datastoreRepairLogSource)
        case .redisBackupLog:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.redisBackupLogSource)
        case .guestObservability:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.guestObservabilitySource)
        case .commandLog:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.commandLogFile)
        case .helperMessageLog:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.helperMessageLogFile)
        case .runtimeStatus:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeStatus)
        case .runtimeOperationLease:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeOperationLease)
        case .runtimeEvents:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeEvents)
        case .runtimeObservabilityDB:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeObservabilityDB)
        case .runtimeObservabilityDBWAL:
            return URL(fileURLWithPath: "\(RuntimeControlClientConstants.Paths.runtimeObservabilityDB)-wal")
        case .runtimeObservabilityDBSHM:
            return URL(fileURLWithPath: "\(RuntimeControlClientConstants.Paths.runtimeObservabilityDB)-shm")
        case .runtimeState:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeState)
        case .vmLifecycle:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.vmLifecycle)
        case .vmIP:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.vmIPFile)
        case .vmConfig:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.vmConfig)
        case .runtimeVersion:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeVersion)
        case .guestRuntimeConfig:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.guestRuntimeConfig)
        case .proxyLaunchDaemon:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.proxyLaunchDaemon)
        case .proxyNginxConfig:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.proxyNginxConfig)
        case .proxyNginxPid:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.proxyNginxPid)
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
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.guestRunDirectory)
        case .runtimeEvents:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeEvents)
                .deletingLastPathComponent()
        }
    }
}
