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
              "shutdownPhase": "poweroff-ready",
              "message": "ready",
              "redisBackupPath": "/mnt/tirosh/backups/redis/redis.tar.gz",
              "details": {
                "stopAction": "ordered-compose-stop",
                "failedService": "app",
                "remainingServices": ["app", "redis"],
                "failureSnapshotPath": "/mnt/tirosh/run/guest-observability/shutdown-failure.latest.json",
                "serviceStates": [
                  {
                    "service": "app",
                    "container": "vitalserver-app-1",
                    "state": "running",
                    "health": "healthy"
                  }
                ]
              },
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
        XCTAssertEqual(result.shutdownPhase, .poweroffReady)
        XCTAssertEqual(result.redisBackupPath, "/mnt/tirosh/backups/redis/redis.tar.gz")
        XCTAssertEqual(result.details?.stopAction, "ordered-compose-stop")
        XCTAssertEqual(result.details?.failedService, "app")
        XCTAssertEqual(result.details?.remainingServices, ["app", "redis"])
        XCTAssertEqual(
            result.details?.failureSnapshotPath,
            "/mnt/tirosh/run/guest-observability/shutdown-failure.latest.json"
        )
        XCTAssertEqual(result.details?.serviceStates?.first?.service, "app")

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

    func testLoadsServiceStackStatusDocument() throws {
        let harness = try GuestGatewayHarness()
        try harness.writeJSON(
            """
            {
              "schemaVersion": 1,
              "owner": "service-stack",
              "updatedAt": "2026-07-01T00:00:00Z",
              "bootID": "boot-1",
              "capabilities": {
                "activateUpdate": true,
                "prepareUpdateShutdown": true,
                "redisBackup": true,
                "redisRestore": true,
                "repairDatastore": true,
                "reconcileCompose": true
              },
              "composeServices": [
                {
                  "service": "app",
                  "containerID": "container-1",
                  "state": "running",
                  "health": "healthy",
                  "memoryUsedBytes": 100,
                  "memoryLimitBytes": 200
                }
              ],
              "httpProbes": {
                "edge": {
                  "status": "200",
                  "failed": false,
                  "message": "",
                  "exitCode": null
                },
                "redisUI": null,
                "swaggerUI": null
              },
              "vitalDBObservation": null,
              "readIssues": [
                {
                  "source": "vitalDBObservation",
                  "message": "timeout"
                }
              ]
            }
            """,
            to: harness.serviceStackStatusURL
        )

        guard case .loaded(let document) = harness.gateway.loadServiceStackStatusDocument() else {
            return XCTFail("Expected loaded service stack status")
        }

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.owner, "service-stack")
        XCTAssertEqual(document.updatedAt, "2026-07-01T00:00:00Z")
        XCTAssertEqual(document.bootID, "boot-1")
        XCTAssertEqual(document.composeServices?.first?.service, "app")
        XCTAssertEqual(document.composeServices?.first?.health, "healthy")
        XCTAssertEqual(document.httpProbes?.edge?.status, "200")
        XCTAssertNil(document.vitalDBObservation)
        XCTAssertEqual(document.readIssues?.first?.source, "vitalDBObservation")

        try harness.cleanup()
    }

    func testClearUpdateShutdownPreparationRemovesRequestAndResult() throws {
        let harness = try GuestGatewayHarness()
        try harness.gateway.writeUpdateShutdownRequest(RuntimeGuestShutdownRequest(
            id: "shutdown-1",
            requestedAt: "2026-05-21T12:33:57Z",
            version: "0.1.4"
        ))
        try harness.writeJSON("{}", to: harness.updateShutdownResultURL)

        try harness.gateway.clearUpdateShutdownPreparation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.updateShutdownRequestURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.updateShutdownResultURL.path))

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

    func testLoadResultReportsDirectoryAtGuestDocumentPath() throws {
        let harness = try GuestGatewayHarness()
        try FileManager.default.createDirectory(
            at: harness.updateActivationResultURL,
            withIntermediateDirectories: true
        )
        defer {
            try? harness.cleanup()
        }

        guard case .failed(let message) = harness.gateway.loadUpdateActivationResultDocument() else {
            return XCTFail("Expected failed update activation result load")
        }
        XCTAssertTrue(message.contains("path state is unexpected"))
        XCTAssertTrue(message.contains("state=directory"))
    }

    func testRemoveResultFailsWhenGuestDocumentPathIsDirectory() throws {
        let harness = try GuestGatewayHarness()
        try FileManager.default.createDirectory(
            at: harness.updateActivationResultURL,
            withIntermediateDirectories: true
        )
        defer {
            try? harness.cleanup()
        }

        XCTAssertThrowsError(try harness.gateway.removeUpdateActivationResult()) { error in
            XCTAssertEqual(
                error as? JSONFileRuntimeGuestGatewayError,
                .unexpectedPathState(path: harness.updateActivationResultURL.path, state: "directory")
            )
        }
    }

    func testLoadResultReportsInjectedPathInspectionFailure() {
        let urls = GuestGatewayURLs(root: URL(fileURLWithPath: "/guest"))
        let fileStore = GuestGatewayFileStore()
        fileStore.pathStates[urls.updateActivationResult.path] = .inspectFailed("permission denied")
        let gateway = urls.gateway(fileStore: fileStore)

        guard case .failed(let message) = gateway.loadUpdateActivationResultDocument() else {
            return XCTFail("Expected failed update activation result load")
        }
        XCTAssertEqual(
            message,
            "runtime guest document path inspection failed path=\(urls.updateActivationResult.path) reason=permission denied"
        )
    }

    func testWritesAndRemovesGuestDocumentsThroughInjectedFileStore() throws {
        let urls = GuestGatewayURLs(root: URL(fileURLWithPath: "/guest"))
        let fileStore = GuestGatewayFileStore()
        let gateway = urls.gateway(fileStore: fileStore)

        try gateway.writeUpdateActivationRequest(RuntimeGuestActivationRequest(
            id: "request-1",
            requestedAt: "2026-05-21T12:33:57Z",
            version: "0.1.4"
        ))

        XCTAssertEqual(fileStore.createdDirectories.map(\.path), [urls.root.path])
        XCTAssertNotNil(fileStore.files[urls.updateActivationRequest])

        fileStore.files[urls.updateActivationResult] = Data("{}".utf8)
        fileStore.pathStates[urls.updateActivationResult.path] = .file

        try gateway.removeUpdateActivationResult()

        XCTAssertEqual(fileStore.removed, [urls.updateActivationResult])
        XCTAssertNil(fileStore.files[urls.updateActivationResult])
    }
}

