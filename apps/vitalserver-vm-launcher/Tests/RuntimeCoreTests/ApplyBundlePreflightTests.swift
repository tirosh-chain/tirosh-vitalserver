import Foundation
import RuntimeCore
import XCTest

final class ApplyBundlePreflightTests: XCTestCase {
    func testRestartPolicyReportsWhetherAnyServiceWasRunning() {
        XCTAssertFalse(RuntimeServiceRestartPolicy(
            restartVM: false,
            restartProxy: false,
            restartWatchdog: false
        ).anyServiceWasRunning)
        XCTAssertTrue(RuntimeServiceRestartPolicy(
            restartVM: false,
            restartProxy: true,
            restartWatchdog: false
        ).anyServiceWasRunning)
    }

    func testPreflightContextCarriesPreparedInputsForApplyAndRollback() {
        let manifest = UpdateBundleManifest(
            schemaVersion: 1,
            product: "TiroshVitalServer",
            version: "1.2.3",
            runtimeVersion: "4.5.6",
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
                restartProxy: false,
                restartWatchdog: true
            )
        )

        XCTAssertEqual(context.manifest.version, "1.2.3")
        XCTAssertEqual(context.stagedRootfs.lastPathComponent, "rootfs-base.raw.gz")
        XCTAssertTrue(context.restartPolicy.restartVM)
        XCTAssertTrue(context.restartPolicy.restartWatchdog)
    }
}
