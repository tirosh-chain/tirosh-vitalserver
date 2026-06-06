import Foundation
import Contracts

public struct RuntimeStatusWriter {
    public let reporter: RuntimeStatusReporter
    public let timestamp: () -> String
    public let runtimeVersion: () -> String
    public let healthSnapshot: () -> RuntimeHealthSnapshot
    public let latestBackup: () -> URL?

    public init(
        reporter: RuntimeStatusReporter,
        timestamp: @escaping () -> String,
        runtimeVersion: @escaping () -> String,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        latestBackup: @escaping () -> URL?
    ) {
        self.reporter = reporter
        self.timestamp = timestamp
        self.runtimeVersion = runtimeVersion
        self.healthSnapshot = healthSnapshot
        self.latestBackup = latestBackup
    }

    @discardableResult
    public func writeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws -> RuntimeHealthSnapshot {
        let snapshot = healthSnapshot()
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
        return snapshot
    }

    public func writeProgress(
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
