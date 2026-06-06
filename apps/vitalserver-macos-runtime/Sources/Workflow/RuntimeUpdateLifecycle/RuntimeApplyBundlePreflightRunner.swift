import Contracts
import Domain
import Foundation

public struct RuntimeApplyBundlePreflightRunner {
    public var stageBundle: (URL) throws -> URL
    public var loadManifest: (URL) throws -> UpdateBundleManifest
    public var fileExists: (URL) -> Bool
    public var createDirectory: (URL, Bool) throws -> Void
    public var fileSize: (URL) throws -> UInt64
    public var requireFreeSpace: (URL, UInt64, RuntimeOperation) throws -> Void
    public var checkCompatibility: (UpdateBundleManifest) throws -> Void
    public var serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    public var runtimeHealthSnapshot: () -> RuntimeHealthSnapshot
    public var requireGuestCapability: (RuntimeGuestCapabilityRequirement) throws -> Void
    public var createBackup: (String) throws -> URL
    public var directorySize: (URL) throws -> UInt64
    public var updateFreeSpaceMarginBytes: UInt64
    public var log: (String) -> Void

    public init(
        stageBundle: @escaping (URL) throws -> URL,
        loadManifest: @escaping (URL) throws -> UpdateBundleManifest,
        fileExists: @escaping (URL) -> Bool,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        fileSize: @escaping (URL) throws -> UInt64,
        requireFreeSpace: @escaping (URL, UInt64, RuntimeOperation) throws -> Void,
        checkCompatibility: @escaping (UpdateBundleManifest) throws -> Void,
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy,
        runtimeHealthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        requireGuestCapability: @escaping (RuntimeGuestCapabilityRequirement) throws -> Void,
        createBackup: @escaping (String) throws -> URL,
        directorySize: @escaping (URL) throws -> UInt64,
        updateFreeSpaceMarginBytes: UInt64,
        log: @escaping (String) -> Void
    ) {
        self.stageBundle = stageBundle
        self.loadManifest = loadManifest
        self.fileExists = fileExists
        self.createDirectory = createDirectory
        self.fileSize = fileSize
        self.requireFreeSpace = requireFreeSpace
        self.checkCompatibility = checkCompatibility
        self.serviceRestartPolicy = serviceRestartPolicy
        self.runtimeHealthSnapshot = runtimeHealthSnapshot
        self.requireGuestCapability = requireGuestCapability
        self.createBackup = createBackup
        self.directorySize = directorySize
        self.updateFreeSpaceMarginBytes = updateFreeSpaceMarginBytes
        self.log = log
    }

    public func prepare(bundleURL: URL, backupsDirectory: URL, rootfsBase: URL) throws -> ApplyBundlePreflightContext {
        let stagedBundle = try stageBundle(bundleURL)
        let manifest = try loadManifest(stagedBundle.appendingPathComponent(RuntimeFileNames.updateBundleManifest))
        log(
            "bundle apply manifest version=\(manifest.version) runtimeVersion=\(manifest.runtimeVersion) artifacts=\(manifest.artifacts.count) migrations=\(manifest.migrations.count)"
        )
        try checkCompatibility(manifest)

        let stagedRootfs = manifest.artifacts.contains { $0.type == .rootfsBase }
            ? stagedBundle.appendingPathComponent(RuntimeFileNames.rootfsBase)
            : nil
        let stagedBundleSize = try directorySize(stagedBundle)
        let rootfsStorage: RuntimeUpdateRootfsStorageInput
        log("bundle apply storage preflight stagedBundle=\(formatBytes(stagedBundleSize))")
        if let stagedRootfs {
            guard fileExists(stagedRootfs) else {
                throw RuntimeApplyBundleWorkflowError.operationFailed("missing file: \(stagedRootfs.path)")
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
            marginBytes: updateFreeSpaceMarginBytes
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
            throw RuntimeApplyBundleWorkflowError.operationFailed(
                "VM disk health blocks update; run Repair VM Disk before applying update. errors=\(codes)"
            )
        }
    }
}
