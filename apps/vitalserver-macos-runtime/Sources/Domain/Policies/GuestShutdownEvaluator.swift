import Contracts
import Errors

public enum GuestShutdownDecision: Equatable {
    case missing(message: String)
    case wait(message: String)
    case ready(message: String)
    case failed(message: String)
}

public enum GuestShutdownWaitResult: Equatable {
    case ready(message: String)
    case failed(message: String)
    case timedOut
}

public struct GuestShutdownWaitConfiguration: Equatable {
    public let maxAttempts: Int
    public let progressEveryAttempts: Int

    public init(maxAttempts: Int, progressEveryAttempts: Int) {
        self.maxAttempts = max(maxAttempts, 1)
        self.progressEveryAttempts = max(progressEveryAttempts, 1)
    }
}

public enum GuestShutdownWaitAttemptOutcome: Equatable {
    case ready(message: String)
    case failed(message: String)
    case waiting(message: String, shouldPublishProgress: Bool)
}

public enum GuestShutdownEvaluator {
    public static func evaluate(
        _ result: GuestUpdateShutdownResultDocument?,
        expectedRequestId: String
    ) -> GuestShutdownDecision {
        guard let result else {
            return .missing(message: "waiting for guest update shutdown worker")
        }

        guard result.requestId == expectedRequestId else {
            return .failed(message: "guest update shutdown result does not match the current request")
        }

        switch result.status {
        case .pending:
            return .wait(message: result.message ?? "guest update shutdown pending")
        case .running:
            if result.shutdownPhase == .poweroffFailed {
                return .failed(message: result.message ?? "guest poweroff request failed")
            }
            return .wait(message: result.message ?? "guest update shutdown running")
        case .ready:
            return evaluateReadyResult(result)
        case .failed:
            return .failed(message: result.message ?? "guest update shutdown failed")
        case .unknown(let status):
            return .failed(message: result.message ?? "unknown guest update shutdown status: \(status)")
        }
    }

    private static func evaluateReadyResult(
        _ result: GuestUpdateShutdownResultDocument
    ) -> GuestShutdownDecision {
        guard let phase = result.shutdownPhase else {
            return .failed(message: "guest update shutdown ready result is missing shutdownPhase")
        }

        switch phase {
        case .preparing, .prepared:
            return .wait(message: result.message ?? "waiting for guest poweroff request")
        case .poweroffRequested:
            return .ready(message: result.message ?? "guest poweroff requested")
        case .poweroffFailed:
            return .failed(message: result.message ?? "guest poweroff request failed")
        case .unknown(let phase):
            return .failed(message: result.message ?? "unknown guest update shutdown phase: \(phase)")
        }
    }
}

public enum GuestShutdownWaiter {
    public static func evaluateAttempt(
        expectedRequestId: String,
        configuration: GuestShutdownWaitConfiguration,
        attempt: Int,
        loadResult: RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>
    ) -> GuestShutdownWaitAttemptOutcome {
        let decision: GuestShutdownDecision
        switch loadResult {
        case .missing:
            decision = GuestShutdownEvaluator.evaluate(nil, expectedRequestId: expectedRequestId)
        case .loaded(let result):
            decision = GuestShutdownEvaluator.evaluate(result, expectedRequestId: expectedRequestId)
        case .failed(let message):
            decision = .failed(message: "failed to read guest update shutdown result: \(message)")
        }
        switch decision {
        case .ready(let message):
            return .ready(message: message)
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
