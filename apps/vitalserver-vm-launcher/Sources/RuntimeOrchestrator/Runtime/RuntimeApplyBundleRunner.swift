import Foundation
import RuntimeCore

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
        if !initialHealth.isHealthy {
            log("bundle apply preflight warning runtime unhealthy reasons=\(reasonText(initialHealth.failureReasons))")
        }

        let preflight: ApplyBundlePreflightContext
        do {
            preflight = try preparePreflight(bundleURL)
        } catch {
            try? writeStatus(.critical, .applyBundle, "bundle apply preflight failed: \(error)")
            throw error
        }

        do {
            try RuntimeOperationPlanRunner.run(
                plan: RuntimeOperationPlans.applyBundle,
                status: .updating,
                execute: { step in
                    try executeStep(step, preflight)
                },
                publish: { event in
                    log("step=\(event.step.rawValue) status=\(event.stepStatus.rawValue)")
                    try? writeProgress(event)
                }
            )
        } catch {
            log("bundle apply failed; rolling back error=\(error)")
            try? writeStatus(.recovering, .applyBundle, "bundle apply failed; rolling back: \(error)")
            do {
                try rollback(preflight.backup)
                try startRuntimeServices(preflight.restartPolicy)
                try? writeStatus(.degraded, .applyBundle, "bundle apply failed; rollback completed: \(error)")
            } catch {
                log("bundle apply rollback failed error=\(error)")
                try? startRuntimeServices(preflight.restartPolicy)
                try? writeStatus(.critical, .applyBundle, "bundle apply failed and rollback failed: \(error)")
            }
            throw error
        }

        try writeStatus(.healthy, .applyBundle, "bundle applied: \(preflight.manifest.version)")
        try pruneOldRuntimeArtifacts()
        log("bundle applied path=\(preflight.stagedBundle.path)")
    }
}
