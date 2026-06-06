import Contracts
import Domain
import Foundation
import Errors

public struct ApplyRuntimeBundleInitialHealthDecision: Equatable, Sendable {
    public let shouldWarn: Bool
    public let warningMessage: String?

    public init(shouldWarn: Bool, warningMessage: String?) {
        self.shouldWarn = shouldWarn
        self.warningMessage = warningMessage
    }
}

public struct ApplyRuntimeBundlePlan: Equatable, Sendable {
    public let operationPlan: RuntimeOperationPlan

    public init(operationPlan: RuntimeOperationPlan) {
        self.operationPlan = operationPlan
    }
}

public struct ApplyRuntimeBundlePreflightCapabilityPlan: Equatable, Sendable {
    public let requiresRuntimeDiskHealthCheck: Bool
    public let requiredGuestCapabilities: [RuntimeGuestCapabilityRequirement]
    public let serviceRestartLogMessage: String

    public init(
        requiresRuntimeDiskHealthCheck: Bool,
        requiredGuestCapabilities: [RuntimeGuestCapabilityRequirement],
        serviceRestartLogMessage: String
    ) {
        self.requiresRuntimeDiskHealthCheck = requiresRuntimeDiskHealthCheck
        self.requiredGuestCapabilities = requiredGuestCapabilities
        self.serviceRestartLogMessage = serviceRestartLogMessage
    }
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

public struct ApplyRuntimeBundleDiskHealthDecision: Equatable, Sendable {
    public let canApplyUpdate: Bool
    public let blockers: [RuntimeVMError]
    public let blockedLogMessage: String?
    public let failureMessage: String?

    public init(
        canApplyUpdate: Bool,
        blockers: [RuntimeVMError],
        blockedLogMessage: String?,
        failureMessage: String?
    ) {
        self.canApplyUpdate = canApplyUpdate
        self.blockers = blockers
        self.blockedLogMessage = blockedLogMessage
        self.failureMessage = failureMessage
    }
}

public struct ApplyRuntimeBundleStopPlan: Equatable, Sendable {
    public let preparesGuestShutdown: Bool

    public init(preparesGuestShutdown: Bool) {
        self.preparesGuestShutdown = preparesGuestShutdown
    }
}

public struct ApplyRuntimeBundleRootfsReplacementPlan: Equatable, Sendable {
    public let stagedRootfs: URL?
    public let rootfsBase: URL
    public let shouldReplace: Bool
    public let skippedLogMessage: String?

    public init(
        stagedRootfs: URL?,
        rootfsBase: URL,
        shouldReplace: Bool,
        skippedLogMessage: String?
    ) {
        self.stagedRootfs = stagedRootfs
        self.rootfsBase = rootfsBase
        self.shouldReplace = shouldReplace
        self.skippedLogMessage = skippedLogMessage
    }
}

public struct RollbackRuntimePlan: Equatable, Sendable {
    public let operationPlan: RuntimeOperationPlan

    public init(operationPlan: RuntimeOperationPlan) {
        self.operationPlan = operationPlan
    }
}

public struct RollbackRuntimePreflightPlan: Equatable, Sendable {
    public let serviceRestartLogMessage: String

    public init(serviceRestartLogMessage: String) {
        self.serviceRestartLogMessage = serviceRestartLogMessage
    }
}

public struct RollbackRuntimeBackupPlan: Equatable, Sendable {
    public let backup: URL
    public let backupRootfs: URL?
    public let backupVersion: URL
    public let restoresRootfsBase: Bool

    public init(
        backup: URL,
        backupRootfs: URL?,
        backupVersion: URL,
        restoresRootfsBase: Bool
    ) {
        self.backup = backup
        self.backupRootfs = backupRootfs
        self.backupVersion = backupVersion
        self.restoresRootfsBase = restoresRootfsBase
    }
}

public enum RollbackRuntimeVersionRestoreDecision: Equatable, Sendable {
    case restoreBackupVersion(source: URL, destination: URL)
    case writeExplicitRollbackMarker(version: String, destinationDirectory: URL)
}

public struct RollbackRuntimeManagedArtifactRestore: Equatable, Sendable {
    public let backupPath: URL
    public let restoreDestination: URL

