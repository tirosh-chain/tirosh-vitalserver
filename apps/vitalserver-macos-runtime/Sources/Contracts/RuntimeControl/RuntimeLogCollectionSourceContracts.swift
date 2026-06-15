import Contracts

public enum RuntimeLogCollectionFileSourceID: String, CaseIterable, Sendable {
    case launcherLog
    case launchdOutputLog
    case launchdErrorLog
    case proxyOutputLog
    case proxyErrorLog
    case guestLogSyncOutputLog
    case guestLogSyncErrorLog
    case sleepPreventionOutputLog
    case sleepPreventionErrorLog
    case watchdogOutputLog
    case watchdogErrorLog
    case bootstrapLog
    case containerLog
    case updateActivationLog
    case updateShutdownLog
    case datastoreRepairLog
    case redisBackupLog
    case commandLog
}

public enum RuntimeLogCollectionDestinationScope: String, Sendable {
    case runtimeLogs
    case guestLogs
    case productLogs
}

public struct RuntimeLogCollectionFileContract: Equatable, Sendable {
    public let sourceID: RuntimeLogCollectionFileSourceID
    public let sourceFileName: String
    public let destinationScope: RuntimeLogCollectionDestinationScope
    public let destinationFileName: String
    public let archivePrefix: String

    public init(
        sourceID: RuntimeLogCollectionFileSourceID,
        sourceFileName: String,
        destinationScope: RuntimeLogCollectionDestinationScope,
        destinationFileName: String,
        archivePrefix: String
    ) {
        self.sourceID = sourceID
        self.sourceFileName = sourceFileName
        self.destinationScope = destinationScope
        self.destinationFileName = destinationFileName
        self.archivePrefix = archivePrefix
    }
}

public enum RuntimeLogCollectionDirectorySourceID: String, CaseIterable, Sendable {
    case guestObservability
}

public struct RuntimeLogCollectionDirectoryContract: Equatable, Sendable {
    public let sourceID: RuntimeLogCollectionDirectorySourceID
    public let destinationScope: RuntimeLogCollectionDestinationScope
    public let destinationDirectoryName: String

    public init(
        sourceID: RuntimeLogCollectionDirectorySourceID,
        destinationScope: RuntimeLogCollectionDestinationScope,
        destinationDirectoryName: String
    ) {
        self.sourceID = sourceID
        self.destinationScope = destinationScope
        self.destinationDirectoryName = destinationDirectoryName
    }
}

public enum RuntimeLogCollectionRotatedSourceID: String, CaseIterable, Sendable {
    case containerLogs
}

public struct RuntimeLogCollectionRotatedContract: Equatable, Sendable {
    public let sourceID: RuntimeLogCollectionRotatedSourceID
    public let sourceFilePrefix: String
    public let destinationScope: RuntimeLogCollectionDestinationScope
    public let destinationFilePrefix: String
    public let archivePrefix: String

    public init(
        sourceID: RuntimeLogCollectionRotatedSourceID,
        sourceFilePrefix: String,
        destinationScope: RuntimeLogCollectionDestinationScope,
        destinationFilePrefix: String,
        archivePrefix: String
    ) {
        self.sourceID = sourceID
        self.sourceFilePrefix = sourceFilePrefix
        self.destinationScope = destinationScope
        self.destinationFilePrefix = destinationFilePrefix
        self.archivePrefix = archivePrefix
    }
}

public enum RuntimeLogCollectionSourceContract {
    public static func fileCopies() -> [RuntimeLogCollectionFileContract] {
        runtimeServiceLogs() + guestLogs() + commandLogs()
    }

    public static func fileCopy(for source: RuntimeLogSource) -> RuntimeLogCollectionFileContract? {
        guard let sourceID = fileSourceID(for: source) else {
            return nil
        }
        return fileCopies().first { $0.sourceID == sourceID }
    }

    public static func directoryCopies() -> [RuntimeLogCollectionDirectoryContract] {
        [
            .init(
                sourceID: .guestObservability,
                destinationScope: .guestLogs,
                destinationDirectoryName: "guest-observability"
            ),
        ]
    }

