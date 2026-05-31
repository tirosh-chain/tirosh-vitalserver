import Core
import Contracts
import Foundation

struct RuntimeGuestShutdownRunner {
    var requireCapability: () throws -> Void
    var createRunDirectory: () throws -> Void
    var removePreviousResult: () throws -> Void
    var requestID: () -> String
    var timestamp: () -> String
    var writeRequest: (RuntimeGuestShutdownRequest) throws -> Void
    var loadResult: () -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>
    var reportProgress: (String) -> Void
    var sleep: () -> Void
    var log: (String) -> Void

    func prepareForUpdate(version: String) throws {
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
        log("waiting for guest update shutdown result timeoutSeconds=\(Constants.Runtime.updateShutdownWaitTimeoutSeconds)")
        let maxAttempts = Int(ceil(Constants.Runtime.updateShutdownWaitTimeoutSeconds / 3.0))
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
            throw LauncherError.runtimeOperationFailed(message)
        case .timedOut:
            throw LauncherError.runtimeOperationFailed("guest update shutdown timed out")
        }
    }
}
