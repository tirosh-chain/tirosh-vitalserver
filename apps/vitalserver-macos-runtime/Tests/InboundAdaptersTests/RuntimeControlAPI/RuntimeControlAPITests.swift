import Foundation
import Darwin
import Application
import Contracts
import RuntimeControl
import InboundAdapters
import XCTest
import Errors

final class RuntimeControlAPITests: XCTestCase {
    func testRoutesAreUniqueByMethodAndPath() {
        let routeKeys = RuntimeControlAPIEndpoint.allCases.map { endpoint in
            "\(endpoint.route.method.rawValue) \(endpoint.route.path)"
        }

        XCTAssertEqual(Set(routeKeys).count, routeKeys.count)
    }

    func testRuntimeControlRoutesDoNotUseHostPathPrefix() {
        let runtimeControlRoutes = RuntimeControlAPIEndpoint.allCases
            .map(\.route)
            .filter { $0.scope == .runtimeControl }

        XCTAssertFalse(runtimeControlRoutes.isEmpty)
        XCTAssertTrue(runtimeControlRoutes.allSatisfy {
            $0.path == "/platform"
                || $0.path.hasPrefix("/platform/")
                || $0.path.hasPrefix("/runtime/")
                || $0.path.hasPrefix("/runtime/vitaldb/")
                || $0.path.hasPrefix("/runtime/lab/")
        })
    }

    func testPlatformAffordanceRoutesAreExplicitlySeparated() {
        let hostRoutes = RuntimeControlAPIEndpoint.allCases
            .map(\.route)
            .filter { $0.scope == .platformAffordance }

        XCTAssertFalse(hostRoutes.isEmpty)
        XCTAssertTrue(hostRoutes.allSatisfy { $0.path.hasPrefix("/platform/") })
    }

