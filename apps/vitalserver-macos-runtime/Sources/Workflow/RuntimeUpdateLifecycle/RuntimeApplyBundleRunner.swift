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
    public var reasonText: ([RuntimeFailureReason]) -> String
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
        pruneOldRuntimeArtifacts: @escaping () throws -> Void,
        reasonText: @escaping ([RuntimeFailureReason]) -> String
    ) {
        self.prepareLogs = prepareLogs
        self.initialHealthSnapshot = initialHealthSnapshot
        self.preparePreflight = preparePreflight
        self.executeStep = executeStep
        self.rollback = rollback
        self.startRuntimeServices = startRuntimeServices
        self.statusReporter = statusReporter
        self.pruneOldRuntimeArtifacts = pruneOldRuntimeArtifacts
        self.reasonText = reasonText
    }

    public func run(bundleURL: URL) throws {
        statusReporter.log("bundle apply started input=\(bundleURL.path)")
        try prepareLogs()
        try statusReporter.write(.updating, operation: .applyBundle, message: "bundle apply started")

        let initialHealth = initialHealthSnapshot()
        if !RuntimeHealthSnapshotPolicy.isHealthy(initialHealth) {
            statusReporter.log("bundle apply preflight warning runtime unhealthy reasons=\(reasonText(initialHealth.failureReasons))")
        }

        let preflight: ApplyBundlePreflightContext
        do {
            preflight = try preparePreflight(bundleURL)
        } catch {
            statusReporter.writeBestEffort(
                .critical,
                operation: .applyBundle,
                message: "bundle apply preflight failed: \(error)"
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
            statusReporter.log("bundle apply failed; rolling back error=\(error)")
            statusReporter.writeBestEffort(
                .recovering,
                operation: .applyBundle,
                message: "bundle apply failed; rolling back: \(error)"
            )
            do {
                try rollback(preflight.backup)
                try startRuntimeServices(preflight.restartPolicy)
                statusReporter.writeBestEffort(
                    .degraded,
                    operation: .applyBundle,
                    message: "bundle apply failed; rollback completed: \(error)"
                )
            } catch {
                statusReporter.log("bundle apply rollback failed error=\(error)")
                startRuntimeServicesBestEffort(preflight.restartPolicy)
                statusReporter.writeBestEffort(
                    .critical,
                    operation: .applyBundle,
                    message: "bundle apply failed and rollback failed: \(error)"
                )
            }
            throw error
        }

        pruneOldRuntimeArtifactsBestEffort()
        try statusReporter.write(.healthy, operation: .applyBundle, message: "bundle applied: \(preflight.manifest.version)")
        statusReporter.log("bundle applied path=\(preflight.stagedBundle.path)")
    }

    private func pruneOldRuntimeArtifactsBestEffort() {
        do {
            try pruneOldRuntimeArtifacts()
        } catch {
            statusReporter.log("runtime artifact cleanup failed after bundle apply error=\(error)")
        }
    }

    private func startRuntimeServicesBestEffort(_ policy: RuntimeServiceRestartPolicy) {
        do {
            try startRuntimeServices(policy)
        } catch {
            statusReporter.log("failed to restart runtime services after rollback failure error=\(error)")
        }
    }
}
