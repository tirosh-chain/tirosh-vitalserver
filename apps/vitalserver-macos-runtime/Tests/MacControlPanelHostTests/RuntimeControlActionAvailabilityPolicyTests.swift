import RuntimeControl
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeControlActionAvailabilityPolicyTests: XCTestCase {
    private let policy = RuntimeControlActionAvailabilityPolicy()
    private let capabilities = RuntimeControlCapabilities(canApplyBundle: true)

    func testExplicitNonExecutableRuntimeStateBlocksRuntimeActionsEvenWhenLegacyBoolIsInstalled() {
        let status = platformState(runtimeInstallationState: .present)

        XCTAssertFalse(policy.isRuntimeExecutable(status))
        XCTAssertFalse(policy.canApplyUpdate(
            status: status,
            capabilities: capabilities,
            stableUpdate: .missing(),
            isBusy: false,
            hasSelectedBundle: true,
            selectedBundleVerified: true
        ))
        XCTAssertFalse(policy.canApplySettings(
            status: status,
            isBusy: false,
            canApplyForCurrentConnection: true
        ))
        XCTAssertFalse(policy.canCreateRedisBackup(
            status: status,
            capabilities: capabilities,
            isBusy: false
        ))
        XCTAssertFalse(policy.canRepairRuntime(status: status, isBusy: false))
        XCTAssertFalse(policy.canControlRuntimeServices(
            status: status,
            capabilities: capabilities,
            isBusy: false
        ))
        XCTAssertFalse(policy.canUninstallRuntime(
            status: status,
            capabilities: capabilities,
            isBusy: false
        ))
    }

    func testExplicitExecutableRuntimeStateAllowsRuntimeActionsWhenOtherInputsAllow() {
        let status = platformState(runtimeInstallationState: .executable)

        XCTAssertTrue(policy.isRuntimeExecutable(status))
        XCTAssertTrue(policy.canApplyUpdate(
            status: status,
            capabilities: capabilities,
            stableUpdate: .missing(),
            isBusy: false,
            hasSelectedBundle: true,
            selectedBundleVerified: true
        ))
        XCTAssertTrue(policy.canApplySettings(
            status: status,
            isBusy: false,
            canApplyForCurrentConnection: true
        ))
        XCTAssertTrue(policy.canCreateRedisBackup(
            status: status,
            capabilities: capabilities,
            isBusy: false
        ))
        XCTAssertTrue(policy.canRepairRuntime(status: status, isBusy: false))
        XCTAssertTrue(policy.canControlRuntimeServices(
            status: status,
            capabilities: capabilities,
            isBusy: false
        ))
        XCTAssertTrue(policy.canUninstallRuntime(
            status: status,
            capabilities: capabilities,
            isBusy: false
        ))
    }

    func testExecutableDecisionUsesExplicitInstallationState() {
        let executable = platformState(runtimeInstallationState: .executable)
        let missing = platformState(runtimeInstallationState: .missing)

        XCTAssertTrue(policy.isRuntimeExecutable(executable))
        XCTAssertFalse(policy.isRuntimeExecutable(missing))
    }

    func testUnavailableStableUpdateJournalBlocksAdmissionWithoutInferringIdle() {
        let status = platformState(runtimeInstallationState: .executable)

        XCTAssertFalse(policy.canApplyUpdate(
            status: status,
            capabilities: capabilities,
            stableUpdate: .unavailable(readError: "Platform Agent is unavailable"),
            isBusy: false,
            hasSelectedBundle: true,
            selectedBundleVerified: true
        ))
    }

    func testBusyOrCapabilityDeniedInputsBlockActionsWithoutChangingRuntimeStateMeaning() {
        let status = platformState(runtimeInstallationState: .executable)
        var restricted = RuntimeControlCapabilities()
        restricted.canApplyBundle = false
        restricted.canControlRuntimeServices = false
        restricted.canUninstallRuntime = false

        XCTAssertFalse(policy.canApplyUpdate(
            status: status,
            capabilities: restricted,
            stableUpdate: .missing(),
            isBusy: false,
            hasSelectedBundle: true,
            selectedBundleVerified: true
        ))
        XCTAssertFalse(policy.canApplySettings(
            status: status,
            isBusy: true,
            canApplyForCurrentConnection: true
        ))
        XCTAssertFalse(policy.canCreateRedisBackup(
            status: status,
            capabilities: restricted,
            isBusy: false
        ))
        XCTAssertFalse(policy.canControlRuntimeServices(
            status: status,
            capabilities: restricted,
            isBusy: false
        ))
        XCTAssertFalse(policy.canUninstallRuntime(
            status: status,
            capabilities: restricted,
            isBusy: false
        ))
    }
}
