import Application
import Contracts
import Foundation
import Workflow
import XCTest

final class RuntimeGuestActivationRunnerTests: XCTestCase {
    func testActivateDelegatesSkipPlanWhenGuestDeployArtifactIsAbsent() throws {
        var plans: [RuntimeGuestActivationExecutionPlan] = []
        let runner = RuntimeGuestActivationRunner(
            executeActivationPlan: { plans.append($0) }
        )

        try runner.activateIfNeeded(manifest: manifest(artifacts: [.appBundle]))

        XCTAssertEqual(plans, [
            .skip(logMessage: "guest update activation not required"),
        ])
    }

    func testActivateDelegatesActivationPlanWhenGuestDeployArtifactExists() throws {
        var plans: [RuntimeGuestActivationExecutionPlan] = []
        let runner = RuntimeGuestActivationRunner(
            executeActivationPlan: { plans.append($0) }
        )

        try runner.activateIfNeeded(manifest: manifest(artifacts: [.guestDeploy]))

        XCTAssertEqual(plans, [
            .activate(
                version: "1.2.3",
                requestedLogMessage: "guest update activation requested version=1.2.3",
                completedLogMessage: "guest update activation completed version=1.2.3"
            ),
        ])
    }

    func testActivatePropagatesExecutionPortFailure() {
        let runner = RuntimeGuestActivationRunner(
            executeActivationPlan: { _ in throw TestGuestActivationRunnerError.executionFailed }
        )

        XCTAssertThrowsError(try runner.activateIfNeeded(manifest: manifest(artifacts: [.guestDeploy]))) { error in
            XCTAssertEqual(error as? TestGuestActivationRunnerError, .executionFailed)
        }
    }

    private func manifest(artifacts: [UpdateBundleArtifactType]) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatform: "macos-arm64",
            components: ["updater": "1.2.3"],
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: artifacts.map {
                UpdateBundleArtifact(name: "\($0.rawValue).tar.gz", type: $0, sha256: "sha256", size: 1)
            },
            migrations: []
        )
    }
}

private enum TestGuestActivationRunnerError: Error, Equatable {
    case executionFailed
}
