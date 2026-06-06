import Contracts
import Domain
import Foundation

public enum RuntimeGuestActivationWorkflowError: Error, CustomStringConvertible {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }
}

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
        guard manifest.artifacts.contains(where: { $0.type == .guestDeploy }) else {
            log("guest update activation not required")
            return
        }

        log("guest update activation requested version=\(manifest.version)")
        try requireCapability()
        try createRunDirectory()
        try removePreviousResult()
        let request = RuntimeGuestActivationRequest(
            id: requestID(),
            requestedAt: timestamp(),
            version: manifest.version
        )
        try writeRequest(request)

        if !isVMServiceLoaded() {
            try startVMService()
        }

        try waitForActivationResult(request)
        log("guest update activation completed version=\(manifest.version)")
    }

    private func waitForActivationResult(_ request: RuntimeGuestActivationRequest) throws {
        log("waiting for guest update activation result timeoutSeconds=\(waitTimeoutSeconds)")
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

        switch waitResult {
        case .completed(let message):
            log("guest update activation result completed message=\(message)")
            return
        case .failed(let message):
            log("guest update activation result failed message=\(message)")
            throw RuntimeGuestActivationWorkflowError.operationFailed("runtime health check failed")
        case .timedOut:
            throw RuntimeGuestActivationWorkflowError.operationFailed("runtime health check failed")
        }
    }
}
