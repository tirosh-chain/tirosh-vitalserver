import Application
import Contracts
import Domain

public enum RuntimeServiceLifecycleWorkflowError: Error, Equatable {
    case operationFailed(String)
}

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

public struct RuntimeServiceLifecycleWorkflow {
    private let useCase: ControlRuntimeServicesUseCase
    private let writer: RuntimeServiceLifecycleWriter

    public init(
        useCase: ControlRuntimeServicesUseCase,
        writer: RuntimeServiceLifecycleWriter
    ) {
        self.useCase = useCase
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
        guard let policy = plan.startPolicy else {
            throw RuntimeServiceLifecycleWorkflowError.operationFailed(
                "runtime service repair plan missing start policy"
            )
        }
        writer.log("runtime services repair requested")
        try writer.writeStatus(.recovering, plan.operation, "runtime services repair requested")
        let stopped = try useCase.stopRuntimeServices(observing: plan.stopServices)
        try requireServicesStopped(plan.requiredStoppedServices, observation: stopped)
        let started = try useCase.startRequiredServices(policy)
        try requireServicesLoaded(plan.requiredStartedServices, observation: started)
        try writer.writeStatus(.recovering, plan.operation, "runtime services repair dispatched")
        writer.log("runtime services repair dispatched")
    }

    private func startAll() throws {
        let plan = useCase.plan(.startAll)
        guard let policy = plan.startPolicy else {
            throw RuntimeServiceLifecycleWorkflowError.operationFailed(
                "runtime service start plan missing start policy"
            )
        }
        writer.log("runtime services start requested")
        try writer.writeStatus(.recovering, plan.operation, "runtime services start requested")
        let observation = try useCase.startRequiredServices(policy)
        try requireServicesLoaded(plan.requiredStartedServices, observation: observation)
        try writer.writeStatus(.recovering, plan.operation, "runtime services start dispatched")
        writer.log("runtime services start dispatched")
    }

    private func stopAll() throws {
        let plan = useCase.plan(.stopAll)
        writer.log("runtime services stop requested")
        let observation = try useCase.stopRuntimeServices(observing: plan.stopServices)
        try requireServicesStopped(plan.requiredStoppedServices, observation: observation)
        try writer.writeStatus(.degraded, plan.operation, "runtime services stopped")
        writer.log("runtime services stopped")
    }

    private func requireServicesLoaded(
        _ services: [RuntimeManagedService],
        observation: RuntimeServiceLifecycleObservation
    ) throws {
        let blockers = RuntimeServiceLifecycleCompletionPolicy.requiredServicesLoaded(
            services,
            states: observation.states
        )
        try throwIfBlocked(blockers)
    }

    private func requireServicesStopped(
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
            throw RuntimeServiceLifecycleWorkflowError.operationFailed(blockers.joined(separator: "; "))
        }
    }
}
