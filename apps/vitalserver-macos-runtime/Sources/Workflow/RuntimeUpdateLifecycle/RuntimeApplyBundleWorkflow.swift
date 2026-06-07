import Application
import Contracts
import Domain
import Foundation
import Errors

public struct ApplyRuntimeBundleInput: Equatable, Sendable {
    public let bundleURL: URL

    public init(bundleURL: URL) {
        self.bundleURL = bundleURL
    }
}

public struct ApplyRuntimeBundleOperations {
    public var prepareLogs: () throws -> Void
    public var initialHealthSnapshot: () -> RuntimeHealthSnapshot
    public var preparePreflight: (URL) throws -> ApplyBundlePreflightContext
    public var rootfsBase: URL
    public var runningVMProcessID: () throws -> pid_t
    public var prepareGuestShutdownForUpdate: (UpdateBundleManifest) throws -> Void
    public var clearGuestShutdownPreparation: () throws -> Void
    public var stopRuntimeServicesAfterGuestPoweroff: (pid_t) throws -> Void
    public var stopRuntimeServices: () throws -> Void
    public var createDirectory: (URL, Bool) throws -> Void
    public var fileSize: (URL) throws -> UInt64
    public var replaceFile: (URL, URL) throws -> Void
    public var replaceUpdateArtifacts: ([UpdateBundleArtifact], URL) throws -> Void
    public var runMigrations: ([UpdateBundleMigration], URL) throws -> Void
    public var refreshCloudInitSeedIfNeeded: (UpdateBundleManifest) throws -> Void
    public var writeRuntimeVersion: (String, URL) throws -> Void
    public var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public var activateGuestUpdateIfNeeded: (UpdateBundleManifest) throws -> Void
    public var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public var rollback: (URL?) throws -> Void
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var writeBestEffortStatus: (RuntimeStatusLevel, RuntimeOperation, String) -> Void
    public var publishProgress: (RuntimeStepExecutionEvent) -> Void
    public var pruneOldRuntimeArtifacts: () throws -> Void
    public var describeError: (Error) -> String
    public var log: (String) -> Void

    public init(
        prepareLogs: @escaping () throws -> Void,
        initialHealthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        preparePreflight: @escaping (URL) throws -> ApplyBundlePreflightContext,
        rootfsBase: URL,
        runningVMProcessID: @escaping () throws -> pid_t,
        prepareGuestShutdownForUpdate: @escaping (UpdateBundleManifest) throws -> Void,
        clearGuestShutdownPreparation: @escaping () throws -> Void,
        stopRuntimeServicesAfterGuestPoweroff: @escaping (pid_t) throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        fileSize: @escaping (URL) throws -> UInt64,
        replaceFile: @escaping (URL, URL) throws -> Void,
        replaceUpdateArtifacts: @escaping ([UpdateBundleArtifact], URL) throws -> Void,
        runMigrations: @escaping ([UpdateBundleMigration], URL) throws -> Void,
        refreshCloudInitSeedIfNeeded: @escaping (UpdateBundleManifest) throws -> Void,
        writeRuntimeVersion: @escaping (String, URL) throws -> Void,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        activateGuestUpdateIfNeeded: @escaping (UpdateBundleManifest) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        rollback: @escaping (URL?) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeBestEffortStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        publishProgress: @escaping (RuntimeStepExecutionEvent) -> Void,
        pruneOldRuntimeArtifacts: @escaping () throws -> Void,
        describeError: @escaping (Error) -> String,
        log: @escaping (String) -> Void
    ) {
        self.prepareLogs = prepareLogs
        self.initialHealthSnapshot = initialHealthSnapshot
        self.preparePreflight = preparePreflight
        self.rootfsBase = rootfsBase
        self.runningVMProcessID = runningVMProcessID
        self.prepareGuestShutdownForUpdate = prepareGuestShutdownForUpdate
        self.clearGuestShutdownPreparation = clearGuestShutdownPreparation
        self.stopRuntimeServicesAfterGuestPoweroff = stopRuntimeServicesAfterGuestPoweroff
        self.stopRuntimeServices = stopRuntimeServices
        self.createDirectory = createDirectory
        self.fileSize = fileSize
        self.replaceFile = replaceFile
        self.replaceUpdateArtifacts = replaceUpdateArtifacts
        self.runMigrations = runMigrations
        self.refreshCloudInitSeedIfNeeded = refreshCloudInitSeedIfNeeded
        self.writeRuntimeVersion = writeRuntimeVersion
        self.startRuntimeServices = startRuntimeServices
        self.activateGuestUpdateIfNeeded = activateGuestUpdateIfNeeded
        self.waitForHealth = waitForHealth
        self.rollback = rollback
        self.writeStatus = writeStatus
        self.writeBestEffortStatus = writeBestEffortStatus
        self.publishProgress = publishProgress
        self.pruneOldRuntimeArtifacts = pruneOldRuntimeArtifacts
        self.describeError = describeError
        self.log = log
    }
}

