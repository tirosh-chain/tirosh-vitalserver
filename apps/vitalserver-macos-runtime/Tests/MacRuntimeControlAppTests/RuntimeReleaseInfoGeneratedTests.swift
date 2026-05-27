import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeReleaseInfoGeneratedTests: XCTestCase {
    func testGeneratedReleaseInfoUsesGeneratedServiceDisplayNames() {
        let services = RuntimeReleaseInfo.generated.services

        XCTAssertEqual(services.map(\.name), [
            GeneratedRelease.vitalServerName,
            GeneratedRelease.auditProxyName,
            GeneratedRelease.vitalDBObserverName,
            GeneratedRelease.redisName,
            GeneratedRelease.redisUIName,
            GeneratedRelease.swaggerUIName,
            GeneratedRelease.guestEdgeName,
            GeneratedRelease.hostProxyName,
        ])
    }
}
