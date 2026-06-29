import Contracts
import Errors

public protocol RuntimeEventDisplayVocabulary {
    var unknownText: String { get }
    var vmStateLabel: String { get }
    var vmErrorsLabel: String { get }
    var failureReasonsLabel: String { get }
    var activeRecorderConnectionsLabel: String { get }
    var knownRecordersLabel: String { get }
    var onlineRecordersLabel: String { get }
    var staleRecordersLabel: String { get }
    var recorderAnomaliesLabel: String { get }

    func vmStateText(_ state: RuntimeVMState) -> String
    func vmErrorText(_ error: RuntimeVMError) -> String
    func domainErrorText(_ reason: RuntimeFailureReason) -> String
}

public struct RuntimeEventDisplayPolicy {
    public enum Severity: Equatable {
        case healthy
        case warning
        case critical
        case neutral
    }

    public struct EventItem: Equatable, Identifiable {
        public let id: String
        public let timestamp: String
        public let eventType: String
        public let status: String
        public let statusSeverity: Severity
        public let operation: String
        public let message: String
        public let detailText: String?

        public init(
            id: String,
            timestamp: String,
            eventType: String,
            status: String,
            statusSeverity: Severity,
            operation: String,
            message: String,
            detailText: String?
        ) {
            self.id = id
            self.timestamp = timestamp
            self.eventType = eventType
            self.status = status
            self.statusSeverity = statusSeverity
            self.operation = operation
            self.message = message
            self.detailText = detailText
        }
    }

    private let vocabulary: any RuntimeEventDisplayVocabulary

    public init(vocabulary: any RuntimeEventDisplayVocabulary) {
        self.vocabulary = vocabulary
    }

    public func item(for event: RuntimeEventDocument) -> EventItem {
        EventItem(
            id: event.id,
            timestamp: event.timestamp,
            eventType: event.eventType.rawValue,
            status: event.status?.rawValue ?? vocabulary.unknownText,
            statusSeverity: severity(for: event.status),
            operation: event.operation?.rawValue ?? vocabulary.unknownText,
            message: event.message,
            detailText: detailText(for: event)
        )
    }

    private func detailText(for event: RuntimeEventDocument) -> String? {
        var details: [String] = []
        if let vmState = event.vmState {
            details.append("\(vocabulary.vmStateLabel): \(vocabulary.vmStateText(vmState))")
        }
        if let vmErrors = event.vmErrors, !vmErrors.isEmpty {
            details.append("\(vocabulary.vmErrorsLabel): \(vmErrors.map(vocabulary.vmErrorText).joined(separator: ", "))")
        }
        if !event.failureReasons.isEmpty {
            details.append("\(vocabulary.failureReasonsLabel): \(event.failureReasons.map(vocabulary.domainErrorText).joined(separator: ", "))")
        }
        if let observation = event.containerObservation?.recorderIngressStatus {
            details.append("\(vocabulary.activeRecorderConnectionsLabel): \(observation.activeRecorderConnections)")
            details.append("\(vocabulary.knownRecordersLabel): \(observation.recorders.count)")
        }
        if let observation = event.vitalDBObservation {
            let onlineCount = observation.recorders.filter(\.online).count
            let staleCount = observation.recorders.filter(\.stale).count
            details.append("\(vocabulary.onlineRecordersLabel): \(onlineCount)")
            details.append("\(vocabulary.staleRecordersLabel): \(staleCount)")
            details.append("\(vocabulary.recorderAnomaliesLabel): \(observation.anomalies.count)")
        }
        return details.isEmpty ? nil : details.joined(separator: ", ")
    }

    private func severity(for status: RuntimeStatusLevel?) -> Severity {
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

struct AppRuntimeEventDisplayVocabulary: RuntimeEventDisplayVocabulary {
    var unknownText: String { AppConstants.StatusText.unknown }
    var vmStateLabel: String { AppConstants.Labels.vmState }
    var vmErrorsLabel: String { AppConstants.Labels.vmErrors }
    var failureReasonsLabel: String { AppConstants.Labels.failureReasons }
    var activeRecorderConnectionsLabel: String { AppConstants.Labels.activeRecorderConnections }
    var knownRecordersLabel: String { AppConstants.Labels.knownRecorders }
    var onlineRecordersLabel: String { AppConstants.Labels.onlineRecorders }
    var staleRecordersLabel: String { AppConstants.Labels.staleRecorders }
    var recorderAnomaliesLabel: String { AppConstants.Labels.recorderAnomalies }

    func vmStateText(_ state: RuntimeVMState) -> String {
        AppConstants.StatusText.vmState(state)
    }

    func vmErrorText(_ error: RuntimeVMError) -> String {
        AppConstants.StatusText.vmError(error)
    }

    func domainErrorText(_ reason: RuntimeFailureReason) -> String {
        AppConstants.StatusText.domainError(reason)
    }
}

extension RuntimeEventDisplayPolicy {
    init() {
        self.init(vocabulary: AppRuntimeEventDisplayVocabulary())
    }
}
