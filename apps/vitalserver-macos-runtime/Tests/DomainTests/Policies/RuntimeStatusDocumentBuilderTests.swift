import Application
import Contracts
import Domain
import XCTest
import Errors

final class RuntimeStatusDocumentBuilderTests: XCTestCase {
    func testBuildsRuntimeStatusV2FromHealthSnapshot() {
        let document = RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: "VitalServerHelper",
            status: .updating,
            productRoot: "/Library/Application Support/VitalServerHelper",
            runtimeHome: "/Library/Application Support/VitalServerHelper/vm",
            runtimeVersion: "0.1.4",
            healthSnapshot: snapshot(
                failureReasons: [.guestHTTP("failed")],
                vitalDBObservation: vitalDBObservation()
            ),
            latestBackup: "/Library/Application Support/VitalServerHelper/backups/backup"
        ))

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.product, "VitalServerHelper")
        XCTAssertEqual(document.status, .updating)
        XCTAssertEqual(document.runtimeVersion, "0.1.4")
        XCTAssertEqual(document.vmService, .loaded)
        XCTAssertEqual(document.proxyService, .loaded)
        XCTAssertEqual(document.watchdogService, .loaded)
        XCTAssertEqual(document.guestAddressRead, .loaded(address: "192.168.64.2", source: .runtimeControlAPI))
        XCTAssertEqual(document.vmIP, "192.168.64.2")
        XCTAssertEqual(document.proxyPort, 80)
        XCTAssertEqual(document.proxyPortReadState, .loaded(80))
        XCTAssertEqual(document.hostProxyHTTP, "200")
        XCTAssertEqual(document.guestHTTP, "failed")
        XCTAssertEqual(document.latestBackup, "/Library/Application Support/VitalServerHelper/backups/backup")
    }

    func testBuildsWithoutLatestBackup() {
        let document = RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: "VitalServerHelper",
            status: .healthy,
            productRoot: "/product",
            runtimeHome: "/product/vm",
            runtimeVersion: "unknown",
            healthSnapshot: snapshot(failureReasons: []),
            latestBackup: nil
        ))

        XCTAssertEqual(document.status, .healthy)
        XCTAssertNil(document.latestBackup)
    }

    func testBuildDoesNotStoreCurrentHealthOrActiveOperationState() throws {
        let document = RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: "VitalServerHelper",
            status: .initializing,
            productRoot: "/product",
            runtimeHome: "/product/vm",
            runtimeVersion: "0.1.0",
            healthSnapshot: snapshot(failureReasons: [
                .hostProxyHTTP("failed"),
                .recorderIngressHTTP("failed"),
                .guestServiceObservationMissing,
            ]),
            latestBackup: nil
        ))

        XCTAssertEqual(document.status, RuntimeStatusLevel.initializing)
        let encoded = try JSONEncoder().encode(document)
        let encodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(encodedObject["vmState"])
        XCTAssertNil(encodedObject["vmErrors"])
        XCTAssertNil(encodedObject["failureReasons"])
        XCTAssertNil(encodedObject["domainErrors"])
        XCTAssertNil(encodedObject["operation"])
        XCTAssertNil(encodedObject["message"])
        XCTAssertNil(encodedObject["updatedAt"])
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
            guestAddressRead: .loaded(address: "192.168.64.2", source: .runtimeControlAPI),
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