private struct GuestGatewayURLs {
    let root: URL

    var runtimeState: URL { root.appendingPathComponent(RuntimeFileNames.runtimeState) }
    var serviceStackStatus: URL { root.appendingPathComponent(RuntimeFileNames.serviceStackStatus) }
    var bootstrapResult: URL { root.appendingPathComponent(RuntimeFileNames.bootstrapResult) }
    var updateActivationRequest: URL { root.appendingPathComponent(RuntimeFileNames.updateActivationRequest) }
    var updateActivationResult: URL { root.appendingPathComponent(RuntimeFileNames.updateActivationResult) }
    var updateShutdownRequest: URL { root.appendingPathComponent(RuntimeFileNames.updateShutdownRequest) }
    var updateShutdownResult: URL { root.appendingPathComponent(RuntimeFileNames.updateShutdownResult) }
    var datastoreRepairRequest: URL { root.appendingPathComponent(RuntimeFileNames.datastoreRepairRequest) }
    var datastoreRepairResult: URL { root.appendingPathComponent(RuntimeFileNames.datastoreRepairResult) }
    var guestComposeReconcileRequest: URL { root.appendingPathComponent(RuntimeFileNames.guestComposeReconcileRequest) }
    var guestComposeReconcileResult: URL { root.appendingPathComponent(RuntimeFileNames.guestComposeReconcileResult) }
    var redisRestoreRequest: URL { root.appendingPathComponent(RuntimeFileNames.redisRestoreRequest) }
    var redisRestoreResult: URL { root.appendingPathComponent(RuntimeFileNames.redisRestoreResult) }

    func gateway(fileStore: RuntimeFileReading & RuntimeFileWriting) -> JSONFileRuntimeGuestGateway {
        JSONFileRuntimeGuestGateway(
            runtimeStateURL: runtimeState,
            serviceStackStatusURL: serviceStackStatus,
            bootstrapResultURL: bootstrapResult,
            updateActivationRequestURL: updateActivationRequest,
            updateActivationResultURL: updateActivationResult,
            updateShutdownRequestURL: updateShutdownRequest,
            updateShutdownResultURL: updateShutdownResult,
            datastoreRepairRequestURL: datastoreRepairRequest,
            datastoreRepairResultURL: datastoreRepairResult,
            guestComposeReconcileRequestURL: guestComposeReconcileRequest,
            guestComposeReconcileResultURL: guestComposeReconcileResult,
            redisRestoreRequestURL: redisRestoreRequest,
            redisRestoreResultURL: redisRestoreResult,
            fileStore: fileStore
        )
    }
}

