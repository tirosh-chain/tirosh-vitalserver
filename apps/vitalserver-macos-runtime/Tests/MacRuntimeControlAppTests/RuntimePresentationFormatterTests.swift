import Contracts
import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

final class RuntimePresentationFormatterTests: XCTestCase {
    private let formatter = RuntimePresentationFormatter()

    func testSelectedBundleConfirmationIncludesBundlePathWhenPresent() {
        XCTAssertEqual(
            formatter.selectedBundleConfirmation(bundlePath: "/tmp/update-bundle.tar.gz"),
            "\(AppConstants.StatusText.updateBundleConfirmation)\n\n/tmp/update-bundle.tar.gz"
        )
    }

    func testSelectedBundleConfirmationOmitsEmptyBundlePath() {
        XCTAssertEqual(
            formatter.selectedBundleConfirmation(bundlePath: ""),
            AppConstants.StatusText.updateBundleConfirmation
        )
    }

    func testApplySettingsConfirmationIncludesOperatorVisibleSettings() {
        var settings = RuntimeSettings()
        settings.proxyPort = 18080
        settings.publicHost = ""
        settings.publicPort = 443
        settings.networkMode = RuntimeNetworkMode.shared
        settings.diskGiB = 128
        settings.vitalFilesDirectory = "/Users/test/Vital Files"
        settings.redisBackupRetentionCount = 20
        settings.autoRecoveryEnabled = false
        settings.restartAfterSave = true

        let confirmation = formatter.applySettingsConfirmation(settings: settings)

        XCTAssertTrue(confirmation.contains("Proxy port: 18080"))
        XCTAssertTrue(confirmation.contains("Public host: (same host)"))
        XCTAssertTrue(confirmation.contains("Public port: 443"))
        XCTAssertTrue(confirmation.contains("Network mode: shared"))
        XCTAssertTrue(confirmation.contains("Disk size: 128 GiB"))
        XCTAssertTrue(confirmation.contains("Vital files directory: /Users/test/Vital Files"))
        XCTAssertTrue(confirmation.contains("Redis backup retention: 20 archives"))
        XCTAssertTrue(confirmation.contains("Automatic recovery: false"))
        XCTAssertTrue(confirmation.contains("Restart services: true"))
    }

    func testLogExportDefaultNameUsesStableTimestampFormat() {
        let date = Date(timeIntervalSince1970: 1_778_979_845)

        XCTAssertTrue(formatter.logExportDefaultName(date: date).hasPrefix("vitalserver-logs-"))
        XCTAssertTrue(formatter.logExportDefaultName(date: date).hasSuffix(".zip"))
        XCTAssertEqual(formatter.logExportDefaultName(date: date).count, "vitalserver-logs-20260515-123045.zip".count)
    }

    func testBackupSizeTextFormatsKnownAndUnknownSizes() {
        XCTAssertEqual(
            formatter.backupSizeText(RuntimeBackup(path: "/tmp/backup", sizeBytes: nil)),
            AppConstants.StatusText.unknown
        )
        XCTAssertEqual(
            formatter.backupSizeText(RuntimeBackup(path: "/tmp/backup", sizeBytes: 1_073_741_824)),
            "1.0 GiB"
        )
    }

    func testStatusDisplayMessageIncludesFailureReasons() {
        let status = RuntimeStatus(
            statusMessage: "runtime is degraded",
            failureReasons: [.hostProxyHTTP("503"), .guestHTTP("000")]
        )

        XCTAssertEqual(
            formatter.statusDisplayMessage(status),
            "runtime is degraded\nFailure reasons: host-proxy-http-503, guest-http-000"
        )
    }

    func testProgressDisplayMessageUsesTypedStepAndStatus() {
        let progress = RuntimeProgressDocument(
            operation: .applyBundle,
            phase: .running,
            step: .replaceRootfsBase,
            stepStatus: .started,
            message: "replacing rootfs",
            reasonCodes: [],
            startedAt: nil,
            updatedAt: "2026-05-23T09:00:00Z"
        )
        let status = RuntimeStatus(progress: progress)

        XCTAssertEqual(formatter.progressDisplayMessage(status), "Running: Replace Rootfs Base")
    }

    func testSystemTimeTextFormatsISO8601TimestampInRequestedTimeZone() {
        let timeZone = TimeZone(identifier: "Asia/Seoul")!

        XCTAssertEqual(
            formatter.systemTimeText("2026-05-21T12:00:00Z", timeZone: timeZone),
            "2026-05-21 21:00:00 GMT+9"
        )
    }

    func testSystemTimeTextKeepsUnparseableTimestamp() {
        XCTAssertEqual(
            formatter.systemTimeText("not-a-date", timeZone: TimeZone(secondsFromGMT: 0)!),
            "not-a-date"
        )
    }
}
