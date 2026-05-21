import RuntimeCore
import XCTest

final class RuntimeHealthEvaluatorTests: XCTestCase {
    func testHealthyInputHasNoFailureReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput())

        XCTAssertTrue(snapshot.isHealthy)
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testMissingArtifactsAndServicesProduceTypedReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            vmExecutable: false,
            proxyExecutable: false,
            rootfsBase: "missing",
            vmDisk: "missing",
            vmService: "not loaded",
            proxyService: "not loaded",
            watchdogService: "not loaded"
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .missingVMBin,
            .missingProxyRunner,
            .missingRootfsBase,
            .missingVMDisk,
            .vmService("not loaded"),
            .proxyService("not loaded"),
            .watchdogService("not loaded"),
        ])
    }

    func testHTTPFailuresIncludeProxyPortAndBootstrapReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            hostProxyHTTP: "502",
            guestHTTP: "bootstrap-pending",
            redisUIHTTP: "failed",
            swaggerUIHTTP: "404",
            proxyPortFailureReasons: [.proxyPortInUse(port: 80, listeners: "nginx-1234")],
            guestBootstrapFailureReason: .guestBootstrapMissingRuntimePackages
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .hostProxyHTTP("502"),
            .proxyPortInUse(port: 80, listeners: "nginx-1234"),
            .redisUIHTTP("failed"),
            .swaggerUIHTTP("404"),
            .guestHTTP("bootstrap-pending"),
            .guestBootstrapMissingRuntimePackages,
        ])
    }

    func testBootstrapReasonIsIgnoredWhenGuestHTTPIsHealthy() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestHTTP: "200",
            guestBootstrapFailureReason: .guestBootstrapFailed
        ))

        XCTAssertTrue(snapshot.isHealthy)
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    private func healthyInput(
        vmExecutable: Bool = true,
        proxyExecutable: Bool = true,
        rootfsBase: String = "present",
        vmDisk: String = "present",
        vmService: String = "loaded",
        proxyService: String = "loaded",
        watchdogService: String = "loaded",
        vmIP: String? = "192.168.64.2",
        proxyPort: Int = 80,
        hostProxyHTTP: String = "200",
        guestHTTP: String = "200",
        redisUIHTTP: String = "200",
        swaggerUIHTTP: String = "200",
        proxyPortFailureReasons: [RuntimeFailureReason] = [],
        guestBootstrapFailureReason: RuntimeFailureReason? = nil
    ) -> RuntimeHealthInput {
        RuntimeHealthInput(
            vmExecutable: vmExecutable,
            proxyExecutable: proxyExecutable,
            rootfsBase: rootfsBase,
            vmDisk: vmDisk,
            vmService: vmService,
            proxyService: proxyService,
            watchdogService: watchdogService,
            vmIP: vmIP,
            proxyPort: proxyPort,
            hostProxyHTTP: hostProxyHTTP,
            guestHTTP: guestHTTP,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            proxyPortFailureReasons: proxyPortFailureReasons,
            guestBootstrapFailureReason: guestBootstrapFailureReason
        )
    }
}