    func testRuntimeSettingsJSONContractRequiresExplicitBridgedInterfaceNull() throws {
        let settingsData = try JSONEncoder().encode(RuntimeSettings(cpuCount: 4, memoryGiB: 6))
        let settingsText = try XCTUnwrap(String(data: settingsData, encoding: .utf8))

        XCTAssertTrue(settingsText.contains(#""bridgedInterface":null"#))

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: settingsData) as? [String: Any])
        object.removeValue(forKey: "bridgedInterface")
        let missingBridgedInterfaceData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try JSONDecoder().decode(RuntimeSettings.self, from: missingBridgedInterfaceData)
        )
    }

    func testFileReferenceCanRepresentLocalAndPWAUploadInputs() throws {
        let references = [
            RuntimeControlFileReference(kind: .localPath, value: "/tmp/update-bundle.tar.gz"),
            RuntimeControlFileReference(kind: .uploadedArtifact, value: "bundle-123"),
            RuntimeControlFileReference(kind: .remoteURL, value: "https://example.invalid/update-bundle.tar.gz"),
        ]

        let encoded = try JSONEncoder().encode(references)
        let decoded = try JSONDecoder().decode([RuntimeControlFileReference].self, from: encoded)

        XCTAssertEqual(decoded, references)
    }

    func testCommandResponseRoundTripsTypedResult() throws {
        let response = RuntimeControlCommandResponse(
            result: RuntimeCommandResult(exitCode: 0, stdout: "ok", stderr: "")
        )

        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(RuntimeControlCommandResponse.self, from: encoded)

        XCTAssertEqual(decoded, response)
    }

    func testPlatformWorkflowJSONRequiresExplicitArtifactOwner() throws {
        let operation = PlatformWorkflowOperation(
            operationId: "workflow-0123456789abcdef0123456789abcdef",
            kind: .updateVerify,
            state: .accepted,
            startedAt: "2026-07-11T00:00:00Z",
            updatedAt: "2026-07-11T00:00:00Z",
            release: nil,
            artifact: nil,
            failure: nil
        )
        let data = try JSONEncoder().encode(operation)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(object.keys.contains("release"))
        XCTAssertTrue(object.keys.contains("artifact"))
        XCTAssertTrue(object.keys.contains("failure"))

        var missingArtifact = object
        missingArtifact.removeValue(forKey: "artifact")
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                PlatformWorkflowOperation.self,
                from: JSONSerialization.data(withJSONObject: missingArtifact)
            )
        )
    }

    @MainActor
    func testManagedPlatformSupportExportPublishesArtifactEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let operation = await createManagedPlatformSupportExport(in: directory) { destination in
            try Data("support evidence".utf8).write(to: destination, options: .withoutOverwriting)
            return RuntimeLogExportResult(destination: destination)
        }

        XCTAssertEqual(operation.kind, .supportExport)
        XCTAssertEqual(operation.state, .completed)
        let artifact = try XCTUnwrap(operation.artifact)
        XCTAssertTrue(artifact.path.hasPrefix(directory.path + "/"))
        XCTAssertEqual(artifact.sizeBytes, 16)
        XCTAssertEqual(artifact.sha256.count, 64)
        XCTAssertNil(operation.failure)
    }

    func testGuestServiceRestartRequestRoundTripsThroughJSON() throws {
        let request = RuntimeGuestServiceRestartRequest(
            service: "recorder-ingress",
            guestControlBaseURL: "http://192.168.64.2:18330"
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(RuntimeGuestServiceRestartRequest.self, from: encoded)

        XCTAssertEqual(decoded, request)
    }

    func testRuntimeLabRequestsRoundTripThroughJSON() throws {
        let create = RuntimeLabSessionCreateRequest(
            scenarioId: "post-operative-monitoring",
            name: "OR recovery lab",
            recorderCount: 2,
            targetURL: "http://edge/"
        )
        let replay = RuntimeLabVitalFileReplayRequest(
            vitalFileRelativePath: "MORA04/202301/230102/sample.vital",
            sessionName: "Replay sample",
            targetURL: "http://edge/",
            resourceSelection: RuntimeLabVitalFileReplayResourceSelection(mode: .quickCreate),
            repeatPolicy: RuntimeLabVitalFileReplayPolicy(mode: .once)
        )

        let decodedCreate = try JSONDecoder().decode(
            RuntimeLabSessionCreateRequest.self,
            from: try JSONEncoder().encode(create)
        )
        let decodedReplay = try JSONDecoder().decode(
            RuntimeLabVitalFileReplayRequest.self,
            from: try JSONEncoder().encode(replay)
        )

        XCTAssertEqual(decodedCreate, create)
        XCTAssertEqual(decodedReplay, replay)
    }

    func testErrorResponseEncoderBuildsDeterministicJSONBody() throws {
        let data = RuntimeControlErrorResponseEncoder.encode(
            code: .badRequest,
            message: "line 1\n\"quoted\""
        )
        let decoded = try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: data)

        XCTAssertEqual(decoded.code, .badRequest)
        XCTAssertEqual(decoded.message, "line 1\n\"quoted\"")
    }

    func testRuntimeInstallInfoDoesNotInferRedisBackupPathFromRollbackBackupPath() {
        let installInfo = RuntimeInstallInfo(backupsPath: "/rollback/backups")

        XCTAssertNil(installInfo.redisBackupsPath)
        XCTAssertNil(installInfo.runtimeDataBackupsPath)
    }

    func testEndpointMatchingIgnoresQueryString() {
        XCTAssertEqual(
            RuntimeControlAPIEndpoint.matching(method: .get, path: "/platform?refresh=false"),
            .platformState
        )
    }

    func testStaticFileResponderServesPWAIndexWithoutToken() throws {
        let root = try makeTemporaryPWA()
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root)

        let response = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/")))
        let body = try XCTUnwrap(response.body).text()

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "text/html; charset=utf-8")
        XCTAssertEqual(response.headers["Cache-Control"], "no-cache")
        XCTAssertTrue(body.contains("Runtime Control"))
    }

    func testStaticFileResponderReportsExistingFileReadFailureSeparatelyFromNotFound() throws {
        let root = try makeTemporaryPWA()
        let index = root.appendingPathComponent("index.html")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: index.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: index.path)
        }
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root)

        let response = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/")))

        XCTAssertEqual(response.status, .internalServerError)
        XCTAssertTrue(try XCTUnwrap(response.body).text().contains("Static file read failed"))
    }

    func testStaticFileResponderReportsPathInspectionFailureSeparatelyFromNotFound() throws {
        let root = URL(fileURLWithPath: "/runtime-control-pwa", isDirectory: true)
        let reader = FakeStaticFileReader(pathStates: [
            root.appendingPathComponent("index.html").path: .inspectFailed("permission denied"),
        ])
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root, fileReader: reader)

        let response = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/")))

        XCTAssertEqual(response.status, .internalServerError)
        XCTAssertEqual(
            try XCTUnwrap(response.body).text(),
            "Static file read failed: static file path inspection failed: /runtime-control-pwa/index.html reason=permission denied"
        )
        XCTAssertEqual(reader.readURLs, [])
    }

    func testStaticFileResponderDoesNotReadUnexpectedDirectoryAsStaticFile() throws {
        let root = URL(fileURLWithPath: "/runtime-control-pwa", isDirectory: true)
        let reader = FakeStaticFileReader(pathStates: [
            root.appendingPathComponent("assets/app.js").path: .directory,
        ])
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root, fileReader: reader)

        let response = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/assets/app.js")))

        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(reader.readURLs, [])
    }

    func testStaticFileResponderReportsUnknownPathStateSeparatelyFromNotFound() throws {
        let root = URL(fileURLWithPath: "/runtime-control-pwa", isDirectory: true)
        let reader = FakeStaticFileReader(pathStates: [
            root.appendingPathComponent("assets/app.js").path: .unknown("stale"),
        ])
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root, fileReader: reader)

        let response = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/assets/app.js")))

        XCTAssertEqual(response.status, .internalServerError)
        XCTAssertEqual(
            try XCTUnwrap(response.body).text(),
            "Static file read failed: static file path state is unexpected: /runtime-control-pwa/assets/app.js state=stale"
        )
        XCTAssertEqual(reader.readURLs, [])
    }

    func testStaticFileResponderRejectsParentDirectoryTraversalInsteadOfFallingBackToIndex() throws {
        let root = URL(fileURLWithPath: "/runtime-control-pwa", isDirectory: true)
        let reader = FakeStaticFileReader(pathStates: [
            root.appendingPathComponent("index.html").path: .file,
        ])
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root, fileReader: reader)

        let response = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/../secret.css")))

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(
            try XCTUnwrap(response.body).text(),
            "Static file request rejected: static file path contains parent directory segment"
        )
        XCTAssertEqual(reader.readURLs, [])
    }

    func testStaticFileResponderRejectsPercentEncodedParentDirectoryTraversal() throws {
        let root = URL(fileURLWithPath: "/runtime-control-pwa", isDirectory: true)
        let reader = FakeStaticFileReader(pathStates: [
            root.appendingPathComponent("index.html").path: .file,
        ])
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root, fileReader: reader)

        let response = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/%2e%2e/secret.css")))

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(
            try XCTUnwrap(response.body).text(),
            "Static file request rejected: static file path contains parent directory segment"
        )
        XCTAssertEqual(reader.readURLs, [])
    }

    func testStaticFileResponderRejectsInvalidPercentEncodingWithoutIndexFallback() throws {
        let root = URL(fileURLWithPath: "/runtime-control-pwa", isDirectory: true)
        let reader = FakeStaticFileReader(pathStates: [
            root.appendingPathComponent("index.html").path: .file,
        ])
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root, fileReader: reader)

        let response = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/%E0%A4%A")))

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(
            try XCTUnwrap(response.body).text(),
            "Static file request rejected: static file path percent-decoding failed"
        )
        XCTAssertEqual(reader.readURLs, [])
    }

    func testStaticFileResponderDoesNotInterceptRuntimeAPI() throws {
        let root = try makeTemporaryPWA()
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root)

        XCTAssertNil(responder.response(for: .init(method: .get, path: "/platform")))
        XCTAssertNil(responder.response(for: .init(method: .get, path: "/runtime/vitaldb/recorders")))
        XCTAssertNil(responder.response(for: .init(method: .get, path: "/runtime/lab/scenarios")))
        XCTAssertNil(responder.response(for: .init(method: .get, path: "/platform/logs/stream")))
    }

    func testStaticFileResponderDoesNotInterceptRuntimeAPIWithQueryString() throws {
        let root = try makeTemporaryPWA()
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root)

        XCTAssertNil(responder.response(for: .init(method: .get, path: "/platform?refresh=true")))
    }

    func testStaticFileResponderFallsBackToIndexForSPARoutes() throws {
        let root = try makeTemporaryPWA()
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root)

        let response = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/recorders/VR_001")))

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(try XCTUnwrap(response.body).text(), "<html>Runtime Control</html>")
    }

    func testStaticFileResponderServesAssetsWithImmutableCache() throws {
        let root = try makeTemporaryPWA()
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try "body {}".write(to: assets.appendingPathComponent("index.css"), atomically: true, encoding: .utf8)
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root)

        let response = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/assets/index.css")))

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "text/css; charset=utf-8")
        XCTAssertEqual(response.headers["Cache-Control"], "public, max-age=31536000, immutable")
    }

    func testStaticFileResponderDoesNotLongCacheServiceWorkerFiles() throws {
        let root = try makeTemporaryPWA()
        try "self.skipWaiting()".write(to: root.appendingPathComponent("sw.js"), atomically: true, encoding: .utf8)
        try "{}".write(to: root.appendingPathComponent("manifest.webmanifest"), atomically: true, encoding: .utf8)
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root)

        let serviceWorker = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/sw.js")))
        let manifest = try XCTUnwrap(responder.response(for: .init(method: .get, path: "/manifest.webmanifest")))

        XCTAssertEqual(serviceWorker.headers["Cache-Control"], "no-cache")
        XCTAssertEqual(manifest.headers["Cache-Control"], "no-cache")
    }

    func testOpenAPIRoutesMatchRuntimeControlAPIEndpoints() throws {
        let documentedRoutes = try openAPIRouteKeys()
        let endpointRoutes = Set(RuntimeControlAPIEndpoint.allCases.map { endpoint in
            "\(endpoint.route.method.rawValue) \(endpoint.route.path)"
        })

        XCTAssertEqual(documentedRoutes, endpointRoutes)
    }

    func testOpenAPIUsesRuntimeControlTokenHeader() throws {
        let document = try openAPIDocument()
        let components = try XCTUnwrap(document["components"] as? [String: Any])
        let securitySchemes = try XCTUnwrap(components["securitySchemes"] as? [String: Any])
        let token = try XCTUnwrap(securitySchemes["runtimeControlToken"] as? [String: Any])

        XCTAssertEqual(token["type"] as? String, "apiKey")
        XCTAssertEqual(token["in"] as? String, "header")
        XCTAssertEqual(token["name"] as? String, "X-Runtime-Control-Token")
    }

    func testOpenAPIScopeAndAccessMatchRuntimeControlAPIEndpoints() throws {
        let operations = try openAPIOperations()

        for endpoint in RuntimeControlAPIEndpoint.allCases {
            let key = "\(endpoint.route.method.rawValue) \(endpoint.route.path)"
            let operation = try XCTUnwrap(operations[key])

            XCTAssertEqual(operation["x-runtime-control-scope"] as? String, endpoint.route.scope.rawValue)
            XCTAssertEqual(operation["x-runtime-control-access"] as? String, endpoint.clientAccess.rawValue)
        }
    }

    func testRuntimeEventStreamOpenAPIUsesSSEMediaType() throws {
        let operations = try openAPIOperations()

        for key in [
            "GET /platform/stream",
            "GET /runtime/vitaldb/observations/stream",
            "GET /platform/logs/stream",
        ] {
            let operation = try XCTUnwrap(operations[key])
            let responses = try XCTUnwrap(operation["responses"] as? [String: Any])
            let okResponse = try XCTUnwrap(responses["200"] as? [String: Any])
            let content = try XCTUnwrap(okResponse["content"] as? [String: Any])

            XCTAssertNotNil(content["text/event-stream"], key)
        }
    }

    func testRuntimeControlAPIStreamCapabilitiesAreExplicit() {
        let supported: Set<RuntimeControlAPIEndpoint> = [
            .platformStateStream,
            .vitalDBObservationStream,
            .logStream,
        ]

        for endpoint in RuntimeControlAPIEndpoint.allCases {
            let expected: RuntimeControlAPIStreamCapability = supported.contains(endpoint) ? .supported : .unsupported
            XCTAssertEqual(endpoint.streamCapability, expected, endpoint.rawValue)
        }

        XCTAssertEqual(RuntimeControlAPIEndpoint.vitalDBRecorders.streamCapability, .unsupported)
        XCTAssertEqual(RuntimeControlAPIEndpoint.vitalDBRecorder.streamCapability, .unsupported)
        XCTAssertEqual(RuntimeControlAPIEndpoint.vitalDBRelationships.streamCapability, .unsupported)
    }

    func testRuntimeEventTypeOpenAPIEnumMatchesSwiftContract() throws {
        let openAPIEventTypes = try openAPIStringEnum(named: "RuntimeEventType")
        let swiftEventTypes = RuntimeOperationEventType.allCases.map(\.rawValue)

        XCTAssertEqual(openAPIEventTypes, swiftEventTypes)
    }

    func testRuntimeEventsOpenAPIPreservesGuestLedgerFailureContract() throws {
        let operation = try XCTUnwrap(try openAPIOperations()["GET /runtime/events"])
        let parameters = try XCTUnwrap(operation["parameters"] as? [[String: Any]])
        let since = try XCTUnwrap(parameters.first { $0["name"] as? String == "since" })
        let sinceSchema = try XCTUnwrap(since["schema"] as? [String: Any])
        let sinceDescription = try XCTUnwrap(sinceSchema["description"] as? String)
        let responses = try XCTUnwrap(operation["responses"] as? [String: Any])
        let unavailable = try XCTUnwrap(responses["503"] as? [String: Any])
        let content = try XCTUnwrap(unavailable["content"] as? [String: Any])
        let json = try XCTUnwrap(content["application/json"] as? [String: Any])
        let errorSchema = try XCTUnwrap(json["schema"] as? [String: Any])

        XCTAssertTrue(sinceDescription.contains("explicit UTC designator"))
        XCTAssertEqual(
            errorSchema["$ref"] as? String,
            "#/components/schemas/RuntimeControlErrorResponse"
        )
        XCTAssertEqual(
            try openAPIStringEnum(named: "RuntimeControlAPIErrorCode"),
            RuntimeControlAPIErrorCode.allCases.map(\.rawValue)
        )
    }

    func testGuestControlOperationOpenAPIEnumsMatchSwiftContract() throws {
        let openAPICommands = try openAPIStringEnum(
            schemaName: "RuntimeGuestControlServiceOperation",
            propertyName: "command"
        )
        let openAPIStates = try openAPIStringEnum(
            schemaName: "RuntimeGuestControlServiceOperation",
            propertyName: "state"
        )

        XCTAssertEqual(
            openAPICommands,
            RuntimeGuestControlServiceCommand.allCases.map(\.rawValue)
        )
        XCTAssertEqual(
            openAPIStates,
            RuntimeGuestControlOperationState.allCases.map(\.rawValue)
        )
    }

    func testGuestControlMutationOpenAPIEndpointsDeclareExplicitLeaseConflict() throws {
        let operations = try openAPIOperations()
        let operationKeys = [
            "PUT /runtime/settings",
            "POST /runtime/admin-password",
            "PUT /runtime/redis-relay/settings",
            "POST /runtime/lab/beds/create",
            "POST /runtime/lab/beds/delete",
            "POST /runtime/lab/beds/reset",
            "POST /runtime/lab/recorders/create",
            "POST /runtime/lab/recorders/delete",
            "POST /runtime/lab/recorders/reset",
            "POST /runtime/lab/sessions",
            "POST /runtime/lab/sessions/{sessionId}/start",
            "POST /runtime/lab/sessions/{sessionId}/stop",
            "POST /runtime/lab/vital-files/replay",
            "POST /runtime/lab/vital-files/upload",
            "POST /runtime/services/{service}/start",
            "POST /runtime/services/{service}/stop",
            "POST /runtime/services/{service}/restart",
            "POST /runtime/maintenance/datastore/repair",
            "POST /platform/backups/redis",
            "POST /platform/backups/redis/restore",
        ]

        for key in operationKeys {
            let operation = try XCTUnwrap(operations[key], key)
            let responses = try XCTUnwrap(operation["responses"] as? [String: Any], key)
            let conflict = try XCTUnwrap(responses["409"] as? [String: Any], key)
            XCTAssertEqual(
                conflict["$ref"] as? String,
                "#/components/responses/OperationInProgress",
                key
            )
        }
    }

    func testRecorderIngressMemoryGuardStatusOpenAPIEnumMatchesSwiftContract() throws {
        let openAPIStatuses = try openAPIStringEnum(
            schemaName: "RuntimeRecorderIngressReplayAdaptiveStatus",
            propertyName: "memoryGuardStatus"
        )
        let swiftStatuses = RuntimeRecorderIngressMemoryGuardStatus.allCases.map(\.rawValue)

        XCTAssertEqual(openAPIStatuses, swiftStatuses)
    }

    func testRuntimeControlOpenAPIOperationsDoNotUseFileReferences() throws {
        let operations = try openAPIOperations()

        for endpoint in RuntimeControlAPIEndpoint.allCases where endpoint.route.scope == .runtimeControl {
            let key = "\(endpoint.route.method.rawValue) \(endpoint.route.path)"
            let operation = try XCTUnwrap(operations[key])
            let data = try JSONSerialization.data(withJSONObject: operation, options: [.sortedKeys])
            let text = try XCTUnwrap(String(data: data, encoding: .utf8))

            XCTAssertFalse(text.contains("RuntimeControlFileReference"), key)
        }
    }

    @MainActor
    func testRouterServesReadOnlyRuntimeEndpointsAsJSON() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/platform"))

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "application/json")

        let body = try XCTUnwrap(response.body)
        let status = try JSONDecoder().decode(PlatformState.self, from: body)

        XCTAssertEqual(status.runtimeInstallationState, .executable)
        XCTAssertEqual(status.platformHealth, .healthy)
        XCTAssertEqual(status.installedVersion, "1.2.3")

    }

    @MainActor
    func testRuntimeStatusStreamReturnsSSEFrameFromRuntimeStatus() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/platform/stream")))
        let event = try await firstStreamEvent(stream)
        let text = try XCTUnwrap(String(data: try RuntimeControlServerSentEventCodec.encode(event), encoding: .utf8))

        XCTAssertEqual(stream.status, .ok)
        XCTAssertEqual(stream.headers["Content-Type"], "text/event-stream")
        XCTAssertTrue(text.contains("id: platform-state"))
        XCTAssertTrue(text.contains("event: platform-state"))
        XCTAssertTrue(text.contains("\"installedVersion\":\"1.2.3\""))
    }

    @MainActor
    func testRuntimeStatusStreamHeartbeatUsesInjectedClock() async throws {
        let clock = RuntimeControlStreamTestClock([
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 2),
        ])
        let router = RuntimeControlAPIRouter(
            handler: StubRuntimeControlAPIReadHandler(status: PlatformState(
                runtimeInstallationState: .executable,
                services: [
                    PlatformServiceStatus(role: .runtimeProvider, state: .loaded),
                    PlatformServiceStatus(role: .publicProxy, state: .loaded),
                    PlatformServiceStatus(role: .logSync, state: .loaded),
                    PlatformServiceStatus(role: .watchdog, state: .loaded),
                ],
                platformHealth: .healthy,
                installedVersion: "1.2.3"
            )),
            streamConfiguration: RuntimeControlAPIStreamConfiguration(
                pollIntervalNanoseconds: 1_000_000,
                heartbeatIntervalNanoseconds: 1_000_000_000
            ),
            now: clock.now
        )

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/platform/stream")))
        var iterator = stream.events.makeAsyncIterator()
        let firstEvent = try await iterator.next()
        let secondEvent = try await iterator.next()
        let first = try XCTUnwrap(firstEvent)
        let second = try XCTUnwrap(secondEvent)

        XCTAssertEqual(first.id, "platform-state")
        XCTAssertEqual(second, .heartbeat)
    }

    @MainActor
    func testHostLogStreamReturnsSSEFrameFromLogText() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/platform/logs/stream?source=command&lineLimit=5")))
        let event = try await firstStreamEvent(stream)
        let text = try XCTUnwrap(String(data: try RuntimeControlServerSentEventCodec.encode(event), encoding: .utf8))

        XCTAssertEqual(stream.status, .ok)
        XCTAssertEqual(stream.headers["Content-Type"], "text/event-stream")
        XCTAssertTrue(text.contains("id: runtime-log-command"))
        XCTAssertTrue(text.contains("event: runtime-log"))
        XCTAssertTrue(text.contains("\"text\":\"command log tail 5\""))
    }

    @MainActor
    func testVitalDBObservationStreamPreservesReadSnapshotState() async throws {
        let handler = StubRuntimeControlAPIReadHandler()
        let router = RuntimeControlAPIRouter(handler: handler)

        let stream = try await streamResponse(from: router.routeResult(.init(
            method: .get,
            path: "/runtime/vitaldb/observations/stream"
        )))
        let event = try await firstStreamEvent(stream)
        let data = try RuntimeControlServerSentEventCodec.encode(event)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decodedEventData = try JSONDecoder().decode(RuntimeVitalDBObservationSnapshot.self, from: try XCTUnwrap(event.data))

        XCTAssertEqual(stream.status, .ok)
        XCTAssertEqual(event.id, "vitaldb-observation")
        XCTAssertEqual(event.event, "vitaldb-observed")
        XCTAssertTrue(text.contains("\"state\":\"loaded\""))
        XCTAssertTrue(text.contains("\"observation\""))
        XCTAssertEqual(decodedEventData.state, .loaded)
        XCTAssertEqual(decodedEventData.observation?.observedAt, "2026-05-25T00:00:00Z")
    }

    func testServerSentEventCodecRejectsIncompleteFrames() throws {
        XCTAssertThrowsError(try RuntimeControlServerSentEventCodec.encode(RuntimeControlServerSentEvent(
            id: nil,
            event: "platform-state",
            data: Data("{}".utf8)
        ))) { error in
            XCTAssertEqual(error as? RuntimeControlServerSentEventEncodingError, .missingID)
        }

        XCTAssertThrowsError(try RuntimeControlServerSentEventCodec.encode(RuntimeControlServerSentEvent(
            id: "platform-state",
            event: nil,
            data: Data("{}".utf8)
        ))) { error in
            XCTAssertEqual(error as? RuntimeControlServerSentEventEncodingError, .missingEvent)
        }

        XCTAssertThrowsError(try RuntimeControlServerSentEventCodec.encode(RuntimeControlServerSentEvent(
            id: "platform-state",
            event: "platform-state",
            data: nil
        ))) { error in
            XCTAssertEqual(error as? RuntimeControlServerSentEventEncodingError, .missingData)
        }

        XCTAssertThrowsError(try RuntimeControlServerSentEventCodec.encode(RuntimeControlServerSentEvent(
            id: "platform-state",
            event: "platform-state",
            data: Data([0xFF])
        ))) { error in
            XCTAssertEqual(error as? RuntimeControlServerSentEventEncodingError, .invalidUTF8Data)
        }

        let heartbeat = try RuntimeControlServerSentEventCodec.encode(.heartbeat)
        XCTAssertEqual(String(data: heartbeat, encoding: .utf8), ": heartbeat\n\n")
    }

    @MainActor
    func testRouterServesCapabilitiesSettingsHealthReleaseAndInstallInfo() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let platformCapabilities = try await decode(
            PlatformCapabilities.self,
            from: router.route(.init(method: .get, path: "/platform/capabilities"))
        )
        let runtimeCapabilities = try await decode(
            RuntimeCapabilities.self,
            from: router.route(.init(method: .get, path: "/runtime/capabilities"))
        )
        let settings = try await decode(
            RuntimeProductSettingsRead.self,
            from: router.route(.init(method: .get, path: "/runtime/settings"))
        )
        let health = try await decode(
            PlatformState.self,
            from: router.route(.init(method: .post, path: "/platform/health"))
        )
        let release = try await decode(
            RuntimeReleaseInfo.self,
            from: router.route(.init(method: .get, path: "/platform/release"))
        )
        let installInfo = try await decode(
            RuntimeInstallInfo.self,
            from: router.route(.init(method: .get, path: "/platform/installation"))
        )
        let operationState = try await decode(
            PlatformOperationState.self,
            from: router.route(.init(method: .get, path: "/platform/operations"))
        )
        let guestAddress = try await decode(
            RuntimeGuestAddressResourceState.self,
            from: router.route(.init(method: .get, path: "/platform/runtime-endpoint"))
        )
        let vmLifecycle = try await decode(
            RuntimeVMLifecycleResourceState.self,
            from: router.route(.init(method: .get, path: "/platform/runtime-provider"))
        )
        let events = try await decode(
            RuntimeOperationEventHistory.self,
            from: router.route(.init(method: .get, path: "/runtime/events"))
        )
        let vitalDBObservation = try await decode(
            VitalDBObservationDocument?.self,
            from: router.route(.init(method: .get, path: "/runtime/vitaldb/observations/latest"))
        )
        let vitalRecorders = try await decode(
            RuntimeVitalRecorderHistory.self,
            from: router.route(.init(method: .get, path: "/runtime/vitaldb/recorders"))
        )
        let vitalRecorder = try await decode(
            RuntimeVitalRecorderRecord.self,
            from: router.route(.init(method: .get, path: "/runtime/vitaldb/recorders/VR_A"))
        )
        let vitalRecorderActivity = try await decode(
            RuntimeVitalRecorderActivityWindow.self,
            from: router.route(.init(
                method: .get,
                path: "/runtime/vitaldb/recorders/VR_A/activity?bucketSeconds=60&period=all&pageIndex=0"
            ))
        )
        let vitalBeds = try await decode(
            RuntimeVitalBedHistory.self,
            from: router.route(.init(method: .get, path: "/runtime/vitaldb/beds"))
        )
        let vitalBed = try await decode(
            RuntimeVitalBedRecord.self,
            from: router.route(.init(method: .get, path: "/runtime/vitaldb/beds/bed-a"))
        )
        let vitalRelationships = try await decode(
            RuntimeVitalRelationshipHistory.self,
            from: router.route(.init(method: .get, path: "/runtime/vitaldb/relationships"))
        )

        XCTAssertTrue(platformCapabilities.canControlRuntimeServices)
        XCTAssertTrue(runtimeCapabilities.capabilities.contains("services:list"))
        XCTAssertEqual(health.platformHealth, .healthy)
        XCTAssertEqual(settings.state, .loaded)
        XCTAssertEqual(settings.settings?.publicHost, "vitalserver.local")
        XCTAssertEqual(health.installedVersion, "healthy")
        XCTAssertEqual(release.helperVersion, "0.1.0")
        XCTAssertEqual(installInfo.runtimeHomePath, "/runtime/home")
        XCTAssertEqual(operationState.activeOperation, nil)
        XCTAssertEqual(operationState.install.state, .unavailable)
        XCTAssertNil(operationState.install.document)
        XCTAssertNil(operationState.install.readError)
        XCTAssertEqual(operationState.lease.state, .unavailable)
        XCTAssertNil(operationState.lease.document)
        XCTAssertNil(operationState.lease.readError)
        XCTAssertNil(operationState.lease.staleReason)
        XCTAssertEqual(guestAddress.state, .missing)
        XCTAssertNil(guestAddress.read)
        XCTAssertEqual(vmLifecycle.state, .missing)
        XCTAssertNil(vmLifecycle.document)
        XCTAssertEqual(events.events.map(\.id), ["runtime-operation-event-1"])
        XCTAssertEqual(vitalDBObservation?.recorders.map(\.vrcode), ["VR_A"])
        XCTAssertEqual(vitalRecorders.recorders.map(\.vrcode), ["VR_A"])
        XCTAssertEqual(vitalRecorders.recorders.first?.activityTimeline?.first?.messageCount, 3)
        XCTAssertEqual(vitalRecorder.vrcode, "VR_A")
        XCTAssertEqual(vitalRecorder.activityTimeline?.first?.byteCount, 2048)
        XCTAssertEqual(vitalRecorder.activityTimeline?.first?.buckets.first?.bucketSeconds, 60)
        XCTAssertEqual(vitalRecorderActivity.query.vrcode, "VR_A")
        XCTAssertEqual(vitalRecorderActivity.query.period, .all)
        XCTAssertEqual(vitalRecorderActivity.query.pageIndex, 0)
        XCTAssertEqual(vitalRecorderActivity.buckets.first?.messageCount, 3)
        XCTAssertEqual(vitalBeds.beds.map(\.bedID), ["bed-a"])
        XCTAssertEqual(vitalBed.vrcode, "VR_A")
        XCTAssertEqual(vitalRelationships.assignments.map(\.vrcode), ["VR_A"])
        XCTAssertEqual(vitalRelationships.events.first?.eventType, .handoff)
    }

    @MainActor
    func testRouterServesOperationStateFromOperationStateContractWithoutLoadingStatus() async throws {
        let lease = RuntimeOperationLeaseDocument(
            operationId: "operation-1",
            operation: .applyBundle,
            ownerPID: 123,
            startedAt: "2026-07-08T00:00:00Z",
            heartbeatAt: "2026-07-08T00:00:01Z",
            expiresAt: "2026-07-08T00:05:00Z",
            message: "applying bundle"
        )
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler(
            statusError: StubRuntimeControlAPIReadHandlerError.statusShouldNotBeLoaded,
            operationState: PlatformOperationState(
                activeOperation: nil,
                install: .unavailable(),
                lease: .loaded(lease)
            )
        ))

        let operationState = try await decode(
            PlatformOperationState.self,
            from: router.route(.init(method: .get, path: "/platform/operations"))
        )

        XCTAssertEqual(operationState.activeOperation, .applyBundle)
        XCTAssertEqual(operationState.lease.state, .loaded)
        XCTAssertEqual(operationState.lease.document, lease)
    }

    @MainActor
    func testRouterServesRedisRelayOwnerResourceWithoutLoadingStatus() async throws {
        let expected = RuntimeRedisRelayStatusReadResult(
            readState: .readFailed,
            document: nil,
            readError: "owner unavailable"
        )
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler(
            statusError: StubRuntimeControlAPIReadHandlerError.statusShouldNotBeLoaded,
            redisRelayStatusRead: expected
        ))

        let read = try await decode(
            RuntimeRedisRelayStatusReadResult.self,
            from: router.route(.init(method: .get, path: "/runtime/redis-relay/status"))
        )

        XCTAssertEqual(read, expected)
    }

    @MainActor
    func testRouterServesAndUpdatesHostGuestAddressResourceWithoutLoadingStatus() async throws {
        let readResult = RuntimeGuestAddressReadResult.loaded(
            address: "192.168.64.10",
            source: .platformAgent
        )
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler(
            statusError: StubRuntimeControlAPIReadHandlerError.statusShouldNotBeLoaded,
            guestAddressResource: .loaded(readResult)
        ))

        let read = try await decode(
            RuntimeGuestAddressResourceState.self,
            from: router.route(.init(method: .get, path: "/platform/runtime-endpoint"))
        )
        let updated = try await decode(
            RuntimeGuestAddressResourceState.self,
            from: router.route(.init(
                method: .put,
                path: "/platform/runtime-endpoint",
                body: try JSONEncoder().encode(RuntimeGuestAddressPutRequest(address: "192.168.64.11"))
            ))
        )

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.read, readResult)
        XCTAssertEqual(updated.state, .loaded)
        XCTAssertEqual(updated.read?.loadedAddress, "192.168.64.11")
        XCTAssertEqual(updated.read?.source, .platformAgent)
    }

    @MainActor
    func testRouterServesAndUpdatesHostVMLifecycleResourceWithoutLoadingStatus() async throws {
        let document = RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            operation: .install,
            startedAt: "2026-07-09T01:00:00Z",
            updatedAt: "2026-07-09T01:01:00Z",
            deadlineAt: nil,
            terminalReason: nil,
            message: "bootstrapping"
        )
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler(
            statusError: StubRuntimeControlAPIReadHandlerError.statusShouldNotBeLoaded,
            vmLifecycleResource: .loaded(document)
        ))

        let read = try await decode(
            RuntimeVMLifecycleResourceState.self,
            from: router.route(.init(method: .get, path: "/platform/runtime-provider"))
        )
        let updated = try await decode(
            RuntimeVMLifecycleResourceState.self,
            from: router.route(.init(
                method: .put,
                path: "/platform/runtime-provider",
                body: try JSONEncoder().encode(RuntimeVMLifecyclePutRequest(document: document))
            ))
        )

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.document, document)
        XCTAssertEqual(updated.state, .loaded)
        XCTAssertEqual(updated.document, document)
    }

    @MainActor
    func testRouterControlsRuntimeProviderWithoutInventingLifecycleState() async throws {
        let missing = RuntimeVMLifecycleResourceState.missing(
            readError: "Runtime Provider lifecycle document missing"
        )
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler(
            vmLifecycleResource: missing
        ))

        let response = await router.route(.init(
            method: .post,
            path: "/platform/runtime-provider/start"
        ))
        XCTAssertEqual(response.status, .ok)
        let wireResponse = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(response.body)) as? [String: Any]
        )
        let wireProvider = try XCTUnwrap(wireResponse["provider"] as? [String: Any])
        XCTAssertTrue(wireResponse["failure"] is NSNull)
        XCTAssertTrue(wireProvider["document"] is NSNull)
        XCTAssertEqual(
            wireProvider["readError"] as? String,
            "Runtime Provider lifecycle document missing"
        )
        let result = try decode(RuntimeProviderCommandResponse.self, from: response)
        XCTAssertEqual(result.action, .start)
        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.provider, missing)
        XCTAssertNil(result.failure)
    }

    @MainActor
    func testRouterEncodesRuntimeProviderLifecycleNullablesExplicitly() async throws {
        let lifecycle = RuntimeVMLifecycleDocument(
            state: .running,
            startedAt: "2026-07-12T00:00:00Z",
            updatedAt: "2026-07-12T00:00:01Z"
        )
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler(
            providerCommandResponse: RuntimeProviderCommandResponse(
                operationId: "provider-restart-1",
                action: .restart,
                state: .completed,
                provider: .loaded(lifecycle),
                failure: nil
            )
        ))

        let response = await router.route(.init(
            method: .post,
            path: "/platform/runtime-provider/restart"
        ))
        XCTAssertEqual(response.status, .ok)

        let wireResponse = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(response.body)) as? [String: Any]
        )
        let wireProvider = try XCTUnwrap(wireResponse["provider"] as? [String: Any])
        let wireLifecycle = try XCTUnwrap(wireProvider["document"] as? [String: Any])

        XCTAssertTrue(wireResponse["failure"] is NSNull)
        XCTAssertTrue(wireProvider["readError"] is NSNull)
        for key in [
            "operation",
            "operationID",
            "bootID",
            "deadlineAt",
            "terminalReason",
            "message",
        ] {
            XCTAssertTrue(wireLifecycle[key] is NSNull, "Expected explicit null for \(key)")
        }
    }

    @MainActor
    func testRouterPreservesRuntimeProviderEffectFailureAsServiceUnavailable() async throws {
        let failure = RuntimeProviderCommandResponse(
            operationId: "provider-failed",
            action: .restart,
            state: .failed,
            provider: .missing(readError: "lifecycle missing"),
            failure: PlatformCommandFailure(
                kind: "permission-denied",
                message: "launchd access denied"
            )
        )
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler(
            providerCommandResponse: failure
        ))

        let response = await router.route(.init(
            method: .post,
            path: "/platform/runtime-provider/restart"
        ))
        XCTAssertEqual(response.status, .serviceUnavailable)
        XCTAssertEqual(
            try JSONDecoder().decode(
                RuntimeProviderCommandResponse.self,
                from: try XCTUnwrap(response.body)
            ),
            failure
        )
    }

    @MainActor
    func testRouterServesLabNamespaceWithExplicitUnavailableState() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())
        let createRequest = RuntimeLabSessionCreateRequest(
            scenarioId: "post-operative-monitoring",
            recorderCount: 2
        )
        let replayRequest = RuntimeLabVitalFileReplayRequest(
            vitalFileRelativePath: "MORA04/202301/230102/sample.vital",
            resourceSelection: RuntimeLabVitalFileReplayResourceSelection(mode: .quickCreate),
            repeatPolicy: RuntimeLabVitalFileReplayPolicy(mode: .once)
        )
        let uploadBoundary = "runtime-vital-files-boundary"
        let uploadBody = Data(
            "--\(uploadBoundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"first.vital\"\r\nContent-Type: application/octet-stream\r\n\r\nfirst\r\n--\(uploadBoundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"second.vital\"\r\nContent-Type: application/octet-stream\r\n\r\nsecond\r\n--\(uploadBoundary)--\r\n".utf8
        )

        let scenarios = try await decode(
            RuntimeLabScenarioList.self,
            from: router.route(.init(method: .get, path: "/runtime/lab/scenarios"))
        )
        let vitalFiles = try await decode(
            RuntimeLabVitalFileList.self,
            from: router.route(.init(method: .get, path: "/runtime/lab/vital-files"))
        )
        let beds = try await decode(
            RuntimeLabBedList.self,
            from: router.route(.init(method: .get, path: "/runtime/lab/beds"))
        )
        let recorders = try await decode(
            RuntimeLabRecorderList.self,
            from: router.route(.init(method: .get, path: "/runtime/lab/recorders"))
        )
        let create = try await decode(RuntimeLabSessionResponse.self, from: router.route(.init(
            method: .post,
            path: "/runtime/lab/sessions",
            body: try JSONEncoder().encode(createRequest)
        )))
        let session = try await decode(
            RuntimeLabSessionResponse.self,
            from: router.route(.init(method: .get, path: "/runtime/lab/sessions/session-1"))
        )
        let start = try await decode(
            RuntimeLabSessionResponse.self,
            from: router.route(.init(method: .post, path: "/runtime/lab/sessions/session-1/start"))
        )
        let stop = try await decode(
            RuntimeLabSessionResponse.self,
            from: router.route(.init(method: .post, path: "/runtime/lab/sessions/session-1/stop"))
        )
        let replay = try await decode(RuntimeLabSessionResponse.self, from: router.route(.init(
            method: .post,
            path: "/runtime/lab/vital-files/replay",
            body: try JSONEncoder().encode(replayRequest)
        )))
        let upload = try await decode(RuntimeLabVitalFileLibraryUploadResponse.self, from: router.route(.init(
            method: .post,
            path: "/runtime/lab/vital-files/upload",
            headers: ["Content-Type": "multipart/form-data; boundary=\(uploadBoundary)"],
            body: uploadBody
        )))

        XCTAssertEqual(scenarios.state, .unavailable)
        XCTAssertEqual(scenarios.scenarios, [])
        XCTAssertEqual(scenarios.readError, "Runtime Lab gateway is unavailable.")
        XCTAssertEqual(vitalFiles.state, .unavailable)
        XCTAssertEqual(vitalFiles.vitalFiles, [])
        XCTAssertEqual(beds.state, .unavailable)
        XCTAssertEqual(beds.beds, [])
        XCTAssertEqual(recorders.state, .unavailable)
        XCTAssertEqual(recorders.recorders, [])
        XCTAssertEqual(create.state, .unavailable)
        XCTAssertEqual(session.state, .unavailable)
        XCTAssertEqual(start.state, .unavailable)
        XCTAssertEqual(stop.state, .unavailable)
        XCTAssertEqual(replay.state, .unavailable)
        XCTAssertEqual(upload.state, "completed")
        XCTAssertEqual(upload.files.map(\.fileName), ["first.vital", "second.vital"])
    }

    @MainActor
    func testVitalDBSingleResourceRoutesReturnTypedNotFoundInsteadOfJSONNull() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let missingRecorder = await router.route(.init(method: .get, path: "/runtime/vitaldb/recorders/VR_MISSING"))
        let missingBed = await router.route(.init(method: .get, path: "/runtime/vitaldb/beds/bed-missing"))
        let recorderError = try decodeError(from: missingRecorder)
        let bedError = try decodeError(from: missingBed)

        XCTAssertEqual(missingRecorder.status, .notFound)
        XCTAssertEqual(recorderError.code, .resourceNotFound)
        XCTAssertEqual(recorderError.message, "VitalDB recorder not found: VR_MISSING")
        XCTAssertEqual(missingBed.status, .notFound)
        XCTAssertEqual(bedError.code, .resourceNotFound)
        XCTAssertEqual(bedError.message, "VitalDB bed not found: bed-missing")
    }

    @MainActor
    func testRouterReturnsTypedNotFoundErrorForUnknownRoute() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/missing"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(error.code, .routeNotFound)
    }

    @MainActor
    func testRouterReturnsTypedMethodErrorForMethodMismatch() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .post, path: "/platform"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .methodNotAllowed)
        XCTAssertEqual(error.code, .methodNotAllowed)
    }

    @MainActor
    func testRouterPreservesExplicitGuestControlLeaseConflict() async throws {
        var handler = StubRuntimeControlAPIReadHandler()
        handler.startGuestServiceError = RuntimeControlOperationInProgressError(
            message: "guest control lease is held by operation op-123"
        )
        let router = RuntimeControlAPIRouter(handler: handler)

        let response = await router.route(.init(
            method: .post,
            path: "/runtime/services/app/start"
        ))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .conflict)
        XCTAssertEqual(error.code, .operationInProgress)
        XCTAssertEqual(error.message, "guest control lease is held by operation op-123")
    }

    @MainActor
    func testRouterExecutesRestoreBackupEndpointsThroughHandler() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let redisRequest = RuntimeBackupRequest(
            backup: RuntimeControlFileReference(kind: .localPath, value: "/redis-backups/redis.tar.gz")
        )
        let runtimeDataRequest = RuntimeBackupRequest(
            backup: RuntimeControlFileReference(kind: .localPath, value: "/backups/vitalserver-helper/manual")
        )

        let redis = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .post,
            path: "/platform/backups/redis/restore",
            body: try JSONEncoder().encode(redisRequest)
        )))
        let runtimeData = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .post,
            path: "/platform/backups/runtime-data/restore",
            body: try JSONEncoder().encode(runtimeDataRequest)
        )))

        XCTAssertEqual(redis.result.stdout, "restore redis /redis-backups/redis.tar.gz")
        XCTAssertEqual(runtimeData.result.stdout, "restore runtime data /backups/vitalserver-helper/manual")
    }

    @MainActor
    func testRouterExecutesRuntimeCommandEndpointsThroughHandler() async throws {
        let handler = StubRuntimeControlAPIReadHandler()
        let router = RuntimeControlAPIRouter(handler: handler)
        let settingsRequest = RuntimeApplyProductSettingsRequest(settings: testRuntimeProductSettings())

        let applyResponse = await router.route(.init(
            method: .put,
            path: "/runtime/settings",
            body: try JSONEncoder().encode(settingsRequest)
        ))
        let applySettings = try JSONDecoder().decode(
            RuntimeGuestControlServiceOperation.self,
            from: try XCTUnwrap(applyResponse.body)
        )
        let adminResponse = await router.route(.init(
            method: .post,
            path: "/runtime/admin-password",
            body: try JSONEncoder().encode(RuntimeAdminPasswordRequest(password: "new-admin-secret"))
        ))
        let applyAdminPassword = try JSONDecoder().decode(
            RuntimeGuestControlServiceOperation.self,
            from: try XCTUnwrap(adminResponse.body)
        )
        let repairRuntime = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(method: .post, path: "/platform/services/repair")))
        let repairProxy = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .post,
            path: "/platform/proxy/repair"
        )))
        let repairDatastoreResponse = await router.route(.init(
            method: .post,
            path: "/runtime/maintenance/datastore/repair"
        ))
        let repairDatastore = try JSONDecoder().decode(
            RuntimeGuestControlServiceOperation.self,
            from: try XCTUnwrap(repairDatastoreResponse.body)
        )
        let repairVMDisk = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(method: .post, path: "/platform/runtime-provider/disk/repair")))

        XCTAssertEqual(applyResponse.status, .accepted)
        XCTAssertEqual(applySettings.command, .applySettings)
        XCTAssertEqual(adminResponse.status, .accepted)
        XCTAssertEqual(applyAdminPassword.command, .applyAdminPassword)
        XCTAssertEqual(repairRuntime.result.stdout, "repair runtime")
        XCTAssertEqual(repairProxy.result.stdout, "repair proxy")
        XCTAssertEqual(repairDatastoreResponse.status, .accepted)
        XCTAssertEqual(repairDatastore.service, "datastore-repair")
        XCTAssertEqual(repairDatastore.command, .repairDatastore)
        XCTAssertEqual(repairDatastore.state, .completed)
        XCTAssertEqual(repairVMDisk.result.stdout, "repair vm disk")
    }

    @MainActor
    func testRouterPreservesFailedGuestDatastoreRepairOperation() async throws {
        let failure = RuntimeGuestControlOperationFailure(
            kind: "datastore-repair-failed",
            message: "redis append-only file repair failed"
        )
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler(
            datastoreRepairOperation: testDatastoreRepairOperation(
                state: .failed,
                failure: failure
            )
        ))

        let response = await router.route(.init(
            method: .post,
            path: "/runtime/maintenance/datastore/repair"
        ))
        let operation = try JSONDecoder().decode(
            RuntimeGuestControlServiceOperation.self,
            from: try XCTUnwrap(response.body)
        )

        XCTAssertEqual(response.status, .accepted)
        XCTAssertEqual(operation.service, "datastore-repair")
        XCTAssertEqual(operation.command, .repairDatastore)
        XCTAssertEqual(operation.state, .failed)
        XCTAssertEqual(operation.failure, failure)
    }

    @MainActor
    func testRouterDoesNotExposeWholeStackRuntimeServiceControl() async throws {
        let handler = StubRuntimeControlAPIReadHandler()
        let router = RuntimeControlAPIRouter(handler: handler)

        let start = await router.route(.init(method: .post, path: "/runtime/services/start"))
        let stop = await router.route(.init(method: .post, path: "/runtime/services/stop"))

        XCTAssertEqual(start.status, .notFound)
        XCTAssertEqual(stop.status, .notFound)
    }

    @MainActor
    func testRouterExecutesHostArtifactEndpointsThroughHandler() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())
        let bundleRequest = RuntimeUpdateBundleRequest(
            bundle: RuntimeControlFileReference(kind: .localPath, value: "/bundles/update.tar.gz")
        )
        let backupRequest = RuntimeBackupRequest(
            backup: RuntimeControlFileReference(kind: .localPath, value: "/backups/latest")
        )
        let exportRequest = RuntimeExportLogsRequest(
            destination: RuntimeControlFileReference(kind: .localPath, value: "/tmp/vitalserver-logs.zip")
        )
        let lease = RuntimeOperationLeaseDocument(
            operationId: "operation-1",
            operation: .applyBundle,
            ownerPID: 123,
            startedAt: "2026-07-09T00:00:00Z",
            heartbeatAt: "2026-07-09T00:00:00Z",
            expiresAt: "2026-07-09T00:05:00Z",
            message: "applying bundle"
        )
        let acquireLeaseRequest = RuntimeOperationLeaseAcquireRequest(document: lease)
        let heartbeatLeaseRequest = RuntimeOperationLeaseHeartbeatRequest(
            operationId: lease.operationId,
            heartbeatAt: "2026-07-09T00:01:00Z",
            expiresAt: "2026-07-09T00:06:00Z"
        )
        let releaseLeaseRequest = RuntimeOperationLeaseReleaseRequest(operationId: lease.operationId)

        let summary = try await decode(RuntimeUpdateBundleSummaryResponse.self, from: router.route(.init(
            method: .post,
            path: "/platform/update-bundles/summary",
            body: try JSONEncoder().encode(bundleRequest)
        )))
        let verify = try await decodeAccepted(PlatformWorkflowOperation.self, from: router.route(.init(
            method: .post,
            path: "/platform/update-bundles/verify",
            body: try JSONEncoder().encode(bundleRequest)
        )))
        let apply = try await decodeAccepted(PlatformWorkflowOperation.self, from: router.route(.init(
            method: .post,
            path: "/platform/update-bundles/apply",
            body: try JSONEncoder().encode(bundleRequest)
        )))
        let rollback = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .post,
            path: "/platform/backups/rollback",
            body: try JSONEncoder().encode(backupRequest)
        )))
        let deleteBackup = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .delete,
            path: "/platform/backups",
            body: try JSONEncoder().encode(backupRequest)
        )))
        let deleteUpdateBackup = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .delete,
            path: "/platform/backups/update",
            body: try JSONEncoder().encode(backupRequest)
        )))
        let deleteRuntimeDataBackup = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .delete,
            path: "/platform/backups/runtime-data",
            body: try JSONEncoder().encode(backupRequest)
        )))
        let export = try await decode(RuntimeLogExportResult.self, from: router.route(.init(
            method: .post,
            path: "/platform/logs/export",
            body: try JSONEncoder().encode(exportRequest)
        )))
        let acquireLease = try await decode(RuntimeOperationLeaseMutationResponse.self, from: router.route(.init(
            method: .post,
            path: "/platform/operations/lease/acquire",
            body: try JSONEncoder().encode(acquireLeaseRequest)
        )))
        let heartbeatLease = try await decode(RuntimeOperationLeaseMutationResponse.self, from: router.route(.init(
            method: .post,
            path: "/platform/operations/lease/heartbeat",
            body: try JSONEncoder().encode(heartbeatLeaseRequest)
        )))
        let releaseLease = try await decode(RuntimeOperationLeaseMutationResponse.self, from: router.route(.init(
            method: .post,
            path: "/platform/operations/lease/release",
            body: try JSONEncoder().encode(releaseLeaseRequest)
        )))

        XCTAssertEqual(summary.summary, "summary /bundles/update.tar.gz")
        XCTAssertEqual(verify.kind, .updateVerify)
        XCTAssertEqual(verify.state, .completed)
        XCTAssertNil(verify.failure)
        XCTAssertEqual(apply.kind, .updateApply)
        XCTAssertEqual(apply.state, .completed)
        XCTAssertNil(apply.failure)
        XCTAssertEqual(rollback.result.stdout, "rollback /backups/latest")
        XCTAssertEqual(deleteBackup.result.stdout, "delete /backups/latest")
        XCTAssertEqual(deleteUpdateBackup.result.stdout, "delete /backups/latest")
        XCTAssertEqual(deleteRuntimeDataBackup.result.stdout, "delete /backups/latest")
        XCTAssertEqual(export.destination.path, "/tmp/vitalserver-logs.zip")
        XCTAssertEqual(acquireLease, RuntimeOperationLeaseMutationResponse(operationId: "operation-1", state: .acquired))
        XCTAssertEqual(heartbeatLease, RuntimeOperationLeaseMutationResponse(operationId: "operation-1", state: .heartbeatRecorded))
        XCTAssertEqual(releaseLease, RuntimeOperationLeaseMutationResponse(operationId: "operation-1", state: .released))
    }

    @MainActor
    func testRouterCreatesRedisBackupThroughRuntimeControlClientHandler() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client, hostClient: client))

        let response = await router.route(.init(method: .post, path: "/platform/backups/redis"))
        let commandResponse = try decode(RuntimeControlCommandResponse.self, from: response)

        XCTAssertEqual(commandResponse.result.stdout, "redis backup created")
        XCTAssertEqual(client.createRedisBackupCount, 1)
    }

    @MainActor
    func testRouterControlsGuestServiceThroughRuntimeControlClientHandler() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client))

        let startResponse = await router.route(.init(
            method: .post,
            path: "/runtime/services/app/start"
        ))
        let stopResponse = await router.route(.init(
            method: .post,
            path: "/runtime/services/app/stop"
        ))
        let restartResponse = await router.route(.init(
            method: .post,
            path: "/runtime/services/app/restart"
        ))
        let startOperation = try decode(RuntimeGuestControlServiceOperation.self, from: startResponse)
        let stopOperation = try decode(RuntimeGuestControlServiceOperation.self, from: stopResponse)
        let restartOperation = try decode(RuntimeGuestControlServiceOperation.self, from: restartResponse)

        XCTAssertEqual(startOperation.operationId, "start-app")
        XCTAssertEqual(startOperation.command, .start)
        XCTAssertEqual(stopOperation.operationId, "stop-app")
        XCTAssertEqual(stopOperation.command, .stop)
        XCTAssertEqual(restartOperation.operationId, "restart-app")
        XCTAssertEqual(restartOperation.service, "app")
        XCTAssertEqual(restartOperation.command, .restart)
        XCTAssertEqual(restartOperation.state, .completed)
        XCTAssertEqual(client.startGuestServiceRequests, [RuntimeGuestServiceControlRequest(service: "app")])
        XCTAssertEqual(client.stopGuestServiceRequests, [RuntimeGuestServiceControlRequest(service: "app")])
        XCTAssertEqual(client.restartGuestServiceRequests, [RuntimeGuestServiceRestartRequest(service: "app")])
    }

    @MainActor
    func testRouterReadsGuestServicesThroughRuntimeControlClientHandler() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client))

        let stackStatus = try await decode(
            RuntimeGuestControlStackStatus.self,
            from: router.route(.init(method: .get, path: "/runtime/stack"))
        )
        let services = try await decode(
            RuntimeGuestControlServiceList.self,
            from: router.route(.init(method: .get, path: "/runtime/services"))
        )
        let status = try await decode(
            RuntimeGuestControlServiceStatus.self,
            from: router.route(.init(method: .get, path: "/runtime/services/recorder-ingress/status"))
        )
        let resource = try await decode(
            RuntimeGuestServiceResource.self,
            from: router.route(.init(method: .get, path: "/runtime/services/recorder-ingress/resource"))
        )

        XCTAssertEqual(stackStatus.state, "loaded")
        XCTAssertEqual(stackStatus.services.map(\.service), ["app", "recorder-ingress", "postgres"])
        XCTAssertEqual(services.services, ["app", "recorder-ingress", "postgres"])
        XCTAssertEqual(status.service, "recorder-ingress")
        XCTAssertEqual(status.state, "running")
        XCTAssertEqual(status.health, "healthy")
        XCTAssertEqual(resource.service, "recorder-ingress")
        XCTAssertEqual(resource.spec.desiredState, "running")
        XCTAssertEqual(resource.status.observedState, "running")
        XCTAssertEqual(resource.lastOperationId, "op-recorder-ingress")
        XCTAssertEqual(client.guestStackStatusCount, 1)
        XCTAssertEqual(client.guestServiceStatusRequests, ["recorder-ingress"])
        XCTAssertEqual(client.guestServiceResourceRequests, ["recorder-ingress"])
        XCTAssertEqual(client.listGuestServicesCount, 1)
    }

    @MainActor
    func testRouterServesBackupListsThroughRuntimeControlClientHandler() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client, hostClient: client))

        let backups = try await decode(
            [RuntimeBackup].self,
            from: router.route(.init(method: .get, path: "/platform/backups"))
        )
        let redisBackups = try await decode(
            [RuntimeBackup].self,
            from: router.route(.init(method: .get, path: "/platform/backups/redis"))
        )

        XCTAssertEqual(backups.map(\.path), ["/backups/rollback"])
        XCTAssertEqual(redisBackups.map(\.path), ["/platform/backups/runtime-data/redis/redis-1.tar.gz"])
        XCTAssertEqual(client.backupLatestPaths, ["latest-backup"])
        XCTAssertEqual(client.loadRedisBackupsCount, 1)
    }

    @MainActor
    func testRuntimeControlClientReadHandlerAdaptsClientReads() async throws {
        let client = FakeRuntimeControlClient()
        let handler = RuntimeControlClientAPIReadHandler(client: client)

        let platformCapabilities = try await handler.loadPlatformCapabilities()
        let runtimeCapabilities = try await handler.loadRuntimeCapabilities()
        let status = try await handler.loadPlatformState()
        let events = try await handler.loadRuntimeOperationEvents(query: RuntimeOperationEventQuery())
        let health = try await handler.loadHealthStatus()
        let release = try await handler.loadReleaseInfo()
        let installInfo = try await handler.loadInstallInfo()
        let observationSnapshot = try await handler.loadVitalDBObservationSnapshot()
        let recorders = try await handler.loadVitalDBRecorders()
        let relationships = try await handler.loadVitalDBRelationships()

        XCTAssertFalse(platformCapabilities.canOpenLocalFiles)
        XCTAssertEqual(runtimeCapabilities.capabilities, ["services:list", "lab:scenarios"])
        XCTAssertEqual(status.installedVersion, "status with 6 CPUs")
        XCTAssertEqual(events.events.map(\.id), ["runtime-operation-event-1"])
        XCTAssertEqual(health.installedVersion, "health with 6 CPUs")
        XCTAssertEqual(release.helperVersion, "0.2.0")
        XCTAssertEqual(installInfo.appBundlePath, "/Applications/VitalServer Helper.app")
        XCTAssertEqual(installInfo.packageIdentifier, "ai.tirosh.vitalserver.helper")
        XCTAssertEqual(installInfo.backupsPath, "/backups")
        XCTAssertEqual(installInfo.redisBackupsPath, "/platform/backups/runtime-data/redis")
        XCTAssertEqual(installInfo.runtimeDataBackupsPath, "/platform/backups/runtime-data/vitalserver-helper")
        XCTAssertEqual(observationSnapshot.state, .loaded)
        XCTAssertEqual(observationSnapshot.observation?.observedAt, "2026-05-25T00:00:00Z")
        XCTAssertEqual(recorders.updatedAt, "2026-05-25T00:00:00Z")
        XCTAssertEqual(relationships.assignments.map(\.assignmentID), ["bed-a:VR_A:2026-05-25T00:00:00Z"])
        XCTAssertEqual(client.loadSettingsCount, 2)
        XCTAssertEqual(client.statusSettings, [RuntimeSettings(cpuCount: 6, memoryGiB: 10)])
        XCTAssertEqual(client.healthSettings, [RuntimeSettings(cpuCount: 6, memoryGiB: 10)])
    }

    @MainActor
    func testRuntimeControlClientReadHandlerReportsMissingObservationExplicitly() async throws {
        let client = FakeRuntimeControlClient()
        client.vitalDBObservation = nil
        let handler = RuntimeControlClientAPIReadHandler(client: client)

        let snapshot = try await handler.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .unavailable)
        XCTAssertNil(snapshot.observation)
        XCTAssertNil(snapshot.readError)
    }

    @MainActor
    func testRuntimeControlClientReadHandlerPreservesObservationReadFailure() async throws {
        let client = FakeRuntimeControlClient()
        client.vitalDBObservationSnapshot = .failed(readError: "sqlite=permission denied")
        let handler = RuntimeControlClientAPIReadHandler(client: client)

        let snapshot = try await handler.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertNil(snapshot.observation)
        XCTAssertEqual(snapshot.readError, "sqlite=permission denied")
    }

    @MainActor
    func testRuntimeControlClientReadHandlerPropagatesBackupPermissionFailure() async throws {
        let client = FakeRuntimeControlClient()
        client.loadBackupsError = CocoaError(.fileReadNoPermission)
        let handler = RuntimeControlClientAPIReadHandler(client: client, hostClient: client)

        do {
            _ = try await handler.loadBackups()
            XCTFail("Expected loadBackups to throw")
        } catch {
            XCTAssertFileReadNoPermission(error)
        }
        XCTAssertEqual(client.backupLatestPaths, ["latest-backup"])
    }

    @MainActor
    func testRuntimeControlClientReadHandlerPropagatesExportLogsPermissionFailure() async throws {
        let client = FakeRuntimeControlClient()
        client.exportLogsError = CocoaError(.fileWriteNoPermission)
        let handler = RuntimeControlClientAPIReadHandler(client: client, hostClient: client)

        do {
            _ = try await handler.exportLogs(
                destination: RuntimeControlFileReference(kind: .localPath, value: "/tmp/vitalserver-logs.zip")
            )
            XCTFail("Expected exportLogs to throw")
        } catch {
            XCTAssertFileWriteNoPermission(error)
        }
    }

    @MainActor
    func testRuntimeControlClientReadHandlerAdaptsClientCommands() async throws {
        let client = FakeRuntimeControlClient()
        let handler = RuntimeControlClientAPIReadHandler(
            client: client,
            hostClient: client,
            guestMaintenanceClient: client
        )

        let repairRuntime = try await handler.repairRuntimeServices()
        let repairProxy = try await handler.repairProxy()
        let repairDatastore = try await handler.repairDatastore()
        let repairVMDisk = try await handler.repairVMDisk()
        let createRedisBackup = try await handler.createRedisBackup()
        let uninstall = try await handler.uninstallRuntime(mode: .clean)

        XCTAssertEqual(repairRuntime.result.stdout, "repair runtime")
        XCTAssertEqual(repairProxy.result.stdout, "repair proxy")
        XCTAssertEqual(repairDatastore.service, "datastore-repair")
        XCTAssertEqual(repairDatastore.command, .repairDatastore)
        XCTAssertEqual(repairDatastore.state, .completed)
        XCTAssertEqual(repairVMDisk.result.stdout, "repair vm disk")
        XCTAssertEqual(createRedisBackup.result.stdout, "redis backup created")
        XCTAssertEqual(uninstall.result.stdout, "clean uninstall")
    }

    @MainActor
    func testRuntimeControlClientReadHandlerAdaptsPlatformAffordances() async throws {
        let client = FakeRuntimeControlClient()
        let handler = RuntimeControlClientAPIReadHandler(client: client, hostClient: client)
        let bundle = RuntimeControlFileReference(kind: .localPath, value: "/bundles/update.tar.gz")
        let backup = RuntimeControlFileReference(kind: .localPath, value: "/backups/latest")
        let destination = RuntimeControlFileReference(kind: .localPath, value: "/tmp/vitalserver-logs.zip")
        let lease = RuntimeOperationLeaseDocument(
            operationId: "operation-1",
            operation: .applyBundle,
            ownerPID: 123,
            startedAt: "2026-07-09T00:00:00Z",
            heartbeatAt: "2026-07-09T00:00:00Z",
            expiresAt: "2026-07-09T00:05:00Z",
            message: "applying bundle"
        )

        let logText = try await handler.loadLogText(request: RuntimeLogTextRequest(
            source: .helperMessage,
            lineLimit: 25
        ))
        let backups = try await handler.loadBackups()
        let redisBackups = try await handler.loadRedisBackups()
        let runtimeDataBackups = try await handler.loadRuntimeDataBackups()
        let summary = try await handler.updateBundleSummary(bundle: bundle)
        let verify = try await handler.verifyUpdateBundle(bundle: bundle)
        let apply = try await handler.applyUpdateBundle(bundle: bundle)
        let rollback = try await handler.rollbackBackup(backup)
        let createRuntimeDataBackup = try await handler.createRuntimeDataBackup()
        let delete = try await handler.deleteBackup(backup)
        let export = try await handler.exportLogs(destination: destination)
        let acquireLease = try await handler.acquireOperationLease(.init(document: lease))
        let heartbeatLease = try await handler.heartbeatOperationLease(.init(
            operationId: lease.operationId,
            heartbeatAt: "2026-07-09T00:01:00Z",
            expiresAt: "2026-07-09T00:06:00Z"
        ))
        let releaseLease = try await handler.releaseOperationLease(.init(operationId: lease.operationId))

        XCTAssertEqual(logText.text, "log:helperMessage:25")
        XCTAssertEqual(backups.map(\.path), ["/backups/rollback"])
        XCTAssertEqual(redisBackups.map(\.path), ["/platform/backups/runtime-data/redis/redis-1.tar.gz"])
        XCTAssertEqual(runtimeDataBackups.map(\.path), ["/backups/vitalserver-helper/20260610T000000Z-manual"])
        XCTAssertEqual(summary.summary, "summary /bundles/update.tar.gz")
        XCTAssertEqual(verify.result.stdout, "verify /bundles/update.tar.gz")
        XCTAssertEqual(apply.result.stdout, "apply /bundles/update.tar.gz")
        XCTAssertEqual(rollback.result.stdout, "rollback /backups/latest")
        XCTAssertEqual(createRuntimeDataBackup.result.stdout, "runtime data backup created")
        XCTAssertEqual(delete.result.stdout, "delete /backups/latest")
        XCTAssertEqual(export.destination.path, "/tmp/vitalserver-logs.zip")
        XCTAssertEqual(acquireLease, RuntimeOperationLeaseMutationResponse(operationId: "operation-1", state: .acquired))
        XCTAssertEqual(heartbeatLease, RuntimeOperationLeaseMutationResponse(operationId: "operation-1", state: .heartbeatRecorded))
        XCTAssertEqual(releaseLease, RuntimeOperationLeaseMutationResponse(operationId: "operation-1", state: .released))
        XCTAssertEqual(client.backupLatestPaths, ["latest-backup"])
        XCTAssertEqual(client.loadRedisBackupsCount, 1)
        XCTAssertEqual(client.loadRuntimeDataBackupsCount, 1)
        XCTAssertEqual(client.createRuntimeDataBackupCount, 1)
        XCTAssertEqual(client.acquiredOperationLeases, [lease])
        XCTAssertEqual(client.heartbeatOperationLeaseRequests.map(\.operationId), ["operation-1"])
        XCTAssertEqual(client.releasedOperationLeaseIDs, ["operation-1"])
    }

    @MainActor
    func testRuntimeControlClientReadHandlerDoesNotTranslateGuestDatastoreRepairThroughHostClient() async throws {
        let client = FakeRuntimeControlClient()
        let handler = RuntimeControlClientAPIReadHandler(
            client: client,
            hostClient: client
        )

        try await XCTAssertThrowsPlatformAffordanceUnavailable(
            "repairDatastore without a Guest maintenance operation client"
        ) {
            _ = try await handler.repairDatastore()
        }
    }

    @MainActor
    func testRuntimeControlClientReadHandlerRequiresPlatformAffordanceClientForHostOperations() async throws {
        let handler = RuntimeControlClientAPIReadHandler(client: FakeRuntimeControlClient())
        let bundle = RuntimeControlFileReference(kind: .localPath, value: "/bundles/update.tar.gz")
        let backup = RuntimeControlFileReference(kind: .localPath, value: "/backups/latest")
        let destination = RuntimeControlFileReference(kind: .localPath, value: "/tmp/vitalserver-logs.zip")
        let lease = RuntimeOperationLeaseDocument(
            operationId: "operation-1",
            operation: .applyBundle,
            ownerPID: 123,
            startedAt: "2026-07-09T00:00:00Z",
            heartbeatAt: "2026-07-09T00:00:00Z",
            expiresAt: "2026-07-09T00:05:00Z",
            message: "applying bundle"
        )

        let operations: [(String, () async throws -> Void)] = [
            ("loadLogText", {
                _ = try await handler.loadLogText(request: RuntimeLogTextRequest(
                    source: .helperMessage,
                    lineLimit: 25
                ))
            }),
            ("loadBackups", { _ = try await handler.loadBackups() }),
            ("loadRedisBackups", { _ = try await handler.loadRedisBackups() }),
            ("loadRuntimeDataBackups", { _ = try await handler.loadRuntimeDataBackups() }),
            ("updateBundleSummary", { _ = try await handler.updateBundleSummary(bundle: bundle) }),
            ("verifyUpdateBundle", { _ = try await handler.verifyUpdateBundle(bundle: bundle) }),
            ("applyUpdateBundle", { _ = try await handler.applyUpdateBundle(bundle: bundle) }),
            ("rollbackBackup", { _ = try await handler.rollbackBackup(backup) }),
            ("repairRuntimeServices", { _ = try await handler.repairRuntimeServices() }),
            ("repairProxy", { _ = try await handler.repairProxy() }),
            ("repairDatastore", { _ = try await handler.repairDatastore() }),
            ("repairVMDisk", { _ = try await handler.repairVMDisk() }),
            ("createRedisBackup", { _ = try await handler.createRedisBackup() }),
            ("createRuntimeDataBackup", { _ = try await handler.createRuntimeDataBackup() }),
            ("deleteBackup", { _ = try await handler.deleteBackup(backup) }),
            ("exportLogs", { _ = try await handler.exportLogs(destination: destination) }),
            ("acquireOperationLease", { _ = try await handler.acquireOperationLease(.init(document: lease)) }),
            ("heartbeatOperationLease", {
                _ = try await handler.heartbeatOperationLease(.init(
                    operationId: lease.operationId,
                    heartbeatAt: "2026-07-09T00:01:00Z",
                    expiresAt: "2026-07-09T00:06:00Z"
                ))
            }),
            ("releaseOperationLease", {
                _ = try await handler.releaseOperationLease(.init(operationId: lease.operationId))
            }),
        ]

        for (name, operation) in operations {
            try await XCTAssertThrowsPlatformAffordanceUnavailable(name, operation)
        }
    }

    @MainActor
    func testRuntimeControlClientReadHandlerRejectsUnsupportedFileReferencesForLocalHostOperations() async throws {
        let client = FakeRuntimeControlClient()
        let handler = RuntimeControlClientAPIReadHandler(client: client, hostClient: client)
        let remote = RuntimeControlFileReference(kind: .remoteURL, value: "https://example.invalid/update.tar.gz")

        let operations: [(String, () async throws -> Void)] = [
            ("updateBundleSummary", { _ = try await handler.updateBundleSummary(bundle: remote) }),
            ("verifyUpdateBundle", { _ = try await handler.verifyUpdateBundle(bundle: remote) }),
            ("applyUpdateBundle", { _ = try await handler.applyUpdateBundle(bundle: remote) }),
            ("rollbackBackup", { _ = try await handler.rollbackBackup(remote) }),
            ("deleteBackup", { _ = try await handler.deleteBackup(remote) }),
            ("exportLogs", { _ = try await handler.exportLogs(destination: remote) }),
        ]

        for (name, operation) in operations {
            try await XCTAssertThrowsUnsupportedFileReference(name, .remoteURL, operation)
        }
    }

    func testRuntimeControlClientReadHandlerErrorsDescribeOperatorVisibleFailures() {
        XCTAssertEqual(
            RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable.localizedDescription,
            "Host affordance client is unavailable."
        )
        XCTAssertEqual(
            RuntimeControlAPIReadHandlerError.unsupportedFileReference(RuntimeControlFileReferenceKind.remoteURL.rawValue).localizedDescription,
            "File reference kind remoteURL is not supported by this local Runtime Control handler."
        )
    }

    @MainActor
    func testRuntimeEventsEndpointAcceptsQueryFilters() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client))

        let response = await router.route(.init(
            method: .get,
            path: "/runtime/events?limit=1&type=operation-completed&since=2026-05-24T09%3A01%3A00%2B09%3A00"
        ))
        let history = try decode(RuntimeOperationEventHistory.self, from: response)

        XCTAssertEqual(history.events.map(\.id), ["runtime-operation-event-1"])
        XCTAssertEqual(client.runtimeOperationEventQueries, [
            RuntimeOperationEventQuery(
                limit: 1,
                eventType: .completed,
                since: "2026-05-24T09:01:00+09:00"
            ),
        ])
    }

    @MainActor
    func testRuntimeEventsEndpointForwardsOpaqueCursor() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client))
        let wireCursor = "guest+ledger/token=v2"

        let response = await router.route(.init(
            method: .get,
            path: "/runtime/events?limit=2&cursor=guest%2Bledger%2Ftoken%3Dv2"
        ))
        let history = try decode(RuntimeOperationEventHistory.self, from: response)

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(history.nextCursor, wireCursor)
        XCTAssertEqual(client.runtimeOperationEventQueries, [
            RuntimeOperationEventQuery(limit: 2, cursor: wireCursor),
        ])
    }

    @MainActor
    func testRuntimeEventsEndpointPreservesGuestQueryRejectionAsBadRequest() async throws {
        let client = FakeRuntimeControlClient()
        client.runtimeOperationEventError = RuntimeGuestOperationEventQueryRejectedError(
            detail: "runtime event history cursor is invalid"
        )
        let router = RuntimeControlAPIRouter(
            handler: RuntimeControlClientAPIReadHandler(client: client)
        )

        let response = await router.route(
            .init(method: .get, path: "/runtime/events?cursor=guest-ledger-token")
        )
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertEqual(error.message, "runtime event history cursor is invalid")
    }

    @MainActor
    func testRuntimeEventsEndpointPreservesGuestLedgerFailureAsServiceUnavailable() async throws {
        let client = FakeRuntimeControlClient()
        client.runtimeOperationEventError = RuntimeGuestOperationEventHistoryUnavailableError(
            detail: "Guest operation event ledger is unavailable"
        )
        let router = RuntimeControlAPIRouter(
            handler: RuntimeControlClientAPIReadHandler(client: client)
        )

        let response = await router.route(.init(method: .get, path: "/runtime/events"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .serviceUnavailable)
        XCTAssertEqual(error.code, .guestControlUnavailable)
        XCTAssertEqual(error.message, "Guest operation event ledger is unavailable")
    }

    @MainActor
    func testRuntimeEventsEndpointRejectsInvalidLimit() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/runtime/events?limit=zero"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
    }

    @MainActor
    func testRuntimeEventsEndpointRejectsLimitAboveGuestContractMaximum() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/runtime/events?limit=501"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
    }

    @MainActor
    func testRuntimeEventsEndpointRejectsDuplicateQueryParameters() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/runtime/events?limit=1&limit=2"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertEqual(error.message, "Duplicate query parameter: limit")
    }

    @MainActor
    func testRuntimeEventsEndpointRejectsMissingQueryParameterValue() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/runtime/events?limit"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertEqual(error.message, "Missing query parameter value: limit")
    }

    @MainActor
    func testRuntimeEventsEndpointRejectsHostDiagnosticsEventType() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/runtime/events?type=watchdog-skipped"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertEqual(error.message, "Invalid runtime event type: watchdog-skipped")
    }

    @MainActor
    func testRuntimeEventsEndpointRejectsMalformedQueryEncoding() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/runtime/events?limit=%ZZ"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertEqual(error.message, "Invalid query string: limit=%ZZ")
    }

    func testRuntimeLogQueryIgnoresObsoleteHelperMessageParameter() throws {
        let missing = try RuntimeControlHTTPRequest(
            method: .get,
            path: "/platform/logs/stream?source=command&lineLimit=5"
        ).runtimeLogTextRequest()
        let explicitEmpty = try RuntimeControlHTTPRequest(
            method: .get,
            path: "/platform/logs/stream?source=command&lineLimit=5&helperMessage="
        ).runtimeLogTextRequest()

        XCTAssertEqual(missing, RuntimeLogTextRequest(source: .command, lineLimit: 5))
        XCTAssertEqual(explicitEmpty, missing)
    }

    func testRuntimeLogQueryRejectsMalformedPercentEncoding() {
        XCTAssertThrowsError(try RuntimeControlHTTPRequest(
            method: .get,
            path: "/platform/logs/stream?source=%ZZ"
        ).runtimeLogTextRequest()) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPQueryError, .invalidQueryString("source=%ZZ"))
        }
    }

    @MainActor
    func testRouterReportsRequestBodyDecodeFailureDetails() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(
            method: .put,
            path: "/runtime/settings",
            body: Data("{".utf8)
        ))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertTrue(error.message.contains("RuntimeApplyProductSettingsRequest"))
        XCTAssertTrue(error.message.contains("Decode failed"))
    }

    @MainActor
    func testRouterMapsPlatformAffordanceUnavailableToTypedHTTPError() async throws {
        let router = RuntimeControlAPIRouter(
            handler: RuntimeControlClientAPIReadHandler(client: FakeRuntimeControlClient())
        )
        let response = await router.route(.init(
            method: .post,
            path: "/platform/logs/read",
            body: try JSONEncoder().encode(RuntimeLogTextRequest(source: .command, lineLimit: 10))
        ))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .notImplemented)
        XCTAssertEqual(error.code, .platformAffordanceUnavailable)
        XCTAssertEqual(error.message, RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable.localizedDescription)
    }

    @MainActor
    func testRouterMapsUnsupportedFileReferenceToBadRequest() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(
            handler: RuntimeControlClientAPIReadHandler(client: client, hostClient: client)
        )
        let remote = RuntimeControlFileReference(kind: .remoteURL, value: "https://example.invalid/update.tar.gz")
        let response = await router.route(.init(
            method: .post,
            path: "/platform/update-bundles/summary",
            body: try JSONEncoder().encode(RuntimeUpdateBundleRequest(bundle: remote))
        ))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertEqual(
            error.message,
            RuntimeControlAPIReadHandlerError.unsupportedFileReference(remote.kind.rawValue).localizedDescription
        )
    }

    @MainActor
    func testRouterCanUseRuntimeControlClientReadHandler() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client))

        let response = await router.route(.init(method: .get, path: "/platform"))
        let status = try decode(PlatformState.self, from: response)

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(status.installedVersion, "status with 6 CPUs")
        XCTAssertEqual(client.loadSettingsCount, 1)
    }

    @MainActor
    func testRouterRejectsMissingOrInvalidTokenWhenAuthorizationIsConfigured() async throws {
        let router = RuntimeControlAPIRouter(
            handler: StubRuntimeControlAPIReadHandler(),
            authorization: RuntimeControlAPIAuthorization(token: "dev-token")
        )

        let missingTokenResponse = await router.route(.init(method: .get, path: "/platform"))
        let invalidTokenResponse = await router.route(.init(
            method: .get,
            path: "/platform",
            headers: ["X-Runtime-Control-Token": "wrong"]
        ))

        XCTAssertEqual(missingTokenResponse.status, .unauthorized)
        XCTAssertEqual(try decodeError(from: missingTokenResponse).code, .unauthorized)
        XCTAssertEqual(invalidTokenResponse.status, .unauthorized)
        XCTAssertEqual(try decodeError(from: invalidTokenResponse).code, .unauthorized)
    }

    @MainActor
    func testRouterAcceptsConfiguredTokenHeaderCaseInsensitively() async throws {
        let router = RuntimeControlAPIRouter(
            handler: StubRuntimeControlAPIReadHandler(),
            authorization: RuntimeControlAPIAuthorization(token: "dev-token")
        )

        let response = await router.route(.init(
            method: .get,
            path: "/platform",
            headers: ["x-runtime-control-token": "dev-token"]
        ))

        XCTAssertEqual(response.status, .ok)
    }

    func testWireCodecDecodesHTTPRequests() throws {
        let rawRequest = [
            "GET /platform?refresh=false HTTP/1.1",
            "Host: 127.0.0.1",
            "X-Runtime-Control-Token: dev-token",
            "",
            "",
        ].joined(separator: "\r\n")

        let request = try RuntimeControlHTTPWireCodec.decodeRequest(Data(rawRequest.utf8))

        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/platform?refresh=false")
        XCTAssertEqual(request.headerValue(named: "x-runtime-control-token"), "dev-token")
        XCTAssertNil(request.body)
    }

    func testWireCodecDecodesRequestBodyByContentLength() throws {
        let rawRequest = [
            "PUT /runtime/settings HTTP/1.1",
            "Content-Type: application/json",
            "Content-Length: 7",
            "",
            "{\"a\":1}ignored",
        ].joined(separator: "\r\n")

        let request = try RuntimeControlHTTPWireCodec.decodeRequest(Data(rawRequest.utf8))

        XCTAssertEqual(request.method, .put)
        XCTAssertEqual(request.path, "/runtime/settings")
        XCTAssertEqual(request.body, Data("{\"a\":1}".utf8))
    }

    func testWireCodecDecodesRequestBodyByContentLengthBytes() throws {
        let body = Data("{\"message\":\"준비\"}".utf8)
        var rawRequest = Data([
            "POST /runtime/events HTTP/1.1",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "",
            "",
        ].joined(separator: "\r\n").utf8)
        rawRequest.append(body)
        rawRequest.append(Data("ignored".utf8))

        let request = try RuntimeControlHTTPWireCodec.decodeRequest(rawRequest)

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/runtime/events")
        XCTAssertEqual(request.body, body)
    }

    func testWireCodecDecodesRequestBodyWithoutContentLength() throws {
        let rawRequest = [
            "POST /runtime/events HTTP/1.1",
            "Content-Type: application/json",
            "",
            "{\"event\":\"ready\"}",
        ].joined(separator: "\r\n")

        let request = try RuntimeControlHTTPWireCodec.decodeRequest(Data(rawRequest.utf8))

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/runtime/events")
        XCTAssertEqual(request.body, Data("{\"event\":\"ready\"}".utf8))
    }

    func testWireCodecReportsIncompleteRequestsBeforeDecoding() throws {
        let partialHeader = Data("GET /platform HTTP/1.1\r\nHost: 127.0.0.1".utf8)
        XCTAssertFalse(try RuntimeControlHTTPWireCodec.requestIsComplete(partialHeader))

        let partialBody = [
            "PUT /runtime/settings HTTP/1.1",
            "Content-Length: 7",
            "",
            "{\"a\"",
        ].joined(separator: "\r\n")
        XCTAssertFalse(try RuntimeControlHTTPWireCodec.requestIsComplete(Data(partialBody.utf8)))

        let completeBody = [
            "PUT /runtime/settings HTTP/1.1",
            "Content-Length: 7",
            "",
            "{\"a\":1}",
        ].joined(separator: "\r\n")
        XCTAssertTrue(try RuntimeControlHTTPWireCodec.requestIsComplete(Data(completeBody.utf8)))
    }

    func testWireCodecWaitsForPartialMultibyteBodyInsteadOfRejectingRequest() throws {
        let body = Data("{\"message\":\"준비\"}".utf8)
        let header = Data([
            "POST /runtime/events HTTP/1.1",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "",
            "",
        ].joined(separator: "\r\n").utf8)
        var partialRequest = header
        partialRequest.append(body.prefix(body.count - 1))
        var completeRequest = header
        completeRequest.append(body)

        XCTAssertFalse(try RuntimeControlHTTPWireCodec.requestIsComplete(partialRequest))
        XCTAssertTrue(try RuntimeControlHTTPWireCodec.requestIsComplete(completeRequest))
    }

    func testWireCodecRejectsMalformedCompletionInputs() {
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.requestIsComplete(Data([0xFF]))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .invalidRequest)
        }

        let malformedHeader = [
            "GET /platform HTTP/1.1",
            "Malformed-Header",
            "",
            "",
        ].joined(separator: "\r\n")
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.requestIsComplete(Data(malformedHeader.utf8))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .invalidRequest)
        }

        let negativeLength = [
            "PUT /runtime/settings HTTP/1.1",
            "Content-Length: -1",
            "",
            "{}",
        ].joined(separator: "\r\n")
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.requestIsComplete(Data(negativeLength.utf8))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .invalidContentLength("-1"))
        }
    }

    func testWireCodecRejectsMalformedDecodeInputs() {
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.decodeRequest(Data([0xFF]))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .invalidRequest)
        }
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.decodeRequest(Data("GET /platform".utf8))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .invalidRequest)
        }
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.decodeRequest(Data("GET\r\n\r\n".utf8))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .invalidRequest)
        }
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.decodeRequest(Data("TRACE /platform HTTP/1.1\r\n\r\n".utf8))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .unsupportedMethod("TRACE"))
        }
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.decodeRequest(Data("GET /platform HTTP/1.1\r\nBadHeader\r\n\r\n".utf8))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .invalidRequest)
        }

        let invalidLength = [
            "PUT /runtime/settings HTTP/1.1",
            "Content-Length: abc",
            "",
            "{}",
        ].joined(separator: "\r\n")
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.decodeRequest(Data(invalidLength.utf8))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .invalidContentLength("abc"))
        }
    }

    func testWireCodecEncodesHTTPResponses() throws {
        let response = RuntimeControlHTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: Data("{\"ok\":true}".utf8)
        )

        let encoded = try XCTUnwrap(String(
            data: RuntimeControlHTTPWireCodec.encodeResponse(response),
            encoding: .utf8
        ))

        XCTAssertTrue(encoded.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(encoded.contains("Content-Length: 11\r\n"))
        XCTAssertTrue(encoded.contains("Content-Type: application/json\r\n"))
        XCTAssertTrue(encoded.hasSuffix("\r\n{\"ok\":true}"))
    }

    func testWireCodecEncodesStreamHeadersAndStatusPhrases() throws {
        let streamHeader = try XCTUnwrap(String(
            data: RuntimeControlHTTPWireCodec.encodeStreamHeader(
                status: .notFound,
                headers: ["Content-Type": "text/event-stream"]
            ),
            encoding: .utf8
        ))

        XCTAssertTrue(streamHeader.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        XCTAssertTrue(streamHeader.contains("Connection: keep-alive\r\n"))
        XCTAssertTrue(streamHeader.contains("Content-Type: text/event-stream\r\n"))
        XCTAssertTrue(streamHeader.hasSuffix("\r\n\r\n"))

        let statuses: [(RuntimeControlHTTPStatus, String)] = [
            (.badRequest, "400 Bad Request"),
            (.methodNotAllowed, "405 Method Not Allowed"),
            (.conflict, "409 Conflict"),
            (.notImplemented, "501 Not Implemented"),
            (.internalServerError, "500 Internal Server Error"),
        ]
        for (status, phrase) in statuses {
            let encoded = try XCTUnwrap(String(
                data: RuntimeControlHTTPWireCodec.encodeResponse(.init(status: status)),
                encoding: .utf8
            ))

            XCTAssertTrue(encoded.hasPrefix("HTTP/1.1 \(phrase)\r\n"))
            XCTAssertTrue(encoded.contains("Content-Length: 0\r\n"))
            XCTAssertTrue(encoded.contains("Connection: close\r\n"))
        }
    }

    func testWireCodecBuildsBadRequestResponses() throws {
        let response = RuntimeControlHTTPWireCodec.badRequestResponse(message: "Invalid HTTP request.")

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(response.headers["Content-Type"], "application/json")

        let body = try XCTUnwrap(response.body)
        let error = try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: body)
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertEqual(error.message, "Invalid HTTP request.")
    }

    func testWireCodecBadRequestResponsesPreserveDecodeFailureReason() throws {
        let invalidContentLength = RuntimeControlHTTPWireCodec.badRequestResponse(
            for: RuntimeControlHTTPWireCodecError.invalidContentLength("abc")
        )
        let unsupportedMethod = RuntimeControlHTTPWireCodec.badRequestResponse(
            for: RuntimeControlHTTPWireCodecError.unsupportedMethod("TRACE")
        )

        let invalidLengthBody = try XCTUnwrap(invalidContentLength.body)
        let unsupportedMethodBody = try XCTUnwrap(unsupportedMethod.body)
        let invalidLengthError = try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: invalidLengthBody)
        let unsupportedMethodError = try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: unsupportedMethodBody)

        XCTAssertEqual(invalidLengthError.code, .badRequest)
        XCTAssertEqual(invalidLengthError.message, "Invalid Content-Length header: abc.")
        XCTAssertEqual(unsupportedMethodError.code, .badRequest)
        XCTAssertEqual(unsupportedMethodError.message, "Unsupported HTTP method: TRACE.")
    }

    func testDevConsoleDocumentServesBrowserTestPage() throws {
        let response = try XCTUnwrap(RuntimeControlDevConsoleDocument.response(for: .init(
            method: .get,
            path: "/dev/runtime-control"
        )))
        let html = try XCTUnwrap(String(data: try XCTUnwrap(response.body), encoding: .utf8))

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "text/html; charset=utf-8")
        XCTAssertTrue(html.contains("Runtime Control API Console"))
        XCTAssertFalse(html.contains("/runtime/overview"))
        XCTAssertTrue(html.contains("/platform/stream"))
        XCTAssertFalse(html.contains("/runtime/events/stream"))
        XCTAssertTrue(html.contains("/runtime/vitaldb/recorders"))
        XCTAssertTrue(html.contains("/platform/logs/stream"))
        XCTAssertTrue(html.contains(#"<option value="containers" selected>containers</option>"#))
        XCTAssertFalse(html.contains("vitalDBObservation || status.vitalDBObservation"))
        XCTAssertFalse(html.contains("overview.vitalDBObservation || (overview.status && overview.status.vitalDBObservation)"))
    }

    @MainActor
    func testLocalHTTPServerServesRuntimeStatusOverLoopback() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token")
        defer {
            server.stop()
        }

        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform")))
        request.setValue("dev-token", forHTTPHeaderField: "X-Runtime-Control-Token")

        let (data, httpResponse) = try await Self.fetchWithRetry(request)
        let status = try JSONDecoder().decode(PlatformState.self, from: data)

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(status.platformHealth, .healthy)
        XCTAssertEqual(status.installedVersion, "1.2.3")
    }

    @MainActor
    func testRuntimeControlE2ESmokeServesCoreReadEndpointsOverHTTP() async throws {
        let token = "dev-token"
        let (server, port) = try await makeStartedServer(token: token)
        defer {
            server.stop()
        }

        let platformCapabilities = try await Self.fetchRuntimeJSON(
            PlatformCapabilities.self,
            port: port,
            path: "/platform/capabilities",
            token: token
        )
        let runtimeCapabilities = try await Self.fetchRuntimeJSON(
            RuntimeCapabilities.self,
            port: port,
            path: "/runtime/capabilities",
            token: token
        )
        let status = try await Self.fetchRuntimeJSON(
            PlatformState.self,
            port: port,
            path: "/platform",
            token: token
        )
        let settings = try await Self.fetchRuntimeJSON(
            RuntimeProductSettingsRead.self,
            port: port,
            path: "/runtime/settings",
            token: token
        )
        let events = try await Self.fetchRuntimeJSON(
            RuntimeOperationEventHistory.self,
            port: port,
            path: "/runtime/events?limit=5",
            token: token
        )

        XCTAssertTrue(platformCapabilities.canExportLogs)
        XCTAssertTrue(platformCapabilities.canStreamLogs)
        XCTAssertTrue(runtimeCapabilities.capabilities.contains("services:list"))
        XCTAssertEqual(status.platformHealth, .healthy)
        XCTAssertEqual(status.installedVersion, "1.2.3")
        XCTAssertEqual(settings.state, .loaded)
        XCTAssertEqual(settings.settings?.publicHost, "vitalserver.local")
        XCTAssertEqual(events.events.map(\.id), ["runtime-operation-event-1"])

        let missingTokenRequest = URLRequest(
            url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform"))
        )
        let (missingTokenData, missingTokenHTTPResponse) = try await Self.fetchWithRetry(missingTokenRequest)
        let missingTokenError = try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: missingTokenData)

        XCTAssertEqual(missingTokenHTTPResponse.statusCode, 401)
        XCTAssertEqual(missingTokenError.code, .unauthorized)
    }

    @MainActor
    func testLocalHTTPServerReportsAsyncListenFailure() async throws {
        let token = "dev-token"
        let (server, port) = try await makeStartedServer(token: token)
        defer {
            server.stop()
        }

        let failed = expectation(description: "server listen failure")
        let conflict = RuntimeControlLocalHTTPServer(
            configuration: RuntimeControlLocalHTTPServerConfiguration(
                port: port,
                bindsToLoopbackOnly: true
            ),
            router: RuntimeControlAPIRouter(
                handler: StubRuntimeControlAPIReadHandler(),
                authorization: RuntimeControlAPIAuthorization(token: token)
            ),
            stateHandler: { state in
                if case .failed = state {
                    failed.fulfill()
                }
            }
        )
        defer {
            conflict.stop()
        }

        do {
            try conflict.start()
        } catch {
            return
        }

        await fulfillment(of: [failed], timeout: 3)
    }

    @MainActor
    func testLocalHTTPServerAllowsLoopbackCORSPreflight() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token")
        defer {
            server.stop()
        }

        let origin = "http://127.0.0.1:5174"
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform")))
        request.httpMethod = "OPTIONS"
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("GET", forHTTPHeaderField: "Access-Control-Request-Method")
        request.setValue("X-Runtime-Control-Token", forHTTPHeaderField: "Access-Control-Request-Headers")

        let (_, httpResponse) = try await Self.fetchWithRetry(request)

        XCTAssertEqual(httpResponse.statusCode, 204)
        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), origin)
        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Headers"), "Accept, Content-Type, X-Runtime-Control-Token")
        XCTAssertTrue(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Methods")?.contains("OPTIONS") == true)
    }

    @MainActor
    func testLocalHTTPServerRejectsPrivateNetworkCORSPreflight() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token")
        defer {
            server.stop()
        }

        let origin = "http://192.168.0.42:5174"
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform")))
        request.httpMethod = "OPTIONS"
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("GET", forHTTPHeaderField: "Access-Control-Request-Method")
        request.setValue("X-Runtime-Control-Token", forHTTPHeaderField: "Access-Control-Request-Headers")

        let (_, httpResponse) = try await Self.fetchWithRetry(request)

        XCTAssertEqual(httpResponse.statusCode, 204)
        XCTAssertNil(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin"))
    }

    @MainActor
    func testLocalHTTPServerAddsCORSHeadersToLoopbackAPIResponses() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token")
        defer {
            server.stop()
        }

        let origin = "http://localhost:5174"
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform")))
        request.setValue("dev-token", forHTTPHeaderField: "X-Runtime-Control-Token")
        request.setValue(origin, forHTTPHeaderField: "Origin")

        let (_, httpResponse) = try await Self.fetchWithRetry(request)

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), origin)
        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Vary"), "Origin")
    }

    @MainActor
    func testLocalHTTPServerDoesNotAllowUntrustedCORSOrigins() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token")
        defer {
            server.stop()
        }

        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform")))
        request.httpMethod = "OPTIONS"
        request.setValue("https://example.com", forHTTPHeaderField: "Origin")
        request.setValue("GET", forHTTPHeaderField: "Access-Control-Request-Method")

        let (_, httpResponse) = try await Self.fetchWithRetry(request)

        XCTAssertEqual(httpResponse.statusCode, 204)
        XCTAssertNil(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin"))
    }

    @MainActor
    func testLocalHTTPServerRejectsDevConsoleWhenDisabled() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token")
        defer {
            server.stop()
        }

        let request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/dev/runtime-control")))

        let (data, httpResponse) = try await Self.fetchWithRetry(request)
        let error = try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: data)

        XCTAssertEqual(httpResponse.statusCode, 401)
        XCTAssertEqual(error.code, .unauthorized)
    }

    @MainActor
    func testLocalHTTPServerServesDevConsoleOverLoopbackWithoutTokenWhenEnabled() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token", servesDevConsole: true)
        defer {
            server.stop()
        }

        let request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/dev/runtime-control")))

        let (data, httpResponse) = try await Self.fetchWithRetry(request)
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Content-Type"), "text/html; charset=utf-8")
        XCTAssertTrue(html.contains("Runtime Control API Console"))
    }

    @MainActor
    func testLocalHTTPServerRejectsMissingTokenOverLoopback() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token")
        defer {
            server.stop()
        }

        let request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform")))

        let (data, httpResponse) = try await Self.fetchWithRetry(request)
        let error = try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: data)

        XCTAssertEqual(httpResponse.statusCode, 401)
        XCTAssertEqual(error.code, .unauthorized)
    }

    @MainActor
    func testLocalHTTPServerUsesSameOriginBrowserSessionWithoutStaticPWAToken() async throws {
        let session = RuntimeControlLoopbackBrowserSession(token: "browser-session-token")
        let (server, port) = try await makeStartedServer(
            token: "native-owner-token",
            browserSession: session
        )
        defer {
            server.stop()
        }

        var bootstrap = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(RuntimeControlLoopbackBrowserSession.bootstrapPath)")))
        bootstrap.httpMethod = "POST"
        bootstrap.setValue("http://127.0.0.1:\(port)", forHTTPHeaderField: "Origin")
        let (bootstrapData, bootstrapResponse) = try await Self.fetchWithRetry(bootstrap)

        XCTAssertEqual(bootstrapResponse.statusCode, 204)
        XCTAssertTrue(bootstrapData.isEmpty)
        let setCookie = try XCTUnwrap(bootstrapResponse.value(forHTTPHeaderField: "Set-Cookie"))
        XCTAssertTrue(setCookie.contains("\(RuntimeControlLoopbackBrowserSession.cookieName)=browser-session-token"))
        XCTAssertTrue(setCookie.contains("HttpOnly"))
        XCTAssertTrue(setCookie.contains("SameSite=Strict"))
        XCTAssertFalse(setCookie.contains("native-owner-token"))

        var read = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform")))
        read.setValue("\(RuntimeControlLoopbackBrowserSession.cookieName)=browser-session-token", forHTTPHeaderField: "Cookie")
        let (_, readResponse) = try await Self.fetchWithRetry(read)
        XCTAssertEqual(readResponse.statusCode, 200)

        var crossOriginMutation = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform/uninstall")))
        crossOriginMutation.httpMethod = "POST"
        crossOriginMutation.setValue("\(RuntimeControlLoopbackBrowserSession.cookieName)=browser-session-token", forHTTPHeaderField: "Cookie")
        crossOriginMutation.setValue("http://127.0.0.1:5174", forHTTPHeaderField: "Origin")
        let (mutationData, mutationResponse) = try await Self.fetchWithRetry(crossOriginMutation)
        let mutationError = try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: mutationData)
        XCTAssertEqual(mutationResponse.statusCode, 401)
        XCTAssertEqual(mutationError.code, .unauthorized)
    }

    @MainActor
    func testLocalHTTPServerRejectsCrossOriginBrowserSessionBootstrap() async throws {
        let session = RuntimeControlLoopbackBrowserSession(token: "browser-session-token")
        let (server, port) = try await makeStartedServer(
            token: "native-owner-token",
            browserSession: session
        )
        defer {
            server.stop()
        }

        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(RuntimeControlLoopbackBrowserSession.bootstrapPath)")))
        request.httpMethod = "POST"
        request.setValue("https://attacker.example", forHTTPHeaderField: "Origin")
        let (data, response) = try await Self.fetchWithRetry(request)
        let error = try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: data)

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertNil(response.value(forHTTPHeaderField: "Set-Cookie"))
        XCTAssertEqual(error.code, .unauthorized)
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from response: RuntimeControlHTTPResponse
    ) throws -> T {
        XCTAssertEqual(response.status, .ok)
        return try JSONDecoder().decode(type, from: try XCTUnwrap(response.body))
    }

    private func decodeAccepted<T: Decodable>(
        _ type: T.Type,
        from response: RuntimeControlHTTPResponse
    ) throws -> T {
        XCTAssertEqual(response.status, .accepted)
        return try JSONDecoder().decode(type, from: try XCTUnwrap(response.body))
    }

    private func decodeError(from response: RuntimeControlHTTPResponse) throws -> RuntimeControlErrorResponse {
        try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: try XCTUnwrap(response.body))
    }

    @MainActor
    private func streamResponse(from result: RuntimeControlHTTPRouteResult) throws -> RuntimeControlHTTPStreamResponse {
        switch result {
        case .stream(let stream):
            return stream
        case .response:
            XCTFail("Expected stream response")
            throw RuntimeControlAPIEndpointTestError.expectedStream
        }
    }

    @MainActor
    private func firstStreamEvent(_ stream: RuntimeControlHTTPStreamResponse) async throws -> RuntimeControlServerSentEvent {
        var iterator = stream.events.makeAsyncIterator()
        guard let event = try await iterator.next() else {
            XCTFail("Expected stream event")
            throw RuntimeControlAPIEndpointTestError.expectedStream
        }
        return event
    }

    private func openAPIRouteKeys() throws -> Set<String> {
        try Set(openAPIOperations().keys)
    }

    private func openAPIOperations() throws -> [String: [String: Any]] {
        let document = try openAPIDocument()
        let paths = try XCTUnwrap(document["paths"] as? [String: Any])
        let methodNames = Set(RuntimeControlHTTPMethod.allCases.map(\.rawValue))
        var operationsByRoute: [String: [String: Any]] = [:]

        for (path, value) in paths {
            let operations = try XCTUnwrap(value as? [String: Any])
            for (method, operationValue) in operations {
                let uppercased = method.uppercased()
                guard methodNames.contains(uppercased) else {
                    continue
                }
                operationsByRoute["\(uppercased) \(path)"] = try XCTUnwrap(operationValue as? [String: Any])
            }
        }
        return operationsByRoute
    }

    private func openAPIStringEnum(named name: String) throws -> [String] {
        let document = try openAPIDocument()
        let components = try XCTUnwrap(document["components"] as? [String: Any])
        let schemas = try XCTUnwrap(components["schemas"] as? [String: Any])
        let schema = try XCTUnwrap(schemas[name] as? [String: Any])
        return try XCTUnwrap(schema["enum"] as? [String])
    }

    private func openAPIStringEnum(schemaName: String, propertyName: String) throws -> [String] {
        let document = try openAPIDocument()
        let components = try XCTUnwrap(document["components"] as? [String: Any])
        let schemas = try XCTUnwrap(components["schemas"] as? [String: Any])
        let schema = try XCTUnwrap(schemas[schemaName] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let property = try XCTUnwrap(properties[propertyName] as? [String: Any])
        let values = try XCTUnwrap(property["enum"] as? [Any])
        return values.compactMap { $0 as? String }
    }

    private func openAPIDocument() throws -> [String: Any] {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repoRoot = packageRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("docs")
            .appendingPathComponent("runtime")
            .appendingPathComponent("runtime-control.openapi.json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func fetchWithRetry(_ request: URLRequest) async throws -> (Data, LocalHTTPTestResponse) {
        let request = try LocalHTTPTestRequest(request)
        var lastError: Error?
        for _ in 0..<20 {
            do {
                let response = try await LocalHTTPTestClient.fetch(request)
                return (response.body, response)
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        if Self.isLoopbackPermissionFailure(lastError) {
            throw XCTSkip("Loopback TCP connections are unavailable in this test sandbox.")
        }
        throw try XCTUnwrap(lastError)
    }

    private static func isLoopbackPermissionFailure(_ error: Error?) -> Bool {
        switch error as? LocalHTTPTestClientError {
        case .connectFailed(EPERM), .sendFailed(EPERM), .receiveFailed(EPERM):
            return true
        default:
            return false
        }
    }

    @MainActor
    private static func fetchRuntimeJSON<T: Decodable>(
        _ type: T.Type,
        port: UInt16,
        path: String,
        token: String
    ) async throws -> T {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(path)")))
        request.setValue(token, forHTTPHeaderField: "X-Runtime-Control-Token")

        let (data, httpResponse) = try await fetchWithRetry(request)

        XCTAssertEqual(httpResponse.statusCode, 200, path)
        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Content-Type"), "application/json", path)
        return try JSONDecoder().decode(type, from: data)
    }

    @MainActor
    private func makeStartedServer(
        token: String,
        servesDevConsole: Bool = false,
        browserSession: RuntimeControlLoopbackBrowserSession? = nil
    ) async throws -> (RuntimeControlLocalHTTPServer, UInt16) {
        let server = RuntimeControlLocalHTTPServer(
            configuration: RuntimeControlLocalHTTPServerConfiguration(
                port: 0,
                servesDevConsole: servesDevConsole,
                bindsToLoopbackOnly: true,
                browserSession: browserSession
            ),
            router: RuntimeControlAPIRouter(
                handler: StubRuntimeControlAPIReadHandler(),
                authorization: RuntimeControlAPIAuthorization(
                    token: token,
                    browserSession: browserSession
                )
            )
        )
        do {
            try server.start()
            let port = try await waitForActivePort(server)
            try await waitForStartedServer(port: port, token: token)
            return (server, port)
        } catch {
            server.stop()
            throw error
        }
    }

    @MainActor
    private func waitForActivePort(_ server: RuntimeControlLocalHTTPServer) async throws -> UInt16 {
        for _ in 0..<50 {
            if let port = server.activePort {
                return port
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw RuntimeControlLocalHTTPServerError.listenerUnavailable
    }

    @MainActor
    private func waitForStartedServer(port: UInt16, token: String) async throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform")))
        request.setValue(token, forHTTPHeaderField: "X-Runtime-Control-Token")
        _ = try await Self.fetchWithRetry(request)
    }

    private func makeTemporaryPWA() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-control-pwa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "<html>Runtime Control</html>".write(
            to: root.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    @MainActor
    private func XCTAssertThrowsPlatformAffordanceUnavailable(
        _ name: String,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            try await operation()
            XCTFail("Expected \(name) to throw platformAffordanceUnavailable", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? RuntimeControlAPIReadHandlerError,
                .platformAffordanceUnavailable,
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func XCTAssertThrowsUnsupportedFileReference(
        _ name: String,
        _ expected: RuntimeControlFileReferenceKind,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            try await operation()
            XCTFail("Expected \(name) to throw unsupportedFileReference", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? RuntimeControlAPIReadHandlerError,
                .unsupportedFileReference(expected.rawValue),
                file: file,
                line: line
            )
        }
    }
}

private final class FakeStaticFileReader: RuntimeControlStaticFileReading, @unchecked Sendable {
    let pathStates: [String: RuntimePathState]
    let dataByPath: [String: Data]
    private(set) var readURLs: [URL] = []

    init(
        pathStates: [String: RuntimePathState] = [:],
        dataByPath: [String: Data] = [:]
    ) {
        self.pathStates = pathStates
        self.dataByPath = dataByPath
    }

    func pathState(at url: URL) -> RuntimePathState {
        pathStates[url.path] ?? .missing
    }

    func readData(at url: URL) throws -> Data {
        readURLs.append(url)
        guard let data = dataByPath[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }
}

private extension Data {
    func text() throws -> String {
        try XCTUnwrap(String(data: self, encoding: .utf8))
    }
}

private enum RuntimeControlAPIEndpointTestError: Error {
    case expectedStream
    case expectedResponse
}

private struct LocalHTTPTestRequest: Sendable {
    let host: String
    let port: UInt16
    let target: String
    let method: String
    let headers: [String: String]
    let body: Data?

    init(_ request: URLRequest) throws {
        let url = try XCTUnwrap(request.url)
        host = try XCTUnwrap(url.host)
        port = UInt16(url.port ?? 80)
        var target = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            target += "?\(query)"
        }
        self.target = target
        method = request.httpMethod ?? "GET"
        headers = request.allHTTPHeaderFields ?? [:]
        body = request.httpBody
    }
}

private struct LocalHTTPTestResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    func value(forHTTPHeaderField name: String) -> String? {
        headers.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}

private enum LocalHTTPTestClientError: Error {
    case unsupportedHost(String)
    case connectFailed(Int32)
    case sendFailed(Int32)
    case receiveFailed(Int32)
    case invalidResponse
}

private enum LocalHTTPTestClient {
    static func fetch(_ request: LocalHTTPTestRequest) async throws -> LocalHTTPTestResponse {
        try await Task.detached {
            try blockingFetch(request)
        }.value
    }

    private static func blockingFetch(_ request: LocalHTTPTestRequest) throws -> LocalHTTPTestResponse {
        let socketDescriptor = try connectSocket(request)
        defer {
            Darwin.close(socketDescriptor)
        }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(socketDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(socketDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        try send(encode(request), socketDescriptor: socketDescriptor)
        return try decodeResponse(receive(socketDescriptor: socketDescriptor))
    }

    private static func connectSocket(_ request: LocalHTTPTestRequest) throws -> Int32 {
        if request.host == "127.0.0.1" {
            do {
                return try connectIPv4(host: request.host, port: request.port)
            } catch LocalHTTPTestClientError.connectFailed(ECONNREFUSED),
                    LocalHTTPTestClientError.connectFailed(EADDRNOTAVAIL) {
                return try connectIPv6Loopback(port: request.port)
            }
        }
        return try connectIPv4(host: request.host, port: request.port)
    }

    private static func connectIPv4(host: String, port: UInt16) throws -> Int32 {
        let socketDescriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw LocalHTTPTestClientError.connectFailed(errno)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            Darwin.close(socketDescriptor)
            throw LocalHTTPTestClientError.unsupportedHost(host)
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            let connectErrno = errno
            Darwin.close(socketDescriptor)
            throw LocalHTTPTestClientError.connectFailed(connectErrno)
        }
        return socketDescriptor
    }

    private static func connectIPv6Loopback(port: UInt16) throws -> Int32 {
        let socketDescriptor = Darwin.socket(AF_INET6, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw LocalHTTPTestClientError.connectFailed(errno)
        }

        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET6, "::1", &address.sin6_addr) == 1 else {
            Darwin.close(socketDescriptor)
            throw LocalHTTPTestClientError.unsupportedHost("::1")
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard connectResult == 0 else {
            let connectErrno = errno
            Darwin.close(socketDescriptor)
            throw LocalHTTPTestClientError.connectFailed(connectErrno)
        }
        return socketDescriptor
    }

    private static func encode(_ request: LocalHTTPTestRequest) -> Data {
        var headers = request.headers
        headers["Host"] = "\(request.host):\(request.port)"
        headers["Connection"] = "close"
        if let body = request.body {
            headers["Content-Length"] = String(body.count)
        }

        var head = "\(request.method) \(request.target) HTTP/1.1\r\n"
        for key in headers.keys.sorted() {
            guard let value = headers[key] else {
                continue
            }
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"

        var data = Data(head.utf8)
        if let body = request.body {
            data.append(body)
        }
        return data
    }

    private static func send(_ data: Data, socketDescriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var sent = 0
            while sent < rawBuffer.count {
                let count = Darwin.send(
                    socketDescriptor,
                    baseAddress.advanced(by: sent),
                    rawBuffer.count - sent,
                    0
                )
                guard count > 0 else {
                    throw LocalHTTPTestClientError.sendFailed(errno)
                }
                sent += count
            }
        }
    }

    private static func receive(socketDescriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.recv(socketDescriptor, &buffer, buffer.count, 0)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                continue
            }
            if count == 0 {
                return data
            }
            throw LocalHTTPTestClientError.receiveFailed(errno)
        }
    }

    private static func decodeResponse(_ data: Data) throws -> LocalHTTPTestResponse {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<separator.lowerBound], encoding: .utf8) else {
            throw LocalHTTPTestClientError.invalidResponse
        }

        let lines = head.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            throw LocalHTTPTestClientError.invalidResponse
        }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
            throw LocalHTTPTestClientError.invalidResponse
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw LocalHTTPTestClientError.invalidResponse
            }
            headers[parts[0]] = parts[1].trimmingCharacters(in: .whitespaces)
        }

        return LocalHTTPTestResponse(
            statusCode: statusCode,
            headers: headers,
            body: Data(data[separator.upperBound...])
        )
    }
}

