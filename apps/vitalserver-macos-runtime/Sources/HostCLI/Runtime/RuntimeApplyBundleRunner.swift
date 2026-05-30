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
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    var pruneOldRuntimeArtifacts: () throws -> Void
    var reasonText: ([RuntimeFailureReason]) -> String
    var log: (String) -> Void

    func run(bundleURL: URL) throws {
        log("bundle apply started input=\(bundleURL.path)")
        try prepareLogs()
        try writeStatus(.updating, .applyBundle, "bundle apply started")

        let initialHealth = initialHealthSnapshot()
        if !RuntimeHealthSnapshotPolicy.isHealthy(initialHealth) {
            log("bundle apply preflight warning runtime unhealthy reasons=\(reasonText(initialHealth.failureReasons))")
        }

        let preflight: ApplyBundlePreflightContext
        do {
            preflight = try preparePreflight(bundleURL)
        } catch {
            writeRuntimeStatusBestEffort(
                .critical,
                operation: .applyBundle,
                message: "bundle apply preflight failed: \(error)",
                writeStatus: writeStatus,
                log: log
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
                    log("step=\(event.step.rawValue) status=\(event.stepStatus.rawValue)")
                    writeRuntimeProgressBestEffort(event, writeProgress: writeProgress, log: log)
                }
            )
        } catch {
            log("bundle apply failed; rolling back error=\(error)")
            writeRuntimeStatusBestEffort(
                .recovering,
                operation: .applyBundle,
                message: "bundle apply failed; rolling back: \(error)",
                writeStatus: writeStatus,
                log: log
            )
            do {
                try rollback(preflight.backup)
                try startRuntimeServices(preflight.restartPolicy)
                writeRuntimeStatusBestEffort(
                    .degraded,
                    operation: .applyBundle,
                    message: "bundle apply failed; rollback completed: \(error)",
                    writeStatus: writeStatus,
                    log: log
                )
            } catch {
                log("bundle apply rollback failed error=\(error)")
                startRuntimeServicesBestEffort(preflight.restartPolicy)
                writeRuntimeStatusBestEffort(
                    .critical,
                    operation: .applyBundle,
                    message: "bundle apply failed and rollback failed: \(error)",
                    writeStatus: writeStatus,
                    log: log
                )
            }
            throw error
        }

        pruneOldRuntimeArtifactsBestEffort()
        try writeStatus(.healthy, .applyBundle, "bundle applied: \(preflight.manifest.version)")
        log("bundle applied path=\(preflight.stagedBundle.path)")
    }

    private func pruneOldRuntimeArtifactsBestEffort() {
        do {
            try pruneOldRuntimeArtifacts()
        } catch {
            log("runtime artifact cleanup failed after bundle apply error=\(error)")
        }
    }

    private func startRuntimeServicesBestEffort(_ policy: RuntimeServiceRestartPolicy) {
        do {
            try startRuntimeServices(policy)
        } catch {
            log("failed to restart runtime services after rollback failure error=\(error)")
        }
    }
}
