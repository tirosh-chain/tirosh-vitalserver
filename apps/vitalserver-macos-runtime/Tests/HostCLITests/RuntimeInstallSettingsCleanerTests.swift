import Foundation
import Workflow
import XCTest

final class RuntimeInstallSettingsCleanerTests: XCTestCase {
    func testCleanupRemovesSettingsFileWhenPresent() throws {
        let settingsFile = URL(fileURLWithPath: "/tmp/install-settings.json")
        let events = EventLog()
        let cleaner = makeCleaner(
            settingsFile: settingsFile,
            existingFiles: [settingsFile],
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
            existingFiles: [],
            events: events
        )

        try cleaner.cleanup()

        XCTAssertEqual(events.values, [])
    }

    private func makeCleaner(
        settingsFile: URL,
        existingFiles: Set<URL>,
        events: EventLog
    ) -> RuntimeInstallSettingsCleaner {
        RuntimeInstallSettingsCleaner(
            context: RuntimeInstallSettingsCleanupContext(
                settingsFile: settingsFile
            ),
            operations: RuntimeInstallSettingsCleanupOperations(
                fileExists: { url in
                    existingFiles.contains(url)
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