    public init(backupPath: URL, restoreDestination: URL) {
        self.backupPath = backupPath
        self.restoreDestination = restoreDestination
    }
}

public struct RollbackRuntimeManagedArtifactRestorePlan: Equatable, Sendable {
    public let directoryRestores: [RollbackRuntimeManagedArtifactRestore]
    public let runtimeToolsBackup: URL

    public init(
        directoryRestores: [RollbackRuntimeManagedArtifactRestore],
        runtimeToolsBackup: URL
    ) {
        self.directoryRestores = directoryRestores
        self.runtimeToolsBackup = runtimeToolsBackup
    }
}

public struct RuntimeGuestActivationPlan: Equatable, Sendable {
    public let requiresActivation: Bool
    public let version: String
    public let skippedLogMessage: String?
    public let requestedLogMessage: String?
    public let completedLogMessage: String?

    public init(
        requiresActivation: Bool,
        version: String,
        skippedLogMessage: String?,
        requestedLogMessage: String?,
        completedLogMessage: String?
    ) {
        self.requiresActivation = requiresActivation
        self.version = version
        self.skippedLogMessage = skippedLogMessage
        self.requestedLogMessage = requestedLogMessage
        self.completedLogMessage = completedLogMessage
    }
}

public struct RuntimeGuestShutdownPlan: Equatable, Sendable {
    public let version: String
    public let requestedLogMessage: String
    public let readyLogMessage: String

    public init(
        version: String,
        requestedLogMessage: String,
        readyLogMessage: String
    ) {
        self.version = version
        self.requestedLogMessage = requestedLogMessage
        self.readyLogMessage = readyLogMessage
    }
}

public struct RuntimeGuestWaitResultPlan: Equatable, Sendable {
    public let logMessage: String?
    public let failureMessage: String?

    public init(logMessage: String?, failureMessage: String?) {
        self.logMessage = logMessage
        self.failureMessage = failureMessage
    }
}

public struct UpdateRuntimeUseCase {
    public init() {}

    public func initialHealthDecision(
        snapshot: RuntimeHealthSnapshot
    ) -> ApplyRuntimeBundleInitialHealthDecision {
        guard !RuntimeHealthSnapshotPolicy.isHealthy(snapshot) else {
            return ApplyRuntimeBundleInitialHealthDecision(
                shouldWarn: false,
                warningMessage: nil
            )
        }
        let reasonText = RuntimeFailureReasonText.describe(snapshot.failureReasons)
        return ApplyRuntimeBundleInitialHealthDecision(
            shouldWarn: true,
            warningMessage: "bundle apply preflight warning runtime unhealthy reasons=\(reasonText)"
        )
    }

    public func planApplyBundle(for preflight: ApplyBundlePreflightContext) -> ApplyRuntimeBundlePlan {
        ApplyRuntimeBundlePlan(
            operationPlan: RuntimeOperationPlans.applyBundle(updatesRootfsBase: preflight.updatesRootfsBase)
        )
    }

