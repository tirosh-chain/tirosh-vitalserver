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
    RuntimeStatusContainerStateVocabulary {
    var proxyServiceLabel: String { get }
    var guestLogSyncServiceLabel: String { get }
    var sleepPreventionServiceLabel: String { get }
    var watchdogServiceLabel: String { get }
    var vitalServerName: String { get }
    var recorderIngressName: String { get }
    var recorderRecoveryName: String { get }
    var hostProxyName: String { get }
    var vitalDBObserverLabel: String { get }
    var redisRelayLabel: String { get }
    var guestProductServicesLabel: String { get }
    var redisUIName: String { get }
    var swaggerUIName: String { get }
    var disabledText: String { get }
    var waitingText: String { get }
    var guestStateStaleText: String { get }
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
        case redisRelay = "redis-relay"
    }

    private struct OperationPresentationState {
        let installInProgress: Bool
        let initializationInProgress: Bool
        let recoveryInProgress: Bool
        let updateInProgress: Bool
    }

    private let serviceValuePolicy: RuntimeStatusServiceValuePolicy
    private let httpValuePolicy: RuntimeStatusHTTPValuePolicy
    private let guestReadinessPolicy = RuntimeStatusGuestReadinessPresentationPolicy()
    private let vocabulary: any RuntimeStatusAdvancedServiceHealthVocabulary

    public init(vocabulary: any RuntimeStatusAdvancedServiceHealthVocabulary) {
        self.vocabulary = vocabulary
        self.serviceValuePolicy = RuntimeStatusServiceValuePolicy(vocabulary: vocabulary)
        self.httpValuePolicy = RuntimeStatusHTTPValuePolicy(vocabulary: vocabulary)
    }

    public func serviceHealth(
        status: RuntimeStatus,
        operationState: RuntimeOperationState,
        redisRelaySettings: RuntimeRedisRelaySettings = RuntimeRedisRelaySettings(),
        now: Date
    ) -> [RuntimeStatusAdvancedServiceHealthItem] {
        let operation = operationState.operationForPresentation
        return serviceHealth(
            status: status,
            redisRelaySettings: redisRelaySettings,
            operationState: OperationPresentationState(
                installInProgress: RuntimeActiveOperationPolicy.isInstallOperation(operation),
                initializationInProgress: RuntimeActiveOperationPolicy.isInitializationInProgress(status),
                recoveryInProgress: RuntimeActiveOperationPolicy.isRecoveryInProgress(status, operation: operation),
                updateInProgress: RuntimeActiveOperationPolicy.isUpdateInProgress(status, operation: operation)
            ),
            runtimeOperationState: operationState,
            now: now
        )
    }

    private func serviceHealth(
        status: RuntimeStatus,
        redisRelaySettings: RuntimeRedisRelaySettings,
        operationState: OperationPresentationState,
        runtimeOperationState: RuntimeOperationState,
        now _: Date
    ) -> [RuntimeStatusAdvancedServiceHealthItem] {
        var items = [
            serviceStateItem(
                vocabulary.proxyServiceLabel,
                state: status.proxyServiceState,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            serviceStateItem(
                vocabulary.guestLogSyncServiceLabel,
                state: status.guestLogSyncServiceState,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            serviceStateItem(
                vocabulary.sleepPreventionServiceLabel,
                state: status.sleepPreventionServiceState,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            serviceStateItem(
                vocabulary.watchdogServiceLabel,
                state: status.watchdogServiceState,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            redisRelayItem(
                status: status,
                settings: redisRelaySettings,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            vitalServerItem(
                status: status,
                runtimeOperationState: runtimeOperationState,
                vocabulary.vitalServerName,
                uptimeText: nil,
                action: .openVitalServer,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            httpServiceItem(
                vocabulary.hostProxyName,
                httpStatus: status.hostProxyHTTP,
                uptimeText: nil,
                action: .openVitalServer,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            httpServiceItem(
                vocabulary.redisUIName,
                httpStatus: status.redisUIHTTP,
                uptimeText: nil,
                action: .openRedisUI,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            httpServiceItem(
                vocabulary.swaggerUIName,
                httpStatus: status.swaggerUIHTTP,
                uptimeText: nil,
                action: .openSwagger,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
        ]
        items.insert(contentsOf: guestServiceItems(
            status: status,
            installInProgress: operationState.installInProgress,
            initializationInProgress: operationState.initializationInProgress,
            recoveryInProgress: operationState.recoveryInProgress,
            updateInProgress: operationState.updateInProgress
        ), at: 4)
        return items
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

    private func guestServiceItems(
        status: RuntimeStatus,
        installInProgress: Bool,
        initializationInProgress: Bool,
        recoveryInProgress: Bool,
        updateInProgress: Bool
    ) -> [RuntimeStatusAdvancedServiceHealthItem] {
        switch status.guestServicesReadState ?? .unavailable {
        case .unavailable:
            return [
                serviceStateItem(
                    vocabulary.guestProductServicesLabel,
                    value: operationValue(
                        installInProgress: installInProgress,
                        initializationInProgress: initializationInProgress,
                        recoveryInProgress: recoveryInProgress,
                        updateInProgress: updateInProgress
                    ) ?? RuntimeStatusAdvancedServiceHealthValue(
                        text: vocabulary.unavailableText,
                        severity: .warning,
                        uptimeText: nil
                    )
                ),
            ]
        case .failed:
            return [
                serviceStateItem(
                    vocabulary.guestProductServicesLabel,
                    value: operationValue(
                        installInProgress: installInProgress,
                        initializationInProgress: initializationInProgress,
                        recoveryInProgress: recoveryInProgress,
                        updateInProgress: updateInProgress
                    ) ?? RuntimeStatusAdvancedServiceHealthValue(
                        text: status.guestServicesReadError ?? vocabulary.failedText,
                        severity: .warning,
                        uptimeText: nil
                    )
                ),
            ]
        case .loaded:
            return orderedGuestServiceStatuses(status).map { serviceStatus in
                guard serviceStatus.service != ComposeService.redisRelay.rawValue else {
                    return nil
                }
                return RuntimeStatusAdvancedServiceHealthItem(
                    label: guestServiceLabel(serviceStatus.service),
                    value: guestServiceValue(serviceStatus),
                    httpStatus: nil,
                    action: nil
                )
            }.compactMap { $0 }
        }
    }

    private func orderedGuestServiceStatuses(
        _ status: RuntimeStatus
    ) -> [RuntimeGuestControlServiceStatus] {
        var statusesByService: [String: RuntimeGuestControlServiceStatus] = [:]
        for serviceStatus in status.guestServiceStatuses where statusesByService[serviceStatus.service] == nil {
            statusesByService[serviceStatus.service] = serviceStatus
        }
        let orderedServices = status.guestServices ?? []
        var orderedStatuses = orderedServices.compactMap { statusesByService[$0] }
        let orderedServiceSet = Set(orderedServices)
        orderedStatuses.append(contentsOf: status.guestServiceStatuses
            .filter { !orderedServiceSet.contains($0.service) }
            .sorted { $0.service < $1.service })
        return orderedStatuses
    }

    private func guestServiceLabel(_ service: String) -> String {
        "\(vocabulary.guestProductServicesLabel): \(service)"
    }

    private func guestServiceValue(
        _ serviceStatus: RuntimeGuestControlServiceStatus
    ) -> RuntimeStatusAdvancedServiceHealthValue {
        RuntimeStatusAdvancedServiceHealthValue(
            text: guestServiceText(serviceStatus),
            severity: guestServiceSeverity(serviceStatus),
            uptimeText: nil
        )
    }

    private func guestServiceText(_ serviceStatus: RuntimeGuestControlServiceStatus) -> String {
        if !serviceStatus.health.isEmpty, serviceStatus.health != "unknown" {
            return vocabulary.containerHealthText(serviceStatus.health)
        }
        if !serviceStatus.state.isEmpty {
            return vocabulary.containerStateText(serviceStatus.state)
        }
        return vocabulary.notReportedText
    }

    private func guestServiceSeverity(
        _ serviceStatus: RuntimeGuestControlServiceStatus
    ) -> RuntimeStatusReachabilityPolicy.Severity {
        switch serviceStatus.health.lowercased() {
        case "healthy":
            return .healthy
        case "unhealthy":
            return .warning
        default:
            switch serviceStatus.state.lowercased() {
            case "running":
                return .healthy
            case "exited", "dead", "failed":
                return .warning
            default:
                return .neutral
            }
        }
    }

    private func serviceStateItem(
        _ label: String,
        state: RuntimeServiceState?,
        installInProgress: Bool,
        initializationInProgress: Bool,
        recoveryInProgress: Bool,
        updateInProgress: Bool
    ) -> RuntimeStatusAdvancedServiceHealthItem {
        RuntimeStatusAdvancedServiceHealthItem(
            label: label,
            value: value(serviceValuePolicy.serviceValue(
                state: state,
                installInProgress: installInProgress,
                initializationInProgress: initializationInProgress,
                recoveryInProgress: recoveryInProgress,
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
        installInProgress: Bool,
        initializationInProgress: Bool,
        recoveryInProgress: Bool,
        updateInProgress: Bool
    ) -> RuntimeStatusAdvancedServiceHealthItem {
        RuntimeStatusAdvancedServiceHealthItem(
            label: label,
            value: value(httpValuePolicy.serviceValue(
                httpStatus: httpStatus,
                uptimeText: uptimeText,
                installInProgress: installInProgress,
                initializationInProgress: initializationInProgress,
                recoveryInProgress: recoveryInProgress,
                updateInProgress: updateInProgress
            )),
            httpStatus: httpStatus,
            action: action
        )
    }

    private func vitalServerItem(
        status: RuntimeStatus,
        runtimeOperationState: RuntimeOperationState,
        _ label: String,
        uptimeText: String?,
        action: RuntimeStatusServiceActionID,
        installInProgress: Bool,
        initializationInProgress: Bool,
        recoveryInProgress: Bool,
        updateInProgress: Bool
    ) -> RuntimeStatusAdvancedServiceHealthItem {
        let computedValue = httpValuePolicy.serviceValue(
            httpStatus: status.guestHTTP,
            uptimeText: uptimeText,
            installInProgress: installInProgress,
            initializationInProgress: initializationInProgress,
            recoveryInProgress: recoveryInProgress,
            updateInProgress: updateInProgress
        )
        let guestHTTPValue = guestReadinessPolicy.guestHTTPValue(
            status: status,
            operationState: runtimeOperationState,
            computedValue: computedValue,
            waitingText: vocabulary.waitingText,
            staleText: vocabulary.guestStateStaleText
        )
        return RuntimeStatusAdvancedServiceHealthItem(
            label: label,
            value: value(guestHTTPValue),
            httpStatus: status.guestHTTP,
            action: action
        )
    }

    private func redisRelayItem(
        status: RuntimeStatus,
        settings: RuntimeRedisRelaySettings,
        installInProgress: Bool,
        initializationInProgress: Bool,
        recoveryInProgress: Bool,
        updateInProgress: Bool
    ) -> RuntimeStatusAdvancedServiceHealthItem {
        guard settings.enabled else {
            return RuntimeStatusAdvancedServiceHealthItem(
                label: vocabulary.redisRelayLabel,
                value: RuntimeStatusAdvancedServiceHealthValue(
                    text: vocabulary.disabledText,
                    severity: .neutral,
                    uptimeText: nil
                ),
                httpStatus: nil,
                action: nil
            )
        }

        let serviceValue = operationValue(
            installInProgress: installInProgress,
            initializationInProgress: initializationInProgress,
            recoveryInProgress: recoveryInProgress,
            updateInProgress: updateInProgress
        ) ?? redisRelayValue(status: status)

        return RuntimeStatusAdvancedServiceHealthItem(
            label: vocabulary.redisRelayLabel,
            value: serviceValue,
            httpStatus: status.redisRelayStatus?.lastError,
            action: nil
        )
    }

    private func redisRelayValue(
        status: RuntimeStatus
    ) -> RuntimeStatusAdvancedServiceHealthValue {
        if let guestStatus = guestServiceStatus(ComposeService.redisRelay.rawValue, in: status) {
            return guestServiceValue(guestStatus)
        }

        if let relayStatus = status.redisRelayStatus,
           isRedisRelayFailureState(relayStatus.state) || relayStatus.lastError != nil {
            return RuntimeStatusAdvancedServiceHealthValue(
                text: vocabulary.failedText,
                severity: .warning,
                uptimeText: nil
            )
        }

        if let relayStatus = status.redisRelayStatus, !relayStatus.state.isEmpty {
            return RuntimeStatusAdvancedServiceHealthValue(
                text: vocabulary.containerStateText(relayStatus.state),
                severity: redisRelaySeverity(state: relayStatus.state),
                uptimeText: nil
            )
        }

        return RuntimeStatusAdvancedServiceHealthValue(
            text: vocabulary.notReportedText,
            severity: .warning,
            uptimeText: nil
        )
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

    private func operationValue(
        installInProgress: Bool,
        initializationInProgress: Bool,
        recoveryInProgress: Bool,
        updateInProgress: Bool
    ) -> RuntimeStatusAdvancedServiceHealthValue? {
        if installInProgress {
            return value(httpValuePolicy.installingValue(uptimeText: nil))
        }
        if initializationInProgress {
            return value(httpValuePolicy.initializingValue(uptimeText: nil))
        }
        if recoveryInProgress {
            return value(httpValuePolicy.recoveringValue(uptimeText: nil))
        }
        if updateInProgress {
            return value(httpValuePolicy.updatingValue(uptimeText: nil))
        }
        return nil
    }

    private func isRedisRelayFailureState(_ state: String) -> Bool {
        let normalized = state.lowercased()
        return normalized == "failed" || normalized == "error"
    }

    private func redisRelaySeverity(state: String) -> RuntimeStatusReachabilityPolicy.Severity {
        switch state.lowercased() {
        case "running", "healthy":
            return .healthy
        case "disabled", "stopped":
            return .neutral
        default:
            return .warning
        }
    }

    private func guestServiceStatus(
        _ service: String,
        in status: RuntimeStatus
    ) -> RuntimeGuestControlServiceStatus? {
        guard (status.guestServicesReadState ?? .unavailable) == .loaded else {
            return nil
        }
        return status.guestServiceStatuses.first { $0.service == service }
    }
}
