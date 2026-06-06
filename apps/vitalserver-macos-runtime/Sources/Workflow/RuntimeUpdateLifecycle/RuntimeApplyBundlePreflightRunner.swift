import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeApplyBundlePreflightRunner {
    public var stageBundle: (URL) throws -> URL
    public var loadStagedManifest: (URL) throws -> UpdateBundleManifest
    public var observeRootfsStorage: (URL, URL) throws -> ApplyRuntimeBundleRootfsStorageObservation
    public var createDirectory: (URL, Bool) throws -> Void
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
        loadStagedManifest: @escaping (URL) throws -> UpdateBundleManifest,
        observeRootfsStorage: @escaping (URL, URL) throws -> ApplyRuntimeBundleRootfsStorageObservation,
        createDirectory: @escaping (URL, Bool) throws -> Void,
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
        self.loadStagedManifest = loadStagedManifest
        self.observeRootfsStorage = observeRootfsStorage
        self.createDirectory = createDirectory
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
        let manifest = try loadStagedManifest(stagedBundle)
        let manifestPlan = useCase.preflightManifestPlan(stagedBundle: stagedBundle, manifest: manifest)
        log(manifestPlan.manifestLogMessage)
        try checkCompatibility(manifest)

        let stagedRootfs = manifestPlan.stagedRootfs
        let stagedBundleSize = try directorySize(stagedBundle)
        let rootfsStorage: RuntimeUpdateRootfsStorageInput
        log(useCase.storagePreflightStagedBundleLogMessage(stagedBundleBytes: stagedBundleSize))
        switch useCase.rootfsStorageObservationPlan(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase) {
        case .unchanged(let rootfsStoragePlan):
            rootfsStorage = rootfsStoragePlan.rootfsStorage
            log(rootfsStoragePlan.logMessage)
        case .replacing(let stagedRootfs, let rootfsBase):
            switch useCase.rootfsStorageDecision(
                observation: try observeRootfsStorage(stagedRootfs, rootfsBase)
            ) {
            case .planned(let rootfsStoragePlan):
                rootfsStorage = rootfsStoragePlan.rootfsStorage
                log(rootfsStoragePlan.logMessage)
            case .failed(let message):
                throw RuntimeApplyBundleWorkflowError.operationFailed(message)
            }
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
        for instruction in capabilityPlan.instructions {
            switch instruction {
            case .requireRuntimeDiskHealthAllowsUpdate:
                try requireRuntimeDiskHealthAllowsUpdate()
            case .requireGuestCapability(let capability):
                try requireGuestCapability(capability)
            }
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

    private func requireRuntimeDiskHealthAllowsUpdate() throws {
        let decision = useCase.diskHealthDecision(snapshot: runtimeHealthSnapshot())
        switch decision {
        case .allowed:
            return
        case .blocked(_, let logMessage, let failureMessage):
            log(logMessage)
            throw RuntimeApplyBundleWorkflowError.operationFailed(failureMessage)
        }
    }
}
