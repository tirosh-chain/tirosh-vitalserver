import Contracts
import Errors

public struct RuntimeGuestCapabilityDecision: Equatable, Sendable {
    public let isSupported: Bool
    public let failure: RuntimeGuestCapabilityCheckError?

    public init(isSupported: Bool, failure: RuntimeGuestCapabilityCheckError?) {
        self.isSupported = isSupported
        self.failure = failure
    }
}

public enum RuntimeGuestCapabilityRequirementPlan: Equatable, Sendable {
    case supported
    case failed(RuntimeGuestCapabilityCheckError)
}

public enum RuntimeGuestCapabilityReadResult: Equatable, Sendable {
    case loaded(RuntimeGuestControlCapabilities)
    case failed(String)
}

public struct RuntimeGuestCapabilityRequirementOperations {
    public let loadCapabilities: () -> RuntimeGuestCapabilityReadResult

    public init(
        loadCapabilities: @escaping () -> RuntimeGuestCapabilityReadResult
    ) {
        self.loadCapabilities = loadCapabilities
    }
}

public struct RequireRuntimeGuestCapabilityUseCase {
    public init() {}

    public func require(
        _ capability: RuntimeGuestCapabilityRequirement,
        operations: RuntimeGuestCapabilityRequirementOperations
    ) throws {
        let plan = guestCapabilityRequirementPlan(
            readResult: operations.loadCapabilities(),
            capability: capability
        )
        switch plan {
        case .supported:
            return
        case .failed(let failure):
            throw failure
        }
    }

    public func guestCapabilityDecision(
        readResult: RuntimeGuestCapabilityReadResult,
        capability: RuntimeGuestCapabilityRequirement
    ) -> RuntimeGuestCapabilityDecision {
        switch readResult {
        case .loaded(let capabilities):
            guard capability.isSupported(by: capabilities) else {
                return RuntimeGuestCapabilityDecision(
                    isSupported: false,
                    failure: .missingCapability(capability.rawValue)
                )
            }
            return RuntimeGuestCapabilityDecision(isSupported: true, failure: nil)
        case .failed(let message):
            return RuntimeGuestCapabilityDecision(
                isSupported: false,
                failure: .capabilitiesReadFailed(
                    capability: capability.rawValue,
                    reason: message
                )
            )
        }
    }

    public func guestCapabilityRequirementPlan(
        readResult: RuntimeGuestCapabilityReadResult,
        capability: RuntimeGuestCapabilityRequirement
    ) -> RuntimeGuestCapabilityRequirementPlan {
        let decision = guestCapabilityDecision(
            readResult: readResult,
            capability: capability
        )
        guard let failure = decision.failure else {
            return .supported
        }
        return .failed(failure)
    }
}
