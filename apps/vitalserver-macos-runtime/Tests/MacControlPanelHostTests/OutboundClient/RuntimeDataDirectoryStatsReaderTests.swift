import Application
import Contracts
import Foundation
@testable import OutboundAdapters
import RuntimeControl
import XCTest
import Errors

final class RuntimeDataDirectoryStatsReaderTests: XCTestCase {
    func testReadCountsNestedNonHiddenFiles() throws {
        let directory = try temporaryDirectory()
        let dataDirectory = directory.appendingPathComponent("vital-files", isDirectory: true)
        let nested = dataDirectory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 3).write(to: dataDirectory.appendingPathComponent("one.vital"))
        try Data(repeating: 1, count: 5).write(to: nested.appendingPathComponent("two.vital"))
        try Data(repeating: 1, count: 7).write(to: nested.appendingPathComponent(".hidden.vital"))

        let stats = RuntimeDataDirectoryStatsReader(fileStore: SystemRuntimeFileStore())
            .read(path: dataDirectory.path)

        XCTAssertEqual(stats, .loaded(RuntimeDataDirectoryStats(fileCount: 2, sizeBytes: 8)))
    }

    func testReadPreservesMissingRootAsMissingState() throws {
        let stats = RuntimeDataDirectoryStatsReader(fileStore: DataDirectoryStatsFileStore())
            .read(path: "/data")

        XCTAssertEqual(stats, .missing(path: "/data"))
    }

    func testReadPreservesRootInspectionFailure() throws {
        let reader = RuntimeDataDirectoryStatsReader(fileStore: DataDirectoryStatsFileStore(
            pathStates: ["/data": .inspectFailed("permission denied")]
        ))

        XCTAssertEqual(
            reader.read(path: "/data"),
            .failed("data directory path inspection failed path=/data reason=permission denied")
        )
    }

    func testReadPreservesUnexpectedRootPathState() throws {
        let reader = RuntimeDataDirectoryStatsReader(fileStore: DataDirectoryStatsFileStore(
            pathStates: ["/data": .file]
        ))

        XCTAssertEqual(
            reader.read(path: "/data"),
            .failed("data directory path state is unexpected path=/data state=file")
        )
    }

    func testReadPreservesListedEntryMissingDuringTraversal() throws {
        let staleEntry = URL(fileURLWithPath: "/data/stale.vital")
        let reader = RuntimeDataDirectoryStatsReader(fileStore: DataDirectoryStatsFileStore(
            pathStates: [
                "/data": .directory,
                staleEntry.path: .missing,
            ],
            directoryContents: [
                "/data": [staleEntry],
            ]
        ))

        XCTAssertEqual(
            reader.read(path: "/data"),
            .failed("data directory listed path is missing during traversal path=/data/stale.vital")
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class DataDirectoryStatsFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let pathStates: [String: RuntimePathState]
    private let directoryContents: [String: [URL]]
    private let fileSizes: [String: UInt64]

    init(
        pathStates: [String: RuntimePathState] = [:],
        directoryContents: [String: [URL]] = [:],
        fileSizes: [String: UInt64] = [:]
    ) {
        self.pathStates = pathStates
        self.directoryContents = directoryContents
        self.fileSizes = fileSizes
    }

    func fileExists(_ url: URL) -> Bool { pathStates[url.path] == .file }
    func directoryExists(_ url: URL) -> Bool { pathStates[url.path] == .directory }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func pathState(at url: URL) -> RuntimePathState { pathStates[url.path] ?? .missing }
    func readData(_ url: URL) throws -> Data { throw CocoaError(.fileReadNoSuchFile) }
    func readUTF8Text(_ url: URL) throws -> String { throw CocoaError(.fileReadNoSuchFile) }
    func fileSize(_ url: URL) throws -> UInt64 {
        guard let size = fileSizes[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return size
    }
    func modificationDate(_ url: URL) throws -> Date { throw CocoaError(.fileReadNoSuchFile) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        directoryContents[url.path] ?? []
    }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] {
        []
    }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 {
        throw CocoaError(.fileReadNoSuchFile)
    }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        throw CocoaError(.fileReadNoSuchFile)
    }
}
