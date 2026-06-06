import Foundation
import Errors

public enum RuntimeEventPeriodOption: String, CaseIterable, Identifiable, Sendable {
    case last15Minutes = "last-15-minutes"
    case lastHour = "last-hour"
    case last6Hours = "last-6-hours"
    case last24Hours = "last-24-hours"
    case last7Days = "last-7-days"
    case all

    public var id: String { rawValue }

    public func sinceTimestamp(now: Date = Date()) -> String? {
        guard let interval else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: now.addingTimeInterval(-interval))
    }

    private var interval: TimeInterval? {
        switch self {
        case .last15Minutes:
            return 15 * 60
        case .lastHour:
            return 60 * 60
        case .last6Hours:
            return 6 * 60 * 60
        case .last24Hours:
            return 24 * 60 * 60
        case .last7Days:
            return 7 * 24 * 60 * 60
        case .all:
            return nil
        }
    }
}

extension RuntimeEventPeriodOption {
    var title: String {
        switch self {
        case .last15Minutes:
            return "Last 15 minutes"
        case .lastHour:
            return "Last hour"
        case .last6Hours:
            return "Last 6 hours"
        case .last24Hours:
            return "Last 24 hours"
        case .last7Days:
            return "Last 7 days"
        case .all:
            return AppConstants.StatusText.allRuntimeEvents
        }
    }
}
