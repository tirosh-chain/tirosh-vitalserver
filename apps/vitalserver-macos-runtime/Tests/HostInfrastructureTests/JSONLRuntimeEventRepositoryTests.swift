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
            progress: nil
        )
    }
}
