import Contracts
import Application
import OutboundAdapters
import XCTest
import Errors

final class JSONLRuntimeEventRepositoryTests: XCTestCase {
    func testAppendsAndReadsRecentRuntimeEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let repository = JSONLRuntimeEventRepository(
            url: directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        )

        try repository.append(event(id: "event-1", status: .healthy))
        try repository.append(event(id: "event-2", status: .degraded))

        XCTAssertEqual(repository.query(RuntimeEventQuery(limit: 1)).events.map(\.id), ["event-2"])
        XCTAssertEqual(repository.query(RuntimeEventQuery(limit: 10)).events.map(\.id), ["event-1", "event-2"])
    }

    func testRotatesRuntimeEventsAndReadsAcrossRotatedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        let repository = JSONLRuntimeEventRepository(
            url: url,
            rotationMaxBytes: 1,
            rotationKeepCount: 2
        )

        try repository.append(event(id: "event-1", status: .healthy))
        try repository.append(event(id: "event-2", status: .degraded))
        try repository.append(event(id: "event-3", status: .critical))

        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(url.path).1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(url.path).2"))
        XCTAssertEqual(repository.query(RuntimeEventQuery(limit: 10)).events.map(\.id), ["event-1", "event-2", "event-3"])
        XCTAssertEqual(repository.query(RuntimeEventQuery(limit: 2)).events.map(\.id), ["event-2", "event-3"])
    }

    func testAllResultReportsInvalidLinesWithoutDroppingValidEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        let repository = JSONLRuntimeEventRepository(url: url)
        try repository.append(event(id: "event-1", status: .healthy))
        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        handle.write(Data("{invalid-json}\n".utf8))

        let result = repository.allResult()

        XCTAssertEqual(result.events.map(\.id), ["event-1"])
        XCTAssertEqual(result.issues.count, 1)
        guard case .invalidLine(let path, let line, let message) = result.issues[0] else {
            return XCTFail("Expected invalid line issue")
        }
        XCTAssertEqual(path, url.path)
        XCTAssertEqual(line, 2)
        XCTAssertFalse(message.isEmpty)
    }

    func testQueryCarriesInvalidLineIssueWithoutDroppingValidEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        let repository = JSONLRuntimeEventRepository(url: url)
        try repository.append(event(id: "event-1", status: .healthy))
        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        handle.write(Data("{invalid-json}\n".utf8))

        let page = repository.query(RuntimeEventQuery(limit: 10))

        XCTAssertEqual(page.state, .partiallyLoaded)
        XCTAssertEqual(page.events.map(\.id), ["event-1"])
        XCTAssertEqual(page.matchingCount, 1)
        XCTAssertNotNil(page.readError)
        XCTAssertTrue(page.readError?.contains("invalidLine") == true)
    }

    func testAllResultReportsUnexpectedEventLogPathState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let repository = JSONLRuntimeEventRepository(url: url)

        let result = repository.allResult()

        XCTAssertEqual(result.events, [])
        XCTAssertEqual(result.issues.count, 1)
        guard case .unexpectedPathState(let path, let state) = result.issues[0] else {
            return XCTFail("Expected unexpected path state issue")
        }
        XCTAssertEqual(path, url.path)
        XCTAssertEqual(state, "directory")
    }

    func testAllResultReportsUnexpectedRotatedEventLogPathStateWithoutDroppingCurrentEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        let repository = JSONLRuntimeEventRepository(url: url, rotationKeepCount: 2)
        try repository.append(event(id: "event-1", status: .healthy))
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "\(url.path).1"), withIntermediateDirectories: true)

        let result = repository.allResult()

        XCTAssertEqual(result.events.map(\.id), ["event-1"])
        XCTAssertEqual(result.issues.count, 1)
        guard case .unexpectedPathState(let path, let state) = result.issues[0] else {
            return XCTFail("Expected unexpected path state issue")
        }
        XCTAssertEqual(path, "\(url.path).1")
        XCTAssertEqual(state, "directory")
    }

    func testAppendFailsWhenEventLogPathIsDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let repository = JSONLRuntimeEventRepository(url: url)

        XCTAssertThrowsError(try repository.append(event(id: "event-1", status: .healthy))) { error in
            XCTAssertEqual(
                error as? JSONLRuntimeEventRepositoryError,
                .unexpectedPathState(path: url.path, state: "directory")
            )
        }
    }

    func testAppendFailsWhenRotatedEventDestinationPathIsDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        let firstRotated = URL(fileURLWithPath: "\(url.path).1")
        let repository = JSONLRuntimeEventRepository(
            url: url,
            rotationMaxBytes: 1,
            rotationKeepCount: 1
        )
        try repository.append(event(id: "event-1", status: .healthy))
        try FileManager.default.createDirectory(at: firstRotated, withIntermediateDirectories: true)

        XCTAssertThrowsError(try repository.append(event(id: "event-2", status: .degraded))) { error in
            XCTAssertEqual(
                error as? JSONLRuntimeEventRepositoryError,
                .unexpectedPathState(path: firstRotated.path, state: "directory")
            )
        }
    }

    func testAppendAndQueryUseInjectedFileStore() throws {
        let url = URL(fileURLWithPath: "/runtime/events.jsonl")
        let fileStore = EventLogFileStore()
        let repository = JSONLRuntimeEventRepository(url: url, fileStore: fileStore)

        try repository.append(event(id: "event-1", status: .healthy))
        try repository.append(event(id: "event-2", status: .degraded))

        XCTAssertEqual(fileStore.createdDirectories.map(\.path), ["/runtime", "/runtime"])
        XCTAssertNotNil(fileStore.files[url])
        XCTAssertEqual(repository.query(RuntimeEventQuery(limit: 10)).events.map(\.id), ["event-1", "event-2"])
    }

    func testAllResultReportsInjectedPathInspectionFailure() {
        let url = URL(fileURLWithPath: "/runtime/events.jsonl")
        let fileStore = EventLogFileStore()
        fileStore.pathStates[url.path] = .inspectFailed("permission denied")
        let repository = JSONLRuntimeEventRepository(url: url, fileStore: fileStore)

        let result = repository.allResult()

        XCTAssertEqual(result.events, [])
        XCTAssertEqual(result.issues, [
            .pathInspectionFailed(path: url.path, message: "permission denied"),
        ])
    }

    private func event(id: String, status: RuntimeStatusLevel) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id,
            eventType: .statusChanged,
            timestamp: "2026-05-24T00:00:00Z",
            product: "VitalServerHelper",
            status: status,
            previousStatus: nil,
            operation: .health,
            message: "message",
            runtimeVersion: "0.1.0",
            failureReasons: [],
            containerObservation: nil,
            progress: nil
        )
    }
}

