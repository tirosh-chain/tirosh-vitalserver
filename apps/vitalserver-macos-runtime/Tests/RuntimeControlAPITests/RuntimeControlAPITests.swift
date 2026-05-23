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
}
