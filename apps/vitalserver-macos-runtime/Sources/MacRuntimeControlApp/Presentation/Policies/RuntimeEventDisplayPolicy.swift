import Contracts

struct RuntimeEventDisplayPolicy {
    enum Severity: Equatable {
        case healthy
        case warning
        case critical
        case neutral
    }

    struct EventItem: Equatable, Identifiable {
        let id: String
        let timestamp: String
        let eventType: String
        let status: String
        let statusSeverity: Severity
        let operation: String
        let message: String
        let detailText: String?
    }

    func item(for event: RuntimeEventDocument) -> EventItem {
        EventItem(
            id: event.id,
            timestamp: event.timestamp,
            eventType: event.eventType.rawValue,
            status: event.status.rawValue,
            statusSeverity: severity(for: event.status),
            operation: event.operation.rawValue,
            message: event.message,
            detailText: detailText(for: event)
        )
    }

    private func detailText(for event: RuntimeEventDocument) -> String? {
        var details: [String] = []
        if let observation = event.containerObservation?.auditProxyStatus {
            details.append("\(AppConstants.Labels.activeRecorderConnections): \(observation.activeRecorderConnections)")
            details.append("\(AppConstants.Labels.knownRecorders): \(observation.recorders.count)")
        }
        if let observation = event.vitalDBObservation {
            let onlineCount = observation.recorders.filter(\.online).count
            let staleCount = observation.recorders.filter(\.stale).count
            details.append("\(AppConstants.Labels.onlineRecorders): \(onlineCount)")
            details.append("\(AppConstants.Labels.staleRecorders): \(staleCount)")
            details.append("\(AppConstants.Labels.recorderAnomalies): \(observation.anomalies.count)")
        }
        return details.isEmpty ? nil : details.joined(separator: ", ")
    }

    private func severity(for status: RuntimeStatusLevel) -> Severity {
        switch status {
        case .healthy:
            return .healthy
        case .critical:
            return .critical
        case .degraded, .recovering:
            return .warning
        default:
            return .neutral
        }
    }
}
