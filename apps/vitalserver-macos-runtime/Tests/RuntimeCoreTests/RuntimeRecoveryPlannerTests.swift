import XCTest
@testable import RuntimeCore
import RuntimeContracts

final class RuntimeRecoveryPlannerTests: XCTestCase {
    func testMissingInstalledArtifactIsNotRecoverable() {
        let plan = RuntimeRecoveryPlanner.plan(input(vmExecutable: false))

        XCTAssertFalse(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
    }

    func testGuestReadinessFailureRestartsOnlyVMWhenProxyIsAlive() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            guestHTTP: "503",
            hostProxyReadinessHTTP: "502",
            hostProxyLivenessHTTP: "204"
        ))

        XCTAssertTrue(plan.canRecover)
        XCTAssertTrue(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
    }

    func testProxyLivenessFailureRestartsProxy() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            hostProxyReadinessHTTP: "502",
            hostProxyLivenessHTTP: "failed"
        ))

        XCTAssertTrue(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertTrue(plan.restartProxy)
    }

    func testProxyReadinessFailureWithHealthyGuestRestartsProxy() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            guestHTTP: "200",
            hostProxyReadinessHTTP: "502",
            hostProxyLivenessHTTP: "204"
        ))

        XCTAssertTrue(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertTrue(plan.restartProxy)
    }

    func testMissingVMIPRestartsVM() {
        let plan = RuntimeRecoveryPlanner.plan(input(vmIP: nil))

        XCTAssertTrue(plan.canRecover)
        XCTAssertTrue(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
    }

    private func input(
        vmExecutable: Bool = true,
        proxyExecutable: Bool = true,
        rootfsBase: RuntimeFileState = .present,
        vmDisk: RuntimeFileState = .present,
        vmService: RuntimeServiceState = .loaded,
        proxyService: RuntimeServiceState = .loaded,
        vmIP: String? = "192.168.64.2",
        guestHTTP: String = "200",
        hostProxyReadinessHTTP: String = "200",
        hostProxyLivenessHTTP: String = "204"
    ) -> RuntimeRecoveryInput {
        RuntimeRecoveryInput(
            vmExecutable: vmExecutable,
            proxyExecutable: proxyExecutable,
            rootfsBase: rootfsBase,
            vmDisk: vmDisk,
            vmService: vmService,
            proxyService: proxyService,
            vmIP: vmIP,
            guestHTTP: guestHTTP,
            hostProxyReadinessHTTP: hostProxyReadinessHTTP,
            hostProxyLivenessHTTP: hostProxyLivenessHTTP
        )
    }
}
