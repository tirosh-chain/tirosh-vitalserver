import Contracts
import Foundation
import RuntimeControl
@testable import OutboundAdapters
import XCTest

final class RuntimeControlAPIPlatformStateReaderTests: XCTestCase {
    func testPlatformStateUsesPlatformAgentContractWithoutSettingsDerivedState() throws {
        let expected = PlatformState(
            runtimeInstallationState: .executable,
            readIssues: [],
            installedVersion: "0.2.0",
            runtimeEndpoint: "192.0.2.10",
            dataDirectoryStatsError: "data directory missing"
        )
        let client = PlatformStateHTTPClient(responses: [jsonResponse(expected)])
        let reader = try RuntimeControlAPIPlatformStateReader(
            baseURL: "http://127.0.0.1:18321/",
            httpClient: client
        )

        let actual = reader.loadPlatformState(
            settings: RuntimeSettings(vitalFilesDirectory: "/Users/Shared/should-not-be-read")
        )

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(client.requests.map { $0.url?.path }, ["/platform"])
    }

    func testHealthStatusUsesPlatformAgentHealthContract() async throws {
        let expected = PlatformState(
            runtimeInstallationState: .executable,
            readIssues: [PlatformStateReadIssue(source: "guestHTTP", message: "timeout")]
        )
        let client = PlatformStateHTTPClient(responses: [jsonResponse(expected)])
        let reader = try RuntimeControlAPIPlatformStateReader(
            baseURL: "http://127.0.0.1:18321/",
            httpClient: client
        )

        let actual = await reader.loadHealthStatus(settings: RuntimeSettings())

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(client.requests.map { $0.url?.path }, ["/platform/health"])
    }

    func testHTTPFailureIsAnExplicitFailedPlatformRead() throws {
        let client = PlatformStateHTTPClient(responses: [
            RuntimeControlClientHTTPResponse(statusCode: 503, data: Data("unavailable".utf8))
        ])
        let reader = try RuntimeControlAPIPlatformStateReader(
            baseURL: "http://127.0.0.1:18321/",
            httpClient: client
        )

        let state = reader.loadPlatformState(settings: RuntimeSettings())

        guard case .inspectFailed(let reason) = state.runtimeInstallationState else {
            return XCTFail("expected explicit failed installation-state read")
        }
        XCTAssertTrue(reason.contains("statusCode=503"))
        XCTAssertEqual(state.readIssues.map(\.source), ["platformState"])
        XCTAssertTrue(state.readIssues[0].message.contains("statusCode=503"))
        XCTAssertNil(state.dataDirectoryStats)
        XCTAssertNil(state.runtimeEndpoint)
    }

    func testOperationStateReadsCompletePlatformAgentContract() throws {
        let expected = PlatformOperationState(
            activeOperation: nil,
            install: .unavailable(),
            lease: .unavailable(),
            workflow: .unavailable(),
            stableUpdate: .missing()
        )
        let client = PlatformStateHTTPClient(responses: [jsonResponse(expected)])
        let reader = try RuntimeControlAPIOperationStateReader(
            baseURL: "http://127.0.0.1:18321/",
            httpClient: client
        )

        XCTAssertEqual(reader.loadOperationState(), expected)
        XCTAssertEqual(client.requests.map { $0.url?.path }, ["/platform/operations"])
    }

    func testOperationStateHTTPFailurePreservesStableUpdateAsUnavailable() throws {
        let client = PlatformStateHTTPClient(responses: [
            RuntimeControlClientHTTPResponse(statusCode: 503, data: Data("unavailable".utf8))
        ])
        let reader = try RuntimeControlAPIOperationStateReader(
            baseURL: "http://127.0.0.1:18321/",
            httpClient: client
        )

        let actual = reader.loadOperationState()

        XCTAssertEqual(actual.stableUpdate.state, .unavailable)
        XCTAssertTrue(actual.stableUpdate.readError?.contains("statusCode=503") == true)
    }

    private func jsonResponse<T: Encodable>(_ value: T) -> RuntimeControlClientHTTPResponse {
        RuntimeControlClientHTTPResponse(statusCode: 200, data: try! JSONEncoder().encode(value))
    }
}

private final class PlatformStateHTTPClient: RuntimeControlClientHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [RuntimeControlClientHTTPResponse]
    private var capturedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    init(responses: [RuntimeControlClientHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) throws -> RuntimeControlClientHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        capturedRequests.append(request)
        return responses.removeFirst()
    }
}