private final class RuntimeControlStreamTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var dates: [Date]
    private var index = 0

    init(_ dates: [Date]) {
        self.dates = dates
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        guard !dates.isEmpty else {
            return Date(timeIntervalSince1970: 0)
        }
        let date = dates[min(index, dates.count - 1)]
        index += 1
        return date
    }
}

private func testRuntimeProductSettings() -> GuestRuntimeSettingsDocument {
    GuestRuntimeSettingsDocument(
        vitalServerURL: "http://vitalserver.local/",
        remoteConsoleURL: "http://console.local/",
        publicHost: "vitalserver.local",
        publicPort: 80
    )
}

private func testRuntimeSettingsOperation() -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: "runtime-settings-1",
        service: "runtime-settings",
        command: .applySettings,
        state: .completed,
        createdAt: "2026-07-01T00:00:00Z",
        updatedAt: "2026-07-01T00:00:01Z"
    )
}

private func testDatastoreRepairOperation(
    state: RuntimeGuestControlOperationState = .completed,
    failure: RuntimeGuestControlOperationFailure? = nil
) -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: "datastore-repair-1",
        service: "datastore-repair",
        command: .repairDatastore,
        state: state,
        createdAt: "2026-07-01T00:00:00Z",
        updatedAt: "2026-07-01T00:00:01Z",
        failure: failure
    )
}

