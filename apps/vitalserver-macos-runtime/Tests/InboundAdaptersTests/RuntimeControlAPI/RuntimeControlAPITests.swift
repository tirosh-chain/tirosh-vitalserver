import Foundation
import Darwin
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
            $0.path.hasPrefix("/runtime/")
                || $0.path.hasPrefix("/vitaldb/")
                || $0.path.hasPrefix("/lab/")
        })
    }

    func testHostAffordanceRoutesAreExplicitlySeparated() {
        let hostRoutes = RuntimeControlAPIEndpoint.allCases
            .map(\.route)
            .filter { $0.scope == .hostAffordance }

        XCTAssertFalse(hostRoutes.isEmpty)
        XCTAssertTrue(hostRoutes.allSatisfy { $0.path.hasPrefix("/host/") })
    }

    func testAPIRequestsRoundTripThroughJSON() throws {
        let request = RuntimeApplySettingsRequest(settings: RuntimeSettings(cpuCount: 4, memoryGiB: 6))

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(RuntimeApplySettingsRequest.self, from: encoded)

        XCTAssertEqual(decoded.settings.cpuCount, 4)
        XCTAssertEqual(decoded.settings.memoryGiB, 6)
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
            vitalFilePath: "MORA04/202301/230102/sample.vital",
            sessionName: "Replay sample",
            targetURL: "http://edge/"
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
            RuntimeControlAPIEndpoint.matching(method: .get, path: "/runtime/status?refresh=false"),
            .status
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

        XCTAssertNil(responder.response(for: .init(method: .get, path: "/runtime/status")))
        XCTAssertNil(responder.response(for: .init(method: .get, path: "/vitaldb/recorders")))
        XCTAssertNil(responder.response(for: .init(method: .get, path: "/lab/scenarios")))
        XCTAssertNil(responder.response(for: .init(method: .get, path: "/host/logs/stream")))
    }

    func testStaticFileResponderDoesNotInterceptRuntimeAPIWithQueryString() throws {
        let root = try makeTemporaryPWA()
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root)

        XCTAssertNil(responder.response(for: .init(method: .get, path: "/runtime/status?refresh=true")))
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
            "GET /runtime/overview/stream",
            "GET /runtime/status/stream",
            "GET /runtime/events/stream",
            "GET /vitaldb/observations/stream",
            "GET /host/logs/stream",
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
            .overviewStream,
            .statusStream,
            .eventStream,
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
        let swiftEventTypes = RuntimeEventType.knownTypes.map(\.rawValue)

        XCTAssertEqual(openAPIEventTypes, swiftEventTypes)
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

        let response = await router.route(.init(method: .get, path: "/runtime/status"))

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "application/json")

        let body = try XCTUnwrap(response.body)
        let status = try JSONDecoder().decode(RuntimeStatus.self, from: body)

        XCTAssertEqual(status.runtimeInstalled, true)
        XCTAssertEqual(status.runtimeState, .healthy)
        XCTAssertEqual(status.runtimeVersion, "1.2.3")

        let overviewResponse = await router.route(.init(method: .get, path: "/runtime/overview"))
        let overviewBody = try XCTUnwrap(overviewResponse.body)
        let overviewText = try XCTUnwrap(String(data: overviewBody, encoding: .utf8))

        XCTAssertEqual(overviewResponse.status, .ok)
        XCTAssertTrue(overviewText.contains(#""bridgedInterface":null"#))
    }

    @MainActor
    func testRuntimeEventStreamReturnsSSEFramesFromRuntimeEvents() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/runtime/events/stream")))
        let event = try await firstStreamEvent(stream)
        let text = try XCTUnwrap(String(data: try RuntimeControlServerSentEventCodec.encode(event), encoding: .utf8))

        XCTAssertEqual(stream.status, .ok)
        XCTAssertEqual(stream.headers["Content-Type"], "text/event-stream")
        XCTAssertTrue(text.contains("id: event-1"))
        XCTAssertTrue(text.contains("event: status-changed"))
        XCTAssertTrue(text.contains("data: "))
        XCTAssertTrue(text.contains("\"id\":\"event-1\""))
    }

    @MainActor
    func testRuntimeEventStreamPreservesReadIssueBeforeEventFrames() async throws {
        let handler = StubRuntimeControlAPIReadHandler(eventHistory: RuntimeEventHistory(
            events: [
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
            ],
            readError: "jsonl=invalid line"
        ))
        let router = RuntimeControlAPIRouter(handler: handler)

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/runtime/events/stream")))
        let event = try await firstStreamEvent(stream)
        let history = try JSONDecoder().decode(RuntimeEventHistory.self, from: try XCTUnwrap(event.data))

        XCTAssertEqual(event.id, "runtime-events-read-issue")
        XCTAssertEqual(event.event, "runtime-events-read-issue")
        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.readError, "jsonl=invalid line")
        XCTAssertEqual(history.events.map(\.id), ["event-1"])
    }

    func testRuntimeEventStreamCodecEncodesReadIssueForFailedHistory() throws {
        let history = RuntimeEventHistory.failed(readError: "jsonl=read failed")

        let text = try XCTUnwrap(String(data: try RuntimeControlServerSentEventCodec.encode(history), encoding: .utf8))

        XCTAssertTrue(text.contains("id: runtime-events-read-issue"))
        XCTAssertTrue(text.contains("event: runtime-events-read-issue"))
        XCTAssertTrue(text.contains("\"state\":\"readFailed\""))
        XCTAssertTrue(text.contains("\"readError\":\"jsonl=read failed\""))
    }

    @MainActor
    func testRuntimeEventStreamWithStaleLastEventIDStillDeliversCurrentEvents() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let stream = try await streamResponse(from: router.routeResult(.init(
            method: .get,
            path: "/runtime/events/stream",
            headers: ["Last-Event-ID": "missing-event"]
        )))
        let event = try await firstStreamEvent(stream)

        XCTAssertEqual(event.id, "event-1")
    }

    @MainActor
    func testRuntimeStatusStreamReturnsSSEFrameFromRuntimeStatus() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/runtime/status/stream")))
        let event = try await firstStreamEvent(stream)
        let text = try XCTUnwrap(String(data: try RuntimeControlServerSentEventCodec.encode(event), encoding: .utf8))

        XCTAssertEqual(stream.status, .ok)
        XCTAssertEqual(stream.headers["Content-Type"], "text/event-stream")
        XCTAssertTrue(text.contains("id: runtime-status"))
        XCTAssertTrue(text.contains("event: runtime-status"))
        XCTAssertTrue(text.contains("\"runtimeVersion\":\"1.2.3\""))
    }

    @MainActor
    func testRuntimeStatusStreamHeartbeatUsesInjectedClock() async throws {
        let clock = RuntimeControlStreamTestClock([
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 2),
        ])
        let router = RuntimeControlAPIRouter(
            handler: StubRuntimeControlAPIReadHandler(status: RuntimeStatus(
                runtimeInstalled: true,
                vmServiceLoaded: true,
                proxyServiceLoaded: true,
                guestLogSyncServiceLoaded: true,
                watchdogServiceLoaded: true,
                runtimeState: .healthy,
                statusMessage: "ready",
                updatedAt: "2026-06-08T00:00:00Z",
                runtimeVersion: "1.2.3"
            )),
            streamConfiguration: RuntimeControlAPIStreamConfiguration(
                pollIntervalNanoseconds: 1_000_000,
                heartbeatIntervalNanoseconds: 1_000_000_000
            ),
            now: clock.now
        )

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/runtime/status/stream")))
        var iterator = stream.events.makeAsyncIterator()
        let firstEvent = try await iterator.next()
        let secondEvent = try await iterator.next()
        let first = try XCTUnwrap(firstEvent)
        let second = try XCTUnwrap(secondEvent)

        XCTAssertEqual(first.id, "runtime-status")
        XCTAssertEqual(second, .heartbeat)
    }

    @MainActor
    func testRuntimeOverviewStreamReturnsPWAReadModelSSEFrame() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/runtime/overview/stream")))
        let event = try await firstStreamEvent(stream)
        let text = try XCTUnwrap(String(data: try RuntimeControlServerSentEventCodec.encode(event), encoding: .utf8))

        XCTAssertEqual(stream.status, .ok)
        XCTAssertEqual(stream.headers["Content-Type"], "text/event-stream")
        XCTAssertTrue(text.contains("id: runtime-overview"))
        XCTAssertTrue(text.contains("event: runtime-overview"))
        XCTAssertTrue(text.contains("\"vitalRecorder\""))
        XCTAssertTrue(text.contains("\"knownRecorders\":1"))
    }

    @MainActor
    func testHostLogStreamReturnsSSEFrameFromLogText() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/host/logs/stream?source=command&lineLimit=5")))
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
            path: "/vitaldb/observations/stream"
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
            event: "runtime-status",
            data: Data("{}".utf8)
        ))) { error in
            XCTAssertEqual(error as? RuntimeControlServerSentEventEncodingError, .missingID)
        }

        XCTAssertThrowsError(try RuntimeControlServerSentEventCodec.encode(RuntimeControlServerSentEvent(
            id: "runtime-status",
            event: nil,
            data: Data("{}".utf8)
        ))) { error in
            XCTAssertEqual(error as? RuntimeControlServerSentEventEncodingError, .missingEvent)
        }

        XCTAssertThrowsError(try RuntimeControlServerSentEventCodec.encode(RuntimeControlServerSentEvent(
            id: "runtime-status",
            event: "runtime-status",
            data: nil
        ))) { error in
            XCTAssertEqual(error as? RuntimeControlServerSentEventEncodingError, .missingData)
        }

        XCTAssertThrowsError(try RuntimeControlServerSentEventCodec.encode(RuntimeControlServerSentEvent(
            id: "runtime-status",
            event: "runtime-status",
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

        let capabilities = try await decode(
            RuntimeControlCapabilities.self,
            from: router.route(.init(method: .get, path: "/runtime/capabilities"))
        )
        let overview = try await decode(
            RuntimeControlOverview.self,
            from: router.route(.init(method: .get, path: "/runtime/overview"))
        )
        let settings = try await decode(
            RuntimeSettings.self,
            from: router.route(.init(method: .get, path: "/runtime/settings"))
        )
        let health = try await decode(
            RuntimeStatus.self,
            from: router.route(.init(method: .post, path: "/runtime/health"))
        )
        let release = try await decode(
            RuntimeReleaseInfo.self,
            from: router.route(.init(method: .get, path: "/runtime/release"))
        )
        let installInfo = try await decode(
            RuntimeInstallInfo.self,
            from: router.route(.init(method: .get, path: "/runtime/install"))
        )
        let events = try await decode(
            RuntimeEventHistory.self,
            from: router.route(.init(method: .get, path: "/runtime/events"))
        )
        let vitalDBObservation = try await decode(
            VitalDBObservationDocument?.self,
            from: router.route(.init(method: .get, path: "/vitaldb/observations/latest"))
        )
        let vitalRecorders = try await decode(
            RuntimeVitalRecorderHistory.self,
            from: router.route(.init(method: .get, path: "/vitaldb/recorders"))
        )
        let vitalRecorder = try await decode(
            RuntimeVitalRecorderRecord.self,
            from: router.route(.init(method: .get, path: "/vitaldb/recorders/VR_A"))
        )
        let vitalRecorderActivity = try await decode(
            RuntimeVitalRecorderActivityWindow.self,
            from: router.route(.init(
                method: .get,
                path: "/vitaldb/recorders/VR_A/activity?bucketSeconds=60&period=all&pageIndex=0"
            ))
        )
        let vitalBeds = try await decode(
            [RuntimeVitalBedRecord].self,
            from: router.route(.init(method: .get, path: "/vitaldb/beds"))
        )
        let vitalBed = try await decode(
            RuntimeVitalBedRecord.self,
            from: router.route(.init(method: .get, path: "/vitaldb/beds/bed-a"))
        )
        let vitalRelationships = try await decode(
            RuntimeVitalRelationshipHistory.self,
            from: router.route(.init(method: .get, path: "/vitaldb/relationships"))
        )

        XCTAssertTrue(capabilities.canControlRuntimeServices)
        XCTAssertTrue(capabilities.canControlGuestServices)
        XCTAssertEqual(overview.status.runtimeVersion, "1.2.3")
        XCTAssertEqual(overview.vitalDBObservationSnapshot.state, .loaded)
        XCTAssertEqual(overview.vitalDBObservationSnapshot.observation?.recorders.map(\.vrcode), ["VR_A"])
        XCTAssertEqual(overview.vitalRecorder.knownRecorders, 1)
        XCTAssertEqual(overview.vitalRecorder.onlineRecorders, 1)
        XCTAssertEqual(overview.vitalRecorder.latestRecorder?.vrcode, "VR_A")
        XCTAssertEqual(settings.cpuCount, 4)
        XCTAssertEqual(health.statusMessage, "healthy")
        XCTAssertEqual(release.helperVersion, "0.1.0")
        XCTAssertEqual(installInfo.runtimeHomePath, "/runtime/home")
        XCTAssertEqual(events.events.map(\.id), ["event-1"])
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
        XCTAssertEqual(vitalBeds.map(\.bedID), ["bed-a"])
        XCTAssertEqual(vitalBed.vrcode, "VR_A")
        XCTAssertEqual(vitalRelationships.assignments.map(\.vrcode), ["VR_A"])
        XCTAssertEqual(vitalRelationships.events.first?.eventType, .handoff)
    }

    @MainActor
    func testRouterServesLabNamespaceWithExplicitUnavailableState() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())
        let createRequest = RuntimeLabSessionCreateRequest(
            scenarioId: "post-operative-monitoring",
            recorderCount: 2
        )
        let replayRequest = RuntimeLabVitalFileReplayRequest(
            vitalFilePath: "MORA04/202301/230102/sample.vital"
        )
        let uploadRequest = RuntimeLabVitalFileUploadRequest(
            vitalFilePath: "MORA04/202301/230102/sample.vital",
            targetURL: "http://edge/"
        )

        let scenarios = try await decode(
            RuntimeLabScenarioList.self,
            from: router.route(.init(method: .get, path: "/lab/scenarios"))
        )
        let vitalFiles = try await decode(
            RuntimeLabVitalFileList.self,
            from: router.route(.init(method: .get, path: "/lab/vital-files"))
        )
        let beds = try await decode(
            RuntimeLabBedList.self,
            from: router.route(.init(method: .get, path: "/lab/beds"))
        )
        let recorders = try await decode(
            RuntimeLabRecorderList.self,
            from: router.route(.init(method: .get, path: "/lab/recorders"))
        )
        let create = try await decode(RuntimeLabSessionResponse.self, from: router.route(.init(
            method: .post,
            path: "/lab/sessions",
            body: try JSONEncoder().encode(createRequest)
        )))
        let session = try await decode(
            RuntimeLabSessionResponse.self,
            from: router.route(.init(method: .get, path: "/lab/sessions/session-1"))
        )
        let start = try await decode(
            RuntimeLabSessionResponse.self,
            from: router.route(.init(method: .post, path: "/lab/sessions/session-1/start"))
        )
        let stop = try await decode(
            RuntimeLabSessionResponse.self,
            from: router.route(.init(method: .post, path: "/lab/sessions/session-1/stop"))
        )
        let replay = try await decode(RuntimeLabSessionResponse.self, from: router.route(.init(
            method: .post,
            path: "/lab/vital-files/replay",
            body: try JSONEncoder().encode(replayRequest)
        )))
        let upload = try await decode(RuntimeLabVitalFileUploadResponse.self, from: router.route(.init(
            method: .post,
            path: "/lab/vital-files/upload",
            body: try JSONEncoder().encode(uploadRequest)
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
        XCTAssertEqual(upload.state, .unavailable)
    }

    @MainActor
    func testVitalDBSingleResourceRoutesReturnTypedNotFoundInsteadOfJSONNull() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let missingRecorder = await router.route(.init(method: .get, path: "/vitaldb/recorders/VR_MISSING"))
        let missingBed = await router.route(.init(method: .get, path: "/vitaldb/beds/bed-missing"))
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
    func testOverviewDoesNotFallbackToStaleStatusVitalDBObservationWhenFreshReadIsUnavailable() async throws {
        let status = RuntimeStatus(runtimeState: .healthy, statusMessage: "ready")
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler(
            status: status,
            vitalDBObservationSnapshot: .unavailable(readError: "sqlite=read failed")
        ))

        let overview = try await decode(
            RuntimeControlOverview.self,
            from: router.route(.init(method: .get, path: "/runtime/overview"))
        )

        XCTAssertNil(overview.vitalDBObservation)
        XCTAssertEqual(overview.vitalDBObservationSnapshot.state, .unavailable)
        XCTAssertEqual(overview.vitalDBObservationSnapshot.readError, "sqlite=read failed")
        XCTAssertNil(overview.vitalRecorder.knownRecorders)
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

        let response = await router.route(.init(method: .post, path: "/runtime/status"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .methodNotAllowed)
        XCTAssertEqual(error.code, .methodNotAllowed)
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
            path: "/host/backups/redis/restore",
            body: try JSONEncoder().encode(redisRequest)
        )))
        let runtimeData = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .post,
            path: "/host/backups/vitalserver-helper/restore",
            body: try JSONEncoder().encode(runtimeDataRequest)
        )))

        XCTAssertEqual(redis.result.stdout, "restore redis /redis-backups/redis.tar.gz")
        XCTAssertEqual(runtimeData.result.stdout, "restore runtime data /backups/vitalserver-helper/manual")
    }

    @MainActor
    func testRouterExecutesRuntimeCommandEndpointsThroughHandler() async throws {
        let handler = StubRuntimeControlAPIReadHandler()
        let router = RuntimeControlAPIRouter(handler: handler)
        let settingsRequest = RuntimeApplySettingsRequest(settings: RuntimeSettings(cpuCount: 3, memoryGiB: 6))

        let applySettings = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .put,
            path: "/runtime/settings",
            body: try JSONEncoder().encode(settingsRequest)
        )))
        let repairRuntime = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(method: .post, path: "/runtime/services/repair-runtime")))
        let repairProxy = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .post,
            path: "/runtime/services/repair-proxy"
        )))
        let repairDatastore = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(method: .post, path: "/runtime/services/repair-datastore")))
        let repairVMDisk = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(method: .post, path: "/runtime/services/repair-vm-disk")))

        XCTAssertEqual(applySettings.result.stdout, "settings 3")
        XCTAssertEqual(repairRuntime.result.stdout, "repair runtime")
        XCTAssertEqual(repairProxy.result.stdout, "repair proxy")
        XCTAssertEqual(repairDatastore.result.stdout, "repair datastore")
        XCTAssertEqual(repairVMDisk.result.stdout, "repair vm disk")
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

        let summary = try await decode(RuntimeUpdateBundleSummaryResponse.self, from: router.route(.init(
            method: .post,
            path: "/host/update-bundles/summary",
            body: try JSONEncoder().encode(bundleRequest)
        )))
        let verify = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .post,
            path: "/host/update-bundles/verify",
            body: try JSONEncoder().encode(bundleRequest)
        )))
        let apply = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .post,
            path: "/host/update-bundles/apply",
            body: try JSONEncoder().encode(bundleRequest)
        )))
        let rollback = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .post,
            path: "/host/backups/rollback",
            body: try JSONEncoder().encode(backupRequest)
        )))
        let deleteBackup = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .delete,
            path: "/host/backups",
            body: try JSONEncoder().encode(backupRequest)
        )))
        let deleteUpdateBackup = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .delete,
            path: "/host/backups/update",
            body: try JSONEncoder().encode(backupRequest)
        )))
        let deleteRuntimeDataBackup = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .delete,
            path: "/host/backups/vitalserver-helper",
            body: try JSONEncoder().encode(backupRequest)
        )))
        let export = try await decode(RuntimeLogExportResult.self, from: router.route(.init(
            method: .post,
            path: "/host/logs/export",
            body: try JSONEncoder().encode(exportRequest)
        )))

        XCTAssertEqual(summary.summary, "summary /bundles/update.tar.gz")
        XCTAssertEqual(verify.result.stdout, "verify /bundles/update.tar.gz")
        XCTAssertEqual(apply.result.stdout, "apply /bundles/update.tar.gz")
        XCTAssertEqual(rollback.result.stdout, "rollback /backups/latest")
        XCTAssertEqual(deleteBackup.result.stdout, "delete /backups/latest")
        XCTAssertEqual(deleteUpdateBackup.result.stdout, "delete /backups/latest")
        XCTAssertEqual(deleteRuntimeDataBackup.result.stdout, "delete /backups/latest")
        XCTAssertEqual(export.destination.path, "/tmp/vitalserver-logs.zip")
    }

    @MainActor
    func testRouterCreatesRedisBackupThroughRuntimeControlClientHandler() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client, hostClient: client))

        let response = await router.route(.init(method: .post, path: "/runtime/redis/backups"))
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
            path: "/runtime/guest/services/start",
            body: try JSONEncoder().encode(RuntimeGuestServiceControlRequest(service: "app"))
        ))
        let stopResponse = await router.route(.init(
            method: .post,
            path: "/runtime/guest/services/stop",
            body: try JSONEncoder().encode(RuntimeGuestServiceControlRequest(service: "app"))
        ))
        let restartResponse = await router.route(.init(
            method: .post,
            path: "/runtime/guest/services/restart",
            body: try JSONEncoder().encode(RuntimeGuestServiceRestartRequest(service: "app"))
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
            from: router.route(.init(method: .get, path: "/runtime/guest/stack/status"))
        )
        let services = try await decode(
            RuntimeGuestControlServiceList.self,
            from: router.route(.init(method: .get, path: "/runtime/guest/services"))
        )
        let status = try await decode(
            RuntimeGuestControlServiceStatus.self,
            from: router.route(.init(method: .get, path: "/runtime/guest/services/recorder-ingress/status"))
        )

        XCTAssertEqual(stackStatus.state, "loaded")
        XCTAssertEqual(stackStatus.services.map(\.service), ["app", "recorder-ingress", "postgres"])
        XCTAssertEqual(services.services, ["app", "recorder-ingress", "postgres"])
        XCTAssertEqual(status.service, "recorder-ingress")
        XCTAssertEqual(status.state, "running")
        XCTAssertEqual(status.health, "healthy")
        XCTAssertEqual(client.guestStackStatusCount, 1)
        XCTAssertEqual(client.guestServiceStatusRequests, ["recorder-ingress"])
        XCTAssertEqual(client.listGuestServicesCount, 1)
    }

    @MainActor
    func testRouterServesBackupListsThroughRuntimeControlClientHandler() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client, hostClient: client))

        let backups = try await decode(
            [RuntimeBackup].self,
            from: router.route(.init(method: .get, path: "/host/backups"))
        )
        let redisBackups = try await decode(
            [RuntimeBackup].self,
            from: router.route(.init(method: .get, path: "/host/backups/redis"))
        )

        XCTAssertEqual(backups.map(\.path), ["/backups/rollback"])
        XCTAssertEqual(redisBackups.map(\.path), ["/runtime/data/backups/redis/redis-1.tar.gz"])
        XCTAssertEqual(client.backupLatestPaths, ["latest-backup"])
        XCTAssertEqual(client.loadRedisBackupsCount, 1)
    }

    @MainActor
    func testRuntimeControlClientReadHandlerAdaptsClientReads() async throws {
        let client = FakeRuntimeControlClient()
        let handler = RuntimeControlClientAPIReadHandler(client: client)

        let capabilities = try await handler.loadCapabilities()
        let settings = try await handler.loadSettings()
        let status = try await handler.loadStatus()
        let events = try await handler.loadEvents(query: RuntimeEventQuery())
        let health = try await handler.loadHealthStatus()
        let release = try await handler.loadReleaseInfo()
        let installInfo = try await handler.loadInstallInfo()
        let observationSnapshot = try await handler.loadVitalDBObservationSnapshot()
        let recorders = try await handler.loadVitalDBRecorders()
        let relationships = try await handler.loadVitalDBRelationships()

        XCTAssertFalse(capabilities.canOpenLocalFiles)
        XCTAssertEqual(settings.cpuCount, 6)
        XCTAssertEqual(status.statusMessage, "status with 6 CPUs")
        XCTAssertEqual(events.events.map(\.id), ["event-1", "event-2", "event-3"])
        XCTAssertEqual(health.statusMessage, "health with 6 CPUs")
        XCTAssertEqual(release.helperVersion, "0.2.0")
        XCTAssertEqual(installInfo.appBundlePath, "/Applications/VitalServer Helper.app")
        XCTAssertEqual(installInfo.packageIdentifier, "ai.tirosh.vitalserver.helper")
        XCTAssertEqual(installInfo.backupsPath, "/backups")
        XCTAssertEqual(installInfo.redisBackupsPath, "/runtime/data/backups/redis")
        XCTAssertEqual(installInfo.runtimeDataBackupsPath, "/runtime/data/backups/vitalserver-helper")
        XCTAssertEqual(observationSnapshot.state, .loaded)
        XCTAssertEqual(observationSnapshot.observation?.observedAt, "2026-05-25T00:00:00Z")
        XCTAssertEqual(recorders.updatedAt, "2026-05-25T00:00:00Z")
        XCTAssertEqual(relationships.assignments.map(\.assignmentID), ["bed-a:VR_A:2026-05-25T00:00:00Z"])
        XCTAssertEqual(client.loadSettingsCount, 3)
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
        let handler = RuntimeControlClientAPIReadHandler(client: client, hostClient: client)

        let applySettings = try await handler.applySettings(RuntimeSettings(cpuCount: 4, memoryGiB: 8))
        let repairRuntime = try await handler.repairRuntimeServices()
        let repairProxy = try await handler.repairProxy()
        let repairDatastore = try await handler.repairDatastore()
        let repairVMDisk = try await handler.repairVMDisk()
        let createRedisBackup = try await handler.createRedisBackup()
        let uninstall = try await handler.uninstallRuntime(mode: .clean)

        XCTAssertEqual(applySettings.result.stdout, "settings 4")
        XCTAssertEqual(repairRuntime.result.stdout, "repair runtime")
        XCTAssertEqual(repairProxy.result.stdout, "repair proxy")
        XCTAssertEqual(repairDatastore.result.stdout, "repair datastore")
        XCTAssertEqual(repairVMDisk.result.stdout, "repair vm disk")
        XCTAssertEqual(createRedisBackup.result.stdout, "redis backup created")
        XCTAssertEqual(uninstall.result.stdout, "clean uninstall")
    }

    @MainActor
    func testRuntimeControlClientReadHandlerAdaptsHostAffordances() async throws {
        let client = FakeRuntimeControlClient()
        let handler = RuntimeControlClientAPIReadHandler(client: client, hostClient: client)
        let bundle = RuntimeControlFileReference(kind: .localPath, value: "/bundles/update.tar.gz")
        let backup = RuntimeControlFileReference(kind: .localPath, value: "/backups/latest")
        let destination = RuntimeControlFileReference(kind: .localPath, value: "/tmp/vitalserver-logs.zip")

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

        XCTAssertEqual(logText.text, "log:helperMessage:25")
        XCTAssertEqual(backups.map(\.path), ["/backups/rollback"])
        XCTAssertEqual(redisBackups.map(\.path), ["/runtime/data/backups/redis/redis-1.tar.gz"])
        XCTAssertEqual(runtimeDataBackups.map(\.path), ["/backups/vitalserver-helper/20260610T000000Z-manual"])
        XCTAssertEqual(summary.summary, "summary /bundles/update.tar.gz")
        XCTAssertEqual(verify.result.stdout, "verify /bundles/update.tar.gz")
        XCTAssertEqual(apply.result.stdout, "apply /bundles/update.tar.gz")
        XCTAssertEqual(rollback.result.stdout, "rollback /backups/latest")
        XCTAssertEqual(createRuntimeDataBackup.result.stdout, "runtime data backup created")
        XCTAssertEqual(delete.result.stdout, "delete /backups/latest")
        XCTAssertEqual(export.destination.path, "/tmp/vitalserver-logs.zip")
        XCTAssertEqual(client.backupLatestPaths, ["latest-backup"])
        XCTAssertEqual(client.loadRedisBackupsCount, 1)
        XCTAssertEqual(client.loadRuntimeDataBackupsCount, 1)
        XCTAssertEqual(client.createRuntimeDataBackupCount, 1)
    }

    @MainActor
    func testRuntimeControlClientReadHandlerRequiresHostAffordanceClientForHostOperations() async throws {
        let handler = RuntimeControlClientAPIReadHandler(client: FakeRuntimeControlClient())
        let bundle = RuntimeControlFileReference(kind: .localPath, value: "/bundles/update.tar.gz")
        let backup = RuntimeControlFileReference(kind: .localPath, value: "/backups/latest")
        let destination = RuntimeControlFileReference(kind: .localPath, value: "/tmp/vitalserver-logs.zip")

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
        ]

        for (name, operation) in operations {
            try await XCTAssertThrowsHostAffordanceUnavailable(name, operation)
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
            RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable.localizedDescription,
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
            path: "/runtime/events?limit=1&type=recorder-ingress-observed&since=2026-05-24T00:01:00Z"
        ))
        let history = try decode(RuntimeEventHistory.self, from: response)

        XCTAssertEqual(history.events.map(\.id), ["event-3"])
        XCTAssertEqual(client.eventQueries, [
            RuntimeEventQuery(limit: 1, eventType: .recorderIngressObserved, since: "2026-05-24T00:01:00Z"),
        ])
    }

    @MainActor
    func testRuntimeEventsEndpointAcceptsCursor() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client))
        let cursor = RuntimeEventCursor(timestamp: "2026-05-24T00:01:00Z", id: "event-2")
        let wireCursor = RuntimeEventCursorWireCodec.encode(cursor)

        let response = await router.route(.init(method: .get, path: "/runtime/events?limit=2&cursor=\(wireCursor)"))
        let history = try decode(RuntimeEventHistory.self, from: response)

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(history.nextCursor, RuntimeEventCursorWireCodec.encode(cursor))
        XCTAssertEqual(client.eventQueries, [
            RuntimeEventQuery(limit: 2, before: cursor),
        ])
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
    func testRuntimeEventsEndpointRejectsInvalidCursor() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/runtime/events?cursor=not-a-cursor"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
    }

    @MainActor
    func testRuntimeEventsEndpointRejectsUnknownEventType() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/runtime/events?type=unknown"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertEqual(error.message, "Invalid runtime event type: unknown")
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
            path: "/host/logs/stream?source=command&lineLimit=5"
        ).runtimeLogTextRequest()
        let explicitEmpty = try RuntimeControlHTTPRequest(
            method: .get,
            path: "/host/logs/stream?source=command&lineLimit=5&helperMessage="
        ).runtimeLogTextRequest()

        XCTAssertEqual(missing, RuntimeLogTextRequest(source: .command, lineLimit: 5))
        XCTAssertEqual(explicitEmpty, missing)
    }

    func testRuntimeLogQueryRejectsMalformedPercentEncoding() {
        XCTAssertThrowsError(try RuntimeControlHTTPRequest(
            method: .get,
            path: "/host/logs/stream?source=%ZZ"
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
        XCTAssertTrue(error.message.contains("RuntimeApplySettingsRequest"))
        XCTAssertTrue(error.message.contains("Decode failed"))
    }

    @MainActor
    func testRouterMapsHostAffordanceUnavailableToTypedHTTPError() async throws {
        let router = RuntimeControlAPIRouter(
            handler: RuntimeControlClientAPIReadHandler(client: FakeRuntimeControlClient())
        )
        let response = await router.route(.init(
            method: .post,
            path: "/host/logs/read",
            body: try JSONEncoder().encode(RuntimeLogTextRequest(source: .command, lineLimit: 10))
        ))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .notImplemented)
        XCTAssertEqual(error.code, .hostAffordanceUnavailable)
        XCTAssertEqual(error.message, RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable.localizedDescription)
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
            path: "/host/update-bundles/summary",
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

        let response = await router.route(.init(method: .get, path: "/runtime/status"))
        let status = try decode(RuntimeStatus.self, from: response)

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(status.statusMessage, "status with 6 CPUs")
        XCTAssertEqual(client.loadSettingsCount, 1)
    }

    @MainActor
    func testRouterRejectsMissingOrInvalidTokenWhenAuthorizationIsConfigured() async throws {
        let router = RuntimeControlAPIRouter(
            handler: StubRuntimeControlAPIReadHandler(),
            authorization: RuntimeControlAPIAuthorization(token: "dev-token")
        )

        let missingTokenResponse = await router.route(.init(method: .get, path: "/runtime/status"))
        let invalidTokenResponse = await router.route(.init(
            method: .get,
            path: "/runtime/status",
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
            path: "/runtime/status",
            headers: ["x-runtime-control-token": "dev-token"]
        ))

        XCTAssertEqual(response.status, .ok)
    }

    func testWireCodecDecodesHTTPRequests() throws {
        let rawRequest = [
            "GET /runtime/status?refresh=false HTTP/1.1",
            "Host: 127.0.0.1",
            "X-Runtime-Control-Token: dev-token",
            "",
            "",
        ].joined(separator: "\r\n")

        let request = try RuntimeControlHTTPWireCodec.decodeRequest(Data(rawRequest.utf8))

        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/runtime/status?refresh=false")
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
        let partialHeader = Data("GET /runtime/status HTTP/1.1\r\nHost: 127.0.0.1".utf8)
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
            "GET /runtime/status HTTP/1.1",
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
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.decodeRequest(Data("GET /runtime/status".utf8))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .invalidRequest)
        }
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.decodeRequest(Data("GET\r\n\r\n".utf8))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .invalidRequest)
        }
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.decodeRequest(Data("TRACE /runtime/status HTTP/1.1\r\n\r\n".utf8))) { error in
            XCTAssertEqual(error as? RuntimeControlHTTPWireCodecError, .unsupportedMethod("TRACE"))
        }
        XCTAssertThrowsError(try RuntimeControlHTTPWireCodec.decodeRequest(Data("GET /runtime/status HTTP/1.1\r\nBadHeader\r\n\r\n".utf8))) { error in
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
        XCTAssertTrue(html.contains("/runtime/overview"))
        XCTAssertTrue(html.contains("/runtime/overview/stream"))
        XCTAssertTrue(html.contains("/runtime/status/stream"))
        XCTAssertTrue(html.contains("/runtime/events/stream"))
        XCTAssertTrue(html.contains("/vitaldb/recorders"))
        XCTAssertTrue(html.contains("/host/logs/stream"))
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

        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/runtime/status")))
        request.setValue("dev-token", forHTTPHeaderField: "X-Runtime-Control-Token")

        let (data, httpResponse) = try await Self.fetchWithRetry(request)
        let status = try JSONDecoder().decode(RuntimeStatus.self, from: data)

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(status.runtimeState, .healthy)
        XCTAssertEqual(status.runtimeVersion, "1.2.3")
    }

    @MainActor
    func testRuntimeControlE2ESmokeServesCoreReadEndpointsOverHTTP() async throws {
        let token = "dev-token"
        let (server, port) = try await makeStartedServer(token: token)
        defer {
            server.stop()
        }

        let capabilities = try await Self.fetchRuntimeJSON(
            RuntimeControlCapabilities.self,
            port: port,
            path: "/runtime/capabilities",
            token: token
        )
        let status = try await Self.fetchRuntimeJSON(
            RuntimeStatus.self,
            port: port,
            path: "/runtime/status",
            token: token
        )
        let settings = try await Self.fetchRuntimeJSON(
            RuntimeSettings.self,
            port: port,
            path: "/runtime/settings",
            token: token
        )
        let events = try await Self.fetchRuntimeJSON(
            RuntimeEventHistory.self,
            port: port,
            path: "/runtime/events?limit=5",
            token: token
        )
        let overview = try await Self.fetchRuntimeJSON(
            RuntimeControlOverview.self,
            port: port,
            path: "/runtime/overview",
            token: token
        )

        XCTAssertTrue(capabilities.canExportLogs)
        XCTAssertTrue(capabilities.canStreamLogs)
        XCTAssertEqual(status.runtimeState, .healthy)
        XCTAssertEqual(status.runtimeVersion, "1.2.3")
        XCTAssertEqual(settings.cpuCount, 4)
        XCTAssertEqual(settings.memoryGiB, 8)
        XCTAssertEqual(events.events.map(\.id), ["event-1"])
        XCTAssertEqual(overview.status.runtimeVersion, "1.2.3")
        XCTAssertEqual(overview.vitalRecorder.knownRecorders, 1)

        let missingTokenRequest = URLRequest(
            url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/runtime/status"))
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
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/runtime/status")))
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
    func testLocalHTTPServerAllowsPrivateNetworkCORSPreflight() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token")
        defer {
            server.stop()
        }

        let origin = "http://192.168.0.42:5174"
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/runtime/status")))
        request.httpMethod = "OPTIONS"
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("GET", forHTTPHeaderField: "Access-Control-Request-Method")
        request.setValue("X-Runtime-Control-Token", forHTTPHeaderField: "Access-Control-Request-Headers")

        let (_, httpResponse) = try await Self.fetchWithRetry(request)

        XCTAssertEqual(httpResponse.statusCode, 204)
        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), origin)
    }

    @MainActor
    func testLocalHTTPServerAddsCORSHeadersToLoopbackAPIResponses() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token")
        defer {
            server.stop()
        }

        let origin = "http://localhost:5174"
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/runtime/status")))
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

        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/runtime/status")))
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

        let request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/runtime/status")))

        let (data, httpResponse) = try await Self.fetchWithRetry(request)
        let error = try JSONDecoder().decode(RuntimeControlErrorResponse.self, from: data)

        XCTAssertEqual(httpResponse.statusCode, 401)
        XCTAssertEqual(error.code, .unauthorized)
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from response: RuntimeControlHTTPResponse
    ) throws -> T {
        XCTAssertEqual(response.status, .ok)
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
            .appendingPathComponent("macos")
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
        servesDevConsole: Bool = false
    ) async throws -> (RuntimeControlLocalHTTPServer, UInt16) {
        let server = RuntimeControlLocalHTTPServer(
            configuration: RuntimeControlLocalHTTPServerConfiguration(
                port: 0,
                servesDevConsole: servesDevConsole,
                bindsToLoopbackOnly: true
            ),
            router: RuntimeControlAPIRouter(
                handler: StubRuntimeControlAPIReadHandler(),
                authorization: RuntimeControlAPIAuthorization(token: token)
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
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/runtime/status")))
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
    private func XCTAssertThrowsHostAffordanceUnavailable(
        _ name: String,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            try await operation()
            XCTFail("Expected \(name) to throw hostAffordanceUnavailable", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? RuntimeControlAPIReadHandlerError,
                .hostAffordanceUnavailable,
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

private struct StubRuntimeControlAPIReadHandler: RuntimeControlAPIReadHandler {
    var status: RuntimeStatus?
    var eventHistory: RuntimeEventHistory?
    var vitalDBObservationSnapshot: RuntimeVitalDBObservationSnapshot?

    func loadCapabilities() async throws -> RuntimeControlCapabilities {
        RuntimeControlCapabilities()
    }

    func loadStatus() async throws -> RuntimeStatus {
        if let status {
            return status
        }
        return RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            statusMessage: "ready",
            runtimeVersion: "1.2.3"
        )
    }

    func loadEvents(query: RuntimeEventQuery) async throws -> RuntimeEventHistory {
        if let eventHistory {
            return eventHistory
        }
        return RuntimeEventHistory(events: [
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
        ])
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

    func loadHealthStatus() async throws -> RuntimeStatus {
        RuntimeStatus(runtimeInstalled: true, runtimeState: .healthy, statusMessage: "healthy")
    }

    func loadSettings() async throws -> RuntimeSettings {
        RuntimeSettings(cpuCount: 4, memoryGiB: 8)
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
        [RuntimeBackup(path: "/runtime/data/backups/redis/redis-1.tar.gz", sizeBytes: 512)]
    }

    func loadRuntimeDataBackups() async throws -> [RuntimeBackup] {
        [RuntimeBackup(path: "/backups/vitalserver-helper/20260610T000000Z-manual", sizeBytes: 2048)]
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "settings \(settings.cpuCount)", stderr: ""))
    }

    func repairRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "repair runtime", stderr: ""))
    }

    func repairProxy() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "repair proxy", stderr: ""))
    }

    func repairDatastore() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "repair datastore", stderr: ""))
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


