import Contracts
import Domain
import XCTest
import Errors

final class DomainRuntimeUninstallReadinessPolicyTests: XCTestCase {
    func testBlocksRunningServiceAndRunningVMProcess() {
        let blockers = RuntimeUninstallReadinessPolicy.blockers(input: RuntimeUninstallReadinessInput(
            serviceStates: serviceStates(overrides: [.vm: .loaded]),
            vmProcessState: .running(pid: 123)
        ))

        XCTAssertEqual(blockers, [
            "launchd-service-loaded:label=\(RuntimeManagedService.vm.label)",
            "vm-process-running:pid=123",
        ])
    }

    func testPackageReceiptFailuresRemainExplicitBlockers() {
        let blockers = RuntimeUninstallReadinessPolicy.packageReceiptBlockers([
            .present(
                identifier: "ai.tirosh.vitalserver.helper",
                version: RuntimePackageVersion(rawValue: "0.2.1")!
            ),
            .readFailed(identifier: "ai.tirosh.vitalserver.helper", reason: "database locked"),
            .forgetFailed(identifier: "ai.tirosh.vitalserver.helper", reason: "permission denied"),
        ])

        XCTAssertEqual(blockers, [
            "package-receipt-present:identifier=ai.tirosh.vitalserver.helper",
            "package-receipt-read-failed:identifier=ai.tirosh.vitalserver.helper reason=database locked",
            "package-receipt-forget-failed:identifier=ai.tirosh.vitalserver.helper permission denied",
        ])
    }
}

private func serviceStates(
    overrides: [RuntimeManagedService: RuntimeServiceState] = [:]
) -> [RuntimeManagedService: RuntimeServiceState] {
    Dictionary(uniqueKeysWithValues: RuntimeManagedService.uninstallOrder.map { service in
        (service, overrides[service] ?? .notLoaded)
    })
}
