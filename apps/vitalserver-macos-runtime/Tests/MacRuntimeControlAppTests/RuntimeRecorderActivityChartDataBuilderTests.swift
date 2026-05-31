import Contracts
@testable import MacRuntimeControlApp
import RuntimeControl
import XCTest

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
}
