import Foundation
import Contracts
import RuntimeControl
import Errors

public enum RuntimeStatusServiceActionID: Equatable, Sendable {
    case openVitalServer
    case openRedisUI
    case openSwagger
}

public protocol RuntimeStatusAdvancedServiceHealthVocabulary: RuntimeStatusHTTPValueVocabulary,
    RuntimeStatusServiceValueVocabulary,
    RuntimeStatusComposeServiceValueVocabulary {
    var proxyServiceLabel: String { get }
    var guestLogSyncServiceLabel: String { get }
    var sleepPreventionServiceLabel: String { get }
    var watchdogServiceLabel: String { get }
    var vitalServerName: String { get }
    var hostProxyName: String { get }
    var vitalDBObserverLabel: String { get }
    var redisUIName: String { get }
    var swaggerUIName: String { get }
}

public struct RuntimeStatusAdvancedServiceHealthValue: Equatable, Sendable {
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

public struct RuntimeStatusAdvancedServiceHealthItem: Equatable, Sendable {
    public let label: String
    public let value: RuntimeStatusAdvancedServiceHealthValue
    public let httpStatus: String?
    public let action: RuntimeStatusServiceActionID?

    public init(
        label: String,
        value: RuntimeStatusAdvancedServiceHealthValue,
        httpStatus: String?,
        action: RuntimeStatusServiceActionID?
    ) {
        self.label = label
        self.value = value
        self.httpStatus = httpStatus
        self.action = action
    }
}

public struct RuntimeStatusAdvancedServiceHealthPolicy {
    private enum ComposeService: String {
        case vitalServer = "app"
        case networkAccess = "edge"
        case vitalDBObserver = "vitaldb-observer"
        case redisUI = "redis-ui"
        case swaggerUI = "swagger-ui"
    }

    private let serviceValuePolicy: RuntimeStatusServiceValuePolicy
    private let httpValuePolicy: RuntimeStatusHTTPValuePolicy
    private let composeServiceValuePolicy: RuntimeStatusComposeServiceValuePolicy
    private let vocabulary: any RuntimeStatusAdvancedServiceHealthVocabulary

    public init(vocabulary: any RuntimeStatusAdvancedServiceHealthVocabulary) {
        self.vocabulary = vocabulary
        self.serviceValuePolicy = RuntimeStatusServiceValuePolicy(vocabulary: vocabulary)
        self.httpValuePolicy = RuntimeStatusHTTPValuePolicy(vocabulary: vocabulary)
        self.composeServiceValuePolicy = RuntimeStatusComposeServiceValuePolicy(vocabulary: vocabulary)
    }

    public func serviceHealth(
        status: RuntimeStatus,
        observation: RuntimeContainerObservation?,
        now: Date
    ) -> [RuntimeStatusAdvancedServiceHealthItem] {
        let updateInProgress = RuntimeActiveOperationPolicy.isUpdateInProgress(status)
        return [
            serviceStateItem(
                vocabulary.proxyServiceLabel,
                state: status.proxyServiceState,
                fallbackLoaded: status.proxyServiceLoaded,
                updateInProgress: updateInProgress
            ),
            serviceStateItem(
                vocabulary.guestLogSyncServiceLabel,
                state: status.guestLogSyncServiceState,
                fallbackLoaded: status.guestLogSyncServiceLoaded,
                updateInProgress: updateInProgress
            ),
            serviceStateItem(
                vocabulary.sleepPreventionServiceLabel,
                state: status.sleepPreventionServiceState,
                fallbackLoaded: status.sleepPreventionServiceLoaded,
                updateInProgress: updateInProgress
            ),
            serviceStateItem(
                vocabulary.watchdogServiceLabel,
                state: status.watchdogServiceState,
                fallbackLoaded: status.watchdogServiceLoaded,
                updateInProgress: updateInProgress
            ),
            httpServiceItem(
                vocabulary.vitalServerName,
                httpStatus: status.guestHTTP,
                uptimeText: uptimeText(for: .vitalServer, observation: observation, now: now),
                action: .openVitalServer,
                updateInProgress: updateInProgress
            ),
            httpServiceItem(
                vocabulary.hostProxyName,
                httpStatus: status.hostProxyHTTP,
                uptimeText: uptimeText(for: .networkAccess, observation: observation, now: now),
                action: .openVitalServer,
                updateInProgress: updateInProgress
            ),
            composeServiceItem(
                vocabulary.vitalDBObserverLabel,
                service: .vitalDBObserver,
                observation: observation,
                now: now,
                updateInProgress: updateInProgress
            ),
            httpServiceItem(
                vocabulary.redisUIName,
                httpStatus: status.redisUIHTTP,
                uptimeText: uptimeText(for: .redisUI, observation: observation, now: now),
                action: .openRedisUI,
                updateInProgress: updateInProgress
            ),
            httpServiceItem(
                vocabulary.swaggerUIName,
                httpStatus: status.swaggerUIHTTP,
                uptimeText: uptimeText(for: .swaggerUI, observation: observation, now: now),
                action: .openSwagger,
                updateInProgress: updateInProgress
            ),
        ]
    }

