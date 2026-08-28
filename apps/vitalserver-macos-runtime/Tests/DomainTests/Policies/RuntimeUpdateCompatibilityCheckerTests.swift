import Contracts
import Domain
import XCTest

final class RuntimeUpdateCompatibilityCheckerTests: XCTestCase {
    func testAllowsMatchingChannelPlatformAndGuestActivation() throws {
        try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(
                requiresGuestActivation: true,
                artifacts: [
                    UpdateBundleArtifact(
                        name: "guest-deploy.tar.gz",
                        type: .guestDeploy,
                        sha256: "abc",
                        size: 10
                    ),
                ]
            ),
            currentChannel: .stable,
            currentPlatform: "macos-arm64"
        )
    }

    func testRejectsMismatchedBundleChannel() {
        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(channel: .dev),
            currentChannel: .stable
        )) { error in
            XCTAssertEqual(
                error as? RuntimeUpdateCompatibilityError,
                .unsupportedChannel(
                    currentChannel: .stable,
                    bundleChannel: .dev
                )
            )
        }
    }

    func testRejectsUnsupportedTargetPlatform() {
        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(targetPlatform: "macos-arm64"),
            currentPlatform: "windows-x64"
        )) { error in
            XCTAssertEqual(
                error as? RuntimeUpdateCompatibilityError,
                .unsupportedPlatform(
                    currentPlatform: "windows-x64",
                    targetPlatform: "macos-arm64"
                )
            )
        }
    }

    func testRequiresGuestActivationFlagToMatchGuestDeployArtifact() {
        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(
                requiresGuestActivation: false,
                artifacts: [
                    UpdateBundleArtifact(
                        name: "guest-deploy.tar.gz",
                        type: .guestDeploy,
                        sha256: "abc",
                        size: 10
                    ),
                ]
            )
        )) { error in
            XCTAssertEqual(
                error as? RuntimeUpdateCompatibilityError,
                .guestActivationRequirementMismatch(
                    requiresGuestActivation: false,
                    hasGuestDeployArtifact: true
                )
            )
        }

        XCTAssertThrowsError(try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest(requiresGuestActivation: true)
        )) { error in
            XCTAssertEqual(
                error as? RuntimeUpdateCompatibilityError,
                .guestActivationRequirementMismatch(
                    requiresGuestActivation: true,
                    hasGuestDeployArtifact: false
                )
            )
        }
    }

    func testCompatibilityErrorsDescribeOperationalFailures() {
        XCTAssertEqual(
            RuntimeUpdateCompatibilityError.unsupportedChannel(
                currentChannel: .stable,
                bundleChannel: .dev
            ).description,
            "update bundle channel dev is not compatible with installed channel stable"
        )
        XCTAssertEqual(
            RuntimeUpdateCompatibilityError.unsupportedPlatform(
                currentPlatform: "windows-x64",
                targetPlatform: "macos-arm64"
            ).description,
            "update bundle targets macos-arm64; current platform is windows-x64"
        )
    }

    private func manifest(
        channel: UpdateBundleChannel = .stable,
        targetPlatform: String = "macos-arm64",
        requiresGuestActivation: Bool = false,
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
            requiresGuestActivation: requiresGuestActivation,
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: artifacts,
            migrations: []
        )
    }
}
