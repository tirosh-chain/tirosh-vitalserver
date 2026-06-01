import XCTest
@testable import Core
import Contracts

final class RuntimeRecoveryPlannerTests: XCTestCase {
    func testMissingInstalledArtifactIsNotRecoverable() {
        let plan = RuntimeRecoveryPlanner.plan(input(vmExecutable: false))

        XCTAssertFalse(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
    }

    func testGuestReadinessFailureRestartsVMAndProxyAfterWakeTransitions() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            guestHTTP: "503",
            hostProxyReadinessHTTP: "502",
            hostProxyLivenessHTTP: "204"
        ))

        XCTAssertTrue(plan.canRecover)
        XCTAssertTrue(plan.restartVM)
        XCTAssertTrue(plan.restartProxy)
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
        XCTAssertTrue(plan.restartProxy)
    }

    func testBootstrappingVMLifecycleDoesNotRestartVMForMissingGuestReadiness() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            vmLifecycle: RuntimeVMLifecycleDocument(
                state: .bootstrapping,
                startedAt: "2026-05-31T00:00:00Z",
                updatedAt: "2026-05-31T00:00:01Z",
                deadlineAt: "2999-01-01T00:00:00Z"
            ),
            vmIP: nil,
            guestHTTP: RuntimeHTTPStatusText.missingVMIP
        ))

        XCTAssertTrue(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
    }

    func testCriticalContainerServiceFailureRestartsVM() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            containerObservation: RuntimeContainerObservation(
                auditProxyHTTP: "200",
                auditProxyStatus: nil,
                containerLogsPresent: true,
                containerLogsBytes: 1024,
                composeServices: [
                    RuntimeContainerServiceObservation(
                        service: "vitaldb-observer",
                        state: "running",
                        health: "unhealthy"
                    ),
                ]
            )
        ))

        XCTAssertTrue(plan.canRecover)
        XCTAssertTrue(plan.restartVM)
        XCTAssertTrue(plan.restartProxy)
    }

    private func input(
        vmExecutable: Bool = true,
        proxyExecutable: Bool = true,
        rootfsBase: RuntimeFileState = .present,
        vmDisk: RuntimeFileState = .present,
        vmService: RuntimeServiceState = .loaded,
        proxyService: RuntimeServiceState = .loaded,
        vmLifecycle: RuntimeVMLifecycleDocument? = nil,
        vmIP: String? = "192.168.64.2",
        guestHTTP: String = "200",
        hostProxyReadinessHTTP: String = "200",
        hostProxyLivenessHTTP: String = "204",
        containerObservation: RuntimeContainerObservation? = nil
    ) -> RuntimeRecoveryInput {
        RuntimeRecoveryInput(
            vmExecutable: vmExecutable,
            proxyExecutable: proxyExecutable,
            rootfsBase: rootfsBase,
            vmDisk: vmDisk,
            vmService: vmService,
            proxyService: proxyService,
            vmLifecycle: vmLifecycle,
            vmIP: vmIP,
            guestHTTP: guestHTTP,
            hostProxyReadinessHTTP: hostProxyReadinessHTTP,
            hostProxyLivenessHTTP: hostProxyLivenessHTTP,
            containerObservation: containerObservation
        )
    }
}
