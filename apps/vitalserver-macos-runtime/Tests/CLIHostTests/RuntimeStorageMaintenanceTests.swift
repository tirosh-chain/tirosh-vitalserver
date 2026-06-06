import Foundation
import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors
@testable import CLIHost

final class RuntimeStorageMaintenanceTests: XCTestCase {
    func testPruneOldRuntimeArtifactsLogsDirectoryListingFailure() throws {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.childDirectoriesError = CocoaError(.fileReadNoPermission)
        var logs: [String] = []
        let maintenance = RuntimeStorageMaintenance(
            fileStore: fileStore,
            configuration: RuntimeStorageMaintenanceConfiguration(
                backupKeepCount: 2,
                stagedBundleKeepCount: 2
            ),
            log: { logs.append($0) }
        )

        try maintenance.pruneOldRuntimeArtifacts(
            backupsDirectory: URL(fileURLWithPath: "/runtime/backups"),
            bundlesDirectory: URL(fileURLWithPath: "/runtime/bundles")
        )

        XCTAssertEqual(fileStore.removed, [])
        XCTAssertTrue(logs.contains { message in
            message.contains("runtime artifact prune skipped")
                && message.contains("/runtime/backups")
                && message.contains("-before-")
        })
        XCTAssertTrue(logs.contains { message in
            message.contains("runtime artifact prune skipped")
                && message.contains("/runtime/bundles")
                && message.contains("update-bundle-")
        })
    }
}