    private func serviceStateItem(
        _ label: String,
        value: RuntimeStatusAdvancedServiceHealthValue
    ) -> RuntimeStatusAdvancedServiceHealthItem {
        RuntimeStatusAdvancedServiceHealthItem(
            label: label,
            value: value,
            httpStatus: nil,
            action: nil
        )
    }

    private func serviceStateItem(
        _ label: String,
        state: RuntimeServiceState?,
        fallbackLoaded: Bool?,
        updateInProgress: Bool
    ) -> RuntimeStatusAdvancedServiceHealthItem {
        RuntimeStatusAdvancedServiceHealthItem(
            label: label,
            value: value(serviceValuePolicy.serviceValue(
                state: state,
                fallbackLoaded: fallbackLoaded,
                updateInProgress: updateInProgress
            )),
            httpStatus: nil,
            action: nil
        )
    }

    private func httpServiceItem(
        _ label: String,
        httpStatus: String?,
        uptimeText: String?,
        action: RuntimeStatusServiceActionID,
        updateInProgress: Bool
    ) -> RuntimeStatusAdvancedServiceHealthItem {
        RuntimeStatusAdvancedServiceHealthItem(
            label: label,
            value: value(httpValuePolicy.serviceValue(
                httpStatus: httpStatus,
                uptimeText: uptimeText,
                updateInProgress: updateInProgress
            )),
            httpStatus: httpStatus,
            action: action
        )
    }

    private func composeServiceItem(
        _ label: String,
        service: ComposeService,
        observation: RuntimeContainerObservation?,
        now: Date,
        updateInProgress: Bool
    ) -> RuntimeStatusAdvancedServiceHealthItem {
        RuntimeStatusAdvancedServiceHealthItem(
            label: label,
            value: updateInProgress
                ? value(httpValuePolicy.updatingValue(uptimeText: nil))
                : value(composeServiceValuePolicy.serviceValue(
                    service: service.rawValue,
                    observation: observation,
                    now: now
                )),
            httpStatus: nil,
            action: nil
        )
    }

    private func uptimeText(
        for service: ComposeService,
        observation: RuntimeContainerObservation?,
        now: Date
    ) -> String? {
        composeServiceValuePolicy.uptimeText(service: service.rawValue, observation: observation, now: now)
    }

    private func value(_ value: RuntimeStatusServiceValue) -> RuntimeStatusAdvancedServiceHealthValue {
        RuntimeStatusAdvancedServiceHealthValue(
            text: value.text,
            severity: value.severity,
            uptimeText: value.uptimeText
        )
    }

    private func value(_ value: RuntimeStatusHTTPValue) -> RuntimeStatusAdvancedServiceHealthValue {
        RuntimeStatusAdvancedServiceHealthValue(
            text: value.text,
            severity: value.severity,
            uptimeText: value.uptimeText
        )
    }

    private func value(_ value: RuntimeStatusComposeServiceValue) -> RuntimeStatusAdvancedServiceHealthValue {
        RuntimeStatusAdvancedServiceHealthValue(
            text: value.text,
            severity: value.severity,
            uptimeText: value.uptimeText
        )
    }
}
