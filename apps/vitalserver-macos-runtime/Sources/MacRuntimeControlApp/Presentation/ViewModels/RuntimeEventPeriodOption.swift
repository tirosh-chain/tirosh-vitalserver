import Interfaces

typealias RuntimeEventPeriodOption = Interfaces.RuntimeEventPeriodOption

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
