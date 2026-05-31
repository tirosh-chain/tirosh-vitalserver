import Foundation
import Core
import Contracts

struct RuntimeDatastoreRepairWorkflowContext {
    let guestRunDirectory: URL
}

struct RuntimeDatastoreRepairWorkflowOperations {
    let requireCapability: () throws -> Void
    let createDirectory: (URL, Bool) throws -> Void
    let removePreviousResult: () throws -> Void
    let writeRequest: (RuntimeDatastoreRepairRequest) throws -> Void
    let isVMServiceLoaded: () -> Bool
    let startVMService: () -> Void
    let restartVMService: () -> Void
    let loadResult: () -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>
    let restartProxyService: () -> Void
    let restartWatchdogService: () -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let requestID: () -> String
    let timestamp: () -> String
    let sleep: () -> Void
    let log: (String) -> Void
}

struct RuntimeDatastoreRepairWorkflow {
    let context: RuntimeDatastoreRepairWorkflowContext
    let operations: RuntimeDatastoreRepairWorkflowOperations

    func repair() throws {
        try runner().run()
    }

    private func runner() -> RuntimeDatastoreRepairRunner {
        RuntimeDatastoreRepairRunner(
            requireCapability: operations.requireCapability,
            prepareGuestRunDirectory: {
                try operations.createDirectory(context.guestRunDirectory, true)
            },
            removePreviousResult: operations.removePreviousResult,
            writeRequest: operations.writeRequest,
            isVMServiceLoaded: operations.isVMServiceLoaded,
            startVMService: operations.startVMService,
            restartVMService: operations.restartVMService,
            waitForResult: { request in
                try waiter().wait(for: request)
            },
            restartProxyService: operations.restartProxyService,
            restartWatchdogService: operations.restartWatchdogService,
            waitForHealth: operations.waitForHealth,
            writeStatus: operations.writeStatus,
            makeRequestID: operations.requestID,
            timestamp: operations.timestamp,
            log: operations.log
        )
    }

    private func waiter() -> RuntimeDatastoreRepairResultWaiter {
        RuntimeDatastoreRepairResultWaiter(
            loadResult: operations.loadResult,
            writeStatus: operations.writeStatus,
            sleep: operations.sleep,
            log: operations.log
        )
    }
}
