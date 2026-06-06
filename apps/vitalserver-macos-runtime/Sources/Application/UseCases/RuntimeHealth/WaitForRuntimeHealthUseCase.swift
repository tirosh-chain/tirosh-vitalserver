import Contracts
import Domain
import Errors

public struct WaitForRuntimeHealthUseCase {
    public init() {}

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