private func testRuntimeOperationEvent() -> RuntimeOperationEventDocument {
    RuntimeOperationEventDocument(
        schemaVersion: 1,
        id: "runtime-operation-event-1",
        source: "runtime-controller",
        eventType: .completed,
        timestamp: "2026-07-01T00:00:01Z",
        operationId: "runtime-settings-1",
        operationService: "runtime-settings",
        operationCommand: "apply-settings",
        operationState: .completed,
        message: "runtime-settings apply-settings completed",
        failure: nil
    )
}

private struct StubRuntimeControlAPIReadHandler: RuntimeControlAPIReadHandler {
    var status: PlatformState?
    var statusError: Error?
    var operationState = PlatformOperationState(activeOperation: nil, install: .unavailable())
    var guestAddressResource = RuntimeGuestAddressResourceState.missing()
    var vmLifecycleResource = RuntimeVMLifecycleResourceState.missing()
    var providerCommandResponse: RuntimeProviderCommandResponse?
    var datastoreRepairOperation: RuntimeGuestControlServiceOperation?
    var startGuestServiceError: Error?
    var vitalDBObservationSnapshot: RuntimeVitalDBObservationSnapshot?
    var redisRelayStatusRead = RuntimeRedisRelayStatusReadResult(
        readState: .notRead,
        document: nil,
        readError: nil
    )

