import Foundation
import Core
import Contracts

struct RuntimeApplyBundlePreflightRunner {
    var stageBundle: (URL) throws -> URL
    var loadManifest: (URL) throws -> UpdateBundleManifest
    var fileExists: (URL) -> Bool
    var createDirectory: (URL, Bool) throws -> Void
    var fileSize: (URL) throws -> UInt64
    var requireFreeSpace: (URL, UInt64, RuntimeOperation) throws -> Void
    var checkCompatibility: (UpdateBundleManifest) throws -> Void
    var serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    var runtimeHealthSnapshot: () -> RuntimeHealthSnapshot
    var requireGuestCapability: (RuntimeGuestCapabilityRequirement) throws -> Void
    var createBackup: (String) throws -> URL
    var directorySize: (URL) throws -> UInt64
    var log: (String) -> Void

    func prepare(bundleURL: URL, backupsDirectory: URL, rootfsBase: URL) throws -> ApplyBundlePreflightContext {
        let stagedBundle = try stageBundle(bundleURL)
        let manifest = try loadManifest(stagedBundle.appendingPathComponent(Constants.Bundle.manifest))
        log(
            "bundle apply manifest version=\(manifest.version) runtimeVersion=\(manifest.runtimeVersion) artifacts=\(manifest.artifacts.count) migrations=\(manifest.migrations.count)"
        )
        try checkCompatibility(manifest)

        let stagedRootfs = manifest.artifacts.contains { $0.type == .rootfsBase }
            ? stagedBundle.appendingPathComponent(Constants.Artifacts.rootfsBase)
            : nil
        let stagedBundleSize = try directorySize(stagedBundle)
        let rootfsStorage: RuntimeUpdateRootfsStorageInput
        log("bundle apply storage preflight stagedBundle=\(formatBytes(stagedBundleSize))")
        if let stagedRootfs {
            guard fileExists(stagedRootfs) else {
                throw LauncherError.missingFile(stagedRootfs.path)
            }
            let installedRootfsSize = try fileSize(rootfsBase)
            let incomingRootfsSize = try fileSize(stagedRootfs)
            rootfsStorage = .replacing(
                installedRootfsBytes: installedRootfsSize,
                incomingRootfsBytes: incomingRootfsSize
            )
            log(
                "bundle apply storage preflight installedRootfs=\(formatBytes(installedRootfsSize)) incomingRootfs=\(formatBytes(incomingRootfsSize))"
            )
        } else {
            rootfsStorage = .unchanged
            log("bundle apply storage preflight rootfsBase=unchanged")
        }
        let storageRequirement = RuntimeUpdatePreflightPolicy.storageRequirement(
            stagedBundleBytes: stagedBundleSize,
            rootfsStorage: rootfsStorage,
            marginBytes: Constants.Runtime.updateFreeSpaceMarginBytes
        )
        try createDirectory(backupsDirectory, true)
        try requireFreeSpace(
            backupsDirectory,
            storageRequirement.requiredBytes,
            .applyBundle
        )

        let restartPolicy = serviceRestartPolicy()
        log(
            "runtime services before update vm=\(restartPolicy.restartVM ? "loaded" : "not-loaded") guestLogSync=\(restartPolicy.restartGuestLogSync ? "loaded" : "not-loaded") proxy=\(restartPolicy.restartProxy ? "loaded" : "not-loaded") watchdog=\(restartPolicy.restartWatchdog ? "loaded" : "not-loaded")"
        )
        if restartPolicy.restartVM {
            try requireRuntimeDiskHealthAllowsUpdate()
            try requireGuestCapability(.prepareUpdateShutdown)
        }
        if manifest.artifacts.contains(where: { $0.type == .guestDeploy }) {
            try requireGuestCapability(.activateUpdate)
        }
        log("creating managed backup reason=before-\(manifest.version)")
        let backup = try createBackup("before-\(manifest.version)")
        log("backup created path=\(backup.path) size=\(formatBytes(try directorySize(backup)))")

        return ApplyBundlePreflightContext(
            stagedBundle: stagedBundle,
            manifest: manifest,
            stagedRootfs: stagedRootfs,
            backup: backup,
            restartPolicy: restartPolicy
        )
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }

    private func requireRuntimeDiskHealthAllowsUpdate() throws {
        let snapshot = runtimeHealthSnapshot()
        let blockers = RuntimeUpdatePreflightPolicy.blockingGuestStorageErrors(snapshot.vmErrors)
        guard blockers.isEmpty else {
            let codes = blockers.map(\.rawValue).joined(separator: ",")
            log("bundle apply blocked by VM guest storage health errors=\(codes)")
            throw LauncherError.runtimeOperationFailed(
                "VM disk health blocks update; run Repair VM Disk before applying update. errors=\(codes)"
            )
        }
    }
}