private final class FakeRuntimeControlClient: RuntimeControlClient, RuntimeHostClient {
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
    var guestStackStatusCount = 0
    var listGuestServicesCount = 0
    var guestServiceStatusRequests: [String] = []
    var startGuestServiceRequests: [RuntimeGuestServiceControlRequest] = []
    var stopGuestServiceRequests: [RuntimeGuestServiceControlRequest] = []
    var restartGuestServiceRequests: [RuntimeGuestServiceRestartRequest] = []
    var backupLatestPaths: [String?] = []
    var loadBackupsError: Error?
    var exportLogsError: Error?
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

    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        statusSettings.append(settings)
        return RuntimeStatus(statusMessage: "status with \(settings.cpuCount) CPUs", latestBackup: "latest-backup")
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        healthSettings.append(settings)
        return RuntimeStatus(statusMessage: "health with \(settings.cpuCount) CPUs")
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
    ) async throws -> RuntimeVitalRecorderHistory {
        loadVitalDBRecorders()
    }

    func unhideVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        loadVitalDBRecorders()
    }

    func deleteVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        loadVitalDBRecorders()
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
        return [RuntimeBackup(path: "/runtime/data/backups/redis/redis-1.tar.gz", sizeBytes: 512)]
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
            redisBackupsPath: "/runtime/data/backups/redis",
            runtimeDataBackupsPath: "/runtime/data/backups/vitalserver-helper"
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
}
