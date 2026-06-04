import Contracts
import Core

public struct RuntimeServiceControlPorts {
    public var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public var stopRuntimeServices: () throws -> Void
    public var serviceStates: ([RuntimeManagedService]) throws -> [RuntimeManagedService: RuntimeServiceState]

    public init(
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        serviceStates: @escaping ([RuntimeManagedService]) throws -> [RuntimeManagedService: RuntimeServiceState]
    ) {
        self.startRuntimeServices = startRuntimeServices
        self.stopRuntimeServices = stopRuntimeServices
        self.serviceStates = serviceStates
    }
}

public struct RuntimeServiceLifecycleObservation: Equatable {
    public let states: [RuntimeManagedService: RuntimeServiceState]

    public init(states: [RuntimeManagedService: RuntimeServiceState]) {
        self.states = states
    }
}

public struct ControlRuntimeServicesUseCase {
    private let ports: RuntimeServiceControlPorts

    public init(ports: RuntimeServiceControlPorts) {
        self.ports = ports
    }

    public func startRequiredServices(
        _ policy: RuntimeServiceRestartPolicy
    ) throws -> RuntimeServiceLifecycleObservation {
        try ports.startRuntimeServices(policy)
        return try observeServices(RuntimeRequiredServicePolicy.requiredServices(for: policy))
    }

    public func stopRuntimeServices(
        observing services: [RuntimeManagedService]
    ) throws -> RuntimeServiceLifecycleObservation {
        try ports.stopRuntimeServices()
        return try observeServices(services)
    }

    public func observeServices(
        _ services: [RuntimeManagedService]
    ) throws -> RuntimeServiceLifecycleObservation {
        RuntimeServiceLifecycleObservation(states: try ports.serviceStates(services))
    }
}
