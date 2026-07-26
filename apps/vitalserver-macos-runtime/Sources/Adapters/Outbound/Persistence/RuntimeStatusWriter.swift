import Foundation
import Contracts
import Errors

public struct RuntimeStatusWriter {
    public let reporter: RuntimeStatusReporter
    public let timestamp: () -> String
    public let runtimeVersion: () -> String
    public let healthSnapshot: () -> RuntimeHealthSnapshot
    public let latestBackup: () throws -> URL?

    public init(
        reporter: RuntimeStatusReporter,
        timestamp: @escaping () -> String,
        runtimeVersion: @escaping () -> String,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        latestBackup: @escaping () throws -> URL?
    ) {
        self.reporter = reporter
        self.timestamp = timestamp
        self.runtimeVersion = runtimeVersion
        self.healthSnapshot = healthSnapshot
        self.latestBackup = latestBackup
    }

    @discardableResult
    public func writeStatus(
        _ status: RuntimeStatusLevel
    ) throws -> RuntimeHealthSnapshot {
        let snapshot = healthSnapshot()
        try reporter.writeStatus(
            status,
            runtimeVersion: runtimeVersion(),
            healthSnapshot: snapshot,
            latestBackup: try latestBackup()
        )
        return snapshot
    }

    public func writeProgress(
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = []
    ) throws {
        try reporter.writeProgress(
            operation: operation,
            step: step,
            stepStatus: stepStatus,
            phase: phase,
            message: message,
            reasonCodes: reasonCodes,
            updatedAt: timestamp()
        )
    }
}
