import Foundation
import Core
import Contracts

struct RuntimeGuestActivationRunner {
    var createRunDirectory: () throws -> Void
    var removePreviousResult: () throws -> Void
    var requestID: () -> String
    var timestamp: () -> String
    var writeRequest: (RuntimeGuestActivationRequest) throws -> Void
    var isVMServiceLoaded: () -> Bool
    var startVMService: () -> Void
    var loadResult: () -> GuestUpdateActivationResultDocument?
    var reportProgress: (String) -> Void
    var sleep: () -> Void
    var log: (String) -> Void

    func activateIfNeeded(manifest: UpdateBundleManifest) throws {
        guard manifest.artifacts.contains(where: { $0.type == .guestDeploy }) else {
            log("guest update activation not required")
            return
        }

        log("guest update activation requested version=\(manifest.version)")
        try createRunDirectory()
        try? removePreviousResult()
        let request = RuntimeGuestActivationRequest(
            id: requestID(),
            requestedAt: timestamp(),
            version: manifest.version
        )
        try writeRequest(request)

        if !isVMServiceLoaded() {
            startVMService()
        }

        try waitForActivationResult(request)
        log("guest update activation completed version=\(manifest.version)")
    }

    private func waitForActivationResult(_ request: RuntimeGuestActivationRequest) throws {
        log("waiting for guest update activation result timeoutSeconds=\(Constants.Runtime.updateActivationWaitTimeoutSeconds)")
        let maxAttempts = Int(ceil(Constants.Runtime.updateActivationWaitTimeoutSeconds / 3.0))
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
            onStale: { message in
                log("guest update activation result stale message=\(message)")
            },
            sleep: sleep
        )

        switch waitResult {
        case .completed(let message):
            log("guest update activation result completed message=\(message)")
            return
        case .failed(let message):
            log("guest update activation result failed message=\(message)")
            throw LauncherError.runtimeHealthFailed
        case .timedOut:
            throw LauncherError.runtimeHealthFailed
        }
    }
}
