import Contracts

public enum RuntimeUninstallWorkflowOperationStateProjectionError: Error, Equatable, CustomStringConvertible {
    case unknownState(String)

    public var description: String {
        switch self {
        case .unknownState(let value):
            return "runtime uninstall workflow state is unknown: \(value)"
        }
    }
}

public enum RuntimeUninstallWorkflowOperationStateProjectionPolicy {
    public static func event(
        operationID: String,
        state: RuntimeUninstallState,
        message: String?,
        blockers: [String]
    ) throws -> RuntimeWorkflowOperationTransitionEvent {
        let explicitMessage = message ?? "runtime uninstall state: \(state.rawValue)"
        switch state {
        case .started:
            return .started(
                operationID: operationID,
                operation: .uninstall,
                message: explicitMessage
            )
        case .redisBackupRequested:
            return progress(
                step: .uninstallCreateRedisBackup,
                status: .started,
                message: explicitMessage,
                blockers: blockers
            )
        case .redisBackupCompleted:
            return progress(
                step: .uninstallCreateRedisBackup,
                status: .completed,
                message: explicitMessage,
                blockers: blockers
            )
        case .stopServicesRequested:
            return progress(
                step: .uninstallStopRuntimeServices,
                status: .started,
                message: explicitMessage,
                blockers: blockers
            )
        case .filesRemovalStarted:
            return progress(
                step: .uninstallRemoveFiles,
                status: .started,
                message: explicitMessage,
                blockers: blockers
            )
        case .receiptsForgetStarted:
            return progress(
                step: .uninstallForgetPackageReceipts,
                status: .started,
                message: explicitMessage,
                blockers: blockers
            )
        case .completed:
            return .completed(message: explicitMessage)
        case .serviceStopBlocked,
             .filesRemovalBlocked,
             .receiptsForgetBlocked,
             .failed:
            return .failed(message: explicitMessage, reasonCodes: blockers)
        case .unknown(let value):
            throw RuntimeUninstallWorkflowOperationStateProjectionError.unknownState(value)
        }
    }

    private static func progress(
        step: RuntimeWorkflowStep,
        status: RuntimeProgressStepStatus,
        message: String,
        blockers: [String]
    ) -> RuntimeWorkflowOperationTransitionEvent {
        .updated(
            phase: .running,
            currentStep: step,
            stepStatus: status,
            message: message,
            reasonCodes: blockers
        )
    }
}
