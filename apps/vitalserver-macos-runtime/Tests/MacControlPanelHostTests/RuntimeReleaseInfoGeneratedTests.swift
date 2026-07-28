import Foundation
import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeReleaseInfoGeneratedTests: XCTestCase {
    func testGeneratedReleaseInfoUsesGeneratedServiceDisplayNames() {
        let services = RuntimeReleaseInfo.generated.services

        let expectedNames = [
            GeneratedRelease.vitalServerName,
            GeneratedRelease.recorderIngressName,
            GeneratedRelease.recorderRecoveryName,
            GeneratedRelease.vitalDBObserverName,
            GeneratedRelease.redisRelayName,
            GeneratedRelease.labName,
            GeneratedRelease.redisName,
            GeneratedRelease.postgresName,
            GeneratedRelease.redisUIName,
            GeneratedRelease.swaggerUIName,
            GeneratedRelease.guestEdgeName,
            GeneratedRelease.hostProxyName,
        ]

        XCTAssertEqual(services.map(\.name), expectedNames)
        XCTAssertFalse(services.map(\.image).contains { $0.contains("testkit") })
    }

    func testGeneratedReleaseInfoDoesNotExposeAnUpdaterVersionGate() throws {
        let encoded = try JSONEncoder().encode(RuntimeReleaseInfo.generated)
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertNil(document["minimumUpdaterVersion"])
    }
}
