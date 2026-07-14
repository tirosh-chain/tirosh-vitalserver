import Contracts

public enum RuntimeInstallWorkflowOperationStateProjectionError: Error, Equatable, CustomStringConvertible {
    case unknownState(String)
    case missingCurrentStep(String)

    public var description: String {
        switch self {
        case .unknownState(let value):
            return "runtime install workflow state is unknown: \(value)"
        case .missingCurrentStep(let state):
            return "runtime install workflow current step is missing state=\(state)"
        }
    }
}

public enum RuntimeInstallWorkflowOperationStateProjectionPolicy {
    public static func event(
        operationID: String,
        state: RuntimeInstallState,
        currentStep: RuntimeWorkflowStep?,
        message: String?,
        blockers: [String]
    ) throws -> RuntimeWorkflowOperationTransitionEvent {
        let explicitMessage = message ?? "runtime install state: \(state.rawValue)"
        switch state {
        case .started:
            return .started(
                operationID: operationID,
                operation: .install,
                message: explicitMessage
            )
        case .settingsLoaded, .preflightVerified, .provisionPayloadVerified:
            return .updated(
                phase: .preparing,
                currentStep: nil,
                stepStatus: nil,
                message: explicitMessage,
                reasonCodes: blockers
            )
        case .stepStarted:
            guard let currentStep else {
                throw RuntimeInstallWorkflowOperationStateProjectionError.missingCurrentStep(state.rawValue)
            }
            return .updated(
                phase: .running,
                currentStep: currentStep,
                stepStatus: .started,
                message: explicitMessage,
                reasonCodes: blockers
            )
        case .stepCompleted:
            guard let currentStep else {
                throw RuntimeInstallWorkflowOperationStateProjectionError.missingCurrentStep(state.rawValue)
            }
            return .updated(
                phase: .running,
                currentStep: currentStep,
                stepStatus: .completed,
                message: explicitMessage,
                reasonCodes: blockers
            )
        case .completed, .provisioned:
            return .completed(message: explicitMessage)
        case .preflightBlocked, .provisionPayloadBlocked, .failed:
            return .failed(message: explicitMessage, reasonCodes: blockers)
        case .unknown(let value):
            throw RuntimeInstallWorkflowOperationStateProjectionError.unknownState(value)
        }
    }
}
