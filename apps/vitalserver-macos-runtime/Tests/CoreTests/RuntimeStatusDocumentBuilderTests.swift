import Core
import Contracts
import XCTest

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
            product: "TiroshVitalServer",
            status: .updating,
            operation: .applyBundle,
            message: "bundle apply started",
            updatedAt: "2026-05-21T12:33:57Z",
            productRoot: "/Library/Application Support/TiroshVitalServer",
            runtimeHome: "/Library/Application Support/TiroshVitalServer/vm",
            runtimeVersion: "0.1.4",
            healthSnapshot: snapshot(failureReasons: [.guestHTTP("failed")]),
            latestBackup: "/Library/Application Support/TiroshVitalServer/backups/backup",
            progress: progress
        ))

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.product, "TiroshVitalServer")
        XCTAssertEqual(document.status, .updating)
        XCTAssertEqual(document.operation, .applyBundle)
        XCTAssertEqual(document.runtimeVersion, "0.1.4")
        XCTAssertEqual(document.vmService, .loaded)
        XCTAssertEqual(document.proxyService, .loaded)
        XCTAssertEqual(document.watchdogService, .loaded)
        XCTAssertEqual(document.vmIP, "192.168.64.2")
        XCTAssertEqual(document.proxyPort, 80)
        XCTAssertEqual(document.hostProxyHTTP, "200")
        XCTAssertEqual(document.guestHTTP, "failed")
        XCTAssertEqual(document.failureReasons, [.guestHTTP("failed")])
        XCTAssertEqual(document.latestBackup, "/Library/Application Support/TiroshVitalServer/backups/backup")
        XCTAssertEqual(document.progress, progress)
    }

    func testBuildsWithoutProgressOrLatestBackup() {
        let document = RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: "TiroshVitalServer",
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
        XCTAssertEqual(document.failureReasons, [])
        XCTAssertNil(document.latestBackup)
        XCTAssertNil(document.progress)
    }

    private func snapshot(failureReasons: [RuntimeFailureReason]) -> RuntimeHealthSnapshot {
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
            guestHTTP: failureReasons.isEmpty ? "200" : "failed",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            failureReasons: failureReasons
        )
    }
}
