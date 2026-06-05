import Core
import Contracts
import XCTest

final class RuntimeUpdateCompatibilityCheckerTests: XCTestCase {
    func testAllowsCompatibleNormalUpdate() throws {
        try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(
                minUpdaterVersion: "1.2.0",
                requiresGuestActivation: true,
                artifacts: [
                    UpdateBundleArtifact(name: "guest-deploy.tar.gz", type: .guestDeploy, sha256: "abc", size: 10),
                ]
            ),
            currentUpdaterVersion: "1.2.3"
        )
    }

    func testAllowsEquivalentVersionWithMissingPatchComponent() throws {
        try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(minUpdaterVersion: "1.2"),
            currentUpdaterVersion: "1.2.0"
        )
    }

    func testRejectsOldUpdater() {
        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(minUpdaterVersion: "1.2.4"),
            currentUpdaterVersion: "1.2.3"
        )) { error in
            XCTAssertEqual(error as? RuntimeUpdateCompatibilityError, .updaterTooOld(
                currentVersion: "1.2.3",
                minimumVersion: "1.2.4"
            ))
        }
    }

    func testComparesTextVersionSegments() throws {
        try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(minUpdaterVersion: "1.2-alpha"),
            currentUpdaterVersion: "1.2-beta"
        )

        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(minUpdaterVersion: "1.2-beta"),
            currentUpdaterVersion: "1.2-alpha"
        )) { error in
            XCTAssertEqual(error as? RuntimeUpdateCompatibilityError, .updaterTooOld(
                currentVersion: "1.2-alpha",
                minimumVersion: "1.2-beta"
            ))
        }
    }

    func testComparesMixedNumericAndTextVersionSegments() throws {
        try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(minUpdaterVersion: "1.2-beta"),
            currentUpdaterVersion: "1.2.0"
        )

        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(minUpdaterVersion: "1.2.0"),
            currentUpdaterVersion: "1.2-beta"
        )) { error in
            XCTAssertEqual(error as? RuntimeUpdateCompatibilityError, .updaterTooOld(
                currentVersion: "1.2-beta",
                minimumVersion: "1.2.0"
            ))
        }
    }

    func testRejectsTwoPhaseUpdateDuringNormalApply() {
        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(requiresTwoPhaseUpdate: true),
            currentUpdaterVersion: "1.2.3"
        )) { error in
            XCTAssertEqual(error as? RuntimeUpdateCompatibilityError, .twoPhaseUpdateRequired)
        }
    }

    func testRejectsMismatchedBundleChannel() {
        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(channel: .dev),
            currentUpdaterVersion: "1.2.3",
            currentChannel: .stable
        )) { error in
            XCTAssertEqual(error as? RuntimeUpdateCompatibilityError, .unsupportedChannel(
                currentChannel: .stable,
                bundleChannel: .dev
            ))
        }
    }

    func testAllowsTwoPhaseUpdateWhenExplicitlyAllowed() throws {
        try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(requiresTwoPhaseUpdate: true),
            currentUpdaterVersion: "1.2.3",
            allowTwoPhaseUpdate: true
        )
    }

    func testRejectsUnsupportedTargetPlatform() {
        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(targetPlatform: "macos-arm64"),
            currentUpdaterVersion: "1.2.3",
            currentPlatform: "windows-x64"
        )) { error in
            XCTAssertEqual(error as? RuntimeUpdateCompatibilityError, .unsupportedPlatform(
                currentPlatform: "windows-x64",
                targetPlatform: "macos-arm64"
            ))
        }
    }

    func testRequiresGuestActivationFlagToMatchGuestDeployArtifact() {
        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(
                requiresGuestActivation: false,
                artifacts: [
                    UpdateBundleArtifact(name: "guest-deploy.tar.gz", type: .guestDeploy, sha256: "abc", size: 10),
                ]
            ),
            currentUpdaterVersion: "1.2.3"
        )) { error in
            XCTAssertEqual(error as? RuntimeUpdateCompatibilityError, .guestActivationRequirementMismatch(
                requiresGuestActivation: false,
                hasGuestDeployArtifact: true
            ))
        }

        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(requiresGuestActivation: true, artifacts: []),
            currentUpdaterVersion: "1.2.3"
        )) { error in
            XCTAssertEqual(error as? RuntimeUpdateCompatibilityError, .guestActivationRequirementMismatch(
                requiresGuestActivation: true,
                hasGuestDeployArtifact: false
            ))
        }
    }

    func testCompatibilityErrorsDescribeOperationalFailures() {
        XCTAssertEqual(
            RuntimeUpdateCompatibilityError.updaterTooOld(
                currentVersion: "1.2.3",
                minimumVersion: "1.2.4"
            ).description,
            "update bundle requires updater 1.2.4 or newer; current updater is 1.2.3"
        )
        XCTAssertEqual(
            RuntimeUpdateCompatibilityError.unsupportedChannel(
                currentChannel: .stable,
                bundleChannel: .dev
            ).description,
            "update bundle channel dev is not compatible with installed channel stable"
        )
        XCTAssertEqual(
            RuntimeUpdateCompatibilityError.twoPhaseUpdateRequired.description,
            "update bundle requires a bridge/two-phase update"
        )
        XCTAssertEqual(
            RuntimeUpdateCompatibilityError.unsupportedPlatform(
                currentPlatform: "windows-x64",
                targetPlatform: "macos-arm64"
            ).description,
            "update bundle targets macos-arm64; current platform is windows-x64"
        )
        XCTAssertEqual(
            RuntimeUpdateCompatibilityError.guestActivationRequirementMismatch(
                requiresGuestActivation: true,
                hasGuestDeployArtifact: false
            ).description,
            "update bundle guest activation flag mismatch: requiresGuestActivation=true, hasGuestDeployArtifact=false"
        )
    }

    private func manifest(
        minUpdaterVersion: String? = "1.2.0",
        channel: UpdateBundleChannel = .stable,
        targetPlatform: String = "macos-arm64",
        requiresGuestActivation: Bool = false,
        requiresTwoPhaseUpdate: Bool = false,
        artifacts: [UpdateBundleArtifact] = []
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
            requiresGuestActivation: requiresGuestActivation,
            requiresTwoPhaseUpdate: requiresTwoPhaseUpdate,
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: artifacts,
            migrations: []
        )
    }
}
