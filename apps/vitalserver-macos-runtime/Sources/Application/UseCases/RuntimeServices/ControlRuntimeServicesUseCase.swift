import Contracts
import Domain

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

public enum RuntimeServiceControlRequest: Equatable {
    case repairAll
    case startAll
    case stopAll

    public var operation: RuntimeOperation {
        switch self {
        case .repairAll:
            return .repairServices
        case .startAll:
            return .startServices
        case .stopAll:
            return .stopServices
        }
    }
}

public struct RuntimeServiceControlPlan: Equatable {
    public let request: RuntimeServiceControlRequest
    public let operation: RuntimeOperation
    public let startPolicy: RuntimeServiceRestartPolicy?
    public let stopServices: [RuntimeManagedService]
    public let requiredStartedServices: [RuntimeManagedService]
    public let requiredStoppedServices: [RuntimeManagedService]

    public init(
        request: RuntimeServiceControlRequest,
        operation: RuntimeOperation,
        startPolicy: RuntimeServiceRestartPolicy?,
        stopServices: [RuntimeManagedService],
        requiredStartedServices: [RuntimeManagedService],
        requiredStoppedServices: [RuntimeManagedService]
    ) {
        self.request = request
        self.operation = operation
        self.startPolicy = startPolicy
        self.stopServices = stopServices
        self.requiredStartedServices = requiredStartedServices
        self.requiredStoppedServices = requiredStoppedServices
    }
}

public struct ControlRuntimeServicesUseCase {
    private let ports: RuntimeServiceControlPorts

    public init(ports: RuntimeServiceControlPorts) {
        self.ports = ports
    }

    public func plan(_ request: RuntimeServiceControlRequest) -> RuntimeServiceControlPlan {
        let allRuntimeServices = RuntimeRequiredServicePolicy.allRuntimeServices
        let allRequiredServices = RuntimeRequiredServicePolicy.requiredServices(for: allRuntimeServices)
        switch request {
        case .repairAll:
            return RuntimeServiceControlPlan(
                request: request,
                operation: .repairServices,
                startPolicy: allRuntimeServices,
                stopServices: RuntimeManagedService.stopOrder,
                requiredStartedServices: allRequiredServices,
                requiredStoppedServices: RuntimeManagedService.stopOrder
            )
        case .startAll:
            return RuntimeServiceControlPlan(
                request: request,
                operation: .startServices,
                startPolicy: allRuntimeServices,
                stopServices: [],
                requiredStartedServices: allRequiredServices,
                requiredStoppedServices: []
            )
        case .stopAll:
            return RuntimeServiceControlPlan(
                request: request,
                operation: .stopServices,
                startPolicy: nil,
                stopServices: RuntimeManagedService.stopOrder,
                requiredStartedServices: [],
                requiredStoppedServices: RuntimeManagedService.stopOrder
            )
        }
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
