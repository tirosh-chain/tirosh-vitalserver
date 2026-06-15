import Foundation
import Contracts
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeLogExportDestinationPolicyTests: XCTestCase {
    func testAllowsWritableLocalZipDestination() {
        let fileManager = FakePathPermissionFileManager(items: [
            "/Users/test/Downloads": .directory(writable: true),
        ])
        let policy = RuntimeLogExportDestinationPolicy(fileManager: fileManager)

        XCTAssertNil(policy.validationMessage(for: URL(fileURLWithPath: "/Users/test/Downloads/vitalserver-logs.zip")))
    }

    func testRejectsICloudDriveDestination() {
        let policy = RuntimeLogExportDestinationPolicy(fileManager: FakePathPermissionFileManager())

        XCTAssertEqual(
            policy.validationMessage(for: URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/vitalserver-logs.zip")),
            AppConstants.StatusText.logExportDestinationProtected
        )
    }

    func testRejectsDesktopAndDocumentsDestinations() {
        let policy = RuntimeLogExportDestinationPolicy(fileManager: FakePathPermissionFileManager())

        XCTAssertEqual(
            policy.validationMessage(for: URL(fileURLWithPath: "/Users/test/Desktop/vitalserver-logs.zip")),
            AppConstants.StatusText.logExportDestinationProtected
        )
        XCTAssertEqual(
            policy.validationMessage(for: URL(fileURLWithPath: "/Users/test/Documents/vitalserver-logs.zip")),
            AppConstants.StatusText.logExportDestinationProtected
        )
    }

    func testRejectsSystemManagedDestinations() {
        let policy = RuntimeLogExportDestinationPolicy(fileManager: FakePathPermissionFileManager())

        XCTAssertEqual(
            policy.validationMessage(for: URL(fileURLWithPath: "/Library/Application Support/VitalServerHelper/vitalserver-logs.zip")),
            AppConstants.StatusText.logExportDestinationProtected
        )
        XCTAssertEqual(
            policy.validationMessage(for: URL(fileURLWithPath: "/Applications/vitalserver-logs.zip")),
            AppConstants.StatusText.logExportDestinationProtected
        )
    }

    func testRejectsExistingDirectoryDestination() {
        let fileManager = FakePathPermissionFileManager(items: [
            "/tmp/vitalserver-logs.zip": .directory(writable: true),
        ])
        let policy = RuntimeLogExportDestinationPolicy(fileManager: fileManager)

        XCTAssertEqual(
            policy.validationMessage(for: URL(fileURLWithPath: "/tmp/vitalserver-logs.zip")),
            AppConstants.StatusText.logExportDestinationDirectory
        )
    }

    func testRejectsNonWritableParentDirectory() {
        let fileManager = FakePathPermissionFileManager(items: [
            "/tmp": .directory(writable: false),
        ])
        let policy = RuntimeLogExportDestinationPolicy(fileManager: fileManager)

        XCTAssertEqual(
            policy.validationMessage(for: URL(fileURLWithPath: "/tmp/vitalserver-logs.zip")),
            AppConstants.StatusText.logExportDestinationNotWritable
        )
    }

    func testRejectsNonZipDestination() {
        let fileManager = FakePathPermissionFileManager(items: [
            "/tmp": .directory(writable: true),
        ])
        let policy = RuntimeLogExportDestinationPolicy(fileManager: fileManager)

        XCTAssertEqual(
            policy.validationMessage(for: URL(fileURLWithPath: "/tmp/vitalserver-logs.txt")),
            AppConstants.StatusText.logExportDestinationInvalid
        )
    }

    func testReportsDestinationPathInspectionFailureSeparatelyFromInvalidDestination() {
        let fileManager = FakePathPermissionFileManager(pathStates: [
            "/tmp/vitalserver-logs.zip": .inspectFailed("permission denied"),
            "/tmp": .directory,
        ])
        let policy = RuntimeLogExportDestinationPolicy(fileManager: fileManager)

        XCTAssertEqual(
            policy.validationMessage(for: URL(fileURLWithPath: "/tmp/vitalserver-logs.zip")),
            AppConstants.StatusText.logExportDestinationInspectionFailed(
                "destination path inspection failed: /tmp/vitalserver-logs.zip reason=permission denied"
            )
        )
    }

    func testReportsParentDirectoryInspectionFailureSeparatelyFromInvalidDestination() {
        let fileManager = FakePathPermissionFileManager(pathStates: [
            "/tmp/vitalserver-logs.zip": .missing,
            "/tmp": .inspectFailed("permission denied"),
        ])
        let policy = RuntimeLogExportDestinationPolicy(fileManager: fileManager)

        XCTAssertEqual(
            policy.validationMessage(for: URL(fileURLWithPath: "/tmp/vitalserver-logs.zip")),
            AppConstants.StatusText.logExportDestinationInspectionFailed(
                "parent directory path inspection failed: /tmp reason=permission denied"
            )
        )
    }
}

private final class FakePathPermissionFileManager: RuntimePathPermissionFileManaging {
    struct Item {
        let isDirectory: Bool
        let writable: Bool

        static func directory(writable: Bool) -> Item {
            Item(isDirectory: true, writable: writable)
        }

        static func file(writable: Bool) -> Item {
            Item(isDirectory: false, writable: writable)
        }
    }

    var items: [String: Item]
    var pathStates: [String: RuntimePathState]

    init(
        items: [String: Item] = [:],
        pathStates: [String: RuntimePathState] = [:]
    ) {
        self.items = items
        self.pathStates = pathStates
    }

    func pathState(atPath path: String) -> RuntimePathState {
        if let pathState = pathStates[path] {
            return pathState
        }
        guard let item = items[path] else {
            return .missing
        }
        return item.isDirectory ? .directory : .file
    }

    func isWritableFile(atPath path: String) -> Bool {
        items[path]?.writable ?? false
    }
}
