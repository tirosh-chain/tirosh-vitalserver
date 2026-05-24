import Foundation
import Contracts
import XCTest

final class ContractsTests: XCTestCase {
    func testDecodesRuntimeStatusV1() throws {
        let document = try decodeFixture(RuntimeStatusDocument.self, named: "runtime-status-v1-healthy")

        XCTAssertNil(document.schemaVersion)
        XCTAssertEqual(document.status, .healthy)
        XCTAssertEqual(document.operation, .health)
        XCTAssertEqual(document.proxyPort, 80)
        XCTAssertEqual(document.failureReasons, [])
        XCTAssertNil(document.progress)
    }

    func testDecodesRuntimeStatusV2Progress() throws {
        let document = try decodeFixture(RuntimeStatusDocument.self, named: "runtime-status-v2-updating")

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.status, .updating)
        XCTAssertEqual(document.progress?.operation, .applyBundle)
        XCTAssertEqual(document.progress?.step, .activateGuestUpdate)
        XCTAssertEqual(document.progress?.stepStatus, .started)
        XCTAssertEqual(document.progress?.reasonCodes, ["guest-activation-pending"])
    }

    func testRuntimeServiceOperationsRoundTrip() throws {
        XCTAssertEqual(RuntimeOperation(rawValue: "start-services"), .startServices)
        XCTAssertEqual(RuntimeOperation.startServices.rawValue, "start-services")
        XCTAssertEqual(RuntimeOperation(rawValue: "stop-services"), .stopServices)
        XCTAssertEqual(RuntimeOperation.stopServices.rawValue, "stop-services")
    }

    func testDecodesGuestRuntimeState() throws {
        let document = try decodeFixture(GuestRuntimeStateDocument.self, named: "runtime-state-ready")

        XCTAssertEqual(document.vmIP, "192.168.64.2")
        XCTAssertEqual(document.bootID, "7b6a6afd-64f8-4dd5-91f1-6dcbf58f8f7d")
        XCTAssertEqual(document.memory?.percent, 25.0)
        XCTAssertEqual(document.systemDisk?.percent, 31.25)
    }

    func testDecodesGuestRuntimeStateContainerServices() throws {
        let json = """
        {
          "schemaVersion": 1,
          "vmIP": "192.168.64.2",
          "guestHTTP": "200",
          "redisUIHTTP": "200",
          "swaggerUIHTTP": "200",
          "updatedAt": "2026-05-24T00:00:00Z",
          "containerServices": [
            {
              "service": "audit-proxy",
              "name": "vitalserver-audit-proxy-1",
              "state": "running",
              "health": "healthy",
              "exitCode": 0
            }
          ]
        }
        """
        let document = try JSONDecoder().decode(GuestRuntimeStateDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.containerServices, [
            RuntimeContainerServiceObservation(
                service: "audit-proxy",
                name: "vitalserver-audit-proxy-1",
                state: "running",
                health: "healthy",
                exitCode: 0
            ),
        ])
    }

    func testDecodesActivationResultV1() throws {
        let document = try decodeFixture(
            GuestUpdateActivationResultDocument.self,
            named: "activate-update-result-v1-completed"
        )

        XCTAssertNil(document.schemaVersion)
        XCTAssertTrue(document.completed)
        XCTAssertFalse(document.failed)
        XCTAssertEqual(document.status, .completed)
    }

    func testDecodesActivationResultV2() throws {
        let document = try decodeFixture(
            GuestUpdateActivationResultDocument.self,
            named: "activate-update-result-v2-running"
        )

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.requestId, "4A3D7063-5E81-4BA1-9E74-74E44347F6E5")
        XCTAssertEqual(document.operation, .activateGuestUpdate)
        XCTAssertEqual(document.step, "load-docker-images")
        XCTAssertFalse(document.completed)
        XCTAssertFalse(document.failed)
    }

    func testDecodesDatastoreRepairResultV2() throws {
        let json = """
        {
          "schemaVersion": 2,
          "requestId": "repair-1",
          "operation": "repair-datastore",
          "status": "running",
          "message": "Datastore repair is running.",
          "updatedAt": "2026-05-21T12:33:57Z"
        }
        """
        let document = try JSONDecoder().decode(DatastoreRepairResultDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.requestId, "repair-1")
        XCTAssertEqual(document.operation, .repairDatastore)
        XCTAssertEqual(document.status, .running)
        XCTAssertFalse(document.completed)
        XCTAssertFalse(document.failed)
    }

    func testUnknownEnumValuesRoundTrip() throws {
        let json = """
        {
          "schemaVersion": 2,
          "product": "TiroshVitalServer",
          "status": "paused",
          "operation": "future-operation",
          "message": "future state",
          "updatedAt": "2026-05-21T12:33:57Z",
          "productRoot": "/Library/Application Support/TiroshVitalServer",
          "runtimeHome": "/Library/Application Support/TiroshVitalServer/vm",
          "runtimeVersion": "0.1.4",
          "vmService": "loaded",
          "proxyService": "loaded",
          "watchdogService": "loaded",
          "vmIP": null,
          "proxyPort": 80,
          "hostProxyHTTP": "failed",
          "guestHTTP": "failed",
          "redisUIHTTP": null,
          "swaggerUIHTTP": null,
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": [],
          "latestBackup": null,
          "progress": {
            "operation": "future-operation",
            "phase": "future-phase",
            "step": "future-step",
            "stepStatus": "future-step-status",
            "message": "future progress",
            "reasonCodes": [],
            "startedAt": null,
            "updatedAt": "2026-05-21T12:33:57Z"
          }
        }
        """
        let document = try JSONDecoder().decode(RuntimeStatusDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.status.rawValue, "paused")
        XCTAssertEqual(document.operation.rawValue, "future-operation")
        XCTAssertEqual(document.vmService, .loaded)
        XCTAssertEqual(document.rootfsBase, .present)
        XCTAssertEqual(document.progress?.phase.rawValue, "future-phase")
        XCTAssertEqual(document.progress?.stepStatus?.rawValue, "future-step-status")

        let encoded = try JSONEncoder().encode(document)
        let roundTripped = try JSONDecoder().decode(RuntimeStatusDocument.self, from: encoded)
        XCTAssertEqual(roundTripped.status.rawValue, "paused")
        XCTAssertEqual(roundTripped.vmService.rawValue, "loaded")
        XCTAssertEqual(roundTripped.rootfsBase.rawValue, "present")
        XCTAssertEqual(roundTripped.progress?.phase.rawValue, "future-phase")
    }

    func testRuntimeFailureReasonsDecodeAsTypedCodes() throws {
        let json = """
        [
          "missing-vm-bin",
          "vm-service-not loaded",
          "host-proxy-http-502",
          "audit-proxy-http-failed",
          "proxy-port-80-in-use-by-nginx-1234",
          "guest-bootstrap-missing-runtime-packages",
          "future-reason"
        ]
        """
        let reasons = try JSONDecoder().decode([RuntimeFailureReason].self, from: Data(json.utf8))

        XCTAssertEqual(reasons[0], .missingVMBin)
        XCTAssertEqual(reasons[1], .vmService("not loaded"))
        XCTAssertEqual(reasons[2], .hostProxyHTTP("502"))
        XCTAssertEqual(reasons[3], .auditProxyHTTP("failed"))
        XCTAssertEqual(reasons[4], .proxyPortInUse(port: 80, listeners: "nginx-1234"))
        XCTAssertEqual(reasons[5], .guestBootstrapMissingRuntimePackages)
        XCTAssertEqual(reasons[6], .unknown("future-reason"))

        let encoded = try JSONEncoder().encode(reasons)
        let roundTripped = try JSONDecoder().decode([RuntimeFailureReason].self, from: encoded)
        XCTAssertEqual(roundTripped.map(\.rawValue), [
            "missing-vm-bin",
            "vm-service-not loaded",
            "host-proxy-http-502",
            "audit-proxy-http-failed",
            "proxy-port-80-in-use-by-nginx-1234",
            "guest-bootstrap-missing-runtime-packages",
            "future-reason",
        ])
    }

    func testRuntimeEventTypeDefinesOperationalTaxonomyAndPreservesUnknownValues() throws {
        let knownTypes: [RuntimeEventType] = [
            .statusChanged,
            .progressUpdated,
            .healthObserved,
            .recoveryTriggered,
            .recoveryCompleted,
            .containerObserved,
            .auditProxyObserved,
            .runtimeCommandStarted,
            .runtimeCommandCompleted,
            .runtimeCommandFailed,
        ]

        XCTAssertEqual(knownTypes.map(\.rawValue), [
            "status-changed",
            "progress-updated",
            "health-observed",
            "recovery-triggered",
            "recovery-completed",
            "container-observed",
            "audit-proxy-observed",
            "runtime-command-started",
            "runtime-command-completed",
            "runtime-command-failed",
        ])

        let encoded = try JSONEncoder().encode(RuntimeEventType.unknown("vendor-event"))
        let decoded = try JSONDecoder().decode(RuntimeEventType.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("vendor-event"))
    }

    private func decodeFixture<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
