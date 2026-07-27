import Contracts
import Foundation
import RuntimeControl

struct RuntimeRecorderObservabilityDisplayPolicy {
    func operationalHealthSummary(
        _ observability: RuntimeRecorderObservability?
    ) -> String {
        let report = summaryReportText(observability)
        let count = observability?.operationalIssueCount ?? 0
        let health: String
        switch observability?.operationalHealthState {
        case .healthy:
            health = "Healthy"
        case .warning:
            health = "Warning (\(count))"
        case .critical:
            health = "Critical (\(count))"
        case .unknown, nil:
            health = "Unknown"
        }
        return "\(health) · report \(report)"
    }

    func incidentQuery(
        vrcode: String,
        now: Date = Date()
    ) -> RuntimeRecorderObservabilityIncidentQuery {
        let formatter = ISO8601DateFormatter()
        let until = formatter.string(from: now)
        let from = formatter.string(
            from: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        )
        return RuntimeRecorderObservabilityIncidentQuery(
            vrcode: vrcode,
            from: from,
            until: until,
            type: nil,
            cursor: nil,
            limit: 20
        )
    }

    func summaryMismatch(
        detail: RuntimeRecorderObservabilityDetail,
        summary: RuntimeRecorderObservability?
    ) -> Bool {
        guard let summary else {
            return false
        }
        return summary.supportState.rawValue != detail.support.state
            || summary.reportState.rawValue != detail.report.state
            || (
                summary.operationalHealthState != nil
                    && summary.operationalHealthState != detail.operationalHealth.state
            )
    }

    func detailSupportText(_ detail: RuntimeRecorderObservabilityDetail) -> String {
        switch detail.support.state {
        case "supported":
            return "Supported"
        case "unsupported":
            return "Not available on this version"
        default:
            return "Support unknown"
        }
    }

    func detailReportText(_ detail: RuntimeRecorderObservabilityDetail) -> String {
        if detail.support.state == "unsupported" {
            return "Not applicable"
        }
        switch detail.report.state {
        case "awaitingFirstReport":
            return "Waiting for first report"
        case "current":
            return "Current"
        case "stale":
            return "Stale"
        case "missing":
            return "Missing"
        case "readFailed":
            return "Unavailable"
        default:
            return "Not evaluated"
        }
    }

    func readingText(
        _ reading: RuntimeRecorderObservabilityReading,
        suffix: String = ""
    ) -> String {
        guard reading.state == .ok else {
            return reading.state.rawValue
                + (reading.detail.map { " — \($0)" } ?? "")
        }
        guard let value = reading.value else {
            return "invalid — scalar value expected"
        }
        switch value {
        case .bool(let value):
            return "\(value)\(suffix)"
        case .int(let value):
            return "\(value)\(suffix)"
        case .double(let value):
            return "\(value)\(suffix)"
        case .string(let value):
            return "\(value)\(suffix)"
        case .null, .array, .object:
            return "invalid — scalar value expected"
        }
    }

    func byteReadingText(_ reading: RuntimeRecorderObservabilityReading) -> String {
        guard reading.state == .ok, let value = reading.value else {
            return readingText(reading)
        }
        let bytes: Int64?
        switch value {
        case .int(let value):
            bytes = Int64(value)
        case .double(let value) where value.isFinite:
            bytes = Int64(value)
        default:
            bytes = nil
        }
        guard let bytes, bytes >= 0 else {
            return "invalid — byte value expected"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func networkText(
        _ networkInterface: RuntimeRecorderObservabilityNetworkInterface
    ) -> String {
        let state = readingText(networkInterface.operState)
        let carrier = readingText(networkInterface.carrier)
        let rxErrors = readingText(networkInterface.rxErrors)
        let txErrors = readingText(networkInterface.txErrors)
        return "\(networkInterface.name): \(state), carrier \(carrier), "
            + "RX errors \(rxErrors), TX errors \(txErrors)"
    }

    func bootText(
        _ detail: RuntimeRecorderObservabilityDetail,
        timeText: (String?) -> String
    ) -> String {
        switch detail.boot.state {
        case "started":
            return "Started " + timeText(detail.boot.startedAt)
        case "shutdownClean":
            return "Clean shutdown " + timeText(detail.boot.cleanShutdownAt)
        default:
            return detail.boot.orderingState == "nonOrderable"
                ? "Reported, but order cannot be established across boot evidence"
                : "Not reported"
        }
    }

    func evidenceHealthText(
        _ evidenceHealth: RuntimeRecorderObservabilityEvidenceHealth
    ) -> String {
        guard evidenceHealth.state != "notReported" else {
            return "Not reported"
        }
        return evidenceHealth.state
            + (evidenceHealth.detail.map { " — \($0)" } ?? "")
    }

    func incidentStateText(
        _ incidentState: RuntimeRecorderObservabilityIncidentState
    ) -> String {
        guard incidentState.state == "reported" else {
            return incidentState.state
        }
        let states = [
            incidentState.bootLoopState,
            incidentState.repeatedUndervoltageState,
        ]
        .compactMap { $0 }
        .filter { $0 != "none" }
        return states.isEmpty
            ? "No active reported assessment"
            : states.joined(separator: ", ")
    }

    func operationalHealthText(_ health: RuntimeRecorderOperationalHealth) -> String {
        switch health.state {
        case .healthy:
            return "Healthy"
        case .warning:
            return "Warning — \(health.issueCount) reported issue(s)"
        case .critical:
            return "Critical — \(health.issueCount) reported issue(s)"
        case .unknown:
            return health.issueCount > 0
                ? "Unknown — \(health.issueCount) issue(s) in the latest report"
                : "Unknown"
        }
    }

    private func summaryReportText(
        _ observability: RuntimeRecorderObservability?
    ) -> String {
        if observability?.supportState == .unsupported {
            return "Not applicable"
        }
        switch observability?.reportState {
        case .awaitingFirstReport:
            return "Waiting for first report"
        case .current:
            return "Current"
        case .stale:
            return "Stale"
        case .missing:
            return "Missing"
        case .readFailed:
            return "Unavailable"
        case .notEvaluated, nil:
            return "Not evaluated"
        }
    }
}
