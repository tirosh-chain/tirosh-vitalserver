import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeGuestActivationCompositionTests: XCTestCase {
    func testActivationCompositionExecutesActivationPlanThroughBootstrapEffects() throws {
        let guestRunDirectory = URL(fileURLWithPath: "/product/guest/run")
        var events: [String] = []
        var logs: [String] = []
        let composition = RuntimeGuestActivationComposition(
            context: RuntimeGuestActivationCompositionContext(guestRunDirectory: guestRunDirectory),
            operations: RuntimeGuestActivationCompositionOperations(
                requireCapability: { events.append("capability") },
                activateUpdate: { requestID, version in
                    events.append("activate:\(requestID):\(version)")
                    return RuntimeGuestControlServiceOperation(
                        operationId: "update-activation-1",
                        service: "update-activation",
                        command: .updateActivation,
                        state: .completed,
                        createdAt: "2026-07-01T00:00:00+00:00",
                        updatedAt: "2026-07-01T00:00:01+00:00"
                    )
                },
                isVMServiceLoaded: { false },
                startVMService: { events.append("start-vm") },
                requestID: { "request-1" },
                log: { logs.append($0) }
            )
        )

        try composition.activateIfNeeded(manifest: manifest(artifacts: [.guestDeploy]))

        XCTAssertTrue(events.contains("capability"))
        XCTAssertTrue(events.contains("start-vm"))
        XCTAssertTrue(events.contains("activate:request-1:1.2.3"))
        XCTAssertTrue(logs.contains("guest update activation requested version=1.2.3"))
        XCTAssertTrue(logs.contains("guest update activation operation completed operationId=update-activation-1"))
        XCTAssertTrue(logs.contains("guest update activation completed version=1.2.3"))
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
