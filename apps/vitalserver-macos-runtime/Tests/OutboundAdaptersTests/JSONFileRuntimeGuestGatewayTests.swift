import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors

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

        guard case .loaded(let result) = harness.gateway.loadUpdateActivationResultDocument() else {
            return XCTFail("Expected loaded update activation result")
        }
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

        guard case .loaded(let result) = harness.gateway.loadDatastoreRepairResultDocument() else {
            return XCTFail("Expected loaded datastore repair result")
        }
        XCTAssertEqual(result.schemaVersion, 2)
        XCTAssertEqual(result.requestId, "repair-1")
        XCTAssertEqual(result.operation, .repairDatastore)
        XCTAssertEqual(result.status, .running)

        try harness.cleanup()
    }

    func testWritesUpdateShutdownRequestAndLoadsResult() throws {
        let harness = try GuestGatewayHarness()

        try harness.gateway.writeUpdateShutdownRequest(RuntimeGuestShutdownRequest(
            id: "shutdown-1",
            requestedAt: "2026-05-21T12:33:57Z",
            version: "0.1.4"
        ))
        try harness.writeJSON(
            """
            {
              "schemaVersion": 2,
              "requestId": "shutdown-1",
              "operation": "prepare-update-shutdown",
              "status": "ready",
              "shutdownPhase": "poweroff-requested",
              "message": "ready",
              "redisBackupPath": "/mnt/tirosh/backups/redis/redis.tar.gz",
              "updatedAt": "2026-05-21T12:34:57Z"
            }
            """,
            to: harness.updateShutdownResultURL
        )

        let request = try harness.jsonObject(at: harness.updateShutdownRequestURL)
        XCTAssertEqual(request["schemaVersion"] as? Int, 1)
        XCTAssertEqual(request["requestId"] as? String, "shutdown-1")
        XCTAssertEqual(request["operation"] as? String, "prepare-update-shutdown")
        XCTAssertEqual(request["version"] as? String, "0.1.4")

        guard case .loaded(let result) = harness.gateway.loadUpdateShutdownResultDocument() else {
            return XCTFail("Expected loaded update shutdown result")
        }
        XCTAssertEqual(result.schemaVersion, 2)
        XCTAssertEqual(result.requestId, "shutdown-1")
        XCTAssertEqual(result.operation, .prepareUpdateShutdown)
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.shutdownPhase, .poweroffRequested)
        XCTAssertEqual(result.redisBackupPath, "/mnt/tirosh/backups/redis/redis.tar.gz")

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
        try harness.writeJSON("{}", to: harness.updateShutdownResultURL)
        try harness.writeJSON("{}", to: harness.datastoreRepairResultURL)
        try harness.writeJSON(
            """
            {
              "schemaVersion": 2,
              "bootID": "boot-1",
              "operation": "bootstrap",
              "status": "failed",
              "message": "Missing runtime packages.",
              "reasonCodes": ["guest-bootstrap-missing-runtime-packages"],
              "updatedAt": "2026-05-21T12:34:57Z"
            }
            """,
            to: harness.bootstrapResultURL
        )

        guard case .loaded(let state) = harness.gateway.loadRuntimeStateDocument() else {
            return XCTFail("Expected loaded runtime state")
        }
        XCTAssertEqual(state.vmIP, "192.168.64.2")
        XCTAssertEqual(state.guestHTTP, "200")
        guard case .loaded(let bootstrapResult) = harness.gateway.loadBootstrapResultDocument() else {
            return XCTFail("Expected loaded bootstrap result")
        }
        XCTAssertEqual(bootstrapResult.status, .failed)
        XCTAssertEqual(bootstrapResult.bootID, "boot-1")
        XCTAssertEqual(bootstrapResult.operation?.rawValue, "bootstrap")
        XCTAssertEqual(bootstrapResult.reasonCodes, [.guestBootstrapMissingRuntimePackages])

        try harness.gateway.removeUpdateActivationResult()
        try harness.gateway.removeUpdateShutdownResult()
        try harness.gateway.removeDatastoreRepairResult()
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.updateActivationResultURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.updateShutdownResultURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.datastoreRepairResultURL.path))

        try harness.cleanup()
    }

    func testLoadResultReportsMissingAndInvalidGuestDocuments() throws {
        let harness = try GuestGatewayHarness()

        guard case .missing = harness.gateway.loadUpdateActivationResultDocument() else {
            return XCTFail("Expected missing update activation result")
        }

        try harness.writeJSON("not-json", to: harness.updateActivationResultURL)
        guard case .failed(let message) = harness.gateway.loadUpdateActivationResultDocument() else {
            return XCTFail("Expected failed update activation result load")
        }
        XCTAssertFalse(message.isEmpty)

        try harness.cleanup()
    }
}

private struct GuestGatewayHarness {
    let directory: URL
    let runtimeStateURL: URL
    let bootstrapResultURL: URL
    let updateActivationRequestURL: URL
    let updateActivationResultURL: URL
    let updateShutdownRequestURL: URL
    let updateShutdownResultURL: URL
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
        updateShutdownRequestURL = directory.appendingPathComponent(RuntimeFileNames.updateShutdownRequest)
        updateShutdownResultURL = directory.appendingPathComponent(RuntimeFileNames.updateShutdownResult)
        datastoreRepairRequestURL = directory.appendingPathComponent(RuntimeFileNames.datastoreRepairRequest)
        datastoreRepairResultURL = directory.appendingPathComponent(RuntimeFileNames.datastoreRepairResult)
        gateway = JSONFileRuntimeGuestGateway(
            runtimeStateURL: runtimeStateURL,
            bootstrapResultURL: bootstrapResultURL,
            updateActivationRequestURL: updateActivationRequestURL,
            updateActivationResultURL: updateActivationResultURL,
            updateShutdownRequestURL: updateShutdownRequestURL,
            updateShutdownResultURL: updateShutdownResultURL,
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
