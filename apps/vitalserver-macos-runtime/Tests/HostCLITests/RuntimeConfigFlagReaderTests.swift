import HostInfrastructure
import XCTest
@testable import HostCLI

final class RuntimeConfigFlagReaderTests: XCTestCase {
    func testReadsConfiguredFlags() {
        let harness = ConfigFlagHarness(config: runtimeConfig(
            autoRecoveryEnabled: false,
            preventSystemSleep: false
        ))

        XCTAssertFalse(harness.reader.automaticRecoveryEnabled())
        XCTAssertFalse(harness.reader.preventSystemSleepEnabled())
        XCTAssertTrue(harness.logs.isEmpty)
    }

    func testDefaultsAndLogsWhenFlagIsMissing() {
        let harness = ConfigFlagHarness(config: runtimeConfig(
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
    let config: VMRuntimeConfig?
    let loadError: Error?
    var logs: [String] = []

    init(config: VMRuntimeConfig? = nil, loadError: Error? = nil) {
        self.config = config
        self.loadError = loadError
    }

    var reader: RuntimeConfigFlagReader {
        RuntimeConfigFlagReader(
            loadConfig: {
                if let loadError = self.loadError {
                    throw loadError
                }
                return self.config ?? runtimeConfig()
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
) -> VMRuntimeConfig {
    var config = VMRuntimeConfig.default(paths: .defaultInstalled)
    config.autoRecoveryEnabled = autoRecoveryEnabled
    config.preventSystemSleep = preventSystemSleep
    return config
}

private enum ConfigFlagError: Error {
    case load
}
