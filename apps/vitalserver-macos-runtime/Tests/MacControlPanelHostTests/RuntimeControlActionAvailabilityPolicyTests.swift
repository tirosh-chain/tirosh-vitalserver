import RuntimeControl
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeControlActionAvailabilityPolicyTests: XCTestCase {
    private let policy = RuntimeControlActionAvailabilityPolicy()
    private let capabilities = RuntimeControlCapabilities()

    func testExplicitNonExecutableRuntimeStateBlocksRuntimeActionsEvenWhenLegacyBoolIsInstalled() {
        let status = RuntimeStatus(runtimeInstalled: true, runtimeInstallationState: .present)

        XCTAssertFalse(policy.isRuntimeExecutable(status))
        XCTAssertFalse(policy.canApplyUpdate(
            status: status,
            capabilities: capabilities,
            updateInProgress: false,
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
        let status = RuntimeStatus(runtimeInstalled: false, runtimeInstallationState: .executable)

        XCTAssertTrue(policy.isRuntimeExecutable(status))
        XCTAssertTrue(policy.canApplyUpdate(
            status: status,
            capabilities: capabilities,
            updateInProgress: false,
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

    func testLegacyInstalledBoolDoesNotCreateExecutableRuntimeState() {
        let legacyInstalled = RuntimeStatus(runtimeInstalled: true)
        let legacyMissing = RuntimeStatus(runtimeInstalled: false)

        XCTAssertFalse(policy.isRuntimeExecutable(legacyInstalled))
        XCTAssertFalse(policy.isRuntimeExecutable(legacyMissing))
    }

    func testBusyOrCapabilityDeniedInputsBlockActionsWithoutChangingRuntimeStateMeaning() {
        let status = RuntimeStatus(runtimeInstalled: true, runtimeInstallationState: .executable)
        var restricted = RuntimeControlCapabilities()
        restricted.canApplyBundle = false
        restricted.canControlRuntimeServices = false
        restricted.canUninstallRuntime = false

        XCTAssertFalse(policy.canApplyUpdate(
            status: status,
            capabilities: restricted,
            updateInProgress: false,
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
