import Foundation

public struct RuntimeLogArchiveRetentionConfiguration: Equatable, Sendable {
    public static let defaultRetentionDays = 14
    public static let maximumRetentionDays = 30
    public static let defaultMaximumBytes: UInt64 = 1_073_741_824

    public let retentionDays: Int
    public let maximumBytes: UInt64

    public init(
        retentionDays: Int = Self.defaultRetentionDays,
        maximumBytes: UInt64 = Self.defaultMaximumBytes
    ) {
        self.retentionDays = retentionDays
        self.maximumBytes = maximumBytes
    }
}

public struct RuntimeLogArchiveDay: Equatable, Sendable {
    public let url: URL
    public let day: Date
    public let sizeBytes: UInt64

    public init(url: URL, day: Date, sizeBytes: UInt64) {
        self.url = url
        self.day = day
        self.sizeBytes = sizeBytes
    }
}

public enum RuntimeLogArchiveRetentionPolicy {
    public static func isValidRetentionDays(_ days: Int) -> Bool {
        (1...RuntimeLogArchiveRetentionConfiguration.maximumRetentionDays).contains(days)
    }

    public static func isValidMaximumBytes(_ bytes: UInt64) -> Bool {
        bytes > 0
    }

    public static func pruneCandidates(
        archives: [RuntimeLogArchiveDay],
        configuration: RuntimeLogArchiveRetentionConfiguration,
        now: Date,
        calendar: Calendar = .current
    ) -> [URL] {
        let sorted = archives.sorted {
            if $0.day == $1.day {
                return $0.url.path < $1.url.path
            }
            return $0.day < $1.day
        }
        let cutoff = calendar.date(
            byAdding: .day,
            value: -configuration.retentionDays,
            to: calendar.startOfDay(for: now)
        ) ?? calendar.startOfDay(for: now)

        var removed: [RuntimeLogArchiveDay] = []
        var retained: [RuntimeLogArchiveDay] = []
        for archive in sorted {
            if archive.day < cutoff {
                removed.append(archive)
            } else {
                retained.append(archive)
            }
        }

        var retainedSize = retained.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        for archive in retained where retainedSize > configuration.maximumBytes {
            removed.append(archive)
            retainedSize = retainedSize > archive.sizeBytes ? retainedSize - archive.sizeBytes : 0
        }
        return removed.map(\.url)
    }
}
