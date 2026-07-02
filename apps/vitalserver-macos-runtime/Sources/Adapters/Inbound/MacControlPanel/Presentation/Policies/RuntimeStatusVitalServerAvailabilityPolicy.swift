import Foundation
import Contracts
import RuntimeControl
import Errors

public protocol RuntimeStatusVitalServerAvailabilityVocabulary: RuntimeStatusReachabilityLabelVocabulary {
    var installingText: String { get }
    var initializingText: String { get }
    var updatingText: String { get }
    var recoveringText: String { get }
}

public struct RuntimeStatusVitalServerAvailabilityValue: Equatable, Sendable {
    public let text: String
    public let severity: RuntimeStatusReachabilityPolicy.Severity
    public let uptimeText: String?

    public init(
        text: String,
        severity: RuntimeStatusReachabilityPolicy.Severity,
        uptimeText: String?
    ) {
        self.text = text
        self.severity = severity
        self.uptimeText = uptimeText
    }
}

public struct RuntimeStatusVitalServerAvailabilityPolicy {
    private let reachabilityPolicy = RuntimeStatusReachabilityPolicy()
    private let labelPolicy: RuntimeStatusReachabilityLabelPolicy
    private let vocabulary: any RuntimeStatusVitalServerAvailabilityVocabulary

    public init(vocabulary: any RuntimeStatusVitalServerAvailabilityVocabulary) {
        self.vocabulary = vocabulary
        self.labelPolicy = RuntimeStatusReachabilityLabelPolicy(vocabulary: vocabulary)
    }

    public func availability(
        status: RuntimeStatus,
        now: Date
    ) -> RuntimeStatusVitalServerAvailabilityValue {
        let text: String
        if RuntimeActiveOperationPolicy.isInstallInProgress(status) {
            text = vocabulary.installingText
        } else if RuntimeActiveOperationPolicy.isInitializationInProgress(status) {
            text = vocabulary.initializingText
        } else if RuntimeActiveOperationPolicy.isRecoveryInProgress(status) {
            text = vocabulary.recoveringText
        } else if RuntimeActiveOperationPolicy.isUpdateInProgress(status) {
            text = vocabulary.updatingText
        } else if !status.effectiveRuntimeInstallationState.isExecutable {
            text = vocabulary.unavailableText
        } else {
            text = labelPolicy.serviceReachabilityLabel(status.hostProxyHTTP)
        }
        return RuntimeStatusVitalServerAvailabilityValue(
            text: text,
            severity: availabilitySeverity(status),
            uptimeText: nil
        )
    }

    private func availabilitySeverity(_ status: RuntimeStatus) -> RuntimeStatusReachabilityPolicy.Severity {
        if RuntimeActiveOperationPolicy.isInstallInProgress(status) ||
            RuntimeActiveOperationPolicy.isInitializationInProgress(status) ||
            RuntimeActiveOperationPolicy.isRecoveryInProgress(status) ||
            RuntimeActiveOperationPolicy.isUpdateInProgress(status) {
            return .warning
        }
        if !status.effectiveRuntimeInstallationState.isExecutable {
            return .critical
        }
        return reachabilityPolicy.httpSeverity(status.hostProxyHTTP)
    }
}
