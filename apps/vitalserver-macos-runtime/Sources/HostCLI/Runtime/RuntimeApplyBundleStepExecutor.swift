import Foundation
import Core
import Contracts

struct RuntimeApplyBundleStepExecutor {
    var stopRuntimeServices: () throws -> Void
    var runningVMProcessID: () throws -> pid_t
    var stopRuntimeServicesAfterGuestPoweroff: (pid_t) throws -> Void
    var prepareGuestShutdownForUpdate: (UpdateBundleManifest) throws -> Void
    var clearGuestShutdownPreparation: () throws -> Void
    var createDirectory: (URL, Bool) throws -> Void
    var fileSize: (URL) throws -> UInt64
    var replaceFile: (URL, URL) throws -> Void
    var replaceUpdateArtifacts: ([UpdateBundleArtifact], URL) throws -> Void
    var runMigrations: ([UpdateBundleMigration], URL) throws -> Void
    var refreshCloudInitSeedIfNeeded: (UpdateBundleManifest) throws -> Void
    var writeRuntimeVersion: (String, URL) throws -> Void
    var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    var activateGuestUpdateIfNeeded: (UpdateBundleManifest) throws -> Void
    var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    var log: (String) -> Void

    func execute(
        _ step: RuntimeWorkflowStep,
        preflight: ApplyBundlePreflightContext,
        rootfsBase: URL
    ) throws {
        switch step {
        case .stopRuntimeServices:
            if preflight.restartPolicy.restartVM {
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
            guard let stagedRootfs = preflight.stagedRootfs else {
                log("rootfs-base replacement skipped; bundle does not include rootfs-base")
                return
            }
            try createDirectory(rootfsBase.deletingLastPathComponent(), true)
            log(
                "replacing rootfs-base source=\(stagedRootfs.path) destination=\(rootfsBase.path) size=\(formatBytes(try fileSize(stagedRootfs)))"
            )
            try replaceFile(stagedRootfs, rootfsBase)
            log("rootfs-base replaced destination=\(rootfsBase.path)")
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
            throw LauncherError.unsupportedCommand("apply-bundle step \(step.rawValue)")
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
