import Contracts
import Domain
import Errors

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
    public let requestedLogMessage: String
    public let requestedStatusPlan: RuntimeServiceControlStatusPlan?
    public let completedStatusPlan: RuntimeServiceControlStatusPlan

    public init(
        request: RuntimeServiceControlRequest,
        operation: RuntimeOperation,
        startPolicy: RuntimeServiceRestartPolicy?,
        stopServices: [RuntimeManagedService],
        requiredStartedServices: [RuntimeManagedService],
        requiredStoppedServices: [RuntimeManagedService],
        requestedLogMessage: String,
        requestedStatusPlan: RuntimeServiceControlStatusPlan?,
        completedStatusPlan: RuntimeServiceControlStatusPlan
    ) {
        self.request = request
        self.operation = operation
        self.startPolicy = startPolicy
        self.stopServices = stopServices
        self.requiredStartedServices = requiredStartedServices
        self.requiredStoppedServices = requiredStoppedServices
        self.requestedLogMessage = requestedLogMessage
        self.requestedStatusPlan = requestedStatusPlan
        self.completedStatusPlan = completedStatusPlan
    }
}

public struct RuntimeServiceControlStatusPlan: Equatable {
    public let logMessage: String
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let statusMessage: String

    public init(
        logMessage: String,
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        statusMessage: String
    ) {
        self.logMessage = logMessage
        self.status = status
        self.operation = operation
        self.statusMessage = statusMessage
    }
}

public struct RuntimeServiceControlResult: Equatable {
    public let plan: RuntimeServiceControlPlan

    public init(plan: RuntimeServiceControlPlan) {
        self.plan = plan
    }
}

public struct ControlRuntimeServicesUseCase {
    public init() {}

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
                requiredStoppedServices: RuntimeManagedService.stopOrder,
                requestedLogMessage: "runtime services repair requested",
                requestedStatusPlan: RuntimeServiceControlStatusPlan(
                    logMessage: "runtime services repair requested",
                    status: .recovering,
                    operation: .repairServices,
                    statusMessage: "runtime services repair requested"
                ),
                completedStatusPlan: RuntimeServiceControlStatusPlan(
                    logMessage: "runtime services repair dispatched",
                    status: .recovering,
                    operation: .repairServices,
                    statusMessage: "runtime services repair dispatched"
                )
            )
        case .startAll:
            return RuntimeServiceControlPlan(
                request: request,
                operation: .startServices,
                startPolicy: allRuntimeServices,
                stopServices: [],
                requiredStartedServices: allRequiredServices,
                requiredStoppedServices: [],
                requestedLogMessage: "runtime services start requested",
                requestedStatusPlan: RuntimeServiceControlStatusPlan(
                    logMessage: "runtime services start requested",
                    status: .recovering,
                    operation: .startServices,
                    statusMessage: "runtime services start requested"
                ),
                completedStatusPlan: RuntimeServiceControlStatusPlan(
                    logMessage: "runtime services start dispatched",
                    status: .recovering,
                    operation: .startServices,
                    statusMessage: "runtime services start dispatched"
                )
            )
        case .stopAll:
            return RuntimeServiceControlPlan(
                request: request,
                operation: .stopServices,
                startPolicy: nil,
                stopServices: RuntimeManagedService.stopOrder,
                requiredStartedServices: [],
                requiredStoppedServices: RuntimeManagedService.stopOrder,
                requestedLogMessage: "runtime services stop requested",
                requestedStatusPlan: nil,
                completedStatusPlan: RuntimeServiceControlStatusPlan(
                    logMessage: "runtime services stopped",
                    status: .degraded,
                    operation: .stopServices,
                    statusMessage: "runtime services stopped"
                )
            )
        }
    }

    public func requireStartPolicy(
        in plan: RuntimeServiceControlPlan,
        operationName: String
    ) throws -> RuntimeServiceRestartPolicy {
        guard let policy = plan.startPolicy else {
            throw RuntimeServiceControlError.operationFailed(
                "runtime service \(operationName) plan missing start policy"
            )
        }
        return policy
    }

    public func observation(
        states: [RuntimeManagedService: RuntimeServiceState]
    ) -> RuntimeServiceLifecycleObservation {
        RuntimeServiceLifecycleObservation(states: states)
    }

    public func requireServicesLoaded(
        _ services: [RuntimeManagedService],
        observation: RuntimeServiceLifecycleObservation
    ) throws {
        let blockers = RuntimeServiceLifecycleCompletionPolicy.requiredServicesLoaded(
            services,
            states: observation.states
        )
        try throwIfBlocked(blockers)
    }

    public func requireServicesStopped(
        _ services: [RuntimeManagedService],
        observation: RuntimeServiceLifecycleObservation
    ) throws {
        let blockers = RuntimeServiceLifecycleCompletionPolicy.servicesStopped(
            services,
            states: observation.states
        )
        try throwIfBlocked(blockers)
    }

    private func throwIfBlocked(_ blockers: [String]) throws {
        guard blockers.isEmpty else {
            throw RuntimeServiceControlError.operationFailed(blockers.joined(separator: "; "))
        }
    }
}
