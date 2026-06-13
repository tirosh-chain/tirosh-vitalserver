import Foundation
import Errors

public struct RuntimeStatusUptimeFormatter {
    public init() {}

    public func formatUptime(
        seconds: Int?,
        startedAt: String?,
        observedAt: String?,
        now: Date
    ) -> String? {
        _ = observedAt
        guard let seconds = seconds ?? liveSeconds(startedAt: startedAt, now: now) else {
            return nil
        }
        return formatDuration(seconds: seconds)
    }

    private func liveSeconds(startedAt: String?, now: Date) -> Int? {
        let liveSeconds = startedAt.flatMap { value in
            parseISODate(value).map { startedAt in
                max(Int(now.timeIntervalSince(startedAt)), 0)
            }
        }
        return liveSeconds
    }

    private func formatDuration(seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        let clock = String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        if days > 0 {
            return "\(days)d \(clock)"
        }
        return clock
    }

    private func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        guard let normalized = normalizedFractionalISODate(value), normalized != value else {
            return nil
        }
        return formatter.date(from: normalized) ?? ISO8601DateFormatter().date(from: normalized)
    }

    private func normalizedFractionalISODate(_ value: String) -> String? {
        guard let dotIndex = value.firstIndex(of: ".") else {
            return nil
        }
        let suffixStart = value[value.index(after: dotIndex)...]
        let fractionEnd = suffixStart.firstIndex { !$0.isNumber } ?? value.endIndex
        let fraction = value[value.index(after: dotIndex)..<fractionEnd]
        guard fraction.count > 3 else {
            return nil
        }
        return String(value[..<value.index(after: dotIndex)] + fraction.prefix(3) + value[fractionEnd...])
    }
}
