import Foundation
import Core
import Contracts

struct RuntimeDatastoreRepairResultWaiter {
    var loadResult: () -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var sleep: () -> Void
    var log: (String) -> Void

    func wait(for request: RuntimeDatastoreRepairRequest) throws {
        log("waiting for datastore repair result timeoutSeconds=\(Constants.Runtime.datastoreRepairWaitTimeoutSeconds)")
        let maxAttempts = Int(ceil(Constants.Runtime.datastoreRepairWaitTimeoutSeconds / 3.0))
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
            throw LauncherError.runtimeHealthFailed
        case .timedOut:
            throw LauncherError.runtimeHealthFailed
        }
    }
}
