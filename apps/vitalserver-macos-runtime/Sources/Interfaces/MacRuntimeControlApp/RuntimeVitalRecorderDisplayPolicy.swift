import Foundation
import RuntimeControl

public struct RuntimeVitalRecorderDisplayPolicy {
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
            return "Patient connection not reported"
        }
        return connected ? "Connected" : "Not connected"
    }

    public func reportedText(_ value: String?, missing: String) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return missing
        }
        return value
    }

    public func recorderAnomalyText(_ recorder: RuntimeVitalRecorderRecord) -> String {
        if !recorder.presentInLatestObservation {
            return "History"
        }
        return recorder.currentAnomalyCount == 0 ? "-" : "\(recorder.currentAnomalyCount)"
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
}
