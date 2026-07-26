import Contracts
import RuntimeControl
import XCTest

final class RuntimePlatformSettingsMappingTests: XCTestCase {
    func testLoadedPlatformSettingsContractPreservesFieldsRequiredByNativeControlPanel() throws {
        let applied = RuntimeAppliedVMSettings(
            cpuCount: 4,
            memoryGiB: 8,
            networkMode: .shared,
            bridgedInterface: nil,
            vitalFilesDirectory: "/Library/Application Support/VitalServerHelper/vm/data/vital-files"
        )
        let current = RuntimeSettings(
            cpuCount: 6,
            memoryGiB: 12,
            vitalFilesDirectory: "/Library/Application Support/VitalServerHelper/vm/data/vital-files",
            vitalServerURL: "http://127.0.0.1/",
            remoteConsoleURL: "http://127.0.0.1:18321/",
            publicHost: "runtime.example.test",
            publicPort: 18080,
            recorderIngressSendDataReplayMaxMiBPerSecond: 31,
            containerMemoryLimitsEnabled: true,
            vitalServerContainerMemoryLimitMiB: 4096,
            recorderIngressContainerMemoryLimitMiB: 512,
            redisContainerMemoryLimitMiB: 2048,
            appliedVMSettings: applied
        )

        let read = RuntimePlatformSettingsRead(runtimeSettings: current)
        let document = try XCTUnwrap(read.settings)
        let roundTrip = document.runtimeSettings

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(roundTrip.vitalFilesDirectory, current.vitalFilesDirectory)
        XCTAssertEqual(roundTrip.vitalServerURL, current.vitalServerURL)
        XCTAssertEqual(roundTrip.remoteConsoleURL, current.remoteConsoleURL)
        XCTAssertEqual(roundTrip.publicHost, current.publicHost)
        XCTAssertEqual(roundTrip.publicPort, current.publicPort)
        XCTAssertEqual(
            roundTrip.recorderIngressSendDataReplayMaxMiBPerSecond,
            current.recorderIngressSendDataReplayMaxMiBPerSecond
        )
        XCTAssertEqual(roundTrip.containerMemoryLimitsEnabled, current.containerMemoryLimitsEnabled)
        XCTAssertEqual(roundTrip.appliedVMSettings, applied)
        XCTAssertEqual(roundTrip.adminPassword, "")
        XCTAssertFalse(roundTrip.changeAdminPassword)
    }

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
