import Application
import Contracts
import Domain
import Workflow

public struct RuntimeServiceControlRunner {
    private let workflow: RuntimeServiceLifecycleWorkflow

    public init(
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        serviceStates: @escaping ([RuntimeManagedService]) throws -> [RuntimeManagedService: RuntimeServiceState],
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.workflow = RuntimeServiceLifecycleWorkflow(
            useCase: ControlRuntimeServicesUseCase(
                ports: RuntimeServiceControlPorts(
                    startRuntimeServices: startRuntimeServices,
                    stopRuntimeServices: stopRuntimeServices,
                    serviceStates: serviceStates
                )
            ),
            writer: RuntimeServiceLifecycleWriter(
                writeStatus: writeStatus,
                log: log
            )
        )
    }

    public func run(_ command: RuntimeServiceControlCommand) throws {
        try workflow.run(command.lifecycleCommand)
    }
}

private extension RuntimeServiceControlCommand {
    var lifecycleCommand: RuntimeServiceLifecycleCommand {
        switch self {
        case .repairAll:
            return .repairAll
        case .startAll:
            return .startAll
        case .stopAll:
            return .stopAll
        }
    }
}
