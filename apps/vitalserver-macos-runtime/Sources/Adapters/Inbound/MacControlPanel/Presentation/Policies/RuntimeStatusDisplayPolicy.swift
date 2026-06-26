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

    func recorderIngressQueue(observation: RuntimeContainerObservation?) -> StatusValue {
        statusValue(healthDetailsPolicy.recorderIngressQueueValue(observation: observation))
    }

    func recorderIngressDetails(observation: RuntimeContainerObservation?) -> [HealthItem] {
        guard let observation else {
            return [
                healthItem(AppConstants.Labels.recorderIngressReplay, AppConstants.StatusText.notReported, .neutral),
            ]
        }
        guard observation.recorderIngressStatusReadState == .loaded else {
            return [
                healthItem(
                    AppConstants.Labels.recorderIngressReplay,
                    AppConstants.StatusText.recorderIngressStatusReadState(
                        observation.recorderIngressStatusReadState
                    ),
                    .warning
                ),
            ]
        }
        guard let status = observation.recorderIngressStatus else {
            return [
                healthItem(AppConstants.Labels.recorderIngressReplay, AppConstants.StatusText.notReported, .neutral),
            ]
        }

        let spool = status.spool
        let replay = status.replay
        return [
            healthItem(
                AppConstants.Labels.recorderIngressConnections,
                "\(status.activeRecorderConnections) active / \(status.activeWebSockets) WebSockets",
                .healthy
            ),
            healthItem(AppConstants.Labels.queue, queueDetailText(spool: spool), queueSeverity(spool: spool, replay: replay)),
            healthItem(
                AppConstants.Labels.recorderIngressThroughput,
                throughputText(status.throughput),
                .neutral
            ),
            healthItem(
                AppConstants.Labels.recorderIngressOldestPending,
                durationText(spool?.oldestPendingAgeSeconds),
                .neutral
            ),
            healthItem(
                AppConstants.Labels.recorderIngressReplay,
                replay?.status ?? AppConstants.StatusText.notReported,
                replaySeverity(replay)
            ),
            healthItem(
                AppConstants.Labels.recorderIngressReplayThroughput,
                replayThroughputText(replay),
                .neutral
            ),
            healthItem(
                AppConstants.Labels.recorderIngressInFlight,
                integerText(replay?.inFlightItems),
                .neutral
            ),
            healthItem(
                AppConstants.Labels.recorderIngressReplayLag,
                durationText(replay?.replayLagSeconds),
                .neutral
            ),
            healthItem(
                AppConstants.Labels.recorderIngressBackpressureRejected,
                integerText(spool?.rejectedEvents),
                countSeverity(spool?.rejectedEvents, nonZero: .warning)
            ),
            healthItem(
                AppConstants.Labels.recorderIngressRetryableFailures,
                integerText(replay?.retryableFailures),
                countSeverity(replay?.retryableFailures, nonZero: .warning)
            ),
            healthItem(
                AppConstants.Labels.recorderIngressDeadLetters,
                integerText(replay?.deadLetteredEvents),
                countSeverity(replay?.deadLetteredEvents, nonZero: .critical)
            ),
            healthItem(
                AppConstants.Labels.recorderIngressLastFailure,
                lastFailureText(spool: spool, replay: replay),
                lastFailureSeverity(spool: spool, replay: replay)
            ),
        ]
    }

    func advancedVMHealth(status: RuntimeStatus) -> [HealthItem] {
        advancedVMHealthPolicy.vmHealth(status: status).map(healthItem)
    }

    func advancedServiceHealth(
        status: RuntimeStatus,
        observation: RuntimeContainerObservation?,
        redisRelaySettings: RuntimeRedisRelaySettings = RuntimeRedisRelaySettings(),
        now: Date = Date()
    ) -> [ServiceHealthItem] {
        advancedServiceHealthPolicy.serviceHealth(
            status: status,
            observation: observation,
            redisRelaySettings: redisRelaySettings,
            now: now
        ).map(serviceHealthItem)
    }

    func recorderSummary(
        observation: RuntimeContainerObservation?,
        vitalDBObservation: VitalDBObservationDocument?,
        now: Date = Date()
    ) -> RecorderSummary {
        recorderSummaryPolicy.recorderSummary(
            observation: observation,
            vitalDBObservation: vitalDBObservation,
            now: now
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

    private func healthItem(
        _ label: String,
        _ text: String,
        _ severity: RuntimeStatusReachabilityPolicy.Severity
    ) -> HealthItem {
        HealthItem(
            label: label,
            value: StatusValue(text: text, severity: displaySeverity(severity), uptimeText: nil)
        )
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

    private func queueDetailText(spool: RuntimeRecorderIngressSpoolStatus?) -> String {
        guard let spool else {
            return AppConstants.StatusText.notReported
        }
        var parts: [String] = []
        if let pendingItems = spool.pendingItems {
            parts.append("\(pendingItems) pending")
        }
        if let pendingBytes = spool.pendingBytes {
            parts.append(formatBytes(pendingBytes))
        }
        return parts.isEmpty ? AppConstants.StatusText.notReported : parts.joined(separator: " / ")
    }

    private func throughputText(_ throughput: RuntimeRecorderIngressThroughputStatus?) -> String {
        guard let throughput else {
            return AppConstants.StatusText.notReported
        }
        var parts: [String] = []
        if let observed = throughput.observedBytesPerSecond {
            parts.append("in \(formatBytesPerSecond(observed))")
        }
        if let replayed = throughput.replayedBytesPerSecond {
            parts.append("replay \(formatBytesPerSecond(replayed))")
        }
        if let growth = throughput.queueGrowthBytesPerSecond {
            parts.append("queue \(signedBytesPerSecond(growth))")
        }
        return parts.isEmpty ? AppConstants.StatusText.notReported : parts.joined(separator: ", ")
    }

    private func replayThroughputText(_ replay: RuntimeRecorderIngressReplayStatus?) -> String {
        guard let replay else {
            return AppConstants.StatusText.notReported
        }
        guard let bytesPerSecond = replay.maxBytesPerSecond else {
            return AppConstants.StatusText.notReported
        }
        let base = formatBinaryBytesPerSecond(bytesPerSecond)
        guard replay.adaptive?.enabled == true,
              let min = replay.adaptive?.minBytesPerSecond,
              let max = replay.adaptive?.maxBytesPerSecond
        else {
            return base
        }
        var parts = [
            "\(base), adaptive \(formatBinaryBytesPerSecond(min))-\(formatBinaryBytesPerSecond(max))"
        ]
        if let memoryGuardStatus = replay.adaptive?.memoryGuardStatus {
            parts.append("guard \(memoryGuardStatus.rawValue)")
        }
        if let itemsPerTick = replay.adaptive?.currentItemsPerTick {
            parts.append("\(itemsPerTick) items/tick")
        }
        if let concurrency = replay.adaptive?.currentConcurrency {
            parts.append("concurrency \(concurrency)")
        }
        return parts.joined(separator: ", ")
    }

    private func queueSeverity(
        spool: RuntimeRecorderIngressSpoolStatus?,
        replay: RuntimeRecorderIngressReplayStatus?
    ) -> RuntimeStatusReachabilityPolicy.Severity {
        if (spool?.writeFailures ?? 0) > 0 || (replay?.deadLetteredEvents ?? 0) > 0 {
            return .critical
        }
        if (spool?.rejectedEvents ?? 0) > 0 || (replay?.retryableFailures ?? 0) > 0 {
            return .warning
        }
        if spool?.mode == "mirror_spool"
            && (replay?.status == nil || replay?.status == "disabled") {
            return .neutral
        }
        if (spool?.pendingItems ?? replay?.pendingItems ?? 0) > 0 || (replay?.inFlightItems ?? 0) > 0 {
            return .warning
        }
        if spool == nil && replay == nil {
            return .neutral
        }
        return .healthy
    }

    private func replaySeverity(_ replay: RuntimeRecorderIngressReplayStatus?) -> RuntimeStatusReachabilityPolicy.Severity {
        guard let status = replay?.status else {
            return .neutral
        }
        switch status {
        case "failed":
            return .critical
        case "degraded":
            return .warning
        case "idle", "replaying":
            return .healthy
        case "disabled":
            return .neutral
        default:
            return .warning
        }
    }

    private func countSeverity(
        _ value: Int?,
        nonZero: RuntimeStatusReachabilityPolicy.Severity
    ) -> RuntimeStatusReachabilityPolicy.Severity {
        guard let value else {
            return .neutral
        }
        return value > 0 ? nonZero : .healthy
    }

    private func integerText(_ value: Int?) -> String {
        value.map(String.init) ?? AppConstants.StatusText.notReported
    }

    private func durationText(_ seconds: Int?) -> String {
        guard let seconds else {
            return AppConstants.StatusText.notReported
        }
        let bounded = max(0, seconds)
        if bounded < 60 {
            return "\(bounded)s"
        }
        let minutes = bounded / 60
        let remainder = bounded % 60
        if minutes < 60 {
            return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
        }
        let hours = minutes / 60
        let minuteRemainder = minutes % 60
        return minuteRemainder == 0 ? "\(hours)h" : "\(hours)h \(minuteRemainder)m"
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes <= 0 {
            return "0 bytes"
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(max(0, bytesPerSecond).rounded())))/s"
    }

    private func formatBinaryBytesPerSecond(_ bytesPerSecond: Int) -> String {
        let bounded = max(0, bytesPerSecond)
        if bounded < 1_024 {
            return "\(bounded) B/s"
        }
        let kib = Double(bounded) / 1_024
        if kib < 1_024 {
            return String(format: "%.1f KiB/s", kib)
        }
        let mib = Double(bounded) / 1_048_576
        if mib < 1_024 {
            return String(format: "%.1f MiB/s", mib)
        }
        let gib = Double(bounded) / 1_073_741_824
        return String(format: "%.1f GiB/s", gib)
    }

    private func signedBytesPerSecond(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond > 0 {
            return "+\(formatBytesPerSecond(bytesPerSecond))"
        }
        if bytesPerSecond < 0 {
            return "-\(formatBytesPerSecond(abs(bytesPerSecond)))"
        }
        return formatBytesPerSecond(0)
    }

    private func lastFailureText(
        spool: RuntimeRecorderIngressSpoolStatus?,
        replay: RuntimeRecorderIngressReplayStatus?
    ) -> String {
        if let text = failureText(replay?.lastFailure) {
            return text
        }
        if let text = failureText(spool?.lastFailure) {
            return text
        }
        if spool != nil || replay != nil {
            return "none"
        }
        return AppConstants.StatusText.notReported
    }

    private func failureText(_ failure: RuntimeRecorderIngressFailureObservation?) -> String? {
        guard let failure else {
            return nil
        }
        if let reason = failure.reason, !reason.isEmpty {
            if let message = failure.message, !message.isEmpty {
                return "\(reason): \(message)"
            }
            return reason
        }
        if let message = failure.message, !message.isEmpty {
            return message
        }
        return nil
    }

    private func lastFailureSeverity(
        spool: RuntimeRecorderIngressSpoolStatus?,
        replay: RuntimeRecorderIngressReplayStatus?
    ) -> RuntimeStatusReachabilityPolicy.Severity {
        if replay?.lastFailure != nil || spool?.lastFailure != nil {
            return (spool?.writeFailures ?? 0) > 0 || (replay?.deadLetteredEvents ?? 0) > 0
                ? .critical
                : .warning
        }
        if spool == nil && replay == nil {
            return .neutral
        }
        return .healthy
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
    var recorderIngressQueueLabel: String { AppConstants.Labels.recorderIngressQueue }
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

    func recorderIngressStatusReadStateText(_ state: RuntimeRecorderIngressStatusReadState) -> String {
        AppConstants.StatusText.recorderIngressStatusReadState(state)
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
    var recorderIngressName: String { GeneratedRelease.recorderIngressName }
    var hostProxyName: String { GeneratedRelease.hostProxyName }
    var vitalDBObserverLabel: String { AppConstants.Labels.vitalDBObserver }
    var redisRelayLabel: String { AppConstants.Labels.redisRelay }
    var redisUIName: String { GeneratedRelease.redisUIName }
    var swaggerUIName: String { GeneratedRelease.swaggerUIName }
    var disabledText: String { AppConstants.StatusText.disabled }
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
