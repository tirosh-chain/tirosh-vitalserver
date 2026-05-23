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
        var requiredBytes = Constants.Runtime.updateFreeSpaceMarginBytes
        if let stagedRootfs {
            guard fileExists(stagedRootfs) else {
                throw LauncherError.missingFile(stagedRootfs.path)
            }
            let installedRootfsSize = try fileSize(rootfsBase)
            let incomingRootfsSize = try fileSize(stagedRootfs)
            requiredBytes += installedRootfsSize + incomingRootfsSize
            log(
                "bundle apply storage preflight installedRootfs=\(formatBytes(installedRootfsSize)) incomingRootfs=\(formatBytes(incomingRootfsSize))"
            )
        } else {
            log("bundle apply storage preflight rootfsBase=unchanged")
        }
        try createDirectory(backupsDirectory, true)
        try requireFreeSpace(
            backupsDirectory,
            requiredBytes,
            .applyBundle
        )

        let restartPolicy = serviceRestartPolicy()
        log(
            "runtime services before update vm=\(restartPolicy.restartVM ? "loaded" : "not-loaded") proxy=\(restartPolicy.restartProxy ? "loaded" : "not-loaded") watchdog=\(restartPolicy.restartWatchdog ? "loaded" : "not-loaded")"
        )
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
}
