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

    func testActivityDisplayKeepsInvalidTimestampDistinctFromOldActivity() {
        let builder = RuntimeRecorderActivityChartDataBuilder()
        let display = builder.display(
            from: [
                activityPoint(observedAt: "not-a-date", messageCount: 4),
                activityPoint(observedAt: "2026-05-30T00:05:00Z", messageCount: 9),
            ],
            interval: .oneMinute,
            period: .lastHour,
            readError: nil
        )

        XCTAssertEqual(display.state, .invalidTimeline("not-a-date"))
        XCTAssertFalse(display.state.showsControls)
        XCTAssertTrue(display.buckets.isEmpty)
        XCTAssertNil(display.latestSample)
        XCTAssertNil(display.totalPackets)
    }

    func testAllSamplesUsesTwelveHourWindowsForOneAndFiveMinuteBuckets() throws {
        let builder = RuntimeRecorderActivityChartDataBuilder()
        let points = [
            activityPoint(
                observedAt: "2026-05-30T13:00:00Z",
                windowSeconds: 60,
                buckets: activityBuckets(
                    startedAt: "2026-05-30T00:00:00Z",
                    count: 13 * 60,
                    intervalSeconds: 60
                )
            )
        ]

        let oneMinuteDisplay = builder.display(
            from: points,
            interval: .oneMinute,
            period: .all,
            readError: nil
        )

        let oneMinuteWindow = try XCTUnwrap(oneMinuteDisplay.allSamplesWindow)
        XCTAssertEqual(oneMinuteWindow.pageCount, 2)
        XCTAssertEqual(oneMinuteWindow.pageIndex, 1)
        XCTAssertEqual(oneMinuteWindow.buckets.count, 60)
        XCTAssertEqual(oneMinuteWindow.windowStartedAt, "2026-05-30T12:00:00Z")
        XCTAssertEqual(oneMinuteWindow.windowEndedAt, "2026-05-30T13:00:00Z")

        let firstOneMinutePage = builder.display(
            from: points,
            interval: .oneMinute,
            period: .all,
            allSamplesPageIndex: 0,
            readError: nil
        )
        XCTAssertEqual(firstOneMinutePage.allSamplesWindow?.buckets.count, 12 * 60)
        XCTAssertEqual(firstOneMinutePage.allSamplesWindow?.windowStartedAt, "2026-05-30T00:00:00Z")
        XCTAssertEqual(firstOneMinutePage.allSamplesWindow?.windowEndedAt, "2026-05-30T12:00:00Z")

        let fiveMinuteDisplay = builder.display(
            from: points,
            interval: .fiveMinutes,
            period: .all,
            readError: nil
        )

        let fiveMinuteWindow = try XCTUnwrap(fiveMinuteDisplay.allSamplesWindow)
        XCTAssertEqual(fiveMinuteWindow.pageCount, 2)
        XCTAssertEqual(fiveMinuteWindow.pageIndex, 1)
        XCTAssertEqual(fiveMinuteWindow.buckets.count, 12)
        XCTAssertEqual(fiveMinuteWindow.windowStartedAt, "2026-05-30T12:00:00Z")
        XCTAssertEqual(fiveMinuteWindow.windowEndedAt, "2026-05-30T13:00:00Z")
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

    private func activityPoint(
        observedAt: String,
        windowSeconds: Int,
        buckets: [VitalDBRecorderActivityBucket]
    ) -> RuntimeVitalRecorderActivityPoint {
        RuntimeVitalRecorderActivityPoint(
            observedAt: observedAt,
            windowSeconds: windowSeconds,
            messageCount: buckets.reduce(0) { $0 + $1.messageCount },
            byteCount: buckets.reduce(0) { $0 + $1.byteCount },
            roomCount: buckets.map(\.roomCount).max() ?? 0,
            messagesPerSecond: 0,
            bytesPerSecond: 0,
            buckets: buckets
        )
    }

    private func activityBuckets(
        startedAt: String,
        count: Int,
        intervalSeconds: Int
    ) -> [VitalDBRecorderActivityBucket] {
        let startDate = RuntimeRecorderActivityDateParser.date(from: startedAt)!
        return (0..<count).map { index in
            VitalDBRecorderActivityBucket(
                bucketStartedAt: RuntimeRecorderActivityDateParser.string(
                    from: startDate.addingTimeInterval(Double(index * intervalSeconds))
                ),
                bucketSeconds: intervalSeconds,
                messageCount: index + 1,
                byteCount: (index + 1) * 10,
                roomCount: 1
            )
        }
    }
}