private final class EventLogFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    var files: [URL: Data] = [:]
    var pathStates: [String: RuntimePathState] = [:]
    var directories: Set<URL> = []
    var createdDirectories: [URL] = []

    func fileExists(_ url: URL) -> Bool {
        files[url] != nil
    }

    func directoryExists(_ url: URL) -> Bool {
        directories.contains(url)
    }

    func isExecutableFile(atPath path: String) -> Bool {
        false
    }

    func pathState(at url: URL) -> RuntimePathState {
        if let state = pathStates[url.path] {
            return state
        }
        if files[url] != nil {
            return .file
        }
        if directories.contains(url) {
            return .directory
        }
        return .missing
    }

    func readData(_ url: URL) throws -> Data {
        guard let data = files[url] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    func readUTF8Text(_ url: URL) throws -> String {
        String(decoding: try readData(url), as: UTF8.self)
    }

    func fileSize(_ url: URL) throws -> UInt64 {
        UInt64(try readData(url).count)
    }

    func modificationDate(_ url: URL) throws -> Date {
        Date(timeIntervalSince1970: 0)
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        files[url] = data
        pathStates[url.path] = .file
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {
        try writeData(data, to: url, options: options)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        directories.insert(url)
        createdDirectories.append(url)
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url)
        directories.remove(url)
        pathStates[url.path] = .missing
    }

    func copyItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
        pathStates[destination.path] = .file
    }

    func moveItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
        files.removeValue(forKey: source)
        pathStates[source.path] = .missing
        pathStates[destination.path] = .file
    }

    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        files.keys.filter { $0.deletingLastPathComponent() == url }
    }

    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] {
        directories.filter {
            $0.deletingLastPathComponent() == url && $0.lastPathComponent.contains(fragment)
        }
    }

    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 {
        files.reduce(UInt64(0)) { total, entry in
            entry.key.path.hasPrefix(url.path) ? total + UInt64(entry.value.count) : total
        }
    }

    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}
