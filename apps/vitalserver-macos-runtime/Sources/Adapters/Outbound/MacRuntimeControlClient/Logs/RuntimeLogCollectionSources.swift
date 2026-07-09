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
        let installed = InstalledRuntimePaths.defaultInstalled
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
            return installed.logsDirectory.appendingPathComponent(contract.sourceFileName)
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
        case .commandLog:
            return installed.managerCommandLog
        }
    }

    static func destinationURL(for scope: RuntimeLogCollectionDestinationScope) -> URL {
        let installed = InstalledRuntimePaths.defaultInstalled
        switch scope {
        case .runtimeLogs:
            return installed.centralRuntimeLogsDirectory
        case .guestLogs:
            return installed.centralGuestLogsDirectory
        case .productLogs:
            return installed.productLogsDirectory
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
            return InstalledRuntimePaths.defaultInstalled.guestObservabilityDirectory
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
            return InstalledRuntimePaths.defaultInstalled.guestRunDirectory
        }
    }
}
