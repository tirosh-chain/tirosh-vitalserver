import Application
import Contracts
import XCTest
import Errors

final class RuntimeOperationReportingUseCaseTests: XCTestCase {
    func testBuildStatusDocumentUseCaseMapsExplicitSnapshotToStatusDocument() {
        let document = BuildRuntimeStatusDocumentUseCase().build(RuntimeStatusDocumentBuildInput(
            product: "VitalServerHelper",
            status: .updating,
            productRoot: "/product",
            runtimeHome: "/product/vm",
            runtimeVersion: "0.1.4",
            healthSnapshot: healthSnapshot(),
            latestBackup: "/product/backups/latest"
        ))

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.product, "VitalServerHelper")
        XCTAssertEqual(document.status, .updating)
        XCTAssertEqual(document.runtimeVersion, "0.1.4")
        XCTAssertEqual(document.vmIP, "192.168.64.2")
        XCTAssertEqual(document.latestBackup, "/product/backups/latest")
    }

    func testOperationReportingMessagesComeFromUseCase() {
        let useCase = RuntimeOperationReportingUseCase()
        let event = RuntimeStepExecutionEvent(
            operation: .applyBundle,
            status: .updating,
            step: .stopRuntimeServices,
            stepStatus: .started,
            phase: .running,
            message: "step started"
        )

        XCTAssertEqual(
            useCase.progressLogMessage(event: event),
            "step=stop-runtime-services status=started"
        )
        XCTAssertEqual(
            useCase.statusWriteFailedLogMessage(status: .critical, operation: .applyBundle, reason: "denied"),
            "failed to write runtime status status=critical operation=apply-bundle error=denied"
        )
        XCTAssertEqual(
            useCase.progressWriteFailedLogMessage(event: event, reason: "denied"),
            "failed to write runtime progress step=stop-runtime-services stepStatus=started error=denied"
        )
        XCTAssertEqual(
            useCase.observedEventRecordFailedLogMessage(status: .degraded, operation: .watchdog, reason: "denied"),
            "failed to record runtime observed event status=degraded operation=watchdog error=denied"
        )
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
            vitalDBObservation: VitalDBObservationDocument(
                observedAt: "2026-05-30T00:00:00Z",
                ready: true,
                recorderOnlineThresholdSeconds: 30
            ),
            failureReasons: []
        )
    }
}
