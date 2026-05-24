import Contracts
import Core
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
        XCTAssertTrue(runtimeControlRoutes.allSatisfy { $0.path.hasPrefix("/runtime/") })
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

    func testEndpointMatchingIgnoresQueryString() {
        XCTAssertEqual(
            RuntimeControlAPIEndpoint.matching(method: .get, path: "/runtime/status?refresh=false"),
            .status
        )
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
    func testRouterServesCapabilitiesSettingsHealthReleaseAndInstallInfo() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let capabilities = try await decode(
            RuntimeControlCapabilities.self,
            from: router.route(.init(method: .get, path: "/runtime/capabilities"))
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

        XCTAssertTrue(capabilities.canControlRuntimeServices)
        XCTAssertEqual(settings.cpuCount, 4)
        XCTAssertEqual(health.statusMessage, "healthy")
        XCTAssertEqual(release.helperVersion, "0.1.0")
        XCTAssertEqual(installInfo.runtimeHomePath, "/runtime/home")
        XCTAssertEqual(events.events.map(\.id), ["event-1"])
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
    func testRouterReturnsTypedNotImplementedErrorForKnownWriteEndpoint() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .put, path: "/runtime/settings"))
        let error = try decodeError(from: response)

        XCTAssertEqual(response.status, .notImplemented)
        XCTAssertEqual(error.code, .endpointNotImplemented)
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

        XCTAssertFalse(capabilities.canOpenLocalFiles)
        XCTAssertEqual(settings.cpuCount, 6)
        XCTAssertEqual(status.statusMessage, "status with 6 CPUs")
        XCTAssertEqual(events.events.map(\.id), ["event-1", "event-2", "event-3"])
        XCTAssertEqual(health.statusMessage, "health with 6 CPUs")
        XCTAssertEqual(release.helperVersion, "0.2.0")
        XCTAssertEqual(installInfo.backupsPath, "/backups")
        XCTAssertEqual(client.loadSettingsCount, 3)
        XCTAssertEqual(client.statusSettings, [RuntimeSettings(cpuCount: 6, memoryGiB: 10)])
        XCTAssertEqual(client.healthSettings, [RuntimeSettings(cpuCount: 6, memoryGiB: 10)])
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
    func testRuntimeEventsEndpointRejectsInvalidLimit() async throws {
        let router = RuntimeControlAPIRouter(handler: StubRuntimeControlAPIReadHandler())

        let response = await router.route(.init(method: .get, path: "/runtime/events?limit=zero"))
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

    @MainActor
    func testLocalHTTPServerServesRuntimeStatusOverLoopback() async throws {
        let (server, port) = try makeStartedServer(token: "dev-token")
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
    func testLocalHTTPServerRejectsMissingTokenOverLoopback() async throws {
        let (server, port) = try makeStartedServer(token: "dev-token")
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
    private func makeStartedServer(token: String) throws -> (RuntimeControlLocalHTTPServer, UInt16) {
        for port in UInt16(18_400)...UInt16(18_450) {
            let server = RuntimeControlLocalHTTPServer(
                configuration: RuntimeControlLocalHTTPServerConfiguration(port: port),
                router: RuntimeControlAPIRouter(
                    handler: StubRuntimeControlAPIReadHandler(),
                    authorization: RuntimeControlAPIAuthorization(token: token)
                )
            )
            do {
                try server.start()
                return (server, port)
            } catch {
                server.stop()
            }
        }
        throw RuntimeControlLocalHTTPServerError.listenerUnavailable
    }
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
        RuntimeInstallInfo(runtimeHomePath: "/runtime/home", backupsPath: "/runtime/backups")
    }
}

@MainActor
private final class FakeRuntimeControlClient: RuntimeControlClient {
    var capabilities = RuntimeControlCapabilities(canOpenLocalFiles: false)
    var loadSettingsCount = 0
    var statusSettings: [RuntimeSettings] = []
    var healthSettings: [RuntimeSettings] = []
    var eventQueries: [RuntimeEventQuery] = []

    func loadSettings() -> RuntimeSettings {
        loadSettingsCount += 1
        return RuntimeSettings(cpuCount: 6, memoryGiB: 10)
    }

    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        statusSettings.append(settings)
        return RuntimeStatus(statusMessage: "status with \(settings.cpuCount) CPUs")
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
        return RuntimeEventHistory(events: Array(events.suffix(query.limit)))
    }

    func uninstallRuntime(clean: Bool) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }

    func repairProxy(proxyPort: Int) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }

    func repairDatastore() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }

    func startRuntimeServices() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }

    func stopRuntimeServices() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
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
        RuntimeInstallInfo(runtimeHomePath: "/runtime", backupsPath: "/backups")
    }
}
