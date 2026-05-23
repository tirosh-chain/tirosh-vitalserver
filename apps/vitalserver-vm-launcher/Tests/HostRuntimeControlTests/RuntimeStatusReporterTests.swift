import Foundation
import RuntimeCore
@testable import HostRuntimeControl
import XCTest

final class RuntimeStatusReporterTests: XCTestCase {
    func testWritesStatusDocumentThroughRepository() throws {
        let repository = RuntimeStatusRepositorySpy()
        let reporter = RuntimeStatusReporter(
            repository: repository,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
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
    }

    func testWritesProgressAsTypedWorkflowStep() throws {
        let repository = RuntimeStatusRepositorySpy()
        let reporter = RuntimeStatusReporter(
            repository: repository,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
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
    }

    func testStatusValueReadsRepositoryStatus() {
        let repository = RuntimeStatusRepositorySpy()
        repository.loaded = RuntimeStatusDocument(
            product: "TiroshVitalServer",
            status: .degraded,
            operation: .watchdog,
            message: "watchdog recovery failed",
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
            failureReasons: [.hostProxyHTTP("failed")],
            latestBackup: nil
        )

        let reporter = RuntimeStatusReporter(
            repository: repository,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        XCTAssertEqual(reporter.statusValue(), "degraded")
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
