import Contracts
import Foundation

public enum DatastoreRepairDecision: Equatable {
    case missing(message: String)
    case wait(message: String)
    case completed(message: String)
    case failed(message: String)
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

public enum DatastoreRepairWaitAttemptOutcome: Equatable {
    case completed(message: String)
    case failed(message: String)
    case waiting(message: String, shouldPublishProgress: Bool)
}

public enum DatastoreRepairEvaluator {
    public static func evaluate(
        _ result: DatastoreRepairResultDocument?,
        expectedRequestId: String? = nil
    ) -> DatastoreRepairDecision {
        guard let result else {
            return .missing(message: "waiting for datastore repair guest worker")
        }

        if let expectedRequestId,
           let resultRequestId = result.requestId,
           resultRequestId != expectedRequestId {
            return .failed(message: "datastore repair result does not match the current request")
        }

        if expectedRequestId != nil, result.requestId == nil, result.schemaVersion != nil {
            return .failed(message: "datastore repair result is missing requestId")
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
        case .unknown(let status):
            return .failed(message: result.message ?? "unknown datastore repair status: \(status)")
        }
    }
}

public enum DatastoreRepairWaiter {
    public static func evaluateAttempt(
        expectedRequestId: String,
        configuration: DatastoreRepairWaitConfiguration,
        attempt: Int,
        loadResult: RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>
    ) -> DatastoreRepairWaitAttemptOutcome {
        let decision: DatastoreRepairDecision
        switch loadResult {
        case .missing:
            decision = DatastoreRepairEvaluator.evaluate(nil, expectedRequestId: expectedRequestId)
        case .loaded(let result):
            decision = DatastoreRepairEvaluator.evaluate(result, expectedRequestId: expectedRequestId)
        case .failed(let message):
            decision = .failed(message: "failed to read datastore repair result: \(message)")
        }
        switch decision {
        case .completed(let message):
            return .completed(message: message)
        case .failed(let message):
            return .failed(message: message)
        case .missing(let message), .wait(let message):
            return .waiting(
                message: message,
                shouldPublishProgress: attempt % configuration.progressEveryAttempts == 0
            )
        }
    }
}