    func loadPlatformCapabilities() async throws -> PlatformCapabilities {
        PlatformCapabilities()
    }

    func uploadLabVitalFiles(
        _ sources: [RuntimeLabVitalFileUploadSource]
    ) async throws -> RuntimeLabVitalFileLibraryUploadResponse {
        RuntimeLabVitalFileLibraryUploadResponse(files: sources.map {
            RuntimeLabVitalFileLibraryUploadItem(
                fileName: $0.fileName,
                relativePath: $0.fileName,
                sizeBytes: $0.content.count
            )
        })
    }

    func loadRuntimeCapabilities() async throws -> RuntimeCapabilities {
        RuntimeCapabilities(schemaVersion: 1, capabilities: ["services:list", "lab:scenarios"])
    }

    func loadPlatformState() async throws -> PlatformState {
        if let statusError {
            throw statusError
        }
        if let status {
            return status
        }
        return PlatformState(
            runtimeInstallationState: .executable,
            services: [
                PlatformServiceStatus(role: .runtimeProvider, state: .loaded),
                PlatformServiceStatus(role: .publicProxy, state: .loaded),
                PlatformServiceStatus(role: .logSync, state: .loaded),
                PlatformServiceStatus(role: .watchdog, state: .loaded),
            ],
            platformHealth: .healthy,
            installedVersion: "1.2.3"
        )
    }

