import Contracts
import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimePresentationFormatterTests: XCTestCase {
    private let formatter = RuntimePresentationFormatter()

    func testSelectedBundleConfirmationIncludesBundlePathWhenPresent() {
        XCTAssertEqual(
            formatter.selectedBundleConfirmation(bundlePath: "/tmp/update-bundle.tar.gz"),
            "\(AppConstants.StatusText.updateBundleConfirmation)\n\n/tmp/update-bundle.tar.gz"
        )
    }

    func testSelectedBundleConfirmationOmitsMissingBundlePath() {
        XCTAssertEqual(
            formatter.selectedBundleConfirmation(bundlePath: nil),
            AppConstants.StatusText.updateBundleConfirmation
        )
    }

    func testApplySettingsConfirmationIncludesOperatorVisibleSettings() {
        var settings = RuntimeSettings()
        settings.proxyPort = 18080
        settings.vitalServerURL = "https://vitaldb.tirosh.ai/"
        settings.remoteConsoleURL = "https://console.tirosh.ai/"
        settings.networkMode = RuntimeNetworkMode.shared
        settings.diskGiB = 128
        settings.vitalFilesDirectory = "/Users/test/Vital Files"
        settings.backupRetentionCount = 20
        settings.autoRecoveryEnabled = false
        settings.preventSystemSleep = false
        settings.restartAfterSave = true

        let confirmation = formatter.applySettingsConfirmation(settings: settings)

        XCTAssertTrue(confirmation.contains("Proxy port: 18080"))
        XCTAssertTrue(confirmation.contains("VitalServer URL: https://vitaldb.tirosh.ai/"))
        XCTAssertTrue(confirmation.contains("Remote Console URL: https://console.tirosh.ai/"))
        XCTAssertTrue(confirmation.contains("Network mode: shared"))
        XCTAssertTrue(confirmation.contains("Disk size: 128 GiB"))
        XCTAssertTrue(confirmation.contains("Vital files directory: /Users/test/Vital Files"))
        XCTAssertTrue(confirmation.contains("VitalServer Helper backup retention: 20 archives"))
        XCTAssertTrue(confirmation.contains("Automatic recovery: false"))
        XCTAssertTrue(confirmation.contains("\(AppConstants.Labels.preventSystemSleep): false"))
        XCTAssertTrue(confirmation.contains("Restart VM runtime when required: true"))
    }

    func testStatusServiceURLsPreserveMissingAdvertisedURLsAsUnknownAndClosed() {
        var settings = RuntimeSettings()
        settings.proxyPort = 18080
        settings.runtimeControlPort = 19090
        settings.vitalServerURL = ""
        settings.remoteConsoleURL = ""

        XCTAssertEqual(
            formatter.vitalServerStatusURL(settings: settings),
            RuntimePresentationFormatter.ServiceURLPresentation(
                displayURL: AppConstants.StatusText.unknown,
                openURL: nil
            )
        )
        XCTAssertEqual(
            formatter.remoteConsoleStatusURL(settings: settings),
            RuntimePresentationFormatter.ServiceURLPresentation(
                displayURL: AppConstants.StatusText.unknown,
                openURL: nil
            )
        )
    }

    func testStatusServiceURLsUseExplicitAdvertisedURLsForDisplayAndOpen() {
        var settings = RuntimeSettings()
        settings.vitalServerURL = " https://vitaldb.tirosh.ai/ "
        settings.remoteConsoleURL = " https://console.tirosh.ai/ "

        XCTAssertEqual(
            formatter.vitalServerStatusURL(settings: settings),
            RuntimePresentationFormatter.ServiceURLPresentation(
                displayURL: "https://vitaldb.tirosh.ai/",
                openURL: "https://vitaldb.tirosh.ai/"
            )
        )
        XCTAssertEqual(
            formatter.remoteConsoleStatusURL(settings: settings),
            RuntimePresentationFormatter.ServiceURLPresentation(
                displayURL: "https://console.tirosh.ai/",
                openURL: "https://console.tirosh.ai/"
            )
        )
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
        let status = platformState(
            failureReasons: [.hostProxyHTTP("503"), .guestHTTP("000")]
        )

        XCTAssertEqual(
            formatter.statusDisplayMessage(status),
            "Failure reasons: Host proxy HTTP 503 (Restart host proxy service), Guest HTTP 000 (Wait for guest readiness)"
        )
    }

    func testUpdateOperationDisplayMessageUsesOperationStateWhenStatusProgressExists() {
        let status = platformState(runtimeState: .updating)
        let operationState = PlatformOperationState(
            activeOperation: .applyBundle,
            install: .unavailable(),
            stableUpdate: .loaded(stableUpdateJournal(state: .running))
        )

        XCTAssertTrue(formatter.updateOperationInProgress(operationState))
        XCTAssertEqual(
            formatter.updateOperationDisplayMessage(status, operationState: operationState),
            "Stable update running"
        )
    }

    func testCompletedUpdateProgressIsNotRestoredAsActive() {
        let status = platformState(runtimeState: .healthy)

        let operationState = PlatformOperationState(
            activeOperation: nil,
            install: .unavailable(),
            stableUpdate: .missing()
        )

        XCTAssertFalse(formatter.updateOperationInProgress(operationState))
        XCTAssertNil(formatter.updateOperationDisplayMessage(status, operationState: operationState))
    }

    func testUpdateOperationDisplayMessageUsesOperationStateResource() {
        let status = platformState(runtimeState: .healthy)
        let operationState = PlatformOperationState(
            activeOperation: .applyBundle,
            install: .unavailable(),
            stableUpdate: .loaded(stableUpdateJournal(state: .handoffPending))
        )

        XCTAssertTrue(formatter.updateOperationInProgress(operationState))
        XCTAssertEqual(
            formatter.updateOperationDisplayMessage(status, operationState: operationState),
            "Stable update handoff pending"
        )
    }

    func testUpdateOperationDisplayMessageDoesNotInferFromLegacyStatusOperation() {
        let status = platformState(
            runtimeState: .updating
        )
        let operationState = PlatformOperationState(
            activeOperation: nil,
            install: .unavailable(),
            stableUpdate: .missing()
        )

        XCTAssertFalse(formatter.updateOperationInProgress(operationState))
        XCTAssertNil(formatter.updateOperationDisplayMessage(status, operationState: operationState))
    }

    func testUpdateOperationDisplayMessagePreservesJournalReadFailure() {
        let status = platformState(runtimeState: .healthy)
        let operationState = PlatformOperationState(
            activeOperation: .applyBundle,
            install: .unavailable(),
            stableUpdate: .failed(readError: "SQLite permission denied")
        )

        XCTAssertFalse(formatter.updateOperationInProgress(operationState))
        XCTAssertEqual(
            formatter.updateOperationDisplayMessage(status, operationState: operationState),
            "SQLite permission denied"
        )
    }

    func testUpdateOperationDisplayMessagePreservesTerminalFailureReason() {
        let status = platformState(runtimeState: .healthy)
        let operationState = PlatformOperationState(
            activeOperation: nil,
            install: .unavailable(),
            stableUpdate: .loaded(stableUpdateJournal(
                state: .failed,
                failureReason: "host activation failed"
            ))
        )

        XCTAssertFalse(formatter.updateOperationInProgress(operationState))
        XCTAssertEqual(
            formatter.updateOperationDisplayMessage(status, operationState: operationState),
            "Stable update failed: host activation failed"
        )
    }

    func testActiveOperationTextUsesOperationStateResource() {
        let operationState = PlatformOperationState(
            activeOperation: .applyBundle,
            install: .unavailable()
        )

        XCTAssertEqual(formatter.activeOperationText(operationState), "Apply Bundle")
    }

    func testActiveOperationTextUsesInstallOperationState() {
        let operationState = PlatformOperationState(
            activeOperation: nil,
            install: .loaded(RuntimeInstallStateDocument(
                state: .stepStarted,
                mode: .full,
                updatedAt: "2026-07-08T00:00:00Z"
            ))
        )

        XCTAssertEqual(formatter.activeOperationText(operationState), "Unknown")
    }

    func testRuntimeStateAndOperationTextUseStandardDisplayVocabulary() {
        XCTAssertEqual(formatter.runtimeStateText(.healthy), AppConstants.StatusText.healthy)
        XCTAssertEqual(formatter.runtimeStateText(.degraded), AppConstants.StatusText.degraded)
        XCTAssertEqual(formatter.runtimeStateText(.unknown("needs-admin-review")), "Needs Admin Review")
        XCTAssertEqual(formatter.operationText(.redisBackup), "Redis-only Backup")
        XCTAssertEqual(formatter.operationText(.redisRestore), "Redis-only Restore")
        XCTAssertEqual(formatter.operationText(.runtimeDataBackup), "VitalServer Backup")
        XCTAssertEqual(formatter.operationText(.runtimeDataRestore), "VitalServer Restore")
        XCTAssertEqual(formatter.operationText(.repairDatastore), "Repair Redis Datastore")
        XCTAssertEqual(formatter.operationText(.repairServices), "Repair Runtime")
        XCTAssertEqual(formatter.operationText(.applyBundle), "Apply Bundle")
        XCTAssertEqual(formatter.operationText(.unknown("custom-op")), "Custom Op")
    }

    func testBackupPresentationCopyUsesSingleVitalServerBackupAsDefaultPath() {
        XCTAssertEqual(AppConstants.Labels.sectionRuntimeDataRecovery, "VitalServer backup")
        XCTAssertEqual(AppConstants.Labels.runtimeDataBackup, "VitalServer backup")
        XCTAssertTrue(AppConstants.Labels.runtimeDataRecoveryHelp.contains("Redis data"))
        XCTAssertEqual(AppConstants.Actions.createBackup, "Create VitalServer Backup")
        XCTAssertEqual(AppConstants.Actions.restoreBackup, "Restore VitalServer Backup")
        XCTAssertEqual(AppConstants.Labels.sectionRedisDataRecovery, "Redis-only recovery")
        XCTAssertEqual(AppConstants.Labels.redisBackup, "Redis-only backup")
        XCTAssertTrue(AppConstants.Labels.redisDataRecoveryHelp.contains("Advanced repair action"))
        XCTAssertEqual(AppConstants.Actions.importBackups, "Import Backups")
        XCTAssertEqual(AppConstants.Actions.createRedisBackup, "Create Redis-only Backup")
        XCTAssertEqual(AppConstants.Actions.restoreRedisBackup, "Restore Redis-only Backup")
    }

    func testSystemTimeTextFormatsISO8601TimestampInRequestedTimeZone() {
        let timeZone = TimeZone(identifier: "Asia/Seoul")!

        XCTAssertEqual(
            formatter.systemTimeText("2026-05-21T12:00:00Z", timeZone: timeZone),
            "2026-05-21 21:00:00 +09:00"
        )
    }

    func testSystemTimeTextKeepsUnparseableTimestamp() {
        XCTAssertEqual(
            formatter.systemTimeText("not-a-date", timeZone: TimeZone(secondsFromGMT: 0)!),
            "not-a-date"
        )
    }

    func testSystemTimeAgeTextReturnsOnlyRelativeAgeForRecorderColumn() {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        let observedAt = ISO8601DateFormatter().string(
            from: now.addingTimeInterval(-3_600)
        )

        XCTAssertEqual(
            formatter.systemTimeAgeText(observedAt, now: now),
            "1h ago"
        )
        XCTAssertEqual(formatter.systemTimeAgeText(nil, now: now), "Unknown")
        XCTAssertEqual(formatter.systemTimeAgeText("not-a-date", now: now), "not-a-date")
    }
}

