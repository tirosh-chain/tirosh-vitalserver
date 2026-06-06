import Foundation
import Interfaces

typealias RuntimeRecorderActivityChartDataBuilder = Interfaces.RuntimeRecorderActivityChartDataBuilder
typealias RuntimeRecorderActivityDisplay = Interfaces.RuntimeRecorderActivityDisplay
typealias RuntimeRecorderActivityDisplayState = Interfaces.RuntimeRecorderActivityDisplayState
typealias RecorderActivityBucketInterval = Interfaces.RecorderActivityBucketInterval
typealias RecorderActivityPeriod = Interfaces.RecorderActivityPeriod
typealias RecorderActivityChartBucket = Interfaces.RecorderActivityChartBucket
typealias RecorderActivityChartBucketBuilder = Interfaces.RecorderActivityChartBucketBuilder
typealias RuntimeRecorderActivityDateParser = Interfaces.RuntimeRecorderActivityDateParser

extension RecorderActivityBucketInterval {
    var title: String {
        switch self {
        case .oneMinute:
            return "1 min"
        case .fiveMinutes:
            return "5 min"
        }
    }
}

extension RecorderActivityPeriod {
    var title: String {
        switch self {
        case .last15Minutes:
            return "Last 15 min"
        case .lastHour:
            return "Last hour"
        case .last6Hours:
            return "Last 6 hours"
        case .last24Hours:
            return "Last 24 hours"
        case .all:
            return "All"
        }
    }
}

extension RuntimeRecorderActivityDateParser {
    static func axisText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
