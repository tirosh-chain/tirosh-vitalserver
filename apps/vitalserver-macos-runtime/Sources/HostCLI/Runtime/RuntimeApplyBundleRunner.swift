import Foundation
import Core
import Contracts

struct RuntimeApplyBundleRunner {
    var prepareLogs: () throws -> Void
    var initialHealthSnapshot: () -> RuntimeHealthSnapshot
    var preparePreflight: (URL) throws -> ApplyBundlePreflightContext
    var executeStep: (RuntimeWorkflowStep, ApplyBundlePreflightContext) throws -> Void
    var rollback: (URL) throws -> Void
    var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    var statusReporter: RuntimeWorkflowStatusReporter
    var pruneOldRuntimeArtifacts: () throws -> Void
    var reasonText: ([RuntimeFailureReason]) -> String

    func run(bundleURL: URL) throws {
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
            try RuntimeOperationPlanRunner.run(
                plan: RuntimeOperationPlans.applyBundle(updatesRootfsBase: preflight.updatesRootfsBase),
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
