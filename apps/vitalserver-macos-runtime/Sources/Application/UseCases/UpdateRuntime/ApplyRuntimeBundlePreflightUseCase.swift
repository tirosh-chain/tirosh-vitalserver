import Contracts
import Domain
import Foundation
import Errors

public struct ApplyRuntimeBundlePreflightInput: Equatable, Sendable {
    public let bundleURL: URL
    public let backupsDirectory: URL
    public let rootfsBase: URL
    public let updateFreeSpaceMarginBytes: UInt64
    public let currentChannel: UpdateBundleChannel
    public let currentPlatform: String?

    public init(
        bundleURL: URL,
        backupsDirectory: URL,
        rootfsBase: URL,
        updateFreeSpaceMarginBytes: UInt64,
        currentChannel: UpdateBundleChannel,
        currentPlatform: String?
    ) {
        self.bundleURL = bundleURL
        self.backupsDirectory = backupsDirectory
        self.rootfsBase = rootfsBase
        self.updateFreeSpaceMarginBytes = updateFreeSpaceMarginBytes
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

public struct ApplyRuntimeBundlePreflightCapabilityPlan: Equatable, Sendable {
    public let instructions: [ApplyRuntimeBundlePreflightCapabilityInstruction]
    public let serviceRestartLogMessage: String

    public init(
        instructions: [ApplyRuntimeBundlePreflightCapabilityInstruction],
        serviceRestartLogMessage: String
    ) {
        self.instructions = instructions
        self.serviceRestartLogMessage = serviceRestartLogMessage
    }
}

public enum ApplyRuntimeBundlePreflightCapabilityInstruction: Equatable, Sendable {
    case requireRuntimeDiskHealthAllowsUpdate
    case requireGuestCapability(RuntimeGuestCapabilityRequirement)
}

public struct ApplyRuntimeBundlePreflightManifestPlan: Equatable, Sendable {
    public let stagedRootfs: URL?
    public let manifestLogMessage: String
    public let backupReason: String
    public let backupStartedLogMessage: String

    public init(
        stagedRootfs: URL?,
        manifestLogMessage: String,
        backupReason: String,
        backupStartedLogMessage: String
    ) {
        self.stagedRootfs = stagedRootfs
        self.manifestLogMessage = manifestLogMessage
        self.backupReason = backupReason
        self.backupStartedLogMessage = backupStartedLogMessage
    }
}

public enum ApplyRuntimeBundleDiskHealthDecision: Equatable, Sendable {
    case allowed
    case blocked(blockers: [RuntimeVMError], logMessage: String, failureMessage: String)
}

public struct ApplyRuntimeBundleRootfsStoragePreflightPlan: Equatable, Sendable {
    public let rootfsStorage: RuntimeUpdateRootfsStorageInput
    public let logMessage: String

    public init(rootfsStorage: RuntimeUpdateRootfsStorageInput, logMessage: String) {
        self.rootfsStorage = rootfsStorage
        self.logMessage = logMessage
    }
}

public enum ApplyRuntimeBundleRootfsStorageObservationPlan: Equatable, Sendable {
    case unchanged(ApplyRuntimeBundleRootfsStoragePreflightPlan)
    case replacing(stagedRootfs: URL, rootfsBase: URL)
}

public struct ApplyRuntimeBundleRootfsStorageObservation: Equatable, Sendable {
    public let stagedRootfs: URL
    public let stagedRootfsState: RuntimePathState
    public let installedRootfsBytes: UInt64?
    public let incomingRootfsBytes: UInt64?

    public init(
        stagedRootfs: URL,
        stagedRootfsState: RuntimePathState,
        installedRootfsBytes: UInt64?,
        incomingRootfsBytes: UInt64?
    ) {
        self.stagedRootfs = stagedRootfs
        self.stagedRootfsState = stagedRootfsState
        self.installedRootfsBytes = installedRootfsBytes
        self.incomingRootfsBytes = incomingRootfsBytes
    }
}

public enum ApplyRuntimeBundleRootfsStorageDecision: Equatable, Sendable {
    case planned(ApplyRuntimeBundleRootfsStoragePreflightPlan)
    case failed(message: String)
}

public struct ApplyRuntimeBundlePreflightUseCase {
    public init() {}

    public func prepare(
        input: ApplyRuntimeBundlePreflightInput,
        operations: ApplyRuntimeBundlePreflightOperations
    ) throws -> ApplyBundlePreflightContext {
        let stagedBundle = try operations.stageBundle(input.bundleURL)
        let manifest = try operations.loadStagedManifest(stagedBundle)
        let manifestPlan = preflightManifestPlan(stagedBundle: stagedBundle, manifest: manifest)
        operations.log(manifestPlan.manifestLogMessage)
        try RuntimeUpdatePreflightPolicy.checkCompatibility(
            manifest: manifest,
            currentChannel: input.currentChannel,
            currentPlatform: input.currentPlatform
        )

        let stagedRootfs = manifestPlan.stagedRootfs
        let stagedBundleSize = try operations.directorySize(stagedBundle)
        operations.log(storagePreflightStagedBundleLogMessage(stagedBundleBytes: stagedBundleSize))
        let rootfsStoragePlan = rootfsStorageObservationPlan(
            stagedRootfs: stagedRootfs,
            rootfsBase: input.rootfsBase
        )
        let rootfsStoragePreflightPlan = try resolveRootfsStorage(
            rootfsStoragePlan,
            operations: operations
        )
        let rootfsStorage = rootfsStoragePreflightPlan.rootfsStorage
        operations.log(rootfsStoragePreflightPlan.logMessage)
        let storageRequirement = storageRequirement(
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
        let capabilityPlan = preflightCapabilityPlan(
            manifest: manifest,
            restartPolicy: restartPolicy
        )
        operations.log(capabilityPlan.serviceRestartLogMessage)
        for instruction in capabilityPlan.instructions {
            try executeCapabilityInstruction(
                instruction,
                operations: operations
            )
        }
        operations.log(manifestPlan.backupStartedLogMessage)
        let backup = try operations.createBackup(manifestPlan.backupReason)
        operations.log(backupCreatedLogMessage(
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

    public func preflightManifestPlan(
        stagedBundle: URL,
        manifest: UpdateBundleManifest
    ) -> ApplyRuntimeBundlePreflightManifestPlan {
        ApplyRuntimeBundlePreflightManifestPlan(
            stagedRootfs: manifest.artifacts.contains { $0.type == .rootfsBase }
                ? stagedBundle.appendingPathComponent(RuntimePackageArtifactFileNames.rootfsBase)
                : nil,
            manifestLogMessage: "bundle apply manifest version=\(manifest.version) runtimeVersion=\(manifest.runtimeVersion) artifacts=\(manifest.artifacts.count) migrations=\(manifest.migrations.count)",
            backupReason: "before-\(manifest.version)",
            backupStartedLogMessage: "creating managed backup reason=before-\(manifest.version)"
        )
    }

    public func preflightCapabilityPlan(
        manifest: UpdateBundleManifest,
        restartPolicy: RuntimeServiceRestartPolicy
    ) -> ApplyRuntimeBundlePreflightCapabilityPlan {
        var instructions: [ApplyRuntimeBundlePreflightCapabilityInstruction] = []
        if restartPolicy.restartVM {
            instructions.append(.requireRuntimeDiskHealthAllowsUpdate)
            instructions.append(.requireGuestCapability(.prepareUpdateShutdown))
        }
        if manifest.artifacts.contains(where: { $0.type == .guestDeploy }) {
            instructions.append(.requireGuestCapability(.activateUpdate))
        }

        return ApplyRuntimeBundlePreflightCapabilityPlan(
            instructions: instructions,
            serviceRestartLogMessage: "runtime services before update vm=\(loadedText(restartPolicy.restartVM)) guestLogSync=\(loadedText(restartPolicy.restartGuestLogSync)) proxy=\(loadedText(restartPolicy.restartProxy)) watchdog=\(loadedText(restartPolicy.restartWatchdog))"
        )
    }

    public func storageRequirement(
        stagedBundleBytes: UInt64,
        rootfsStorage: RuntimeUpdateRootfsStorageInput,
        marginBytes: UInt64
    ) -> RuntimeUpdateStorageRequirement {
        RuntimeUpdatePreflightPolicy.storageRequirement(
            stagedBundleBytes: stagedBundleBytes,
            rootfsStorage: rootfsStorage,
            marginBytes: marginBytes
        )
    }

    public func storagePreflightStagedBundleLogMessage(stagedBundleBytes: UInt64) -> String {
        "bundle apply storage preflight stagedBundle=\(formatBytes(stagedBundleBytes))"
    }

    public func replacingRootfsStoragePreflightPlan(
        installedRootfsBytes: UInt64,
        incomingRootfsBytes: UInt64
    ) -> ApplyRuntimeBundleRootfsStoragePreflightPlan {
        ApplyRuntimeBundleRootfsStoragePreflightPlan(
            rootfsStorage: .replacing(
                installedRootfsBytes: installedRootfsBytes,
                incomingRootfsBytes: incomingRootfsBytes
            ),
            logMessage: "bundle apply storage preflight installedRootfs=\(formatBytes(installedRootfsBytes)) incomingRootfs=\(formatBytes(incomingRootfsBytes))"
        )
    }

    public func unchangedRootfsStoragePreflightPlan() -> ApplyRuntimeBundleRootfsStoragePreflightPlan {
        ApplyRuntimeBundleRootfsStoragePreflightPlan(
            rootfsStorage: .unchanged,
            logMessage: "bundle apply storage preflight rootfsBase=unchanged"
        )
    }

    public func rootfsStorageObservationPlan(
        stagedRootfs: URL?,
        rootfsBase: URL
    ) -> ApplyRuntimeBundleRootfsStorageObservationPlan {
        guard let stagedRootfs else {
            return .unchanged(unchangedRootfsStoragePreflightPlan())
        }
        return .replacing(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase)
    }

    public func rootfsStorageDecision(
        observation: ApplyRuntimeBundleRootfsStorageObservation
    ) -> ApplyRuntimeBundleRootfsStorageDecision {
        switch observation.stagedRootfsState {
        case .file:
            break
        case .missing:
            return .failed(message: missingFileFailureMessage(path: observation.stagedRootfs.path))
        case .inspectFailed(let reason):
            return .failed(message: "staged rootfs path inspection failed: \(observation.stagedRootfs.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed(message: "staged rootfs path state is unexpected: \(observation.stagedRootfs.path) state=\(observation.stagedRootfsState.rawValue)")
        }
        guard let installedRootfsBytes = observation.installedRootfsBytes,
              let incomingRootfsBytes = observation.incomingRootfsBytes
        else {
            return .failed(message: "missing rootfs storage observation")
        }
        return .planned(replacingRootfsStoragePreflightPlan(
            installedRootfsBytes: installedRootfsBytes,
            incomingRootfsBytes: incomingRootfsBytes
        ))
    }

    public func missingFileFailureMessage(path: String) -> String {
        "missing file: \(path)"
    }

    public func backupCreatedLogMessage(backupPath: String, backupBytes: UInt64) -> String {
        "backup created path=\(backupPath) size=\(formatBytes(backupBytes))"
    }

    public func diskHealthDecision(
        snapshot: RuntimeHealthSnapshot
    ) -> ApplyRuntimeBundleDiskHealthDecision {
        let blockers = RuntimeUpdatePreflightPolicy.blockingGuestStorageErrors(snapshot.vmErrors)
        guard !blockers.isEmpty else {
            return .allowed
        }

        let codes = blockers.map(\.rawValue).joined(separator: ",")
        return .blocked(
            blockers: blockers,
            logMessage: "bundle apply blocked by VM guest storage health errors=\(codes)",
            failureMessage: "VM disk health blocks update; run Repair VM Disk before applying update. errors=\(codes)"
        )
    }

    private func resolveRootfsStorage(
        _ plan: ApplyRuntimeBundleRootfsStorageObservationPlan,
        operations: ApplyRuntimeBundlePreflightOperations
    ) throws -> ApplyRuntimeBundleRootfsStoragePreflightPlan {
        let decision: ApplyRuntimeBundleRootfsStorageDecision
        switch plan {
        case .unchanged(let rootfsStoragePlan):
            decision = .planned(rootfsStoragePlan)
        case .replacing(let stagedRootfs, let rootfsBase):
            decision = rootfsStorageDecision(
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
        operations: ApplyRuntimeBundlePreflightOperations
    ) throws {
        switch instruction {
        case .requireRuntimeDiskHealthAllowsUpdate:
            let decision = diskHealthDecision(snapshot: operations.runtimeHealthSnapshot())
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

    private func loadedText(_ loaded: Bool) -> String {
        loaded ? "loaded" : "not-loaded"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}
