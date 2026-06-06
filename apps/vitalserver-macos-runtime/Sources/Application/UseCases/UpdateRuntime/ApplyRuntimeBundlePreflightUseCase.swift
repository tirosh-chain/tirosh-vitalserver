import Contracts
import Domain
import Foundation
import Errors

public struct ApplyRuntimeBundlePreflightInput: Equatable, Sendable {
    public let bundleURL: URL
    public let backupsDirectory: URL
    public let rootfsBase: URL
    public let updateFreeSpaceMarginBytes: UInt64

    public init(
        bundleURL: URL,
        backupsDirectory: URL,
        rootfsBase: URL,
        updateFreeSpaceMarginBytes: UInt64
    ) {
        self.bundleURL = bundleURL
        self.backupsDirectory = backupsDirectory
        self.rootfsBase = rootfsBase
        self.updateFreeSpaceMarginBytes = updateFreeSpaceMarginBytes
    }
}

public struct ApplyRuntimeBundlePreflightOperations {
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
    public var log: (String) -> Void

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
        self.log = log
    }
}

public struct ApplyRuntimeBundlePreflightUseCase {
    public init() {}

    public func prepare(
        input: ApplyRuntimeBundlePreflightInput,
        operations: ApplyRuntimeBundlePreflightOperations
    ) throws -> ApplyBundlePreflightContext {
        let update = UpdateRuntimeUseCase()
        let stagedBundle = try operations.stageBundle(input.bundleURL)
        let manifest = try operations.loadStagedManifest(stagedBundle)
        let manifestPlan = update.preflightManifestPlan(stagedBundle: stagedBundle, manifest: manifest)
        operations.log(manifestPlan.manifestLogMessage)
        try operations.checkCompatibility(manifest)

        let stagedRootfs = manifestPlan.stagedRootfs
        let stagedBundleSize = try operations.directorySize(stagedBundle)
        operations.log(update.storagePreflightStagedBundleLogMessage(stagedBundleBytes: stagedBundleSize))
        let rootfsStoragePlan = update.rootfsStorageObservationPlan(
            stagedRootfs: stagedRootfs,
            rootfsBase: input.rootfsBase
        )
        let rootfsStoragePreflightPlan = try operations.resolveRootfsStorage(rootfsStoragePlan)
        let rootfsStorage = rootfsStoragePreflightPlan.rootfsStorage
        operations.log(rootfsStoragePreflightPlan.logMessage)
        let storageRequirement = update.storageRequirement(
            stagedBundleBytes: stagedBundleSize,
            rootfsStorage: rootfsStorage,
            marginBytes: input.updateFreeSpaceMarginBytes
        )
        try operations.createDirectory(input.backupsDirectory, true)
        try operations.requireFreeSpace(
            input.backupsDirectory,
            storageRequirement.requiredBytes,
            .applyBundle
        )

        let restartPolicy = operations.serviceRestartPolicy()
        let capabilityPlan = update.preflightCapabilityPlan(
            manifest: manifest,
            restartPolicy: restartPolicy
        )
        operations.log(capabilityPlan.serviceRestartLogMessage)
        for instruction in capabilityPlan.instructions {
            try operations.executeCapabilityInstruction(instruction)
        }
        operations.log(manifestPlan.backupStartedLogMessage)
        let backup = try operations.createBackup(manifestPlan.backupReason)
        operations.log(update.backupCreatedLogMessage(
            backupPath: backup.path,
            backupBytes: try operations.directorySize(backup)
        ))

        return ApplyBundlePreflightContext(
            stagedBundle: stagedBundle,
            manifest: manifest,
            stagedRootfs: stagedRootfs,
            backup: backup,
            restartPolicy: restartPolicy
        )
    }
}
