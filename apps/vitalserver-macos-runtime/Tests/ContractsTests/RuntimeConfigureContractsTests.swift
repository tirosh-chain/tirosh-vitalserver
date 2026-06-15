import Contracts
import XCTest
import Errors

final class RuntimeConfigureContractsTests: XCTestCase {
    func testConfigureOptionsMapStableCLIFlags() {
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--cpu"), .cpu)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--memory-gib"), .memoryGiB)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--disk-gib"), .diskGiB)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--network"), .network)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--bridged-interface"), .bridgedInterface)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--proxy-port"), .proxyPort)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--vital-files-dir"), .vitalFilesDirectory)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--vitalserver-url"), .vitalServerURL)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--remote-console-url"), .remoteConsoleURL)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--public-host"), .publicHost)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--public-port"), .publicPort)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--admin-password"), .adminPassword)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--admin-password-file"), .adminPasswordFile)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--start-on-boot"), .startOnBoot)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--auto-recovery"), .autoRecovery)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--prevent-system-sleep"), .preventSystemSleep)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--automatic-backup"), .automaticBackup)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--backup-schedule-times"), .backupScheduleTimes)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--backup-retention"), .backupRetention)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--restart"), .restart)
        XCTAssertEqual(RuntimeConfigureOption(rawValue: "--future"), .unknown("--future"))
    }

    func testOnlyRestartDoesNotRequireValue() {
        XCTAssertFalse(RuntimeConfigureOption.restart.requiresValue)
        XCTAssertTrue(RuntimeConfigureOption.cpu.requiresValue)
        XCTAssertTrue(RuntimeConfigureOption.unknown("--future").requiresValue)
    }

    func testBooleanParserAcceptsCLIForms() {
        XCTAssertEqual(RuntimeBooleanParser.parse("true"), true)
        XCTAssertEqual(RuntimeBooleanParser.parse("YES"), true)
        XCTAssertEqual(RuntimeBooleanParser.parse("1"), true)
        XCTAssertEqual(RuntimeBooleanParser.parse("false"), false)
        XCTAssertEqual(RuntimeBooleanParser.parse("NO"), false)
        XCTAssertEqual(RuntimeBooleanParser.parse("0"), false)
        XCTAssertNil(RuntimeBooleanParser.parse("maybe"))
    }

    func testRuntimeNetworkModePreservesSharedAndBridgedValues() {
        XCTAssertEqual(RuntimeNetworkMode(rawValue: "shared"), .shared)
        XCTAssertEqual(RuntimeNetworkMode(rawValue: "bridged"), .bridged)
        XCTAssertNil(RuntimeNetworkMode(rawValue: "host"))
        XCTAssertEqual(RuntimeNetworkMode.shared.rawValue, "shared")
        XCTAssertEqual(RuntimeNetworkMode.bridged.rawValue, "bridged")
    }

    func testTextValidatorRejectsNewlines() {
        XCTAssertTrue(RuntimeTextValidator.isSingleLine("value"))
        XCTAssertFalse(RuntimeTextValidator.isSingleLine("line\nbreak"))
        XCTAssertFalse(RuntimeTextValidator.isSingleLine("line\rbreak"))
    }
}
