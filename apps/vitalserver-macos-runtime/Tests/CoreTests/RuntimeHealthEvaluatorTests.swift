import Core
import Contracts
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
            rootfsBase: .missing,
            vmDisk: .missing,
            vmService: .notLoaded,
            proxyService: .notLoaded,
            watchdogService: .notLoaded
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

    func testReadinessFailuresIncludeProxyPortAndBootstrapReasons() {
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
            .guestHTTP("bootstrap-pending"),
            .guestBootstrapMissingRuntimePackages,
        ])
    }

    func testAuxiliaryUIFailuresDoNotTriggerRuntimeRecovery() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            redisUIHTTP: "failed",
            swaggerUIHTTP: "500"
        ))

        XCTAssertTrue(snapshot.isHealthy)
        XCTAssertEqual(snapshot.redisUIHTTP, "failed")
        XCTAssertEqual(snapshot.swaggerUIHTTP, "500")
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testAuditProxyStatusFailureProducesTypedReason() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            containerObservation: RuntimeContainerObservation(
                auditProxyHTTP: "failed",
                auditProxyStatus: nil,
                containerLogsPresent: true,
                containerLogsBytes: 1024
            )
        ))

        XCTAssertEqual(snapshot.failureReasons, [.auditProxyHTTP("failed")])
    }

    func testAuditProxyCountersAreObservedWithoutTriggeringRecovery() {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: RuntimeAuditProxyStatusDocument(auditWriteFailures: 2),
            containerLogsPresent: true,
            containerLogsBytes: 2048
        )
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(containerObservation: observation))

        XCTAssertTrue(snapshot.isHealthy)
        XCTAssertEqual(snapshot.containerObservation, observation)
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
        rootfsBase: RuntimeFileState = .present,
        vmDisk: RuntimeFileState = .present,
        vmService: RuntimeServiceState = .loaded,
        proxyService: RuntimeServiceState = .loaded,
        watchdogService: RuntimeServiceState = .loaded,
        vmIP: String? = "192.168.64.2",
        proxyPort: Int = 80,
        hostProxyHTTP: String = "200",
        guestHTTP: String = "200",
        redisUIHTTP: String = "200",
        swaggerUIHTTP: String = "200",
        containerObservation: RuntimeContainerObservation? = nil,
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
            containerObservation: containerObservation,
            proxyPortFailureReasons: proxyPortFailureReasons,
            guestBootstrapFailureReason: guestBootstrapFailureReason
        )
    }
}
