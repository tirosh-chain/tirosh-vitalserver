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
        let latestRecorder: String?
    }

    private enum ComposeService: String {
        case vitalServer = "app"
        case networkAccess = "edge"
        case redis = "redis"
        case redisUI = "redis-ui"
        case swaggerUI = "swagger-ui"
    }

    func overallHealth(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> StatusValue {
        if status.isReady {
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
        case .some(.critical):
            return StatusValue(
                text: AppConstants.StatusText.critical,
                severity: .critical,
                uptimeText: nil
            )
        case .some(.degraded), .some(.recovering):
            return StatusValue(
                text: AppConstants.StatusText.needsAttention,
                severity: .warning,
                uptimeText: nil
            )
        default:
            return StatusValue(
                text: AppConstants.StatusText.starting,
                severity: .warning,
                uptimeText: nil
            )
        }
    }

    func vitalServerAvailability(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> StatusValue {
        let text: String
        if isSuccessfulHTTPStatus(status.hostProxyHTTP) {
            text = AppConstants.StatusText.reachable
        } else if status.runtimeInstalled {
            text = AppConstants.StatusText.waiting
        } else {
            text = AppConstants.StatusText.unavailable
        }
        return StatusValue(
            text: text,
            severity: isSuccessfulHTTPStatus(status.hostProxyHTTP) ? .healthy : .warning,
            uptimeText: vitalServerUptimeText(status: status, observation: observation, now: now)
        )
    }

    func healthDetails(status: RuntimeStatus, observation: RuntimeContainerObservation?, now: Date = Date()) -> [HealthItem] {
        [
            HealthItem(
                label: AppConstants.Labels.runtimeInstallation,
                value: StatusValue(
                    text: AppConstants.StatusText.installState(installed: status.runtimeInstalled),
                    severity: status.runtimeInstalled ? .healthy : .warning,
                    uptimeText: nil
                )
            ),
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
                label: AppConstants.Labels.watchdog,
                value: StatusValue(
                    text: AppConstants.StatusText.launchdState(loaded: status.watchdogServiceLoaded),
                    severity: status.watchdogServiceLoaded ? .healthy : .warning,
                    uptimeText: nil
                )
            ),
        ]
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
                isHealthy: status.vmServiceLoaded,
                value: AppConstants.StatusText.launchdState(loaded: status.vmServiceLoaded)
            ),
            serviceStateItem(
                AppConstants.Labels.proxyService,
                isHealthy: status.proxyServiceLoaded,
                value: AppConstants.StatusText.launchdState(loaded: status.proxyServiceLoaded)
            ),
            serviceStateItem(
                AppConstants.Labels.guestLogSyncService,
                isHealthy: status.guestLogSyncServiceLoaded,
                value: AppConstants.StatusText.launchdState(loaded: status.guestLogSyncServiceLoaded)
            ),
            serviceStateItem(
                AppConstants.Labels.watchdogService,
                isHealthy: status.watchdogServiceLoaded,
                value: AppConstants.StatusText.launchdState(loaded: status.watchdogServiceLoaded)
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

    func recorderSummary(observation: RuntimeContainerObservation?) -> RecorderSummary {
        let recorders = observation?.auditProxyStatus?.recorders ?? []
        let latest = recorders
            .sorted { ($0.lastSeenAt ?? "") > ($1.lastSeenAt ?? "") }
            .first
        return RecorderSummary(
            activeConnections: "\(observation?.auditProxyStatus?.activeRecorderConnections ?? 0)",
            knownRecorders: "\(recorders.count)",
            latestRecorder: latest.map { "\($0.vrcode) \($0.selectedIp ?? AppConstants.StatusText.unknown)" }
        )
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

    private func httpValue(_ status: String?, uptimeText: String?) -> StatusValue {
        StatusValue(
            text: serviceReachabilityLabel(status),
            severity: isSuccessfulHTTPStatus(status) ? .healthy : .warning,
            uptimeText: uptimeText
        )
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
            ?? formatUptime(nil, startedAt: status.startedAt, observedAt: nil, now: now)
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
        return AppConstants.StatusText.waiting
    }

    private func composeSeverity(_ observation: RuntimeContainerServiceObservation?) -> Severity {
        if observation?.health == "healthy" {
            return .healthy
        }
        if observation?.state == "running", observation?.health == nil {
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
        AppConstants.StatusText.reachability(httpStatus: value)
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