public struct RuntimeApplyBundleWorkflow {
    public init() {}

    public func run(
        input: ApplyRuntimeBundleInput,
        operations: ApplyRuntimeBundleOperations
    ) throws {
        let update = ApplyRuntimeBundleUseCase()
        let startedPlan = update.applyBundleStartedPlan(inputPath: input.bundleURL.path)
        operations.log(startedPlan.logMessage)
        try operations.prepareLogs()
        try write(startedPlan, operations: operations)

        executeInitialHealthWarningPlan(update.initialHealthWarningPlan(
            snapshot: operations.initialHealthSnapshot()
        ), operations: operations)

        let preflight: ApplyBundlePreflightContext
        do {
            preflight = try operations.preparePreflight(input.bundleURL)
        } catch {
            executePreflightFailurePlan(update.applyBundlePreflightFailurePlan(
                reason: operations.describeError(error)
            ), operations: operations)
            throw error
        }

        do {
            let plan = update.planApplyBundle(for: preflight)
            try RuntimeOperationPlanRunner.run(
                plan: plan.operationPlan,
                status: .updating,
                execute: { step in
                    try executeApplyBundleStep(step, preflight: preflight, operations: operations, update: update)
                },
                publish: operations.publishProgress
            )
        } catch {
            executeFailureRecoveryPlan(update.applyBundleFailureRecoveryPlan(
                preflight: preflight,
                applyFailureReason: operations.describeError(error)
            ), operations: operations, update: update)
            throw error
        }

        pruneOldRuntimeArtifactsBestEffort(operations: operations, update: update)
        let completedPlan = update.applyBundleCompletedPlan(
            version: preflight.manifest.version,
            stagedBundlePath: preflight.stagedBundle.path
        )
        try write(completedPlan, operations: operations)
        operations.log(completedPlan.logMessage)
    }

    private func pruneOldRuntimeArtifactsBestEffort(
        operations: ApplyRuntimeBundleOperations,
        update: ApplyRuntimeBundleUseCase
    ) {
        do {
            try operations.pruneOldRuntimeArtifacts()
        } catch {
            operations.log(update.applyBundleArtifactCleanupFailedLogMessage(
                reason: operations.describeError(error)
            ))
        }
    }

    private func write(
        _ plan: UpdateRuntimeLoggedStatusPlan,
        operations: ApplyRuntimeBundleOperations
    ) throws {
        try operations.writeStatus(plan.status, plan.operation, plan.statusMessage)
    }

    private func executeInitialHealthWarningPlan(
        _ plan: ApplyRuntimeBundleInitialHealthWarningPlan,
        operations: ApplyRuntimeBundleOperations
    ) {
        switch plan {
        case .continueWithoutWarning:
            return
        case .continueWithWarning(let logMessage):
            operations.log(logMessage)
        }
    }

    private func executePreflightFailurePlan(
        _ plan: ApplyRuntimeBundlePreflightFailurePlan,
        operations: ApplyRuntimeBundleOperations
    ) {
        operations.writeBestEffortStatus(
            plan.statusPlan.status,
            plan.statusPlan.operation,
            plan.statusPlan.message
        )
    }

    private func executeFailureRecoveryPlan(
        _ plan: ApplyRuntimeBundleFailureRecoveryPlan,
        operations: ApplyRuntimeBundleOperations,
        update: ApplyRuntimeBundleUseCase
    ) {
        operations.log(plan.rollbackStartedPlan.logMessage)
        operations.writeBestEffortStatus(
            plan.rollbackStartedPlan.status,
            plan.rollbackStartedPlan.operation,
            plan.rollbackStartedPlan.statusMessage
        )
        do {
            try operations.rollback(plan.backup)
            try operations.startRuntimeServices(plan.restartPolicy)
            operations.writeBestEffortStatus(
                plan.rollbackCompletedPlan.status,
                plan.rollbackCompletedPlan.operation,
                plan.rollbackCompletedPlan.message
            )
        } catch {
            let rollbackFailedPlan = update.applyBundleRollbackFailedPlan(
                reason: operations.describeError(error)
            )
            operations.log(rollbackFailedPlan.logMessage)
            startRuntimeServicesBestEffort(plan.restartPolicy, operations: operations, update: update)
            operations.writeBestEffortStatus(
                rollbackFailedPlan.status,
                rollbackFailedPlan.operation,
                rollbackFailedPlan.statusMessage
            )
        }
    }

