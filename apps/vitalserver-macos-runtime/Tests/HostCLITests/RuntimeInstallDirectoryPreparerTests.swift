import Foundation
import Workflow
import XCTest

final class RuntimeInstallDirectoryPreparerTests: XCTestCase {
    func testPrepareCreatesRuntimeDirectoriesAndCustomVitalFilesDirectory() throws {
        let runtimeDirectory = URL(fileURLWithPath: "/product/runtime")
        let deployDirectory = URL(fileURLWithPath: "/product/deploy")
        let guestRunDirectory = URL(fileURLWithPath: "/product/run/guest")
        let logsDirectory = URL(fileURLWithPath: "/product/logs")
        let vmIPFile = URL(fileURLWithPath: "/product/run/guest/vm-ip")
        let runtimeState = URL(fileURLWithPath: "/product/run/guest/runtime-state.json")
        let bootstrapResult = URL(fileURLWithPath: "/product/run/guest/bootstrap-result.json")
        let updateActivationResult = URL(fileURLWithPath: "/product/run/guest/update-activation-result.json")
        let updateShutdownResult = URL(fileURLWithPath: "/product/run/guest/update-shutdown-result.json")
        let datastoreRepairResult = URL(fileURLWithPath: "/product/run/guest/datastore-repair-result.json")
        var createdDirectories: [URL] = []
        var existingFiles: Set<URL> = [
            vmIPFile,
            runtimeState,
            bootstrapResult,
            updateActivationResult,
            updateShutdownResult,
            datastoreRepairResult,
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
                    updateActivationResult,
                    updateShutdownResult,
                    datastoreRepairResult,
                ],
                vitalFilesDirectory: { settings in
                    URL(fileURLWithPath: settings.vitalFilesDirectory)
                }
            ),
            operations: RuntimeInstallDirectoryPreparationOperations(
                createDirectory: { url, _ in
                    createdDirectories.append(url)
                },
                fileExists: { url in
                    existingFiles.contains(url)
                },
                removeItem: { url in
                    removed.append(url)
                    existingFiles.remove(url)
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
            updateActivationResult,
            updateShutdownResult,
            datastoreRepairResult,
        ])
    }
}

private struct TestInstallDirectorySettings {
    var vitalFilesDirectory: String
}
