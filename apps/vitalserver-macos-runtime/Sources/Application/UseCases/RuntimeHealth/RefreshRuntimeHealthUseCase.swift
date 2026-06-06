import Contracts
import Domain

public struct RuntimeHealthRefreshPorts {
    public var healthSnapshot: () -> RuntimeHealthSnapshot

    public init(
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot
    ) {
        self.healthSnapshot = healthSnapshot
    }
}

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

public struct RefreshRuntimeHealthUseCase {
    private let ports: RuntimeHealthRefreshPorts

    public init(ports: RuntimeHealthRefreshPorts) {
        self.ports = ports
    }

    public func refresh() -> RuntimeHealthRefreshDecision {
        let snapshot = ports.healthSnapshot()

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