private func stableUpdateJournal(
    state: UpdateBootstrapJournalState,
    failureReason: String? = nil
) -> UpdateBootstrapJournal {
    let artifact = UpdateBootstrapArtifact(
        id: "artifact",
        relativePath: "payload/artifact",
        sha256: String(repeating: "a", count: 64),
        sizeBytes: 64,
        mediaType: "application/octet-stream"
    )
    let envelope = UpdateBootstrapEnvelope(
        schemaVersion: "v1",
        id: "envelope-1",
        productId: "com.tirosh.vitalserver-helper",
        target: UpdateBootstrapTarget(platform: .macos, architecture: .arm64),
        targetRelease: UpdateBootstrapRelease(
            productVersion: "0.2.2",
            runtimeVersion: "0.2.2"
        ),
        layerOrder: [.container, .guestRuntime, .hostPlatform],
        nextUpdaterArtifact: artifact,
        specification: artifact,
        signature: UpdateBootstrapSignature(
            algorithm: .ed25519,
            keyId: "release-key",
            signedSha256: String(repeating: "b", count: 64),
            value: "c2lnbmF0dXJl"
        ),
        issuedAt: "2026-07-29T00:00:00Z"
    )
    return UpdateBootstrapJournal(
        schemaVersion: "v2",
        id: "update-1",
        journalRevision: 1,
        operationId: "operation-1",
        targetInstallationId: "installation-1",
        expectedInstallationRevision: 1,
        requestId: "request-1",
        envelope: envelope,
        bootstrapSignedSHA256: String(repeating: "b", count: 64),
        state: state,
        stagedUpdaterRelativePath: nil,
        stagedSpecificationRelativePath: nil,
        completion: nil,
        failureReason: failureReason,
        createdAt: "2026-07-29T00:00:00Z",
        updatedAt: "2026-07-29T00:00:01Z"
    )
}
