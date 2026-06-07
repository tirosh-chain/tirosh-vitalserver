import Foundation
import Contracts
import OutboundAdapters
import XCTest
import Errors

final class RuntimeInstallSettingsCleanerTests: XCTestCase {
    func testCleanupRemovesSettingsFileWhenPresent() throws {
        let settingsFile = URL(fileURLWithPath: "/tmp/install-settings.json")
        let events = EventLog()
        let cleaner = makeCleaner(
            settingsFile: settingsFile,
            pathStates: [settingsFile: .file],
            events: events
        )

        try cleaner.cleanup()

        XCTAssertEqual(events.values, [
            "remove:/tmp/install-settings.json",
        ])
    }

    func testCleanupDoesNothingWhenSettingsFileIsAbsent() throws {
        let settingsFile = URL(fileURLWithPath: "/tmp/install-settings.json")
        let events = EventLog()
        let cleaner = makeCleaner(
            settingsFile: settingsFile,
            pathStates: [settingsFile: .missing],
            events: events
        )

        try cleaner.cleanup()

        XCTAssertEqual(events.values, [])
    }

    func testCleanupFailsWhenSettingsFileInspectionFails() {
        let settingsFile = URL(fileURLWithPath: "/tmp/install-settings.json")
        let cleaner = makeCleaner(
            settingsFile: settingsFile,
            pathStates: [settingsFile: .inspectFailed("permission denied")],
            events: EventLog()
        )

        XCTAssertThrowsError(try cleaner.cleanup()) { error in
            XCTAssertEqual(
                error as? RuntimeInstallSettingsCleanupError,
                .pathInspectionFailed(path: settingsFile.path, reason: "permission denied")
            )
        }
    }

    func testCleanupFailsWhenSettingsPathIsDirectory() {
        let settingsFile = URL(fileURLWithPath: "/tmp/install-settings.json")
        let cleaner = makeCleaner(
            settingsFile: settingsFile,
            pathStates: [settingsFile: .directory],
            events: EventLog()
        )

        XCTAssertThrowsError(try cleaner.cleanup()) { error in
            XCTAssertEqual(
                error as? RuntimeInstallSettingsCleanupError,
                .unexpectedPathState(path: settingsFile.path, state: "directory")
            )
        }
    }

    private func makeCleaner(
        settingsFile: URL,
        pathStates: [URL: RuntimePathState],
        events: EventLog
    ) -> RuntimeInstallSettingsCleaner {
        RuntimeInstallSettingsCleaner(
            context: RuntimeInstallSettingsCleanupContext(
                settingsFile: settingsFile
            ),
            operations: RuntimeInstallSettingsCleanupOperations(
                pathState: { url in
                    pathStates[url] ?? .missing
                },
                removeItem: { url in
                    events.append("remove:\(url.path)")
                }
            )
        )
    }

    private final class EventLog {
        private(set) var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }
    }
}
