import Contracts
import RuntimeControl
import RuntimeControlAPI
import XCTest

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
            $0.path.hasPrefix("/runtime/") || $0.path.hasPrefix("/vitaldb/")
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

    func testRuntimeInstallInfoDoesNotInferRedisBackupPathFromRollbackBackupPath() {
        let installInfo = RuntimeInstallInfo(backupsPath: "/rollback/backups")

        XCTAssertNil(installInfo.redisBackupsPath)
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

    func testStaticFileResponderDoesNotInterceptRuntimeAPI() throws {
        let root = try makeTemporaryPWA()
        let responder = RuntimeControlStaticFileResponder(rootDirectory: root)

        XCTAssertNil(responder.response(for: .init(method: .get, path: "/runtime/status")))
        XCTAssertNil(responder.response(for: .init(method: .get, path: "/vitaldb/recorders")))
        XCTAssertNil(responder.response(for: .init(method: .get, path: "/host/logs/stream")))
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

    func testTestKitEndpointsIncludeManagementActions() {
        XCTAssertEqual(
            RuntimeTestKitAPIEndpoint.matching(method: .post, path: "/dev/testkit/beds/delete"),
            .deleteBeds
        )
        XCTAssertEqual(
            RuntimeTestKitAPIEndpoint.matching(method: .post, path: "/dev/testkit/virtual-recorders/delete"),
            .deleteVirtualRecorders
        )
        XCTAssertEqual(
            RuntimeTestKitAPIEndpoint.matching(method: .post, path: "/dev/testkit/virtual-recorders/delete-orphan"),
            .deleteVirtualRecorder
        )
        XCTAssertEqual(
            RuntimeTestKitAPIEndpoint.matching(method: .post, path: "/dev/testkit/virtual-recorders/reset"),
            .resetVirtualRecorders
        )
        XCTAssertTrue(RuntimeTestKitAPIEndpoint.matches(path: "/dev/testkit/status"))
    }

    func testOpenAPIRoutesMatchRuntimeControlAPIEndpoints() throws {
        let documentedRoutes = try openAPIRouteKeys()
        var endpointRoutes = Set(RuntimeControlAPIEndpoint.allCases.map { endpoint in
            "\(endpoint.route.method.rawValue) \(endpoint.route.path)"
        })
        endpointRoutes.formUnion(RuntimeTestKitAPIEndpoint.allCases.map { endpoint in
            "\(endpoint.method.rawValue) \(endpoint.path)"
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

    func testOpenAPITestKitRoutesAreDocumentedAsTestOnly() throws {
        let operations = try openAPIOperations()

        for endpoint in RuntimeTestKitAPIEndpoint.allCases {
            let key = "\(endpoint.method.rawValue) \(endpoint.path)"
            let operation = try XCTUnwrap(operations[key])

            XCTAssertEqual(operation["x-runtime-control-scope"] as? String, RuntimeControlAPIScope.runtimeControl.rawValue)
            XCTAssertEqual(operation["x-runtime-control-implementation"] as? String, "testOnlyLocal")
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
    }

    @MainActor
    func testRuntimeEventStreamReturnsSSEFramesFromRuntimeEvents() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/runtime/events/stream")))
        let event = try await firstStreamEvent(stream)
        let text = try XCTUnwrap(String(data: RuntimeControlServerSentEventCodec.encode(event), encoding: .utf8))

        XCTAssertEqual(stream.status, .ok)
        XCTAssertEqual(stream.headers["Content-Type"], "text/event-stream")
        XCTAssertTrue(text.contains("id: event-1"))
        XCTAssertTrue(text.contains("event: status-changed"))
        XCTAssertTrue(text.contains("data: "))
        XCTAssertTrue(text.contains("\"id\":\"event-1\""))
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
        let text = try XCTUnwrap(String(data: RuntimeControlServerSentEventCodec.encode(event), encoding: .utf8))

        XCTAssertEqual(stream.status, .ok)
        XCTAssertEqual(stream.headers["Content-Type"], "text/event-stream")
        XCTAssertTrue(text.contains("id: runtime-status"))
        XCTAssertTrue(text.contains("event: runtime-status"))
        XCTAssertTrue(text.contains("\"runtimeVersion\":\"1.2.3\""))
    }

    @MainActor
    func testRuntimeOverviewStreamReturnsPWAReadModelSSEFrame() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let stream = try await streamResponse(from: router.routeResult(.init(method: .get, path: "/runtime/overview/stream")))
        let event = try await firstStreamEvent(stream)
        let text = try XCTUnwrap(String(data: RuntimeControlServerSentEventCodec.encode(event), encoding: .utf8))

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
        let text = try XCTUnwrap(String(data: RuntimeControlServerSentEventCodec.encode(event), encoding: .utf8))

        XCTAssertEqual(stream.status, .ok)
        XCTAssertEqual(stream.headers["Content-Type"], "text/event-stream")
        XCTAssertTrue(text.contains("id: runtime-log-command"))
        XCTAssertTrue(text.contains("event: runtime-log"))
        XCTAssertTrue(text.contains("\"text\":\"command log tail 5\""))
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
            RuntimeVitalRecorderRecord?.self,
            from: router.route(.init(method: .get, path: "/vitaldb/recorders/VR_A"))
        )
        let vitalBeds = try await decode(
            [RuntimeVitalBedRecord].self,
            from: router.route(.init(method: .get, path: "/vitaldb/beds"))
        )
        let vitalBed = try await decode(
            RuntimeVitalBedRecord?.self,
            from: router.route(.init(method: .get, path: "/vitaldb/beds/bed-a"))
        )
        let vitalRelationships = try await decode(
            RuntimeVitalRelationshipHistory.self,
            from: router.route(.init(method: .get, path: "/vitaldb/relationships"))
        )

        XCTAssertTrue(capabilities.canControlRuntimeServices)
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
        XCTAssertEqual(vitalRecorders.recorders.first?.activityTimeline.first?.messageCount, 3)
        XCTAssertEqual(vitalRecorder?.vrcode, "VR_A")
        XCTAssertEqual(vitalRecorder?.activityTimeline.first?.byteCount, 2048)
        XCTAssertEqual(vitalRecorder?.activityTimeline.first?.buckets.first?.bucketSeconds, 60)
        XCTAssertEqual(vitalBeds.map(\.bedID), ["bed-a"])
        XCTAssertEqual(vitalBed?.vrcode, "VR_A")
        XCTAssertEqual(vitalRelationships.assignments.map(\.vrcode), ["VR_A"])
        XCTAssertEqual(vitalRelationships.events.first?.eventType, .handoff)
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
    func testRouterReturnsTypedNotImplementedErrorForUnsupportedRestoreEndpoint() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let request = RuntimeBackupRequest(
            backup: RuntimeControlFileReference(kind: .localPath, value: "/redis-backups/redis.tar.gz")
        )
        let response = await router.route(.init(
            method: .post,
            path: "/host/backups/redis/restore",
            body: try JSONEncoder().encode(request)
        ))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .notImplemented)
        XCTAssertEqual(error.code, .endpointNotImplemented)
    }

    @MainActor
    func testRouterExecutesRuntimeCommandEndpointsThroughHandler() async throws {
        let handler = StubRuntimeControlAPIReadHandler()
        let router = RuntimeControlAPIRouter(handler: handler)
        let settingsRequest = RuntimeApplySettingsRequest(settings: RuntimeSettings(cpuCount: 3, memoryGiB: 6))
        let repairProxyRequest = RuntimeRepairProxyRequest(proxyPort: 8080)

        let applySettings = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .put,
            path: "/runtime/settings",
            body: try JSONEncoder().encode(settingsRequest)
        )))
        let start = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(method: .post, path: "/runtime/services/start")))
        let stop = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(method: .post, path: "/runtime/services/stop")))
        let repairRuntime = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(method: .post, path: "/runtime/services/repair-runtime")))
        let repairProxy = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(
            method: .post,
            path: "/runtime/services/repair-proxy",
            body: try JSONEncoder().encode(repairProxyRequest)
        )))
        let repairDatastore = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(method: .post, path: "/runtime/services/repair-datastore")))
        let repairVMDisk = try await decode(RuntimeControlCommandResponse.self, from: router.route(.init(method: .post, path: "/runtime/services/repair-vm-disk")))

        XCTAssertEqual(applySettings.result.stdout, "settings 3")
        XCTAssertEqual(start.result.stdout, "start services")
        XCTAssertEqual(stop.result.stdout, "stop services")
        XCTAssertEqual(repairRuntime.result.stdout, "repair runtime")
        XCTAssertEqual(repairProxy.result.stdout, "repair proxy 8080")
        XCTAssertEqual(repairDatastore.result.stdout, "repair datastore")
        XCTAssertEqual(repairVMDisk.result.stdout, "repair vm disk")
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
        XCTAssertEqual(export.destination.path, "/tmp/vitalserver-logs.zip")
    }

    @MainActor
    func testRouterCreatesRedisBackupThroughRuntimeControlClientHandler() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client))

        let response = await router.route(.init(method: .post, path: "/runtime/redis/backups"))
        let commandResponse = try decode(RuntimeControlCommandResponse.self, from: response)

        XCTAssertEqual(commandResponse.result.stdout, "redis backup created")
        XCTAssertEqual(client.createRedisBackupCount, 1)
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
        XCTAssertEqual(installInfo.packageIdentifier, "com.tirosh.vitalserver.vm")
        XCTAssertEqual(installInfo.backupsPath, "/backups")
        XCTAssertEqual(installInfo.redisBackupsPath, "/runtime/data/backups/redis")
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
        let handler = RuntimeControlClientAPIReadHandler(client: client)

        let applySettings = try await handler.applySettings(RuntimeSettings(cpuCount: 4, memoryGiB: 8))
        let start = try await handler.startRuntimeServices()
        let stop = try await handler.stopRuntimeServices()
        let repairRuntime = try await handler.repairRuntimeServices()
        let repairProxy = try await handler.repairProxy(proxyPort: 8080)
        let repairDatastore = try await handler.repairDatastore()
        let repairVMDisk = try await handler.repairVMDisk()
        let createRedisBackup = try await handler.createRedisBackup()
        let uninstall = try await handler.uninstallRuntime(clean: true)

        XCTAssertEqual(applySettings.result.stdout, "settings 4")
        XCTAssertEqual(start.result.stdout, "start services")
        XCTAssertEqual(stop.result.stdout, "stop services")
        XCTAssertEqual(repairRuntime.result.stdout, "repair runtime")
        XCTAssertEqual(repairProxy.result.stdout, "repair proxy 8080")
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
            helperMessage: "helper unavailable",
            lineLimit: 25
        ))
        let backups = try await handler.loadBackups()
        let redisBackups = try await handler.loadRedisBackups()
        let summary = try await handler.updateBundleSummary(bundle: bundle)
        let verify = try await handler.verifyUpdateBundle(bundle: bundle)
        let apply = try await handler.applyUpdateBundle(bundle: bundle)
        let rollback = try await handler.rollbackBackup(backup)
        let delete = try await handler.deleteBackup(backup)
        let export = try await handler.exportLogs(destination: destination)

        XCTAssertEqual(logText.text, "helper unavailable")
        XCTAssertEqual(backups.map(\.path), ["/backups/rollback"])
        XCTAssertEqual(redisBackups.map(\.path), ["/runtime/data/backups/redis/redis-1.tar.gz"])
        XCTAssertEqual(summary.summary, "summary /bundles/update.tar.gz")
        XCTAssertEqual(verify.result.stdout, "verify /bundles/update.tar.gz")
        XCTAssertEqual(apply.result.stdout, "apply /bundles/update.tar.gz")
        XCTAssertEqual(rollback.result.stdout, "rollback /backups/latest")
        XCTAssertEqual(delete.result.stdout, "delete /backups/latest")
        XCTAssertEqual(export.destination.path, "/tmp/vitalserver-logs.zip")
        XCTAssertEqual(client.backupLatestPaths, ["latest-backup"])
        XCTAssertEqual(client.loadRedisBackupsCount, 1)
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
                    helperMessage: "helper unavailable",
                    lineLimit: 25
                ))
            }),
            ("loadBackups", { _ = try await handler.loadBackups() }),
            ("loadRedisBackups", { _ = try await handler.loadRedisBackups() }),
            ("updateBundleSummary", { _ = try await handler.updateBundleSummary(bundle: bundle) }),
            ("verifyUpdateBundle", { _ = try await handler.verifyUpdateBundle(bundle: bundle) }),
            ("applyUpdateBundle", { _ = try await handler.applyUpdateBundle(bundle: bundle) }),
            ("rollbackBackup", { _ = try await handler.rollbackBackup(backup) }),
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
            RuntimeControlAPIReadHandlerError.unsupportedFileReference(.remoteURL).localizedDescription,
            "File reference kind remoteURL is not supported by this local Runtime Control handler."
        )
    }

    @MainActor
    func testRuntimeEventsEndpointAcceptsQueryFilters() async throws {
        let client = FakeRuntimeControlClient()
        let router = RuntimeControlAPIRouter(handler: RuntimeControlClientAPIReadHandler(client: client))

        let response = await router.route(.init(
            method: .get,
            path: "/runtime/events?limit=1&type=audit-proxy-observed&since=2026-05-24T00:01:00Z"
        ))
        let history = try decode(RuntimeEventHistory.self, from: response)

        XCTAssertEqual(history.events.map(\.id), ["event-3"])
        XCTAssertEqual(client.eventQueries, [
            RuntimeEventQuery(limit: 1, eventType: .auditProxyObserved, since: "2026-05-24T00:01:00Z"),
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
    func testRuntimeEventsEndpointRejectsInvalidCursor() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/runtime/events?cursor=not-a-cursor"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(error.code, .badRequest)
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
    }

    @MainActor
    func testLocalHTTPServerServesRuntimeStatusOverLoopback() async throws {
        let (server, port) = try await makeStartedServer(token: "dev-token")
        defer {
            server.stop()
        }

        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/runtime/status")))
        request.setValue("dev-token", forHTTPHeaderField: "X-Runtime-Control-Token")

        let (data, response) = try await fetchWithRetry(request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let status = try JSONDecoder().decode(RuntimeStatus.self, from: data)

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(status.runtimeState, .healthy)
        XCTAssertEqual(status.runtimeVersion, "1.2.3")
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
            configuration: RuntimeControlLocalHTTPServerConfiguration(port: port),
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

        let (_, response) = try await fetchWithRetry(request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)

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

        let (_, response) = try await fetchWithRetry(request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)

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

        let (_, response) = try await fetchWithRetry(request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)

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

        let (_, response) = try await fetchWithRetry(request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)

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

        let (data, response) = try await fetchWithRetry(request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
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

        let (data, response) = try await fetchWithRetry(request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
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

        let (data, response) = try await fetchWithRetry(request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
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

    private func openAPIDocument() throws -> [String: Any] {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repoRoot = packageRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("docs")
            .appendingPathComponent("macos-runtime")
            .appendingPathComponent("runtime-control.openapi.json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    private func fetchWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }

        var lastError: Error?
        for _ in 0..<20 {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        throw try XCTUnwrap(lastError)
    }

    @MainActor
    private func makeStartedServer(
        token: String,
        servesDevConsole: Bool = false
    ) async throws -> (RuntimeControlLocalHTTPServer, UInt16) {
        for port in UInt16(18_400)...UInt16(18_450) {
            let server = RuntimeControlLocalHTTPServer(
                configuration: RuntimeControlLocalHTTPServerConfiguration(
                    port: port,
                    servesDevConsole: servesDevConsole
                ),
                router: RuntimeControlAPIRouter(
                    handler: StubRuntimeControlAPIReadHandler(),
                    authorization: RuntimeControlAPIAuthorization(token: token)
                )
            )
            do {
                try server.start()
                try await waitForStartedServer(port: port, token: token)
                return (server, port)
            } catch {
                server.stop()
            }
        }
        throw RuntimeControlLocalHTTPServerError.listenerUnavailable
    }

    @MainActor
    private func waitForStartedServer(port: UInt16, token: String) async throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/runtime/status")))
        request.setValue(token, forHTTPHeaderField: "X-Runtime-Control-Token")
        _ = try await fetchWithRetry(request)
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
                .unsupportedFileReference(expected),
                file: file,
                line: line
            )
        }
    }
}

private extension Data {
    func text() throws -> String {
        try XCTUnwrap(String(data: self, encoding: .utf8))
    }
}

private enum RuntimeControlAPIEndpointTestError: Error {
    case expectedStream
}

private struct StubRuntimeControlAPIReadHandler: RuntimeControlAPIReadHandler {
    func loadCapabilities() async throws -> RuntimeControlCapabilities {
        RuntimeControlCapabilities()
    }

    func loadStatus() async throws -> RuntimeStatus {
        RuntimeStatus(
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
        RuntimeEventHistory(events: [
            RuntimeEventDocument(
                id: "event-1",
                eventType: .statusChanged,
                timestamp: "2026-05-24T00:00:00Z",
                product: "TiroshVitalServer",
                status: .healthy,
                previousStatus: nil,
                operation: .health,
                message: "ready",
                runtimeVersion: "1.2.3",
                failureReasons: [],
                containerObservation: nil,
                progress: nil
            ),
        ])
    }

    func loadVitalDBObservationSnapshot() async throws -> RuntimeVitalDBObservationSnapshot {
        .loaded(VitalDBObservationDocument(
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
            redisBackupsPath: "/runtime/home/data/backups/redis"
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

    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "settings \(settings.cpuCount)", stderr: ""))
    }

    func startRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "start services", stderr: ""))
    }

    func stopRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "stop services", stderr: ""))
    }

    func repairRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "repair runtime", stderr: ""))
    }

    func repairProxy(proxyPort: Int) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "repair proxy \(proxyPort)", stderr: ""))
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

    func deleteBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: "delete \(backup.value)", stderr: ""))
    }

    func exportLogs(destination: RuntimeControlFileReference) async throws -> RuntimeLogExportResult {
        RuntimeLogExportResult(destination: URL(fileURLWithPath: destination.value))
    }

    func uninstallRuntime(clean: Bool) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: RuntimeCommandResult(exitCode: 0, stdout: clean ? "clean uninstall" : "uninstall", stderr: ""))
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

