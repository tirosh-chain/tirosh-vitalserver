import Foundation
import Contracts
import RuntimeControl
import Errors

public protocol RuntimeStatusHealthDetailsVocabulary: RuntimeStatusVMStateVocabulary,
    RuntimeStatusHTTPValueVocabulary,
    RuntimeStatusServiceValueVocabulary,
    RuntimeStatusComposeServiceValueVocabulary {
    var runtimeInstallationLabel: String { get }
    var vmStateLabel: String { get }
    var vmErrorsLabel: String { get }
    var failureReasonsLabel: String { get }
    var statusReadIssuesLabel: String { get }
    var vmIPAddressLabel: String { get }
    var vitalServerName: String { get }
    var hostProxyName: String { get }
    var redisName: String { get }
    var vitalDBObserverLabel: String { get }
    var watchdogLabel: String { get }
    var waitingText: String { get }

    func installStateText(_ state: RuntimeFileState) -> String
    func vmErrorText(_ error: RuntimeVMError) -> String
    func domainErrorText(_ reason: RuntimeFailureReason) -> String
}

public struct RuntimeStatusHealthDetailValue: Equatable, Sendable {
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

public struct RuntimeStatusHealthDetailItem: Equatable, Sendable {
    public let label: String
    public let value: RuntimeStatusHealthDetailValue

    public init(label: String, value: RuntimeStatusHealthDetailValue) {
        self.label = label
        self.value = value
    }
}

public struct RuntimeStatusHealthDetailsPolicy {
    private enum ComposeService: String {
        case vitalServer = "app"
        case networkAccess = "edge"
        case redis = "redis"
        case vitalDBObserver = "vitaldb-observer"
    }

    private let reachabilityPolicy = RuntimeStatusReachabilityPolicy()
    private let reachabilityLabelPolicy: RuntimeStatusReachabilityLabelPolicy
    private let vmStatePolicy: RuntimeStatusVMStatePolicy
    private let serviceValuePolicy: RuntimeStatusServiceValuePolicy
    private let httpValuePolicy: RuntimeStatusHTTPValuePolicy
    private let composeServiceValuePolicy: RuntimeStatusComposeServiceValuePolicy
    private let vocabulary: any RuntimeStatusHealthDetailsVocabulary

    public init(vocabulary: any RuntimeStatusHealthDetailsVocabulary) {
        self.vocabulary = vocabulary
        self.reachabilityLabelPolicy = RuntimeStatusReachabilityLabelPolicy(vocabulary: vocabulary)
        self.vmStatePolicy = RuntimeStatusVMStatePolicy(vocabulary: vocabulary)
        self.serviceValuePolicy = RuntimeStatusServiceValuePolicy(vocabulary: vocabulary)
        self.httpValuePolicy = RuntimeStatusHTTPValuePolicy(vocabulary: vocabulary)
        self.composeServiceValuePolicy = RuntimeStatusComposeServiceValuePolicy(vocabulary: vocabulary)
    }

    public func healthDetails(
        status: RuntimeStatus,
        observation: RuntimeContainerObservation?,
        now: Date
    ) -> [RuntimeStatusHealthDetailItem] {
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
        ]
        if let vmErrors = status.vmErrors, !vmErrors.isEmpty {
            items.append(RuntimeStatusHealthDetailItem(
                label: vocabulary.vmErrorsLabel,
                value: value(
                    vmErrors.map(vocabulary.vmErrorText).joined(separator: ", "),
                    .critical
                )
            ))
        }
        if !status.failureReasons.isEmpty {
            items.append(RuntimeStatusHealthDetailItem(
                label: vocabulary.failureReasonsLabel,
                value: value(
                    status.failureReasons.map(vocabulary.domainErrorText).joined(separator: ", "),
                    status.failureReasons.contains { $0.domainSeverity == .critical } ? .critical : .warning
                )
            ))
        }
        if !status.readIssues.isEmpty {
            items.append(RuntimeStatusHealthDetailItem(
                label: vocabulary.statusReadIssuesLabel,
                value: value(
                    status.readIssues.map { "\($0.source): \($0.message)" }.joined(separator: ", "),
                    .warning
                )
            ))
        }
        items.append(contentsOf: [
            RuntimeStatusHealthDetailItem(
                label: vocabulary.vmIPAddressLabel,
                value: value(
                    status.vmIP ?? vocabulary.waitingText,
                    status.vmServiceState == .loaded && status.vmIP != nil ? .healthy : .warning
                )
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.vitalServerName,
                value: value(httpValuePolicy.httpValue(
                    status.guestHTTP,
                    uptimeText: uptimeText(for: .vitalServer, observation: observation, now: now)
                ))
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.hostProxyName,
                value: RuntimeStatusHealthDetailValue(
                    text: reachabilityLabelPolicy.serviceReachabilityLabel(status.hostProxyHTTP),
                    severity: status.proxyServiceState == .loaded && reachabilityPolicy.isSuccessfulHTTPStatus(status.hostProxyHTTP)
                        ? .healthy
                        : .warning,
                    uptimeText: uptimeText(for: .networkAccess, observation: observation, now: now)
                )
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.redisName,
                value: value(composeValue(for: .redis, observation: observation, now: now))
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.vitalDBObserverLabel,
                value: value(composeValue(for: .vitalDBObserver, observation: observation, now: now))
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.watchdogLabel,
                value: value(serviceValuePolicy.serviceValue(
                    state: status.watchdogServiceState
                ))
            ),
        ])
        return items
    }

    private func uptimeText(
        for service: ComposeService,
        observation: RuntimeContainerObservation?,
        now: Date
    ) -> String? {
        composeServiceValuePolicy.uptimeText(service: service.rawValue, observation: observation, now: now)
    }

    private func composeValue(
        for service: ComposeService,
        observation: RuntimeContainerObservation?,
        now: Date
    ) -> RuntimeStatusComposeServiceValue {
        composeServiceValuePolicy.serviceValue(
            service: service.rawValue,
            observation: observation,
            now: now
        )
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

    private func value(_ value: RuntimeStatusHTTPValue) -> RuntimeStatusHealthDetailValue {
        RuntimeStatusHealthDetailValue(
            text: value.text,
            severity: value.severity,
            uptimeText: value.uptimeText
        )
    }

    private func value(_ value: RuntimeStatusComposeServiceValue) -> RuntimeStatusHealthDetailValue {
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
