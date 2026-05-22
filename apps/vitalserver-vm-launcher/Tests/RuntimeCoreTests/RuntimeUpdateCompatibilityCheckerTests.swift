import RuntimeCore
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

    func testRejectsTwoPhaseUpdateDuringNormalApply() {
        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(requiresTwoPhaseUpdate: true),
            currentUpdaterVersion: "1.2.3"
        )) { error in
            XCTAssertEqual(error as? RuntimeUpdateCompatibilityError, .twoPhaseUpdateRequired)
        }
    }

    func testAllowsTwoPhaseUpdateWhenExplicitlyAllowed() throws {
        try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(requiresTwoPhaseUpdate: true),
            currentUpdaterVersion: "1.2.3",
            allowTwoPhaseUpdate: true
        )
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

    private func manifest(
        minUpdaterVersion: String? = "1.2.0",
        requiresGuestActivation: Bool = false,
        requiresTwoPhaseUpdate: Bool = false,
        artifacts: [UpdateBundleArtifact] = []
    ) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 2,
            product: "TiroshVitalServer",
            version: "1.2.3",
            runtimeVersion: "1.2.3",
            minUpdaterVersion: minUpdaterVersion,
            requiresGuestActivation: requiresGuestActivation,
            requiresTwoPhaseUpdate: requiresTwoPhaseUpdate,
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: artifacts,
            migrations: []
        )
    }
}
