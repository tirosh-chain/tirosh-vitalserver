import Application
import Contracts
import Domain
import Foundation
import Errors

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
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

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
        let manifestPlan = useCase.preflightManifestPlan(stagedBundle: stagedBundle, manifest: manifest)
        log(manifestPlan.manifestLogMessage)
        try checkCompatibility(manifest)

        let stagedRootfs = manifestPlan.stagedRootfs
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
        let storageRequirement = useCase.storageRequirement(
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
        let capabilityPlan = useCase.preflightCapabilityPlan(
            manifest: manifest,
            restartPolicy: restartPolicy
        )
        log(capabilityPlan.serviceRestartLogMessage)
        if capabilityPlan.requiresRuntimeDiskHealthCheck {
            try requireRuntimeDiskHealthAllowsUpdate()
        }
        for capability in capabilityPlan.requiredGuestCapabilities {
            try requireGuestCapability(capability)
        }
        log(manifestPlan.backupStartedLogMessage)
        let backup = try createBackup(manifestPlan.backupReason)
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
        let decision = useCase.diskHealthDecision(snapshot: runtimeHealthSnapshot())
        guard decision.canApplyUpdate else {
            if let blockedLogMessage = decision.blockedLogMessage {
                log(blockedLogMessage)
            }
            throw RuntimeApplyBundleWorkflowError.operationFailed(decision.failureMessage ?? "VM disk health blocks update")
        }
    }
}
