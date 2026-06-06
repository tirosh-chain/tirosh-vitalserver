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
