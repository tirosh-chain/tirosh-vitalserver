import Contracts
import HostInfrastructure
import XCTest

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

        XCTAssertEqual(page.events.map(\.id), ["event-1"])
        XCTAssertEqual(page.matchingCount, 1)
        XCTAssertNotNil(page.readError)
        XCTAssertTrue(page.readError?.contains("invalidLine") == true)
    }

    func testAllResultReportsUnreadableEventLog() throws {
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
        guard case .readFailed(let path, let message) = result.issues[0] else {
            return XCTFail("Expected read failure issue")
        }
        XCTAssertEqual(path, url.path)
        XCTAssertFalse(message.isEmpty)
    }

    private func event(id: String, status: RuntimeStatusLevel) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id,
            eventType: .statusChanged,
            timestamp: "2026-05-24T00:00:00Z",
            product: "TiroshVitalServer",
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
