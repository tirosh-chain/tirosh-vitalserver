import Contracts
import Application
import Domain
import XCTest
import Errors

final class RuntimeUninstallReadinessPolicyTests: XCTestCase {
    func testLaunchdReadFailureBlocksUninstallCleanup() {
        let blockers = RuntimeUninstallReadinessPolicy.blockers(input: RuntimeUninstallReadinessInput(
            serviceStates: serviceStates(overrides: [
                .vm: .readFailed("exitCode=1 stderr=permission denied"),
            ]),
            vmProcessState: .pidFileMissing
        ))

        XCTAssertEqual(blockers, [
            "launchd-service-read-failed:label=\(RuntimeManagedService.vm.label) reason=exitCode=1 stderr=permission denied",
            "vm-process-pid-file-missing",
        ])
    }

    func testMissingPidFileDoesNotBlockWhenVMServiceIsExplicitlyNotLoaded() {
        let blockers = RuntimeUninstallReadinessPolicy.blockers(input: RuntimeUninstallReadinessInput(
            serviceStates: serviceStates(),
            vmProcessState: .pidFileMissing
        ))

        XCTAssertEqual(blockers, [])
    }

    func testMissingPidFileBlocksWhenVMServiceStateIsNotStopped() {
        let blockers = RuntimeUninstallReadinessPolicy.blockers(input: RuntimeUninstallReadinessInput(
            serviceStates: serviceStates(overrides: [
                .vm: .loaded,
            ]),
            vmProcessState: .pidFileMissing
        ))

        XCTAssertEqual(blockers, [
            "launchd-service-loaded:label=\(RuntimeManagedService.vm.label)",
            "vm-process-pid-file-missing",
        ])
    }

    func testRunningVMProcessBlocksUninstallCleanup() {
        let blockers = RuntimeUninstallReadinessPolicy.blockers(input: RuntimeUninstallReadinessInput(
            serviceStates: serviceStates(),
            vmProcessState: .running(pid: 123)
        ))

        XCTAssertEqual(blockers, ["vm-process-running:pid=123"])
    }

    func testReceiptStatesBlockUntilAllReceiptsAreExplicitlyAbsent() {
        let blockers = RuntimeUninstallReadinessPolicy.blockers(input: RuntimeUninstallReadinessInput(
            serviceStates: serviceStates(),
            vmProcessState: .stopped,
            packageReceiptStates: [
                .present(identifier: "ai.tirosh.vitalserver.helper"),
                .readFailed(identifier: "ai.tirosh.vitalserver.helper.tools", reason: "exitCode=1 stderr=denied"),
            ]
        ))

        XCTAssertEqual(blockers, [
            "package-receipt-present:identifier=ai.tirosh.vitalserver.helper",
            "package-receipt-read-failed:identifier=ai.tirosh.vitalserver.helper.tools reason=exitCode=1 stderr=denied",
        ])
    }

    func testCleanupArtifactsBlockUntilExplicitlyAbsent() {
        let blockers = RuntimeUninstallReadinessPolicy.cleanupArtifactBlockers([
            .absent(path: "/Applications/VitalServer Helper.app"),
            .present(path: "/usr/local/bin/vitalserver-vm"),
            .inspectFailed(path: "/Library/Application Support/VitalServerHelper", reason: "permission denied"),
        ])

        XCTAssertEqual(blockers, [
            "runtime-artifact-present:path=/usr/local/bin/vitalserver-vm",
            "runtime-artifact-inspect-failed:path=/Library/Application Support/VitalServerHelper reason=permission denied",
        ])
    }

    private func serviceStates(
        overrides: [RuntimeManagedService: RuntimeServiceState] = [:]
    ) -> [RuntimeManagedService: RuntimeServiceState] {
        var states = Dictionary(uniqueKeysWithValues: RuntimeManagedService.uninstallOrder.map {
            ($0, RuntimeServiceState.notLoaded)
        })
        for (service, state) in overrides {
            states[service] = state
        }
        return states
    }
}
