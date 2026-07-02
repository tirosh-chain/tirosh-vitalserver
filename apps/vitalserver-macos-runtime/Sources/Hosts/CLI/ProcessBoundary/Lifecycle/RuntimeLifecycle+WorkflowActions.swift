import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Workflow
import Errors

extension RuntimeLifecycle {
    func runtimeBestEffortResult(_ action: () throws -> Void) -> RuntimeBestEffortOperationResult {
        do {
            try action()
            return .completed
        } catch {
            return .failed(reason: RuntimeErrorDescription.describe(error))
        }
    }

    func runtimeRepairCompositionActions() -> RuntimeRepairCompositionActions {
        RuntimeRepairCompositionActions(
            requireRedisBackupCapability: {
                try requireGuestCapability(.redisBackup)
            },
            isVMServiceLoaded: vmServiceLoadedAction(),
            startVMService: startVMServiceAction(),
            runGuestDatastoreRepair: {
                try repairDatastoreThroughGuestControl()
            },
            restartProxyService: {
                try restartOrStartLaunchdService(.proxy)
            },
            restartWatchdogService: {
                try restartOrStartLaunchdService(.watchdog)
            },
            waitForHealth: waitForHealth,
            writeStatus: runtimeStatusWriterAction(),
            backupTimestamp: backupTimestamp,
            requireFreeSpace: { url, minimumBytes, operation in
                try storageMaintenance().requireFreeSpace(
                    at: url,
                    minimumBytes: minimumBytes,
                    operation: operation
                )
            },
            createReplacementVMDisk: createReplacementVMDisk,
            createRedisBackup: {
                do {
                    try createRedisBackup()
                    return .completed
                } catch {
                    return .failed(reason: RuntimeErrorDescription.describe(error))
                }
            },
            stopRuntimeServicesForVMDiskReplacement: {
                runtimeBestEffortResult {
                    try stopRuntimeServicesForVMDiskReplacement()
                }
            },
            startRuntimeServices: startRuntimeServicesForServiceControl,
            log: log
        )
    }

    func runtimeWorkflowStatusReporter() -> RuntimeWorkflowStatusReporter {
        RuntimeWorkflowStatusReporterComposition.make(
            writeStatus: runtimeStatusWriterAction(),
            writeProgress: runtimeProgressWriterAction(),
            log: log
        )
    }

    func runtimeStatusWriterAction() -> (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void {
        { status, operation, message in
            try writeRuntimeStatus(status, operation: operation, message: message)
        }
    }

    func runtimeProgressWriterAction() -> (RuntimeStepExecutionEvent) throws -> Void {
        { event in
            try writeRuntimeProgress(
                event.status,
                operation: event.operation,
                step: event.step,
                stepStatus: event.stepStatus,
                phase: event.phase,
                message: event.message
            )
        }
    }

    func createDirectoryAction() -> (URL, Bool) throws -> Void {
        { url, withIntermediateDirectories in
            try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
        }
    }

    func vmServiceLoadedAction() -> () -> Bool {
        {
            isLaunchdLoaded(.vm)
        }
    }

    func startVMServiceAction() -> () throws -> Void {
        {
            try startVMServiceForGuestOperation()
        }
    }

    func restartVMServiceAction() -> () throws -> Void {
        {
            try restartVMRuntimeForRepairOperation()
        }
    }

    func requestIDAction() -> () -> String {
        {
            UUID().uuidString
        }
    }

    func workflowPollingSleepAction() -> () -> Void {
        {
            sleeper.sleep(forTimeInterval: 3)
        }
    }
}
