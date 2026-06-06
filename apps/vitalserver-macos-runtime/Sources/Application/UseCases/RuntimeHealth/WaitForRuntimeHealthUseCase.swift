import Contracts
import Domain
import Errors
import Foundation

public struct RuntimeHealthWaitPlan: Equatable {
    public let policy: RuntimeServiceRestartPolicy
    public let shouldWait: Bool
    public let observedServices: [RuntimeManagedService]
    public let skippedMessage: String?
    public let startedMessage: String?

    public init(
        policy: RuntimeServiceRestartPolicy,
        shouldWait: Bool,
        observedServices: [RuntimeManagedService],
        skippedMessage: String?,
        startedMessage: String?
    ) {
        self.policy = policy
        self.shouldWait = shouldWait
        self.observedServices = observedServices
        self.skippedMessage = skippedMessage
        self.startedMessage = startedMessage
    }
}

public struct RuntimeHealthWaitProgressPlan: Equatable {
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let logMessage: String
    public let statusMessage: String

    public init(
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        logMessage: String,
        statusMessage: String
    ) {
        self.status = status
        self.operation = operation
        self.logMessage = logMessage
        self.statusMessage = statusMessage
    }
}

public struct RuntimeHealthWaitExecutionContext: Equatable {
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

public struct RuntimeHealthWaitOperations {
    public let serviceStates: ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState]
    public let healthSnapshot: () -> RuntimeHealthSnapshot
    public let writeStatusBestEffort: (RuntimeStatusLevel, RuntimeOperation, String) -> Void
    public let sleep: () -> Void
    public let log: (String) -> Void

    public init(
        serviceStates: @escaping ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState],
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.serviceStates = serviceStates
        self.healthSnapshot = healthSnapshot
        self.writeStatusBestEffort = writeStatusBestEffort
        self.sleep = sleep
        self.log = log
    }
}

public enum RuntimeHealthWaitExecutionOutcome: Equatable {
    case completed
    case skipped
}

public struct WaitForRuntimeHealthUseCase {
    public init() {}

    public func plan(
        policy: RuntimeServiceRestartPolicy,
        timeoutSeconds: Double
    ) -> RuntimeHealthWaitPlan {
        guard policy.anyServiceWasRunning else {
            return RuntimeHealthWaitPlan(
                policy: policy,
                shouldWait: false,
                observedServices: [],
                skippedMessage: "runtime services were not running before apply; skipping health wait",
                startedMessage: nil
            )
        }

        return RuntimeHealthWaitPlan(
            policy: policy,
            shouldWait: true,
            observedServices: observedServices(),
            skippedMessage: nil,
            startedMessage: "waiting for runtime health timeoutSeconds=\(timeoutSeconds)"
        )
    }

    public func observedServices() -> [RuntimeManagedService] {
        [
            .vm,
            .guestLogSync,
            .proxy,
            .watchdog,
        ]
    }

    public func observation(
        policy: RuntimeServiceRestartPolicy,
        serviceStates: [RuntimeManagedService: RuntimeServiceState],
        snapshot: RuntimeHealthSnapshot
    ) -> RuntimeHealthWaitObservation {
        let requiredServices = RuntimeRequiredServicePolicy.requiredServices(for: policy)
        return RuntimeHealthWaitObservation(
            requiredServices: requiredServices,
            serviceStates: serviceStates,
            snapshot: snapshot
        )
    }

    public func progressPlan(reasons: [RuntimeFailureReason]) -> RuntimeHealthWaitProgressPlan {
        let reasonText = RuntimeFailureReasonText.describe(reasons)
        return RuntimeHealthWaitProgressPlan(
            status: .recovering,
            operation: .health,
            logMessage: "waiting for runtime health reasons=\(reasonText)",
            statusMessage: "waiting for runtime health: \(reasonText)"
        )
    }

    public func healthyLogMessage(snapshot: RuntimeHealthSnapshot) -> String {
        "runtime health ok hostProxyHTTP=\(snapshot.hostProxyHTTP)"
    }

    public func failedEarlyMessage(reason: RuntimeFailureReason) -> String {
        "runtime health failed early reason=\(reason.rawValue)"
    }

    public func timedOutFailureMessage(reasons: [RuntimeFailureReason]) -> String {
        "runtime health timed out reasons=\(RuntimeFailureReasonText.describe(reasons))"
    }

    @discardableResult
    public func wait(
        policy: RuntimeServiceRestartPolicy,
        context: RuntimeHealthWaitExecutionContext,
        operations: RuntimeHealthWaitOperations
    ) throws -> RuntimeHealthWaitExecutionOutcome {
        let plan = plan(policy: policy, timeoutSeconds: context.timeoutSeconds)
        guard plan.shouldWait else {
            if let skippedMessage = plan.skippedMessage {
                operations.log(skippedMessage)
            }
            return .skipped
        }

        if let startedMessage = plan.startedMessage {
            operations.log(startedMessage)
        }
        let waitResult = RuntimeHealthWaiter.wait(
            configuration: waitConfiguration(context),
            observe: {
                observation(
                    policy: plan.policy,
                    serviceStates: operations.serviceStates(plan.observedServices),
                    snapshot: operations.healthSnapshot()
                )
            },
            onProgress: { reasons in
                let progressPlan = progressPlan(reasons: reasons)
                operations.log(progressPlan.logMessage)
                operations.writeStatusBestEffort(
                    progressPlan.status,
                    progressPlan.operation,
                    progressPlan.statusMessage
                )
            },
            sleep: operations.sleep
        )

        try execute(waitResult, operations: operations)
        return .completed
    }

    private func waitConfiguration(
        _ context: RuntimeHealthWaitExecutionContext
    ) -> RuntimeHealthWaitConfiguration {
        RuntimeHealthWaitConfiguration(
            maxAttempts: Int(ceil(context.timeoutSeconds / context.pollIntervalSeconds)),
            progressEveryAttempts: context.progressEveryAttempts
        )
    }

    private func execute(
        _ waitResult: RuntimeHealthWaitResult,
        operations: RuntimeHealthWaitOperations
    ) throws {
        switch waitResult {
        case .healthy:
            let snapshot = operations.healthSnapshot()
            operations.log(healthyLogMessage(snapshot: snapshot))
        case .failedEarly(let reason):
            let message = failedEarlyMessage(reason: reason)
            operations.log(message)
            throw RuntimeHealthWaitUseCaseError.operationFailed(message)
        case .timedOut(let reasons):
            throw RuntimeHealthWaitUseCaseError.operationFailed(timedOutFailureMessage(reasons: reasons))
        }
    }
}
