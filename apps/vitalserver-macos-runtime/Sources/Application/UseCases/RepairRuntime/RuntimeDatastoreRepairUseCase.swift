import Contracts
import Domain
import Foundation

public struct RepairRuntimeDatastorePlan: Equatable, Sendable {
    public let requestedLogMessage: String
    public let requestedStatusMessage: String
    public let completedLogMessage: String
    public let completedStatusMessage: String
    public let restartPolicy: RuntimeServiceRestartPolicy

    public init(
        requestedLogMessage: String,
        requestedStatusMessage: String,
        completedLogMessage: String,
        completedStatusMessage: String,
        restartPolicy: RuntimeServiceRestartPolicy
    ) {
        self.requestedLogMessage = requestedLogMessage
        self.requestedStatusMessage = requestedStatusMessage
        self.completedLogMessage = completedLogMessage
        self.completedStatusMessage = completedStatusMessage
        self.restartPolicy = restartPolicy
    }
}

public struct RuntimeDatastoreRepairUseCase {
    public init() {}

    public func plan() -> RepairRuntimeDatastorePlan {
        RepairRuntimeDatastorePlan(
            requestedLogMessage: "datastore repair requested",
            requestedStatusMessage: "datastore repair requested",
            completedLogMessage: "datastore repair completed",
            completedStatusMessage: "datastore repair completed",
            restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: true,
                restartWatchdog: true
            )
        )
    }

    public func request(
        requestID: String,
        requestedAt: String
    ) -> RuntimeDatastoreRepairRequest {
        RuntimeDatastoreRepairRequest(id: requestID, requestedAt: requestedAt)
    }

    public func waitStartedLogMessage(timeoutSeconds: Double) -> String {
        "waiting for datastore repair result timeoutSeconds=\(timeoutSeconds)"
    }

    public func waitProgressPlan(message: String) -> RepairRuntimeStatusPlan {
        RepairRuntimeStatusPlan(
            status: .recovering,
            operation: .repairDatastore,
            message: message
        )
    }

    public func waitResultPlan(
        _ result: DatastoreRepairWaitResult
    ) -> RepairRuntimeWaitResultPlan {
        switch result {
        case .completed(let message):
            return RepairRuntimeWaitResultPlan(
                logMessage: "datastore repair guest result completed message=\(message)",
                failureMessage: nil
            )
        case .failed(let message):
            return RepairRuntimeWaitResultPlan(
                logMessage: "datastore repair guest result failed message=\(message)",
                failureMessage: "runtime health check failed"
            )
        case .timedOut:
            return RepairRuntimeWaitResultPlan(
                logMessage: nil,
                failureMessage: "runtime health check failed"
            )
        }
    }
}
