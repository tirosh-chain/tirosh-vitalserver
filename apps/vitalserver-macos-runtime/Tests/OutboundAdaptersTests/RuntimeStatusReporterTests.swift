import Foundation
import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors

final class RuntimeStatusReporterTests: XCTestCase {
    private let productIdentifier = "VitalServerHelper"

    func testWritesStatusDocumentThroughArtifactSink() throws {
        let sink = RuntimeStatusArtifactSinkSpy()
        let reporter = makeReporter(
            statusArtifactSink: sink,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        try reporter.writeStatus(
            .healthy,
            runtimeVersion: "0.1.0",
            healthSnapshot: healthSnapshot(),
            latestBackup: URL(fileURLWithPath: "/product/backups/latest")
        )

        let document = try XCTUnwrap(sink.saved)
        XCTAssertEqual(document.status, .healthy)
        XCTAssertEqual(document.productRoot, "/product")
        XCTAssertEqual(document.runtimeHome, "/product/vm")
        XCTAssertEqual(document.runtimeVersion, "0.1.0")
        XCTAssertEqual(document.latestBackup, "/product/backups/latest")
    }

    func testWritesInjectedStatusDocumentWithoutOwningBuildPolicy() throws {
        let sink = RuntimeStatusArtifactSinkSpy()
        var receivedInput: RuntimeStatusDocumentBuildInput?
        let injectedDocument = RuntimeStatusDocument(
            schemaVersion: 2,
            product: "InjectedProduct",
            status: .degraded,
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
            latestBackup: nil
        )
        let reporter = makeReporter(
            statusArtifactSink: sink,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm"),
            makeStatusDocument: { input in
                receivedInput = input
                return injectedDocument
            }
        )

        try reporter.writeStatus(
            .healthy,
            runtimeVersion: "0.1.0",
            healthSnapshot: healthSnapshot(),
            latestBackup: nil
        )

        XCTAssertEqual(receivedInput?.product, productIdentifier)
        XCTAssertEqual(receivedInput?.productRoot, "/product")
        XCTAssertEqual(sink.saved, injectedDocument)
    }

    func testWritesProgressAsTypedWorkflowStep() throws {
        let sink = RuntimeStatusArtifactSinkSpy()
        let progressArtifactSink = RuntimeProgressArtifactSinkSpy()
        let reporter = makeReporter(
            statusArtifactSink: sink,
            progressArtifactSink: progressArtifactSink,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        try reporter.writeProgress(
            operation: .applyBundle,
            step: .activateGuestUpdate,
            stepStatus: .started,
            phase: .running,
            message: "step started",
            updatedAt: "2026-05-22T00:00:00Z"
        )

        XCTAssertNil(sink.saved)
        let progress = try XCTUnwrap(progressArtifactSink.saved)
        XCTAssertEqual(progress.operation, .applyBundle)
        XCTAssertEqual(progress.step, .activateGuestUpdate)
        XCTAssertEqual(progress.stepStatus, .started)
        XCTAssertEqual(progress.phase, .running)
    }

    func testWriteProgressDoesNotReadOrCopyStatusDocument() throws {
        let sink = RuntimeStatusArtifactSinkSpy()
        let progressArtifactSink = RuntimeProgressArtifactSinkSpy()
        let reporter = makeReporter(
            statusArtifactSink: sink,
            progressArtifactSink: progressArtifactSink,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        try reporter.writeProgress(
            operation: .applyBundle,
            step: .activateGuestUpdate,
            stepStatus: .started,
            phase: .running,
            message: "step started",
            updatedAt: "2026-05-22T00:00:00Z"
        )

        XCTAssertEqual(progressArtifactSink.saved?.operation, .applyBundle)
        XCTAssertNil(sink.saved)
    }

    func testWriteProgressReportsProgressDocumentWriteFailure() {
        let progressArtifactSink = RuntimeProgressArtifactSinkSpy()
        progressArtifactSink.saveError = RuntimeArtifactSinkError.missingRequiredRoot(path: "/missing")
        let reporter = makeReporter(
            statusArtifactSink: RuntimeStatusArtifactSinkSpy(),
            progressArtifactSink: progressArtifactSink,
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm")
        )

        XCTAssertThrowsError(try reporter.writeProgress(
            operation: .applyBundle,
            step: .activateGuestUpdate,
            stepStatus: .started,
            phase: .running,
            message: "step started",
            updatedAt: "2026-05-22T00:00:00Z"
        )) { error in
            XCTAssertEqual(
                error as? RuntimeArtifactSinkError,
                .missingRequiredRoot(path: "/missing")
            )
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
        statusArtifactSink: RuntimeStatusArtifactSink,
        progressArtifactSink: RuntimeProgressArtifactSink = RuntimeProgressArtifactSinkSpy(),
        productRoot: URL,
        runtimeHome: URL,
        makeStatusDocument: @escaping (RuntimeStatusDocumentBuildInput) -> RuntimeStatusDocument =
            BuildRuntimeStatusDocumentUseCase().build,
        makeProgressDocument: @escaping (RuntimeStatusProgressUpdateInput) -> RuntimeProgressDocument =
            BuildRuntimeStatusDocumentUseCase().progressDocument
    ) -> RuntimeStatusReporter {
        RuntimeStatusReporter(
            statusArtifactSink: statusArtifactSink,
            progressArtifactSink: progressArtifactSink,
            productIdentifier: productIdentifier,
            productRoot: productRoot,
            runtimeHome: runtimeHome,
            makeStatusDocument: makeStatusDocument,
            makeProgressDocument: makeProgressDocument
        )
    }
}

private final class RuntimeStatusArtifactSinkSpy: RuntimeStatusArtifactSink {
    var saved: RuntimeStatusDocument?

    func save(_ document: RuntimeStatusDocument) throws {
        saved = document
    }
}

private final class RuntimeProgressArtifactSinkSpy: RuntimeProgressArtifactSink {
    var saved: RuntimeProgressDocument?
    var saveError: Error?

    func save(_ document: RuntimeProgressDocument) throws {
        if let saveError {
            throw saveError
        }
        saved = document
    }
}
