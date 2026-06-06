import XCTest
import Errors
import Application
import Contracts
@testable import Domain

final class RuntimeRecoveryPlannerTests: XCTestCase {
    func testMissingInstalledArtifactIsNotRecoverable() {
        let plan = RuntimeRecoveryPlanner.plan(input(vmExecutable: false))

        XCTAssertFalse(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
    }

    func testGuestReadinessFailureRestartsVMAndProxyAfterWakeTransitions() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            vmLifecycle: runningLifecycle(),
            guestHTTP: "503",
            hostProxyReadinessHTTP: "502",
            hostProxyLivenessHTTP: "204"
        ))

        XCTAssertTrue(plan.canRecover)
        XCTAssertTrue(plan.restartVM)
        XCTAssertTrue(plan.restartProxy)
        XCTAssertEqual(plan.restartReasons, [
            .guestHTTPUnhealthy("503"),
            .vmRestartRequiresProxyRestart,
        ])
    }

    func testGuestReadinessFailureWithoutVMLifecycleBlocksRecovery() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            guestHTTP: "503",
            hostProxyReadinessHTTP: "502",
            hostProxyLivenessHTTP: "204"
        ))

        XCTAssertFalse(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
        XCTAssertEqual(plan.blockers, ["recovery-blocked-missing-vm-lifecycle-for-vm-restart"])
    }

    func testProxyLivenessFailureRestartsProxy() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            hostProxyReadinessHTTP: "502",
            hostProxyLivenessHTTP: "503"
        ))

        XCTAssertTrue(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertTrue(plan.restartProxy)
        XCTAssertEqual(plan.restartReasons, [
            .hostProxyLivenessUnhealthy("503"),
            .hostProxyReadinessUnhealthy("502"),
        ])
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
        XCTAssertEqual(plan.restartReasons, [
            .hostProxyReadinessUnhealthy("502"),
        ])
    }

    func testMissingVMIPRestartsVM() {
        let plan = RuntimeRecoveryPlanner.plan(input(vmLifecycle: runningLifecycle(), vmIP: nil))

        XCTAssertTrue(plan.canRecover)
        XCTAssertTrue(plan.restartVM)
        XCTAssertTrue(plan.restartProxy)
        XCTAssertEqual(plan.restartReasons, [
            .missingVMIP,
            .vmRestartRequiresProxyRestart,
        ])
    }

    func testMissingVMIPWithoutVMLifecycleBlocksRecovery() {
        let plan = RuntimeRecoveryPlanner.plan(input(vmIP: nil))

        XCTAssertFalse(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
        XCTAssertEqual(plan.blockers, ["recovery-blocked-missing-vm-lifecycle-for-vm-restart"])
    }

    func testHTTPProbeReadFailureBlocksRecoveryInsteadOfCreatingRestartPlan() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            guestHTTP: "failed",
            hostProxyReadinessHTTP: RuntimeHTTPStatusText.invalidResponse,
            hostProxyLivenessHTTP: "connection-refused"
        ))

        XCTAssertFalse(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
        XCTAssertEqual(plan.blockers, [
            "recovery-blocked-guest-http-read-failed-failed",
            "recovery-blocked-host-proxy-readiness-http-read-failed-invalid-response",
            "recovery-blocked-host-proxy-liveness-http-read-failed-connection-refused",
        ])
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
        XCTAssertEqual(plan.restartReasons, [])
    }

    func testCriticalContainerServiceFailureRestartsVM() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            vmLifecycle: runningLifecycle(),
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
        XCTAssertEqual(plan.restartReasons, [
            .containerFailureRequiresVMRestart,
            .vmRestartRequiresProxyRestart,
        ])
    }

    func testMissingContainerObservationDoesNotCreateVMRestartReason() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            vmLifecycle: runningLifecycle(),
            containerObservationInput: .missing
        ))

        XCTAssertTrue(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
        XCTAssertEqual(plan.restartReasons, [])
    }

    func testServiceReadFailureBlocksRecoveryInsteadOfRestartingServices() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            vmService: .readFailed("launchctl denied"),
            proxyService: .permissionDenied("launchctl denied")
        ))

        XCTAssertFalse(plan.canRecover)
        XCTAssertFalse(plan.restartVM)
        XCTAssertFalse(plan.restartProxy)
        XCTAssertEqual(plan.blockers, [
            "recovery-blocked-vm-service-state-read_failed__launchctl_denied",
            "recovery-blocked-proxy-service-state-permission_denied__launchctl_denied",
        ])
    }

    func testServiceRestartReasonsAreExplicit() {
        let plan = RuntimeRecoveryPlanner.plan(input(
            vmService: .notLoaded,
            proxyService: .notLoaded
        ))

        XCTAssertTrue(plan.canRecover)
        XCTAssertTrue(plan.restartVM)
        XCTAssertTrue(plan.restartProxy)
        XCTAssertEqual(plan.restartReasons, [
            .vmServiceNotLoaded("not loaded"),
            .vmRestartRequiresProxyRestart,
            .proxyServiceNotLoaded("not loaded"),
        ])
        XCTAssertEqual(plan.restartReasonCodes, [
            "vm-service-not-loaded-not_loaded",
            "vm-restart-requires-proxy-restart",
            "proxy-service-not-loaded-not_loaded",
        ])
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
        containerObservation: RuntimeContainerObservation? = nil,
        containerObservationInput: RuntimeObservationInput<RuntimeContainerObservation>? = nil
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
            containerObservation: containerObservationInput
                ?? containerObservation.map(RuntimeObservationInput.loaded)
                ?? .notReported
        )
    }

    private func runningLifecycle() -> RuntimeVMLifecycleDocument {
        RuntimeVMLifecycleDocument(
            state: .running,
            startedAt: "2026-05-31T00:00:00Z",
            updatedAt: "2026-05-31T00:00:01Z"
        )
    }
}
