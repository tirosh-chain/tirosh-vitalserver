import Application
import Contracts
import Foundation
import RuntimeControl
@testable import OutboundAdapters
import XCTest

final class RuntimeControlAPIOperationLeaseOwnerTests: XCTestCase {
    func testLoadOperationLeaseReadsPlatformOperationStateAPI() throws {
        let lease = operationLeaseDocument()
        let state = PlatformOperationState(
            activeOperation: nil,
            install: .unavailable(),
            lease: .loaded(lease)
        )
        let client = CapturingRuntimeControlClientHTTPClient(response: jsonResponse(state))
        let owner = try RuntimeControlAPIOperationLeaseOwner(
            baseURL: "http://127.0.0.1:18321/",
            token: "token",
            httpClient: client
        )

        XCTAssertEqual(owner.loadOperationLease(), .loaded(lease))
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/platform/operations")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Runtime-Control-Token"), "token")
    }

    func testUnavailableLeaseMapsToMissing() throws {
        let state = PlatformOperationState(
            activeOperation: nil,
            install: .unavailable(),
            lease: .unavailable()
        )
        let owner = try RuntimeControlAPIOperationLeaseOwner(
            httpClient: CapturingRuntimeControlClientHTTPClient(response: jsonResponse(state))
        )

        XCTAssertEqual(owner.loadOperationLease(), .missing)
    }

    func testFailedLeasePreservesReadFailure() throws {
        let state = PlatformOperationState(
            activeOperation: nil,
            install: .unavailable(),
            lease: .failed(readError: "postgres read failed")
        )
        let owner = try RuntimeControlAPIOperationLeaseOwner(
            httpClient: CapturingRuntimeControlClientHTTPClient(response: jsonResponse(state))
        )

        XCTAssertEqual(owner.loadOperationLease(), .failed("postgres read failed"))
    }

    func testAcquireHeartbeatAndReleasePostOwnerMutationRoutes() throws {
        let lease = operationLeaseDocument()
        let client = CapturingRuntimeControlClientHTTPClient(responses: [
            jsonResponse(RuntimeOperationLeaseMutationResponse(operationId: lease.operationId, state: .acquired)),
            jsonResponse(RuntimeOperationLeaseMutationResponse(operationId: lease.operationId, state: .heartbeatRecorded)),
            jsonResponse(RuntimeOperationLeaseMutationResponse(operationId: lease.operationId, state: .released)),
        ])
        let owner = try RuntimeControlAPIOperationLeaseOwner(
            baseURL: "http://127.0.0.1:18321/",
            token: "token",
            httpClient: client
        )

        try owner.acquire(lease)
        try owner.heartbeat(
            operationId: lease.operationId,
            heartbeatAt: "2026-07-09T00:01:00Z",
            expiresAt: "2026-07-09T00:06:00Z"
        )
        try owner.release(operationId: lease.operationId)

        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST", "POST", "POST"])
        XCTAssertEqual(client.requests.map { $0.url?.path }, [
            "/platform/operations/lease/acquire",
            "/platform/operations/lease/heartbeat",
            "/platform/operations/lease/release",
        ])
        XCTAssertTrue(try XCTUnwrap(client.requests[0].httpBody).contains(Data(#""operationId":"operation-1""#.utf8)))
        XCTAssertTrue(try XCTUnwrap(client.requests[1].httpBody).contains(Data(#""heartbeatAt":"2026-07-09T00:01:00Z""#.utf8)))
        XCTAssertTrue(try XCTUnwrap(client.requests[2].httpBody).contains(Data(#""operationId":"operation-1""#.utf8)))
    }

    func testHTTPFailureDoesNotBecomeMissingLease() throws {
        let owner = try RuntimeControlAPIOperationLeaseOwner(
            httpClient: CapturingRuntimeControlClientHTTPClient(response: RuntimeControlClientHTTPResponse(
                statusCode: 503,
                data: Data("service unavailable".utf8)
            ))
        )

        guard case .failed(let reason) = owner.loadOperationLease() else {
            return XCTFail("expected failed lease read")
        }
        XCTAssertTrue(reason.contains("statusCode=503"))
        XCTAssertTrue(reason.contains("service unavailable"))
    }

    private func operationLeaseDocument() -> RuntimeOperationLeaseDocument {
        RuntimeOperationLeaseDocument(
            operationId: "operation-1",
            operation: .applyBundle,
            ownerPID: 123,
            startedAt: "2026-07-09T00:00:00Z",
            heartbeatAt: "2026-07-09T00:00:00Z",
            expiresAt: "2026-07-09T00:05:00Z",
            message: "applying bundle"
        )
    }

    private func jsonResponse<T: Encodable>(_ value: T) -> RuntimeControlClientHTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return RuntimeControlClientHTTPResponse(
            statusCode: 200,
            data: try! encoder.encode(value)
        )
    }
}

private final class CapturingRuntimeControlClientHTTPClient: RuntimeControlClientHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [RuntimeControlClientHTTPResponse]
    private var capturedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    init(response: RuntimeControlClientHTTPResponse) {
        self.responses = [response]
    }

    init(responses: [RuntimeControlClientHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) throws -> RuntimeControlClientHTTPResponse {
        lock.lock()
        capturedRequests.append(request)
        let response = responses.isEmpty ? RuntimeControlClientHTTPResponse(statusCode: 500, data: Data()) : responses.removeFirst()
        lock.unlock()
        return response
    }
}
