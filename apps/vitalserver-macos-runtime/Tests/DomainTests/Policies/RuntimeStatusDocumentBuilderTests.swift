import Application
import Contracts
import Domain
import XCTest
import Errors

final class RuntimeStatusDocumentBuilderTests: XCTestCase {
    func testBuildsRuntimeStatusV2FromHealthSnapshotAndProgress() {
        let progress = RuntimeProgressDocument(
            operation: .applyBundle,
            phase: .running,
            step: .activateGuestUpdate,
            stepStatus: .started,
            message: "Waiting for VM update activation",
            reasonCodes: ["guest-activation-pending"],
            startedAt: nil,
            updatedAt: "2026-05-21T12:34:00Z"
        )

        let document = RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: "VitalServerHelper",
            status: .updating,
            operation: .applyBundle,
            message: "bundle apply started",
            updatedAt: "2026-05-21T12:33:57Z",
            productRoot: "/Library/Application Support/VitalServerHelper",
            runtimeHome: "/Library/Application Support/VitalServerHelper/vm",
            runtimeVersion: "0.1.4",
            healthSnapshot: snapshot(
                failureReasons: [.guestHTTP("failed")],
                vitalDBObservation: vitalDBObservation()
            ),
            latestBackup: "/Library/Application Support/VitalServerHelper/backups/backup",
            progress: progress
        ))

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.product, "VitalServerHelper")
        XCTAssertEqual(document.status, .updating)
        XCTAssertEqual(document.operation, .applyBundle)
        XCTAssertEqual(document.runtimeVersion, "0.1.4")
        XCTAssertEqual(document.vmService, .loaded)
        XCTAssertEqual(document.proxyService, .loaded)
        XCTAssertEqual(document.watchdogService, .loaded)
        XCTAssertEqual(document.vmState, .unreachable)
        XCTAssertEqual(document.vmErrors ?? [], [.guestHTTP("failed")])
        XCTAssertEqual(document.vmIP, "192.168.64.2")
        XCTAssertEqual(document.proxyPort, 80)
        XCTAssertEqual(document.proxyPortReadState, .loaded(80))
        XCTAssertEqual(document.hostProxyHTTP, "200")
        XCTAssertEqual(document.guestHTTP, "failed")
        XCTAssertEqual(document.failureReasons, [.guestHTTP("failed")])
        XCTAssertEqual(document.domainErrors, [RuntimeDomainError(.guestHTTP("failed"))])
        XCTAssertEqual(document.latestBackup, "/Library/Application Support/VitalServerHelper/backups/backup")
        XCTAssertEqual(document.progress, progress)
    }

    func testBuildsWithoutProgressOrLatestBackup() {
        let document = RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: "VitalServerHelper",
            status: .healthy,
            operation: .health,
            message: "runtime health check passed",
            updatedAt: "2026-05-21T12:33:57Z",
            productRoot: "/product",
            runtimeHome: "/product/vm",
            runtimeVersion: "unknown",
            healthSnapshot: snapshot(failureReasons: []),
            latestBackup: nil
        ))

        XCTAssertEqual(document.status, .healthy)
        XCTAssertEqual(document.operation, .health)
        XCTAssertEqual(document.vmState, .running)
        XCTAssertEqual(document.vmErrors ?? [], [])
        XCTAssertEqual(document.failureReasons, [])
        XCTAssertNil(document.domainErrors)
        XCTAssertNil(document.latestBackup)
        XCTAssertNil(document.progress)
    }

    func testBuildSuppressesTransientFailureReasonsDuringInstallInitialization() {
        let document = RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: "VitalServerHelper",
            status: .initializing,
            operation: .install,
            message: "runtime initialized; runtime services starting",
            updatedAt: "2026-06-10T05:33:48Z",
            productRoot: "/product",
            runtimeHome: "/product/vm",
            runtimeVersion: "0.1.0",
            healthSnapshot: snapshot(failureReasons: [
                .guestRuntimeStateMissing,
                .hostProxyHTTP("failed"),
                .recorderIngressHTTP("failed"),
                .guestServiceObservationMissing,
            ]),
            latestBackup: nil
        ))

        XCTAssertEqual(document.status, RuntimeStatusLevel.initializing)
        XCTAssertEqual(document.failureReasons, [RuntimeFailureReason]())
        XCTAssertNil(document.domainErrors)
    }

    private func snapshot(
        failureReasons: [RuntimeFailureReason],
        vitalDBObservation: VitalDBObservationDocument? = nil
    ) -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: .executable,
            proxyExecutable: .executable,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmState: failureReasons.isEmpty ? .running : .unreachable,
            vmErrors: failureReasons.isEmpty ? [] : [.guestHTTP("failed")],
            vmIP: "192.168.64.2",
            proxyPort: 80,
            proxyPortReadState: .loaded(80),
            hostProxyHTTP: "200",
            guestHTTP: failureReasons.isEmpty ? "200" : "failed",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            vitalDBObservation: vitalDBObservation,
            failureReasons: failureReasons
        )
    }

    private func vitalDBObservation() -> VitalDBObservationDocument {
        VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 30
        )
    }
}
