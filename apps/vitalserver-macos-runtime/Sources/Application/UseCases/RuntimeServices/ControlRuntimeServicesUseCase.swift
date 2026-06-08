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
    case repairProxy
    case startAll
    case stopAll

    public var operation: RuntimeOperation {
        switch self {
        case .repairAll:
            return .repairServices
        case .repairProxy:
            return .repairProxy
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

public struct RuntimeServiceControlOperations {
    public var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public var stopRuntimeServices: () throws -> Void
    public var serviceStates: ([RuntimeManagedService]) throws -> [RuntimeManagedService: RuntimeServiceState]
    public var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var log: (String) -> Void

    public init(
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        serviceStates: @escaping ([RuntimeManagedService]) throws -> [RuntimeManagedService: RuntimeServiceState],
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.startRuntimeServices = startRuntimeServices
        self.stopRuntimeServices = stopRuntimeServices
        self.serviceStates = serviceStates
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.log = log
    }
}

public struct ControlRuntimeServicesUseCase {
    public init() {}

    public func run(
        _ request: RuntimeServiceControlRequest,
        operations: RuntimeServiceControlOperations
    ) throws {
        switch request {
        case .repairAll:
            try repairAll(operations: operations)
        case .repairProxy:
            try repairProxy(operations: operations)
        case .startAll:
            try startAll(operations: operations)
        case .stopAll:
            try stopAll(operations: operations)
        }
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
                requiredStoppedServices: RuntimeManagedService.stopOrder,
                requestedLogMessage: "runtime services repair requested",
                requestedStatusPlan: RuntimeServiceControlStatusPlan(
                    logMessage: "runtime services repair requested",
                    status: .recovering,
                    operation: .repairServices,
                    statusMessage: "runtime services repair requested"
                ),
                completedStatusPlan: RuntimeServiceControlStatusPlan(
                    logMessage: "runtime services repaired",
                    status: .healthy,
                    operation: .repairServices,
                    statusMessage: "runtime services repaired"
                )
            )
        case .repairProxy:
            let proxyOnlyPolicy = RuntimeServiceRestartPolicy(
                restartVM: false,
                restartGuestLogSync: false,
                restartProxy: true,
                restartWatchdog: false
            )
            return RuntimeServiceControlPlan(
                request: request,
                operation: .repairProxy,
                startPolicy: proxyOnlyPolicy,
                stopServices: [.proxy],
                requiredStartedServices: [.proxy],
                requiredStoppedServices: [.proxy],
                requestedLogMessage: "host proxy repair requested",
                requestedStatusPlan: RuntimeServiceControlStatusPlan(
                    logMessage: "host proxy repair requested",
                    status: .recovering,
                    operation: .repairProxy,
                    statusMessage: "host proxy repair requested"
                ),
                completedStatusPlan: RuntimeServiceControlStatusPlan(
                    logMessage: "host proxy repaired",
                    status: .healthy,
                    operation: .repairProxy,
                    statusMessage: "host proxy repaired"
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
                    logMessage: "runtime services started",
                    status: .healthy,
                    operation: .startServices,
                    statusMessage: "runtime services started"
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

    private func repairAll(operations: RuntimeServiceControlOperations) throws {
        let controlPlan = plan(.repairAll)
        try reportRequested(controlPlan, operations: operations)
        try operations.stopRuntimeServices()
        try requireServicesStopped(controlPlan.requiredStoppedServices, operations: operations)
        let policy = try requireStartPolicy(in: controlPlan, operationName: "repair")
        try operations.startRuntimeServices(policy)
        try requireServicesLoaded(controlPlan.requiredStartedServices, operations: operations)
        try operations.waitForHealth(policy)
        try reportCompleted(controlPlan.completedStatusPlan, operations: operations)
    }

    private func repairProxy(operations: RuntimeServiceControlOperations) throws {
        let controlPlan = plan(.repairProxy)
        try reportRequested(controlPlan, operations: operations)
        let policy = try requireStartPolicy(in: controlPlan, operationName: "repair proxy")
        try operations.startRuntimeServices(policy)
        try requireServicesLoaded(controlPlan.requiredStartedServices, operations: operations)
        try operations.waitForHealth(policy)
        try reportCompleted(controlPlan.completedStatusPlan, operations: operations)
    }

    private func startAll(operations: RuntimeServiceControlOperations) throws {
        let controlPlan = plan(.startAll)
        try reportRequested(controlPlan, operations: operations)
        let policy = try requireStartPolicy(in: controlPlan, operationName: "start")
        try operations.startRuntimeServices(policy)
        try requireServicesLoaded(controlPlan.requiredStartedServices, operations: operations)
        try operations.waitForHealth(policy)
        try reportCompleted(controlPlan.completedStatusPlan, operations: operations)
    }

    private func stopAll(operations: RuntimeServiceControlOperations) throws {
        let controlPlan = plan(.stopAll)
        try reportRequested(controlPlan, operations: operations)
        try operations.stopRuntimeServices()
        try requireServicesStopped(controlPlan.requiredStoppedServices, operations: operations)
        try reportCompleted(controlPlan.completedStatusPlan, operations: operations)
    }

    private func reportRequested(
        _ controlPlan: RuntimeServiceControlPlan,
        operations: RuntimeServiceControlOperations
    ) throws {
        operations.log(controlPlan.requestedLogMessage)
        if let statusPlan = controlPlan.requestedStatusPlan {
            try operations.writeStatus(statusPlan.status, statusPlan.operation, statusPlan.statusMessage)
        }
    }

    private func reportCompleted(
        _ statusPlan: RuntimeServiceControlStatusPlan,
        operations: RuntimeServiceControlOperations
    ) throws {
        try operations.writeStatus(statusPlan.status, statusPlan.operation, statusPlan.statusMessage)
        operations.log(statusPlan.logMessage)
    }

    private func requireServicesLoaded(
        _ services: [RuntimeManagedService],
        operations: RuntimeServiceControlOperations
    ) throws {
        let states = try operations.serviceStates(services)
        try requireServicesLoaded(services, observation: observation(states: states))
    }

    private func requireServicesStopped(
        _ services: [RuntimeManagedService],
        operations: RuntimeServiceControlOperations
    ) throws {
        let states = try operations.serviceStates(services)
        try requireServicesStopped(services, observation: observation(states: states))
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
