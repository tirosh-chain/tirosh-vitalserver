import Contracts
import Domain
import Foundation
import Errors

public struct ApplyRuntimeBundlePreflightInput: Equatable, Sendable {
    public let bundleURL: URL
    public let backupsDirectory: URL
    public let rootfsBase: URL
    public let updateFreeSpaceMarginBytes: UInt64
    public let currentUpdaterVersion: String
    public let currentChannel: UpdateBundleChannel
    public let currentPlatform: String?

    public init(
        bundleURL: URL,
        backupsDirectory: URL,
        rootfsBase: URL,
        updateFreeSpaceMarginBytes: UInt64,
        currentUpdaterVersion: String,
        currentChannel: UpdateBundleChannel,
        currentPlatform: String?
    ) {
        self.bundleURL = bundleURL
        self.backupsDirectory = backupsDirectory
        self.rootfsBase = rootfsBase
        self.updateFreeSpaceMarginBytes = updateFreeSpaceMarginBytes
        self.currentUpdaterVersion = currentUpdaterVersion
        self.currentChannel = currentChannel
        self.currentPlatform = currentPlatform
    }
}

public struct ApplyRuntimeBundlePreflightOperations {
    public var stageBundle: (URL) throws -> URL
    public var loadStagedManifest: (URL) throws -> UpdateBundleManifest
    public var observeRootfsStorage: (URL, URL) throws -> ApplyRuntimeBundleRootfsStorageObservation
    public var createDirectory: (URL, Bool) throws -> Void
    public var requireFreeSpace: (URL, UInt64, RuntimeOperation) throws -> Void
    public var serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    public var runtimeHealthSnapshot: () -> RuntimeHealthSnapshot
    public var requireGuestCapability: (RuntimeGuestCapabilityRequirement) throws -> Void
    public var createBackup: (String) throws -> URL
    public var directorySize: (URL) throws -> UInt64
    public var log: (String) -> Void

    public init(
        stageBundle: @escaping (URL) throws -> URL,
        loadStagedManifest: @escaping (URL) throws -> UpdateBundleManifest,
        observeRootfsStorage: @escaping (URL, URL) throws -> ApplyRuntimeBundleRootfsStorageObservation,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        requireFreeSpace: @escaping (URL, UInt64, RuntimeOperation) throws -> Void,
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy,
        runtimeHealthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        requireGuestCapability: @escaping (RuntimeGuestCapabilityRequirement) throws -> Void,
        createBackup: @escaping (String) throws -> URL,
        directorySize: @escaping (URL) throws -> UInt64,
        log: @escaping (String) -> Void
    ) {
        self.stageBundle = stageBundle
        self.loadStagedManifest = loadStagedManifest
        self.observeRootfsStorage = observeRootfsStorage
        self.createDirectory = createDirectory
        self.requireFreeSpace = requireFreeSpace
        self.serviceRestartPolicy = serviceRestartPolicy
        self.runtimeHealthSnapshot = runtimeHealthSnapshot
        self.requireGuestCapability = requireGuestCapability
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
        try RuntimeUpdatePreflightPolicy.checkCompatibility(
            manifest: manifest,
            currentUpdaterVersion: input.currentUpdaterVersion,
            currentChannel: input.currentChannel,
            currentPlatform: input.currentPlatform
        )

        let stagedRootfs = manifestPlan.stagedRootfs
        let stagedBundleSize = try operations.directorySize(stagedBundle)
        operations.log(update.storagePreflightStagedBundleLogMessage(stagedBundleBytes: stagedBundleSize))
        let rootfsStoragePlan = update.rootfsStorageObservationPlan(
            stagedRootfs: stagedRootfs,
            rootfsBase: input.rootfsBase
        )
        let rootfsStoragePreflightPlan = try resolveRootfsStorage(
            rootfsStoragePlan,
            operations: operations,
            update: update
        )
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
            try executeCapabilityInstruction(
                instruction,
                operations: operations,
                update: update
            )
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

    private func resolveRootfsStorage(
        _ plan: ApplyRuntimeBundleRootfsStorageObservationPlan,
        operations: ApplyRuntimeBundlePreflightOperations,
        update: UpdateRuntimeUseCase
    ) throws -> ApplyRuntimeBundleRootfsStoragePreflightPlan {
        let decision: ApplyRuntimeBundleRootfsStorageDecision
        switch plan {
        case .unchanged(let rootfsStoragePlan):
            decision = .planned(rootfsStoragePlan)
        case .replacing(let stagedRootfs, let rootfsBase):
            decision = update.rootfsStorageDecision(
                observation: try operations.observeRootfsStorage(stagedRootfs, rootfsBase)
            )
        }

        switch decision {
        case .planned(let rootfsStoragePlan):
            return rootfsStoragePlan
        case .failed(let message):
            throw ApplyRuntimeBundleCompositionError.operationFailed(message)
        }
    }

    private func executeCapabilityInstruction(
        _ instruction: ApplyRuntimeBundlePreflightCapabilityInstruction,
        operations: ApplyRuntimeBundlePreflightOperations,
        update: UpdateRuntimeUseCase
    ) throws {
        switch instruction {
        case .requireRuntimeDiskHealthAllowsUpdate:
            let decision = update.diskHealthDecision(snapshot: operations.runtimeHealthSnapshot())
            switch decision {
            case .allowed:
                return
            case .blocked(_, let logMessage, let failureMessage):
                operations.log(logMessage)
                throw ApplyRuntimeBundleCompositionError.operationFailed(failureMessage)
            }
        case .requireGuestCapability(let capability):
            try operations.requireGuestCapability(capability)
        }
    }
}
