import Contracts
import RuntimeControl

public struct RuntimeStatusGuestReadinessPresentationPolicy {
    public init() {}

    public func isWaitingForInitialGuestState(_ status: RuntimeStatus) -> Bool {
        guard status.vmState == .starting else {
            return false
        }
        return status.guestHTTP == RuntimeHTTPStatusText.missingVMIP
    }

    public func vmErrorSeverity(
        status: RuntimeStatus,
        vmErrors: [RuntimeVMError]
    ) -> RuntimeStatusReachabilityPolicy.Severity {
        guard isWaitingForInitialGuestState(status),
              vmErrors.allSatisfy(isInitialGuestStateError)
        else {
            return .critical
        }
        return .warning
    }

    public func guestHTTPValue(
        status: RuntimeStatus,
        operationState: RuntimeOperationState,
        computedValue: RuntimeStatusHTTPValue,
        waitingText: String,
        staleText: String
    ) -> RuntimeStatusHTTPValue {
        guard !shouldPreserveComputedGuestHTTP(status: status, operationState: operationState) else {
            return computedValue
        }
        guard isWaitingForInitialGuestState(status),
              status.guestHTTP == RuntimeHTTPStatusText.missingVMIP
        else {
            return computedValue
        }
        return RuntimeStatusHTTPValue(
            text: pendingGuestStateText(
                status: status,
                waitingText: waitingText,
                staleText: staleText
            ),
            severity: .warning,
            uptimeText: computedValue.uptimeText
        )
    }

    public func pendingGuestStateText(
        status: RuntimeStatus,
        waitingText: String,
        staleText _: String
    ) -> String {
        waitingText
    }

    private func isInitialGuestStateError(_ error: RuntimeVMError) -> Bool {
        switch error {
        case .missingIPAddress:
            return true
        case .guestHTTP(let status):
            return status == RuntimeHTTPStatusText.missingVMIP
        default:
            return false
        }
    }

    private func shouldPreserveComputedGuestHTTP(
        status: RuntimeStatus,
        operationState: RuntimeOperationState
    ) -> Bool {
        if RuntimeActiveOperationPolicy.isInitializationInProgress(status) {
            return true
        }
        guard let operation = operationState.operationForPresentation else {
            return false
        }
        return RuntimeActiveOperationPolicy.isInstallOperation(operation)
            || RuntimeActiveOperationPolicy.isRecoveryOperation(operation)
            || RuntimeActiveOperationPolicy.isUpdateOperation(operation)
    }
}
