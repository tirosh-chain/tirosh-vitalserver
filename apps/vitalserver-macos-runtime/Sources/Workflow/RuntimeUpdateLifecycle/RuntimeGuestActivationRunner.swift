import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestActivationRunner {
    public var requireCapability: () throws -> Void
    public var createRunDirectory: () throws -> Void
    public var removePreviousResult: () throws -> Void
    public var requestID: () -> String
    public var timestamp: () -> String
    public var writeRequest: (RuntimeGuestActivationRequest) throws -> Void
    public var isVMServiceLoaded: () -> Bool
    public var startVMService: () throws -> Void
    public var loadResult: () -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>
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
        writeRequest: @escaping (RuntimeGuestActivationRequest) throws -> Void,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        loadResult: @escaping () -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>,
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
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.loadResult = loadResult
        self.reportProgress = reportProgress
        self.sleep = sleep
        self.log = log
        self.waitTimeoutSeconds = waitTimeoutSeconds
    }

    public func activateIfNeeded(manifest: UpdateBundleManifest) throws {
        let executionPlan = useCase.guestActivationExecutionPlan(manifest: manifest)
        switch executionPlan {
        case .skip(let logMessage):
            log(logMessage)
            return
        case .activate(let version, let requestLog, let completionLog):
            log(requestLog)
            try requireCapability()
            try createRunDirectory()
            try removePreviousResult()
            let request = useCase.guestActivationRequest(
                version: version,
                requestID: requestID(),
                requestedAt: timestamp()
            )
            try writeRequest(request)
            try startVMServiceIfNeeded()
            try waitForActivationResult(request)
            log(completionLog)
        }
    }

    private func startVMServiceIfNeeded() throws {
        switch useCase.guestActivationVMStartPlan(isVMServiceLoaded: isVMServiceLoaded()) {
        case .alreadyLoaded:
            return
        case .startService:
            try startVMService()
        }
    }

    private func waitForActivationResult(_ request: RuntimeGuestActivationRequest) throws {
        log(useCase.guestActivationWaitStartedLogMessage(timeoutSeconds: waitTimeoutSeconds))
        let maxAttempts = Int(ceil(waitTimeoutSeconds / 3.0))
        let waitResult = GuestActivationWaiter.wait(
            expectedRequestId: request.id,
            configuration: GuestActivationWaitConfiguration(
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

        let resultPlan = useCase.guestActivationWaitResultPlan(waitResult)
        if let logMessage = resultPlan.logMessage {
            log(logMessage)
        }
        if let failureMessage = resultPlan.failureMessage {
            throw RuntimeGuestActivationWorkflowError.operationFailed(failureMessage)
        }
    }
}
