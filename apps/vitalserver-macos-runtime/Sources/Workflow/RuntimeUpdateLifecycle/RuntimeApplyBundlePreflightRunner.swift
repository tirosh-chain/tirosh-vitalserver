import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeApplyBundlePreflightRunner {
    public var stageBundle: (URL) throws -> URL
    public var loadStagedManifest: (URL) throws -> UpdateBundleManifest
    public var resolveRootfsStorage: (ApplyRuntimeBundleRootfsStorageObservationPlan) throws -> ApplyRuntimeBundleRootfsStoragePreflightPlan
    public var createDirectory: (URL, Bool) throws -> Void
    public var requireFreeSpace: (URL, UInt64, RuntimeOperation) throws -> Void
    public var checkCompatibility: (UpdateBundleManifest) throws -> Void
    public var serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    public var executeCapabilityInstruction: (ApplyRuntimeBundlePreflightCapabilityInstruction) throws -> Void
    public var createBackup: (String) throws -> URL
    public var directorySize: (URL) throws -> UInt64
    public var updateFreeSpaceMarginBytes: UInt64
    public var log: (String) -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        stageBundle: @escaping (URL) throws -> URL,
        loadStagedManifest: @escaping (URL) throws -> UpdateBundleManifest,
        resolveRootfsStorage: @escaping (ApplyRuntimeBundleRootfsStorageObservationPlan) throws -> ApplyRuntimeBundleRootfsStoragePreflightPlan,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        requireFreeSpace: @escaping (URL, UInt64, RuntimeOperation) throws -> Void,
        checkCompatibility: @escaping (UpdateBundleManifest) throws -> Void,
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy,
        executeCapabilityInstruction: @escaping (ApplyRuntimeBundlePreflightCapabilityInstruction) throws -> Void,
        createBackup: @escaping (String) throws -> URL,
        directorySize: @escaping (URL) throws -> UInt64,
        updateFreeSpaceMarginBytes: UInt64,
        log: @escaping (String) -> Void
    ) {
        self.stageBundle = stageBundle
        self.loadStagedManifest = loadStagedManifest
        self.resolveRootfsStorage = resolveRootfsStorage
        self.createDirectory = createDirectory
        self.requireFreeSpace = requireFreeSpace
        self.checkCompatibility = checkCompatibility
        self.serviceRestartPolicy = serviceRestartPolicy
        self.executeCapabilityInstruction = executeCapabilityInstruction
        self.createBackup = createBackup
        self.directorySize = directorySize
        self.updateFreeSpaceMarginBytes = updateFreeSpaceMarginBytes
        self.log = log
    }

    public func prepare(bundleURL: URL, backupsDirectory: URL, rootfsBase: URL) throws -> ApplyBundlePreflightContext {
        let stagedBundle = try stageBundle(bundleURL)
        let manifest = try loadStagedManifest(stagedBundle)
        let manifestPlan = useCase.preflightManifestPlan(stagedBundle: stagedBundle, manifest: manifest)
        log(manifestPlan.manifestLogMessage)
        try checkCompatibility(manifest)

        let stagedRootfs = manifestPlan.stagedRootfs
        let stagedBundleSize = try directorySize(stagedBundle)
        log(useCase.storagePreflightStagedBundleLogMessage(stagedBundleBytes: stagedBundleSize))
        let rootfsStoragePlan = useCase.rootfsStorageObservationPlan(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase)
        let rootfsStoragePreflightPlan = try resolveRootfsStorage(rootfsStoragePlan)
        let rootfsStorage = rootfsStoragePreflightPlan.rootfsStorage
        log(rootfsStoragePreflightPlan.logMessage)
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
        for instruction in capabilityPlan.instructions {
            try executeCapabilityInstruction(instruction)
        }
        log(manifestPlan.backupStartedLogMessage)
        let backup = try createBackup(manifestPlan.backupReason)
        log(useCase.backupCreatedLogMessage(backupPath: backup.path, backupBytes: try directorySize(backup)))

        return ApplyBundlePreflightContext(
            stagedBundle: stagedBundle,
            manifest: manifest,
            stagedRootfs: stagedRootfs,
            backup: backup,
            restartPolicy: restartPolicy
        )
    }
}
