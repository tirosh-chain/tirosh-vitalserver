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
    public var executePreflight: (ApplyRuntimeBundlePreflightInput) throws -> ApplyBundlePreflightContext
    public var runtimeHealthSnapshot: () -> RuntimeHealthSnapshot
    public var executeInitialHealthWarningPlan: (ApplyRuntimeBundleInitialHealthWarningPlan) throws -> Void
    public var executePreflightFailurePlan: (ApplyRuntimeBundlePreflightFailurePlan) -> Void
    public var prepareLogs: (URL) -> Void
    public var executeFailureRecoveryPlan: (ApplyRuntimeBundleFailureRecoveryPlan) -> Void
    public var statusReporter: RuntimeWorkflowStatusReporter
    public var pruneOldRuntimeArtifacts: () throws -> Void
    public var executeApplyBundleStepPlan: (ApplyRuntimeBundleStepExecutionPlan) throws -> Void
    public var describeError: (Error) -> String
    public var log: (String) -> Void

    public init(
        executePreflight: @escaping (ApplyRuntimeBundlePreflightInput) throws -> ApplyBundlePreflightContext,
        runtimeHealthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        executeInitialHealthWarningPlan: @escaping (ApplyRuntimeBundleInitialHealthWarningPlan) throws -> Void,
        executePreflightFailurePlan: @escaping (ApplyRuntimeBundlePreflightFailurePlan) -> Void,
        prepareLogs: @escaping (URL) -> Void,
        executeFailureRecoveryPlan: @escaping (ApplyRuntimeBundleFailureRecoveryPlan) -> Void,
        statusReporter: RuntimeWorkflowStatusReporter,
        pruneOldRuntimeArtifacts: @escaping () throws -> Void,
        executeApplyBundleStepPlan: @escaping (ApplyRuntimeBundleStepExecutionPlan) throws -> Void,
        describeError: @escaping (Error) -> String,
        log: @escaping (String) -> Void
    ) {
        self.executePreflight = executePreflight
        self.runtimeHealthSnapshot = runtimeHealthSnapshot
        self.executeInitialHealthWarningPlan = executeInitialHealthWarningPlan
        self.executePreflightFailurePlan = executePreflightFailurePlan
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
        try applyRuntimeBundleUseCaseRun(bundleURL)
        operations.log(UpdateRuntimeUseCase().mutableVMDiskPreservedLogMessage(path: context.vmDisk.path))
    }

    private func applyRuntimeBundleUseCaseRun(_ bundleURL: URL) throws {
        try ApplyRuntimeBundleUseCase().run(
            input: ApplyRuntimeBundleInput(bundleURL: bundleURL),
            operations: ApplyRuntimeBundleOperations(
                prepareLogs: { operations.prepareLogs(context.logsDirectory) },
                initialHealthSnapshot: operations.runtimeHealthSnapshot,
                executeInitialHealthWarningPlan: operations.executeInitialHealthWarningPlan,
                preparePreflight: prepareApplyBundlePreflight,
                executePreflightFailurePlan: operations.executePreflightFailurePlan,
                executeStep: executeApplyBundleStep,
                executeFailureRecoveryPlan: operations.executeFailureRecoveryPlan,
                writeStatus: { status, operation, message in
                    try operations.statusReporter.write(status, operation: operation, message: message)
                },
                publishProgress: operations.statusReporter.publishProgress,
                pruneOldRuntimeArtifacts: operations.pruneOldRuntimeArtifacts,
                describeError: operations.describeError,
                log: operations.statusReporter.log
            )
        )
    }

    private func prepareApplyBundlePreflight(_ bundleURL: URL) throws -> ApplyBundlePreflightContext {
        try operations.executePreflight(ApplyRuntimeBundlePreflightInput(
            bundleURL: bundleURL,
            backupsDirectory: context.backupsDirectory,
            rootfsBase: context.rootfsBase,
            updateFreeSpaceMarginBytes: context.updateFreeSpaceMarginBytes
        ))
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
