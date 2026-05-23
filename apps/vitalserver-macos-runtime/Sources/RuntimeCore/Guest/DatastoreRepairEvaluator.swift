import RuntimeContracts
import Foundation

public enum DatastoreRepairDecision: Equatable {
    case wait(message: String)
    case completed(message: String)
    case failed(message: String)
    case stale(message: String)
}

public enum DatastoreRepairWaitResult: Equatable {
    case completed(message: String)
    case failed(message: String)
    case timedOut
}

public struct DatastoreRepairWaitConfiguration: Equatable {
    public let maxAttempts: Int
    public let progressEveryAttempts: Int

    public init(maxAttempts: Int, progressEveryAttempts: Int) {
        self.maxAttempts = max(maxAttempts, 1)
        self.progressEveryAttempts = max(progressEveryAttempts, 1)
    }
}

public enum DatastoreRepairEvaluator {
    public static func evaluate(
        _ result: DatastoreRepairResultDocument?,
        expectedRequestId: String? = nil
    ) -> DatastoreRepairDecision {
        guard let result else {
            return .wait(message: "waiting for datastore repair guest worker")
        }

        if let expectedRequestId,
           let resultRequestId = result.requestId,
           resultRequestId != expectedRequestId {
            return .stale(message: "stale datastore repair result")
        }

        if expectedRequestId != nil, result.requestId == nil, result.schemaVersion != nil {
            return .stale(message: "datastore repair result is missing requestId")
        }

        switch result.status {
        case .pending:
            return .wait(message: result.message ?? "datastore repair pending")
        case .running:
            return .wait(message: result.message ?? "datastore repair running")
        case .completed:
            return .completed(message: result.message ?? "datastore repair completed")
        case .failed:
            return .failed(message: result.message ?? "datastore repair failed")
        case .skipped:
            return .failed(message: result.message ?? "datastore repair skipped")
        case .stale:
            return .stale(message: result.message ?? "stale datastore repair result")
        case .unknown(let status):
            return .failed(message: result.message ?? "unknown datastore repair status: \(status)")
        }
    }
}

public enum DatastoreRepairWaiter {
    public static func wait(
        expectedRequestId: String,
        configuration: DatastoreRepairWaitConfiguration,
        loadResult: () -> DatastoreRepairResultDocument?,
        onProgress: (String) -> Void,
        onStale: (String) -> Void,
        sleep: () -> Void
    ) -> DatastoreRepairWaitResult {
        for attempt in 0..<configuration.maxAttempts {
            switch DatastoreRepairEvaluator.evaluate(loadResult(), expectedRequestId: expectedRequestId) {
            case .completed(let message):
                return .completed(message: message)
            case .failed(let message):
                return .failed(message: message)
            case .stale(let message):
                onStale(message)
            case .wait(let message):
                if attempt % configuration.progressEveryAttempts == 0 {
                    onProgress(message)
                }
            }

            if attempt < configuration.maxAttempts - 1 {
                sleep()
            }
        }
        return .timedOut
    }
}
