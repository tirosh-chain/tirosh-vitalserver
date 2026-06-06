import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeApplyBundleWorkflowContext {
    public var backupsDirectory: URL
    public var logsDirectory: URL
    public var rootfsBase: URL
    public var vmDisk: URL
    public var updateFreeSpaceMarginBytes: UInt64

    public init(
        backupsDirectory: URL,
        logsDirectory: URL,
        rootfsBase: URL,
        vmDisk: URL,
        updateFreeSpaceMarginBytes: UInt64
    ) {
        self.backupsDirectory = backupsDirectory
        self.logsDirectory = logsDirectory
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.updateFreeSpaceMarginBytes = updateFreeSpaceMarginBytes
    }
}

public struct RuntimeApplyBundleWorkflowOperations {
    public var stageBundle: (URL) throws -> URL
    public var loadStagedManifest: (URL) throws -> UpdateBundleManifest
    public var resolveRootfsStorage: (ApplyRuntimeBundleRootfsStorageObservationPlan) throws -> ApplyRuntimeBundleRootfsStoragePreflightPlan
    public var createDirectory: (URL, Bool) throws -> Void
    public var directorySize: (URL) throws -> UInt64
    public var requireFreeSpace: (URL, UInt64, RuntimeOperation) throws -> Void
    public var checkCompatibility: (UpdateBundleManifest) throws -> Void
    public var serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    public var runtimeHealthSnapshot: () -> RuntimeHealthSnapshot
    public var executeInitialHealthWarningPlan: (ApplyRuntimeBundleInitialHealthWarningPlan) throws -> Void
    public var executePreflightCapabilityInstruction: (ApplyRuntimeBundlePreflightCapabilityInstruction) throws -> Void
    public var executePreflightFailurePlan: (ApplyRuntimeBundlePreflightFailurePlan) -> Void
    public var createBackup: (String) throws -> URL
    public var prepareLogs: (URL) -> Void
    public var executeFailureRecoveryPlan: (ApplyRuntimeBundleFailureRecoveryPlan) -> Void
    public var statusReporter: RuntimeWorkflowStatusReporter
    public var pruneOldRuntimeArtifacts: () throws -> Void
    public var executeApplyBundleStepPlan: (ApplyRuntimeBundleStepExecutionPlan) throws -> Void
    public var describeError: (Error) -> String
    public var log: (String) -> Void

    public init(
        stageBundle: @escaping (URL) throws -> URL,
        loadStagedManifest: @escaping (URL) throws -> UpdateBundleManifest,
        resolveRootfsStorage: @escaping (ApplyRuntimeBundleRootfsStorageObservationPlan) throws -> ApplyRuntimeBundleRootfsStoragePreflightPlan,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        directorySize: @escaping (URL) throws -> UInt64,
        requireFreeSpace: @escaping (URL, UInt64, RuntimeOperation) throws -> Void,
        checkCompatibility: @escaping (UpdateBundleManifest) throws -> Void,
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy,
        runtimeHealthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        executeInitialHealthWarningPlan: @escaping (ApplyRuntimeBundleInitialHealthWarningPlan) throws -> Void,
        executePreflightCapabilityInstruction: @escaping (ApplyRuntimeBundlePreflightCapabilityInstruction) throws -> Void,
        executePreflightFailurePlan: @escaping (ApplyRuntimeBundlePreflightFailurePlan) -> Void,
        createBackup: @escaping (String) throws -> URL,
        prepareLogs: @escaping (URL) -> Void,
        executeFailureRecoveryPlan: @escaping (ApplyRuntimeBundleFailureRecoveryPlan) -> Void,
        statusReporter: RuntimeWorkflowStatusReporter,
        pruneOldRuntimeArtifacts: @escaping () throws -> Void,
        executeApplyBundleStepPlan: @escaping (ApplyRuntimeBundleStepExecutionPlan) throws -> Void,
        describeError: @escaping (Error) -> String,
        log: @escaping (String) -> Void
    ) {
        self.stageBundle = stageBundle
        self.loadStagedManifest = loadStagedManifest
        self.resolveRootfsStorage = resolveRootfsStorage
        self.createDirectory = createDirectory
        self.directorySize = directorySize
        self.requireFreeSpace = requireFreeSpace
        self.checkCompatibility = checkCompatibility
        self.serviceRestartPolicy = serviceRestartPolicy
        self.runtimeHealthSnapshot = runtimeHealthSnapshot
        self.executeInitialHealthWarningPlan = executeInitialHealthWarningPlan
        self.executePreflightCapabilityInstruction = executePreflightCapabilityInstruction
        self.executePreflightFailurePlan = executePreflightFailurePlan
        self.createBackup = createBackup
        self.prepareLogs = prepareLogs
        self.executeFailureRecoveryPlan = executeFailureRecoveryPlan
        self.statusReporter = statusReporter
        self.pruneOldRuntimeArtifacts = pruneOldRuntimeArtifacts
        self.executeApplyBundleStepPlan = executeApplyBundleStepPlan
        self.describeError = describeError
        self.log = log
    }
}

