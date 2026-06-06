import Contracts
import Foundation
import RuntimeControl
import Errors

public struct RuntimeRecorderActivityChartDataBuilder {
    public init() {}

    public func display(
        from timeline: [RuntimeVitalRecorderActivityPoint]?,
        interval: RecorderActivityBucketInterval,
        period: RecorderActivityPeriod,
        readError: String?
    ) -> RuntimeRecorderActivityDisplay {
        if let readError {
            return RuntimeRecorderActivityDisplay(
                state: .readFailed(readError),
                buckets: [],
                latestSample: nil,
                latestBucket: nil,
                latestBucketBytesPerSecond: nil,
                totalPackets: nil
            )
        }
        guard let timeline else {
            return RuntimeRecorderActivityDisplay(
                state: .notReported,
                buckets: [],
                latestSample: nil,
                latestBucket: nil,
                latestBucketBytesPerSecond: nil,
                totalPackets: nil
            )
        }
        guard !timeline.isEmpty else {
            return RuntimeRecorderActivityDisplay(
                state: .emptyTimeline,
                buckets: [],
                latestSample: nil,
                latestBucket: nil,
                latestBucketBytesPerSecond: nil,
                totalPackets: 0
            )
        }

        let latestSample = timeline.max {
            let lhs = RuntimeRecorderActivityDateParser.date(from: $0.observedAt) ?? .distantPast
            let rhs = RuntimeRecorderActivityDateParser.date(from: $1.observedAt) ?? .distantPast
            return lhs < rhs
        }
        let buckets = displayActivityBuckets(
            activityBuckets(from: timeline, interval: interval),
            interval: interval,
            period: period
        )
        guard !buckets.isEmpty else {
            return RuntimeRecorderActivityDisplay(
                state: .noBucketsInPeriod,
                buckets: [],
                latestSample: latestSample,
                latestBucket: nil,
                latestBucketBytesPerSecond: nil,
                totalPackets: 0
            )
        }

        let latestBucket = buckets.last(where: { $0.messageCount > 0 }) ?? buckets.last
        return RuntimeRecorderActivityDisplay(
            state: .available,
            buckets: buckets,
            latestSample: latestSample,
            latestBucket: latestBucket,
            latestBucketBytesPerSecond: latestBucket.map {
                Double($0.byteCount) / Double(max($0.bucketSeconds, 1))
            },
            totalPackets: buckets.reduce(0) { $0 + $1.messageCount }
        )
    }

    public func activityBuckets(
        from points: [RuntimeVitalRecorderActivityPoint],
        interval: RecorderActivityBucketInterval
    ) -> [RecorderActivityChartBucket] {
        let rawBuckets = stableActivityBuckets(from: points)
        if rawBuckets.isEmpty {
            return points.map {
                RecorderActivityChartBucket(
                    bucketStartedAt: $0.observedAt,
                    bucketSeconds: interval.seconds,
                    messageCount: $0.messageCount,
                    byteCount: $0.byteCount,
                    roomCount: $0.roomCount
                )
            }
        }

        if interval == .oneMinute {
            return rawBuckets
        }

        var builders: [String: RecorderActivityChartBucketBuilder] = [:]
        for bucket in rawBuckets {
            let startedAt = normalizedBucketStart(
                bucket.bucketStartedAt,
                intervalSeconds: interval.seconds
            )
            var builder = builders[startedAt] ?? RecorderActivityChartBucketBuilder(
                bucketStartedAt: startedAt,
                bucketSeconds: interval.seconds
            )
            builder.add(bucket)
            builders[startedAt] = builder
        }
        return builders.values
            .map(\.bucket)
            .sorted { $0.bucketStartedAt < $1.bucketStartedAt }
    }

