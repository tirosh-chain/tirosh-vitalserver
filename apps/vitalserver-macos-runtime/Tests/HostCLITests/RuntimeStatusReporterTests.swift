import Foundation
import Core
import Contracts
@testable import HostCLI
import XCTest

final class RuntimeStatusReporterTests: XCTestCase {
    func testWritesStatusDocumentThroughRepository() throws {
        let repository = RuntimeStatusRepositorySpy()
        let reporter = RuntimeStatusReporter(
            repository: repository,
            productIdentifier: Constants.Product.identifier,
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
        XCTAssertEqual(document.vmState, .running)
        XCTAssertEqual(document.vmErrors ?? [], [])
        XCTAssertEqual(document.latestBackup, "/product/backups/latest")
    }

    func testWritesProgressAsTypedWorkflowStep() throws {
        let repository = RuntimeStatusRepositorySpy()
        repository.loaded = RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: "VitalServerHelper",
            status: .healthy,
            operation: .health,
            message: "runtime health check passed",
            updatedAt: "2026-05-22T00:00:00Z",
            productRoot: "/product",
            runtimeHome: "/product/vm",
            runtimeVersion: "0.1.0",
            healthSnapshot: healthSnapshot(),
            latestBackup: nil
        ))
        let reporter = RuntimeStatusReporter(
            repository: repository,
            productIdentifier: Constants.Product.identifier,
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
            latestBackup: nil
        )

        XCTAssertEqual(repository.saved?.vmState, .running)
        let progress = try XCTUnwrap(repository.saved?.progress)
        XCTAssertEqual(progress.operation, .applyBundle)
        XCTAssertEqual(progress.step, .activateGuestUpdate)
        XCTAssertEqual(progress.stepStatus, .started)
        XCTAssertEqual(progress.phase, .running)
    }

    func testWriteProgressRequiresExistingStatusDocument() {
        let reporter = RuntimeStatusReporter(
            repository: RuntimeStatusRepositorySpy(),
            productIdentifier: Constants.Product.identifier,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        XCTAssertThrowsError(try reporter.writeProgress(
            .updating,
            operation: .applyBundle,
            step: .activateGuestUpdate,
            stepStatus: .started,
            phase: .running,
            message: "step started",
            updatedAt: "2026-05-22T00:00:00Z",
            runtimeVersion: "0.1.0",
            latestBackup: nil
        )) { error in
            XCTAssertEqual(error as? RuntimeStatusReporterError, .missingStatusDocumentForProgress)
        }
    }

    func testWriteProgressReportsStatusDocumentReadFailure() {
        let repository = RuntimeStatusRepositorySpy()
        repository.result = .failed("not-json")
        let reporter = RuntimeStatusReporter(
            repository: repository,
            productIdentifier: Constants.Product.identifier,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        XCTAssertThrowsError(try reporter.writeProgress(
            .updating,
            operation: .applyBundle,
            step: .activateGuestUpdate,
            stepStatus: .started,
            phase: .running,
            message: "step started",
            updatedAt: "2026-05-22T00:00:00Z",
            runtimeVersion: "0.1.0",
            latestBackup: nil
        )) { error in
            XCTAssertEqual(error as? RuntimeStatusReporterError, .statusDocumentReadFailed("not-json"))
        }
    }

    func testStatusValueReadsRepositoryStatus() {
        let repository = RuntimeStatusRepositorySpy()
        repository.loaded = RuntimeStatusDocument(
            product: "VitalServerHelper",
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
            guestHTTP: RuntimeHTTPStatusText.missingVMIP,
            redisUIHTTP: nil,
            swaggerUIHTTP: nil,
            rootfsBase: .present,
            vmDisk: .present,
            failureReasons: [.hostProxyHTTP("failed")],
            latestBackup: nil
        )

        let reporter = RuntimeStatusReporter(
            repository: repository,
            productIdentifier: Constants.Product.identifier,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        XCTAssertEqual(reporter.statusValue(), "degraded")
    }

    func testStatusValueReturnsNilWhenStatusDocumentIsMissing() {
        let reporter = RuntimeStatusReporter(
            repository: RuntimeStatusRepositorySpy(),
            productIdentifier: Constants.Product.identifier,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        XCTAssertNil(reporter.statusValue())
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
            vmState: .running,
            vmErrors: [],
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
    var result: RuntimeStatusDocumentLoadResult = .missing
    var saved: RuntimeStatusDocument?

    var loaded: RuntimeStatusDocument? {
        get {
            guard case .loaded(let document) = result else {
                return nil
            }
            return document
        }
        set {
            result = newValue.map(RuntimeStatusDocumentLoadResult.loaded) ?? .missing
        }
    }

    func loadResult() -> RuntimeStatusDocumentLoadResult {
        result
    }

    func save(_ document: RuntimeStatusDocument) throws {
        saved = document
    }
}
