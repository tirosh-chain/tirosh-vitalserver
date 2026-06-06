import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestShutdownRunner {
    public var requireCapability: () throws -> Void
    public var createRunDirectory: () throws -> Void
    public var removePreviousResult: () throws -> Void
    public var requestID: () -> String
    public var timestamp: () -> String
    public var writeRequest: (RuntimeGuestShutdownRequest) throws -> Void
    public var loadResult: () -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>
    public var reportProgress: (String) -> Void
    public var sleep: () -> Void
    public var log: (String) -> Void
    public var waitTimeoutSeconds: Double
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        requireCapability: @escaping () throws -> Void,
        createRunDirectory: @escaping () throws -> Void,
        removePreviousResult: @escaping () throws -> Void,
        requestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        writeRequest: @escaping (RuntimeGuestShutdownRequest) throws -> Void,
        loadResult: @escaping () -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>,
        reportProgress: @escaping (String) -> Void,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void,
        waitTimeoutSeconds: Double
    ) {
        self.requireCapability = requireCapability
        self.createRunDirectory = createRunDirectory
        self.removePreviousResult = removePreviousResult
        self.requestID = requestID
        self.timestamp = timestamp
        self.writeRequest = writeRequest
        self.loadResult = loadResult
        self.reportProgress = reportProgress
        self.sleep = sleep
        self.log = log
        self.waitTimeoutSeconds = waitTimeoutSeconds
    }

    public func prepareForUpdate(version: String) throws {
        let plan = useCase.guestShutdownPlan(version: version)
        log(plan.requestedLogMessage)
        try requireCapability()
        try createRunDirectory()
        try removePreviousResult()
        let request = useCase.guestShutdownRequest(
            plan: plan,
            requestID: requestID(),
            requestedAt: timestamp()
        )
        try writeRequest(request)
        try waitForShutdownReady(request)
        log(plan.readyLogMessage)
    }

    private func waitForShutdownReady(_ request: RuntimeGuestShutdownRequest) throws {
        log(useCase.guestShutdownWaitStartedLogMessage(timeoutSeconds: waitTimeoutSeconds))
        let maxAttempts = Int(ceil(waitTimeoutSeconds / 3.0))
        let waitResult = GuestShutdownWaiter.wait(
            expectedRequestId: request.id,
            configuration: GuestShutdownWaitConfiguration(
                maxAttempts: maxAttempts,
                progressEveryAttempts: 5
            ),
            loadResult: loadResult,
            onProgress: { message in
                log(message)
                reportProgress(message)
            },
            sleep: sleep
        )

        let resultPlan = useCase.guestShutdownWaitResultPlan(waitResult)
        if let logMessage = resultPlan.logMessage {
            log(logMessage)
        }
        if let failureMessage = resultPlan.failureMessage {
            throw RuntimeGuestShutdownWorkflowError.operationFailed(failureMessage)
        }
    }
}
