import Application
import Contracts
import Domain
import Errors

public struct RuntimeHealthWaitRunner {
    private let useCase: WaitForRuntimeHealthUseCase
    private let context: RuntimeHealthWaitExecutionContext
    private let operations: RuntimeHealthWaitOperations

    public init(
        context: RuntimeHealthWaitExecutionContext,
        serviceStates: @escaping ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState],
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.useCase = WaitForRuntimeHealthUseCase()
        self.context = context
        self.operations = RuntimeHealthWaitOperations(
            serviceStates: serviceStates,
            healthSnapshot: healthSnapshot,
            writeStatusBestEffort: writeStatusBestEffort,
            sleep: sleep,
            log: log
        )
    }

    public func wait(for policy: RuntimeServiceRestartPolicy) throws {
        do {
            try useCase.wait(
                policy: policy,
                context: context,
                operations: operations
            )
        } catch RuntimeHealthWaitUseCaseError.operationFailed {
            throw RuntimeHealthWaitRunnerError.runtimeHealthFailed
        }
    }
}
