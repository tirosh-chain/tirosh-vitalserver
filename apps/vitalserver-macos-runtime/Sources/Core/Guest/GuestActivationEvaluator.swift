import Contracts
import Foundation

public enum GuestActivationDecision: Equatable {
    case wait(message: String)
    case completed(message: String)
    case failed(message: String)
}

public enum GuestActivationWaitResult: Equatable {
    case completed(message: String)
    case failed(message: String)
    case timedOut
}

public struct GuestActivationWaitConfiguration: Equatable {
    public let maxAttempts: Int
    public let progressEveryAttempts: Int

    public init(maxAttempts: Int, progressEveryAttempts: Int) {
        self.maxAttempts = max(maxAttempts, 1)
        self.progressEveryAttempts = max(progressEveryAttempts, 1)
    }
}

public enum GuestActivationEvaluator {
    public static func evaluate(
        _ result: GuestUpdateActivationResultDocument?,
        expectedRequestId: String? = nil
    ) -> GuestActivationDecision {
        guard let result else {
            return .wait(message: "waiting for guest update activation worker")
        }

        if let expectedRequestId,
           let resultRequestId = result.requestId,
           resultRequestId != expectedRequestId {
            return .failed(message: "guest update activation result does not match the current request")
        }

        if expectedRequestId != nil, result.requestId == nil, result.schemaVersion != nil {
            return .failed(message: "guest update activation result is missing requestId")
        }

        switch result.status {
        case .pending:
            return .wait(message: result.message ?? "guest update activation pending")
        case .running:
            return .wait(message: result.message ?? "guest update activation running")
        case .completed:
            return .completed(message: result.message ?? "guest update activation completed")
        case .failed:
            return .failed(message: result.message ?? "guest update activation failed")
        case .skipped:
            return .failed(message: result.message ?? "guest update activation skipped")
        case .unknown(let status):
            return .failed(message: result.message ?? "unknown guest update activation status: \(status)")
        }
    }
}

public enum GuestActivationWaiter {
    public static func wait(
        expectedRequestId: String,
        configuration: GuestActivationWaitConfiguration,
        loadResult: () -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>,
        onProgress: (String) -> Void,
        sleep: () -> Void
    ) -> GuestActivationWaitResult {
        for attempt in 0..<configuration.maxAttempts {
            let decision: GuestActivationDecision
            switch loadResult() {
            case .missing:
                decision = GuestActivationEvaluator.evaluate(nil, expectedRequestId: expectedRequestId)
            case .loaded(let result):
                decision = GuestActivationEvaluator.evaluate(result, expectedRequestId: expectedRequestId)
            case .failed(let message):
                decision = .failed(message: "failed to read guest update activation result: \(message)")
            }
            switch decision {
            case .completed(let message):
                return .completed(message: message)
            case .failed(let message):
                return .failed(message: message)
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
