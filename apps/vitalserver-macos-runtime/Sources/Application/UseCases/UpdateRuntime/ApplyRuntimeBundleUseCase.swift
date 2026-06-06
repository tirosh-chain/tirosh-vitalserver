import Contracts
import Domain
import Foundation
import Errors

public struct ApplyRuntimeBundleInput: Equatable, Sendable {
    public let bundleURL: URL

    public init(bundleURL: URL) {
        self.bundleURL = bundleURL
    }
}

public struct ApplyRuntimeBundleOperations {
    public var prepareLogs: () throws -> Void
    public var initialHealthSnapshot: () -> RuntimeHealthSnapshot
    public var executeInitialHealthWarningPlan: (ApplyRuntimeBundleInitialHealthWarningPlan) throws -> Void
    public var preparePreflight: (URL) throws -> ApplyBundlePreflightContext
    public var executePreflightFailurePlan: (ApplyRuntimeBundlePreflightFailurePlan) -> Void
    public var executeStep: (RuntimeWorkflowStep, ApplyBundlePreflightContext) throws -> Void
    public var executeFailureRecoveryPlan: (ApplyRuntimeBundleFailureRecoveryPlan) -> Void
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var publishProgress: (RuntimeStepExecutionEvent) -> Void
    public var pruneOldRuntimeArtifacts: () throws -> Void
    public var describeError: (Error) -> String
    public var log: (String) -> Void

    public init(
        prepareLogs: @escaping () throws -> Void,
        initialHealthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        executeInitialHealthWarningPlan: @escaping (ApplyRuntimeBundleInitialHealthWarningPlan) throws -> Void,
        preparePreflight: @escaping (URL) throws -> ApplyBundlePreflightContext,
        executePreflightFailurePlan: @escaping (ApplyRuntimeBundlePreflightFailurePlan) -> Void,
        executeStep: @escaping (RuntimeWorkflowStep, ApplyBundlePreflightContext) throws -> Void,
        executeFailureRecoveryPlan: @escaping (ApplyRuntimeBundleFailureRecoveryPlan) -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        publishProgress: @escaping (RuntimeStepExecutionEvent) -> Void,
        pruneOldRuntimeArtifacts: @escaping () throws -> Void,
        describeError: @escaping (Error) -> String,
        log: @escaping (String) -> Void
    ) {
        self.prepareLogs = prepareLogs
        self.initialHealthSnapshot = initialHealthSnapshot
        self.executeInitialHealthWarningPlan = executeInitialHealthWarningPlan
        self.preparePreflight = preparePreflight
        self.executePreflightFailurePlan = executePreflightFailurePlan
        self.executeStep = executeStep
        self.executeFailureRecoveryPlan = executeFailureRecoveryPlan
        self.writeStatus = writeStatus
        self.publishProgress = publishProgress
        self.pruneOldRuntimeArtifacts = pruneOldRuntimeArtifacts
        self.describeError = describeError
        self.log = log
    }
}

public struct ApplyRuntimeBundleUseCase {
    public init() {}

    public func run(
        input: ApplyRuntimeBundleInput,
        operations: ApplyRuntimeBundleOperations
    ) throws {
        let update = UpdateRuntimeUseCase()
        let startedPlan = update.applyBundleStartedPlan(inputPath: input.bundleURL.path)
        operations.log(startedPlan.logMessage)
        try operations.prepareLogs()
        try write(startedPlan, operations: operations)

        try operations.executeInitialHealthWarningPlan(update.initialHealthWarningPlan(
            snapshot: operations.initialHealthSnapshot()
        ))

        let preflight: ApplyBundlePreflightContext
        do {
            preflight = try operations.preparePreflight(input.bundleURL)
        } catch {
            operations.executePreflightFailurePlan(update.applyBundlePreflightFailurePlan(
                reason: operations.describeError(error)
            ))
            throw error
        }

        do {
            let plan = update.planApplyBundle(for: preflight)
            try RuntimeOperationPlanRunner.run(
                plan: plan.operationPlan,
                status: .updating,
                execute: { step in
                    try operations.executeStep(step, preflight)
                },
                publish: operations.publishProgress
            )
        } catch {
            operations.executeFailureRecoveryPlan(update.applyBundleFailureRecoveryPlan(
                preflight: preflight,
                applyFailureReason: operations.describeError(error)
            ))
            throw error
        }

        pruneOldRuntimeArtifactsBestEffort(operations: operations, update: update)
        let completedPlan = update.applyBundleCompletedPlan(
            version: preflight.manifest.version,
            stagedBundlePath: preflight.stagedBundle.path
        )
        try write(completedPlan, operations: operations)
        operations.log(completedPlan.logMessage)
    }

    private func pruneOldRuntimeArtifactsBestEffort(
        operations: ApplyRuntimeBundleOperations,
        update: UpdateRuntimeUseCase
    ) {
        do {
            try operations.pruneOldRuntimeArtifacts()
        } catch {
            operations.log(update.applyBundleArtifactCleanupFailedLogMessage(
                reason: operations.describeError(error)
            ))
        }
    }

    private func write(
        _ plan: UpdateRuntimeLoggedStatusPlan,
        operations: ApplyRuntimeBundleOperations
    ) throws {
        try operations.writeStatus(plan.status, plan.operation, plan.statusMessage)
    }
}
