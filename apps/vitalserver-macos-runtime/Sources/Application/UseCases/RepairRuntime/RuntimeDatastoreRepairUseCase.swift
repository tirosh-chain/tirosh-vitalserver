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
}
