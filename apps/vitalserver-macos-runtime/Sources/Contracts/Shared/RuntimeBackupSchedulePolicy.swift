import Foundation

public enum RuntimeBackupSchedulePolicy {
    public static let maximumRetentionCount = 30

    public static func isValidTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 2,
              parts[1].count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    public static func hasUniqueTimes(_ values: [String]) -> Bool {
        Set(values).count == values.count
    }

    public static func isValidSchedule(_ values: [String]) -> Bool {
        !values.isEmpty
            && values.allSatisfy(isValidTime)
            && hasUniqueTimes(values)
    }

    public static func isValidRetentionCount(_ count: Int) -> Bool {
        (1...maximumRetentionCount).contains(count)
    }

    public static func normalizedTimes(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    public static func scheduledSlotIdentifier(
        now: Date,
        scheduleTimes: [String],
        calendar: Calendar = Calendar.current
    ) -> String? {
        let time = timeString(now: now, calendar: calendar)
        guard scheduleTimes.contains(time) else {
            return nil
        }
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return nil
        }
        return String(format: "%04d-%02d-%02dT%@", year, month, day, time)
    }

    private static func timeString(now: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
