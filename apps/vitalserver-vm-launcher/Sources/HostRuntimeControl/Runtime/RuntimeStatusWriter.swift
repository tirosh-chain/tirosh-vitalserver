import Foundation
import RuntimeCore

struct RuntimeStatusWriter {
    let reporter: RuntimeStatusReporter
    let timestamp: () -> String
    let runtimeVersion: () -> String
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let latestBackup: () -> URL?

    func writeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        try reporter.writeStatus(
            status,
            operation: operation,
            message: message,
            updatedAt: timestamp(),
            runtimeVersion: runtimeVersion(),
            healthSnapshot: healthSnapshot(),
            latestBackup: latestBackup(),
            progress: progress
        )
    }

    func writeProgress(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = []
    ) throws {
        try reporter.writeProgress(
            status,
            operation: operation,
            step: step,
            stepStatus: stepStatus,
            phase: phase,
            message: message,
            reasonCodes: reasonCodes,
            updatedAt: timestamp(),
            runtimeVersion: runtimeVersion(),
            healthSnapshot: healthSnapshot(),
            latestBackup: latestBackup()
        )
    }
}
