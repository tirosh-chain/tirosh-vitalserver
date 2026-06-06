import Contracts
import Domain
import XCTest

final class DomainRuntimeUninstallTransitionPolicyTests: XCTestCase {
    func testStopRequiresExplicitStoppedStateBeforeRemovingFiles() throws {
        let blocked = try RuntimeUninstallTransitionPolicy.transition(
            from: .stopServicesRequested,
            event: .stoppedStateObserved(readiness(vmProcessState: .pidFileMissing, serviceState: .loaded))
        )

        XCTAssertEqual(blocked.state, .serviceStopBlocked)
        XCTAssertEqual(blocked.persistedState, .serviceStopBlocked)
        XCTAssertEqual(blocked.commands, [])
        XCTAssertTrue(blocked.blockers.contains("vm-process-pid-file-missing"))

        let allowed = try RuntimeUninstallTransitionPolicy.transition(
            from: .stopServicesRequested,
            event: .stoppedStateObserved(readiness(vmProcessState: .stopped))
        )

        XCTAssertEqual(allowed.state, .stoppedVerified)
        XCTAssertEqual(allowed.commands, [.removeFiles])
        XCTAssertEqual(allowed.blockers, [])
    }

    func testCleanupArtifactsMustBeExplicitlyAbsentBeforeReceiptForgetCommand() throws {
        let blocked = try RuntimeUninstallTransitionPolicy.transition(
            from: .filesRemovalStarted,
            event: .cleanupArtifactsObserved([
                .present(path: "/usr/local/bin/vitalserver-vm"),
            ])
        )

        XCTAssertEqual(blocked.state, .filesRemovalBlocked)
        XCTAssertEqual(blocked.commands, [])
        XCTAssertTrue(blocked.blockers.contains("runtime-artifact-present:path=/usr/local/bin/vitalserver-vm"))

        let allowed = try RuntimeUninstallTransitionPolicy.transition(
            from: .filesRemovalStarted,
            event: .cleanupArtifactsObserved([
                .absent(path: "/usr/local/bin/vitalserver-vm"),
            ])
        )

        XCTAssertEqual(allowed.state, .cleanupVerified)
        XCTAssertEqual(allowed.commands, [.forgetPackageReceipts])
    }

    func testReceiptsMustBeExplicitlyAbsentBeforeCompletion() throws {
        let blocked = try RuntimeUninstallTransitionPolicy.transition(
            from: .receiptsForgetStarted,
            event: .packageReceiptsObserved([
                .present(identifier: "ai.tirosh.vitalserver.helper"),
            ])
        )

        XCTAssertEqual(blocked.state, .receiptsForgetBlocked)
        XCTAssertEqual(blocked.commands, [])
        XCTAssertTrue(blocked.blockers.contains("package-receipt-present:identifier=ai.tirosh.vitalserver.helper"))

        let allowed = try RuntimeUninstallTransitionPolicy.transition(
            from: .receiptsForgetStarted,
            event: .packageReceiptsObserved([
                .absent(identifier: "ai.tirosh.vitalserver.helper"),
            ])
        )

        XCTAssertEqual(allowed.state, .completed)
        XCTAssertEqual(allowed.persistedState, .completed)
        XCTAssertEqual(allowed.commands, [.complete])
    }

    private func readiness(
        vmProcessState: RuntimeVMProcessState,
        serviceState: RuntimeServiceState = .notLoaded
    ) -> RuntimeUninstallReadinessInput {
        RuntimeUninstallReadinessInput(
            serviceStates: Dictionary(uniqueKeysWithValues: RuntimeManagedService.stopOrder.map { service in
                (service, service == .watchdog || service == .vm ? serviceState : .notLoaded)
            }),
            vmProcessState: vmProcessState
        )
    }
}
