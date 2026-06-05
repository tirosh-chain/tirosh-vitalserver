import Application
import Contracts
import Core
import RuntimeWorkflow

struct RuntimeHealthWaitRunner {
    private let workflow: RuntimeHealthWaitWorkflow

    init(
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
            configuration: RuntimeHealthWaitWorkflowConfiguration(
                timeoutSeconds: Constants.Runtime.waitTimeoutSeconds,
                pollIntervalSeconds: 3.0,
                progressEveryAttempts: 5
            ),
            writer: RuntimeHealthWaitWriter(
                writeStatusBestEffort: writeStatusBestEffort,
                sleep: sleep,
                log: log
            )
        )
    }

    func wait(for policy: RuntimeServiceRestartPolicy) throws {
        do {
            try workflow.wait(for: policy)
        } catch RuntimeWorkflowError.operationFailed {
            throw LauncherError.runtimeHealthFailed
        }
    }
}
