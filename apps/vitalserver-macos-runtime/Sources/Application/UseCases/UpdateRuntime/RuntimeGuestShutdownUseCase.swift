import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestShutdownPlan: Equatable, Sendable {
    public let version: String
    public let requestedLogMessage: String
    public let readyLogMessage: String

    public init(
        version: String,
        requestedLogMessage: String,
        readyLogMessage: String
    ) {
        self.version = version
        self.requestedLogMessage = requestedLogMessage
        self.readyLogMessage = readyLogMessage
    }
}

public enum RuntimeGuestShutdownExecutionPlan: Equatable, Sendable {
    case prepare(version: String, requestLog: String, readyLog: String)
}

public struct RuntimeGuestShutdownUseCase {
    public init() {}

    public func plan(version: String) -> RuntimeGuestShutdownPlan {
        RuntimeGuestShutdownPlan(
            version: version,
            requestedLogMessage: "guest update shutdown requested version=\(version)",
            readyLogMessage: "guest update shutdown ready version=\(version)"
        )
    }

    public func executionPlan(version: String) -> RuntimeGuestShutdownExecutionPlan {
        .prepare(
            version: version,
            requestLog: "guest update shutdown requested version=\(version)",
            readyLog: "guest update shutdown ready version=\(version)"
        )
    }

    public func waitStartedLogMessage(timeoutSeconds: Double) -> String {
        "waiting for guest update shutdown result timeoutSeconds=\(timeoutSeconds)"
    }

    public func operationWaitConfiguration(timeoutSeconds: Double) throws -> RuntimeGuestOperationWaitConfiguration {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw RuntimeGuestUpdateUseCaseError.operationFailed(
                "invalid guest operation wait configuration: timeoutSeconds must be positive"
            )
        }
        return RuntimeGuestOperationWaitConfiguration(
            maxAttempts: Int(ceil(timeoutSeconds / 3.0)),
            progressEveryAttempts: 5
        )
    }
}