    public func preflightManifestPlan(
        stagedBundle: URL,
        manifest: UpdateBundleManifest
    ) -> ApplyRuntimeBundlePreflightManifestPlan {
        ApplyRuntimeBundlePreflightManifestPlan(
            stagedRootfs: manifest.artifacts.contains { $0.type == .rootfsBase }
                ? stagedBundle.appendingPathComponent(RuntimeFileNames.rootfsBase)
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
        var capabilities: [RuntimeGuestCapabilityRequirement] = []
        if restartPolicy.restartVM {
            capabilities.append(.prepareUpdateShutdown)
        }
        if manifest.artifacts.contains(where: { $0.type == .guestDeploy }) {
            capabilities.append(.activateUpdate)
        }

        return ApplyRuntimeBundlePreflightCapabilityPlan(
            requiresRuntimeDiskHealthCheck: restartPolicy.restartVM,
            requiredGuestCapabilities: capabilities,
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

    public func stopPlan(restartPolicy: RuntimeServiceRestartPolicy) -> ApplyRuntimeBundleStopPlan {
        ApplyRuntimeBundleStopPlan(preparesGuestShutdown: restartPolicy.restartVM)
    }

    public func rootfsReplacementPlan(
        stagedRootfs: URL?,
        rootfsBase: URL
    ) -> ApplyRuntimeBundleRootfsReplacementPlan {
        ApplyRuntimeBundleRootfsReplacementPlan(
            stagedRootfs: stagedRootfs,
            rootfsBase: rootfsBase,
            shouldReplace: stagedRootfs != nil,
            skippedLogMessage: stagedRootfs == nil ? "rootfs-base replacement skipped; bundle does not include rootfs-base" : nil
        )
    }

    public func diskHealthDecision(
        snapshot: RuntimeHealthSnapshot
    ) -> ApplyRuntimeBundleDiskHealthDecision {
        let blockers = RuntimeUpdatePreflightPolicy.blockingGuestStorageErrors(snapshot.vmErrors)
        guard !blockers.isEmpty else {
            return ApplyRuntimeBundleDiskHealthDecision(
                canApplyUpdate: true,
                blockers: [],
                blockedLogMessage: nil,
                failureMessage: nil
            )
        }

        let codes = blockers.map(\.rawValue).joined(separator: ",")
        return ApplyRuntimeBundleDiskHealthDecision(
            canApplyUpdate: false,
            blockers: blockers,
            blockedLogMessage: "bundle apply blocked by VM guest storage health errors=\(codes)",
            failureMessage: "VM disk health blocks update; run Repair VM Disk before applying update. errors=\(codes)"
        )
    }

    public func planRollback(for preflight: RollbackPreflightContext) -> RollbackRuntimePlan {
        RollbackRuntimePlan(
            operationPlan: RuntimeOperationPlans.rollback(restoresRootfsBase: preflight.restoresRootfsBase)
        )
    }

    public func rollbackPreflightPlan(
        backup: URL,
        restartPolicy: RuntimeServiceRestartPolicy
    ) -> RollbackRuntimePreflightPlan {
        RollbackRuntimePreflightPlan(
            serviceRestartLogMessage: "rollback preflight backup=\(backup.path) vm=\(loadedText(restartPolicy.restartVM)) guestLogSync=\(loadedText(restartPolicy.restartGuestLogSync)) proxy=\(loadedText(restartPolicy.restartProxy)) watchdog=\(loadedText(restartPolicy.restartWatchdog))"
        )
    }

    public func rollbackBackupPlan(
        backup: URL,
        manifest: BackupManifest
    ) -> RollbackRuntimeBackupPlan {
        let backupRootfs = manifest.rootfsBase.map { backup.appendingPathComponent($0) }
        return RollbackRuntimeBackupPlan(
            backup: backup,
            backupRootfs: backupRootfs,
            backupVersion: backup.appendingPathComponent(RuntimeFileNames.runtimeVersion),
            restoresRootfsBase: backupRootfs != nil
        )
    }

    public func rollbackVersionRestoreDecision(
        backupVersion: URL,
        runtimeVersion: URL,
        backupVersionExists: Bool,
        backup: URL
    ) -> RollbackRuntimeVersionRestoreDecision {
        if backupVersionExists {
            return .restoreBackupVersion(source: backupVersion, destination: runtimeVersion)
        }
        return .writeExplicitRollbackMarker(version: "rolled-back", destinationDirectory: backup)
    }

    public func rollbackManagedArtifactRestorePlan(
        backup: URL,
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL
    ) -> RollbackRuntimeManagedArtifactRestorePlan {
        RollbackRuntimeManagedArtifactRestorePlan(
            directoryRestores: [
                RollbackRuntimeManagedArtifactRestore(
                    backupPath: backup.appendingPathComponent(UpdateBundleArtifactType.appBundle.rawValue),
                    restoreDestination: managerAppPath
                ),
                RollbackRuntimeManagedArtifactRestore(
                    backupPath: backup.appendingPathComponent(UpdateBundleArtifactType.nginxBundle.rawValue),
                    restoreDestination: nginxDirectory
                ),
                RollbackRuntimeManagedArtifactRestore(
                    backupPath: backup.appendingPathComponent(UpdateBundleArtifactType.guestDeploy.rawValue),
                    restoreDestination: deployDirectory
                ),
            ],
            runtimeToolsBackup: backup.appendingPathComponent(UpdateBundleArtifactType.runtimeTools.rawValue)
        )
    }

    public func guestActivationPlan(
        manifest: UpdateBundleManifest
    ) -> RuntimeGuestActivationPlan {
        let requiresActivation = manifest.artifacts.contains(where: { $0.type == .guestDeploy })
        guard requiresActivation else {
            return RuntimeGuestActivationPlan(
                requiresActivation: false,
                version: manifest.version,
                skippedLogMessage: "guest update activation not required",
                requestedLogMessage: nil,
                completedLogMessage: nil
            )
        }

        return RuntimeGuestActivationPlan(
            requiresActivation: true,
            version: manifest.version,
            skippedLogMessage: nil,
            requestedLogMessage: "guest update activation requested version=\(manifest.version)",
            completedLogMessage: "guest update activation completed version=\(manifest.version)"
        )
    }

    public func guestActivationRequest(
        plan: RuntimeGuestActivationPlan,
        requestID: String,
        requestedAt: String
    ) -> RuntimeGuestActivationRequest? {
        guard plan.requiresActivation else {
            return nil
        }
        return RuntimeGuestActivationRequest(
            id: requestID,
            requestedAt: requestedAt,
            version: plan.version
        )
    }

    public func guestActivationWaitStartedLogMessage(timeoutSeconds: Double) -> String {
        "waiting for guest update activation result timeoutSeconds=\(timeoutSeconds)"
    }

    public func guestActivationWaitResultPlan(
        _ result: GuestActivationWaitResult
    ) -> RuntimeGuestWaitResultPlan {
        switch result {
        case .completed(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update activation result completed message=\(message)",
                failureMessage: nil
            )
        case .failed(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update activation result failed message=\(message)",
                failureMessage: "runtime health check failed"
            )
        case .timedOut:
            return RuntimeGuestWaitResultPlan(
                logMessage: nil,
                failureMessage: "runtime health check failed"
            )
        }
    }

    public func guestShutdownPlan(version: String) -> RuntimeGuestShutdownPlan {
        RuntimeGuestShutdownPlan(
            version: version,
            requestedLogMessage: "guest update shutdown requested version=\(version)",
            readyLogMessage: "guest update shutdown ready version=\(version)"
        )
    }

    public func guestShutdownRequest(
        plan: RuntimeGuestShutdownPlan,
        requestID: String,
        requestedAt: String
    ) -> RuntimeGuestShutdownRequest {
        RuntimeGuestShutdownRequest(
            id: requestID,
            requestedAt: requestedAt,
            version: plan.version
        )
    }

    public func guestShutdownWaitStartedLogMessage(timeoutSeconds: Double) -> String {
        "waiting for guest update shutdown result timeoutSeconds=\(timeoutSeconds)"
    }

    public func guestShutdownWaitResultPlan(
        _ result: GuestShutdownWaitResult
    ) -> RuntimeGuestWaitResultPlan {
        switch result {
        case .ready(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update shutdown result ready message=\(message)",
                failureMessage: nil
            )
        case .failed(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update shutdown result failed message=\(message)",
                failureMessage: message
            )
        case .timedOut:
            return RuntimeGuestWaitResultPlan(
                logMessage: nil,
                failureMessage: "guest update shutdown timed out"
            )
        }
    }

    private func loadedText(_ loaded: Bool) -> String {
        loaded ? "loaded" : "not-loaded"
    }
}
