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

    public func vmStartPlan(
        isVMServiceLoaded: Bool
    ) -> RuntimeGuestActivationVMStartPlan {
        isVMServiceLoaded ? .alreadyLoaded : .startService
    }

}