    func loadOperationState() async throws -> PlatformOperationState {
        operationState
    }

    func loadGuestAddressResource() async throws -> RuntimeGuestAddressResourceState {
        guestAddressResource
    }

    func putGuestAddressResource(_ request: RuntimeGuestAddressPutRequest) async throws -> RuntimeGuestAddressResourceState {
        .loaded(.loaded(address: request.address, source: .platformAgent))
    }

    func loadVMLifecycleResource() async throws -> RuntimeVMLifecycleResourceState {
        vmLifecycleResource
    }

    func putVMLifecycleResource(_ request: RuntimeVMLifecyclePutRequest) async throws -> RuntimeVMLifecycleResourceState {
        .loaded(request.document)
    }

    func controlRuntimeProvider(
        _ action: RuntimeProviderCommandAction
    ) async throws -> RuntimeProviderCommandResponse {
        if let providerCommandResponse {
            return providerCommandResponse
        }
        return RuntimeProviderCommandResponse(
            operationId: "provider-test",
            action: action,
            state: .completed,
            provider: vmLifecycleResource,
            failure: nil
        )
    }

    func loadRuntimeOperationEvents(
        query: RuntimeOperationEventQuery
    ) async throws -> RuntimeOperationEventHistory {
        RuntimeOperationEventHistory(
            events: [testRuntimeOperationEvent()],
            nextCursor: query.cursor,
            matchingCount: nil
        )
    }

