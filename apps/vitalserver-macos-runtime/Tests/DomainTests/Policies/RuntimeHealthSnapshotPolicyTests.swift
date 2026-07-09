import Contracts
import Application
@testable import Domain
import XCTest
import Errors

final class RuntimeHealthSnapshotPolicyTests: XCTestCase {
    func testExplicitFailureStateWithEmptyFailureReasonsIsNotHealthy() {
        let snapshot = healthSnapshot(
            vmState: .unreachable,
            guestHTTP: "503",
            failureReasons: []
        )

        XCTAssertFalse(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(
            RuntimeHealthSnapshotPolicy.missingFailureReasonIssue(snapshot),
            RuntimeHealthSnapshotPolicy.missingFailureReasons
        )
    }

    func testAuxiliaryUIHTTPFailuresDoNotRequireRuntimeFailureReasons() {
        let snapshot = healthSnapshot(
            redisUIHTTP: "failed",
            swaggerUIHTTP: "500",
            failureReasons: []
        )

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertNil(RuntimeHealthSnapshotPolicy.missingFailureReasonIssue(snapshot))
    }

    func testTransientVMStateWithHealthyInputsDoesNotRequireFailureReasons() {
        let snapshot = healthSnapshot(
            vmState: .starting,
            failureReasons: []
        )

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertNil(RuntimeHealthSnapshotPolicy.missingFailureReasonIssue(snapshot))
    }

    func testGuestAddressReadFailureDoesNotRequireCurrentHealthFailureReason() {
        let snapshot = healthSnapshot(
            guestAddressRead: .readFailed("permission denied"),
            vmIP: nil,
            failureReasons: []
        )

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertNil(RuntimeHealthSnapshotPolicy.missingFailureReasonIssue(snapshot))
    }

    private func healthSnapshot(
        vmExecutable: RuntimeFileState = .executable,
        proxyExecutable: RuntimeFileState = .executable,
        rootfsBase: RuntimeFileState = .present,
        vmDisk: RuntimeFileState = .present,
        vmService: RuntimeServiceState = .loaded,
        proxyService: RuntimeServiceState = .loaded,
        watchdogService: RuntimeServiceState = .loaded,
        vmState: RuntimeVMState = .running,
        vmErrors: [RuntimeVMError] = [],
        guestAddressRead: RuntimeGuestAddressReadResult = .loaded(address: "192.168.64.2", source: .runtimeControlAPI),
        vmIP: String? = "192.168.64.2",
        hostProxyHTTP: String = "200",
        guestHTTP: String = "200",
        redisUIHTTP: String = "200",
        swaggerUIHTTP: String = "200",
        failureReasons: [RuntimeFailureReason]
    ) -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: vmExecutable,
            proxyExecutable: proxyExecutable,
            rootfsBase: rootfsBase,
            vmDisk: vmDisk,
            vmService: vmService,
            proxyService: proxyService,
            watchdogService: watchdogService,
            vmState: vmState,
            vmErrors: vmErrors,
            guestAddressRead: guestAddressRead,
            vmIP: vmIP,
            proxyPort: 80,
            hostProxyHTTP: hostProxyHTTP,
            guestHTTP: guestHTTP,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            failureReasons: failureReasons
        )
    }
}
