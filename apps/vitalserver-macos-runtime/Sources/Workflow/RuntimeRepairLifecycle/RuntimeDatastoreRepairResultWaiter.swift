import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeDatastoreRepairResultWaiter {
    public var loadResult: () -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var sleep: () -> Void
    public var log: (String) -> Void
    public var waitTimeoutSeconds: Double

    public init(
        loadResult: @escaping () -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void,
        waitTimeoutSeconds: Double
    ) {
        self.loadResult = loadResult
        self.writeStatus = writeStatus
        self.sleep = sleep
        self.log = log
        self.waitTimeoutSeconds = waitTimeoutSeconds
    }

    public func wait(for request: RuntimeDatastoreRepairRequest) throws {
        log("waiting for datastore repair result timeoutSeconds=\(waitTimeoutSeconds)")
        let maxAttempts = Int(ceil(waitTimeoutSeconds / 3.0))
        let waitResult = DatastoreRepairWaiter.wait(
            expectedRequestId: request.id,
            configuration: DatastoreRepairWaitConfiguration(
                maxAttempts: maxAttempts,
                progressEveryAttempts: 5
            ),
            loadResult: loadResult,
            onProgress: { message in
                log(message)
                writeRuntimeStatusBestEffort(
                    .recovering,
                    operation: .repairDatastore,
                    message: message,
                    writeStatus: writeStatus,
                    log: log
                )
            },
            sleep: sleep
        )

        switch waitResult {
        case .completed(let message):
            log("datastore repair guest result completed message=\(message)")
            return
        case .failed(let message):
            log("datastore repair guest result failed message=\(message)")
            throw RuntimeDatastoreRepairWorkflowError.operationFailed("runtime health check failed")
        case .timedOut:
            throw RuntimeDatastoreRepairWorkflowError.operationFailed("runtime health check failed")
        }
    }
}
