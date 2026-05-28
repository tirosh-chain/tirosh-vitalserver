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

        XCTAssertEqual(repository.recent(limit: 1).map(\.id), ["event-2"])
        XCTAssertEqual(repository.recent(limit: 10).map(\.id), ["event-1", "event-2"])
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
        XCTAssertEqual(repository.recent(limit: 10).map(\.id), ["event-1", "event-2", "event-3"])
        XCTAssertEqual(repository.recent(limit: 2).map(\.id), ["event-2", "event-3"])
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
