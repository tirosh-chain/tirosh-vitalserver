import Application
import Contracts
import Domain
import Errors

public enum RuntimeServiceLifecycleCommand: Equatable {
    case repairAll
    case startAll
    case stopAll

    var request: RuntimeServiceControlRequest {
        switch self {
        case .repairAll:
            return .repairAll
        case .startAll:
            return .startAll
        case .stopAll:
            return .stopAll
        }
    }

    var operation: RuntimeOperation {
        request.operation
    }
}

public struct RuntimeServiceLifecycleWriter {
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var log: (String) -> Void

    public init(
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.writeStatus = writeStatus
        self.log = log
    }
}

public struct RuntimeServiceLifecycleEffects {
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

public struct RuntimeServiceLifecycleWorkflow {
    private let useCase: ControlRuntimeServicesUseCase
    private let effects: RuntimeServiceLifecycleEffects
    private let writer: RuntimeServiceLifecycleWriter

    public init(
        useCase: ControlRuntimeServicesUseCase,
        effects: RuntimeServiceLifecycleEffects,
        writer: RuntimeServiceLifecycleWriter
    ) {
        self.useCase = useCase
        self.effects = effects
        self.writer = writer
    }

    public func run(_ command: RuntimeServiceLifecycleCommand) throws {
        switch command {
        case .repairAll:
            try repairAll()
        case .startAll:
            try startAll()
        case .stopAll:
            try stopAll()
        }
    }

    private func repairAll() throws {
        let plan = useCase.plan(.repairAll)
        writer.log("runtime services repair requested")
        try writer.writeStatus(.recovering, plan.operation, "runtime services repair requested")
        try effects.stopRuntimeServices()
        try requireServicesStopped(plan.requiredStoppedServices)
        let policy = try useCase.requireStartPolicy(in: plan, operationName: "repair")
        try effects.startRuntimeServices(policy)
        try requireServicesLoaded(plan.requiredStartedServices)
        try writer.writeStatus(.recovering, plan.operation, "runtime services repair dispatched")
        writer.log("runtime services repair dispatched")
    }

    private func startAll() throws {
        let plan = useCase.plan(.startAll)
        writer.log("runtime services start requested")
        try writer.writeStatus(.recovering, plan.operation, "runtime services start requested")
        let policy = try useCase.requireStartPolicy(in: plan, operationName: "start")
        try effects.startRuntimeServices(policy)
        try requireServicesLoaded(plan.requiredStartedServices)
        try writer.writeStatus(.recovering, plan.operation, "runtime services start dispatched")
        writer.log("runtime services start dispatched")
    }

    private func stopAll() throws {
        let plan = useCase.plan(.stopAll)
        writer.log("runtime services stop requested")
        try effects.stopRuntimeServices()
        try requireServicesStopped(plan.requiredStoppedServices)
        try writer.writeStatus(.degraded, plan.operation, "runtime services stopped")
        writer.log("runtime services stopped")
    }

    private func requireServicesLoaded(_ services: [RuntimeManagedService]) throws {
        do {
            let states = try effects.serviceStates(services)
            try useCase.requireServicesLoaded(
                services,
                observation: useCase.observation(states: states)
            )
        } catch RuntimeServiceControlError.operationFailed(let message) {
            throw RuntimeServiceLifecycleWorkflowError.operationFailed(message)
        }
    }

    private func requireServicesStopped(_ services: [RuntimeManagedService]) throws {
        do {
            let states = try effects.serviceStates(services)
            try useCase.requireServicesStopped(
                services,
                observation: useCase.observation(states: states)
            )
        } catch RuntimeServiceControlError.operationFailed(let message) {
            throw RuntimeServiceLifecycleWorkflowError.operationFailed(message)
        }
    }
}
