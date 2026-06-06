import Contracts
@testable import MacControlPanelHost
import RuntimeControl
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeRecorderActivityChartDataBuilderTests: XCTestCase {
    func testActivityBucketsUsesStableBucketCountsWhenPresent() {
        let builder = RuntimeRecorderActivityChartDataBuilder()
        let points = [
            RuntimeVitalRecorderActivityPoint(
                observedAt: "2026-05-30T00:00:30Z",
                windowSeconds: 60,
                messageCount: 1,
                byteCount: 2,
                roomCount: 1,
                messagesPerSecond: 1,
                bytesPerSecond: 2,
                buckets: [
                    VitalDBRecorderActivityBucket(
                        bucketStartedAt: "2026-05-30T00:00:00Z",
                        bucketSeconds: 60,
                        messageCount: 3,
                        byteCount: 30,
                        roomCount: 1
                    )
                ]
            ),
            RuntimeVitalRecorderActivityPoint(
                observedAt: "2026-05-30T00:00:50Z",
                windowSeconds: 60,
                messageCount: 2,
                byteCount: 4,
                roomCount: 2,
                messagesPerSecond: 2,
                bytesPerSecond: 4,
                buckets: [
                    VitalDBRecorderActivityBucket(
                        bucketStartedAt: "2026-05-30T00:00:00Z",
                        bucketSeconds: 60,
                        messageCount: 5,
                        byteCount: 20,
                        roomCount: 2
                    )
                ]
            )
        ]

        let buckets = builder.activityBuckets(from: points, interval: .oneMinute)

        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets.first?.messageCount, 5)
        XCTAssertEqual(buckets.first?.byteCount, 30)
        XCTAssertEqual(buckets.first?.roomCount, 2)
    }

    func testDisplayActivityBucketsFillsMissingBucketsInSelectedPeriod() {
        let builder = RuntimeRecorderActivityChartDataBuilder()
        let buckets = [
            RecorderActivityChartBucket(
                bucketStartedAt: "2026-05-30T00:00:00Z",
                bucketSeconds: 300,
                messageCount: 3,
                byteCount: 30,
                roomCount: 1
            ),
            RecorderActivityChartBucket(
                bucketStartedAt: "2026-05-30T00:10:00Z",
                bucketSeconds: 300,
                messageCount: 7,
                byteCount: 70,
                roomCount: 2
            )
        ]

        let displayed = builder.displayActivityBuckets(
            buckets,
            interval: .fiveMinutes,
            period: .last15Minutes
        )

        XCTAssertEqual(displayed.map(\.bucketStartedAt), [
            "2026-05-29T23:55:00Z",
            "2026-05-30T00:00:00Z",
            "2026-05-30T00:05:00Z",
            "2026-05-30T00:10:00Z",
        ])
        XCTAssertEqual(displayed.map(\.messageCount), [0, 3, 0, 7])
    }

    func testActivityDisplayUsesLatestTimestampAndOwnsSummaryMetrics() throws {
        let builder = RuntimeRecorderActivityChartDataBuilder()
        let display = builder.display(
            from: [
                activityPoint(observedAt: "2026-05-30T00:10:00Z", messageCount: 4),
                activityPoint(observedAt: "2026-05-30T00:05:00Z", messageCount: 9),
            ],
            interval: .oneMinute,
            period: .lastHour,
            readError: nil
        )

        XCTAssertEqual(display.state, .available)
        XCTAssertEqual(display.latestSample?.observedAt, "2026-05-30T00:10:00Z")
        XCTAssertEqual(display.totalPackets, 13)
        XCTAssertEqual(display.latestBucket?.messageCount, 4)
        let latestBucketBytesPerSecond = try XCTUnwrap(display.latestBucketBytesPerSecond)
        XCTAssertEqual(latestBucketBytesPerSecond, 40.0 / 60.0, accuracy: 0.001)
    }

    func testActivityDisplayKeepsReadFailureDistinctFromEmptyActivity() {
        let builder = RuntimeRecorderActivityChartDataBuilder()
        let display = builder.display(
            from: [],
            interval: .oneMinute,
            period: .lastHour,
            readError: "activity projection denied"
        )

        XCTAssertEqual(display.state, .readFailed("activity projection denied"))
        XCTAssertTrue(display.buckets.isEmpty)
        XCTAssertNil(display.totalPackets)
    }

    private func activityPoint(
        observedAt: String,
        messageCount: Int
    ) -> RuntimeVitalRecorderActivityPoint {
        RuntimeVitalRecorderActivityPoint(
            observedAt: observedAt,
            windowSeconds: 60,
            messageCount: messageCount,
            byteCount: messageCount * 10,
            roomCount: 1,
            messagesPerSecond: Double(messageCount),
            bytesPerSecond: Double(messageCount * 10),
            buckets: [
                VitalDBRecorderActivityBucket(
                    bucketStartedAt: observedAt,
                    bucketSeconds: 60,
                    messageCount: messageCount,
                    byteCount: messageCount * 10,
                    roomCount: 1
                )
            ]
        )
    }
}
