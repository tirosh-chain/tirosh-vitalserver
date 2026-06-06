import Contracts
import Domain
import Errors
import Foundation

public struct RuntimeHealthWaitPlan: Equatable {
    public let policy: RuntimeServiceRestartPolicy
    public let shouldWait: Bool
    public let observedServices: [RuntimeManagedService]
    public let skippedMessage: String?
    public let startedMessage: String?

    public init(
        policy: RuntimeServiceRestartPolicy,
        shouldWait: Bool,
        observedServices: [RuntimeManagedService],
        skippedMessage: String?,
        startedMessage: String?
    ) {
        self.policy = policy
        self.shouldWait = shouldWait
        self.observedServices = observedServices
        self.skippedMessage = skippedMessage
        self.startedMessage = startedMessage
    }
}

public struct RuntimeHealthWaitProgressPlan: Equatable {
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let logMessage: String
    public let statusMessage: String

    public init(
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        logMessage: String,
        statusMessage: String
    ) {
        self.status = status
        self.operation = operation
        self.logMessage = logMessage
        self.statusMessage = statusMessage
    }
}

public struct WaitForRuntimeHealthUseCase {
    public init() {}

    public func plan(
        policy: RuntimeServiceRestartPolicy,
        timeoutSeconds: Double
    ) -> RuntimeHealthWaitPlan {
        guard policy.anyServiceWasRunning else {
            return RuntimeHealthWaitPlan(
                policy: policy,
                shouldWait: false,
                observedServices: [],
                skippedMessage: "runtime services were not running before apply; skipping health wait",
                startedMessage: nil
            )
        }

        return RuntimeHealthWaitPlan(
            policy: policy,
            shouldWait: true,
            observedServices: observedServices(),
            skippedMessage: nil,
            startedMessage: "waiting for runtime health timeoutSeconds=\(timeoutSeconds)"
        )
    }

    public func observedServices() -> [RuntimeManagedService] {
        [
            .vm,
            .guestLogSync,
            .proxy,
            .watchdog,
        ]
    }

    public func observation(
        policy: RuntimeServiceRestartPolicy,
        serviceStates: [RuntimeManagedService: RuntimeServiceState],
        snapshot: RuntimeHealthSnapshot
    ) -> RuntimeHealthWaitObservation {
        let requiredServices = RuntimeRequiredServicePolicy.requiredServices(for: policy)
        return RuntimeHealthWaitObservation(
            requiredServices: requiredServices,
            serviceStates: serviceStates,
            snapshot: snapshot
        )
    }

    public func progressPlan(reasons: [RuntimeFailureReason]) -> RuntimeHealthWaitProgressPlan {
        let reasonText = RuntimeFailureReasonText.describe(reasons)
        return RuntimeHealthWaitProgressPlan(
            status: .recovering,
            operation: .health,
            logMessage: "waiting for runtime health reasons=\(reasonText)",
            statusMessage: "waiting for runtime health: \(reasonText)"
        )
    }

    public func healthyLogMessage(snapshot: RuntimeHealthSnapshot) -> String {
        "runtime health ok hostProxyHTTP=\(snapshot.hostProxyHTTP)"
    }

    public func failedEarlyMessage(reason: RuntimeFailureReason) -> String {
        "runtime health failed early reason=\(reason.rawValue)"
    }

    public func timedOutFailureMessage(reasons: [RuntimeFailureReason]) -> String {
        "runtime health timed out reasons=\(RuntimeFailureReasonText.describe(reasons))"
    }
}
