import Application
import Contracts
import Domain
import Errors
import Foundation

public struct RuntimeHealthWaitWorkflowContext: Equatable {
    public let timeoutSeconds: Double
    public let pollIntervalSeconds: Double
    public let progressEveryAttempts: Int

    public init(
        timeoutSeconds: Double,
        pollIntervalSeconds: Double,
        progressEveryAttempts: Int
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
        self.progressEveryAttempts = progressEveryAttempts
    }
}

public struct RuntimeHealthWaitWorkflowActions {
    public let serviceStates: ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState]
    public let healthSnapshot: () -> RuntimeHealthSnapshot
    public let writeStatusBestEffort: (RuntimeStatusLevel, RuntimeOperation, String) -> Void
    public let sleep: (TimeInterval) -> Void
    public let log: (String) -> Void

    public init(
        serviceStates: @escaping ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState],
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.serviceStates = serviceStates
        self.healthSnapshot = healthSnapshot
        self.writeStatusBestEffort = writeStatusBestEffort
        self.sleep = sleep
        self.log = log
    }
}

public enum RuntimeHealthWaitWorkflowOutcome: Equatable {
    case completed
    case skipped
}

public struct RuntimeHealthWaitWorkflow {
    private let useCase: WaitForRuntimeHealthUseCase

    public init(useCase: WaitForRuntimeHealthUseCase = WaitForRuntimeHealthUseCase()) {
        self.useCase = useCase
    }

    @discardableResult
    public func wait(
        policy: RuntimeServiceRestartPolicy,
        context: RuntimeHealthWaitWorkflowContext,
        actions: RuntimeHealthWaitWorkflowActions
    ) throws -> RuntimeHealthWaitWorkflowOutcome {
        let plan = useCase.plan(policy: policy, timeoutSeconds: context.timeoutSeconds)
        guard plan.shouldWait else {
            if let skippedMessage = plan.skippedMessage {
                actions.log(skippedMessage)
            }
            return .skipped
        }

        if let startedMessage = plan.startedMessage {
            actions.log(startedMessage)
        }
        let waitResult = RuntimeHealthWaiter.wait(
            configuration: waitConfiguration(context),
            observe: {
                useCase.observation(
                    policy: plan.policy,
                    serviceStates: actions.serviceStates(plan.observedServices),
                    snapshot: actions.healthSnapshot()
                )
            },
            onProgress: { reasons in
                let progressPlan = useCase.progressPlan(reasons: reasons)
                actions.log(progressPlan.logMessage)
                actions.writeStatusBestEffort(
                    progressPlan.status,
                    progressPlan.operation,
                    progressPlan.statusMessage
                )
            },
            sleep: {
                actions.sleep(context.pollIntervalSeconds)
            }
        )

        try execute(waitResult, actions: actions)
        return .completed
    }

    private func waitConfiguration(
        _ context: RuntimeHealthWaitWorkflowContext
    ) -> RuntimeHealthWaitConfiguration {
        RuntimeHealthWaitConfiguration(
            maxAttempts: Int(ceil(context.timeoutSeconds / context.pollIntervalSeconds)),
            progressEveryAttempts: context.progressEveryAttempts
        )
    }

    private func execute(
        _ waitResult: RuntimeHealthWaitResult,
        actions: RuntimeHealthWaitWorkflowActions
    ) throws {
        switch waitResult {
        case .healthy:
            let snapshot = actions.healthSnapshot()
            actions.log(useCase.healthyLogMessage(snapshot: snapshot))
        case .failedEarly(let reason):
            let message = useCase.failedEarlyMessage(reason: reason)
            actions.log(message)
            throw RuntimeHealthWaitUseCaseError.operationFailed(message)
        case .timedOut(let reasons):
            throw RuntimeHealthWaitUseCaseError.operationFailed(useCase.timedOutFailureMessage(reasons: reasons))
        }
    }
}
