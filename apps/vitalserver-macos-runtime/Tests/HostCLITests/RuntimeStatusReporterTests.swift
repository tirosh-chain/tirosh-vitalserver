import Foundation
import Core
import Contracts
@testable import HostCLI
import XCTest

final class RuntimeStatusReporterTests: XCTestCase {
    func testWritesStatusDocumentAndRuntimeEvent() throws {
        let repository = RuntimeStatusRepositorySpy()
        let eventRepository = RuntimeEventRepositorySpy()
        let reporter = RuntimeStatusReporter(
            repository: repository,
            eventRepository: eventRepository,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm"),
            eventID: { "event-1" }
        )

        try reporter.writeStatus(
            .healthy,
            operation: .health,
            message: "runtime health check passed",
            updatedAt: "2026-05-22T00:00:00Z",
            runtimeVersion: "0.1.0",
            healthSnapshot: healthSnapshot(),
            latestBackup: URL(fileURLWithPath: "/product/backups/latest")
        )

        let document = try XCTUnwrap(repository.saved)
        XCTAssertEqual(document.status, .healthy)
        XCTAssertEqual(document.operation, .health)
        XCTAssertEqual(document.productRoot, "/product")
        XCTAssertEqual(document.runtimeHome, "/product/vm")
        XCTAssertEqual(document.runtimeVersion, "0.1.0")
        XCTAssertEqual(document.latestBackup, "/product/backups/latest")

        let event = try XCTUnwrap(eventRepository.events.first)
        XCTAssertEqual(event.id, "event-1")
        XCTAssertEqual(event.eventType, .statusChanged)
        XCTAssertEqual(event.status, .healthy)
        XCTAssertNil(event.previousStatus)
        XCTAssertEqual(event.operation, .health)
        XCTAssertEqual(event.message, "runtime health check passed")
    }

    func testWritesProgressAsTypedWorkflowStepAndRuntimeEvent() throws {
        let repository = RuntimeStatusRepositorySpy()
        repository.loaded = statusDocument(status: .healthy)
        let eventRepository = RuntimeEventRepositorySpy()
        let reporter = RuntimeStatusReporter(
            repository: repository,
            eventRepository: eventRepository,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm"),
            eventID: { "event-2" }
        )

        try reporter.writeProgress(
            .updating,
            operation: .applyBundle,
            step: .activateGuestUpdate,
            stepStatus: .started,
            phase: .running,
            message: "step started",
            updatedAt: "2026-05-22T00:00:00Z",
            runtimeVersion: "0.1.0",
            healthSnapshot: healthSnapshot(),
            latestBackup: nil
        )

        let progress = try XCTUnwrap(repository.saved?.progress)
        XCTAssertEqual(progress.operation, .applyBundle)
        XCTAssertEqual(progress.step, .activateGuestUpdate)
        XCTAssertEqual(progress.stepStatus, .started)
        XCTAssertEqual(progress.phase, .running)

        let event = try XCTUnwrap(eventRepository.events.first)
        XCTAssertEqual(event.id, "event-2")
        XCTAssertEqual(event.eventType, .progressUpdated)
        XCTAssertEqual(event.status, .updating)
        XCTAssertEqual(event.previousStatus, .healthy)
        XCTAssertEqual(event.progress?.step, .activateGuestUpdate)
    }

    func testStatusValueReadsRepositoryStatus() {
        let repository = RuntimeStatusRepositorySpy()
        repository.loaded = statusDocument(
            status: .degraded,
            operation: .watchdog,
            message: "watchdog recovery failed",
            failureReasons: [.hostProxyHTTP("failed")]
        )

        let reporter = RuntimeStatusReporter(
            repository: repository,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        XCTAssertEqual(reporter.statusValue(), "degraded")
    }

    func testRecentEventsReadEventRepository() {
        let repository = RuntimeStatusRepositorySpy()
        let eventRepository = RuntimeEventRepositorySpy()
        eventRepository.events = [
            runtimeEvent(id: "event-1", status: .healthy),
            runtimeEvent(id: "event-2", status: .degraded),
        ]
        let reporter = RuntimeStatusReporter(
            repository: repository,
            eventRepository: eventRepository,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        XCTAssertEqual(reporter.recentEvents(limit: 1).map(\.id), ["event-2"])
    }

    private func statusDocument(
        status: RuntimeStatusLevel,
        operation: RuntimeOperation = .health,
        message: String = "message",
        failureReasons: [RuntimeFailureReason] = []
    ) -> RuntimeStatusDocument {
        RuntimeStatusDocument(
            product: "TiroshVitalServer",
            status: status,
            operation: operation,
            message: message,
            updatedAt: "2026-05-22T00:00:00Z",
            productRoot: "/product",
            runtimeHome: "/product/vm",
            runtimeVersion: "0.1.0",
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmIP: nil,
            proxyPort: 80,
            hostProxyHTTP: "failed",
            guestHTTP: "missing-vm-ip",
            redisUIHTTP: nil,
            swaggerUIHTTP: nil,
            rootfsBase: .present,
            vmDisk: .present,
            failureReasons: failureReasons,
            latestBackup: nil
        )
    }

    private func runtimeEvent(id: String, status: RuntimeStatusLevel) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id,
            eventType: .statusChanged,
            timestamp: "2026-05-22T00:00:00Z",
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

    private func healthSnapshot() -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: true,
            proxyExecutable: true,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmIP: "192.168.64.2",
            proxyPort: 80,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            failureReasons: []
        )
    }
}

private final class RuntimeStatusRepositorySpy: RuntimeStatusRepository {
    var loaded: RuntimeStatusDocument?
    var saved: RuntimeStatusDocument?

    func load() -> RuntimeStatusDocument? {
        loaded
    }

    func save(_ document: RuntimeStatusDocument) throws {
        saved = document
    }
}

private final class RuntimeEventRepositorySpy: RuntimeEventRepository {
    var events: [RuntimeEventDocument] = []

    func append(_ event: RuntimeEventDocument) throws {
        events.append(event)
    }

    func recent(limit: Int) -> [RuntimeEventDocument] {
        Array(events.suffix(limit))
    }
}
