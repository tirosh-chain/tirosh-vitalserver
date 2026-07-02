import Foundation
import Contracts
import OutboundAdapters
import XCTest
import Errors

final class RuntimeInstallDirectoryPreparerTests: XCTestCase {
    func testPrepareCreatesRuntimeDirectoriesAndCustomVitalFilesDirectory() throws {
        let runtimeDirectory = URL(fileURLWithPath: "/product/runtime")
        let deployDirectory = URL(fileURLWithPath: "/product/deploy")
        let guestRunDirectory = URL(fileURLWithPath: "/product/run/guest")
        let logsDirectory = URL(fileURLWithPath: "/product/logs")
        let vmIPFile = URL(fileURLWithPath: "/product/run/guest/vm-ip")
        let runtimeState = URL(fileURLWithPath: "/product/run/guest/runtime-state.json")
        let bootstrapResult = URL(fileURLWithPath: "/product/run/guest/bootstrap-result.json")
        var createdDirectories: [URL] = []
        var pathStates: [URL: RuntimePathState] = [
            vmIPFile: .file,
            runtimeState: .file,
            bootstrapResult: .file,
        ]
        var removed: [URL] = []
        let preparer = RuntimeInstallDirectoryPreparer<TestInstallDirectorySettings>(
            context: RuntimeInstallDirectoryPreparationContext(
                fixedDirectories: [
                    runtimeDirectory,
                    deployDirectory,
                    guestRunDirectory,
                    logsDirectory,
                ],
                staleGuestRunDocuments: [
                    vmIPFile,
                    runtimeState,
                    bootstrapResult,
                ],
                vitalFilesDirectory: { settings in
                    URL(fileURLWithPath: settings.vitalFilesDirectory)
                }
            ),
            operations: RuntimeInstallDirectoryPreparationOperations(
                createDirectory: { url, _ in
                    createdDirectories.append(url)
                },
                pathState: { url in
                    pathStates[url] ?? .missing
                },
                removeItem: { url in
                    removed.append(url)
                    pathStates[url] = .missing
                }
            )
        )

        try preparer.prepare(settings: TestInstallDirectorySettings(vitalFilesDirectory: "/custom/vital-files"))

        XCTAssertEqual(createdDirectories, [
            URL(fileURLWithPath: "/custom/vital-files"),
            runtimeDirectory,
            deployDirectory,
            guestRunDirectory,
            logsDirectory,
        ])
        XCTAssertEqual(Set(removed), [
            vmIPFile,
            runtimeState,
            bootstrapResult,
        ])
    }

    func testPrepareFailsWhenStaleGuestDocumentInspectionFails() {
        let runtimeState = URL(fileURLWithPath: "/product/run/guest/runtime-state.json")
        let preparer = RuntimeInstallDirectoryPreparer<TestInstallDirectorySettings>(
            context: RuntimeInstallDirectoryPreparationContext(
                fixedDirectories: [],
                staleGuestRunDocuments: [runtimeState],
                vitalFilesDirectory: { settings in
                    URL(fileURLWithPath: settings.vitalFilesDirectory)
                }
            ),
            operations: RuntimeInstallDirectoryPreparationOperations(
                createDirectory: { _, _ in },
                pathState: { _ in .inspectFailed("permission denied") },
                removeItem: { _ in }
            )
        )

        XCTAssertThrowsError(try preparer.prepare(settings: TestInstallDirectorySettings(vitalFilesDirectory: "/custom"))) { error in
            XCTAssertEqual(
                error as? RuntimeInstallDirectoryPreparationError,
                .pathInspectionFailed(path: runtimeState.path, reason: "permission denied")
            )
        }
    }

    func testPrepareFailsWhenStaleGuestDocumentPathIsDirectory() {
        let runtimeState = URL(fileURLWithPath: "/product/run/guest/runtime-state.json")
        let preparer = RuntimeInstallDirectoryPreparer<TestInstallDirectorySettings>(
            context: RuntimeInstallDirectoryPreparationContext(
                fixedDirectories: [],
                staleGuestRunDocuments: [runtimeState],
                vitalFilesDirectory: { settings in
                    URL(fileURLWithPath: settings.vitalFilesDirectory)
                }
            ),
            operations: RuntimeInstallDirectoryPreparationOperations(
                createDirectory: { _, _ in },
                pathState: { _ in .directory },
                removeItem: { _ in }
            )
        )

        XCTAssertThrowsError(try preparer.prepare(settings: TestInstallDirectorySettings(vitalFilesDirectory: "/custom"))) { error in
            XCTAssertEqual(
                error as? RuntimeInstallDirectoryPreparationError,
                .unexpectedPathState(path: runtimeState.path, state: "directory")
            )
        }
    }
}

private struct TestInstallDirectorySettings {
    var vitalFilesDirectory: String
}
