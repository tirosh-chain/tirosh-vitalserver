import Foundation
import Contracts
import RuntimeControl

public protocol RuntimeStatusVitalServerAvailabilityVocabulary: RuntimeStatusReachabilityLabelVocabulary {
    var updatingText: String { get }
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
    private let appComposeService = "app"
    private let reachabilityPolicy = RuntimeStatusReachabilityPolicy()
    private let labelPolicy: RuntimeStatusReachabilityLabelPolicy
    private let composeServiceValuePolicy: RuntimeStatusComposeServiceValuePolicy
    private let vocabulary: any RuntimeStatusVitalServerAvailabilityVocabulary

    public init(vocabulary: any RuntimeStatusVitalServerAvailabilityVocabulary) {
        self.vocabulary = vocabulary
        self.labelPolicy = RuntimeStatusReachabilityLabelPolicy(vocabulary: vocabulary)
        self.composeServiceValuePolicy = RuntimeStatusComposeServiceValuePolicy(
            vocabulary: RuntimeStatusVitalServerAvailabilityComposeVocabulary()
        )
    }

    public func availability(
        status: RuntimeStatus,
        observation: RuntimeContainerObservation?,
        now: Date
    ) -> RuntimeStatusVitalServerAvailabilityValue {
        let text: String
        if RuntimeActiveOperationPolicy.isUpdateInProgress(status) {
            text = vocabulary.updatingText
        } else if !status.runtimeInstalled {
            text = vocabulary.unavailableText
        } else {
            text = labelPolicy.serviceReachabilityLabel(status.hostProxyHTTP)
        }
        return RuntimeStatusVitalServerAvailabilityValue(
            text: text,
            severity: RuntimeActiveOperationPolicy.isUpdateInProgress(status)
                ? .warning
                : reachabilityPolicy.httpSeverity(status.hostProxyHTTP),
            uptimeText: composeServiceValuePolicy.uptimeText(
                service: appComposeService,
                observation: observation,
                now: now
            )
        )
    }
}

private struct RuntimeStatusVitalServerAvailabilityComposeVocabulary: RuntimeStatusComposeServiceValueVocabulary {
    var notReportedText: String { "" }

    func containerHealthText(_ health: String) -> String {
        health
    }

    func containerStateText(_ state: String) -> String {
        state
    }
}
