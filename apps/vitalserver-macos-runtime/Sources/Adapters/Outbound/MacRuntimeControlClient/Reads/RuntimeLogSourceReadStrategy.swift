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
        let installed = InstalledRuntimePaths.defaultInstalled
        switch sourceID {
        case .helperMessage:
            return .direct(RuntimeLogFileSource(
                path: installed.managerHelperMessageLog.path,
                sourcePath: nil
            ))
        case .command:
            return .direct(RuntimeLogFileSource(
                path: installed.managerCommandLog.path,
                sourcePath: nil
            ))
        case .install:
            return .refreshThenRead(RuntimeLogFileSource(
                path: installed.installLog.path,
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
            return (installed.logsDirectory.path as NSString)
                .appendingPathComponent(contract.sourceFileName)
        case .bootstrapLog:
            return installed.bootstrapLog.path
        case .containerLog:
            return installed.containerLogs.path
        case .updateActivationLog:
            return installed.updateActivationLog.path
        case .updateShutdownLog:
            return installed.updateShutdownLog.path
        case .datastoreRepairLog:
            return installed.datastoreRepairLog.path
        case .redisBackupLog:
            return installed.redisBackupLog.path
        case .commandLog:
            return installed.managerCommandLog.path
        }
    }

    private func destinationRootPath(for scope: RuntimeLogCollectionDestinationScope) -> String {
        let installed = InstalledRuntimePaths.defaultInstalled
        switch scope {
        case .runtimeLogs:
            return installed.centralRuntimeLogsDirectory.path
        case .guestLogs:
            return installed.centralGuestLogsDirectory.path
        case .productLogs:
            return installed.productLogsDirectory.path
        }
    }

}
