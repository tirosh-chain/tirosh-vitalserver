import Foundation
import Contracts
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class RuntimeNavigationCoordinatorTests: XCTestCase {
    func testOpenFolderOpensExistingDirectory() {
        let shell = FakeNavigationNativeShell(existingDirectories: ["/runtime/data"])
        let coordinator = RuntimeNavigationCoordinator()

        let result = coordinator.openFolder("/runtime/data", nativeShell: shell)

        XCTAssertEqual(result, .completed)
        XCTAssertEqual(shell.openedFileURLs, [URL(fileURLWithPath: "/runtime/data")])
        XCTAssertEqual(shell.confirmCreateDirectoryPaths, [])
    }

    func testOpenFolderCreatesMissingDirectoryWhenConfirmed() {
        let shell = FakeNavigationNativeShell(
            existingDirectories: [],
            confirmCreateDirectoryResponses: [true]
        )
        let coordinator = RuntimeNavigationCoordinator()

        let result = coordinator.openFolder("/runtime/data", nativeShell: shell)

        XCTAssertEqual(result, .completed)
        XCTAssertEqual(shell.confirmCreateDirectoryPaths, ["/runtime/data"])
        XCTAssertEqual(shell.createdDirectoryURLs, [URL(fileURLWithPath: "/runtime/data")])
        XCTAssertEqual(shell.openedFileURLs, [URL(fileURLWithPath: "/runtime/data")])
    }

    func testOpenFolderReturnsCreationFailureMessage() {
        let shell = FakeNavigationNativeShell(
            existingDirectories: [],
            confirmCreateDirectoryResponses: [true],
            createDirectoryError: CocoaError(.fileWriteNoPermission)
        )
        let coordinator = RuntimeNavigationCoordinator()

        let result = coordinator.openFolder("/runtime/data", nativeShell: shell)

        XCTAssertEqual(
            result,
            .failed(AppConstants.StatusText.folderCreateFailed(CocoaError(.fileWriteNoPermission).localizedDescription))
        )
        XCTAssertEqual(shell.openedFileURLs, [])
    }

    func testOpenFolderReportsPathInspectionFailureWithoutCreatingDirectory() {
        let shell = FakeNavigationNativeShell(
            pathStates: ["/runtime/data": .inspectFailed("permission denied")],
            confirmCreateDirectoryResponses: [true]
        )
        let coordinator = RuntimeNavigationCoordinator()

        let result = coordinator.openFolder("/runtime/data", nativeShell: shell)

        XCTAssertEqual(result, .failed(AppConstants.StatusText.folderReadFailed("permission denied")))
        XCTAssertEqual(shell.confirmCreateDirectoryPaths, [])
        XCTAssertEqual(shell.createdDirectoryURLs, [])
        XCTAssertEqual(shell.openedFileURLs, [])
    }

    func testOpenFolderDoesNotTreatMissingNativeShellProviderAsMissingDirectory() {
        let shell = NoopRuntimeNativeShell()
        let coordinator = RuntimeNavigationCoordinator()

        let result = coordinator.openFolder("/runtime/data", nativeShell: shell)

        XCTAssertEqual(result, .failed(AppConstants.StatusText.folderReadFailed("native shell is not configured")))
    }

    func testOpenFolderRejectsUnexpectedPathStateWithoutOpeningFile() {
        let shell = FakeNavigationNativeShell(
            pathStates: ["/runtime/data": .file],
            confirmCreateDirectoryResponses: [true]
        )
        let coordinator = RuntimeNavigationCoordinator()

        let result = coordinator.openFolder("/runtime/data", nativeShell: shell)

        XCTAssertEqual(
            result,
            .failed(AppConstants.StatusText.folderReadFailed(
                "folder path state is unexpected: /runtime/data state=file"
            ))
        )
        XCTAssertEqual(shell.confirmCreateDirectoryPaths, [])
        XCTAssertEqual(shell.createdDirectoryURLs, [])
        XCTAssertEqual(shell.openedFileURLs, [])
    }

    func testOpenWebURLReportsInvalidURLs() {
        let shell = FakeNavigationNativeShell()
        let coordinator = RuntimeNavigationCoordinator()

        let invalidResult = coordinator.openWebURL("http://[::1", nativeShell: shell)
        let openedResult = coordinator.openWebURL("https://example.test", nativeShell: shell)

        XCTAssertEqual(invalidResult, .failed(AppConstants.StatusText.invalidRuntimeURL))
        XCTAssertEqual(openedResult, .completed)
        XCTAssertEqual(shell.openedWebURLs, [URL(string: "https://example.test")])
    }

    func testOpenWebURLRejectsRelativeURLs() {
        let shell = FakeNavigationNativeShell()
        let coordinator = RuntimeNavigationCoordinator()

        let result = coordinator.openWebURL("vitaldb.tirosh.ai", nativeShell: shell)

        XCTAssertEqual(result, .failed(AppConstants.StatusText.invalidRuntimeURL))
        XCTAssertEqual(shell.openedWebURLs, [])
    }
}

@MainActor
private final class FakeNavigationNativeShell: RuntimeNativeShell {
    var existingDirectories: Set<String>
    var pathStates: [String: RuntimePathState]
    var confirmCreateDirectoryResponses: [Bool]
    var confirmCreateDirectoryPaths: [String] = []
    var createdDirectoryURLs: [URL] = []
    var openedFileURLs: [URL] = []
    var openedWebURLs: [URL] = []
    var createDirectoryError: Error?

    init(
        existingDirectories: Set<String> = [],
        pathStates: [String: RuntimePathState] = [:],
        confirmCreateDirectoryResponses: [Bool] = [],
        createDirectoryError: Error? = nil
    ) {
        self.existingDirectories = existingDirectories
        self.pathStates = pathStates
        self.confirmCreateDirectoryResponses = confirmCreateDirectoryResponses
        self.createDirectoryError = createDirectoryError
    }

    func chooseDirectory(prompt: String) -> URL? {
        nil
    }

    func chooseUpdateBundle(prompt: String) -> URL? {
        nil
    }

    func chooseLogExportDestination(defaultName: String, prompt: String) -> URL? {
        nil
    }

    func logExportDestinationValidationMessage(for url: URL) -> String? {
        nil
    }

    func pathState(_ url: URL) -> RuntimePathState {
        pathStates[url.path] ?? (existingDirectories.contains(url.path) ? .directory : .missing)
    }

    func confirmCreateDirectory(path: String) -> Bool {
        confirmCreateDirectoryPaths.append(path)
        return confirmCreateDirectoryResponses.isEmpty ? false : confirmCreateDirectoryResponses.removeFirst()
    }

    func createDirectory(_ url: URL) throws {
        if let createDirectoryError {
            throw createDirectoryError
        }
        createdDirectoryURLs.append(url)
        existingDirectories.insert(url.path)
    }

    func copyDirectory(_ source: URL, to destination: URL) throws {}

    func openFileURL(_ url: URL) {
        openedFileURLs.append(url)
    }

    func openWebURL(_ url: URL) {
        openedWebURLs.append(url)
    }

    func relaunchHelper() {}

    func terminate() {}
}
