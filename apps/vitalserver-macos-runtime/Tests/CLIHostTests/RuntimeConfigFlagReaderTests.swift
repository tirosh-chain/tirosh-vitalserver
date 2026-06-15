import OutboundAdapters
import InboundAdapters
import XCTest
import Errors
@testable import CLIHost

final class RuntimeConfigFlagReaderTests: XCTestCase {
    func testReadsConfiguredFlags() {
        let harness = ConfigFlagHarness(flags: runtimeConfig(
            autoRecoveryEnabled: false,
            preventSystemSleep: false
        ))

        XCTAssertEqual(
            harness.reader.automaticRecoveryFlag(),
            .configured(name: "autoRecoveryEnabled", value: false)
        )
        XCTAssertEqual(
            harness.reader.preventSystemSleepFlag(),
            .configured(name: "preventSystemSleep", value: false)
        )
        XCTAssertTrue(harness.logs.isEmpty)
    }

    func testDefaultsAndLogsWhenFlagIsMissing() {
        let harness = ConfigFlagHarness(flags: runtimeConfig(
            autoRecoveryEnabled: nil,
            preventSystemSleep: nil
        ))

        XCTAssertEqual(
            harness.reader.automaticRecoveryFlag(),
            .defaulted(name: "autoRecoveryEnabled", value: true, reason: "missing")
        )
        XCTAssertEqual(
            harness.reader.preventSystemSleepFlag(),
            .defaulted(name: "preventSystemSleep", value: true, reason: "missing")
        )
        XCTAssertEqual(harness.logs.count, 2)
        XCTAssertTrue(harness.logs[0].contains("runtime config flag missing name=autoRecoveryEnabled"))
        XCTAssertTrue(harness.logs[1].contains("runtime config flag missing name=preventSystemSleep"))
    }

    func testReportsFailureAndLogsWhenConfigCannotBeRead() {
        let harness = ConfigFlagHarness(loadError: ConfigFlagError.load)

        XCTAssertEqual(
            harness.reader.automaticRecoveryFlag(),
            .failed(name: "autoRecoveryEnabled", reason: "load")
        )
        XCTAssertEqual(
            harness.reader.preventSystemSleepFlag(),
            .failed(name: "preventSystemSleep", reason: "load")
        )
        XCTAssertEqual(harness.logs.count, 2)
        XCTAssertTrue(harness.logs[0].contains("failed to read runtime config flag name=autoRecoveryEnabled"))
        XCTAssertTrue(harness.logs[1].contains("failed to read runtime config flag name=preventSystemSleep"))
    }
}

private final class ConfigFlagHarness {
    let flags: RuntimeConfigFlagValues?
    let loadError: Error?
    var logs: [String] = []

    init(flags: RuntimeConfigFlagValues? = nil, loadError: Error? = nil) {
        self.flags = flags
        self.loadError = loadError
    }

    var reader: RuntimeConfigFlagReader {
        RuntimeConfigFlagReader(
            loadFlags: {
                if let loadError = self.loadError {
                    throw loadError
                }
                return self.flags ?? runtimeConfigFlags()
            },
            log: { message in
                self.logs.append(message)
            }
        )
    }
}

private func runtimeConfig(
    autoRecoveryEnabled: Bool? = true,
    preventSystemSleep: Bool? = true
) -> RuntimeConfigFlagValues {
    runtimeConfigFlags(
        autoRecoveryEnabled: autoRecoveryEnabled,
        preventSystemSleep: preventSystemSleep
    )
}

private func runtimeConfigFlags(
    autoRecoveryEnabled: Bool? = true,
    preventSystemSleep: Bool? = true
) -> RuntimeConfigFlagValues {
    RuntimeConfigFlagValues(
        autoRecoveryEnabled: autoRecoveryEnabled,
        preventSystemSleep: preventSystemSleep
    )
}

private enum ConfigFlagError: Error {
    case load
}
