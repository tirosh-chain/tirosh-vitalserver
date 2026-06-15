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

    public func request(
        plan: RuntimeGuestShutdownPlan,
        requestID: String,
        requestedAt: String
    ) -> RuntimeGuestShutdownRequest {
        RuntimeGuestShutdownRequest(
            id: requestID,
            requestedAt: requestedAt,
            version: plan.version
        )
    }

    public func request(
        version: String,
        requestID: String,
        requestedAt: String
    ) -> RuntimeGuestShutdownRequest {
        RuntimeGuestShutdownRequest(
            id: requestID,
            requestedAt: requestedAt,
            version: version
        )
    }

    public func waitStartedLogMessage(timeoutSeconds: Double) -> String {
        "waiting for guest update shutdown result timeoutSeconds=\(timeoutSeconds)"
    }

    public func waitConfiguration(timeoutSeconds: Double) throws -> GuestShutdownWaitConfiguration {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw RuntimeGuestUpdateUseCaseError.operationFailed(
                "invalid guest shutdown wait configuration: timeoutSeconds must be positive"
            )
        }
        return GuestShutdownWaitConfiguration(
            maxAttempts: Int(ceil(timeoutSeconds / 3.0)),
            progressEveryAttempts: 5
        )
    }

    public func waitResultPlan(
        _ result: GuestShutdownWaitResult
    ) -> RuntimeGuestWaitResultPlan {
        switch result {
        case .ready(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update shutdown result ready message=\(message)",
                failureMessage: nil
            )
        case .failed(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update shutdown result failed message=\(message)",
                failureMessage: message
            )
        case .timedOut:
            return RuntimeGuestWaitResultPlan(
                logMessage: nil,
                failureMessage: "guest update shutdown timed out"
            )
        }
    }

    public func waitResultExecutionPlan(
        _ result: GuestShutdownWaitResult
    ) -> RuntimeGuestWaitResultExecutionPlan {
        switch result {
        case .ready(let message):
            return .completed(logMessage: "guest update shutdown result ready message=\(message)")
        case .failed(let message):
            return .failed(
                logMessage: "guest update shutdown result failed message=\(message)",
                failureMessage: message
            )
        case .timedOut:
            return .failedWithoutLog(failureMessage: "guest update shutdown timed out")
        }
    }
}
