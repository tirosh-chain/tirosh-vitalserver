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
        status: PlatformState,
        operationState: PlatformOperationState,
        runtimeStackStatus: RuntimeGuestControlStackStatus?,
        runtimeStackReadError: String?,
        runtimeServiceResources: [RuntimeGuestServiceResource],
        runtimeServiceResourceReadIssues: [RuntimeGuestServiceResourceReadIssue],
        redisRelaySettings: RuntimeRedisRelaySettings = RuntimeRedisRelaySettings(),
        redisRelayStatusRead: RuntimeRedisRelayStatusReadResult,
        now: Date
    ) -> [RuntimeStatusAdvancedServiceHealthItem] {
        let operation = operationState.operationForPresentation
        return serviceHealth(
            status: status,
            runtimeStackStatus: runtimeStackStatus,
            runtimeStackReadError: runtimeStackReadError,
            runtimeServiceResources: runtimeServiceResources,
            runtimeServiceResourceReadIssues: runtimeServiceResourceReadIssues,
            redisRelaySettings: redisRelaySettings,
            redisRelayStatusRead: redisRelayStatusRead,
            operationState: OperationPresentationState(
                installInProgress: RuntimeActiveOperationPolicy.isInstallOperation(operation),
                initializationInProgress: RuntimeActiveOperationPolicy.isInitializationInProgress(status),
                recoveryInProgress: RuntimeActiveOperationPolicy.isRecoveryInProgress(status, operation: operation),
                updateInProgress: RuntimeActiveOperationPolicy.isUpdateInProgress(status, operation: operation)
            ),
            platformOperationState: operationState,
            now: now
        )
    }

    private func serviceHealth(
        status: PlatformState,
        runtimeStackStatus: RuntimeGuestControlStackStatus?,
        runtimeStackReadError: String?,
        runtimeServiceResources: [RuntimeGuestServiceResource],
        runtimeServiceResourceReadIssues: [RuntimeGuestServiceResourceReadIssue],
        redisRelaySettings: RuntimeRedisRelaySettings,
        redisRelayStatusRead: RuntimeRedisRelayStatusReadResult,
        operationState: OperationPresentationState,
        platformOperationState: PlatformOperationState,
        now _: Date
    ) -> [RuntimeStatusAdvancedServiceHealthItem] {
        var items = [
            serviceStateItem(
                vocabulary.proxyServiceLabel,
                state: status.serviceState(.publicProxy),
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            serviceStateItem(
                vocabulary.guestLogSyncServiceLabel,
                state: status.serviceState(.logSync),
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            serviceStateItem(
                vocabulary.sleepPreventionServiceLabel,
                state: status.serviceState(.sleepPrevention),
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            serviceStateItem(
                vocabulary.watchdogServiceLabel,
                state: status.serviceState(.watchdog),
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            redisRelayItem(
                status: status,
                settings: redisRelaySettings,
                statusRead: redisRelayStatusRead,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            vitalServerItem(
                status: status,
                platformOperationState: platformOperationState,
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
                httpStatus: status.publicProxyHTTP,
                uptimeText: nil,
                action: .openVitalServer,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            httpServiceItem(
                vocabulary.redisUIName,
                httpStatus: nil,
                uptimeText: nil,
                action: .openRedisUI,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
            httpServiceItem(
                vocabulary.swaggerUIName,
                httpStatus: nil,
                uptimeText: nil,
                action: .openSwagger,
                installInProgress: operationState.installInProgress,
                initializationInProgress: operationState.initializationInProgress,
                recoveryInProgress: operationState.recoveryInProgress,
                updateInProgress: operationState.updateInProgress
            ),
        ]
        items.insert(contentsOf: guestServiceItems(
            stackStatus: runtimeStackStatus,
            stackReadError: runtimeStackReadError,
            resources: runtimeServiceResources,
            resourceReadIssues: runtimeServiceResourceReadIssues,
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
        stackStatus: RuntimeGuestControlStackStatus?,
        stackReadError: String?,
        resources: [RuntimeGuestServiceResource],
        resourceReadIssues: [RuntimeGuestServiceResourceReadIssue],
        installInProgress: Bool,
        initializationInProgress: Bool,
        recoveryInProgress: Bool,
        updateInProgress: Bool
    ) -> [RuntimeStatusAdvancedServiceHealthItem] {
        if let stackReadError {
            return [
                serviceStateItem(
                    vocabulary.guestProductServicesLabel,
                    value: operationValue(
                        installInProgress: installInProgress,
                        initializationInProgress: initializationInProgress,
                        recoveryInProgress: recoveryInProgress,
                        updateInProgress: updateInProgress
                    ) ?? RuntimeStatusAdvancedServiceHealthValue(
                        text: stackReadError,
                        severity: .warning,
                        uptimeText: nil
                    )
                ),
            ]
        }
        guard let stackStatus else {
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
        }
        guard stackStatus.state == "loaded" else {
            return [
                serviceStateItem(
                    vocabulary.guestProductServicesLabel,
                    value: operationValue(
                        installInProgress: installInProgress,
                        initializationInProgress: initializationInProgress,
                        recoveryInProgress: recoveryInProgress,
                        updateInProgress: updateInProgress
                    ) ?? RuntimeStatusAdvancedServiceHealthValue(
                        text: "Runtime stack status is \(stackStatus.state)",
                        severity: .warning,
                        uptimeText: nil
                    )
                ),
            ]
        }
        var items: [RuntimeStatusAdvancedServiceHealthItem] = orderedGuestServiceStatuses(stackStatus).compactMap { serviceStatus in
                guard serviceStatus.service != ComposeService.redisRelay.rawValue else {
                    return nil
                }
                return RuntimeStatusAdvancedServiceHealthItem(
                    label: guestServiceLabel(serviceStatus.service),
                    value: guestServiceValue(
                        serviceStatus,
                        resources: resources,
                        resourceReadIssues: resourceReadIssues
                    ),
                    httpStatus: nil,
                    action: nil
                )
            }
        if let probeItem = guestStackProbeErrorItem(stackStatus) {
            items.append(probeItem)
        }
        return items
    }

    private func guestStackProbeErrorItem(_ stackStatus: RuntimeGuestControlStackStatus) -> RuntimeStatusAdvancedServiceHealthItem? {
        guard !stackStatus.probeErrors.isEmpty else {
            return nil
        }
        return RuntimeStatusAdvancedServiceHealthItem(
            label: "\(vocabulary.guestProductServicesLabel) probes",
            value: RuntimeStatusAdvancedServiceHealthValue(
                text: stackStatus.probeErrors
                    .map { "\($0.source): \($0.message)" }
                    .joined(separator: ", "),
                severity: .warning,
                uptimeText: nil
            ),
            httpStatus: nil,
            action: nil
        )
    }

    private func orderedGuestServiceStatuses(
        _ stackStatus: RuntimeGuestControlStackStatus
    ) -> [RuntimeGuestControlServiceStatus] {
        var statusesByService: [String: RuntimeGuestControlServiceStatus] = [:]
        for serviceStatus in stackStatus.services where statusesByService[serviceStatus.service] == nil {
            statusesByService[serviceStatus.service] = serviceStatus
        }
        let orderedServices = stackStatus.services.map(\.service)
        var orderedStatuses = orderedServices.compactMap { statusesByService[$0] }
        let orderedServiceSet = Set(orderedServices)
        orderedStatuses.append(contentsOf: stackStatus.services
            .filter { !orderedServiceSet.contains($0.service) }
            .sorted { $0.service < $1.service })
        return orderedStatuses
    }

    private func guestServiceLabel(_ service: String) -> String {
        "\(vocabulary.guestProductServicesLabel): \(service)"
    }

    private func guestServiceValue(
        _ serviceStatus: RuntimeGuestControlServiceStatus,
        resources: [RuntimeGuestServiceResource],
        resourceReadIssues: [RuntimeGuestServiceResourceReadIssue]
    ) -> RuntimeStatusAdvancedServiceHealthValue {
        let resource = resources.first { $0.service == serviceStatus.service }
        let readIssue = resourceReadIssues.first { $0.service == serviceStatus.service }
        return RuntimeStatusAdvancedServiceHealthValue(
            text: guestServiceText(serviceStatus, resource: resource, readIssue: readIssue),
            severity: guestServiceSeverity(serviceStatus, readIssue: readIssue),
            uptimeText: nil
        )
    }

    private func guestServiceText(
        _ serviceStatus: RuntimeGuestControlServiceStatus,
        resource: RuntimeGuestServiceResource?,
        readIssue: RuntimeGuestServiceResourceReadIssue?
    ) -> String {
        if let readIssue {
            return "Resource read failed: \(readIssue.message)"
        }
        var parts: [String] = []
        if !serviceStatus.health.isEmpty, serviceStatus.health != "unknown" {
            parts.append(vocabulary.containerHealthText(serviceStatus.health))
        } else if !serviceStatus.state.isEmpty {
            parts.append(vocabulary.containerStateText(serviceStatus.state))
        } else {
            parts.append(vocabulary.notReportedText)
        }
        if let resource {
            parts.append("spec \(resource.spec.state)")
            if let desiredState = resource.spec.desiredState {
                parts.append("desired \(desiredState)")
            }
            parts.append("status \(resource.status.state)")
            if let observedState = resource.status.observedState {
                parts.append("observed \(observedState)")
            }
            if let readError = resource.status.readError {
                parts.append("status read failed \(readError.kind): \(readError.message)")
            }
            let conditionText = resource.conditions
                .map { "\($0.type)=\($0.status) \($0.reason): \($0.message)" }
                .joined(separator: "; ")
            if !conditionText.isEmpty {
                parts.append("conditions \(conditionText)")
            }
            if let lastOperationId = resource.lastOperationId {
                parts.append("last operation \(lastOperationId)")
            }
        }
        return parts.joined(separator: " | ")
    }

    private func guestServiceSeverity(
        _ serviceStatus: RuntimeGuestControlServiceStatus,
        readIssue: RuntimeGuestServiceResourceReadIssue?
    ) -> RuntimeStatusReachabilityPolicy.Severity {
        if readIssue != nil {
            return .warning
        }
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
        status: PlatformState,
        platformOperationState: PlatformOperationState,
        _ label: String,
        uptimeText: String?,
        action: RuntimeStatusServiceActionID,
        installInProgress: Bool,
        initializationInProgress: Bool,
        recoveryInProgress: Bool,
        updateInProgress: Bool
    ) -> RuntimeStatusAdvancedServiceHealthItem {
        let computedValue = httpValuePolicy.serviceValue(
            httpStatus: status.runtimeControllerHTTP,
            uptimeText: uptimeText,
            installInProgress: installInProgress,
            initializationInProgress: initializationInProgress,
            recoveryInProgress: recoveryInProgress,
            updateInProgress: updateInProgress
        )
        let guestHTTPValue = guestReadinessPolicy.guestHTTPValue(
            status: status,
            operationState: platformOperationState,
            computedValue: computedValue,
            waitingText: vocabulary.waitingText,
            staleText: vocabulary.guestStateStaleText
        )
        return RuntimeStatusAdvancedServiceHealthItem(
            label: label,
            value: value(guestHTTPValue),
            httpStatus: status.runtimeControllerHTTP,
            action: action
        )
    }

    private func redisRelayItem(
        status: PlatformState,
        settings: RuntimeRedisRelaySettings,
        statusRead: RuntimeRedisRelayStatusReadResult,
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
        ) ?? redisRelayValue(statusRead: statusRead)

        return RuntimeStatusAdvancedServiceHealthItem(
            label: vocabulary.redisRelayLabel,
            value: serviceValue,
            httpStatus: statusRead.document?.lastError ?? statusRead.readError,
            action: nil
        )
    }

    private func redisRelayValue(
        statusRead: RuntimeRedisRelayStatusReadResult
    ) -> RuntimeStatusAdvancedServiceHealthValue {
        if let relayStatus = statusRead.document,
           isRedisRelayFailureState(relayStatus.state) || relayStatus.lastError != nil {
            return RuntimeStatusAdvancedServiceHealthValue(
                text: vocabulary.failedText,
                severity: .warning,
                uptimeText: nil
            )
        }

        if let relayStatus = statusRead.document, !relayStatus.state.isEmpty {
            return RuntimeStatusAdvancedServiceHealthValue(
                text: vocabulary.containerStateText(relayStatus.state),
                severity: redisRelaySeverity(state: relayStatus.state),
                uptimeText: nil
            )
        }

        switch statusRead.readState {
        case .invalidResponse, .readFailed:
            return RuntimeStatusAdvancedServiceHealthValue(
                text: vocabulary.failedText,
                severity: .warning,
                uptimeText: nil
            )
        case .notRead, .loaded:
            return RuntimeStatusAdvancedServiceHealthValue(
                text: vocabulary.notReportedText,
                severity: .warning,
                uptimeText: nil
            )
        }
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

}
