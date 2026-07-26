import Contracts
import RuntimeControl

public struct RuntimeStatusGuestReadinessPresentationPolicy {
    public init() {}

    public func isWaitingForInitialGuestState(_ status: PlatformState) -> Bool {
        guard status.runtimeProviderState == .starting else {
            return false
        }
        return status.runtimeControllerHTTP == RuntimeHTTPStatusText.missingVMIP
    }

    public func vmErrorSeverity(
        status: PlatformState,
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
        status: PlatformState,
        operationState: PlatformOperationState,
        computedValue: RuntimeStatusHTTPValue,
        waitingText: String,
        staleText: String
    ) -> RuntimeStatusHTTPValue {
        guard !shouldPreserveComputedGuestHTTP(status: status, operationState: operationState) else {
            return computedValue
        }
        guard isWaitingForInitialGuestState(status),
              status.runtimeControllerHTTP == RuntimeHTTPStatusText.missingVMIP
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
        status: PlatformState,
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
        status: PlatformState,
        operationState: PlatformOperationState
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