    public static func rotatedCopies() -> [RuntimeLogCollectionRotatedContract] {
        [
            .init(
                sourceID: .containerLogs,
                sourceFilePrefix: "\(RuntimeFileNames.containerLogs).",
                destinationScope: .guestLogs,
                destinationFilePrefix: "\(RuntimeFileNames.containerLogs).",
                archivePrefix: "guest-container-logs.log."
            ),
        ]
    }

    private static func fileSourceID(for source: RuntimeLogSource) -> RuntimeLogCollectionFileSourceID? {
        switch source {
        case .helperMessage, .install:
            return nil
        case .command:
            return .commandLog
        case .launcher:
            return .launcherLog
        case .vmLaunchOutput:
            return .launchdOutputLog
        case .vmLaunchError:
            return .launchdErrorLog
        case .proxyOutput:
            return .proxyOutputLog
        case .proxyError:
            return .proxyErrorLog
        case .watchdog:
            return .watchdogOutputLog
        case .updateActivation:
            return .updateActivationLog
        case .updateShutdown:
            return .updateShutdownLog
        case .containers:
            return .containerLog
        }
    }

    private static func runtimeServiceLogs() -> [RuntimeLogCollectionFileContract] {
        [
            runtimeLog(.launcherLog, fileName: "launcher.log"),
            runtimeLog(.launchdOutputLog, fileName: "launchd.out.log"),
            runtimeLog(.launchdErrorLog, fileName: "launchd.err.log"),
            runtimeLog(.proxyOutputLog, fileName: "proxy.out.log"),
            runtimeLog(.proxyErrorLog, fileName: "proxy.err.log"),
            runtimeLog(.guestLogSyncOutputLog, fileName: "guest-log-sync.out.log"),
            runtimeLog(.guestLogSyncErrorLog, fileName: "guest-log-sync.err.log"),
            runtimeLog(.sleepPreventionOutputLog, fileName: "sleep-prevention.out.log"),
            runtimeLog(.sleepPreventionErrorLog, fileName: "sleep-prevention.err.log"),
            runtimeLog(.watchdogOutputLog, fileName: "watchdog.out.log"),
            runtimeLog(.watchdogErrorLog, fileName: "watchdog.err.log"),
        ]
    }

    private static func guestLogs() -> [RuntimeLogCollectionFileContract] {
        [
            guestLog(.bootstrapLog, fileName: RuntimeFileNames.bootstrapLog, archivePrefix: "guest-bootstrap.log"),
            guestLog(.containerLog, fileName: RuntimeFileNames.containerLogs, archivePrefix: "guest-container-logs.log"),
            guestLog(.updateActivationLog, fileName: RuntimeFileNames.updateActivationLog, archivePrefix: "guest-activate-update.log"),
            guestLog(.updateShutdownLog, fileName: RuntimeFileNames.updateShutdownLog, archivePrefix: "guest-prepare-update-shutdown.log"),
            guestLog(.datastoreRepairLog, fileName: RuntimeFileNames.datastoreRepairLog, archivePrefix: "guest-repair-datastore.log"),
            guestLog(.redisBackupLog, fileName: RuntimeFileNames.redisBackupLog, archivePrefix: "guest-redis-backup.log"),
        ]
    }

    private static func commandLogs() -> [RuntimeLogCollectionFileContract] {
        [
            .init(
                sourceID: .commandLog,
                sourceFileName: RuntimeFileNames.managerCommandLog,
                destinationScope: .productLogs,
                destinationFileName: "command.log",
                archivePrefix: "command.log"
            ),
        ]
    }

    private static func runtimeLog(
        _ sourceID: RuntimeLogCollectionFileSourceID,
        fileName: String
    ) -> RuntimeLogCollectionFileContract {
        .init(
            sourceID: sourceID,
            sourceFileName: fileName,
            destinationScope: .runtimeLogs,
            destinationFileName: fileName,
            archivePrefix: "runtime-\(fileName)"
        )
    }

    private static func guestLog(
        _ sourceID: RuntimeLogCollectionFileSourceID,
        fileName: String,
        archivePrefix: String
    ) -> RuntimeLogCollectionFileContract {
        .init(
            sourceID: sourceID,
            sourceFileName: fileName,
            destinationScope: .guestLogs,
            destinationFileName: fileName,
            archivePrefix: archivePrefix
        )
    }
}
