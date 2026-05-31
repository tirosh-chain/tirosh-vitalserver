import Foundation
import HostInfrastructure
@testable import HostCLI
import XCTest

final class RuntimeInstallDirectoryPreparerTests: XCTestCase {
    func testPrepareCreatesRuntimeDirectoriesAndCustomVitalFilesDirectory() throws {
        let fileStore = RuntimeFileStoreSpy()
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        for staleDocument in [
            paths.vmIPFile,
            paths.runtimeState,
            paths.bootstrapResult,
            paths.updateActivationResult,
            paths.updateShutdownResult,
            paths.datastoreRepairResult,
        ] {
            fileStore.files[staleDocument] = Data("stale".utf8)
        }
        let preparer = RuntimeInstallDirectoryPreparer(
            installedPaths: paths,
            fileStore: fileStore
        )

        try preparer.prepare(settings: InstallSettings(vitalFilesDirectory: "/custom/vital-files"))

        XCTAssertTrue(fileStore.directories.contains(paths.runtimeDirectory))
        XCTAssertTrue(fileStore.directories.contains(URL(fileURLWithPath: "/custom/vital-files")))
        XCTAssertTrue(fileStore.directories.contains(paths.deployDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.guestRunDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.vrReleaseDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.productLogsDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.centralRuntimeLogsDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.centralGuestLogsDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.logArchiveDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.hostRunDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.statusDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.nginxLogsDirectory))
        XCTAssertEqual(Set(fileStore.removed), [
            paths.vmIPFile,
            paths.runtimeState,
            paths.bootstrapResult,
            paths.updateActivationResult,
            paths.updateShutdownResult,
            paths.datastoreRepairResult,
        ])
    }
}
