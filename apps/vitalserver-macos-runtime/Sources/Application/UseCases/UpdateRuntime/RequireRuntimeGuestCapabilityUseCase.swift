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

public struct RuntimeGuestCapabilityRequirementOperations {
    public let loadRuntimeState: () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>

    public init(
        loadRuntimeState: @escaping () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>
    ) {
        self.loadRuntimeState = loadRuntimeState
    }
}

public struct RequireRuntimeGuestCapabilityUseCase {
    public init() {}

    public func require(
        _ capability: RuntimeGuestCapabilityRequirement,
        operations: RuntimeGuestCapabilityRequirementOperations
    ) throws {
        let plan = guestCapabilityRequirementPlan(
            loadResult: operations.loadRuntimeState(),
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
        loadResult: RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>,
        capability: RuntimeGuestCapabilityRequirement
    ) -> RuntimeGuestCapabilityDecision {
        switch loadResult {
        case .loaded(let state):
            guard let capabilities = state.capabilities,
                  capability.isSupported(by: capabilities)
            else {
                return RuntimeGuestCapabilityDecision(
                    isSupported: false,
                    failure: .missingCapability(capability.rawValue)
                )
            }
            return RuntimeGuestCapabilityDecision(isSupported: true, failure: nil)
        case .missing:
            return RuntimeGuestCapabilityDecision(
                isSupported: false,
                failure: .missingRuntimeState(capability.rawValue)
            )
        case .failed(let message):
            return RuntimeGuestCapabilityDecision(
                isSupported: false,
                failure: .runtimeStateReadFailed(
                    capability: capability.rawValue,
                    reason: message
                )
            )
        }
    }

    public func guestCapabilityRequirementPlan(
        loadResult: RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>,
        capability: RuntimeGuestCapabilityRequirement
    ) -> RuntimeGuestCapabilityRequirementPlan {
        let decision = guestCapabilityDecision(
            loadResult: loadResult,
            capability: capability
        )
        guard let failure = decision.failure else {
            return .supported
        }
        return .failed(failure)
    }
}
