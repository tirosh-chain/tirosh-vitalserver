import Core
import Contracts
import XCTest

final class RuntimeUpdatePreflightPolicyTests: XCTestCase {
    func testCheckCompatibilityAllowsMatchingBundle() throws {
        try RuntimeUpdatePreflightPolicy.checkCompatibility(
            manifest: manifest(
                channel: .stable,
                targetPlatform: "macos-arm64",
                minUpdaterVersion: "1.2.0"
            ),
            currentUpdaterVersion: "1.2.3",
            currentChannel: .stable,
            currentPlatform: "macos-arm64"
        )
    }

    func testCheckCompatibilityPropagatesCompatibilityFailures() {
        XCTAssertThrowsError(try RuntimeUpdatePreflightPolicy.checkCompatibility(
            manifest: manifest(channel: .dev),
            currentUpdaterVersion: "1.2.3",
            currentChannel: .stable,
            currentPlatform: "macos-arm64"
        )) { error in
            XCTAssertEqual(error as? RuntimeUpdateCompatibilityError, .unsupportedChannel(
                currentChannel: .stable,
                bundleChannel: .dev
            ))
        }
    }

    func testStorageRequirementIncludesBundleRootfsAndMargin() {
        let requirement = RuntimeUpdatePreflightPolicy.storageRequirement(
            stagedBundleBytes: 30,
            rootfsStorage: .replacing(installedRootfsBytes: 10, incomingRootfsBytes: 20),
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
            rootfsStorage: .unchanged,
            marginBytes: 100
        )

        XCTAssertEqual(requirement.requiredBytes, 130)
        XCTAssertNil(requirement.installedRootfsBytes)
        XCTAssertNil(requirement.incomingRootfsBytes)
    }

    func testBlockingGuestStorageErrorsKeepsOnlyDiskRepairClassErrors() {
        XCTAssertEqual(
            RuntimeUpdatePreflightPolicy.blockingGuestStorageErrors([
                .runtimeStateStale,
                .guestFilesystemError,
                .guestHTTP("failed"),
                .guestFilesystemReadOnly,
                .guestDiskIO,
            ]),
            [
                .guestFilesystemError,
                .guestFilesystemReadOnly,
                .guestDiskIO,
            ]
        )
    }

    private func manifest(
        channel: UpdateBundleChannel = .stable,
        targetPlatform: String = "macos-arm64",
        minUpdaterVersion: String? = "1.2.0"
    ) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            channel: channel,
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatform: targetPlatform,
            components: ["updater": "1.2.3"],
            minUpdaterVersion: minUpdaterVersion,
            requiresGuestActivation: false,
            requiresTwoPhaseUpdate: false,
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: [],
            migrations: []
        )
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
        XCTAssertEqual(RuntimeHealthClassificationPolicy.containerHealthState(nil), .unreported)
        XCTAssertEqual(RuntimeHealthClassificationPolicy.containerHealthState(""), .unreported)
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
