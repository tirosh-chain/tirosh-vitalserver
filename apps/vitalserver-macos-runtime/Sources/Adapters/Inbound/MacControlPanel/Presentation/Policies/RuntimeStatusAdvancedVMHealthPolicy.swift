import Foundation
import Contracts
import RuntimeControl
import Errors

public protocol RuntimeStatusAdvancedVMHealthVocabulary: RuntimeStatusVMStateVocabulary,
    RuntimeStatusServiceValueVocabulary {
    var runtimeInstallationLabel: String { get }
    var vmStateLabel: String { get }
    var vmServiceLabel: String { get }
    var vmIPAddressLabel: String { get }
    var vmErrorsLabel: String { get }
    var waitingText: String { get }
    var guestStateStaleText: String { get }

    func installStateText(_ state: RuntimeFileState) -> String
    func vmErrorText(_ error: RuntimeVMError) -> String
}

public struct RuntimeStatusAdvancedVMHealthPolicy {
    private let vmStatePolicy: RuntimeStatusVMStatePolicy
    private let serviceValuePolicy: RuntimeStatusServiceValuePolicy
    private let guestReadinessPolicy = RuntimeStatusGuestReadinessPresentationPolicy()
    private let vocabulary: any RuntimeStatusAdvancedVMHealthVocabulary

    public init(vocabulary: any RuntimeStatusAdvancedVMHealthVocabulary) {
        self.vocabulary = vocabulary
        self.vmStatePolicy = RuntimeStatusVMStatePolicy(vocabulary: vocabulary)
        self.serviceValuePolicy = RuntimeStatusServiceValuePolicy(vocabulary: vocabulary)
    }

    public func vmHealth(status: RuntimeStatus) -> [RuntimeStatusHealthDetailItem] {
        let installInProgress = RuntimeActiveOperationPolicy.isInstallInProgress(status)
        var items = [
            RuntimeStatusHealthDetailItem(
                label: vocabulary.runtimeInstallationLabel,
                value: value(
                    vocabulary.installStateText(status.effectiveRuntimeInstallationState),
                    installStateSeverity(status.effectiveRuntimeInstallationState)
                )
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.vmStateLabel,
                value: value(vmStatePolicy.vmStateValue(status.vmState))
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.vmServiceLabel,
                value: value(serviceValuePolicy.serviceValue(
                    state: status.vmServiceState,
                    installInProgress: installInProgress
                ))
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.vmIPAddressLabel,
                value: value(
                    status.vmIP ?? guestReadinessPolicy.pendingGuestStateText(
                        status: status,
                        waitingText: vocabulary.waitingText,
                        staleText: vocabulary.guestStateStaleText
                    ),
                    status.vmServiceState == .loaded && status.vmIP != nil ? .healthy : .warning
                )
            ),
        ]
        if let vmErrors = status.vmErrors, !vmErrors.isEmpty {
            items.append(RuntimeStatusHealthDetailItem(
                label: vocabulary.vmErrorsLabel,
                value: value(
                    vmErrors.map(vocabulary.vmErrorText).joined(separator: ", "),
                    guestReadinessPolicy.vmErrorSeverity(status: status, vmErrors: vmErrors)
                )
            ))
        }
        return items
    }

    private func value(
        _ text: String,
        _ severity: RuntimeStatusReachabilityPolicy.Severity
    ) -> RuntimeStatusHealthDetailValue {
        RuntimeStatusHealthDetailValue(text: text, severity: severity, uptimeText: nil)
    }

    private func value(_ value: RuntimeStatusVMStateValue) -> RuntimeStatusHealthDetailValue {
        RuntimeStatusHealthDetailValue(
            text: value.text,
            severity: value.severity,
            uptimeText: value.uptimeText
        )
    }

    private func value(_ value: RuntimeStatusServiceValue) -> RuntimeStatusHealthDetailValue {
        RuntimeStatusHealthDetailValue(
            text: value.text,
            severity: value.severity,
            uptimeText: value.uptimeText
        )
    }

    private func installStateSeverity(_ state: RuntimeFileState) -> RuntimeStatusReachabilityPolicy.Severity {
        switch state {
        case .executable:
            .healthy
        case .missing:
            .warning
        case .present, .inspectFailed, .unknown:
            .critical
        }
    }
}
