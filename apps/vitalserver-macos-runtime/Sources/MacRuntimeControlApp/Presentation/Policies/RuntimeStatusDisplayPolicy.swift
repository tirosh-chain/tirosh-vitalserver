import Foundation
import Contracts
import RuntimeControl

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

    struct RecorderSummary: Equatable {
        let activeConnections: String
        let knownRecorders: String
        let onlineRecorders: String
        let staleRecorders: String
        let knownBeds: String
        let anomalies: String
        let latestRecorder: String?
        let observedAt: String?
    }

    private enum ComposeService: String {
        case vitalServer = "app"
        case networkAccess = "edge"
        case redis = "redis"
        case vitalDBObserver = "vitaldb-observer"
        case redisUI = "redis-ui"
        case swaggerUI = "swagger-ui"
    }

    func overallHealth(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> StatusValue {
        if RuntimeActiveOperationPolicy.isUpdateInProgress(status) {
            return StatusValue(
                text: AppConstants.StatusText.updating,
                severity: .warning,
                uptimeText: nil
            )
        }
        if RuntimeReadinessPolicy.isReady(status) {
            return StatusValue(
                text: AppConstants.StatusText.healthy,
                severity: .healthy,
                uptimeText: nil
            )
        }
        if !status.runtimeInstalled {
            return StatusValue(
                text: AppConstants.StatusText.notInstalled,
                severity: .critical,
                uptimeText: nil
            )
        }
        switch status.runtimeState {
        case .some(.installing):
            return StatusValue(
                text: AppConstants.StatusText.installing,
                severity: .warning,
                uptimeText: nil
            )
        case .some(.updating):
            return StatusValue(
                text: AppConstants.StatusText.updating,
                severity: .warning,
                uptimeText: nil
            )
        case .some(.recovering):
            return StatusValue(
                text: AppConstants.StatusText.recovering,
                severity: .warning,
                uptimeText: nil
            )
        case .some(.healthy):
            return StatusValue(
                text: AppConstants.StatusText.needsAttention,
                severity: .warning,
                uptimeText: nil
            )
        case .some(.critical):
            return StatusValue(
                text: AppConstants.StatusText.critical,
                severity: .critical,
                uptimeText: nil
            )
        case .some(.degraded):
            return StatusValue(
                text: AppConstants.StatusText.needsAttention,
                severity: .warning,
                uptimeText: nil
            )
        case .some(.unknown(let value)):
            return StatusValue(
                text: AppConstants.StatusText.runtimeLifecycle(value),
                severity: .warning,
                uptimeText: nil
            )
        default:
            return StatusValue(
                text: AppConstants.StatusText.unknown,
                severity: .neutral,
                uptimeText: nil
            )
        }
    }

    func vitalServerAvailability(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> StatusValue {
        let text: String
        if RuntimeActiveOperationPolicy.isUpdateInProgress(status) {
            text = AppConstants.StatusText.updating
        } else if !status.runtimeInstalled {
            text = AppConstants.StatusText.unavailable
        } else {
            text = serviceReachabilityLabel(status.hostProxyHTTP)
        }
        return StatusValue(
            text: text,
            severity: RuntimeActiveOperationPolicy.isUpdateInProgress(status) ? .warning : httpSeverity(status.hostProxyHTTP),
            uptimeText: vitalServerUptimeText(status: status, observation: observation, now: now)
        )
    }

    func remoteConsoleAvailability(status: RuntimeStatus, now: Date = Date()) -> StatusValue {
        remoteConsoleAvailability(
            http: status.runtimeControlHTTP,
            startedAt: status.runtimeControlStartedAt,
            now: now
        )
    }

    func remoteConsoleAvailability(http: String?, startedAt: String?, now: Date = Date()) -> StatusValue {
        let reachable = isSuccessfulHTTPStatus(http)
        return StatusValue(
            text: reachable ? AppConstants.StatusText.reachable : AppConstants.StatusText.unavailable,
            severity: reachable ? .healthy : .warning,
            uptimeText: formatUptime(nil, startedAt: startedAt, observedAt: nil, now: now)
        )
    }

    func actionNeeded(status: RuntimeStatus) -> ActionNeededItem? {
        if RuntimeReadinessPolicy.isReady(status) || isManagedOperationInProgress(status.runtimeState) {
            return nil
        }
        if !status.runtimeInstalled {
            return ActionNeededItem(
                title: AppConstants.StatusText.runtimeNotInstalled,
                recommendedAction: AppConstants.Actions.install,
                severity: .critical
            )
        }

        let primaryReason = status.failureReasons.first { $0.domainSeverity == .critical }
            ?? status.failureReasons.first
        if let primaryReason {
            return ActionNeededItem(
                title: userFacingProblemTitle(status),
                recommendedAction: userFacingAction(for: primaryReason.recoveryAction),
                severity: primaryReason.domainSeverity == .critical ? .critical : .warning
            )
        }
        if !status.readIssues.isEmpty {
            return ActionNeededItem(
                title: AppConstants.StatusText.vitalServerNeedsAttention,
                recommendedAction: AppConstants.Actions.openLogs,
                severity: .warning
            )
        }
        return nil
    }

    func healthDetails(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> [HealthItem] {
        var items = [
            HealthItem(
                label: AppConstants.Labels.runtimeInstallation,
                value: StatusValue(
                    text: AppConstants.StatusText.installState(installed: status.runtimeInstalled),
                    severity: status.runtimeInstalled ? .healthy : .warning,
                    uptimeText: nil
                )
            ),
            HealthItem(
                label: AppConstants.Labels.vmState,
                value: vmStateValue(status.vmState)
            ),
        ]
        if let vmErrors = status.vmErrors, !vmErrors.isEmpty {
            items.append(HealthItem(
                label: AppConstants.Labels.vmErrors,
                value: StatusValue(
                    text: vmErrors.map(AppConstants.StatusText.vmError).joined(separator: ", "),
                    severity: .critical,
                    uptimeText: nil
                )
            ))
        }
        if !status.failureReasons.isEmpty {
            items.append(HealthItem(
                label: AppConstants.Labels.failureReasons,
                value: StatusValue(
                    text: status.failureReasons.map(AppConstants.StatusText.domainError).joined(separator: ", "),
                    severity: status.failureReasons.contains { $0.domainSeverity == .critical } ? .critical : .warning,
                    uptimeText: nil
                )
            ))
        }
        if !status.readIssues.isEmpty {
            items.append(HealthItem(
                label: AppConstants.Labels.statusReadIssues,
                value: StatusValue(
                    text: status.readIssues.map { "\($0.source): \($0.message)" }.joined(separator: ", "),
                    severity: .warning,
                    uptimeText: nil
                )
            ))
        }
        items.append(contentsOf: [
            HealthItem(
                label: AppConstants.Labels.vmIPAddress,
                value: StatusValue(
                    text: status.vmIP ?? AppConstants.StatusText.waiting,
                    severity: status.vmServiceLoaded && status.vmIP != nil ? .healthy : .warning,
                    uptimeText: nil
                )
            ),
            HealthItem(
                label: GeneratedRelease.vitalServerName,
                value: httpValue(status.guestHTTP, uptimeText: uptimeText(for: .vitalServer, observation: observation, now: now))
            ),
            HealthItem(
                label: GeneratedRelease.hostProxyName,
                value: StatusValue(
                    text: serviceReachabilityLabel(status.hostProxyHTTP),
                    severity: status.proxyServiceLoaded && isSuccessfulHTTPStatus(status.hostProxyHTTP) ? .healthy : .warning,
                    uptimeText: uptimeText(for: .networkAccess, observation: observation, now: now)
                )
            ),
            HealthItem(
                label: GeneratedRelease.redisName,
                value: composeValue(for: .redis, observation: observation, now: now)
            ),
            HealthItem(
                label: AppConstants.Labels.vitalDBObserver,
                value: composeValue(for: .vitalDBObserver, observation: observation, now: now)
            ),
            HealthItem(
                label: AppConstants.Labels.watchdog,
                value: serviceValue(state: status.watchdogServiceState, fallbackLoaded: status.watchdogServiceLoaded)
            ),
        ])
        return items
    }

    func advancedServiceHealth(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> [ServiceHealthItem] {
        [
            serviceStateItem(
                AppConstants.Labels.runtimeInstallation,
                isHealthy: status.runtimeInstalled,
                value: AppConstants.StatusText.installState(installed: status.runtimeInstalled)
            ),
            serviceStateItem(
                AppConstants.Labels.vmService,
                state: status.vmServiceState,
                fallbackLoaded: status.vmServiceLoaded
            ),
            serviceStateItem(
                AppConstants.Labels.proxyService,
                state: status.proxyServiceState,
                fallbackLoaded: status.proxyServiceLoaded
            ),
            serviceStateItem(
                AppConstants.Labels.guestLogSyncService,
                state: status.guestLogSyncServiceState,
                fallbackLoaded: status.guestLogSyncServiceLoaded
            ),
            serviceStateItem(
                AppConstants.Labels.sleepPreventionService,
                state: status.sleepPreventionServiceState,
                fallbackLoaded: status.sleepPreventionServiceLoaded
            ),
            serviceStateItem(
                AppConstants.Labels.watchdogService,
                state: status.watchdogServiceState,
                fallbackLoaded: status.watchdogServiceLoaded
            ),
            httpServiceItem(
                GeneratedRelease.vitalServerName,
                httpStatus: status.guestHTTP,
                uptimeText: uptimeText(for: .vitalServer, observation: observation, now: now),
                action: .openVitalServer
            ),
            httpServiceItem(
                GeneratedRelease.hostProxyName,
                httpStatus: status.hostProxyHTTP,
                uptimeText: uptimeText(for: .networkAccess, observation: observation, now: now),
                action: .openVitalServer
            ),
            composeServiceItem(
                AppConstants.Labels.vitalDBObserver,
                service: .vitalDBObserver,
                observation: observation,
                now: now
            ),
            httpServiceItem(
                GeneratedRelease.redisUIName,
                httpStatus: status.redisUIHTTP,
                uptimeText: uptimeText(for: .redisUI, observation: observation, now: now),
                action: .openRedisUI
            ),
            httpServiceItem(
                GeneratedRelease.swaggerUIName,
                httpStatus: status.swaggerUIHTTP,
                uptimeText: uptimeText(for: .swaggerUI, observation: observation, now: now),
                action: .openSwagger
            ),
        ]
    }

    func recorderSummary(status: RuntimeStatus, observation: RuntimeContainerObservation?) -> RecorderSummary {
        let summary = RuntimeVitalRecorderSummary(
            containerObservation: observation,
            vitalDBObservation: status.vitalDBObservation
        )
        return RecorderSummary(
            activeConnections: summary.activeConnections.map(String.init) ?? AppConstants.StatusText.notReported,
            knownRecorders: reportedRecorderMetric(summary.source, summary.knownRecorders),
            onlineRecorders: reportedRecorderMetric(summary.source, summary.onlineRecorders),
            staleRecorders: reportedRecorderMetric(summary.source, summary.staleRecorders),
            knownBeds: reportedRecorderMetric(summary.source, summary.knownBeds),
            anomalies: reportedRecorderMetric(summary.source, summary.recorderAnomalies),
            latestRecorder: summary.latestRecorder.map(latestRecorderText),
            observedAt: summary.observedAt
        )
    }

    private func reportedRecorderMetric(_ source: RuntimeVitalRecorderSummarySource, _ value: Int?) -> String {
        guard source == .vitalDBObservation, let value else {
            return AppConstants.StatusText.notReported
        }
        return "\(value)"
    }

    private func latestRecorderText(_ recorder: RuntimeVitalRecorderReference) -> String {
        guard let ip = recorder.ip, !ip.isEmpty else {
            return "\(recorder.vrcode) \(AppConstants.StatusText.notReported)"
        }
        return "\(recorder.vrcode) \(ip)"
    }

    private func serviceStateItem(_ label: String, isHealthy: Bool, value: String) -> ServiceHealthItem {
        ServiceHealthItem(
            label: label,
            value: StatusValue(
                text: value,
                severity: isHealthy ? .healthy : .warning,
                uptimeText: nil
            ),
            httpStatus: nil,
            action: nil
        )
    }

    private func serviceStateItem(
        _ label: String,
        state: RuntimeServiceState?,
        fallbackLoaded: Bool?
    ) -> ServiceHealthItem {
        let value = serviceValue(state: state, fallbackLoaded: fallbackLoaded)
        return ServiceHealthItem(
            label: label,
            value: value,
            httpStatus: nil,
            action: nil
        )
    }

    private func serviceValue(state: RuntimeServiceState?, fallbackLoaded: Bool?) -> StatusValue {
        let text: String
        let severity: Severity
        if let state {
            text = AppConstants.StatusText.launchdState(state)
            severity = serviceStateSeverity(state)
        } else if let fallbackLoaded {
            text = AppConstants.StatusText.launchdState(loaded: fallbackLoaded)
            severity = fallbackLoaded ? .healthy : .warning
        } else {
            text = AppConstants.StatusText.unavailable
            severity = .warning
        }
        return StatusValue(text: text, severity: severity, uptimeText: nil)
    }

    private func serviceStateSeverity(_ state: RuntimeServiceState) -> Severity {
        switch state {
        case .loaded:
            return .healthy
        case .notLoaded, .readFailed, .permissionDenied:
            return .warning
        case .unknown:
            return .neutral
        }
    }

    private func httpServiceItem(
        _ label: String,
        httpStatus: String?,
        uptimeText: String?,
        action: ServiceAction
    ) -> ServiceHealthItem {
        ServiceHealthItem(
            label: label,
            value: httpValue(httpStatus, uptimeText: uptimeText),
            httpStatus: httpStatus,
            action: action
        )
    }

    private func composeServiceItem(
        _ label: String,
        service: ComposeService,
        observation: RuntimeContainerObservation?,
        now: Date
    ) -> ServiceHealthItem {
        ServiceHealthItem(
            label: label,
            value: composeValue(for: service, observation: observation, now: now),
            httpStatus: nil,
            action: nil
        )
    }

    private func httpValue(_ status: String?, uptimeText: String?) -> StatusValue {
        StatusValue(
            text: serviceReachabilityLabel(status),
            severity: httpSeverity(status),
            uptimeText: uptimeText
        )
    }

    private func isManagedOperationInProgress(_ state: RuntimeState?) -> Bool {
        state == .installing || state == .updating || state == .recovering
    }

    private func userFacingProblemTitle(_ status: RuntimeStatus) -> String {
        if !isSuccessfulHTTPStatus(status.guestHTTP) || !isSuccessfulHTTPStatus(status.hostProxyHTTP) {
            return AppConstants.StatusText.vitalServerUnavailable
        }
        return AppConstants.StatusText.vitalServerNeedsAttention
    }

    private func userFacingAction(for action: RuntimeDomainRecoveryAction) -> String {
        switch action {
        case .installRuntime:
            return AppConstants.Actions.install
        default:
            return AppConstants.StatusText.domainRecoveryAction(action)
        }
    }

    private func uptimeText(for service: ComposeService, observation: RuntimeContainerObservation?, now: Date) -> String? {
        let serviceObservation = composeObservation(for: service, observation: observation)
        return formatUptime(
            serviceObservation?.uptimeSeconds,
            startedAt: serviceObservation?.startedAt,
            observedAt: observation?.runtimeStateUpdatedAt ?? observation?.runtimeStateFileUpdatedAt,
            now: now
        )
    }

    private func vitalServerUptimeText(
        status: RuntimeStatus,
        observation: RuntimeContainerObservation?,
        now: Date
    ) -> String? {
        uptimeText(for: .vitalServer, observation: observation, now: now)
    }

    private func composeValue(for service: ComposeService, observation: RuntimeContainerObservation?, now: Date) -> StatusValue {
        let serviceObservation = composeObservation(for: service, observation: observation)
        return StatusValue(
            text: composeStatusText(serviceObservation),
            severity: composeSeverity(serviceObservation),
            uptimeText: formatUptime(
                serviceObservation?.uptimeSeconds,
                startedAt: serviceObservation?.startedAt,
                observedAt: observation?.runtimeStateUpdatedAt ?? observation?.runtimeStateFileUpdatedAt,
                now: now
            )
        )
    }

    private func composeObservation(
        for service: ComposeService,
        observation: RuntimeContainerObservation?
    ) -> RuntimeContainerServiceObservation? {
        observation?.composeServices.first { $0.service == service.rawValue }
    }

    private func composeStatusText(_ observation: RuntimeContainerServiceObservation?) -> String {
        if let health = observation?.health, !health.isEmpty {
            return AppConstants.StatusText.containerHealth(health)
        }
        if let state = observation?.state, !state.isEmpty {
            return AppConstants.StatusText.containerState(state)
        }
        return AppConstants.StatusText.notReported
    }

    private func composeSeverity(_ observation: RuntimeContainerServiceObservation?) -> Severity {
        guard let observation else {
            return .neutral
        }
        if observation.health == "healthy" {
            return .healthy
        }
        return .warning
    }

    private func isSuccessfulHTTPStatus(_ value: String?) -> Bool {
        guard let value, let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    private func serviceReachabilityLabel(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return AppConstants.StatusText.notReported
        }
        if isSuccessfulHTTPStatus(value) {
            return AppConstants.StatusText.reachable
        }
        if Int(value) != nil {
            return AppConstants.StatusText.unavailable
        }
        if value == "failed" {
            return AppConstants.StatusText.unreachable
        }
        return AppConstants.StatusText.failed
    }

    private func httpSeverity(_ value: String?) -> Severity {
        guard let value, !value.isEmpty else {
            return .neutral
        }
        return isSuccessfulHTTPStatus(value) ? .healthy : .warning
    }

    func vmStateValue(_ value: RuntimeVMState?) -> StatusValue {
        return StatusValue(
            text: AppConstants.StatusText.vmState(value),
            severity: vmStateSeverity(value),
            uptimeText: nil
        )
    }

    private func vmStateSeverity(_ value: RuntimeVMState?) -> Severity {
        switch value {
        case .running:
            return .healthy
        case .starting, .stale:
            return .warning
        case .notInstalled, .stopped, .unreachable, .failed:
            return .critical
        case .unknown, nil:
            return .neutral
        }
    }

    private func formatUptime(_ seconds: Int?, startedAt: String?, observedAt: String?, now: Date) -> String? {
        let liveSeconds = startedAt.flatMap { value in
            parseISODate(value).map { startedAt in
                max(Int(now.timeIntervalSince(startedAt)), 0)
            }
        }
        let observedSeconds = seconds.flatMap { seconds in
            observedAt.flatMap { value in
                parseISODate(value).map { observedAt in
                    seconds + max(Int(now.timeIntervalSince(observedAt)), 0)
                }
            }
        }
        guard let seconds = liveSeconds ?? observedSeconds ?? seconds else {
            return nil
        }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        let clock = String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        if days > 0 {
            return "\(days)d \(clock)"
        }
        return clock
    }

    private func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        guard let normalized = normalizedFractionalISODate(value), normalized != value else {
            return nil
        }
        return formatter.date(from: normalized) ?? ISO8601DateFormatter().date(from: normalized)
    }

    private func normalizedFractionalISODate(_ value: String) -> String? {
        guard let dotIndex = value.firstIndex(of: ".") else {
            return nil
        }
        let suffixStart = value[value.index(after: dotIndex)...]
        let fractionEnd = suffixStart.firstIndex { !$0.isNumber } ?? value.endIndex
        let fraction = value[value.index(after: dotIndex)..<fractionEnd]
        guard fraction.count > 3 else {
            return nil
        }
        return String(value[..<value.index(after: dotIndex)] + fraction.prefix(3) + value[fractionEnd...])
    }
}
