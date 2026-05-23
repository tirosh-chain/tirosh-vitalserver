import Foundation
import Core
import Contracts

struct RuntimeGuestActivationWorkflowContext {
    let guestRunDirectory: URL
}

struct RuntimeGuestActivationWorkflowOperations {
    let createDirectory: (URL, Bool) throws -> Void
    let removePreviousResult: () throws -> Void
    let writeRequest: (RuntimeGuestActivationRequest) throws -> Void
    let isVMServiceLoaded: () -> Bool
    let startVMService: () -> Void
    let loadResult: () -> GuestUpdateActivationResultDocument?
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let requestID: () -> String
    let timestamp: () -> String
    let sleep: () -> Void
    let log: (String) -> Void
}

struct RuntimeGuestActivationWorkflow {
    let context: RuntimeGuestActivationWorkflowContext
    let operations: RuntimeGuestActivationWorkflowOperations

    func activateIfNeeded(manifest: UpdateBundleManifest) throws {
        try runner().activateIfNeeded(manifest: manifest)
    }

    private func runner() -> RuntimeGuestActivationRunner {
        RuntimeGuestActivationRunner(
            createRunDirectory: {
                try operations.createDirectory(context.guestRunDirectory, true)
            },
            removePreviousResult: operations.removePreviousResult,
            requestID: operations.requestID,
            timestamp: operations.timestamp,
            writeRequest: operations.writeRequest,
            isVMServiceLoaded: operations.isVMServiceLoaded,
            startVMService: operations.startVMService,
            loadResult: operations.loadResult,
            reportProgress: { message in
                try? operations.writeStatus(.recovering, .activateGuestUpdate, message)
            },
            sleep: operations.sleep,
            log: operations.log
        )
    }
}
