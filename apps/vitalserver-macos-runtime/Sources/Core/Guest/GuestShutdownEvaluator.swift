import Contracts

public enum GuestShutdownDecision: Equatable {
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

public enum GuestShutdownEvaluator {
    public static func evaluate(
        _ result: GuestUpdateShutdownResultDocument?,
        expectedRequestId: String
    ) -> GuestShutdownDecision {
        guard let result else {
            return .wait(message: "waiting for guest update shutdown worker")
        }

        guard result.requestId == expectedRequestId else {
            return .failed(message: "guest update shutdown result does not match the current request")
        }

        switch result.status {
        case .pending:
            return .wait(message: result.message ?? "guest update shutdown pending")
        case .running:
            return .wait(message: result.message ?? "guest update shutdown running")
        case .ready:
            return .ready(message: result.message ?? "guest update shutdown ready")
        case .failed:
            return .failed(message: result.message ?? "guest update shutdown failed")
        case .unknown(let status):
            return .failed(message: result.message ?? "unknown guest update shutdown status: \(status)")
        }
    }
}

public enum GuestShutdownWaiter {
    public static func wait(
        expectedRequestId: String,
        configuration: GuestShutdownWaitConfiguration,
        loadResult: () -> GuestUpdateShutdownResultDocument?,
        onProgress: (String) -> Void,
        sleep: () -> Void
    ) -> GuestShutdownWaitResult {
        for attempt in 0..<configuration.maxAttempts {
            switch GuestShutdownEvaluator.evaluate(loadResult(), expectedRequestId: expectedRequestId) {
            case .ready(let message):
                return .ready(message: message)
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
