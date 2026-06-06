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
        let pausedSession = try await controller.pauseVirtualRecorders(sessionID: nil)
        let resumedSession = try await controller.resumeVirtualRecorders(sessionID: nil)
        let stoppedSession = try await controller.stopVirtualRecorders(sessionID: nil)
        let restartedSession = try await controller.restartVirtualRecorders(sessionID: "session-1", bedRoomNames: ["OR-2"])
        let deletedSession = try await controller.deleteVirtualRecorders(sessionID: nil)
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

        XCTAssertTrue(TestKitURLProtocol.requests.contains { $0.method == "POST" && $0.path == "/sessions" })
        XCTAssertTrue(TestKitURLProtocol.requests.contains { $0.method == "DELETE" && $0.path == "/beds" })
        XCTAssertTrue(TestKitURLProtocol.requests.contains { $0.method == "POST" && $0.path == "/recorders/delete" })
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
            generateFrames: true
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
        let body = request.httpBody ?? Data()
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
