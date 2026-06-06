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
        switch step {
        case .stopRuntimeServices:
            let stopPlan = useCase.stopPlan(restartPolicy: preflight.restartPolicy)
            if stopPlan.preparesGuestShutdown {
                let expectedVMProcessID = try runningVMProcessID()
                log("captured VM process before guest update shutdown pid=\(expectedVMProcessID)")
                try prepareGuestShutdownForUpdate(preflight.manifest)
                do {
                    defer { clearGuestShutdownPreparationAfterRuntimeStop() }
                    try stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID)
                }
                return
            }
            try stopRuntimeServices()
        case .replaceRootfsBase:
            let rootfsPlan = useCase.rootfsReplacementPlan(
                stagedRootfs: preflight.stagedRootfs,
                rootfsBase: rootfsBase
            )
            guard let stagedRootfs = rootfsPlan.stagedRootfs, rootfsPlan.shouldReplace else {
                if let skippedLogMessage = rootfsPlan.skippedLogMessage {
                    log(skippedLogMessage)
                }
                return
            }
            try createDirectory(rootfsPlan.rootfsBase.deletingLastPathComponent(), true)
            log(
                "replacing rootfs-base source=\(stagedRootfs.path) destination=\(rootfsPlan.rootfsBase.path) size=\(formatBytes(try fileSize(stagedRootfs)))"
            )
            try replaceFile(stagedRootfs, rootfsPlan.rootfsBase)
            log("rootfs-base replaced destination=\(rootfsPlan.rootfsBase.path)")
        case .replaceUpdateArtifacts:
            try replaceUpdateArtifacts(preflight.manifest.artifacts, preflight.stagedBundle)
        case .runMigrations:
            try runMigrations(preflight.manifest.migrations, preflight.stagedBundle)
        case .refreshCloudInitSeed:
            try refreshCloudInitSeedIfNeeded(preflight.manifest)
        case .writeRuntimeVersion:
            try writeRuntimeVersion(preflight.manifest.version, preflight.stagedBundle)
        case .startRuntimeServices:
            try startRuntimeServices(preflight.restartPolicy)
        case .activateGuestUpdate:
            try activateGuestUpdateIfNeeded(preflight.manifest)
        case .waitRuntimeHealth:
            try waitForHealth(preflight.restartPolicy)
        default:
            throw RuntimeApplyBundleWorkflowError.operationFailed("unsupported command: apply-bundle step \(step.rawValue)")
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }

    private func clearGuestShutdownPreparationAfterRuntimeStop() {
        do {
            try clearGuestShutdownPreparation()
        } catch {
            log("guest shutdown preparation cleanup failed error=\(error)")
        }
    }
}
