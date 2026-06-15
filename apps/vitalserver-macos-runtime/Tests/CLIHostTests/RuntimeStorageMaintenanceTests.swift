import Foundation
import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors
@testable import CLIHost

final class RuntimeStorageMaintenanceTests: XCTestCase {
    func testPruneOldRuntimeArtifactsFailsOnDirectoryListingFailure() throws {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates["/runtime/backups"] = .directory
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

        XCTAssertThrowsError(try maintenance.pruneOldRuntimeArtifacts(
            backupsDirectory: URL(fileURLWithPath: "/runtime/backups"),
            bundlesDirectory: URL(fileURLWithPath: "/runtime/bundles")
        )) { error in
            guard case .directoryListingFailed(let path, let reason) = error as? RuntimeStorageMaintenanceError else {
                return XCTFail("Expected directoryListingFailed, got \(error)")
            }
            XCTAssertEqual(path, "/runtime/backups")
            XCTAssertFalse(reason.isEmpty)
        }

        XCTAssertEqual(fileStore.removed, [])
        XCTAssertEqual(logs, [])
    }

    func testPruneOldRuntimeArtifactsFailsOnDirectoryInspectionFailure() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates["/runtime/backups"] = .inspectFailed("permission denied")
        let maintenance = RuntimeStorageMaintenance(
            fileStore: fileStore,
            configuration: RuntimeStorageMaintenanceConfiguration(
                backupKeepCount: 2,
                stagedBundleKeepCount: 2
            ),
            log: { _ in }
        )

        XCTAssertThrowsError(try maintenance.pruneOldRuntimeArtifacts(
            backupsDirectory: URL(fileURLWithPath: "/runtime/backups"),
            bundlesDirectory: URL(fileURLWithPath: "/runtime/bundles")
        )) { error in
            XCTAssertEqual(
                error as? RuntimeStorageMaintenanceError,
                .pathInspectionFailed(path: "/runtime/backups", reason: "permission denied")
            )
        }
    }

    func testReplaceFileFailsWhenTemporaryPathInspectionFails() {
        let fileStore = RuntimeFileStoreSpy()
        let source = URL(fileURLWithPath: "/runtime/source.img")
        let destination = URL(fileURLWithPath: "/runtime/destination.img")
        let temporary = URL(fileURLWithPath: "/runtime/.destination.img.tmp")
        fileStore.files[source] = Data("disk".utf8)
        fileStore.pathStates[temporary.path] = .inspectFailed("permission denied")
        let maintenance = RuntimeStorageMaintenance(
            fileStore: fileStore,
            configuration: RuntimeStorageMaintenanceConfiguration(
                backupKeepCount: 2,
                stagedBundleKeepCount: 2
            ),
            log: { _ in }
        )

        XCTAssertThrowsError(try maintenance.replaceFile(from: source, to: destination)) { error in
            XCTAssertEqual(
                error as? RuntimeStorageMaintenanceError,
                .pathInspectionFailed(path: temporary.path, reason: "permission denied")
            )
        }
    }
}
