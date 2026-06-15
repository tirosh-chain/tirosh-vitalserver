import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestActivationPlan: Equatable, Sendable {
    public let requiresActivation: Bool
    public let version: String
    public let skippedLogMessage: String?
    public let requestedLogMessage: String?
    public let completedLogMessage: String?

    public init(
        requiresActivation: Bool,
        version: String,
        skippedLogMessage: String?,
        requestedLogMessage: String?,
        completedLogMessage: String?
    ) {
        self.requiresActivation = requiresActivation
        self.version = version
        self.skippedLogMessage = skippedLogMessage
        self.requestedLogMessage = requestedLogMessage
        self.completedLogMessage = completedLogMessage
    }
}

public enum RuntimeGuestActivationExecutionPlan: Equatable, Sendable {
    case skip(logMessage: String)
    case activate(version: String, requestedLogMessage: String, completedLogMessage: String)
}

public enum RuntimeGuestActivationVMStartPlan: Equatable, Sendable {
    case alreadyLoaded
    case startService
}

public struct RuntimeGuestActivationUseCase {
    public init() {}

    public func plan(
        manifest: UpdateBundleManifest
    ) -> RuntimeGuestActivationPlan {
        let requiresActivation = manifest.artifacts.contains(where: { $0.type == .guestDeploy })
        guard requiresActivation else {
            return RuntimeGuestActivationPlan(
                requiresActivation: false,
                version: manifest.version,
                skippedLogMessage: "guest update activation not required",
                requestedLogMessage: nil,
                completedLogMessage: nil
            )
        }

        return RuntimeGuestActivationPlan(
            requiresActivation: true,
            version: manifest.version,
            skippedLogMessage: nil,
            requestedLogMessage: "guest update activation requested version=\(manifest.version)",
            completedLogMessage: "guest update activation completed version=\(manifest.version)"
        )
    }

    public func executionPlan(
        manifest: UpdateBundleManifest
    ) -> RuntimeGuestActivationExecutionPlan {
        let requiresActivation = manifest.artifacts.contains(where: { $0.type == .guestDeploy })
        guard requiresActivation else {
            return .skip(logMessage: "guest update activation not required")
        }
        return .activate(
            version: manifest.version,
            requestedLogMessage: "guest update activation requested version=\(manifest.version)",
            completedLogMessage: "guest update activation completed version=\(manifest.version)"
        )
    }

    public func request(
        plan: RuntimeGuestActivationPlan,
        requestID: String,
        requestedAt: String
    ) -> RuntimeGuestActivationRequest? {
        guard plan.requiresActivation else {
            return nil
        }
        return RuntimeGuestActivationRequest(
            id: requestID,
            requestedAt: requestedAt,
            version: plan.version
        )
    }

    public func request(
        version: String,
        requestID: String,
        requestedAt: String
    ) -> RuntimeGuestActivationRequest {
        RuntimeGuestActivationRequest(
            id: requestID,
            requestedAt: requestedAt,
            version: version
        )
    }

    public func vmStartPlan(
        isVMServiceLoaded: Bool
    ) -> RuntimeGuestActivationVMStartPlan {
        isVMServiceLoaded ? .alreadyLoaded : .startService
    }

    public func waitStartedLogMessage(timeoutSeconds: Double) -> String {
        "waiting for guest update activation result timeoutSeconds=\(timeoutSeconds)"
    }

    public func waitConfiguration(timeoutSeconds: Double) throws -> GuestActivationWaitConfiguration {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw RuntimeGuestUpdateUseCaseError.operationFailed(
                "invalid guest activation wait configuration: timeoutSeconds must be positive"
            )
        }
        return GuestActivationWaitConfiguration(
            maxAttempts: Int(ceil(timeoutSeconds / 3.0)),
            progressEveryAttempts: 5
        )
    }

    public func requiredRequestMissingFailureMessage() -> String {
        "guest activation request missing for required activation"
    }

    public func waitResultPlan(
        _ result: GuestActivationWaitResult
    ) -> RuntimeGuestWaitResultPlan {
        switch result {
        case .completed(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update activation result completed message=\(message)",
                failureMessage: nil
            )
        case .failed(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update activation result failed message=\(message)",
                failureMessage: "runtime health check failed"
            )
        case .timedOut:
            return RuntimeGuestWaitResultPlan(
                logMessage: nil,
                failureMessage: "runtime health check failed"
            )
        }
    }

    public func waitResultExecutionPlan(
        _ result: GuestActivationWaitResult
    ) -> RuntimeGuestWaitResultExecutionPlan {
        switch result {
        case .completed(let message):
            return .completed(logMessage: "guest update activation result completed message=\(message)")
        case .failed(let message):
            return .failed(
                logMessage: "guest update activation result failed message=\(message)",
                failureMessage: "runtime health check failed"
            )
        case .timedOut:
            return .failedWithoutLog(failureMessage: "runtime health check failed")
        }
    }
}
