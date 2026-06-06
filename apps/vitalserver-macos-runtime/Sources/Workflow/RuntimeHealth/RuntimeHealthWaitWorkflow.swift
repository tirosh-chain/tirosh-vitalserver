import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeHealthWaitWorkflowConfiguration {
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

    var waitConfiguration: RuntimeHealthWaitConfiguration {
        RuntimeHealthWaitConfiguration(
            maxAttempts: Int(ceil(timeoutSeconds / pollIntervalSeconds)),
            progressEveryAttempts: progressEveryAttempts
        )
    }
}

public struct RuntimeHealthWaitWriter {
    public var writeStatusBestEffort: (RuntimeStatusLevel, RuntimeOperation, String) -> Void
    public var sleep: () -> Void
    public var log: (String) -> Void

    public init(
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.writeStatusBestEffort = writeStatusBestEffort
        self.sleep = sleep
        self.log = log
    }
}

public struct RuntimeHealthWaitReader {
    public var serviceStates: ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState]
    public var healthSnapshot: () -> RuntimeHealthSnapshot

    public init(
        serviceStates: @escaping ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState],
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot
    ) {
        self.serviceStates = serviceStates
        self.healthSnapshot = healthSnapshot
    }
}

public struct RuntimeHealthWaitWorkflow {
    private let useCase: WaitForRuntimeHealthUseCase
    private let reader: RuntimeHealthWaitReader
    private let configuration: RuntimeHealthWaitWorkflowConfiguration
    private let writer: RuntimeHealthWaitWriter

    public init(
        useCase: WaitForRuntimeHealthUseCase,
        reader: RuntimeHealthWaitReader,
        configuration: RuntimeHealthWaitWorkflowConfiguration,
        writer: RuntimeHealthWaitWriter
    ) {
        self.useCase = useCase
        self.reader = reader
        self.configuration = configuration
        self.writer = writer
    }

    public func wait(for policy: RuntimeServiceRestartPolicy) throws {
        let plan = useCase.plan(
            policy: policy,
            timeoutSeconds: configuration.timeoutSeconds
        )

        guard plan.shouldWait else {
            if let skippedMessage = plan.skippedMessage {
                writer.log(skippedMessage)
            }
            return
        }

        if let startedMessage = plan.startedMessage {
            writer.log(startedMessage)
        }
        let waitResult = RuntimeHealthWaiter.wait(
            configuration: configuration.waitConfiguration,
            observe: {
                useCase.observation(
                    policy: plan.policy,
                    serviceStates: reader.serviceStates(plan.observedServices),
                    snapshot: reader.healthSnapshot()
                )
            },
            onProgress: { reasons in
                let progressPlan = useCase.progressPlan(reasons: reasons)
                writer.log(progressPlan.logMessage)
                writer.writeStatusBestEffort(
                    progressPlan.status,
                    progressPlan.operation,
                    progressPlan.statusMessage
                )
            },
            sleep: writer.sleep
        )

        switch waitResult {
        case .healthy:
            let snapshot = reader.healthSnapshot()
            writer.log(useCase.healthyLogMessage(snapshot: snapshot))
        case .failedEarly(let reason):
            let message = useCase.failedEarlyMessage(reason: reason)
            writer.log(message)
            throw RuntimeHealthWaitWorkflowError.operationFailed(message)
        case .timedOut(let reasons):
            throw RuntimeHealthWaitWorkflowError.operationFailed(useCase.timedOutFailureMessage(reasons: reasons))
        }
    }
}
