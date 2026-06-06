import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeApplyBundleRunner {
    public var prepareLogs: () throws -> Void
    public var initialHealthSnapshot: () -> RuntimeHealthSnapshot
    public var preparePreflight: (URL) throws -> ApplyBundlePreflightContext
    public var executeStep: (RuntimeWorkflowStep, ApplyBundlePreflightContext) throws -> Void
    public var rollback: (URL) throws -> Void
    public var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public var statusReporter: RuntimeWorkflowStatusReporter
    public var pruneOldRuntimeArtifacts: () throws -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        prepareLogs: @escaping () throws -> Void,
        initialHealthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        preparePreflight: @escaping (URL) throws -> ApplyBundlePreflightContext,
        executeStep: @escaping (RuntimeWorkflowStep, ApplyBundlePreflightContext) throws -> Void,
        rollback: @escaping (URL) throws -> Void,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        statusReporter: RuntimeWorkflowStatusReporter,
        pruneOldRuntimeArtifacts: @escaping () throws -> Void
    ) {
        self.prepareLogs = prepareLogs
        self.initialHealthSnapshot = initialHealthSnapshot
        self.preparePreflight = preparePreflight
        self.executeStep = executeStep
        self.rollback = rollback
        self.startRuntimeServices = startRuntimeServices
        self.statusReporter = statusReporter
        self.pruneOldRuntimeArtifacts = pruneOldRuntimeArtifacts
    }

    public func run(bundleURL: URL) throws {
        let startedPlan = useCase.applyBundleStartedPlan(inputPath: bundleURL.path)
        statusReporter.log(startedPlan.logMessage)
        try prepareLogs()
        try write(startedPlan)

        let initialHealth = initialHealthSnapshot()
        let initialHealthDecision = useCase.initialHealthDecision(
            snapshot: initialHealth
        )
        if let warningMessage = initialHealthDecision.warningMessage {
            statusReporter.log(warningMessage)
        }

        let preflight: ApplyBundlePreflightContext
        do {
            preflight = try preparePreflight(bundleURL)
        } catch {
            let failedPlan = useCase.applyBundlePreflightFailedStatusPlan(reason: "\(error)")
            statusReporter.writeBestEffort(
                failedPlan.status,
                operation: failedPlan.operation,
                message: failedPlan.message
            )
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
            let rollbackStartedPlan = useCase.applyBundleRollbackStartedPlan(reason: "\(error)")
            statusReporter.log(rollbackStartedPlan.logMessage)
            statusReporter.writeBestEffort(
                rollbackStartedPlan.status,
                operation: rollbackStartedPlan.operation,
                message: rollbackStartedPlan.statusMessage
            )
            do {
                try rollback(preflight.backup)
                try startRuntimeServices(preflight.restartPolicy)
                let rollbackCompletedPlan = useCase.applyBundleRollbackCompletedStatusPlan(reason: "\(error)")
                statusReporter.writeBestEffort(
                    rollbackCompletedPlan.status,
                    operation: rollbackCompletedPlan.operation,
                    message: rollbackCompletedPlan.message
                )
            } catch {
                let rollbackFailedPlan = useCase.applyBundleRollbackFailedPlan(reason: "\(error)")
                statusReporter.log(rollbackFailedPlan.logMessage)
                startRuntimeServicesBestEffort(preflight.restartPolicy)
                statusReporter.writeBestEffort(
                    rollbackFailedPlan.status,
                    operation: rollbackFailedPlan.operation,
                    message: rollbackFailedPlan.statusMessage
                )
            }
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
            statusReporter.log(useCase.applyBundleArtifactCleanupFailedLogMessage(reason: "\(error)"))
        }
    }

    private func startRuntimeServicesBestEffort(_ policy: RuntimeServiceRestartPolicy) {
        do {
            try startRuntimeServices(policy)
        } catch {
            statusReporter.log(useCase.applyBundleRollbackFailureServiceRestartFailedLogMessage(reason: "\(error)"))
        }
    }

    private func write(_ plan: UpdateRuntimeLoggedStatusPlan) throws {
        try statusReporter.write(plan.status, operation: plan.operation, message: plan.statusMessage)
    }
}
