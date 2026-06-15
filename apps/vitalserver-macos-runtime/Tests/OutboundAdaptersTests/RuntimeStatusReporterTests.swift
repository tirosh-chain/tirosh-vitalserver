import Foundation
import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors

final class RuntimeStatusReporterTests: XCTestCase {
    private let productIdentifier = "VitalServerHelper"

    func testWritesStatusDocumentThroughRepository() throws {
        let repository = RuntimeStatusRepositorySpy()
        let reporter = makeReporter(
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
        XCTAssertEqual(document.vmState, .running)
        XCTAssertEqual(document.vmErrors ?? [], [])
        XCTAssertEqual(document.latestBackup, "/product/backups/latest")
    }

    func testWritesInjectedStatusDocumentWithoutOwningBuildPolicy() throws {
        let repository = RuntimeStatusRepositorySpy()
        var receivedInput: RuntimeStatusDocumentBuildInput?
        let injectedDocument = RuntimeStatusDocument(
            schemaVersion: 2,
            product: "InjectedProduct",
            status: .degraded,
            operation: .watchdog,
            message: "injected",
            updatedAt: "2026-05-22T00:00:00Z",
            productRoot: "/injected/product",
            runtimeHome: "/injected/runtime",
            runtimeVersion: "9.9.9",
            vmService: .notLoaded,
            proxyService: .notLoaded,
            watchdogService: .loaded,
            vmIP: nil,
            proxyPort: nil,
            hostProxyHTTP: "missing-proxy-port",
            guestHTTP: "missing",
            redisUIHTTP: nil,
            swaggerUIHTTP: nil,
            rootfsBase: .missing,
            vmDisk: .missing,
            failureReasons: [.vmService("not-loaded")],
            latestBackup: nil
        )
        let reporter = makeReporter(
            repository: repository,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm"),
            makeStatusDocument: { input in
                receivedInput = input
                return injectedDocument
            }
        )

        try reporter.writeStatus(
            .healthy,
            operation: .health,
            message: "runtime health check passed",
            updatedAt: "2026-05-22T00:00:00Z",
            runtimeVersion: "0.1.0",
            healthSnapshot: healthSnapshot(),
            latestBackup: nil
        )

        XCTAssertEqual(receivedInput?.product, productIdentifier)
        XCTAssertEqual(receivedInput?.productRoot, "/product")
        XCTAssertEqual(repository.saved, injectedDocument)
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
        let reporter = makeReporter(
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
            latestBackup: nil
        )

        XCTAssertEqual(repository.saved?.vmState, .running)
        let progress = try XCTUnwrap(repository.saved?.progress)
        XCTAssertEqual(progress.operation, .applyBundle)
        XCTAssertEqual(progress.step, .activateGuestUpdate)
        XCTAssertEqual(progress.stepStatus, .started)
        XCTAssertEqual(progress.phase, .running)
    }

    func testWriteProgressDoesNotPreservePreviousLatestBackupWhenCurrentReadReportsNone() throws {
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
            latestBackup: "/product/backups/old"
        ))
        let reporter = makeReporter(
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
            latestBackup: nil
        )

        XCTAssertNil(repository.saved?.latestBackup)
    }

    func testWriteProgressRequiresExistingStatusDocument() {
        let reporter = makeReporter(
            repository: RuntimeStatusRepositorySpy(),
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
        let reporter = makeReporter(
            repository: repository,
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

    private func healthSnapshot() -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: .executable,
            proxyExecutable: .executable,
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

    private func makeReporter(
        repository: RuntimeStatusRepository,
        productRoot: URL,
        runtimeHome: URL,
        makeStatusDocument: @escaping (RuntimeStatusDocumentBuildInput) -> RuntimeStatusDocument =
            BuildRuntimeStatusDocumentUseCase().build,
        makeProgressDocument: @escaping (RuntimeStatusProgressUpdateInput) -> RuntimeStatusDocument =
            BuildRuntimeStatusDocumentUseCase().progressUpdate
    ) -> RuntimeStatusReporter {
        RuntimeStatusReporter(
            repository: repository,
            productIdentifier: productIdentifier,
            productRoot: productRoot,
            runtimeHome: runtimeHome,
            makeStatusDocument: makeStatusDocument,
            makeProgressDocument: makeProgressDocument
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