private final class GuestGatewayFileStore: RuntimeFileReading, RuntimeFileWriting {
    var files: [URL: Data] = [:]
    var pathStates: [String: RuntimePathState] = [:]
    var createdDirectories: [URL] = []
    var removed: [URL] = []

    func fileExists(_ url: URL) -> Bool {
        files[url] != nil
    }

    func directoryExists(_ url: URL) -> Bool {
        createdDirectories.contains(url)
    }

    func isExecutableFile(atPath path: String) -> Bool {
        false
    }

    func pathState(at url: URL) -> RuntimePathState {
        if let state = pathStates[url.path] {
            return state
        }
        if files[url] != nil {
            return .file
        }
        return .missing
    }

    func readData(_ url: URL) throws -> Data {
        guard let data = files[url] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    func readUTF8Text(_ url: URL) throws -> String {
        String(decoding: try readData(url), as: UTF8.self)
    }

    func fileSize(_ url: URL) throws -> UInt64 {
        UInt64(try readData(url).count)
    }

    func modificationDate(_ url: URL) throws -> Date {
        Date(timeIntervalSince1970: 0)
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        files[url] = data
        pathStates[url.path] = .file
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {
        try writeData(data, to: url, options: options)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        createdDirectories.append(url)
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url)
        pathStates[url.path] = .missing
        removed.append(url)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
        files.removeValue(forKey: source)
    }
}

private struct GuestGatewayHarness {
    let directory: URL
    let runtimeStateURL: URL
    let serviceStackStatusURL: URL
    let bootstrapResultURL: URL
    let updateActivationRequestURL: URL
    let updateActivationResultURL: URL
    let updateShutdownRequestURL: URL
    let updateShutdownResultURL: URL
    let datastoreRepairRequestURL: URL
    let datastoreRepairResultURL: URL
    let guestComposeReconcileRequestURL: URL
    let guestComposeReconcileResultURL: URL
    let gateway: JSONFileRuntimeGuestGateway

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        runtimeStateURL = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        serviceStackStatusURL = directory.appendingPathComponent(RuntimeFileNames.serviceStackStatus)
        bootstrapResultURL = directory.appendingPathComponent(RuntimeFileNames.bootstrapResult)
        updateActivationRequestURL = directory.appendingPathComponent(RuntimeFileNames.updateActivationRequest)
        updateActivationResultURL = directory.appendingPathComponent(RuntimeFileNames.updateActivationResult)
        updateShutdownRequestURL = directory.appendingPathComponent(RuntimeFileNames.updateShutdownRequest)
        updateShutdownResultURL = directory.appendingPathComponent(RuntimeFileNames.updateShutdownResult)
        datastoreRepairRequestURL = directory.appendingPathComponent(RuntimeFileNames.datastoreRepairRequest)
        datastoreRepairResultURL = directory.appendingPathComponent(RuntimeFileNames.datastoreRepairResult)
        guestComposeReconcileRequestURL = directory.appendingPathComponent(RuntimeFileNames.guestComposeReconcileRequest)
        guestComposeReconcileResultURL = directory.appendingPathComponent(RuntimeFileNames.guestComposeReconcileResult)
        gateway = JSONFileRuntimeGuestGateway(
            runtimeStateURL: runtimeStateURL,
            serviceStackStatusURL: serviceStackStatusURL,
            bootstrapResultURL: bootstrapResultURL,
            updateActivationRequestURL: updateActivationRequestURL,
            updateActivationResultURL: updateActivationResultURL,
            updateShutdownRequestURL: updateShutdownRequestURL,
            updateShutdownResultURL: updateShutdownResultURL,
            datastoreRepairRequestURL: datastoreRepairRequestURL,
            datastoreRepairResultURL: datastoreRepairResultURL,
            guestComposeReconcileRequestURL: guestComposeReconcileRequestURL,
            guestComposeReconcileResultURL: guestComposeReconcileResultURL,
            redisRestoreRequestURL: directory.appendingPathComponent(RuntimeFileNames.redisRestoreRequest),
            redisRestoreResultURL: directory.appendingPathComponent(RuntimeFileNames.redisRestoreResult)
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
