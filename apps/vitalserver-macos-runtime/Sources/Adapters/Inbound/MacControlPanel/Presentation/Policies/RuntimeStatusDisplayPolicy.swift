import Foundation
import Contracts
import RuntimeControl
import Errors

struct RuntimeStatusDisplayPolicy {
    enum Severity: Equatable {
        case healthy
        case warning
        case critical
        case neutral
    }

    enum ServiceAction: Equatable {
        case openVitalServer
        case openRedisUI
        case openSwagger
    }

    struct StatusValue: Equatable {
        let text: String
        let severity: Severity
        let uptimeText: String?
    }

    struct HealthItem: Equatable, Identifiable {
        var id: String { label }
        let label: String
        let value: StatusValue
    }

    struct ActionNeededItem: Equatable {
        let title: String
        let recommendedAction: String
        let severity: Severity
    }

    struct ServiceHealthItem: Equatable, Identifiable {
        var id: String { label }
        let label: String
        let value: StatusValue
        let httpStatus: String?
        let action: ServiceAction?
    }

    typealias RecorderSummary = RuntimeStatusRecorderSummary

    private let recorderSummaryPolicy = RuntimeStatusRecorderSummaryPolicy(
        vocabulary: AppRuntimeStatusRecorderSummaryVocabulary()
    )
    private let actionNeededPolicy = RuntimeStatusActionNeededPolicy(
        vocabulary: AppRuntimeStatusActionNeededVocabulary()
    )
    private let remoteConsoleAvailabilityPolicy = RuntimeStatusRemoteConsoleAvailabilityPolicy(
        vocabulary: AppRuntimeStatusRemoteConsoleAvailabilityVocabulary()
    )
    private let vmStatePolicy = RuntimeStatusVMStatePolicy(
        vocabulary: AppRuntimeStatusVMStateVocabulary()
    )
    private let overallHealthPolicy = RuntimeStatusOverallHealthPolicy(
        vocabulary: AppRuntimeStatusOverallHealthVocabulary()
    )
    private let advancedVMHealthPolicy = RuntimeStatusAdvancedVMHealthPolicy(
        vocabulary: AppRuntimeStatusAdvancedVMHealthVocabulary()
    )
    private let healthDetailsPolicy = RuntimeStatusHealthDetailsPolicy(
        vocabulary: AppRuntimeStatusHealthDetailsVocabulary()
    )
    private let advancedServiceHealthPolicy = RuntimeStatusAdvancedServiceHealthPolicy(
        vocabulary: AppRuntimeStatusAdvancedServiceHealthVocabulary()
    )
    private let vitalServerAvailabilityPolicy = RuntimeStatusVitalServerAvailabilityPolicy(
        vocabulary: AppRuntimeStatusVitalServerAvailabilityVocabulary()
    )

