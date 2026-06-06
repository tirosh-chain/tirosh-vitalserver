import Contracts
import Domain
import Errors

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
}
