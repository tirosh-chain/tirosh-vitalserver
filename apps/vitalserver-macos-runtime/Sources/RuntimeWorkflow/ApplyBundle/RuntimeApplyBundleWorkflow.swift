import Contracts
import Core
import Foundation

public struct RuntimeApplyBundleWorkflowContext {
    public var backupsDirectory: URL
    public var logsDirectory: URL
    public var rootfsBase: URL
    public var vmDisk: URL
    public var updateFreeSpaceMarginBytes: UInt64

    public init(
        backupsDirectory: URL,
        logsDirectory: URL,
        rootfsBase: URL,
        vmDisk: URL,
        updateFreeSpaceMarginBytes: UInt64
    ) {
        self.backupsDirectory = backupsDirectory
        self.logsDirectory = logsDirectory
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.updateFreeSpaceMarginBytes = updateFreeSpaceMarginBytes
    }
}

public struct RuntimeApplyBundleWorkflowOperations {
    public var stageBundle: (URL) throws -> URL
    public var loadManifest: (URL) throws -> UpdateBundleManifest
    public var fileExists: (URL) -> Bool
    public var createDirectory: (URL, Bool) throws -> Void
    public var fileSize: (URL) throws -> UInt64
    public var directorySize: (URL) throws -> UInt64
    public var requireFreeSpace: (URL, UInt64, RuntimeOperation) throws -> Void
    public var checkCompatibility: (UpdateBundleManifest) throws -> Void
    public var serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    public var runtimeHealthSnapshot: () -> RuntimeHealthSnapshot
    public var requireGuestCapability: (RuntimeGuestCapabilityRequirement) throws -> Void
    public var createBackup: (String) throws -> URL
    public var rotateRuntimeLogs: () throws -> Void
    public var rollback: (URL) throws -> Void
    public var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public var statusReporter: RuntimeWorkflowStatusReporter
    public var pruneOldRuntimeArtifacts: () throws -> Void
    public var reasonText: ([RuntimeFailureReason]) -> String
    public var stopRuntimeServices: () throws -> Void
    public var runningVMProcessID: () throws -> pid_t
    public var stopRuntimeServicesAfterGuestPoweroff: (pid_t) throws -> Void
    public var prepareGuestShutdownForUpdate: (UpdateBundleManifest) throws -> Void
    public var clearGuestShutdownPreparation: () throws -> Void
    public var replaceFile: (URL, URL) throws -> Void
    public var replaceUpdateArtifacts: ([UpdateBundleArtifact], URL) throws -> Void
    public var runMigrations: ([UpdateBundleMigration], URL) throws -> Void
    public var refreshCloudInitSeedIfNeeded: (UpdateBundleManifest) throws -> Void
    public var writeRuntimeVersion: (String, URL) throws -> Void
    public var activateGuestUpdateIfNeeded: (UpdateBundleManifest) throws -> Void
    public var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public var log: (String) -> Void

    public init(
        stageBundle: @escaping (URL) throws -> URL,
        loadManifest: @escaping (URL) throws -> UpdateBundleManifest,
        fileExists: @escaping (URL) -> Bool,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        fileSize: @escaping (URL) throws -> UInt64,
        directorySize: @escaping (URL) throws -> UInt64,
        requireFreeSpace: @escaping (URL, UInt64, RuntimeOperation) throws -> Void,
        checkCompatibility: @escaping (UpdateBundleManifest) throws -> Void,
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy,
        runtimeHealthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        requireGuestCapability: @escaping (RuntimeGuestCapabilityRequirement) throws -> Void,
        createBackup: @escaping (String) throws -> URL,
        rotateRuntimeLogs: @escaping () throws -> Void,
        rollback: @escaping (URL) throws -> Void,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        statusReporter: RuntimeWorkflowStatusReporter,
        pruneOldRuntimeArtifacts: @escaping () throws -> Void,
        reasonText: @escaping ([RuntimeFailureReason]) -> String,
        stopRuntimeServices: @escaping () throws -> Void,
        runningVMProcessID: @escaping () throws -> pid_t,
        stopRuntimeServicesAfterGuestPoweroff: @escaping (pid_t) throws -> Void,
        prepareGuestShutdownForUpdate: @escaping (UpdateBundleManifest) throws -> Void,
        clearGuestShutdownPreparation: @escaping () throws -> Void,
        replaceFile: @escaping (URL, URL) throws -> Void,
        replaceUpdateArtifacts: @escaping ([UpdateBundleArtifact], URL) throws -> Void,
        runMigrations: @escaping ([UpdateBundleMigration], URL) throws -> Void,
        refreshCloudInitSeedIfNeeded: @escaping (UpdateBundleManifest) throws -> Void,
        writeRuntimeVersion: @escaping (String, URL) throws -> Void,
        activateGuestUpdateIfNeeded: @escaping (UpdateBundleManifest) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.stageBundle = stageBundle
        self.loadManifest = loadManifest
        self.fileExists = fileExists
        self.createDirectory = createDirectory
        self.fileSize = fileSize
        self.directorySize = directorySize
        self.requireFreeSpace = requireFreeSpace
        self.checkCompatibility = checkCompatibility
        self.serviceRestartPolicy = serviceRestartPolicy
        self.runtimeHealthSnapshot = runtimeHealthSnapshot
        self.requireGuestCapability = requireGuestCapability
        self.createBackup = createBackup
        self.rotateRuntimeLogs = rotateRuntimeLogs
        self.rollback = rollback
        self.startRuntimeServices = startRuntimeServices
        self.statusReporter = statusReporter
        self.pruneOldRuntimeArtifacts = pruneOldRuntimeArtifacts
        self.reasonText = reasonText
        self.stopRuntimeServices = stopRuntimeServices
        self.runningVMProcessID = runningVMProcessID
        self.stopRuntimeServicesAfterGuestPoweroff = stopRuntimeServicesAfterGuestPoweroff
        self.prepareGuestShutdownForUpdate = prepareGuestShutdownForUpdate
        self.clearGuestShutdownPreparation = clearGuestShutdownPreparation
        self.replaceFile = replaceFile
        self.replaceUpdateArtifacts = replaceUpdateArtifacts
        self.runMigrations = runMigrations
        self.refreshCloudInitSeedIfNeeded = refreshCloudInitSeedIfNeeded
        self.writeRuntimeVersion = writeRuntimeVersion
        self.activateGuestUpdateIfNeeded = activateGuestUpdateIfNeeded
        self.waitForHealth = waitForHealth
        self.log = log
    }
}

