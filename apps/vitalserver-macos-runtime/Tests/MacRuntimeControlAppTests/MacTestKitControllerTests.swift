import Contracts
@testable import MacHostRuntimeAdapter
import RuntimeControl
import XCTest

@MainActor
final class MacTestKitControllerTests: XCTestCase {
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
    }
}
