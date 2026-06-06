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
                let reasonText = RuntimeFailureReasonText.describe(reasons)
                writer.log("waiting for runtime health reasons=\(reasonText)")
                writer.writeStatusBestEffort(
                    .recovering,
                    .health,
                    "waiting for runtime health: \(reasonText)"
                )
            },
            sleep: writer.sleep
        )

        switch waitResult {
        case .healthy:
            let snapshot = reader.healthSnapshot()
            writer.log("runtime health ok hostProxyHTTP=\(snapshot.hostProxyHTTP)")
        case .failedEarly(let reason):
            writer.log("runtime health failed early reason=\(reason.rawValue)")
            throw RuntimeHealthWaitWorkflowError.operationFailed(
                "runtime health failed early reason=\(reason.rawValue)"
            )
        case .timedOut(let reasons):
            let reasonText = RuntimeFailureReasonText.describe(reasons)
            throw RuntimeHealthWaitWorkflowError.operationFailed("runtime health timed out reasons=\(reasonText)")
        }
    }
}