    private func startRuntimeServicesBestEffort(
        _ policy: RuntimeServiceRestartPolicy,
        operations: ApplyRuntimeBundleOperations,
        update: ApplyRuntimeBundleUseCase
    ) {
        do {
            try operations.startRuntimeServices(policy)
        } catch {
            operations.log(update.applyBundleRollbackFailureServiceRestartFailedLogMessage(
                reason: operations.describeError(error)
            ))
        }
    }

    private func executeApplyBundleStep(
        _ step: RuntimeWorkflowStep,
        preflight: ApplyBundlePreflightContext,
        operations: ApplyRuntimeBundleOperations,
        update: ApplyRuntimeBundleUseCase
    ) throws {
        try executeApplyBundleStepPlan(update.applyBundleStepExecutionPlan(
            step: step,
            preflight: preflight,
            rootfsBase: operations.rootfsBase
        ), operations: operations, update: update)
    }

    private func executeApplyBundleStepPlan(
        _ executionPlan: ApplyRuntimeBundleStepExecutionPlan,
        operations: ApplyRuntimeBundleOperations,
        update: ApplyRuntimeBundleUseCase
    ) throws {
        switch executionPlan {
        case .stopRuntimeServices(let stopPlan):
            try executeApplyBundleStopPlan(stopPlan, operations: operations, update: update)
        case .replaceRootfsBase(let rootfsPlan):
            try executeApplyBundleRootfsReplacementPlan(rootfsPlan, operations: operations, update: update)
        case .replaceUpdateArtifacts(let artifacts, let stagedBundle):
            try operations.replaceUpdateArtifacts(artifacts, stagedBundle)
        case .runMigrations(let migrations, let stagedBundle):
            try operations.runMigrations(migrations, stagedBundle)
        case .refreshCloudInitSeed(let manifest):
            try operations.refreshCloudInitSeedIfNeeded(manifest)
        case .writeRuntimeVersion(let version, let stagedBundle):
            try operations.writeRuntimeVersion(version, stagedBundle)
        case .startRuntimeServices(let restartPolicy):
            try operations.startRuntimeServices(restartPolicy)
        case .activateGuestUpdate(let manifest):
            try operations.activateGuestUpdateIfNeeded(manifest)
        case .waitRuntimeHealth(let restartPolicy):
            try operations.waitForHealth(restartPolicy)
        case .unsupported(let failureMessage):
            throw ApplyRuntimeBundleCompositionError.operationFailed(failureMessage)
        }
    }

    private func executeApplyBundleStopPlan(
        _ stopPlan: ApplyRuntimeBundleStopExecutionPlan,
        operations: ApplyRuntimeBundleOperations,
        update: ApplyRuntimeBundleUseCase
    ) throws {
        switch stopPlan {
        case .prepareGuestShutdownAndStopServicesAfterPoweroff(let manifest):
            let expectedVMProcessID = try operations.runningVMProcessID()
            operations.log(update.capturedVMProcessBeforeGuestUpdateShutdownLogMessage(
                processID: expectedVMProcessID
            ))
            defer {
                clearGuestShutdownPreparationAfterRuntimeStop(operations: operations, update: update)
            }
            try operations.prepareGuestShutdownForUpdate(manifest)
            try operations.stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID)
        case .stopServicesDirectly:
            try operations.stopRuntimeServices()
        }
    }

    private func executeApplyBundleRootfsReplacementPlan(
        _ rootfsPlan: ApplyRuntimeBundleRootfsReplacementPlan,
        operations: ApplyRuntimeBundleOperations,
        update: ApplyRuntimeBundleUseCase
    ) throws {
        switch rootfsPlan {
        case .skip(let logMessage):
            operations.log(logMessage)
        case .replace(let stagedRootfs, let rootfsBase):
            try operations.createDirectory(rootfsBase.deletingLastPathComponent(), true)
            let stagedRootfsBytes = try operations.fileSize(stagedRootfs)
            let executionPlan = update.rootfsReplacementExecutionPlan(
                stagedRootfs: stagedRootfs,
                rootfsBase: rootfsBase,
                stagedRootfsBytes: stagedRootfsBytes
            )
            operations.log(executionPlan.startedLogMessage)
            try operations.replaceFile(stagedRootfs, rootfsBase)
            operations.log(executionPlan.completedLogMessage)
        }
    }

    private func clearGuestShutdownPreparationAfterRuntimeStop(
        operations: ApplyRuntimeBundleOperations,
        update: ApplyRuntimeBundleUseCase
    ) {
        do {
            try operations.clearGuestShutdownPreparation()
        } catch {
            operations.log(update.guestShutdownPreparationCleanupFailedLogMessage(
                reason: operations.describeError(error)
            ))
        }
    }
}
