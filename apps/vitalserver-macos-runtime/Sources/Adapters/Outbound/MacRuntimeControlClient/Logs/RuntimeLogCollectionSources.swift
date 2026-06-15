import Foundation
import RuntimeControl

struct RuntimeLogCopy {
    let source: URL
    let destination: URL
    let archivePrefix: String

    init(source: URL, destination: URL, archivePrefix: String) {
        self.source = source
        self.destination = destination
        self.archivePrefix = archivePrefix
    }

    static func defaultCopies() -> [RuntimeLogCopy] {
        RuntimeLogCollectionSourceContract.fileCopies().map { contract in
            RuntimeLogCopy(
                source: sourceURL(for: contract),
                destination: destinationURL(for: contract.destinationScope)
                    .appendingPathComponent(contract.destinationFileName),
                archivePrefix: contract.archivePrefix
            )
        }
    }

    private static func sourceURL(for contract: RuntimeLogCollectionFileContract) -> URL {
        switch contract.sourceID {
        case .launcherLog,
             .launchdOutputLog,
             .launchdErrorLog,
             .proxyOutputLog,
             .proxyErrorLog,
             .guestLogSyncOutputLog,
             .guestLogSyncErrorLog,
             .sleepPreventionOutputLog,
             .sleepPreventionErrorLog,
             .watchdogOutputLog,
             .watchdogErrorLog:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeLogSources)
                .appendingPathComponent(contract.sourceFileName)
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
        case .commandLog:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.commandLogFile)
        }
    }

    static func destinationURL(for scope: RuntimeLogCollectionDestinationScope) -> URL {
        switch scope {
        case .runtimeLogs:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeLogs)
        case .guestLogs:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.guestLogs)
        case .productLogs:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.productLogs)
        }
    }
}

struct RuntimeLogDirectoryCopy {
    let source: URL
    let destination: URL

    init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }

    static func defaultCopies() -> [RuntimeLogDirectoryCopy] {
        RuntimeLogCollectionSourceContract.directoryCopies().map { contract in
            RuntimeLogDirectoryCopy(
                source: sourceURL(for: contract.sourceID),
                destination: RuntimeLogCopy.destinationURL(for: contract.destinationScope)
                    .appendingPathComponent(contract.destinationDirectoryName)
            )
        }
    }

    private static func sourceURL(for sourceID: RuntimeLogCollectionDirectorySourceID) -> URL {
        switch sourceID {
        case .guestObservability:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.guestObservabilitySource)
        }
    }
}

struct RuntimeRotatedLogCopySet {
    let sourceDirectory: URL
    let sourceFilePrefix: String
    let destinationDirectory: URL
    let destinationFilePrefix: String
    let archivePrefix: String

    init(
        sourceDirectory: URL,
        sourceFilePrefix: String,
        destinationDirectory: URL,
        destinationFilePrefix: String,
        archivePrefix: String
    ) {
        self.sourceDirectory = sourceDirectory
        self.sourceFilePrefix = sourceFilePrefix
        self.destinationDirectory = destinationDirectory
        self.destinationFilePrefix = destinationFilePrefix
        self.archivePrefix = archivePrefix
    }

    static func defaultSets() -> [RuntimeRotatedLogCopySet] {
        RuntimeLogCollectionSourceContract.rotatedCopies().map { contract in
            RuntimeRotatedLogCopySet(
                sourceDirectory: sourceDirectory(for: contract.sourceID),
                sourceFilePrefix: contract.sourceFilePrefix,
                destinationDirectory: RuntimeLogCopy.destinationURL(for: contract.destinationScope),
                destinationFilePrefix: contract.destinationFilePrefix,
                archivePrefix: contract.archivePrefix
            )
        }
    }

    private static func sourceDirectory(for sourceID: RuntimeLogCollectionRotatedSourceID) -> URL {
        switch sourceID {
        case .containerLogs:
            return URL(fileURLWithPath: RuntimeControlClientConstants.Paths.guestRunDirectory)
        }
    }
}