    func loadVitalDBObservationSnapshot() async throws -> RuntimeVitalDBObservationSnapshot {
        if let vitalDBObservationSnapshot {
            return vitalDBObservationSnapshot
        }
        return .loaded(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_A",
                    ip: "10.0.0.10",
                    online: true,
                    activity: VitalDBRecorderActivityObservation(
                        windowSeconds: 300,
                        messageCount: 3,
                        byteCount: 2048,
                        roomCount: 1,
                        messagesPerSecond: 0.01,
                        bytesPerSecond: 6.8,
                        buckets: [
                            VitalDBRecorderActivityBucket(
                                bucketStartedAt: "2026-05-25T00:00:00Z",
                                bucketSeconds: 60,
                                messageCount: 3,
                                byteCount: 2048,
                                roomCount: 1
                            ),
                        ]
                    )
                ),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "Bed A",
                    vrcode: "VR_A",
                    lastSeenAt: "2026-05-25T00:00:00Z",
                    patientConnected: true,
                    online: true
                ),
            ]
        ))
    }

    func loadRedisRelayStatus() async throws -> RuntimeRedisRelayStatusReadResult {
        redisRelayStatusRead
    }

    func loadVitalDBRecorders() async throws -> RuntimeVitalRecorderHistory {
        let observationSnapshot = try await loadVitalDBObservationSnapshot()
        return RuntimeVitalRecorderHistory(
            observations: [observationSnapshot.observation].compactMap { $0 },
            activityBuckets: [
                VitalDBRecorderActivityBucketRecord(
                    vrcode: "VR_A",
                    bucketStartedAt: "2026-05-25T00:00:00Z",
                    bucketSeconds: 60,
                    messageCount: 3,
                    byteCount: 2048,
                    roomCount: 1,
                    firstObservedAt: "2026-05-25T00:00:00Z",
                    lastObservedAt: "2026-05-25T00:00:00Z"
                ),
            ]
        )
    }

    func loadVitalDBBeds() async throws -> RuntimeVitalBedHistory {
        let history = try await loadVitalDBRecorders()
        return RuntimeVitalBedHistory(
            state: history.state,
            updatedAt: history.updatedAt,
            beds: history.beds,
            summary: RuntimeVitalBedHistorySummary(recorderSummary: history.summary),
            readError: history.readError
        )
    }

    func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async throws -> RuntimeVitalRecorderActivityWindow {
        RuntimeVitalRecorderActivityWindow(
            state: .loaded,
            query: query,
            page: RuntimeVitalRecorderActivityWindowPage(
                index: query.pageIndex ?? 0,
                count: 1,
                windowSeconds: query.period.intervalSeconds ?? RuntimeVitalRecorderActivityWindowQuery.allWindowSeconds,
                windowStartedAt: "2026-05-25T00:00:00Z",
                windowEndedAt: "2026-05-25T00:01:00Z",
                firstBucketStartedAt: "2026-05-25T00:00:00Z",
                latestBucketStartedAt: "2026-05-25T00:00:00Z"
            ),
            buckets: [
                VitalDBRecorderActivityBucket(
                    bucketStartedAt: "2026-05-25T00:00:00Z",
                    bucketSeconds: query.bucketSeconds,
                    messageCount: 3,
                    byteCount: 2048,
                    roomCount: 1
                ),
            ],
            latestSampleAt: "2026-05-25T00:00:00Z"
        )
    }

    func loadVitalDBRelationships() async throws -> RuntimeVitalRelationshipHistory {
        RuntimeVitalRelationshipHistory(
            assignments: [
                RuntimeVitalBedAssignmentRecord(
                    assignmentID: "bed-a:VR_A:2026-05-25T00:00:00Z",
                    bedID: "bed-a",
                    bedName: "Bed A",
                    vrcode: "VR_A",
                    startedAt: "2026-05-25T00:00:00Z",
                    endedAt: nil,
                    lastSeenAt: "2026-05-25T00:00:00Z",
                    lastObservedAt: "2026-05-25T00:00:00Z",
                    status: .online,
                    patientConnected: true,
                    observationCount: 1
                ),
            ],
            events: [
                RuntimeVitalRelationshipEventRecord(
                    eventID: "2026-05-25T00:00:00Z:handoff:bed-a:VR_A",
                    observedAt: "2026-05-25T00:00:00Z",
                    eventType: .handoff,
                    severity: .info,
                    bedID: "bed-a",
                    bedName: "Bed A",
                    vrcode: "VR_A",
                    previousVrcode: nil,
                    previousBedID: nil,
                    message: "Bed bed-a is linked to VRecorder VR_A."
                ),
            ]
        )
    }

    func loadHealthStatus() async throws -> PlatformState {
        PlatformState(runtimeInstallationState: .executable, platformHealth: .healthy, installedVersion: "healthy")
    }

    func loadRuntimeProductSettings() async throws -> RuntimeProductSettingsRead {
        RuntimeProductSettingsRead(
            state: .loaded,
            settings: testRuntimeProductSettings(),
            readError: nil
        )
    }

    func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        RuntimeReleaseInfo(
            helperVersion: "0.1.0",
            minimumUpdaterVersion: "0.1.0",
            vitalServerVersion: "1.0.0",
            services: []
        )
    }

    func loadInstallInfo() async throws -> RuntimeInstallInfo {
        RuntimeInstallInfo(
            runtimeHomePath: "/runtime/home",
            backupsPath: "/runtime/backups",
            redisBackupsPath: "/runtime/home/data/backups/redis",
            runtimeDataBackupsPath: "/runtime/home/data/backups/vitalserver-helper"
        )
    }

    func loadLogText(request: RuntimeLogTextRequest) async throws -> RuntimeLogTextResponse {
        RuntimeLogTextResponse(text: "\(request.source.rawValue) log tail \(request.lineLimit)")
    }

    func loadBackups() async throws -> [RuntimeBackup] {
        [RuntimeBackup(path: "/backups/rollback", sizeBytes: 1024)]
    }

    func loadRedisBackups() async throws -> [RuntimeBackup] {
        [RuntimeBackup(path: "/platform/backups/runtime-data/redis/redis-1.tar.gz", sizeBytes: 512)]
    }

    func loadRuntimeDataBackups() async throws -> [RuntimeBackup] {
        [RuntimeBackup(path: "/backups/vitalserver-helper/20260610T000000Z-manual", sizeBytes: 2048)]
    }

    func applyRuntimeProductSettings(
        _: GuestRuntimeSettingsDocument
    ) async throws -> RuntimeGuestControlServiceOperation {
        testRuntimeSettingsOperation()
    }

    func applyRuntimeAdminPassword(
        _: String
    ) async throws -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "runtime-admin-1",
            service: "runtime-admin",
            command: .applyAdminPassword,
            state: .completed,
            createdAt: "2026-07-01T00:00:00Z",
            updatedAt: "2026-07-01T00:00:01Z"
        )
    }

    func repairRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "repair runtime", stderr: ""))
    }

    func repairProxy() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "repair proxy", stderr: ""))
    }

    func repairDatastore() async throws -> RuntimeGuestControlServiceOperation {
        datastoreRepairOperation ?? testDatastoreRepairOperation()
    }

    func repairVMDisk() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "repair vm disk", stderr: ""))
    }

    func createRedisBackup() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "redis backup created", stderr: ""))
    }

    func createRuntimeDataBackup() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "runtime data backup created", stderr: ""))
    }

    func updateBundleSummary(bundle: RuntimeControlFileReference) async throws -> RuntimeUpdateBundleSummaryResponse {
        RuntimeUpdateBundleSummaryResponse(summary: "summary \(bundle.value)")
    }

    func verifyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "verify \(bundle.value)", stderr: ""))
    }

    func applyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "apply \(bundle.value)", stderr: ""))
    }

    func rollbackBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "rollback \(backup.value)", stderr: ""))
    }

    func restoreRedisBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "restore redis \(backup.value)", stderr: ""))
    }

    func restoreRuntimeDataBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "restore runtime data \(backup.value)", stderr: ""))
    }

    func deleteBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "delete \(backup.value)", stderr: ""))
    }

    func exportLogs(destination: RuntimeControlFileReference) async throws -> RuntimeLogExportResult {
        RuntimeLogExportResult(destination: URL(fileURLWithPath: destination.value))
    }

    func acquireOperationLease(
        _ request: RuntimeOperationLeaseAcquireRequest
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        RuntimeOperationLeaseMutationResponse(
            operationId: request.document.operationId,
            state: .acquired
        )
    }

    func heartbeatOperationLease(
        _ request: RuntimeOperationLeaseHeartbeatRequest
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        RuntimeOperationLeaseMutationResponse(
            operationId: request.operationId,
            state: .heartbeatRecorded
        )
    }

    func releaseOperationLease(
        _ request: RuntimeOperationLeaseReleaseRequest
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        RuntimeOperationLeaseMutationResponse(
            operationId: request.operationId,
            state: .released
        )
    }

    func startGuestService(
        _ request: RuntimeGuestServiceControlRequest
    ) async throws -> RuntimeGuestControlServiceOperation {
        if let startGuestServiceError {
            throw startGuestServiceError
        }
        return RuntimeGuestControlServiceOperation(
            operationId: "start-\(request.service)",
            service: request.service,
            command: .start,
            state: .accepted,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:00+00:00"
        )
    }

    func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(
            exitCode: 0,
            stdout: mode.clean ? "clean uninstall" : "uninstall",
            stderr: ""
        ))
    }
}

