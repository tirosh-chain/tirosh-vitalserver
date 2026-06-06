import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeApplyBundleRunner {
    public var prepareLogs: () throws -> Void
    public var initialHealthSnapshot: () -> RuntimeHealthSnapshot
    public var executeInitialHealthWarningPlan: (ApplyRuntimeBundleInitialHealthWarningPlan) throws -> Void
    public var preparePreflight: (URL) throws -> ApplyBundlePreflightContext
    public var executePreflightFailurePlan: (ApplyRuntimeBundlePreflightFailurePlan) -> Void
    public var executeStep: (RuntimeWorkflowStep, ApplyBundlePreflightContext) throws -> Void
    public var executeFailureRecoveryPlan: (ApplyRuntimeBundleFailureRecoveryPlan) -> Void
    public var statusReporter: RuntimeWorkflowStatusReporter
    public var pruneOldRuntimeArtifacts: () throws -> Void
    public var describeError: (Error) -> String
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        prepareLogs: @escaping () throws -> Void,
        initialHealthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        executeInitialHealthWarningPlan: @escaping (ApplyRuntimeBundleInitialHealthWarningPlan) throws -> Void,
        preparePreflight: @escaping (URL) throws -> ApplyBundlePreflightContext,
        executePreflightFailurePlan: @escaping (ApplyRuntimeBundlePreflightFailurePlan) -> Void,
        executeStep: @escaping (RuntimeWorkflowStep, ApplyBundlePreflightContext) throws -> Void,
        executeFailureRecoveryPlan: @escaping (ApplyRuntimeBundleFailureRecoveryPlan) -> Void,
        statusReporter: RuntimeWorkflowStatusReporter,
        pruneOldRuntimeArtifacts: @escaping () throws -> Void,
        describeError: @escaping (Error) -> String
    ) {
        self.prepareLogs = prepareLogs
        self.initialHealthSnapshot = initialHealthSnapshot
        self.executeInitialHealthWarningPlan = executeInitialHealthWarningPlan
        self.preparePreflight = preparePreflight
        self.executePreflightFailurePlan = executePreflightFailurePlan
        self.executeStep = executeStep
        self.executeFailureRecoveryPlan = executeFailureRecoveryPlan
        self.statusReporter = statusReporter
        self.pruneOldRuntimeArtifacts = pruneOldRuntimeArtifacts
        self.describeError = describeError
    }

    public func run(bundleURL: URL) throws {
        let startedPlan = useCase.applyBundleStartedPlan(inputPath: bundleURL.path)
        statusReporter.log(startedPlan.logMessage)
        try prepareLogs()
        try write(startedPlan)

        try executeInitialHealthWarningPlan(useCase.initialHealthWarningPlan(snapshot: initialHealthSnapshot()))

        let preflight: ApplyBundlePreflightContext
        do {
            preflight = try preparePreflight(bundleURL)
        } catch {
            executePreflightFailurePlan(useCase.applyBundlePreflightFailurePlan(reason: describeError(error)))
            throw error
        }

        do {
            let plan = useCase.planApplyBundle(for: preflight)
            try RuntimeOperationPlanRunner.run(
                plan: plan.operationPlan,
                status: .updating,
                execute: { step in
                    try executeStep(step, preflight)
                },
                publish: { event in
                    statusReporter.publishProgress(event)
                }
            )
        } catch {
            let applyFailureReason = describeError(error)
            executeFailureRecoveryPlan(useCase.applyBundleFailureRecoveryPlan(
                preflight: preflight,
                applyFailureReason: applyFailureReason
            ))
            throw error
        }

        pruneOldRuntimeArtifactsBestEffort()
        let completedPlan = useCase.applyBundleCompletedPlan(
            version: preflight.manifest.version,
            stagedBundlePath: preflight.stagedBundle.path
        )
        try write(completedPlan)
        statusReporter.log(completedPlan.logMessage)
    }

    private func pruneOldRuntimeArtifactsBestEffort() {
        do {
            try pruneOldRuntimeArtifacts()
        } catch {
            statusReporter.log(useCase.applyBundleArtifactCleanupFailedLogMessage(reason: describeError(error)))
        }
    }

    private func write(_ plan: UpdateRuntimeLoggedStatusPlan) throws {
        try statusReporter.write(plan.status, operation: plan.operation, message: plan.statusMessage)
    }
}
