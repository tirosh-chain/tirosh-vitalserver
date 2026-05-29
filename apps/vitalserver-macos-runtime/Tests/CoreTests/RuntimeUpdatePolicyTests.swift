import Core
import Contracts
import XCTest

final class RuntimeUpdatePreflightPolicyTests: XCTestCase {
    func testStorageRequirementIncludesBundleRootfsAndMargin() {
        let requirement = RuntimeUpdatePreflightPolicy.storageRequirement(
            stagedBundleBytes: 30,
            installedRootfsBytes: 10,
            incomingRootfsBytes: 20,
            marginBytes: 100
        )

        XCTAssertEqual(requirement.requiredBytes, 160)
        XCTAssertEqual(requirement.stagedBundleBytes, 30)
        XCTAssertEqual(requirement.installedRootfsBytes, 10)
        XCTAssertEqual(requirement.incomingRootfsBytes, 20)
    }

    func testStorageRequirementDoesNotRequireRootfsSpaceWhenRootfsIsUnchanged() {
        let requirement = RuntimeUpdatePreflightPolicy.storageRequirement(
            stagedBundleBytes: 30,
            installedRootfsBytes: nil,
            incomingRootfsBytes: nil,
            marginBytes: 100
        )

        XCTAssertEqual(requirement.requiredBytes, 130)
        XCTAssertNil(requirement.installedRootfsBytes)
        XCTAssertNil(requirement.incomingRootfsBytes)
    }
}

final class RuntimeManagedOperationPolicyTests: XCTestCase {
    func testProtectedOperationsAreCentralizedForWatchdogRecovery() {
        XCTAssertTrue(RuntimeManagedOperationPolicy.isProtectedFromWatchdogRecovery(.applyBundle))
        XCTAssertTrue(RuntimeManagedOperationPolicy.isProtectedFromWatchdogRecovery(.prepareUpdateShutdown))
        XCTAssertTrue(RuntimeManagedOperationPolicy.isProtectedFromWatchdogRecovery(.rollback))
        XCTAssertTrue(RuntimeManagedOperationPolicy.isProtectedFromWatchdogRecovery(.repairVMDisk))
        XCTAssertFalse(RuntimeManagedOperationPolicy.isProtectedFromWatchdogRecovery(.status))
        XCTAssertFalse(RuntimeManagedOperationPolicy.isProtectedFromWatchdogRecovery(.watchdog))
    }
}

final class RuntimeHealthClassificationPolicyTests: XCTestCase {
    func testContainerHealthClassifiesTransientStartingAsNonFailure() {
        XCTAssertEqual(RuntimeHealthClassificationPolicy.containerHealthState(nil), .stable)
        XCTAssertEqual(RuntimeHealthClassificationPolicy.containerHealthState("healthy"), .stable)
        XCTAssertEqual(RuntimeHealthClassificationPolicy.containerHealthState("starting"), .transitional)
        XCTAssertEqual(RuntimeHealthClassificationPolicy.containerHealthState("unhealthy"), .failed)
        XCTAssertFalse(RuntimeHealthClassificationPolicy.isFailingContainerHealth(nil))
        XCTAssertFalse(RuntimeHealthClassificationPolicy.isFailingContainerHealth(""))
        XCTAssertFalse(RuntimeHealthClassificationPolicy.isFailingContainerHealth("healthy"))
        XCTAssertFalse(RuntimeHealthClassificationPolicy.isFailingContainerHealth("starting"))
        XCTAssertFalse(RuntimeHealthClassificationPolicy.isFailingContainerHealth(" STARTING "))
        XCTAssertTrue(RuntimeHealthClassificationPolicy.isFailingContainerHealth("unhealthy"))
    }
}
