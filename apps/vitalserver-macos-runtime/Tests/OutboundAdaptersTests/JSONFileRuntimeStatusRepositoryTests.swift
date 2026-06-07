import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors

final class JSONFileRuntimeStatusRepositoryTests: XCTestCase {
    func testSaveAndLoadRuntimeStatusDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        let repository = JSONFileRuntimeStatusRepository(url: url)

        try repository.save(document(message: "runtime health check passed"))

        guard case .loaded(let loaded) = repository.loadResult() else {
            return XCTFail("Expected loaded status document")
        }
        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertEqual(loaded.status, .healthy)
        XCTAssertEqual(loaded.operation, .health)
        XCTAssertEqual(loaded.message, "runtime health check passed")
        XCTAssertEqual(loaded.failureReasons, [])
        XCTAssertEqual(loaded.progress?.phase, .completed)

        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadReturnsNilWhenStatusFileIsMissing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(RuntimeFileNames.runtimeStatus)
        let repository = JSONFileRuntimeStatusRepository(url: url)

        XCTAssertEqual(repository.loadResult(), .missing)
    }

    func testLoadResultReportsInvalidStatusDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: url)
        let repository = JSONFileRuntimeStatusRepository(url: url)

        guard case .failed(let message) = repository.loadResult() else {
            return XCTFail("Expected failed status document load")
        }
        XCTAssertFalse(message.isEmpty)

        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadResultReportsDirectoryAtStatusDocumentPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let repository = JSONFileRuntimeStatusRepository(url: url)

        guard case .failed(let message) = repository.loadResult() else {
            return XCTFail("Expected failed status document load")
        }
        XCTAssertTrue(message.contains("path state is unexpected"))
        XCTAssertTrue(message.contains("state=directory"))
    }

    func testSaveAndLoadUseInjectedFileStore() throws {
        let url = URL(fileURLWithPath: "/runtime/status.json")
        let fileStore = StatusRepositoryFileStore()
        let repository = JSONFileRuntimeStatusRepository(url: url, fileStore: fileStore)

        try repository.save(document(message: "runtime health check passed"))

        XCTAssertEqual(fileStore.createdDirectories, [url.deletingLastPathComponent()])
        guard case .loaded(let loaded) = repository.loadResult() else {
            return XCTFail("Expected loaded status document from injected file store")
        }
        XCTAssertEqual(loaded.message, "runtime health check passed")
    }

    func testLoadResultReportsInjectedPathInspectionFailure() {
        let url = URL(fileURLWithPath: "/runtime/status.json")
        let fileStore = StatusRepositoryFileStore()
        fileStore.pathStates[url.path] = .inspectFailed("permission denied")
        let repository = JSONFileRuntimeStatusRepository(url: url, fileStore: fileStore)

        XCTAssertEqual(
            repository.loadResult(),
            .failed("runtime status document path inspection failed path=/runtime/status.json reason=permission denied")
        )
    }

    private func document(message: String) -> RuntimeStatusDocument {
        RuntimeStatusDocument(
            schemaVersion: 2,
            product: "VitalServerHelper",
            status: .healthy,
            operation: .health,
            message: message,
            updatedAt: "2026-05-21T12:33:57Z",
            productRoot: "/Library/Application Support/VitalServerHelper",
            runtimeHome: "/Library/Application Support/VitalServerHelper/vm",
            runtimeVersion: "0.1.4",
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmIP: "192.168.64.2",
            proxyPort: 80,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            rootfsBase: .present,
            vmDisk: .present,
            failureReasons: [],
            latestBackup: nil,
            progress: RuntimeProgressDocument(
                operation: .health,
                phase: .completed,
                step: nil,
                stepStatus: .completed,
                message: message,
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-05-21T12:33:57Z"
            )
        )
    }
}

private final class StatusRepositoryFileStore: RuntimeFileReading, RuntimeFileWriting {
    var files: [URL: Data] = [:]
    var pathStates: [String: RuntimePathState] = [:]
    var createdDirectories: [URL] = []

    func fileExists(_ url: URL) -> Bool {
        files[url] != nil
    }

    func directoryExists(_ url: URL) -> Bool {
        createdDirectories.contains(url)
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
        createdDirectories.append(url)
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url)
        pathStates[url.path] = .missing
    }

    func copyItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
        files.removeValue(forKey: source)
    }
}