    public func displayActivityBuckets(
        _ buckets: [RecorderActivityChartBucket],
        interval: RecorderActivityBucketInterval,
        period: RecorderActivityPeriod
    ) -> [RecorderActivityChartBucket] {
        guard let periodSeconds = period.interval,
              let latest = buckets.compactMap({ RuntimeRecorderActivityDateParser.date(from: $0.bucketStartedAt) }).max() else {
            return buckets
        }
        let threshold = latest.addingTimeInterval(-periodSeconds)
        let filtered = buckets.filter { bucket in
            guard let date = RuntimeRecorderActivityDateParser.date(from: bucket.bucketStartedAt) else {
                return true
            }
            return date >= threshold
        }
        return filledActivityBuckets(
            filtered,
            start: threshold,
            end: latest,
            interval: interval
        )
    }

    private func stableActivityBuckets(
        from points: [RuntimeVitalRecorderActivityPoint]
    ) -> [RecorderActivityChartBucket] {
        var buckets: [String: RecorderActivityChartBucket] = [:]
        for point in points {
            for bucket in point.buckets {
                let stableBucket = RecorderActivityChartBucket(bucket)
                buckets[stableBucket.id] = buckets[stableBucket.id]
                    .map { $0.keepingLargestCounts(stableBucket) } ?? stableBucket
            }
        }
        return buckets.values.sorted { $0.bucketStartedAt < $1.bucketStartedAt }
    }

    private func filledActivityBuckets(
        _ buckets: [RecorderActivityChartBucket],
        start: Date,
        end: Date,
        interval: RecorderActivityBucketInterval
    ) -> [RecorderActivityChartBucket] {
        guard !buckets.isEmpty else {
            return []
        }
        let intervalSeconds = interval.seconds
        let startTimestamp = floor(start.timeIntervalSince1970 / Double(intervalSeconds)) * Double(intervalSeconds)
        let endTimestamp = floor(end.timeIntervalSince1970 / Double(intervalSeconds)) * Double(intervalSeconds)
        var existing: [String: RecorderActivityChartBucket] = [:]
        for bucket in buckets {
            let key = normalizedBucketStart(bucket.bucketStartedAt, intervalSeconds: intervalSeconds)
            let normalizedBucket = RecorderActivityChartBucket(
                bucketStartedAt: key,
                bucketSeconds: intervalSeconds,
                messageCount: bucket.messageCount,
                byteCount: bucket.byteCount,
                roomCount: bucket.roomCount
            )
            existing[key] = existing[key].map { $0.merging(normalizedBucket) } ?? normalizedBucket
        }

        var result: [RecorderActivityChartBucket] = []
        var cursor = startTimestamp
        while cursor <= endTimestamp {
            let key = RuntimeRecorderActivityDateParser.string(from: Date(timeIntervalSince1970: cursor))
            result.append(existing[key] ?? RecorderActivityChartBucket(
                bucketStartedAt: key,
                bucketSeconds: intervalSeconds,
                messageCount: 0,
                byteCount: 0,
                roomCount: 0
            ))
            cursor += Double(intervalSeconds)
        }
        return result
    }

    private func normalizedBucketStart(_ timestamp: String, intervalSeconds: Int) -> String {
        guard let date = RuntimeRecorderActivityDateParser.date(from: timestamp) else {
            return timestamp
        }
        let bucketTimestamp = floor(date.timeIntervalSince1970 / Double(intervalSeconds)) * Double(intervalSeconds)
        return RuntimeRecorderActivityDateParser.string(from: Date(timeIntervalSince1970: bucketTimestamp))
    }
}

public struct RuntimeRecorderActivityDisplay {
    public let state: RuntimeRecorderActivityDisplayState
    public let buckets: [RecorderActivityChartBucket]
    public let latestSample: RuntimeVitalRecorderActivityPoint?
    public let latestBucket: RecorderActivityChartBucket?
    public let latestBucketBytesPerSecond: Double?
    public let totalPackets: Int?

    public init(
        state: RuntimeRecorderActivityDisplayState,
        buckets: [RecorderActivityChartBucket],
        latestSample: RuntimeVitalRecorderActivityPoint?,
        latestBucket: RecorderActivityChartBucket?,
        latestBucketBytesPerSecond: Double?,
        totalPackets: Int?
    ) {
        self.state = state
        self.buckets = buckets
        self.latestSample = latestSample
        self.latestBucket = latestBucket
        self.latestBucketBytesPerSecond = latestBucketBytesPerSecond
        self.totalPackets = totalPackets
    }
}

