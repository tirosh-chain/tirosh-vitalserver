import Application
import Bootstrap
import Contracts
import Domain
import Foundation

public struct RuntimeRepairCompositionActions {
    public let requireDatastoreRepairCapability: () throws -> Void
    public let requireRedisBackupCapability: () throws -> Void
    public let isVMServiceLoaded: () -> Bool
    public let startVMService: () throws -> Void
    public let restartVMService: () throws -> Void
    public let restartProxyService: () throws -> Void
    public let restartWatchdogService: () throws -> Void
    public let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let requestID: () -> String
    public let timestamp: () -> String
    public let backupTimestamp: () -> String
    public let requireFreeSpace: (URL, UInt64, String) throws -> Void
    public let createReplacementVMDisk: (RepairRuntimeVMDiskReplacementBuildPlan) throws -> Void
    public let createRedisBackup: () -> RuntimeBestEffortOperationResult
    public let stopRuntimeServicesForVMDiskReplacement: () -> RuntimeBestEffortOperationResult
    public let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public let log: (String) -> Void

    public init(
        requireDatastoreRepairCapability: @escaping () throws -> Void,
        requireRedisBackupCapability: @escaping () throws -> Void,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        restartVMService: @escaping () throws -> Void,
        restartProxyService: @escaping () throws -> Void,
        restartWatchdogService: @escaping () throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        requestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        backupTimestamp: @escaping () -> String,
        requireFreeSpace: @escaping (URL, UInt64, String) throws -> Void,
        createReplacementVMDisk: @escaping (RepairRuntimeVMDiskReplacementBuildPlan) throws -> Void,
        createRedisBackup: @escaping () -> RuntimeBestEffortOperationResult,
        stopRuntimeServicesForVMDiskReplacement: @escaping () -> RuntimeBestEffortOperationResult,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireDatastoreRepairCapability = requireDatastoreRepairCapability
        self.requireRedisBackupCapability = requireRedisBackupCapability
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.restartVMService = restartVMService
        self.restartProxyService = restartProxyService
        self.restartWatchdogService = restartWatchdogService
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.requestID = requestID
        self.timestamp = timestamp
        self.backupTimestamp = backupTimestamp
        self.requireFreeSpace = requireFreeSpace
        self.createReplacementVMDisk = createReplacementVMDisk
        self.createRedisBackup = createRedisBackup
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
            context: RuntimeDatastoreRepairCompositionContext(
                guestRunDirectory: installedPaths.guestRunDirectory
            ),
            operations: RuntimeDatastoreRepairCompositionOperations(
                fileStore: fileStore,
                guestGateway: guestGateway,
                requireCapability: actions.requireDatastoreRepairCapability,
                isVMServiceLoaded: actions.isVMServiceLoaded,
                startVMService: actions.startVMService,
                restartVMService: actions.restartVMService,
                restartProxyService: actions.restartProxyService,
                restartWatchdogService: actions.restartWatchdogService,
                waitForHealth: actions.waitForHealth,
                writeStatus: actions.writeStatus,
                requestID: actions.requestID,
                timestamp: actions.timestamp,
                sleep: {
                    sleeper.sleep(forTimeInterval: 3)
                },
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
                createRedisBackup: actions.createRedisBackup,
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
