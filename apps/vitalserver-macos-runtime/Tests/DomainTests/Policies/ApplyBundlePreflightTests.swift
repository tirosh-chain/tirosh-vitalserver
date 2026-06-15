import Foundation
import Application
import Contracts
import Domain
import XCTest
import Errors

final class ApplyBundlePreflightTests: XCTestCase {
    func testRestartPolicyReportsWhetherAnyServiceWasRunning() {
        XCTAssertFalse(RuntimeServiceRestartPolicy(
            restartVM: false,
            restartGuestLogSync: false,
            restartProxy: false,
            restartWatchdog: false
        ).anyServiceWasRunning)
        XCTAssertTrue(RuntimeServiceRestartPolicy(
            restartVM: false,
            restartGuestLogSync: false,
            restartProxy: true,
            restartWatchdog: false
        ).anyServiceWasRunning)
    }

    func testPreflightContextCarriesPreparedInputsForApplyAndRollback() {
        let manifest = UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatform: "macos-arm64",
            components: ["updater": "4.5.6"],
            createdAt: "2026-05-21T12:00:00Z",
            artifacts: [
                UpdateBundleArtifact(
                    name: "rootfs-base.raw.gz",
                    type: .rootfsBase,
                    sha256: "abc",
                    size: 10
                ),
            ],
            migrations: []
        )

        let context = ApplyBundlePreflightContext(
            stagedBundle: URL(fileURLWithPath: "/tmp/staged"),
            manifest: manifest,
            stagedRootfs: URL(fileURLWithPath: "/tmp/staged/rootfs-base.raw.gz"),
            backup: URL(fileURLWithPath: "/tmp/backup"),
            restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: false,
                restartWatchdog: true
            )
        )

        XCTAssertEqual(context.manifest.version, "1.2.3")
        XCTAssertEqual(context.stagedRootfs?.lastPathComponent, "rootfs-base.raw.gz")
        XCTAssertTrue(context.updatesRootfsBase)
        XCTAssertTrue(context.restartPolicy.restartVM)
        XCTAssertTrue(context.restartPolicy.restartWatchdog)
    }
}
