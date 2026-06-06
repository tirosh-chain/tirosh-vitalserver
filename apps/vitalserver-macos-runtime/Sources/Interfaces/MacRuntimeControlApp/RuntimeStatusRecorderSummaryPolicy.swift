import Contracts
import RuntimeControl

public protocol RuntimeStatusRecorderSummaryVocabulary {
    var notReportedText: String { get }
}

public struct RuntimeStatusRecorderSummary: Equatable, Sendable {
    public let activeConnections: String
    public let knownRecorders: String
    public let onlineRecorders: String
    public let staleRecorders: String
    public let knownBeds: String
    public let anomalies: String
    public let latestRecorder: String?
    public let observedAt: String?

    public init(
        activeConnections: String,
        knownRecorders: String,
        onlineRecorders: String,
        staleRecorders: String,
        knownBeds: String,
        anomalies: String,
        latestRecorder: String?,
        observedAt: String?
    ) {
        self.activeConnections = activeConnections
        self.knownRecorders = knownRecorders
        self.onlineRecorders = onlineRecorders
        self.staleRecorders = staleRecorders
        self.knownBeds = knownBeds
        self.anomalies = anomalies
        self.latestRecorder = latestRecorder
        self.observedAt = observedAt
    }
}

public struct RuntimeStatusRecorderSummaryPolicy {
    private let vocabulary: any RuntimeStatusRecorderSummaryVocabulary

    public init(vocabulary: any RuntimeStatusRecorderSummaryVocabulary) {
        self.vocabulary = vocabulary
    }

    public func recorderSummary(
        status: RuntimeStatus,
        observation: RuntimeContainerObservation?
    ) -> RuntimeStatusRecorderSummary {
        let summary = RuntimeVitalRecorderSummary(
            containerObservation: observation,
            vitalDBObservation: status.vitalDBObservation
        )
        return RuntimeStatusRecorderSummary(
            activeConnections: summary.activeConnections.map(String.init) ?? vocabulary.notReportedText,
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
            return vocabulary.notReportedText
        }
        return "\(value)"
    }

    private func latestRecorderText(_ recorder: RuntimeVitalRecorderReference) -> String {
        guard let ip = recorder.ip, !ip.isEmpty else {
            return "\(recorder.vrcode) \(vocabulary.notReportedText)"
        }
        return "\(recorder.vrcode) \(ip)"
    }
}
