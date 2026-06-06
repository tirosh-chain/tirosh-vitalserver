import Application
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
    private var useCase: RepairRuntimeUseCase {
        RepairRuntimeUseCase()
    }

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
        log(useCase.datastoreRepairWaitStartedLogMessage(timeoutSeconds: waitTimeoutSeconds))
        let maxAttempts = Int(ceil(waitTimeoutSeconds / 3.0))
        let waitResult = DatastoreRepairWaiter.wait(
            expectedRequestId: request.id,
            configuration: DatastoreRepairWaitConfiguration(
                maxAttempts: maxAttempts,
                progressEveryAttempts: 5
            ),
            loadResult: loadResult,
            onProgress: { message in
                let progressPlan = useCase.datastoreRepairWaitProgressPlan(message: message)
                log(message)
                writeRuntimeStatusBestEffort(
                    progressPlan.status,
                    operation: progressPlan.operation,
                    message: progressPlan.message,
                    writeStatus: writeStatus,
                    log: log
                )
            },
            sleep: sleep
        )

        let resultPlan = useCase.datastoreRepairWaitResultPlan(waitResult)
        if let logMessage = resultPlan.logMessage {
            log(logMessage)
        }
        if let failureMessage = resultPlan.failureMessage {
            throw RuntimeDatastoreRepairWorkflowError.operationFailed(failureMessage)
        }
    }
}
