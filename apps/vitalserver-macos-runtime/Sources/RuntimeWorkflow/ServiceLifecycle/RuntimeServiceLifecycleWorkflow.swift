import Application
import Contracts
import Core

public enum RuntimeServiceLifecycleCommand: Equatable {
    case repairAll
    case startAll
    case stopAll

    var operation: RuntimeOperation {
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
        let policy = RuntimeRequiredServicePolicy.allRuntimeServices
        writer.log("runtime services repair requested")
        try writer.writeStatus(.recovering, .repairServices, "runtime services repair requested")
        let stopped = try useCase.stopRuntimeServices(observing: RuntimeManagedService.stopOrder)
        try requireServicesStopped(RuntimeManagedService.stopOrder, observation: stopped)
        let started = try useCase.startRequiredServices(policy)
        try requireServicesLoaded(RuntimeRequiredServicePolicy.requiredServices(for: policy), observation: started)
        try writer.writeStatus(.recovering, .repairServices, "runtime services repair dispatched")
        writer.log("runtime services repair dispatched")
    }

    private func startAll() throws {
        let policy = RuntimeRequiredServicePolicy.allRuntimeServices
        writer.log("runtime services start requested")
        try writer.writeStatus(.recovering, .startServices, "runtime services start requested")
        let observation = try useCase.startRequiredServices(policy)
        try requireServicesLoaded(RuntimeRequiredServicePolicy.requiredServices(for: policy), observation: observation)
        try writer.writeStatus(.recovering, .startServices, "runtime services start dispatched")
        writer.log("runtime services start dispatched")
    }

    private func stopAll() throws {
        writer.log("runtime services stop requested")
        let observation = try useCase.stopRuntimeServices(observing: RuntimeManagedService.stopOrder)
        try requireServicesStopped(RuntimeManagedService.stopOrder, observation: observation)
        try writer.writeStatus(.degraded, .stopServices, "runtime services stopped")
        writer.log("runtime services stopped")
    }

    private func requireServicesLoaded(
        _ services: [RuntimeManagedService],
        observation: RuntimeServiceLifecycleObservation
    ) throws {
        let blockers = RuntimeServiceLifecycleCompletionGate.requiredServicesLoaded(
            services,
            states: observation.states
        )
        try throwIfBlocked(blockers)
    }

    private func requireServicesStopped(
        _ services: [RuntimeManagedService],
        observation: RuntimeServiceLifecycleObservation
    ) throws {
        let blockers = RuntimeServiceLifecycleCompletionGate.servicesStopped(
            services,
            states: observation.states
        )
        try throwIfBlocked(blockers)
    }

    private func throwIfBlocked(_ blockers: [String]) throws {
        guard blockers.isEmpty else {
            throw RuntimeWorkflowError.operationFailed(blockers.joined(separator: "; "))
        }
    }
}

public enum RuntimeServiceLifecycleCompletionGate {
    public static func requiredServicesLoaded(
        _ services: [RuntimeManagedService],
        states: [RuntimeManagedService: RuntimeServiceState]
    ) -> [String] {
        services.compactMap { service in
            guard let state = states[service] else {
                return "launchd-service-state-missing:label=\(service.label)"
            }
            guard state == .loaded else {
                return serviceStateBlocker(
                    prefix: "launchd-service-not-loaded",
                    service: service,
                    state: state
                )
            }
            return nil
        }
    }

    public static func servicesStopped(
        _ services: [RuntimeManagedService],
        states: [RuntimeManagedService: RuntimeServiceState]
    ) -> [String] {
        services.compactMap { service in
            guard let state = states[service] else {
                return "launchd-service-state-missing:label=\(service.label)"
            }
            guard state == .notLoaded else {
                return serviceStateBlocker(
                    prefix: "launchd-service-not-stopped",
                    service: service,
                    state: state
                )
            }
            return nil
        }
    }

    private static func serviceStateBlocker(
        prefix: String,
        service: RuntimeManagedService,
        state: RuntimeServiceState
    ) -> String {
        "\(prefix):label=\(service.label) state=\(state.rawValue)"
    }
}
