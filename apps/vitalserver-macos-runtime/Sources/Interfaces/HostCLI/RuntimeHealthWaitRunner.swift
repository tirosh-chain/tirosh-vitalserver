import Application
import Contracts
import Domain
import Workflow

public enum RuntimeHealthWaitRunnerError: Error, CustomStringConvertible, Equatable {
    case runtimeHealthFailed

    public var description: String {
        switch self {
        case .runtimeHealthFailed:
            return "runtime health check failed"
        }
    }
}

public struct RuntimeHealthWaitRunner {
    private let workflow: RuntimeHealthWaitWorkflow

    public init(
        configuration: RuntimeHealthWaitWorkflowConfiguration,
        serviceStates: @escaping ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState],
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.workflow = RuntimeHealthWaitWorkflow(
            useCase: WaitForRuntimeHealthUseCase(
                ports: RuntimeHealthWaitPorts(
                    serviceStates: serviceStates,
                    healthSnapshot: healthSnapshot
                )
            ),
            configuration: configuration,
            writer: RuntimeHealthWaitWriter(
                writeStatusBestEffort: writeStatusBestEffort,
                sleep: sleep,
                log: log
            )
        )
    }

    public func wait(for policy: RuntimeServiceRestartPolicy) throws {
        do {
            try workflow.wait(for: policy)
        } catch RuntimeHealthWaitWorkflowError.operationFailed {
            throw RuntimeHealthWaitRunnerError.runtimeHealthFailed
        }
    }
}
