import Application
import Bootstrap
import Contracts
import Domain
import Foundation

public struct RuntimeRepairCompositionActions {
    public let requireRedisBackupCapability: () throws -> Void
    public let isVMServiceLoaded: () -> Bool
    public let startVMService: () throws -> Void
    public let runGuestDatastoreRepair: () throws -> RuntimeGuestControlServiceOperation
    public let restartProxyService: () throws -> Void
    public let restartWatchdogService: () throws -> Void
    public let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let backupTimestamp: () -> String
    public let requireFreeSpace: (URL, UInt64, String) throws -> Void
    public let createReplacementVMDisk: (RepairRuntimeVMDiskReplacementBuildPlan) throws -> Void
    public let createVitalServerBackup: () -> RuntimeBestEffortOperationResult
    public let stopRuntimeServicesForVMDiskReplacement: () -> RuntimeBestEffortOperationResult
    public let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public let log: (String) -> Void

    public init(
        requireRedisBackupCapability: @escaping () throws -> Void,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        runGuestDatastoreRepair: @escaping () throws -> RuntimeGuestControlServiceOperation,
        restartProxyService: @escaping () throws -> Void,
        restartWatchdogService: @escaping () throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        backupTimestamp: @escaping () -> String,
        requireFreeSpace: @escaping (URL, UInt64, String) throws -> Void,
        createReplacementVMDisk: @escaping (RepairRuntimeVMDiskReplacementBuildPlan) throws -> Void,
        createVitalServerBackup: @escaping () -> RuntimeBestEffortOperationResult,
        stopRuntimeServicesForVMDiskReplacement: @escaping () -> RuntimeBestEffortOperationResult,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireRedisBackupCapability = requireRedisBackupCapability
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.runGuestDatastoreRepair = runGuestDatastoreRepair
        self.restartProxyService = restartProxyService
        self.restartWatchdogService = restartWatchdogService
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.backupTimestamp = backupTimestamp
        self.requireFreeSpace = requireFreeSpace
        self.createReplacementVMDisk = createReplacementVMDisk
        self.createVitalServerBackup = createVitalServerBackup
        self.stopRuntimeServicesForVMDiskReplacement = stopRuntimeServicesForVMDiskReplacement
        self.startRuntimeServices = startRuntimeServices
        self.log = log
    }
}

public extension RuntimeApplicationContainer {
    func makeRuntimeDatastoreRepairComposition(
        actions: RuntimeRepairCompositionActions
    ) -> RuntimeDatastoreRepairComposition {
        RuntimeDatastoreRepairComposition(
            context: RuntimeDatastoreRepairCompositionContext(),
            operations: RuntimeDatastoreRepairCompositionOperations(
                isVMServiceLoaded: actions.isVMServiceLoaded,
                startVMService: actions.startVMService,
                runGuestDatastoreRepair: actions.runGuestDatastoreRepair,
                restartProxyService: actions.restartProxyService,
                restartWatchdogService: actions.restartWatchdogService,
                waitForHealth: actions.waitForHealth,
                writeStatus: actions.writeStatus,
                log: actions.log
            )
        )
    }

    func makeRuntimeVMDiskRepairComposition(
        actions: RuntimeRepairCompositionActions
    ) -> RuntimeVMDiskRepairComposition {
        RuntimeVMDiskRepairComposition(
            context: RuntimeVMDiskRepairCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeVMDiskRepairCompositionOperations(
                fileStore: fileStore,
                requireFreeSpace: actions.requireFreeSpace,
                createReplacementVMDisk: actions.createReplacementVMDisk,
                createVitalServerBackup: actions.createVitalServerBackup,
                stopRuntimeServicesForVMDiskReplacement: actions.stopRuntimeServicesForVMDiskReplacement,
                startRuntimeServices: actions.startRuntimeServices,
                waitForHealth: actions.waitForHealth,
                writeStatus: actions.writeStatus,
                timestamp: actions.backupTimestamp,
                log: actions.log
            )
        )
    }
}