public struct RuntimeApplyBundleWorkflow {
    public var context: RuntimeApplyBundleWorkflowContext
    public var operations: RuntimeApplyBundleWorkflowOperations

    public init(
        context: RuntimeApplyBundleWorkflowContext,
        operations: RuntimeApplyBundleWorkflowOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func applyBundle(_ bundleURL: URL) throws {
        try runtimeApplyBundleRunner().run(bundleURL: bundleURL)
        operations.log(UpdateRuntimeUseCase().mutableVMDiskPreservedLogMessage(path: context.vmDisk.path))
    }

    private func runtimeApplyBundleRunner() -> RuntimeApplyBundleRunner {
        RuntimeApplyBundleRunner(
            prepareLogs: { operations.prepareLogs(context.logsDirectory) },
            initialHealthSnapshot: operations.runtimeHealthSnapshot,
            executeInitialHealthWarningPlan: operations.executeInitialHealthWarningPlan,
            preparePreflight: prepareApplyBundlePreflight,
            executePreflightFailurePlan: operations.executePreflightFailurePlan,
            executeStep: executeApplyBundleStep,
            executeFailureRecoveryPlan: operations.executeFailureRecoveryPlan,
            statusReporter: operations.statusReporter,
            pruneOldRuntimeArtifacts: operations.pruneOldRuntimeArtifacts,
            describeError: operations.describeError
        )
    }

    private func prepareApplyBundlePreflight(_ bundleURL: URL) throws -> ApplyBundlePreflightContext {
        try RuntimeApplyBundlePreflightRunner(
            stageBundle: operations.stageBundle,
            loadStagedManifest: operations.loadStagedManifest,
            resolveRootfsStorage: operations.resolveRootfsStorage,
            createDirectory: operations.createDirectory,
            requireFreeSpace: operations.requireFreeSpace,
            checkCompatibility: operations.checkCompatibility,
            serviceRestartPolicy: operations.serviceRestartPolicy,
            executeCapabilityInstruction: operations.executePreflightCapabilityInstruction,
            createBackup: operations.createBackup,
            directorySize: operations.directorySize,
            updateFreeSpaceMarginBytes: context.updateFreeSpaceMarginBytes,
            log: operations.log
        ).prepare(
            bundleURL: bundleURL,
            backupsDirectory: context.backupsDirectory,
            rootfsBase: context.rootfsBase
        )
    }

    private func executeApplyBundleStep(
        _ step: RuntimeWorkflowStep,
        preflight: ApplyBundlePreflightContext
    ) throws {
        try RuntimeApplyBundleStepExecutor(
            executeStepPlan: operations.executeApplyBundleStepPlan
        ).execute(step, preflight: preflight, rootfsBase: context.rootfsBase)
    }
}
