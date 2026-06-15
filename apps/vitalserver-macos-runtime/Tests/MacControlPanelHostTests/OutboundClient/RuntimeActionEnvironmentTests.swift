import XCTest
import Application
import Contracts
import Errors
@testable import OutboundAdapters
@testable import MacControlPanelHost
@testable import InboundAdapters

@MainActor
final class RuntimeActionEnvironmentTests: XCTestCase {
    func testWritesAndRemovesAdminPasswordFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeActionEnvironmentTests", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = SystemRuntimeActionEnvironment(
            temporaryDirectory: directory,
            adminPasswordFileID: { "fixed-id" }
        )

        let url = try environment.writeAdminPasswordFile("secret")
        defer { try? environment.removeItem(at: url) }

        XCTAssertEqual(
            url,
            directory.appendingPathComponent("tirosh-vitalserver-admin-password-fixed-id")
        )
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "secret")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try environment.removeItem(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAdminPasswordFileWriteFailurePreservesPathAndReason() {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        let environment = SystemRuntimeActionEnvironment(
            fileStore: FailingAdminPasswordFileStore(writeError: CocoaError(.fileWriteNoPermission)),
            temporaryDirectory: directory,
            adminPasswordFileID: { "fixed-id" }
        )
        let expectedPath = directory
            .appendingPathComponent("tirosh-vitalserver-admin-password-fixed-id")
            .path

        XCTAssertThrowsError(try environment.writeAdminPasswordFile("secret")) { error in
            guard case RuntimeActionEnvironmentError.adminPasswordFileCreateFailed(let path, let reason) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(path, expectedPath)
            XCTAssertFalse(reason.isEmpty)
        }
    }

}

private final class FailingAdminPasswordFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
    private let writeError: Error

    init(writeError: Error) {
        self.writeError = writeError
    }

    func fileExists(_ url: URL) -> Bool { false }
    func directoryExists(_ url: URL) -> Bool { false }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func fileState(atPath path: String) -> RuntimeFileState { .missing }
    func pathState(at url: URL) -> RuntimePathState { .missing }
    func readData(_ url: URL) throws -> Data { throw CocoaError(.fileReadNoSuchFile) }
    func readUTF8Text(_ url: URL) throws -> String { throw CocoaError(.fileReadNoSuchFile) }
    func fileSize(_ url: URL) throws -> UInt64 { throw CocoaError(.fileReadNoSuchFile) }
    func modificationDate(_ url: URL) throws -> Date { throw CocoaError(.fileReadNoSuchFile) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws { throw writeError }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {
        throw writeError
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 { 0 }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 0)
    }
}
