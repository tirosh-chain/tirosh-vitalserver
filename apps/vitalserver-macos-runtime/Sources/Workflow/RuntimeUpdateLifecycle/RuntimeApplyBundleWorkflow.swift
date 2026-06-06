import Application
import Contracts
import Domain
import Foundation
import Errors

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
    public var loadStagedManifest: (URL) throws -> UpdateBundleManifest
    public var observeRootfsStorage: (URL, URL) throws -> ApplyRuntimeBundleRootfsStorageObservation
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
    public var describeError: (Error) -> String
    public var log: (String) -> Void

    public init(
        stageBundle: @escaping (URL) throws -> URL,
        loadStagedManifest: @escaping (URL) throws -> UpdateBundleManifest,
        observeRootfsStorage: @escaping (URL, URL) throws -> ApplyRuntimeBundleRootfsStorageObservation,
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
        describeError: @escaping (Error) -> String,
        log: @escaping (String) -> Void
    ) {
        self.stageBundle = stageBundle
        self.loadStagedManifest = loadStagedManifest
        self.observeRootfsStorage = observeRootfsStorage
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
        self.describeError = describeError
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
        operations.log(UpdateRuntimeUseCase().mutableVMDiskPreservedLogMessage(path: context.vmDisk.path))
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
            pruneOldRuntimeArtifacts: operations.pruneOldRuntimeArtifacts
        )
    }

    private func prepareApplyBundleLogs() {
        do {
            try operations.createDirectory(context.logsDirectory, true)
        } catch {
            operations.log(UpdateRuntimeUseCase().applyBundleLogDirectoryPreparationFailedLogMessage(
                reason: operations.describeError(error)
            ))
        }
        do {
            try operations.rotateRuntimeLogs()
        } catch {
            operations.log(UpdateRuntimeUseCase().applyBundleLogRotationFailedLogMessage(
                reason: operations.describeError(error)
            ))
        }
    }

    private func prepareApplyBundlePreflight(_ bundleURL: URL) throws -> ApplyBundlePreflightContext {
        try RuntimeApplyBundlePreflightRunner(
            stageBundle: operations.stageBundle,
            loadStagedManifest: operations.loadStagedManifest,
            observeRootfsStorage: operations.observeRootfsStorage,
            createDirectory: operations.createDirectory,
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
            describeError: operations.describeError,
            log: operations.log
        ).execute(step, preflight: preflight, rootfsBase: context.rootfsBase)
    }
}
