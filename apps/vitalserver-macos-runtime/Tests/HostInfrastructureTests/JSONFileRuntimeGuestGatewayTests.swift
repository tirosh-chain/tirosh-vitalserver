import Core
import Contracts
import HostInfrastructure
import XCTest

final class JSONFileRuntimeGuestGatewayTests: XCTestCase {
    func testWritesUpdateActivationRequestAndLoadsResult() throws {
        let harness = try GuestGatewayHarness()

        try harness.gateway.writeUpdateActivationRequest(RuntimeGuestActivationRequest(
            id: "request-1",
            requestedAt: "2026-05-21T12:33:57Z",
            version: "0.1.4"
        ))
        try harness.writeJSON(
            """
            {
              "schemaVersion": 2,
              "requestId": "request-1",
              "operation": "activate-update",
              "status": "completed",
              "message": "done",
              "updatedAt": "2026-05-21T12:34:57Z"
            }
            """,
            to: harness.updateActivationResultURL
        )

        let request = try harness.jsonObject(at: harness.updateActivationRequestURL)
        XCTAssertEqual(request["schemaVersion"] as? Int, 2)
        XCTAssertEqual(request["requestId"] as? String, "request-1")
        XCTAssertEqual(request["operation"] as? String, "activate-update")
        XCTAssertEqual(request["version"] as? String, "0.1.4")

        let result = try XCTUnwrap(harness.gateway.loadUpdateActivationResult())
        XCTAssertEqual(result.schemaVersion, 2)
        XCTAssertEqual(result.requestId, "request-1")
        XCTAssertEqual(result.operation, .activateGuestUpdate)
        XCTAssertEqual(result.status, .completed)

        try harness.cleanup()
    }

    func testWritesDatastoreRepairRequestAndLoadsResult() throws {
        let harness = try GuestGatewayHarness()

        try harness.gateway.writeDatastoreRepairRequest(RuntimeDatastoreRepairRequest(
            id: "repair-1",
            requestedAt: "2026-05-21T12:33:57Z"
        ))
        try harness.writeJSON(
            """
            {
              "schemaVersion": 2,
              "requestId": "repair-1",
              "operation": "repair-datastore",
              "status": "running",
              "message": "Datastore repair is running.",
              "updatedAt": "2026-05-21T12:34:57Z"
            }
            """,
            to: harness.datastoreRepairResultURL
        )

        let request = try harness.jsonObject(at: harness.datastoreRepairRequestURL)
        XCTAssertEqual(request["schemaVersion"] as? Int, 2)
        XCTAssertEqual(request["requestId"] as? String, "repair-1")
        XCTAssertEqual(request["operation"] as? String, "repair-datastore")

        let result = try XCTUnwrap(harness.gateway.loadDatastoreRepairResult())
        XCTAssertEqual(result.schemaVersion, 2)
        XCTAssertEqual(result.requestId, "repair-1")
        XCTAssertEqual(result.operation, .repairDatastore)
        XCTAssertEqual(result.status, .running)

        try harness.cleanup()
    }

    func testLoadsRuntimeStateAndRemovesStaleResults() throws {
        let harness = try GuestGatewayHarness()
        try harness.writeJSON(
            """
            {
              "vmIP": "192.168.64.2",
              "bootID": "boot-1",
              "guestHTTP": "200",
              "redisUIHTTP": "200",
              "swaggerUIHTTP": "200",
              "updatedAt": "2026-05-21T12:34:57Z"
            }
            """,
            to: harness.runtimeStateURL
        )
        try harness.writeJSON("{}", to: harness.updateActivationResultURL)
        try harness.writeJSON("{}", to: harness.datastoreRepairResultURL)
        try harness.writeJSON(
            """
            {
              "schemaVersion": 2,
              "operation": "bootstrap",
              "status": "failed",
              "message": "Missing runtime packages.",
              "reasonCodes": ["guest-bootstrap-missing-runtime-packages"],
              "updatedAt": "2026-05-21T12:34:57Z"
            }
            """,
            to: harness.bootstrapResultURL
        )

        let state = try XCTUnwrap(harness.gateway.loadRuntimeState())
        XCTAssertEqual(state.vmIP, "192.168.64.2")
        XCTAssertEqual(state.guestHTTP, "200")
        let bootstrapResult = try XCTUnwrap(harness.gateway.loadBootstrapResult())
        XCTAssertEqual(bootstrapResult.status, .failed)
        XCTAssertEqual(bootstrapResult.operation?.rawValue, "bootstrap")
        XCTAssertEqual(bootstrapResult.reasonCodes, [.guestBootstrapMissingRuntimePackages])

        try harness.gateway.removeUpdateActivationResult()
        try harness.gateway.removeDatastoreRepairResult()
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.updateActivationResultURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.datastoreRepairResultURL.path))

        try harness.cleanup()
    }
}

private struct GuestGatewayHarness {
    let directory: URL
    let runtimeStateURL: URL
    let bootstrapResultURL: URL
    let updateActivationRequestURL: URL
    let updateActivationResultURL: URL
    let datastoreRepairRequestURL: URL
    let datastoreRepairResultURL: URL
    let gateway: JSONFileRuntimeGuestGateway

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        runtimeStateURL = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        bootstrapResultURL = directory.appendingPathComponent(RuntimeFileNames.bootstrapResult)
        updateActivationRequestURL = directory.appendingPathComponent(RuntimeFileNames.updateActivationRequest)
        updateActivationResultURL = directory.appendingPathComponent(RuntimeFileNames.updateActivationResult)
        datastoreRepairRequestURL = directory.appendingPathComponent(RuntimeFileNames.datastoreRepairRequest)
        datastoreRepairResultURL = directory.appendingPathComponent(RuntimeFileNames.datastoreRepairResult)
        gateway = JSONFileRuntimeGuestGateway(
            runtimeStateURL: runtimeStateURL,
            bootstrapResultURL: bootstrapResultURL,
            updateActivationRequestURL: updateActivationRequestURL,
            updateActivationResultURL: updateActivationResultURL,
            datastoreRepairRequestURL: datastoreRepairRequestURL,
            datastoreRepairResultURL: datastoreRepairResultURL
        )
    }

    func writeJSON(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    func jsonObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func cleanup() throws {
        try FileManager.default.removeItem(at: directory)
    }
}