public enum RuntimeRecorderActivityDisplayState: Equatable {
    case available
    case notReported
    case emptyTimeline
    case noBucketsInPeriod
    case readFailed(String)

    public var showsControls: Bool {
        switch self {
        case .available, .emptyTimeline, .noBucketsInPeriod:
            return true
        case .notReported, .readFailed:
            return false
        }
    }
}

public enum RecorderActivityBucketInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300

    public var id: Int { rawValue }
    public var seconds: Int { rawValue }
}

public enum RecorderActivityPeriod: String, CaseIterable, Identifiable {
    case last15Minutes = "last-15-minutes"
    case lastHour = "last-hour"
    case last6Hours = "last-6-hours"
    case last24Hours = "last-24-hours"
    case all

    public var id: String { rawValue }

    public var interval: TimeInterval? {
        switch self {
        case .last15Minutes:
            return 15 * 60
        case .lastHour:
            return 60 * 60
        case .last6Hours:
            return 6 * 60 * 60
        case .last24Hours:
            return 24 * 60 * 60
        case .all:
            return nil
        }
    }
}

public struct RecorderActivityChartBucket: Identifiable {
    public var id: String { "\(bucketStartedAt)-\(bucketSeconds)" }
    public let bucketStartedAt: String
    public let bucketSeconds: Int
    public let messageCount: Int
    public let byteCount: Int
    public let roomCount: Int

    public init(_ bucket: VitalDBRecorderActivityBucket) {
        self.init(
            bucketStartedAt: bucket.bucketStartedAt,
            bucketSeconds: bucket.bucketSeconds,
            messageCount: bucket.messageCount,
            byteCount: bucket.byteCount,
            roomCount: bucket.roomCount
        )
    }

    public init(
        bucketStartedAt: String,
        bucketSeconds: Int,
        messageCount: Int,
        byteCount: Int,
        roomCount: Int
    ) {
        self.bucketStartedAt = bucketStartedAt
        self.bucketSeconds = bucketSeconds
        self.messageCount = messageCount
        self.byteCount = byteCount
        self.roomCount = roomCount
    }

    public func merging(_ other: RecorderActivityChartBucket) -> RecorderActivityChartBucket {
        RecorderActivityChartBucket(
            bucketStartedAt: bucketStartedAt,
            bucketSeconds: bucketSeconds,
            messageCount: messageCount + other.messageCount,
            byteCount: byteCount + other.byteCount,
            roomCount: max(roomCount, other.roomCount)
        )
    }

    public func keepingLargestCounts(_ other: RecorderActivityChartBucket) -> RecorderActivityChartBucket {
        RecorderActivityChartBucket(
            bucketStartedAt: bucketStartedAt,
            bucketSeconds: bucketSeconds,
            messageCount: max(messageCount, other.messageCount),
            byteCount: max(byteCount, other.byteCount),
            roomCount: max(roomCount, other.roomCount)
        )
    }
}

public struct RecorderActivityChartBucketBuilder {
    public let bucketStartedAt: String
    public let bucketSeconds: Int
    public var messageCount = 0
    public var byteCount = 0
    public var roomCount = 0

    public init(bucketStartedAt: String, bucketSeconds: Int) {
        self.bucketStartedAt = bucketStartedAt
        self.bucketSeconds = bucketSeconds
    }

    public mutating func add(_ bucket: RecorderActivityChartBucket) {
        messageCount += bucket.messageCount
        byteCount += bucket.byteCount
        roomCount += bucket.roomCount
    }

    public var bucket: RecorderActivityChartBucket {
        RecorderActivityChartBucket(
            bucketStartedAt: bucketStartedAt,
            bucketSeconds: bucketSeconds,
            messageCount: messageCount,
            byteCount: byteCount,
            roomCount: roomCount
        )
    }
}

public enum RuntimeRecorderActivityDateParser {
    public static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)
    }

    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}

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
