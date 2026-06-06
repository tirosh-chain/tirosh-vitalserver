import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeReleaseInfoGeneratedTests: XCTestCase {
    func testGeneratedReleaseInfoUsesGeneratedServiceDisplayNames() {
        let services = RuntimeReleaseInfo.generated.services

        var expectedNames = [
            GeneratedRelease.vitalServerName,
            GeneratedRelease.auditProxyName,
            GeneratedRelease.vitalDBObserverName,
            GeneratedRelease.redisName,
            GeneratedRelease.redisUIName,
            GeneratedRelease.swaggerUIName,
            GeneratedRelease.guestEdgeName,
            GeneratedRelease.hostProxyName,
        ]
        if GeneratedRelease.testkitContainerIncluded {
            expectedNames.append(GeneratedRelease.testkitName)
        }

        XCTAssertEqual(services.map(\.name), expectedNames)
    }
}
