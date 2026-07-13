import Contracts
import RuntimeControl
import XCTest

final class RuntimePlatformSettingsMappingTests: XCTestCase {
    func testReadRejectsIncompleteOwnerStateInsteadOfPublishingDraftValues() {
        let current = RuntimeSettings(
            readIssues: [RuntimeSettingsReadIssue(source: "proxyPort", message: "plist unreadable")],
            cpuCount: 6
        )

        let read = RuntimePlatformSettingsRead(runtimeSettings: current)

        XCTAssertEqual(read.state, .failed)
        XCTAssertNil(read.settings)
        XCTAssertEqual(read.readIssues, [
            RuntimePlatformSettingsReadIssue(source: "proxyPort", message: "plist unreadable")
        ])
        XCTAssertNotNil(read.readError)
    }

    func testApplyChangesOnlyPlatformOwnedMutableFields() {
        let current = RuntimeSettings(
            cpuCount: 4,
            memoryGiB: 8,
            diskGiB: 128,
            minimumDiskGiB: 16,
            vitalServerURL: "https://runtime.example.test/",
            adminPassword: "secret-that-must-be-preserved",
            startOnBootConfigurable: false
        )
        let apply = RuntimePlatformSettingsApplyDocument(
            cpuCount: 6,
            memoryGiB: 12,
            diskGiB: 256,
            networkMode: .shared,
            bridgedInterface: nil,
            proxyPort: 18080,
            runtimeControlPort: 18321,
            vitalFilesDirectory: "/data/vital-files",
            startOnBoot: false,
            autoRecoveryEnabled: true,
            preventSystemSleep: false,
            automaticBackupEnabled: true,
            backupScheduleTimes: ["03:00"],
            backupRetentionCount: 9,
            logArchiveRetentionDays: 21,
            logArchiveMaximumGiB: 12,
            restartAfterSave: true
        )

        let next = apply.applying(to: current)

        XCTAssertEqual(next.cpuCount, 6)
        XCTAssertEqual(next.memoryGiB, 12)
        XCTAssertEqual(next.diskGiB, 256)
        XCTAssertEqual(next.adminPassword, "secret-that-must-be-preserved")
        XCTAssertEqual(next.vitalServerURL, "https://runtime.example.test/")
        XCTAssertEqual(next.minimumDiskGiB, 16)
        XCTAssertFalse(next.startOnBootConfigurable)
    }
}
