import Application
import Contracts
import Domain
import Errors
import Foundation

public struct RuntimeHealthWaitRunner {
    private let workflow: RuntimeHealthWaitWorkflow
    private let context: RuntimeHealthWaitWorkflowContext
    private let actions: RuntimeHealthWaitWorkflowActions

    public init(
        context: RuntimeHealthWaitWorkflowContext,
        serviceStates: @escaping ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState],
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.workflow = RuntimeHealthWaitWorkflow()
        self.context = context
        self.actions = RuntimeHealthWaitWorkflowActions(
            serviceStates: serviceStates,
            healthSnapshot: healthSnapshot,
            writeStatusBestEffort: writeStatusBestEffort,
            sleep: sleep,
            log: log
        )
    }

    public func wait(for policy: RuntimeServiceRestartPolicy) throws {
        do {
            try workflow.wait(
                policy: policy,
                context: context,
                actions: actions
            )
        } catch RuntimeHealthWaitUseCaseError.operationFailed {
            throw RuntimeHealthWaitRunnerError.runtimeHealthFailed
        }
    }
}
