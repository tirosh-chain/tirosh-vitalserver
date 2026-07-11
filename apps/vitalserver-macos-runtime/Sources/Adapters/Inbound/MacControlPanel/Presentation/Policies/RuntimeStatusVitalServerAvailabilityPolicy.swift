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
        status: PlatformState,
        operationState: PlatformOperationState,
        now: Date
    ) -> RuntimeStatusVitalServerAvailabilityValue {
        let text: String
        if let operation = operationState.operationForPresentation,
           RuntimeActiveOperationPolicy.isInstallOperation(operation) {
            text = vocabulary.installingText
        } else if RuntimeActiveOperationPolicy.isInitializationInProgress(status) {
            text = vocabulary.initializingText
        } else if let operation = operationState.operationForPresentation,
                  RuntimeActiveOperationPolicy.isRecoveryInProgress(status, operation: operation) {
            text = vocabulary.recoveringText
        } else if let operation = operationState.operationForPresentation,
                  RuntimeActiveOperationPolicy.isUpdateInProgress(status, operation: operation) {
            text = vocabulary.updatingText
        } else if !status.runtimeInstallationState.isExecutable {
            text = vocabulary.unavailableText
        } else {
            text = labelPolicy.serviceReachabilityLabel(status.publicProxyHTTP)
        }
        return RuntimeStatusVitalServerAvailabilityValue(
            text: text,
            severity: availabilitySeverity(status, operationState: operationState),
            uptimeText: nil
        )
    }

    private func availabilitySeverity(
        _ status: PlatformState,
        operationState: PlatformOperationState
    ) -> RuntimeStatusReachabilityPolicy.Severity {
        if let operation = operationState.operationForPresentation,
           RuntimeActiveOperationPolicy.isInstallOperation(operation) ||
            RuntimeActiveOperationPolicy.isRecoveryInProgress(status, operation: operation) ||
            RuntimeActiveOperationPolicy.isUpdateInProgress(status, operation: operation) {
            return .warning
        }
        if RuntimeActiveOperationPolicy.isInitializationInProgress(status) {
            return .warning
        }
        if !status.runtimeInstallationState.isExecutable {
            return .critical
        }
        return reachabilityPolicy.httpSeverity(status.publicProxyHTTP)
    }
}
