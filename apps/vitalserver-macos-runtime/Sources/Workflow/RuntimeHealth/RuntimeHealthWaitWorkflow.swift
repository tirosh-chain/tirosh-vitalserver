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
    public let now: () -> Date
    public let sleep: (TimeInterval) -> Void
    public let log: (String) -> Void

    public init(
        serviceStates: @escaping ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState],
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.serviceStates = serviceStates
        self.healthSnapshot = healthSnapshot
        self.writeStatusBestEffort = writeStatusBestEffort
        self.now = now
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
        let configuration = try waitConfiguration(context)
        let deadline = actions.now().addingTimeInterval(context.timeoutSeconds)
        var state = RuntimeHealthWaitState()

        for attempt in 0..<configuration.maxAttempts {
            guard attempt == 0 || actions.now() < deadline else {
                break
            }
            let observation = useCase.observation(
                policy: plan.policy,
                serviceStates: actions.serviceStates(plan.observedServices),
                snapshot: actions.healthSnapshot()
            )
            switch RuntimeHealthWaiter.evaluateAttempt(
                configuration: configuration,
                attempt: attempt,
                state: state,
                observation: observation
            ) {
            case .healthy:
                actions.log(useCase.healthyLogMessage(snapshot: observation.snapshot))
                return .completed
            case .failedEarly(let reason):
                let message = useCase.failedEarlyMessage(reason: reason)
                actions.log(message)
                throw RuntimeHealthWaitUseCaseError.operationFailed(message)
            case .waiting(let nextState, let progress):
                state = nextState
                if let progress {
                    let progressPlan = useCase.progressPlan(reasons: progress.reasons)
                    actions.log(progressPlan.logMessage)
                    actions.writeStatusBestEffort(
                        progressPlan.status,
                        progressPlan.operation,
                        progressPlan.statusMessage
                    )
                }
                let remainingSeconds = deadline.timeIntervalSince(actions.now())
                if remainingSeconds > 0 {
                    actions.sleep(min(context.pollIntervalSeconds, remainingSeconds))
                }
            }
        }

        throw RuntimeHealthWaitUseCaseError.operationFailed(
            useCase.timedOutFailureMessage(reasons: state.accumulatedReasons)
        )
    }

    private func waitConfiguration(
        _ context: RuntimeHealthWaitWorkflowContext
    ) throws -> RuntimeHealthWaitConfiguration {
        guard context.timeoutSeconds.isFinite, context.timeoutSeconds > 0 else {
            throw RuntimeHealthWaitUseCaseError.operationFailed(
                "invalid runtime health wait configuration: timeoutSeconds must be positive"
            )
        }
        guard context.pollIntervalSeconds.isFinite, context.pollIntervalSeconds > 0 else {
            throw RuntimeHealthWaitUseCaseError.operationFailed(
                "invalid runtime health wait configuration: pollIntervalSeconds must be positive"
            )
        }
        guard context.progressEveryAttempts > 0 else {
            throw RuntimeHealthWaitUseCaseError.operationFailed(
                "invalid runtime health wait configuration: progressEveryAttempts must be positive"
            )
        }
        return RuntimeHealthWaitConfiguration(
            maxAttempts: Int(ceil(context.timeoutSeconds / context.pollIntervalSeconds)),
            progressEveryAttempts: context.progressEveryAttempts
        )
    }

}
