import Application
import Contracts
import Errors

public struct RuntimeServiceControlRunner {
    private let useCase: ControlRuntimeServicesUseCase
    private let operations: RuntimeServiceControlOperations

    public init(
        useCase: ControlRuntimeServicesUseCase,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        serviceStates: @escaping ([RuntimeManagedService]) throws -> [RuntimeManagedService: RuntimeServiceState],
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.useCase = useCase
        self.operations = RuntimeServiceControlOperations(
            startRuntimeServices: startRuntimeServices,
            stopRuntimeServices: stopRuntimeServices,
            serviceStates: serviceStates,
            writeStatus: writeStatus,
            log: log
        )
    }

    public func run(_ command: RuntimeServiceControlCommand) throws {
        try useCase.run(command.lifecycleRequest, operations: operations)
    }
}

private extension RuntimeServiceControlCommand {
    var lifecycleRequest: RuntimeServiceControlRequest {
        switch self {
        case .repairAll:
            return .repairAll
        case .repairProxy:
            return .repairProxy
        case .startAll:
            return .startAll
        case .stopAll:
            return .stopAll
        }
    }
}
