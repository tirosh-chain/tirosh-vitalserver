import Foundation
import Contracts
import Errors

public protocol RuntimeStatusComposeServiceValueVocabulary {
    var notReportedText: String { get }

    func containerHealthText(_ health: String) -> String
    func containerStateText(_ state: String) -> String
}

public struct RuntimeStatusComposeServiceValue: Equatable, Sendable {
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

public struct RuntimeStatusComposeServiceValuePolicy {
    private let uptimeFormatter = RuntimeStatusUptimeFormatter()
    private let vocabulary: any RuntimeStatusComposeServiceValueVocabulary

    public init(vocabulary: any RuntimeStatusComposeServiceValueVocabulary) {
        self.vocabulary = vocabulary
    }

    public func serviceValue(
        service: String,
        observation: RuntimeContainerObservation?,
        now: Date
    ) -> RuntimeStatusComposeServiceValue {
        serviceValue(
            serviceObservation: serviceObservation(service: service, observation: observation),
            observedAt: observation?.runtimeStateUpdatedAt ?? observation?.runtimeStateFileUpdatedAt,
            now: now
        )
    }

    public func serviceValue(
        serviceObservation: RuntimeContainerServiceObservation?,
        observedAt: String?,
        now: Date
    ) -> RuntimeStatusComposeServiceValue {
        RuntimeStatusComposeServiceValue(
            text: statusText(serviceObservation),
            severity: severity(serviceObservation),
            uptimeText: uptimeFormatter.formatUptime(
                seconds: serviceObservation?.uptimeSeconds,
                startedAt: serviceObservation?.startedAt,
                observedAt: observedAt,
                now: now
            )
        )
    }

    public func uptimeText(
        service: String,
        observation: RuntimeContainerObservation?,
        now: Date
    ) -> String? {
        let serviceObservation = serviceObservation(service: service, observation: observation)
        return uptimeFormatter.formatUptime(
            seconds: serviceObservation?.uptimeSeconds,
            startedAt: serviceObservation?.startedAt,
            observedAt: observation?.runtimeStateUpdatedAt ?? observation?.runtimeStateFileUpdatedAt,
            now: now
        )
    }

    public func serviceObservation(
        service: String,
        observation: RuntimeContainerObservation?
    ) -> RuntimeContainerServiceObservation? {
        observation?.composeServices.first { $0.service == service }
    }

    private func statusText(_ observation: RuntimeContainerServiceObservation?) -> String {
        if let health = observation?.health, !health.isEmpty {
            return vocabulary.containerHealthText(health)
        }
        if let state = observation?.state, !state.isEmpty {
            return vocabulary.containerStateText(state)
        }
        return vocabulary.notReportedText
    }

    private func severity(_ observation: RuntimeContainerServiceObservation?) -> RuntimeStatusReachabilityPolicy.Severity {
        guard let observation else {
            return .neutral
        }
        if observation.health == "healthy" {
            return .healthy
        }
        return .warning
    }
}
