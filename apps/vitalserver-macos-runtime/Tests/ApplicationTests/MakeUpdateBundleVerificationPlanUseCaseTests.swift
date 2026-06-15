import Application
import Contracts
import Domain
import XCTest

final class MakeUpdateBundleVerificationPlanUseCaseTests: XCTestCase {
    func testMakePlanDelegatesBundleManifestPolicyWithoutAdapterFallback() throws {
        let manifest = UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatform: "macos-arm64",
            components: ["runtime": "1.2.3"],
            createdAt: "2026-06-05T00:00:00Z",
            artifacts: [
                UpdateBundleArtifact(name: "app.tar.gz", type: .appBundle, sha256: "abc", size: 10),
            ],
            migrations: [
                UpdateBundleMigration(name: "001.sql", sha256: "def", size: 20),
            ]
        )

        let plan = try MakeUpdateBundleVerificationPlanUseCase().makePlan(
            manifest: manifest,
            expectedProduct: "ai.tirosh.vitalserver.helper"
        )

        XCTAssertEqual(plan.artifactFiles.map(\.checksumKey), ["app.tar.gz"])
        XCTAssertEqual(plan.migrationFiles.map(\.checksumKey), ["migrations/001.sql"])
    }

    func testMakePlanPreservesUnsupportedProductFailure() {
        let manifest = UpdateBundleManifest(
            schemaVersion: 3,
            product: "wrong.product",
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatform: "macos-arm64",
            components: [:],
            createdAt: "2026-06-05T00:00:00Z",
            artifacts: [],
            migrations: []
        )

        XCTAssertThrowsError(try MakeUpdateBundleVerificationPlanUseCase().makePlan(
            manifest: manifest,
            expectedProduct: "ai.tirosh.vitalserver.helper"
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .unsupportedProduct("wrong.product"))
        }
    }
}
