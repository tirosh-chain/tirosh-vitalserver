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

    func overallHealth(status: RuntimeStatus, observation: RuntimeContainerObservation?) -> StatusValue {
        if status.isReady {
            return StatusValue(
                text: AppConstants.StatusText.healthy,
                severity: .healthy,
                uptimeText: uptimeText(for: .vitalServer, observation: observation)
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
                uptimeText: uptimeText(for: .vitalServer, observation: observation)
            )
        case .some(.degraded), .some(.recovering):
            return StatusValue(
                text: AppConstants.StatusText.needsAttention,
                severity: .warning,
                uptimeText: uptimeText(for: .vitalServer, observation: observation)
            )
        default:
            return StatusValue(
                text: AppConstants.StatusText.starting,
                severity: .warning,
                uptimeText: uptimeText(for: .vitalServer, observation: observation)
            )
        }
    }

    func vitalServerAvailability(status: RuntimeStatus, observation: RuntimeContainerObservation?) -> StatusValue {
        let text: String
        if isSuccessfulHTTPStatus(status.hostProxyHTTP) {
            text = AppConstants.StatusText.available
        } else if status.runtimeInstalled {
            text = AppConstants.StatusText.waiting
        } else {
            text = AppConstants.StatusText.unavailable
        }
        return StatusValue(
            text: text,
            severity: isSuccessfulHTTPStatus(status.hostProxyHTTP) ? .healthy : .warning,
            uptimeText: uptimeText(for: .vitalServer, observation: observation)
        )
    }

    func healthDetails(status: RuntimeStatus, observation: RuntimeContainerObservation?) -> [HealthItem] {
        [
            HealthItem(
                label: AppConstants.Labels.managerRuntime,
                value: StatusValue(
                    text: status.runtimeInstalled ? AppConstants.StatusText.ready : AppConstants.StatusText.notInstalled,
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
                value: httpValue(status.guestHTTP, uptimeText: uptimeText(for: .vitalServer, observation: observation))
            ),
            HealthItem(
                label: GeneratedRelease.hostProxyName,
                value: StatusValue(
                    text: serviceReachabilityLabel(status.hostProxyHTTP),
                    severity: status.proxyServiceLoaded && isSuccessfulHTTPStatus(status.hostProxyHTTP) ? .healthy : .warning,
                    uptimeText: uptimeText(for: .networkAccess, observation: observation)
                )
            ),
            HealthItem(
                label: GeneratedRelease.redisName,
                value: composeValue(for: .redis, observation: observation)
            ),
            HealthItem(
                label: AppConstants.Labels.watchdog,
                value: StatusValue(
                    text: status.watchdogServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded,
                    severity: status.watchdogServiceLoaded ? .healthy : .warning,
                    uptimeText: nil
                )
            ),
        ]
    }

    func advancedServiceHealth(status: RuntimeStatus, observation: RuntimeContainerObservation?) -> [ServiceHealthItem] {
        [
            serviceStateItem(
                AppConstants.Labels.managerRuntime,
                isHealthy: status.runtimeInstalled,
                value: status.runtimeInstalled ? AppConstants.StatusText.installed : AppConstants.StatusText.notInstalled
            ),
            serviceStateItem(
                AppConstants.Labels.vmService,
                isHealthy: status.vmServiceLoaded,
                value: status.vmServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded
            ),
            serviceStateItem(
                AppConstants.Labels.proxyService,
                isHealthy: status.proxyServiceLoaded,
                value: status.proxyServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded
            ),
            serviceStateItem(
                AppConstants.Labels.watchdogService,
                isHealthy: status.watchdogServiceLoaded,
                value: status.watchdogServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded
            ),
            httpServiceItem(
                GeneratedRelease.vitalServerName,
                httpStatus: status.guestHTTP,
                uptimeText: uptimeText(for: .vitalServer, observation: observation),
                action: .openVitalServer
            ),
            httpServiceItem(
                GeneratedRelease.hostProxyName,
                httpStatus: status.hostProxyHTTP,
                uptimeText: uptimeText(for: .networkAccess, observation: observation),
                action: .openVitalServer
            ),
            httpServiceItem(
                GeneratedRelease.redisUIName,
                httpStatus: status.redisUIHTTP,
                uptimeText: uptimeText(for: .redisUI, observation: observation),
                action: .openRedisUI
            ),
            httpServiceItem(
                GeneratedRelease.swaggerUIName,
                httpStatus: status.swaggerUIHTTP,
                uptimeText: uptimeText(for: .swaggerUI, observation: observation),
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

    private func uptimeText(for service: ComposeService, observation: RuntimeContainerObservation?) -> String? {
        formatUptime(composeObservation(for: service, observation: observation)?.uptimeSeconds)
    }

    private func composeValue(for service: ComposeService, observation: RuntimeContainerObservation?) -> StatusValue {
        let serviceObservation = composeObservation(for: service, observation: observation)
        return StatusValue(
            text: composeStatusText(serviceObservation),
            severity: composeSeverity(serviceObservation),
            uptimeText: formatUptime(serviceObservation?.uptimeSeconds)
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
            return health
        }
        if let state = observation?.state, !state.isEmpty {
            return state
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
        if isSuccessfulHTTPStatus(value) {
            return AppConstants.StatusText.reachable
        }
        if value == AppConstants.StatusText.failed {
            return AppConstants.StatusText.needsRepair
        }
        return AppConstants.StatusText.waiting
    }

    private func formatUptime(_ seconds: Int?) -> String? {
        guard let seconds else {
            return nil
        }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m \(remainingSeconds)s"
        }
        return "\(hours)h \(minutes)m \(remainingSeconds)s"
    }
}
