import Foundation
import Core
import Contracts

struct RuntimeStatusWriter {
    let reporter: RuntimeStatusReporter
    let timestamp: () -> String
    let runtimeVersion: () -> String
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let latestBackup: () -> URL?
    let projectVitalDBObservation: (VitalDBObservationDocument) -> Void

    init(
        reporter: RuntimeStatusReporter,
        timestamp: @escaping () -> String,
        runtimeVersion: @escaping () -> String,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        latestBackup: @escaping () -> URL?,
        projectVitalDBObservation: @escaping (VitalDBObservationDocument) -> Void = { _ in }
    ) {
        self.reporter = reporter
        self.timestamp = timestamp
        self.runtimeVersion = runtimeVersion
        self.healthSnapshot = healthSnapshot
        self.latestBackup = latestBackup
        self.projectVitalDBObservation = projectVitalDBObservation
    }

    func writeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        let snapshot = healthSnapshot()
        if let vitalDBObservation = snapshot.vitalDBObservation {
            projectVitalDBObservation(vitalDBObservation)
        }
        try reporter.writeStatus(
            status,
            operation: operation,
            message: message,
            updatedAt: timestamp(),
            runtimeVersion: runtimeVersion(),
            healthSnapshot: snapshot,
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
            latestBackup: latestBackup()
        )
    }
}
