import HostInfrastructure
import XCTest
@testable import HostCLI

final class RuntimeConfigFlagReaderTests: XCTestCase {
    func testReadsConfiguredFlags() {
        let harness = ConfigFlagHarness(flags: runtimeConfig(
            autoRecoveryEnabled: false,
            preventSystemSleep: false
        ))

        XCTAssertFalse(harness.reader.automaticRecoveryEnabled())
        XCTAssertFalse(harness.reader.preventSystemSleepEnabled())
        XCTAssertTrue(harness.logs.isEmpty)
    }

    func testDefaultsAndLogsWhenFlagIsMissing() {
        let harness = ConfigFlagHarness(flags: runtimeConfig(
            autoRecoveryEnabled: nil,
            preventSystemSleep: nil
        ))

        XCTAssertTrue(harness.reader.automaticRecoveryEnabled())
        XCTAssertTrue(harness.reader.preventSystemSleepEnabled())
        XCTAssertEqual(harness.logs.count, 2)
        XCTAssertTrue(harness.logs[0].contains("runtime config flag missing name=autoRecoveryEnabled"))
        XCTAssertTrue(harness.logs[1].contains("runtime config flag missing name=preventSystemSleep"))
    }

    func testDefaultsAndLogsWhenConfigCannotBeRead() {
        let harness = ConfigFlagHarness(loadError: ConfigFlagError.load)

        XCTAssertTrue(harness.reader.automaticRecoveryEnabled())
        XCTAssertTrue(harness.reader.preventSystemSleepEnabled())
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