private func XCTAssertFileReadNoPermission(
    _ error: Error,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let nsError = error as NSError
    XCTAssertEqual(nsError.domain, NSCocoaErrorDomain, file: file, line: line)
    XCTAssertEqual(nsError.code, CocoaError.Code.fileReadNoPermission.rawValue, file: file, line: line)
}

private func XCTAssertFileWriteNoPermission(
    _ error: Error,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let nsError = error as NSError
    XCTAssertEqual(nsError.domain, NSCocoaErrorDomain, file: file, line: line)
    XCTAssertEqual(nsError.code, CocoaError.Code.fileWriteNoPermission.rawValue, file: file, line: line)
}

private enum StubRuntimeControlAPIReadHandlerError: Error {
    case statusShouldNotBeLoaded
}

private final class FakeRuntimeControlClient:
    RuntimeControlClient,
    RuntimeHostClient,
    RuntimeGuestMaintenanceOperationClient
{
    var capabilities = RuntimeControlCapabilities(canOpenLocalFiles: false)
    var loadSettingsCount = 0
    var createRedisBackupCount = 0
    var createRuntimeDataBackupCount = 0
    var restoreRedisBackupCount = 0
    var restoreRuntimeDataBackupCount = 0
    var loadRedisBackupsCount = 0
    var loadRuntimeDataBackupsCount = 0
    var statusSettings: [RuntimeSettings] = []
    var healthSettings: [RuntimeSettings] = []
    var eventQueries: [RuntimeEventQuery] = []
    var runtimeOperationEventQueries: [RuntimeOperationEventQuery] = []
    var runtimeOperationEventError: Error?
    var guestStackStatusCount = 0
    var listGuestServicesCount = 0
    var guestServiceStatusRequests: [String] = []
    var guestServiceResourceRequests: [String] = []
    var startGuestServiceRequests: [RuntimeGuestServiceControlRequest] = []
    var stopGuestServiceRequests: [RuntimeGuestServiceControlRequest] = []
    var restartGuestServiceRequests: [RuntimeGuestServiceRestartRequest] = []
    var backupLatestPaths: [String?] = []
    var loadBackupsError: Error?
    var exportLogsError: Error?
    var operationState = PlatformOperationState(activeOperation: nil, install: .unavailable())

    func runtimeCapabilities() async throws -> RuntimeCapabilities {
        RuntimeCapabilities(schemaVersion: 1, capabilities: ["services:list", "lab:scenarios"])
    }

    func loadRuntimeProductSettings() async throws -> RuntimeProductSettingsRead {
        RuntimeProductSettingsRead(
            state: .loaded,
            settings: testRuntimeProductSettings(),
            readError: nil
        )
    }

    func applyRuntimeProductSettings(
        _: GuestRuntimeSettingsDocument
    ) async throws -> RuntimeGuestControlServiceOperation {
        testRuntimeSettingsOperation()
    }

    func loadRuntimeOperationEvents(
        query: RuntimeOperationEventQuery
    ) async throws -> RuntimeOperationEventHistory {
        runtimeOperationEventQueries.append(query)
        if let runtimeOperationEventError {
            throw runtimeOperationEventError
        }
        return RuntimeOperationEventHistory(
            events: [testRuntimeOperationEvent()],
            nextCursor: query.cursor,
            matchingCount: nil
        )
    }
    var acquiredOperationLeases: [RuntimeOperationLeaseDocument] = []
    var heartbeatOperationLeaseRequests: [RuntimeOperationLeaseHeartbeatRequest] = []
    var releasedOperationLeaseIDs: [String] = []
    var vitalDBObservationSnapshot: RuntimeVitalDBObservationSnapshot?
    var vitalDBObservation: VitalDBObservationDocument? = VitalDBObservationDocument(
        observedAt: "2026-05-25T00:00:00Z",
        ready: true,
        recorderOnlineThresholdSeconds: 120
    )

    func loadSettings() -> RuntimeSettings {
        loadSettingsCount += 1
        return RuntimeSettings(cpuCount: 6, memoryGiB: 10)
    }

    func loadPlatformState(settings: RuntimeSettings) -> PlatformState {
        statusSettings.append(settings)
        return PlatformState(runtimeInstallationState: .executable, installedVersion: "status with \(settings.cpuCount) CPUs", latestBackup: "latest-backup")
    }

    func loadOperationState() -> PlatformOperationState {
        operationState
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState {
        healthSettings.append(settings)
        return PlatformState(runtimeInstallationState: .executable, installedVersion: "health with \(settings.cpuCount) CPUs")
    }

    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        loadRuntimeEvents(query: RuntimeEventQuery(limit: limit))
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        eventQueries.append(query)
        let events = [
            RuntimeEventDocument(
                id: "event-1",
                eventType: .statusChanged,
                timestamp: "2026-05-24T00:00:00Z",
                product: "VitalServerHelper",
                status: .healthy,
                previousStatus: nil,
                operation: .health,
                message: "ready",
                runtimeVersion: "1.2.3",
                failureReasons: [],
                progress: nil
            ),
            RuntimeEventDocument(
                id: "event-2",
                eventType: .containerObserved,
                timestamp: "2026-05-24T00:01:00Z",
                product: "VitalServerHelper",
                status: .healthy,
                previousStatus: nil,
                operation: .health,
                message: "container observed",
                runtimeVersion: "1.2.3",
                failureReasons: [],
                progress: nil
            ),
            RuntimeEventDocument(
                id: "event-3",
                eventType: .recorderIngressObserved,
                timestamp: "2026-05-24T00:02:00Z",
                product: "VitalServerHelper",
                status: .healthy,
                previousStatus: nil,
                operation: .health,
                message: "recorder ingress observed",
                runtimeVersion: "1.2.3",
                failureReasons: [],
                progress: nil
            ),
        ].filter { event in
            guard let eventType = query.eventType else {
                return true
            }
            return event.eventType == eventType
        }.filter { event in
            guard let since = query.since else {
                return true
            }
            return event.timestamp >= since
        }
        return RuntimeEventHistory(
            events: Array(events.suffix(query.limit)),
            nextCursor: query.before.map(RuntimeEventCursorWireCodec.encode)
        )
    }

    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        vitalDBObservationSnapshot ?? RuntimeVitalDBObservationSnapshot.fromOptional(vitalDBObservation)
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        RuntimeVitalRecorderHistory(observations: [loadVitalDBObservationSnapshot().observation].compactMap { $0 })
    }

    func loadVitalDBBeds() -> RuntimeVitalBedHistory {
        let history = loadVitalDBRecorders()
        return RuntimeVitalBedHistory(
            state: history.state,
            updatedAt: history.updatedAt,
            beds: history.beds,
            summary: RuntimeVitalBedHistorySummary(recorderSummary: history.summary),
            readError: history.readError
        )
    }

    func hideVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        loadVitalDBRecorders()
    }

    func unhideVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        loadVitalDBRecorders()
    }

    func deleteVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        loadVitalDBRecorders()
    }

    func hideVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalBedHistory {
        loadVitalDBBeds()
    }

    func unhideVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalBedHistory {
        loadVitalDBBeds()
    }

    func deleteVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalBedHistory {
        loadVitalDBBeds()
    }

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        RuntimeVitalRelationshipHistory(
            assignments: [
                RuntimeVitalBedAssignmentRecord(
                    assignmentID: "bed-a:VR_A:2026-05-25T00:00:00Z",
                    bedID: "bed-a",
                    bedName: "Bed A",
                    vrcode: "VR_A",
                    startedAt: "2026-05-25T00:00:00Z",
                    endedAt: nil,
                    lastSeenAt: "2026-05-25T00:00:00Z",
                    lastObservedAt: "2026-05-25T00:00:00Z",
                    status: .online,
                    patientConnected: true,
                    observationCount: 1
                ),
            ],
            events: []
        )
    }

    func loadBackups(latestBackupPath: String?) throws -> [RuntimeBackup] {
        backupLatestPaths.append(latestBackupPath)
        if let loadBackupsError {
            throw loadBackupsError
        }
        return [RuntimeBackup(path: "/backups/rollback", sizeBytes: 1024)]
    }

    func loadRedisBackups() throws -> [RuntimeBackup] {
        loadRedisBackupsCount += 1
        return [RuntimeBackup(path: "/platform/backups/runtime-data/redis/redis-1.tar.gz", sizeBytes: 512)]
    }

    func loadRuntimeDataBackups() throws -> [RuntimeBackup] {
        loadRuntimeDataBackupsCount += 1
        return [RuntimeBackup(path: "/backups/vitalserver-helper/20260610T000000Z-manual", sizeBytes: 2048)]
    }

    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult {
        .loaded("summary \(url.path)")
    }

    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult {
        .loaded("log:\(sourceID.rawValue):\(lineLimit)")
    }

    func loadLogTextResult(sourceID: RuntimeLogSource, lineLimit: Int) async -> RuntimeHostTextReadResult {
        logTextResult(sourceID: sourceID, lineLimit: lineLimit)
    }

    func preferredLogsPath() -> String {
        "/logs"
    }

    func vitalFileFolders(root: String) throws -> [VitalFilesFolder] {
        []
    }

    func createDirectory(at url: URL) {}

    func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "verify \(url.path)", stderr: "")
    }

    func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: mode.clean ? "clean uninstall" : "uninstall", stderr: "")
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "settings \(settings.cpuCount)", stderr: "")
    }

    func repairProxy() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "repair proxy", stderr: "")
    }

    func requestDatastoreRepair() async throws -> RuntimeGuestControlServiceOperation {
        testDatastoreRepairOperation()
    }

    func repairDatastore() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "repair datastore", stderr: "")
    }

    func repairVMDisk() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "repair vm disk", stderr: "")
    }

    func repairRuntimeServices() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "repair runtime", stderr: "")
    }

    func createRedisBackup() async throws -> RuntimeCommandResult {
        createRedisBackupCount += 1
        return RuntimeCommandResult(exitCode: 0, stdout: "redis backup created", stderr: "")
    }

    func createRuntimeDataBackup() async throws -> RuntimeCommandResult {
        createRuntimeDataBackupCount += 1
        return RuntimeCommandResult(exitCode: 0, stdout: "runtime data backup created", stderr: "")
    }

    func listGuestServices() async throws -> RuntimeGuestControlServiceList {
        listGuestServicesCount += 1
        return RuntimeGuestControlServiceList(services: ["app", "recorder-ingress", "postgres"])
    }

    func guestStackStatus() async throws -> RuntimeGuestControlStackStatus {
        guestStackStatusCount += 1
        return RuntimeGuestControlStackStatus(
            state: "loaded",
            observedAt: "2026-07-01T00:00:00+00:00",
            services: [
                RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00+00:00",
                    container: "vitalserver-app-1"
                ),
                RuntimeGuestControlServiceStatus(
                    service: "recorder-ingress",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00+00:00",
                    container: "vitalserver-recorder-ingress-1"
                ),
                RuntimeGuestControlServiceStatus(
                    service: "postgres",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00+00:00",
                    container: "vitalserver-postgres-1"
                ),
            ]
        )
    }

    func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus {
        guestServiceStatusRequests.append(service)
        return RuntimeGuestControlServiceStatus(
            service: service,
            state: "running",
            health: "healthy",
            observedAt: "2026-07-01T00:00:00+00:00",
            container: "vitalserver-\(service)-1"
        )
    }

    func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource {
        guestServiceResourceRequests.append(service)
        return RuntimeGuestServiceResource(
            service: service,
            spec: RuntimeGuestServiceSpec(
                state: "configured",
                desiredState: "running",
                updatedAt: "2026-07-01T00:00:00+00:00"
            ),
            status: RuntimeGuestServiceStatusRead(
                state: "loaded",
                observedState: "running",
                observedAt: "2026-07-01T00:00:00+00:00",
                serviceStatus: RuntimeGuestControlServiceStatus(
                    service: service,
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00+00:00"
                )
            ),
            conditions: [
                RuntimeGuestServiceCondition(
                    type: "Reconciled",
                    status: "true",
                    reason: "DesiredStateObserved",
                    message: "matched desired state",
                    observedAt: "2026-07-01T00:00:00+00:00"
                )
            ],
            lastOperationId: "op-\(service)"
        )
    }

    func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        startGuestServiceRequests.append(request)
        return guestServiceOperation(request.service, command: .start)
    }

    func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        stopGuestServiceRequests.append(request)
        return guestServiceOperation(request.service, command: .stop)
    }

    func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation {
        restartGuestServiceRequests.append(request)
        return guestServiceOperation(request.service, command: .restart)
    }

    private func guestServiceOperation(
        _ service: String,
        command: RuntimeGuestControlServiceCommand
    ) -> RuntimeGuestControlServiceOperation {
        return RuntimeGuestControlServiceOperation(
            operationId: "\(command.rawValue)-\(service)",
            service: service,
            command: command,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00"
        )
    }

    func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        RuntimeReleaseInfo(
            helperVersion: "0.2.0",
            minimumUpdaterVersion: "0.1.0",
            vitalServerVersion: "1.1.0",
            services: []
        )
    }

    func loadInstallInfo() -> RuntimeInstallInfo {
        RuntimeInstallInfo(
            appBundlePath: "/Applications/VitalServer Helper.app",
            packageIdentifier: "ai.tirosh.vitalserver.helper",
            runtimeHomePath: "/runtime",
            backupsPath: "/backups",
            redisBackupsPath: "/platform/backups/runtime-data/redis",
            runtimeDataBackupsPath: "/platform/backups/runtime-data/vitalserver-helper"
        )
    }

    func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "apply \(url.path)", stderr: "")
    }

    func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "rollback \(backupURL.path)", stderr: "")
    }

    func restoreRedisBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        restoreRedisBackupCount += 1
        return RuntimeCommandResult(exitCode: 0, stdout: "restore redis \(backupURL.path)", stderr: "")
    }

    func restoreRuntimeDataBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        restoreRuntimeDataBackupCount += 1
        return RuntimeCommandResult(exitCode: 0, stdout: "restore runtime data \(backupURL.path)", stderr: "")
    }

    func deleteBackup(url: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "delete \(url.path)", stderr: "")
    }

    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        if let exportLogsError {
            throw exportLogsError
        }
        return RuntimeLogExportResult(destination: destination)
    }

    func acquireOperationLease(
        _ document: RuntimeOperationLeaseDocument
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        acquiredOperationLeases.append(document)
        return RuntimeOperationLeaseMutationResponse(
            operationId: document.operationId,
            state: .acquired
        )
    }

    func heartbeatOperationLease(
        operationId: String,
        heartbeatAt: String,
        expiresAt: String?
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        heartbeatOperationLeaseRequests.append(RuntimeOperationLeaseHeartbeatRequest(
            operationId: operationId,
            heartbeatAt: heartbeatAt,
            expiresAt: expiresAt
        ))
        return RuntimeOperationLeaseMutationResponse(
            operationId: operationId,
            state: .heartbeatRecorded
        )
    }

    func releaseOperationLease(
        operationId: String
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        releasedOperationLeaseIDs.append(operationId)
        return RuntimeOperationLeaseMutationResponse(
            operationId: operationId,
            state: .released
        )
    }
}