public struct RuntimeApplyBundleWorkflow {
    public var context: RuntimeApplyBundleWorkflowContext
    public var operations: RuntimeApplyBundleWorkflowOperations

    public init(
        context: RuntimeApplyBundleWorkflowContext,
        operations: RuntimeApplyBundleWorkflowOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func applyBundle(_ bundleURL: URL) throws {
        try runtimeApplyBundleRunner().run(bundleURL: bundleURL)
        operations.log("mutable VM disk preserved path=\(context.vmDisk.path)")
    }

    private func runtimeApplyBundleRunner() -> RuntimeApplyBundleRunner {
        RuntimeApplyBundleRunner(
            prepareLogs: prepareApplyBundleLogs,
            initialHealthSnapshot: operations.runtimeHealthSnapshot,
            preparePreflight: prepareApplyBundlePreflight,
            executeStep: executeApplyBundleStep,
            rollback: operations.rollback,
            startRuntimeServices: operations.startRuntimeServices,
            statusReporter: operations.statusReporter,
            pruneOldRuntimeArtifacts: operations.pruneOldRuntimeArtifacts,
            reasonText: operations.reasonText
        )
    }

    private func prepareApplyBundleLogs() {
        do {
            try operations.createDirectory(context.logsDirectory, true)
        } catch {
            operations.log("bundle apply log directory preparation failed error=\(error)")
        }
        do {
            try operations.rotateRuntimeLogs()
        } catch {
            operations.log("bundle apply log rotation failed error=\(error)")
        }
    }

    private func prepareApplyBundlePreflight(_ bundleURL: URL) throws -> ApplyBundlePreflightContext {
        try RuntimeApplyBundlePreflightRunner(
            stageBundle: operations.stageBundle,
            loadManifest: operations.loadManifest,
            fileExists: operations.fileExists,
            createDirectory: operations.createDirectory,
            fileSize: operations.fileSize,
            requireFreeSpace: operations.requireFreeSpace,
            checkCompatibility: operations.checkCompatibility,
            serviceRestartPolicy: operations.serviceRestartPolicy,
            runtimeHealthSnapshot: operations.runtimeHealthSnapshot,
            requireGuestCapability: operations.requireGuestCapability,
            createBackup: operations.createBackup,
            directorySize: operations.directorySize,
            updateFreeSpaceMarginBytes: context.updateFreeSpaceMarginBytes,
            log: operations.log
        ).prepare(
            bundleURL: bundleURL,
            backupsDirectory: context.backupsDirectory,
            rootfsBase: context.rootfsBase
        )
    }

    private func executeApplyBundleStep(
        _ step: RuntimeWorkflowStep,
        preflight: ApplyBundlePreflightContext
    ) throws {
        try RuntimeApplyBundleStepExecutor(
            stopRuntimeServices: operations.stopRuntimeServices,
            runningVMProcessID: operations.runningVMProcessID,
            stopRuntimeServicesAfterGuestPoweroff: operations.stopRuntimeServicesAfterGuestPoweroff,
            prepareGuestShutdownForUpdate: operations.prepareGuestShutdownForUpdate,
            clearGuestShutdownPreparation: operations.clearGuestShutdownPreparation,
            createDirectory: operations.createDirectory,
            fileSize: operations.fileSize,
            replaceFile: operations.replaceFile,
            replaceUpdateArtifacts: operations.replaceUpdateArtifacts,
            runMigrations: operations.runMigrations,
            refreshCloudInitSeedIfNeeded: operations.refreshCloudInitSeedIfNeeded,
            writeRuntimeVersion: operations.writeRuntimeVersion,
            startRuntimeServices: operations.startRuntimeServices,
            activateGuestUpdateIfNeeded: operations.activateGuestUpdateIfNeeded,
            waitForHealth: operations.waitForHealth,
            log: operations.log
        ).execute(step, preflight: preflight, rootfsBase: context.rootfsBase)
    }
}
