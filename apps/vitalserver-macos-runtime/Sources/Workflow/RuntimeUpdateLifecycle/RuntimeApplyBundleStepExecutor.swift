import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeApplyBundleStepExecutor {
    public var stopRuntimeServices: () throws -> Void
    public var runningVMProcessID: () throws -> pid_t
    public var stopRuntimeServicesAfterGuestPoweroff: (pid_t) throws -> Void
    public var prepareGuestShutdownForUpdate: (UpdateBundleManifest) throws -> Void
    public var clearGuestShutdownPreparation: () throws -> Void
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
    public var log: (String) -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        stopRuntimeServices: @escaping () throws -> Void,
        runningVMProcessID: @escaping () throws -> pid_t,
        stopRuntimeServicesAfterGuestPoweroff: @escaping (pid_t) throws -> Void,
        prepareGuestShutdownForUpdate: @escaping (UpdateBundleManifest) throws -> Void,
        clearGuestShutdownPreparation: @escaping () throws -> Void,
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
        log: @escaping (String) -> Void
    ) {
        self.stopRuntimeServices = stopRuntimeServices
        self.runningVMProcessID = runningVMProcessID
        self.stopRuntimeServicesAfterGuestPoweroff = stopRuntimeServicesAfterGuestPoweroff
        self.prepareGuestShutdownForUpdate = prepareGuestShutdownForUpdate
        self.clearGuestShutdownPreparation = clearGuestShutdownPreparation
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
        self.log = log
    }

    public func execute(
        _ step: RuntimeWorkflowStep,
        preflight: ApplyBundlePreflightContext,
        rootfsBase: URL
    ) throws {
        let executionPlan = useCase.applyBundleStepExecutionPlan(
            step: step,
            preflight: preflight,
            rootfsBase: rootfsBase
        )

        switch executionPlan {
        case .stopRuntimeServices(let preparesGuestShutdown, let manifest):
            if preparesGuestShutdown {
                let expectedVMProcessID = try runningVMProcessID()
                log(useCase.capturedVMProcessBeforeGuestUpdateShutdownLogMessage(processID: expectedVMProcessID))
                try prepareGuestShutdownForUpdate(manifest)
                do {
                    defer { clearGuestShutdownPreparationAfterRuntimeStop() }
                    try stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID)
                }
                return
            }
            try stopRuntimeServices()
        case .replaceRootfsBase(let rootfsPlan):
            guard let stagedRootfs = rootfsPlan.stagedRootfs, rootfsPlan.shouldReplace else {
                if let skippedLogMessage = rootfsPlan.skippedLogMessage {
                    log(skippedLogMessage)
                }
                return
            }
            try createDirectory(rootfsPlan.rootfsBase.deletingLastPathComponent(), true)
            let executionPlan = useCase.rootfsReplacementExecutionPlan(
                stagedRootfs: stagedRootfs,
                rootfsBase: rootfsPlan.rootfsBase,
                stagedRootfsBytes: try fileSize(stagedRootfs)
            )
            log(executionPlan.startedLogMessage)
            try replaceFile(stagedRootfs, rootfsPlan.rootfsBase)
            log(executionPlan.completedLogMessage)
        case .replaceUpdateArtifacts(let artifacts, let stagedBundle):
            try replaceUpdateArtifacts(artifacts, stagedBundle)
        case .runMigrations(let migrations, let stagedBundle):
            try runMigrations(migrations, stagedBundle)
        case .refreshCloudInitSeed(let manifest):
            try refreshCloudInitSeedIfNeeded(manifest)
        case .writeRuntimeVersion(let version, let stagedBundle):
            try writeRuntimeVersion(version, stagedBundle)
        case .startRuntimeServices(let restartPolicy):
            try startRuntimeServices(restartPolicy)
        case .activateGuestUpdate(let manifest):
            try activateGuestUpdateIfNeeded(manifest)
        case .waitRuntimeHealth(let restartPolicy):
            try waitForHealth(restartPolicy)
        case .unsupported(let failureMessage):
            throw RuntimeApplyBundleWorkflowError.operationFailed(failureMessage)
        }
    }

    private func clearGuestShutdownPreparationAfterRuntimeStop() {
        do {
            try clearGuestShutdownPreparation()
        } catch {
            log(useCase.guestShutdownPreparationCleanupFailedLogMessage(reason: String(describing: error)))
        }
    }
}
