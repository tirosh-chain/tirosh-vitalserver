import Application
import Contracts
import Errors
import OutboundAdapters
import XCTest

final class JSONFileRuntimeOperationLeaseRepositoryTests: XCTestCase {
    func testAcquireLoadAndReleaseOperationLease() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)
        let document = operationLease(operationId: "lease-1", operation: .applyBundle)

        try repository.acquire(document)

        guard case .loaded(let loaded) = repository.loadResult() else {
            return XCTFail("Expected loaded operation lease")
        }
        XCTAssertEqual(loaded, document)

        try repository.release(operationId: "lease-1")
        XCTAssertEqual(repository.loadResult(), .missing)

        try? FileManager.default.removeItem(at: directory)
    }

    func testAcquireFailsWhenOperationLeaseAlreadyExists() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)
        try repository.acquire(operationLease(operationId: "lease-1", operation: .applyBundle))

        XCTAssertThrowsError(try repository.acquire(operationLease(operationId: "lease-2", operation: .rollback))) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseRepositoryError,
                .existingOperation(operationId: "lease-1", operation: "apply-bundle")
            )
        }

        try? FileManager.default.removeItem(at: directory)
    }

    func testAcquireHeartbeatAndReleaseUseFileLock() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        let fileLock = RecordingOperationLeaseFileLock()
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url, fileLock: fileLock)

        try repository.acquire(operationLease(operationId: "lease-1", operation: .applyBundle))
        try repository.heartbeat(
            operationId: "lease-1",
            heartbeatAt: "2026-05-22T00:10:00Z",
            expiresAt: "2026-05-22T01:10:00Z"
        )
        try repository.release(operationId: "lease-1")

        XCTAssertEqual(fileLock.lockedURLs, [url, url, url])

        try? FileManager.default.removeItem(at: directory)
    }

    func testReleaseFailsWhenOperationIdDoesNotMatch() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)
        try repository.acquire(operationLease(operationId: "lease-1", operation: .applyBundle))

        XCTAssertThrowsError(try repository.release(operationId: "lease-2")) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseRepositoryError,
                .operationIdMismatch(expected: "lease-2", actual: "lease-1")
            )
        }
        guard case .loaded(let loaded) = repository.loadResult() else {
            return XCTFail("Expected mismatched release to preserve lease")
        }
        XCTAssertEqual(loaded.operationId, "lease-1")

        try? FileManager.default.removeItem(at: directory)
    }

    func testHeartbeatUpdatesLeaseHeartbeatAndExpiration() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)
        try repository.acquire(operationLease(operationId: "lease-1", operation: .applyBundle))

        try repository.heartbeat(
            operationId: "lease-1",
            heartbeatAt: "2026-05-22T00:10:00Z",
            expiresAt: "2026-05-22T01:10:00Z"
        )

        guard case .loaded(let loaded) = repository.loadResult() else {
            return XCTFail("Expected heartbeat to preserve loaded operation lease")
        }
        XCTAssertEqual(loaded.operationId, "lease-1")
        XCTAssertEqual(loaded.startedAt, "2026-05-22T00:00:00Z")
        XCTAssertEqual(loaded.heartbeatAt, "2026-05-22T00:10:00Z")
        XCTAssertEqual(loaded.expiresAt, "2026-05-22T01:10:00Z")

        try? FileManager.default.removeItem(at: directory)
    }

    func testHeartbeatFailsWhenOperationIdDoesNotMatch() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)
        try repository.acquire(operationLease(operationId: "lease-1", operation: .applyBundle))

        XCTAssertThrowsError(try repository.heartbeat(
            operationId: "lease-2",
            heartbeatAt: "2026-05-22T00:10:00Z",
            expiresAt: "2026-05-22T01:10:00Z"
        )) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseRepositoryError,
                .operationIdMismatch(expected: "lease-2", actual: "lease-1")
            )
        }

        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadResultReportsInvalidOperationLeaseDocument() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: url)
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)

        guard case .failed(let message) = repository.loadResult() else {
            return XCTFail("Expected failed operation lease load")
        }
        XCTAssertFalse(message.isEmpty)

        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadResultReportsDirectoryAtOperationLeasePath() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)

        guard case .failed(let message) = repository.loadResult() else {
            return XCTFail("Expected failed operation lease load")
        }
        XCTAssertTrue(message.contains("path state is unexpected"))
        XCTAssertTrue(message.contains("state=directory"))
    }

    func testLoadResultReportsInjectedPathInspectionFailure() {
        let url = URL(fileURLWithPath: "/runtime/operation-lease.json")
        let fileStore = OperationLeaseFileStore()
        fileStore.pathStates[url.path] = .inspectFailed("permission denied")
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url, fileStore: fileStore)

        XCTAssertEqual(
            repository.loadResult(),
            .failed("runtime operation lease path inspection failed path=/runtime/operation-lease.json reason=permission denied")
        )
    }

    func testAcquireAndReleaseUseInjectedFileStore() throws {
        let url = URL(fileURLWithPath: "/runtime/operation-lease.json")
        let fileStore = OperationLeaseFileStore()
        let repository = JSONFileRuntimeOperationLeaseRepository(
            url: url,
            fileStore: fileStore,
            fileLock: NoopOperationLeaseFileLock()
        )
        let document = operationLease(operationId: "lease-1", operation: .applyBundle)

        try repository.acquire(document)

        XCTAssertEqual(fileStore.createdDirectories, [url.deletingLastPathComponent()])
        guard case .loaded(let loaded) = repository.loadResult() else {
            return XCTFail("Expected loaded operation lease from injected file store")
        }
        XCTAssertEqual(loaded, document)

        try repository.release(operationId: "lease-1")

        XCTAssertEqual(fileStore.removed, [url])
        XCTAssertEqual(repository.loadResult(), .missing)
    }

    private func operationLease(
        operationId: String,
        operation: RuntimeOperation
    ) -> RuntimeOperationLeaseDocument {
        RuntimeOperationLeaseDocument(
            operationId: operationId,
            operation: operation,
            ownerPID: 123,
            startedAt: "2026-05-22T00:00:00Z",
            heartbeatAt: "2026-05-22T00:00:00Z",
            expiresAt: nil,
            message: nil
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private struct NoopOperationLeaseFileLock: RuntimeFileLocking {
    func withExclusiveLock<T>(for url: URL, _ body: () throws -> T) throws -> T {
        try body()
    }
}

private final class RecordingOperationLeaseFileLock: RuntimeFileLocking {
    private(set) var lockedURLs: [URL] = []

    func withExclusiveLock<T>(for url: URL, _ body: () throws -> T) throws -> T {
        lockedURLs.append(url)
        return try body()
    }
}

private final class OperationLeaseFileStore: RuntimeFileReading, RuntimeFileWriting {
    var files: [URL: Data] = [:]
    var pathStates: [String: RuntimePathState] = [:]
    var createdDirectories: [URL] = []
    var removed: [URL] = []

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
        removed.append(url)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
        files.removeValue(forKey: source)
    }
}
