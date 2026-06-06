import Contracts
import Domain

public struct RuntimeHealthWaitPorts {
    public var serviceStates: ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState]
    public var healthSnapshot: () -> RuntimeHealthSnapshot

    public init(
        serviceStates: @escaping ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState],
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot
    ) {
        self.serviceStates = serviceStates
        self.healthSnapshot = healthSnapshot
    }
}

public struct WaitForRuntimeHealthUseCase {
    private let ports: RuntimeHealthWaitPorts

    public init(ports: RuntimeHealthWaitPorts) {
        self.ports = ports
    }

    public func observe(policy: RuntimeServiceRestartPolicy) -> RuntimeHealthWaitObservation {
        let requiredServices = RuntimeRequiredServicePolicy.requiredServices(for: policy)
        let states = ports.serviceStates(Self.observedServices)
        return RuntimeHealthWaitObservation(
            requiredServices: requiredServices,
            serviceStates: states,
            snapshot: ports.healthSnapshot()
        )
    }

    public func currentSnapshot() -> RuntimeHealthSnapshot {
        ports.healthSnapshot()
    }

    private static let observedServices: [RuntimeManagedService] = [
        .vm,
        .guestLogSync,
        .proxy,
        .watchdog,
    ]
}
