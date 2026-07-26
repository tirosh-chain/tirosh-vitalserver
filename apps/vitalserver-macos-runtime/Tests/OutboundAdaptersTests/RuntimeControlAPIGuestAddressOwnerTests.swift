import Contracts
import Foundation
import RuntimeControl
@testable import OutboundAdapters
import XCTest

final class RuntimeControlAPIGuestAddressOwnerTests: XCTestCase {
    func testLoadGuestAddressResourceReadsHostOwnerAPI() throws {
        let read = RuntimeGuestAddressReadResult.loaded(address: "192.168.64.10", source: .platformAgent)
        let client = GuestAddressCapturingRuntimeControlClientHTTPClient(response: jsonResponse(
            RuntimeGuestAddressResourceState.loaded(read)
        ))
        let owner = try RuntimeControlAPIGuestAddressOwner(
            baseURL: "http://127.0.0.1:18321/",
            token: "token",
            httpClient: client
        )

        XCTAssertEqual(try owner.loadGuestAddressResource(), .loaded(read))
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/platform/runtime-endpoint")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Runtime-Control-Token"), "token")
    }

    func testPutGuestAddressResourceWritesHostOwnerAPI() throws {
        let read = RuntimeGuestAddressReadResult.loaded(address: "192.168.64.11", source: .platformAgent)
        let client = GuestAddressCapturingRuntimeControlClientHTTPClient(response: jsonResponse(
            RuntimeGuestAddressResourceState.loaded(read)
        ))
        let owner = try RuntimeControlAPIGuestAddressOwner(
            baseURL: "http://127.0.0.1:18321/",
            token: "token",
            httpClient: client
        )

        XCTAssertEqual(try owner.putGuestAddressResource(address: "192.168.64.11"), .loaded(read))
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/platform/runtime-endpoint")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(try XCTUnwrap(request.httpBody).contains(Data(#""address":"192.168.64.11""#.utf8)))
    }

    func testHTTPFailureDoesNotBecomeMissingResource() throws {
        let owner = try RuntimeControlAPIGuestAddressOwner(
            token: "token",
            httpClient: GuestAddressCapturingRuntimeControlClientHTTPClient(response: RuntimeControlClientHTTPResponse(
                statusCode: 503,
                data: Data("service unavailable".utf8)
            ))
        )

        XCTAssertThrowsError(try owner.loadGuestAddressResource()) { error in
            let description = String(describing: error)
            XCTAssertTrue(description.contains("statusCode=503"))
            XCTAssertTrue(description.contains("service unavailable"))
        }
    }

    func testLoadedWithoutReadResultIsInvalidResourceState() throws {
        let owner = try RuntimeControlAPIGuestAddressOwner(
            token: "token",
            httpClient: GuestAddressCapturingRuntimeControlClientHTTPClient(response: jsonResponse(
                RuntimeGuestAddressResourceState(state: .loaded, read: nil)
            ))
        )

        XCTAssertThrowsError(try owner.loadGuestAddressResource()) { error in
            XCTAssertTrue(String(describing: error).contains("state=loaded has no Guest address read result"))
        }
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

private final class GuestAddressCapturingRuntimeControlClientHTTPClient: RuntimeControlClientHTTPClient, @unchecked Sendable {
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

    func send(_ request: URLRequest) throws -> RuntimeControlClientHTTPResponse {
        lock.lock()
        capturedRequests.append(request)
        let response = responses.isEmpty ? RuntimeControlClientHTTPResponse(statusCode: 500, data: Data()) : responses.removeFirst()
        lock.unlock()
        return response
    }
}
