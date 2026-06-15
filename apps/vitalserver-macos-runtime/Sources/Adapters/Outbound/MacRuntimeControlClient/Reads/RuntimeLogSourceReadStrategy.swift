import Foundation
import RuntimeControl

enum RuntimeLogSourceReadStrategy {
    case direct(RuntimeLogFileSource)
    case refreshThenRead(RuntimeLogFileSource)
    case refreshWhenPrimaryMissing(RuntimeLogFileSource)
}

struct RuntimeLogFileSource {
    var path: String
    var sourcePath: String?
}

struct RuntimeLogSourceReadStrategyCatalog {
    func strategy(for sourceID: RuntimeLogSource) -> RuntimeLogSourceReadStrategy {
        switch sourceID {
        case .helperMessage:
            return .direct(RuntimeLogFileSource(
                path: RuntimeControlClientConstants.Paths.helperMessageLogFile,
                sourcePath: nil
            ))
        case .command:
            return .direct(RuntimeLogFileSource(
                path: RuntimeControlClientConstants.Paths.commandLogFile,
                sourcePath: nil
            ))
        case .install:
            return .refreshThenRead(RuntimeLogFileSource(
                path: RuntimeControlClientConstants.Paths.installLog,
                sourcePath: nil
            ))
        case .launcher:
            return .refreshThenRead(collectionLogSource(for: sourceID))
        case .vmLaunchOutput:
            return .refreshThenRead(collectionLogSource(for: sourceID))
        case .vmLaunchError:
            return .refreshThenRead(collectionLogSource(for: sourceID))
        case .proxyOutput:
            return .refreshThenRead(collectionLogSource(for: sourceID))
        case .proxyError:
            return .refreshThenRead(collectionLogSource(for: sourceID))
        case .watchdog:
            return .refreshThenRead(collectionLogSource(for: sourceID))
        case .updateActivation:
            return .refreshThenRead(collectionLogSource(for: sourceID))
        case .updateShutdown:
            return .refreshThenRead(collectionLogSource(for: sourceID))
        case .containers:
            return .refreshWhenPrimaryMissing(collectionLogSource(for: sourceID))
        }
    }

    private func collectionLogSource(for sourceID: RuntimeLogSource) -> RuntimeLogFileSource {
        guard let contract = RuntimeLogCollectionSourceContract.fileCopy(for: sourceID) else {
            preconditionFailure("missing runtime log collection file contract for \(sourceID.rawValue)")
        }
        return RuntimeLogFileSource(
            path: destinationPath(for: contract),
            sourcePath: sourcePath(for: contract)
        )
    }

    private func destinationPath(for contract: RuntimeLogCollectionFileContract) -> String {
        (destinationRootPath(for: contract.destinationScope) as NSString)
            .appendingPathComponent(contract.destinationFileName)
    }

    private func sourcePath(for contract: RuntimeLogCollectionFileContract) -> String {
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
            return (RuntimeControlClientConstants.Paths.runtimeLogSources as NSString)
                .appendingPathComponent(contract.sourceFileName)
        case .bootstrapLog:
            return RuntimeControlClientConstants.Paths.bootstrapLogSource
        case .containerLog:
            return RuntimeControlClientConstants.Paths.containerLogSource
        case .updateActivationLog:
            return RuntimeControlClientConstants.Paths.updateActivationLogSource
        case .updateShutdownLog:
            return RuntimeControlClientConstants.Paths.updateShutdownLogSource
        case .datastoreRepairLog:
            return RuntimeControlClientConstants.Paths.datastoreRepairLogSource
        case .redisBackupLog:
            return RuntimeControlClientConstants.Paths.redisBackupLogSource
        case .commandLog:
            return RuntimeControlClientConstants.Paths.commandLogFile
        }
    }

    private func destinationRootPath(for scope: RuntimeLogCollectionDestinationScope) -> String {
        switch scope {
        case .runtimeLogs:
            return RuntimeControlClientConstants.Paths.runtimeLogs
        case .guestLogs:
            return RuntimeControlClientConstants.Paths.guestLogs
        case .productLogs:
            return RuntimeControlClientConstants.Paths.productLogs
        }
    }

}