    func overallHealth(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> StatusValue {
        statusValue(overallHealthPolicy.overallHealth(status: status))
    }

    func vitalServerAvailability(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> StatusValue {
        statusValue(vitalServerAvailabilityPolicy.availability(status: status, observation: observation, now: now))
    }

    func remoteConsoleAvailability(status: RuntimeStatus, now: Date = Date()) -> StatusValue {
        statusValue(remoteConsoleAvailabilityPolicy.availability(status: status, now: now))
    }

    func remoteConsoleAvailability(http: String?, startedAt: String?, now: Date = Date()) -> StatusValue {
        statusValue(remoteConsoleAvailabilityPolicy.availability(http: http, startedAt: startedAt, now: now))
    }

    func actionNeeded(status: RuntimeStatus) -> ActionNeededItem? {
        actionNeededPolicy.actionNeeded(status: status).map(actionNeededItem)
    }

    func healthDetails(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> [HealthItem] {
        healthDetailsPolicy.healthDetails(status: status, observation: observation, now: now).map(healthItem)
    }

    func advancedVMHealth(status: RuntimeStatus) -> [HealthItem] {
        advancedVMHealthPolicy.vmHealth(status: status).map(healthItem)
    }

    func advancedServiceHealth(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> [ServiceHealthItem] {
        advancedServiceHealthPolicy.serviceHealth(status: status, observation: observation, now: now).map(serviceHealthItem)
    }

    func recorderSummary(
        observation: RuntimeContainerObservation?,
        vitalDBObservation: VitalDBObservationDocument?
    ) -> RecorderSummary {
        recorderSummaryPolicy.recorderSummary(
            observation: observation,
            vitalDBObservation: vitalDBObservation
        )
    }

    func vmStateValue(_ value: RuntimeVMState?) -> StatusValue {
        statusValue(vmStatePolicy.vmStateValue(value))
    }

    private func actionNeededItem(_ decision: RuntimeStatusActionNeededDecision) -> ActionNeededItem {
        ActionNeededItem(
            title: decision.title,
            recommendedAction: decision.recommendedAction,
            severity: displaySeverity(decision.severity)
        )
    }

    private func healthItem(_ item: RuntimeStatusHealthDetailItem) -> HealthItem {
        HealthItem(label: item.label, value: statusValue(item.value))
    }

    private func serviceHealthItem(_ item: RuntimeStatusAdvancedServiceHealthItem) -> ServiceHealthItem {
        ServiceHealthItem(
            label: item.label,
            value: statusValue(item.value),
            httpStatus: item.httpStatus,
            action: serviceAction(item.action)
        )
    }

    private func serviceAction(_ action: RuntimeStatusServiceActionID?) -> ServiceAction? {
        switch action {
        case .openVitalServer:
            return .openVitalServer
        case .openRedisUI:
            return .openRedisUI
        case .openSwagger:
            return .openSwagger
        case nil:
            return nil
        }
    }

    private func statusValue(_ value: RuntimeStatusAdvancedServiceHealthValue) -> StatusValue {
        StatusValue(
            text: value.text,
            severity: displaySeverity(value.severity),
            uptimeText: value.uptimeText
        )
    }

    private func statusValue(_ value: RuntimeStatusVitalServerAvailabilityValue) -> StatusValue {
        StatusValue(
            text: value.text,
            severity: displaySeverity(value.severity),
            uptimeText: value.uptimeText
        )
    }

    private func statusValue(_ value: RuntimeStatusHealthDetailValue) -> StatusValue {
        StatusValue(
            text: value.text,
            severity: displaySeverity(value.severity),
            uptimeText: value.uptimeText
        )
    }

    private func statusValue(_ value: RuntimeStatusRemoteConsoleAvailabilityValue) -> StatusValue {
        StatusValue(
            text: value.text,
            severity: displaySeverity(value.severity),
            uptimeText: value.uptimeText
        )
    }

    private func statusValue(_ value: RuntimeStatusVMStateValue) -> StatusValue {
        StatusValue(
            text: value.text,
            severity: displaySeverity(value.severity),
            uptimeText: value.uptimeText
        )
    }

    private func statusValue(_ value: RuntimeStatusOverallHealthValue) -> StatusValue {
        StatusValue(
            text: value.text,
            severity: displaySeverity(value.severity),
            uptimeText: value.uptimeText
        )
    }

    private func displaySeverity(_ severity: RuntimeStatusActionNeededSeverity) -> Severity {
        switch severity {
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }

    private func displaySeverity(_ severity: RuntimeStatusOverallHealthSeverity) -> Severity {
        switch severity {
        case .healthy:
            return .healthy
        case .warning:
            return .warning
        case .critical:
            return .critical
        case .neutral:
            return .neutral
        }
    }

    private func displaySeverity(_ severity: RuntimeStatusReachabilityPolicy.Severity) -> Severity {
        switch severity {
        case .healthy:
            return .healthy
        case .warning:
            return .warning
        case .critical:
            return .critical
        case .neutral:
            return .neutral
        }
    }

}

private struct AppRuntimeStatusRecorderSummaryVocabulary: RuntimeStatusRecorderSummaryVocabulary {
    var notReportedText: String { AppConstants.StatusText.notReported }
}

private struct AppRuntimeStatusRemoteConsoleAvailabilityVocabulary: RuntimeStatusRemoteConsoleAvailabilityVocabulary {
    var reachableText: String { AppConstants.StatusText.reachable }
    var unavailableText: String { AppConstants.StatusText.unavailable }
}

private struct AppRuntimeStatusVMStateVocabulary: RuntimeStatusVMStateVocabulary {
    func vmStateText(_ value: RuntimeVMState?) -> String {
        AppConstants.StatusText.vmState(value)
    }
}

private struct AppRuntimeStatusOverallHealthVocabulary: RuntimeStatusOverallHealthVocabulary {
    var healthyText: String { AppConstants.StatusText.healthy }
    var notInstalledText: String { AppConstants.StatusText.notInstalled }
    var installingText: String { AppConstants.StatusText.installing }
    var initializingText: String { AppConstants.StatusText.initializing }
    var updatingText: String { AppConstants.StatusText.updating }
    var recoveringText: String { AppConstants.StatusText.recovering }
    var needsAttentionText: String { AppConstants.StatusText.needsAttention }
    var criticalText: String { AppConstants.StatusText.critical }
    var unknownText: String { AppConstants.StatusText.unknown }

    func runtimeLifecycleText(_ value: String) -> String {
        AppConstants.StatusText.runtimeLifecycle(value)
    }

    func installStateText(_ state: RuntimeFileState) -> String {
        AppConstants.StatusText.installState(state)
    }
}

private struct AppRuntimeStatusHealthDetailsVocabulary: RuntimeStatusHealthDetailsVocabulary {
    var runtimeInstallationLabel: String { AppConstants.Labels.runtimeInstallation }
    var vmStateLabel: String { AppConstants.Labels.vmState }
    var vmErrorsLabel: String { AppConstants.Labels.vmErrors }
    var failureReasonsLabel: String { AppConstants.Labels.failureReasons }
    var statusReadIssuesLabel: String { AppConstants.Labels.statusReadIssues }
    var vmIPAddressLabel: String { AppConstants.Labels.vmIPAddress }
    var vitalServerName: String { GeneratedRelease.vitalServerName }
    var hostProxyName: String { GeneratedRelease.hostProxyName }
    var redisName: String { GeneratedRelease.redisName }
    var vitalDBObserverLabel: String { AppConstants.Labels.vitalDBObserver }
    var watchdogLabel: String { AppConstants.Labels.watchdog }
    var waitingText: String { AppConstants.StatusText.waiting }
    var guestStateStaleText: String { AppConstants.StatusText.guestStateStale }
    var installingText: String { AppConstants.StatusText.installing }
    var initializingText: String { AppConstants.StatusText.initializing }
    var updatingText: String { AppConstants.StatusText.updating }
    var recoveringText: String { AppConstants.StatusText.recovering }
    var notReportedText: String { AppConstants.StatusText.notReported }
    var reachableText: String { AppConstants.StatusText.reachable }
    var unavailableText: String { AppConstants.StatusText.unavailable }
    var unreachableText: String { AppConstants.StatusText.unreachable }
    var failedText: String { AppConstants.StatusText.failed }

    func installStateText(_ state: RuntimeFileState) -> String {
        AppConstants.StatusText.installState(state)
    }

    func vmStateText(_ value: RuntimeVMState?) -> String {
        AppConstants.StatusText.vmState(value)
    }

    func launchdStateText(_ state: RuntimeServiceState) -> String {
        AppConstants.StatusText.launchdState(state)
    }

    func containerHealthText(_ health: String) -> String {
        AppConstants.StatusText.containerHealth(health)
    }

    func containerStateText(_ state: String) -> String {
        AppConstants.StatusText.containerState(state)
    }

    func vmErrorText(_ error: RuntimeVMError) -> String {
        AppConstants.StatusText.vmError(error)
    }

    func domainErrorText(_ reason: RuntimeFailureReason) -> String {
        AppConstants.StatusText.domainError(reason)
    }
}

private struct AppRuntimeStatusAdvancedVMHealthVocabulary: RuntimeStatusAdvancedVMHealthVocabulary {
    var runtimeInstallationLabel: String { AppConstants.Labels.runtimeInstallation }
    var vmStateLabel: String { AppConstants.Labels.vmState }
    var vmServiceLabel: String { AppConstants.Labels.vmService }
    var vmIPAddressLabel: String { AppConstants.Labels.vmIPAddress }
    var vmErrorsLabel: String { AppConstants.Labels.vmErrors }
    var waitingText: String { AppConstants.StatusText.waiting }
    var guestStateStaleText: String { AppConstants.StatusText.guestStateStale }
    var installingText: String { AppConstants.StatusText.installing }
    var initializingText: String { AppConstants.StatusText.initializing }
    var updatingText: String { AppConstants.StatusText.updating }
    var recoveringText: String { AppConstants.StatusText.recovering }
    var notReportedText: String { AppConstants.StatusText.notReported }
    var reachableText: String { AppConstants.StatusText.reachable }
    var unavailableText: String { AppConstants.StatusText.unavailable }
    var unreachableText: String { AppConstants.StatusText.unreachable }
    var failedText: String { AppConstants.StatusText.failed }

    func installStateText(_ state: RuntimeFileState) -> String {
        AppConstants.StatusText.installState(state)
    }

    func vmStateText(_ value: RuntimeVMState?) -> String {
        AppConstants.StatusText.vmState(value)
    }

    func launchdStateText(_ state: RuntimeServiceState) -> String {
        AppConstants.StatusText.launchdState(state)
    }

    func vmErrorText(_ error: RuntimeVMError) -> String {
        AppConstants.StatusText.vmError(error)
    }
}

private struct AppRuntimeStatusVitalServerAvailabilityVocabulary: RuntimeStatusVitalServerAvailabilityVocabulary {
    var installingText: String { AppConstants.StatusText.installing }
    var initializingText: String { AppConstants.StatusText.initializing }
    var updatingText: String { AppConstants.StatusText.updating }
    var recoveringText: String { AppConstants.StatusText.recovering }
    var notReportedText: String { AppConstants.StatusText.notReported }
    var reachableText: String { AppConstants.StatusText.reachable }
    var unavailableText: String { AppConstants.StatusText.unavailable }
    var unreachableText: String { AppConstants.StatusText.unreachable }
    var failedText: String { AppConstants.StatusText.failed }
}

private struct AppRuntimeStatusAdvancedServiceHealthVocabulary: RuntimeStatusAdvancedServiceHealthVocabulary {
    var proxyServiceLabel: String { AppConstants.Labels.proxyService }
    var guestLogSyncServiceLabel: String { AppConstants.Labels.guestLogSyncService }
    var sleepPreventionServiceLabel: String { AppConstants.Labels.sleepPreventionService }
    var watchdogServiceLabel: String { AppConstants.Labels.watchdogService }
    var vitalServerName: String { GeneratedRelease.vitalServerName }
    var hostProxyName: String { GeneratedRelease.hostProxyName }
    var vitalDBObserverLabel: String { AppConstants.Labels.vitalDBObserver }
    var redisUIName: String { GeneratedRelease.redisUIName }
    var swaggerUIName: String { GeneratedRelease.swaggerUIName }
    var waitingText: String { AppConstants.StatusText.waiting }
    var guestStateStaleText: String { AppConstants.StatusText.guestStateStale }
    var installingText: String { AppConstants.StatusText.installing }
    var initializingText: String { AppConstants.StatusText.initializing }
    var updatingText: String { AppConstants.StatusText.updating }
    var recoveringText: String { AppConstants.StatusText.recovering }
    var notReportedText: String { AppConstants.StatusText.notReported }
    var reachableText: String { AppConstants.StatusText.reachable }
    var unavailableText: String { AppConstants.StatusText.unavailable }
    var unreachableText: String { AppConstants.StatusText.unreachable }
    var failedText: String { AppConstants.StatusText.failed }

    func launchdStateText(_ state: RuntimeServiceState) -> String {
        AppConstants.StatusText.launchdState(state)
    }

    func containerHealthText(_ health: String) -> String {
        AppConstants.StatusText.containerHealth(health)
    }

    func containerStateText(_ state: String) -> String {
        AppConstants.StatusText.containerState(state)
    }
}

private struct AppRuntimeStatusActionNeededVocabulary: RuntimeStatusActionNeededVocabulary {
    var runtimeNotInstalledTitle: String { AppConstants.StatusText.runtimeNotInstalled }
    var installAction: String { AppConstants.Actions.install }
    var vitalServerNeedsAttentionTitle: String { AppConstants.StatusText.vitalServerNeedsAttention }
    var openLogsAction: String { AppConstants.Actions.openLogs }
    var vitalServerUnavailableTitle: String { AppConstants.StatusText.vitalServerUnavailable }

    func installStateText(_ state: RuntimeFileState) -> String {
        AppConstants.StatusText.installState(state)
    }

    func domainRecoveryActionText(_ action: RuntimeDomainRecoveryAction) -> String {
        AppConstants.StatusText.domainRecoveryAction(action)
    }
}
