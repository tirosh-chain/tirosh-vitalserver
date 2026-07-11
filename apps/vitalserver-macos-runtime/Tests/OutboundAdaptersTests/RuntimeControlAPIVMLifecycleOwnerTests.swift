import Contracts
import Foundation
import RuntimeControl
@testable import OutboundAdapters
import XCTest

final class RuntimeControlAPIVMLifecycleOwnerTests: XCTestCase {
    func testLoadVMLifecycleResourceReadsHostOwnerAPI() throws {
        let document = vmLifecycleDocument()
        let client = VMLifecycleCapturingRuntimeControlClientHTTPClient(response: jsonResponse(
            RuntimeVMLifecycleResourceState.loaded(document)
        ))
        let owner = try RuntimeControlAPIVMLifecycleOwner(
            baseURL: "http://127.0.0.1:18321/",
            token: "token",
            httpClient: client
        )

        XCTAssertEqual(try owner.loadVMLifecycleResource(), .loaded(document))
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/platform/runtime-provider")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Runtime-Control-Token"), "token")
    }

    func testPutVMLifecycleResourceWritesHostOwnerAPI() throws {
        let document = vmLifecycleDocument(state: .bootstrapping, message: "bootstrapping")
        let client = VMLifecycleCapturingRuntimeControlClientHTTPClient(response: jsonResponse(
            RuntimeVMLifecycleResourceState.loaded(document)
        ))
        let owner = try RuntimeControlAPIVMLifecycleOwner(
            baseURL: "http://127.0.0.1:18321/",
            token: "token",
            httpClient: client
        )

        XCTAssertEqual(try owner.putVMLifecycleResource(document), .loaded(document))
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/platform/runtime-provider")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(try XCTUnwrap(request.httpBody).contains(Data(#""message":"bootstrapping""#.utf8)))
    }

    func testMissingResourceStaysMissing() throws {
        let owner = try RuntimeControlAPIVMLifecycleOwner(
            httpClient: VMLifecycleCapturingRuntimeControlClientHTTPClient(response: jsonResponse(
                RuntimeVMLifecycleResourceState.missing(readError: "VM lifecycle document missing")
            ))
        )

        XCTAssertEqual(
            try owner.loadVMLifecycleResource(),
            .missing(readError: "VM lifecycle document missing")
        )
    }

    func testHTTPFailureDoesNotBecomeMissingResource() throws {
        let owner = try RuntimeControlAPIVMLifecycleOwner(
            httpClient: VMLifecycleCapturingRuntimeControlClientHTTPClient(response: RuntimeControlClientHTTPResponse(
                statusCode: 503,
                data: Data("service unavailable".utf8)
            ))
        )

        XCTAssertThrowsError(try owner.loadVMLifecycleResource()) { error in
            let description = String(describing: error)
            XCTAssertTrue(description.contains("statusCode=503"))
            XCTAssertTrue(description.contains("service unavailable"))
        }
    }

    func testLoadedWithoutDocumentIsInvalidResourceState() throws {
        let owner = try RuntimeControlAPIVMLifecycleOwner(
            httpClient: VMLifecycleCapturingRuntimeControlClientHTTPClient(response: jsonResponse(
                RuntimeVMLifecycleResourceState(state: .loaded, document: nil)
            ))
        )

        XCTAssertThrowsError(try owner.loadVMLifecycleResource()) { error in
            XCTAssertTrue(String(describing: error).contains("state=loaded has no VM lifecycle document"))
        }
    }

    private func vmLifecycleDocument(
        state: RuntimeVMLifecycleState = .running,
        message: String = "running"
    ) -> RuntimeVMLifecycleDocument {
        RuntimeVMLifecycleDocument(
            state: state,
            operation: .install,
            operationID: "operation-1",
            bootID: "boot-1",
            startedAt: "2026-07-09T01:00:00Z",
            updatedAt: "2026-07-09T01:01:00Z",
            deadlineAt: nil,
            terminalReason: nil,
            message: message
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

private final class VMLifecycleCapturingRuntimeControlClientHTTPClient: RuntimeControlClientHTTPClient, @unchecked Sendable {
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
