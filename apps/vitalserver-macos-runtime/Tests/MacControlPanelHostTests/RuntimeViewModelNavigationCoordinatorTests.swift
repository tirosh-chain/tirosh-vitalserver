import Foundation
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class RuntimeViewModelNavigationCoordinatorTests: XCTestCase {
    func testOpenFolderOpensExistingDirectory() {
        let shell = FakeNavigationNativeShell(existingDirectories: ["/runtime/data"])
        let coordinator = RuntimeViewModelNavigationCoordinator()

        let message = coordinator.openFolder("/runtime/data", nativeShell: shell)

        XCTAssertNil(message)
        XCTAssertEqual(shell.openedFileURLs, [URL(fileURLWithPath: "/runtime/data")])
        XCTAssertEqual(shell.confirmCreateDirectoryPaths, [])
    }

    func testOpenFolderCreatesMissingDirectoryWhenConfirmed() {
        let shell = FakeNavigationNativeShell(
            existingDirectories: [],
            confirmCreateDirectoryResponses: [true]
        )
        let coordinator = RuntimeViewModelNavigationCoordinator()

        let message = coordinator.openFolder("/runtime/data", nativeShell: shell)

        XCTAssertNil(message)
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
        let coordinator = RuntimeViewModelNavigationCoordinator()

        let message = coordinator.openFolder("/runtime/data", nativeShell: shell)

        XCTAssertEqual(
            message,
            AppConstants.StatusText.folderCreateFailed(CocoaError(.fileWriteNoPermission).localizedDescription)
        )
        XCTAssertEqual(shell.openedFileURLs, [])
    }

    func testOpenWebURLIgnoresInvalidURLs() {
        let shell = FakeNavigationNativeShell()
        let coordinator = RuntimeViewModelNavigationCoordinator()

        coordinator.openWebURL("http://[::1", nativeShell: shell)
        coordinator.openWebURL("https://example.test", nativeShell: shell)

        XCTAssertEqual(shell.openedWebURLs, [URL(string: "https://example.test")])
    }
}

@MainActor
private final class FakeNavigationNativeShell: RuntimeNativeShell {
    var existingDirectories: Set<String>
    var confirmCreateDirectoryResponses: [Bool]
    var confirmCreateDirectoryPaths: [String] = []
    var createdDirectoryURLs: [URL] = []
    var openedFileURLs: [URL] = []
    var openedWebURLs: [URL] = []
    var createDirectoryError: Error?

    init(
        existingDirectories: Set<String> = [],
        confirmCreateDirectoryResponses: [Bool] = [],
        createDirectoryError: Error? = nil
    ) {
        self.existingDirectories = existingDirectories
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

    func directoryExists(_ url: URL) -> Bool {
        existingDirectories.contains(url.path)
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

    func openFileURL(_ url: URL) {
        openedFileURLs.append(url)
    }

    func openWebURL(_ url: URL) {
        openedWebURLs.append(url)
    }

    func relaunchHelper() {}

    func terminate() {}
}
