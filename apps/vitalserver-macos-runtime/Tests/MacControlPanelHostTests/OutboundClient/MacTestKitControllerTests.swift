import Contracts
@testable import OutboundAdapters
import RuntimeControl
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class MacTestKitControllerTests: XCTestCase {
    override func tearDown() {
        TestKitURLProtocol.stop()
        super.tearDown()
    }

    func testExplicitAPIEndpointDoesNotRequireRuntimeStatusVMIP() async {
        let controller = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .explicit(baseURL: "http://127.0.0.1:18322/")
            ),
            statusProvider: { RuntimeStatus(vmIP: nil) },
            apiHealthCheck: { _ in false }
        )

        let status = await controller.loadTestKitStatus()

        XCTAssertEqual(status.apiBaseURL, "http://127.0.0.1:18322")
        XCTAssertEqual(status.state, .stopped)
        XCTAssertFalse(status.lastError?.contains("VM IP") ?? false)
        XCTAssertEqual(status.readIssues.map(\.source), ["testKitAPI", "containerService"])
    }

    func testRuntimeStatusVMIPEndpointReportsMissingVMIP() async {
        let controller = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .runtimeStatusVMIP(port: 18322)
            ),
            statusProvider: { RuntimeStatus(vmIP: nil) },
            apiHealthCheck: { _ in true }
        )

        let status = await controller.loadTestKitStatus()

        XCTAssertNil(status.apiBaseURL)
        XCTAssertEqual(status.state, .failed)
        XCTAssertEqual(
            status.lastError,
            "TestKit container API is unavailable because the VM IP is not known yet."
        )
        XCTAssertEqual(status.readIssues, [
            RuntimeTestKitReadIssue(
                source: "apiEndpoint",
                message: "TestKit container API is unavailable because the VM IP is not known yet."
            ),
        ])
    }

    func testExplicitEmptyAPIEndpointReportsConfiguredEndpointUnavailable() async {
        let controller = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .explicit(baseURL: "///")
            ),
            statusProvider: { RuntimeStatus(vmIP: "192.168.64.8") },
            apiHealthCheck: { _ in true }
        )

        let status = await controller.loadTestKitStatus()

        XCTAssertNil(status.apiBaseURL)
        XCTAssertEqual(status.state, .failed)
        XCTAssertEqual(status.lastError, "TestKit container API endpoint is not configured.")
        XCTAssertEqual(status.readIssues, [
            RuntimeTestKitReadIssue(
                source: "apiEndpoint",
                message: "TestKit container API endpoint is not configured."
            ),
        ])
    }

    func testMutationUsesEndpointResolutionFailureReason() async {
        let controller = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .runtimeStatusVMIP(port: 18322)
            ),
            statusProvider: { RuntimeStatus(vmIP: nil) },
            apiHealthCheck: { _ in true }
        )

        do {
            _ = try await controller.createTestKitBeds(RuntimeTestKitCreateBedsRequest(count: 1))
            XCTFail("Expected missing VM IP endpoint failure")
        } catch let error as MacTestKitControllerError {
            XCTAssertEqual(
                error,
                .apiEndpointUnavailable("TestKit container API is unavailable because the VM IP is not known yet.")
            )
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testControllerUsesInjectedHTTPClientForHealthSessionsAndBeds() async throws {
        let client = FakeMacTestKitHTTPClient()
        let session = testKitSession(id: "session-1", state: "running", bedRoomNames: ["OR-1"])
        client.register(method: "GET", path: "/health", data: Data())
        client.register(method: "GET", path: "/sessions", data: try JSONEncoder().encode(TestKitSessionsPayload(sessions: [session])))
        client.register(
            method: "GET",
            path: "/beds",
            data: try JSONEncoder().encode(TestKitBedsPayload(beds: [
                RuntimeTestKitBed(roomName: "OR-1", bedID: "bed-1"),
            ]))
        )
        let controller = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .explicit(baseURL: "http://testkit.local"),
                recorderTargetURL: "http://edge/"
            ),
            statusProvider: { RuntimeStatus(vmIP: nil) },
            httpClient: client,
            apiHealthCheck: nil
        )

        let status = await controller.loadTestKitStatus()

        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.activeSession?.id, "session-1")
        XCTAssertEqual(client.requests.map(\.path), ["/health", "/sessions", "/beds"])
    }

    func testDefaultHealthCheckPreservesHTTPFailureReason() async throws {
        let client = FakeMacTestKitHTTPClient()
        client.register(method: "GET", path: "/health", statusCode: 503, data: Data("unavailable".utf8))
        let controller = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .explicit(baseURL: "http://testkit.local")
            ),
            statusProvider: {
                RuntimeStatus(
                    vmIP: nil,
                    containerObservation: RuntimeContainerObservation(
                        auditProxyHTTP: "200",
                        auditProxyStatus: nil,
                        containerLogsPresent: false,
                        containerLogsBytes: nil,
                        composeServices: [
                            RuntimeContainerServiceObservation(
                                service: "testkit",
                                state: "running",
                                health: "unhealthy"
                            ),
                        ]
                    )
                )
            },
            httpClient: client,
            apiHealthCheck: nil
        )

        let status = await controller.loadTestKitStatus()

        XCTAssertEqual(status.state, .starting)
        XCTAssertTrue(status.lastError?.contains("Health check: health endpoint returned HTTP 503.") == true)
        XCTAssertEqual(status.readIssues.map(\.source), ["testKitAPI", "testKitAPI.health"])
        XCTAssertEqual(status.readIssues.last?.message, "health endpoint returned HTTP 503")
    }

    func testInvalidAPIEndpointIsReportedAsHealthReadIssueInsteadOfCrashing() async {
        let controller = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .explicit(baseURL: "http://[::1")
            ),
            statusProvider: {
                RuntimeStatus(
                    vmIP: nil,
                    containerObservation: RuntimeContainerObservation(
                        auditProxyHTTP: "200",
                        auditProxyStatus: nil,
                        containerLogsPresent: false,
                        containerLogsBytes: nil,
                        composeServices: [
                            RuntimeContainerServiceObservation(
                                service: "testkit",
                                state: "running",
                                health: "healthy"
                            ),
                        ]
                    )
                )
            },
            httpClient: FakeMacTestKitHTTPClient(),
            apiHealthCheck: nil
        )

        let status = await controller.loadTestKitStatus()

        XCTAssertEqual(status.state, .starting)
        XCTAssertEqual(status.apiBaseURL, "http://[::1")
        XCTAssertTrue(status.lastError?.contains("TestKit API request URL is invalid") == true)
        XCTAssertEqual(status.readIssues.map(\.source), ["testKitAPI", "testKitAPI.health"])
        XCTAssertEqual(
            status.readIssues.last?.message,
            "TestKit API request URL is invalid baseURL=http://[::1 path=/health"
        )
    }

    func testHealthyAPIEndpointLoadsSessionsAndBeds() async throws {
        TestKitURLProtocol.start()
        let session = testKitSession(id: "session-1", state: "running", bedRoomNames: ["OR-1"])
        TestKitURLProtocol.register(method: "GET", path: "/sessions") {
            try Self.jsonResponse(["sessions": [session]])
        }
        TestKitURLProtocol.register(method: "GET", path: "/beds") {
            try Self.jsonResponse(["beds": [RuntimeTestKitBed(roomName: "OR-1", bedID: "bed-1")]])
        }
        let controller = makeHTTPController()

        let status = await controller.loadTestKitStatus()

        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.activeSession?.id, "session-1")
        XCTAssertEqual(status.sessions.map(\.id), ["session-1"])
        XCTAssertEqual(status.beds.map(\.roomName), ["OR-1"])
        XCTAssertNil(status.lastError)
    }

    func testControllerSendsMutationRequests() async throws {
        TestKitURLProtocol.start()
        let session = testKitSession(id: "session-1", state: "running", bedRoomNames: ["OR-1"])
        let restarted = testKitSession(id: "session-2", state: "running", bedRoomNames: ["OR-2"])
        let bed = RuntimeTestKitBed(roomName: "OR-1", bedID: "bed-1")
        TestKitURLProtocol.register(method: "GET", path: "/sessions") {
            try Self.jsonResponse(["sessions": [session]])
        }
        TestKitURLProtocol.register(method: "GET", path: "/beds") {
            try Self.jsonResponse(["beds": [bed]])
        }
        TestKitURLProtocol.register(method: "POST", path: "/beds") {
            try Self.jsonResponse(["beds": [bed]])
        }
        TestKitURLProtocol.register(method: "POST", path: "/beds/delete") {
            try Self.jsonResponse(["beds": [bed]])
        }
        TestKitURLProtocol.register(method: "DELETE", path: "/beds") {
            try Self.jsonResponse(["beds": [bed]])
        }
        TestKitURLProtocol.register(method: "POST", path: "/sessions") {
            try Self.jsonResponse(session)
        }
        TestKitURLProtocol.register(method: "POST", path: "/sessions/session-1/pause") {
            try Self.jsonResponse(session)
        }
        TestKitURLProtocol.register(method: "POST", path: "/sessions/session-1/resume") {
            try Self.jsonResponse(session)
        }
        TestKitURLProtocol.register(method: "POST", path: "/sessions/session-1/stop") {
            try Self.jsonResponse(session)
        }
        TestKitURLProtocol.register(method: "POST", path: "/sessions/session-1/restart") {
            try Self.jsonResponse(restarted)
        }
        TestKitURLProtocol.register(method: "DELETE", path: "/sessions/session-2") {
            try Self.jsonResponse(restarted)
        }
        TestKitURLProtocol.register(method: "POST", path: "/recorders/delete") {
            try Self.jsonResponse(RuntimeTestKitRecorderDeletion(
                vrcode: "VR_ORPHAN",
                targetURL: "http://edge/",
                deleted: true
            ))
        }
        TestKitURLProtocol.register(method: "DELETE", path: "/sessions") {
            try Self.jsonResponse(TestKitSessionsPayload(sessions: []))
        }
        let controller = makeHTTPController()

        let createdBeds = try await controller.createTestKitBeds(RuntimeTestKitCreateBedsRequest(count: 1))
        let deletedBeds = try await controller.deleteTestKitBeds(RuntimeTestKitDeleteBedsRequest(roomNames: ["OR-1"]))
        let resetBeds = try await controller.resetTestKitBeds()
        let startedSession = try await controller.startVirtualRecorders(startRequest())
        let pausedSession = try await controller.pauseVirtualRecorders(sessionID: "session-1")
        let resumedSession = try await controller.resumeVirtualRecorders(sessionID: "session-1")
        let stoppedSession = try await controller.stopVirtualRecorders(sessionID: "session-1")
        let restartedSession = try await controller.restartVirtualRecorders(sessionID: "session-1", bedRoomNames: ["OR-2"])
        let deletedSession = try await controller.deleteVirtualRecorders(sessionID: "session-2")
        let recorderDeletion = try await controller.deleteVirtualRecorder(vrcode: "VR_ORPHAN")
        let resetStatus = try await controller.resetVirtualRecorders()

        XCTAssertEqual(createdBeds.map(\.roomName), ["OR-1"])
        XCTAssertEqual(deletedBeds.map(\.roomName), ["OR-1"])
        XCTAssertEqual(resetBeds.map(\.roomName), ["OR-1"])
        XCTAssertEqual(startedSession.id, "session-1")
        XCTAssertEqual(pausedSession?.id, "session-1")
        XCTAssertEqual(resumedSession?.id, "session-1")
        XCTAssertEqual(stoppedSession?.id, "session-1")
        XCTAssertEqual(restartedSession?.id, "session-2")
        XCTAssertEqual(deletedSession?.id, "session-2")
        XCTAssertTrue(recorderDeletion.deleted)
        XCTAssertEqual(resetStatus.state, .running)

        let startRequest = try XCTUnwrap(TestKitURLProtocol.requests.first {
            $0.method == "POST" && $0.path == "/sessions"
        })
        let startBody = try JSONSerialization.jsonObject(with: startRequest.body) as? [String: Any]
        XCTAssertEqual(startBody?["exportVital"] as? Bool, true)
        XCTAssertEqual(startBody?["uploadVital"] as? Bool, true)
        XCTAssertEqual(startBody?["vitalUploadEndpoint"] as? String, "/upload")
        XCTAssertTrue(TestKitURLProtocol.requests.contains { $0.method == "DELETE" && $0.path == "/beds" })
        XCTAssertTrue(TestKitURLProtocol.requests.contains { $0.method == "POST" && $0.path == "/recorders/delete" })
    }

    func testManualVitalUploadRegistersBedsFromFilenamesAndPostsFilesToUploadEndpoint() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = directory.appendingPathComponent("MORC03_260617_120000.vital")
        let second = directory.appendingPathComponent("MORC04_260617_120100.vital")
        try Data([1, 2, 3]).write(to: first)
        try Data([4, 5]).write(to: second)
        defer { try? FileManager.default.removeItem(at: directory) }

        let client = FakeMacTestKitHTTPClient()
        client.register(
            method: "POST",
            path: "/beds",
            data: try JSONEncoder().encode(TestKitBedsPayload(beds: [
                RuntimeTestKitBed(roomName: "MORC03", bedID: "bed-1"),
                RuntimeTestKitBed(roomName: "MORC04", bedID: "bed-2"),
            ]))
        )
        client.register(method: "POST", path: "/upload", data: Data("OK".utf8))
        let controller = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .explicit(baseURL: "http://testkit.local")
            ),
            statusProvider: { RuntimeStatus(vmIP: nil) },
            httpClient: client,
            apiHealthCheck: { _ in true }
        )

        let summary = try await controller.uploadVitalFiles(RuntimeTestKitVitalFileUploadRequest(
            filePaths: [first.path, second.path],
            vitalServerBaseURL: "http://127.0.0.1:18080/",
            endpoint: "/upload"
        ))

        XCTAssertEqual(summary.bedRoomNames, ["MORC03", "MORC04"])
        XCTAssertEqual(summary.uploadedCount, 2)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(client.requests.map { "\($0.method) \($0.path)" }, [
            "POST /beds",
            "POST /upload",
            "POST /upload",
        ])
    }

    func testMutationReportsInvalidAPIEndpointAsTypedError() async throws {
        let controller = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .explicit(baseURL: "http://[::1")
            ),
            statusProvider: { RuntimeStatus(vmIP: nil) },
            httpClient: FakeMacTestKitHTTPClient(),
            apiHealthCheck: { _ in true }
        )

        do {
            _ = try await controller.createTestKitBeds(RuntimeTestKitCreateBedsRequest(count: 1))
            XCTFail("createTestKitBeds must reject invalid API endpoint explicitly")
        } catch let error as MacTestKitControllerError {
            XCTAssertEqual(
                error,
                .invalidRequestURL("TestKit API request URL is invalid baseURL=http://[::1 path=/beds")
            )
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testControllerReportsHTTPFailures() async throws {
        TestKitURLProtocol.start()
        TestKitURLProtocol.register(method: "GET", path: "/sessions") {
            TestKitURLProtocol.Response(statusCode: 500, data: Data("boom".utf8))
        }
        let controller = makeHTTPController()

        let status = await controller.loadTestKitStatus()

        XCTAssertEqual(status.state, .failed)
        XCTAssertEqual(status.lastError, "TestKit container API read failed: boom")
        XCTAssertEqual(status.readIssues, [
            RuntimeTestKitReadIssue(
                source: "containerAPI",
                message: "TestKit container API read failed: boom"
            ),
        ])
    }

    func testControllerReportsInvalidUTF8HTTPFailureBody() async throws {
        TestKitURLProtocol.start()
        TestKitURLProtocol.register(method: "GET", path: "/sessions") {
            TestKitURLProtocol.Response(statusCode: 500, data: Data([0xff]))
        }
        let controller = makeHTTPController()

        let status = await controller.loadTestKitStatus()

        XCTAssertEqual(status.state, .failed)
        XCTAssertEqual(
            status.lastError,
            "TestKit container API read failed: HTTP 500 response body is not valid UTF-8"
        )
        XCTAssertEqual(status.readIssues, [
            RuntimeTestKitReadIssue(
                source: "containerAPI",
                message: "TestKit container API read failed: HTTP 500 response body is not valid UTF-8"
            ),
        ])
    }

    func testControllerReportsMissingServiceStateAndHealth() async {
        let controller = MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .explicit(baseURL: "http://127.0.0.1:18322/")
            ),
            statusProvider: {
                RuntimeStatus(
                    vmIP: nil,
                    containerObservation: RuntimeContainerObservation(
                        auditProxyHTTP: "200",
                        auditProxyStatus: nil,
                        containerLogsPresent: false,
                        containerLogsBytes: nil,
                        composeServices: [
                            RuntimeContainerServiceObservation(service: "testkit"),
                        ]
                    )
                )
            },
            apiHealthCheck: { _ in false }
        )

        let status = await controller.loadTestKitStatus()

        XCTAssertEqual(status.state, .stopped)
        XCTAssertEqual(status.readIssues.map(\.source), [
            "testKitAPI",
            "containerService.state",
            "containerService.health",
        ])
    }

    func testSessionMutationRequiresExplicitSessionID() async throws {
        let controller = makeHTTPController()

        do {
            _ = try await controller.pauseVirtualRecorders(sessionID: nil)
            XCTFail("pauseVirtualRecorders must require an explicit session ID")
        } catch let error as MacTestKitControllerError {
            XCTAssertEqual(error, .missingSessionID)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func makeHTTPController() -> MacTestKitController {
        MacTestKitController(
            configuration: MacTestKitControllerConfiguration(
                enabled: true,
                apiEndpoint: .explicit(baseURL: "http://testkit.local"),
                recorderTargetURL: "http://edge/"
            ),
            statusProvider: { RuntimeStatus(vmIP: nil) },
            apiHealthCheck: { _ in true }
        )
    }

    private func startRequest() -> RuntimeTestKitVirtualRecorderStartRequest {
        RuntimeTestKitVirtualRecorderStartRequest(
            scenario: .normal,
            signalProfile: .normal,
            recorders: 1,
            bedRoomNames: ["OR-1"],
            vrcode: "VR_TEST",
            version: "testkit",
            intervalSeconds: 1,
            durationSeconds: nil,
            maxMessages: nil,
            shiftTime: true,
            generateFrames: true,
            exportVital: true,
            uploadVital: true,
            vitalUploadEndpoint: "/upload"
        )
    }

    private static func jsonResponse<T: Encodable>(_ value: T) throws -> TestKitURLProtocol.Response {
        TestKitURLProtocol.Response(data: try JSONEncoder().encode(value))
    }
}

private struct TestKitRequestRecord {
    let method: String
    let path: String
    let body: Data
}

private struct TestKitSessionsPayload: Encodable {
    let sessions: [RuntimeTestKitSession]
}

private struct TestKitBedsPayload: Encodable {
    let beds: [RuntimeTestKitBed]
}

private final class FakeMacTestKitHTTPClient: MacTestKitHTTPClient, @unchecked Sendable {
    struct Response {
        var statusCode = 200
        var data: Data
    }

    private let lock = NSLock()
    private var handlers: [String: Response] = [:]
    private var protectedRequests: [TestKitRequestRecord] = []

    var requests: [TestKitRequestRecord] {
        lock.withLock { protectedRequests }
    }

    func register(method: String, path: String, statusCode: Int = 200, data: Data) {
        lock.withLock {
            handlers["\(method) \(path)"] = Response(statusCode: statusCode, data: data)
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await response(for: request)
    }

    func upload(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await response(for: request)
    }

    private func response(for request: URLRequest) async throws -> (Data, URLResponse) {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "/"
        let key = "\(method) \(path)"
        let response = lock.withLock { handlers[key] } ?? Response(statusCode: 404, data: Data("missing mock".utf8))
        let body = requestBodyData(request)
        lock.withLock {
            protectedRequests.append(TestKitRequestRecord(method: method, path: path, body: body))
        }
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response.data, httpResponse)
    }
}

private final class TestKitURLProtocol: URLProtocol {
    struct Response {
        var statusCode = 200
        var data: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: () throws -> Response] = [:]
    nonisolated(unsafe) private static var protectedRequests: [TestKitRequestRecord] = []

    static var requests: [TestKitRequestRecord] {
        lock.withLock { protectedRequests }
    }

    static func start() {
        lock.withLock {
            handlers = [:]
            protectedRequests = []
        }
        URLProtocol.registerClass(Self.self)
    }

    static func stop() {
        URLProtocol.unregisterClass(Self.self)
        lock.withLock {
            handlers = [:]
            protectedRequests = []
        }
    }

    static func register(method: String, path: String, handler: @escaping () throws -> Response) {
        lock.withLock {
            handlers["\(method) \(path)"] = handler
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "testkit.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "/"
        let body = requestBodyData(request)
        let key = "\(method) \(path)"
        let handler = Self.lock.withLock { Self.handlers[key] }
        Self.lock.withLock {
            Self.protectedRequests.append(TestKitRequestRecord(method: method, path: path, body: body))
        }

        do {
            let response = try handler?() ?? Response(statusCode: 404, data: Data("missing mock".utf8))
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBodyData(_ request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}

private func testKitSession(
    id: String,
    state: String,
    bedRoomNames: [String]
) -> RuntimeTestKitSession {
    RuntimeTestKitSession(
        id: id,
        state: state,
        targetURL: "http://edge/",
        recordersRequested: bedRoomNames.count,
        bedsRequested: bedRoomNames.count,
        bedRoomNames: bedRoomNames,
        vrcode: "VR_TEST",
        version: "testkit",
        intervalSeconds: 1,
        durationSeconds: nil,
        maxMessages: nil,
        shiftTime: true,
        generateFrames: true,
        scenario: RuntimeTestKitScenario.normal.rawValue,
        defaultScenario: RuntimeTestKitSignalProfile.normal.rawValue,
        createdAt: 1,
        startedAt: 1,
        stoppedAt: nil,
        messagesSent: 0,
        bytesSent: 0,
        lastError: nil,
        recorders: []
    )
}
