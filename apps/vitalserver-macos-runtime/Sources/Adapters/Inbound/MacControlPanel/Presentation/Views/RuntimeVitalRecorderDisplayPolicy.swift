import Contracts
import Foundation
import RuntimeControl
import Errors

public struct RuntimeVitalRecorderDisplayPolicy {
    private static let productLabVersion = "vitalserver-lab"

    public enum RecorderSortOption: String, CaseIterable, Identifiable, Equatable, Sendable {
        case vrcode
        case lastSeen
        case status
        case bed

        public var id: String { rawValue }
    }

    public enum StatusTone: Equatable, Sendable {
        case active
        case warning
        case neutral
    }

    public init() {}

    public func statusText(_ status: RuntimeVitalRecorderStatus) -> String {
        switch status {
        case .online:
            return "Online"
        case .stale:
            return "Stale"
        case .offline:
            return "Offline"
        case .notObserved:
            return "Not observed"
        case .unknown:
            return "Unknown"
        }
    }

    public func statusText(_ status: RuntimeVitalBedStatus) -> String {
        switch status {
        case .online:
            return "Online"
        case .stale:
            return "Stale"
        case .offline:
            return "Offline"
        case .notObserved:
            return "Not observed"
        case .unknown:
            return "Unknown"
        }
    }

    public func statusTone(_ status: RuntimeVitalRecorderStatus) -> StatusTone {
        switch status {
        case .online:
            return .active
        case .stale:
            return .warning
        case .offline, .notObserved, .unknown:
            return .neutral
        }
    }

    public func statusTone(_ status: RuntimeVitalBedStatus) -> StatusTone {
        switch status {
        case .online:
            return .active
        case .stale:
            return .warning
        case .offline, .notObserved, .unknown:
            return .neutral
        }
    }

    public func patientText(_ connected: Bool?) -> String {
        guard let connected else {
            return "Not reported"
        }
        return connected ? "Present" : "Not present"
    }

    public func reportedText(_ value: String?, missing: String) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return missing
        }
        return value
    }

    public func recorderSourceText(_ version: String?) -> String {
        guard let version, !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Not reported"
        }
        return isProductLabRecorder(version: version) ? "Lab" : "Vital Recorder"
    }

    public func isProductLabRecorder(version: String?) -> Bool {
        version == Self.productLabVersion
    }

    public func recorderAnomalyText(_ recorder: RuntimeVitalRecorderRecord) -> String {
        if !recorder.presentInLatestObservation {
            return "History"
        }
        guard recorder.currentAnomalyCount > 0 else {
            return "-"
        }
        return anomalyKindText(recorder.latestAnomalyKind) ?? "\(recorder.currentAnomalyCount)"
    }

    public func bedAnomalyText(_ bed: RuntimeVitalBedRecord) -> String {
        guard bed.currentAnomalyCount > 0 else {
            return "-"
        }
        return anomalyKindText(bed.latestAnomalyKind) ?? "\(bed.currentAnomalyCount)"
    }

    public func anomalyDetailText(
        kind: VitalDBAnomalyKind?,
        severity: VitalDBAnomalySeverity?,
        message: String?,
        count: Int
    ) -> String {
        guard count > 0 else {
            return "None"
        }
        let title = anomalyKindText(kind) ?? "Reported anomaly"
        let severityText = severity.map { " · \($0.rawValue)" } ?? ""
        let reportedMessage = reportedText(message, missing: "")
        let messageText = reportedMessage.isEmpty ? "" : " · \(reportedMessage)"
        return "\(title)\(severityText)\(messageText)"
    }

    public func sortedRecorders(
        _ recorders: [RuntimeVitalRecorderRecord],
        by option: RecorderSortOption
    ) -> [RuntimeVitalRecorderRecord] {
        recorders.sorted { lhs, rhs in
            switch option {
            case .vrcode:
                return compareText(lhs.vrcode, rhs.vrcode, tieBreaker: lhs.vrcode < rhs.vrcode)
            case .lastSeen:
                switch compareReportedTimestamp(lhs.lastSeenAt, rhs.lastSeenAt) {
                case .orderedDescending:
                    return true
                case .orderedAscending:
                    return false
                case .orderedSame:
                    return lhs.vrcode < rhs.vrcode
                }
            case .status:
                let lhsRank = statusRank(lhs.status)
                let rhsRank = statusRank(rhs.status)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.vrcode < rhs.vrcode
            case .bed:
                return compareText(lhs.bedName ?? lhs.bedID, rhs.bedName ?? rhs.bedID, tieBreaker: lhs.vrcode < rhs.vrcode)
            }
        }
    }

    public func bytesPerSecondText(_ value: Double) -> String {
        let boundedValue = max(value, 0)
        if boundedValue < 1, boundedValue > 0 {
            return String(format: "%.2f B/s", boundedValue)
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.includesCount = true
        return "\(formatter.string(fromByteCount: Int64(boundedValue.rounded())))/s"
    }

    private func statusRank(_ status: RuntimeVitalRecorderStatus) -> Int {
        switch status {
        case .online:
            return 0
        case .stale:
            return 1
        case .offline:
            return 2
        case .notObserved:
            return 3
        case .unknown:
            return 4
        }
    }

    private func compareText(_ lhs: String?, _ rhs: String?, tieBreaker: Bool) -> Bool {
        let lhsText = normalizedSortText(lhs)
        let rhsText = normalizedSortText(rhs)
        switch (lhsText, rhsText) {
        case let (lhsText?, rhsText?) where lhsText != rhsText:
            return lhsText < rhsText
        case (.some, .some):
            return tieBreaker
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return tieBreaker
        }
    }

    private func normalizedSortText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private func anomalyKindText(_ kind: VitalDBAnomalyKind?) -> String? {
        guard let kind else {
            return nil
        }
        return kind.rawValue
            .split(separator: "-")
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    private func compareReportedTimestamp(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        let lhsDate = reportedTimestampDate(lhs)
        let rhsDate = reportedTimestampDate(rhs)
        if let lhsDate, let rhsDate {
            if lhsDate == rhsDate {
                return .orderedSame
            }
            return lhsDate > rhsDate ? .orderedDescending : .orderedAscending
        }
        if lhsDate != nil {
            return .orderedDescending
        }
        if rhsDate != nil {
            return .orderedAscending
        }
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs > rhs ? .orderedDescending : .orderedAscending
        case (.some, .some):
            return .orderedSame
        case (.some, nil):
            return .orderedDescending
        case (nil, .some):
            return .orderedAscending
        case (nil, nil):
            return .orderedSame
        }
    }

    private func reportedTimestampDate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
