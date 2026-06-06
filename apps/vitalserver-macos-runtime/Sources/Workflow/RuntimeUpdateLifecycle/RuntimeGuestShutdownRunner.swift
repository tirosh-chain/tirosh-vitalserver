import Contracts
import Domain
import Foundation

public enum RuntimeGuestShutdownWorkflowError: Error, CustomStringConvertible {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }
}

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
        log("guest update shutdown requested version=\(version)")
        try requireCapability()
        try createRunDirectory()
        try removePreviousResult()
        let request = RuntimeGuestShutdownRequest(
            id: requestID(),
            requestedAt: timestamp(),
            version: version
        )
        try writeRequest(request)
        try waitForShutdownReady(request)
        log("guest update shutdown ready version=\(version)")
    }

    private func waitForShutdownReady(_ request: RuntimeGuestShutdownRequest) throws {
        log("waiting for guest update shutdown result timeoutSeconds=\(waitTimeoutSeconds)")
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

        switch waitResult {
        case .ready(let message):
            log("guest update shutdown result ready message=\(message)")
        case .failed(let message):
            log("guest update shutdown result failed message=\(message)")
            throw RuntimeGuestShutdownWorkflowError.operationFailed(message)
        case .timedOut:
            throw RuntimeGuestShutdownWorkflowError.operationFailed("guest update shutdown timed out")
        }
    }
}