@MainActor
private final class FakeRuntimeControlClient: RuntimeControlClient, RuntimeHostClient {
    var capabilities = RuntimeControlCapabilities(canOpenLocalFiles: false)
    var loadSettingsCount = 0
    var createRedisBackupCount = 0
    var loadRedisBackupsCount = 0
    var statusSettings: [RuntimeSettings] = []
    var healthSettings: [RuntimeSettings] = []
    var eventQueries: [RuntimeEventQuery] = []
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
                product: "TiroshVitalServer",
                status: .healthy,
                previousStatus: nil,
                operation: .health,
                message: "ready",
                runtimeVersion: "1.2.3",
                failureReasons: [],
                containerObservation: nil,
                progress: nil
            ),
            RuntimeEventDocument(
                id: "event-2",
                eventType: .containerObserved,
                timestamp: "2026-05-24T00:01:00Z",
                product: "TiroshVitalServer",
                status: .healthy,
                previousStatus: nil,
                operation: .health,
                message: "container observed",
                runtimeVersion: "1.2.3",
                failureReasons: [],
                containerObservation: nil,
                progress: nil
            ),
            RuntimeEventDocument(
                id: "event-3",
                eventType: .auditProxyObserved,
                timestamp: "2026-05-24T00:02:00Z",
                product: "TiroshVitalServer",
                status: .healthy,
                previousStatus: nil,
                operation: .health,
                message: "audit proxy observed",
                runtimeVersion: "1.2.3",
                failureReasons: [],
                containerObservation: nil,
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

    func loadVitalDBObservation() -> VitalDBObservationDocument? {
        vitalDBObservation
    }

    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        vitalDBObservationSnapshot ?? RuntimeVitalDBObservationSnapshot.fromOptional(vitalDBObservation)
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        RuntimeVitalRecorderHistory(observations: [loadVitalDBObservation()].compactMap { $0 })
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

    func updateBundleSummary(url: URL) -> String {
        "summary \(url.path)"
    }

    func logText(sourceID: RuntimeLogSource, helperMessage: String, lineLimit: Int) -> String {
        helperMessage
    }

    func loadLogText(sourceID: RuntimeLogSource, helperMessage: String, lineLimit: Int) async -> String {
        helperMessage
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

    func uninstallRuntime(clean: Bool) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: clean ? "clean uninstall" : "uninstall", stderr: "")
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "settings \(settings.cpuCount)", stderr: "")
    }

    func repairProxy(proxyPort: Int) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "repair proxy \(proxyPort)", stderr: "")
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

    func startRuntimeServices() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "start services", stderr: "")
    }

    func stopRuntimeServices() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "stop services", stderr: "")
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
            packageIdentifier: "com.tirosh.vitalserver.vm",
            runtimeHomePath: "/runtime",
            backupsPath: "/backups",
            redisBackupsPath: "/runtime/data/backups/redis"
        )
    }

    func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "apply \(url.path)", stderr: "")
    }

    func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "rollback \(backupURL.path)", stderr: "")
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
