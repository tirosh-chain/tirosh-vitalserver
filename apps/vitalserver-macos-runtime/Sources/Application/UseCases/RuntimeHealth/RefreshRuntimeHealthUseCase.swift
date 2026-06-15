import Contracts
import Domain
import Errors

public struct RuntimeHealthRefreshDecision: Equatable {
    public let snapshot: RuntimeHealthSnapshot
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let statusMessage: String
    public let observedEventMessage: String?
    public let outputLine: String
    public let healthy: Bool

    public init(
        snapshot: RuntimeHealthSnapshot,
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        statusMessage: String,
        observedEventMessage: String?,
        outputLine: String,
        healthy: Bool
    ) {
        self.snapshot = snapshot
        self.status = status
        self.operation = operation
        self.statusMessage = statusMessage
        self.observedEventMessage = observedEventMessage
        self.outputLine = outputLine
        self.healthy = healthy
    }
}

public struct RefreshRuntimeHealthOperations {
    public let healthSnapshot: () -> RuntimeHealthSnapshot
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let writeStatusBestEffort: (RuntimeStatusLevel, RuntimeOperation, String) -> Void
    public let recordObservedEventBestEffort: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot
    ) -> Void

    public init(
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        recordObservedEventBestEffort: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot
        ) -> Void
    ) {
        self.healthSnapshot = healthSnapshot
        self.writeStatus = writeStatus
        self.writeStatusBestEffort = writeStatusBestEffort
        self.recordObservedEventBestEffort = recordObservedEventBestEffort
    }
}

public struct RefreshRuntimeHealthUseCase {
    public init() {}

    public func refresh(operations: RefreshRuntimeHealthOperations) throws -> RuntimeHealthRefreshDecision {
        let decision = decision(snapshot: operations.healthSnapshot())

        guard decision.healthy else {
            operations.writeStatusBestEffort(
                decision.status,
                decision.operation,
                decision.statusMessage
            )
            if let observedEventMessage = decision.observedEventMessage {
                operations.recordObservedEventBestEffort(
                    decision.status,
                    decision.operation,
                    observedEventMessage,
                    decision.snapshot
                )
            }
            throw RefreshRuntimeHealthUseCaseError.operationFailed(decision.statusMessage)
        }

        try operations.writeStatus(decision.status, decision.operation, decision.statusMessage)
        return decision
    }

    public func decision(snapshot: RuntimeHealthSnapshot) -> RuntimeHealthRefreshDecision {
        guard !RuntimeHealthSnapshotPolicy.isHealthy(snapshot) else {
            return RuntimeHealthRefreshDecision(
                snapshot: snapshot,
                status: .healthy,
                operation: .health,
                statusMessage: "runtime health check passed",
                observedEventMessage: nil,
                outputLine: "health: ok",
                healthy: true
            )
        }

        let reasons = RuntimeFailureReasonText.describe(snapshot.failureReasons)
        return RuntimeHealthRefreshDecision(
            snapshot: snapshot,
            status: .degraded,
            operation: .health,
            statusMessage: "runtime health check failed: \(reasons)",
            observedEventMessage: "\(observedErrorLabel(snapshot)) observed: \(observedErrorText(snapshot))",
            outputLine: "health: failed",
            healthy: false
        )
    }

    public func observedEventType(
        snapshot: RuntimeHealthSnapshot,
        defaultEventType: RuntimeEventType
    ) -> RuntimeEventType {
        RuntimeObservedEventTypePolicy.eventType(for: snapshot, defaultEventType: defaultEventType)
    }

    private func observedErrorLabel(_ snapshot: RuntimeHealthSnapshot) -> String {
        snapshot.vmErrors.isEmpty ? "runtime domain errors" : "runtime VM errors"
    }

    private func observedErrorText(_ snapshot: RuntimeHealthSnapshot) -> String {
        let vmErrors = snapshot.vmErrors.map(\.rawValue)
        if !vmErrors.isEmpty {
            return vmErrors.joined(separator: ", ")
        }
        return RuntimeFailureReasonText.describe(snapshot.failureReasons)
    }
}
