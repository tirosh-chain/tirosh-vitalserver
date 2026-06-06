import Application
import Contracts
import Domain
import Foundation
import Workflow
import XCTest
import Errors

final class RuntimeApplyBundleStepExecutorTests: XCTestCase {
    func testExecuteDelegatesApplyBundleStepPlansToPort() throws {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        let stagedRootfs = stagedBundle.appendingPathComponent(rootfsBaseName)
        let rootfsBase = URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        let artifact = UpdateBundleArtifact(name: "app.tar.gz", type: .appBundle, sha256: "abc", size: 10)
        let migration = UpdateBundleMigration(name: "001-test", sha256: "def", size: 20)
        let manifest = manifest(version: "1.2.3", artifacts: [
            UpdateBundleArtifact(name: rootfsBaseName, type: .rootfsBase, sha256: "root", size: 1),
            artifact,
        ], migrations: [migration])
        let policy = RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: true
        )
        let preflight = ApplyBundlePreflightContext(
            stagedBundle: stagedBundle,
            manifest: manifest,
            stagedRootfs: stagedRootfs,
            backup: URL(fileURLWithPath: "/backup"),
            restartPolicy: policy
        )
        var delegatedPlans: [ApplyRuntimeBundleStepExecutionPlan] = []
        let executor = RuntimeApplyBundleStepExecutor(
            executeStepPlan: { plan in delegatedPlans.append(plan) }
        )

        for step in RuntimeOperationPlans.applyBundle(updatesRootfsBase: true).steps {
            try executor.execute(step, preflight: preflight, rootfsBase: rootfsBase)
        }

        XCTAssertEqual(delegatedPlans.map(planLabel), [
            "stopRuntimeServices:guestPoweroff",
            "replaceRootfsBase:replace",
            "replaceUpdateArtifacts",
            "runMigrations",
            "refreshCloudInitSeed",
            "writeRuntimeVersion:1.2.3:update-bundle-1.2.3",
            "startRuntimeServices:true:false:true",
            "activateGuestUpdate",
            "waitRuntimeHealth:true:false:true",
        ])
    }

    func testStopRuntimeServicesDelegatesDirectStopWhenVMWasNotRunning() throws {
        let executor = RuntimeApplyBundleStepExecutor(
            executeStepPlan: { plan in
                XCTAssertEqual(planLabel(plan), "stopRuntimeServices:direct")
            }
        )

        try executor.execute(
            .stopRuntimeServices,
            preflight: preflight(restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: false,
                restartGuestLogSync: true,
                restartProxy: false,
                restartWatchdog: false
            )),
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        )
    }

    func testRootfsReplacementDelegatesSkipWhenBundleDoesNotIncludeRootfs() throws {
        let executor = RuntimeApplyBundleStepExecutor(
            executeStepPlan: { plan in
                XCTAssertEqual(planLabel(plan), "replaceRootfsBase:skip")
            }
        )
        let preflight = ApplyBundlePreflightContext(
            stagedBundle: URL(fileURLWithPath: "/staged"),
            manifest: manifest(version: "1.2.3"),
            stagedRootfs: nil,
            backup: URL(fileURLWithPath: "/backup"),
            restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: false,
                restartGuestLogSync: false,
                restartProxy: false,
                restartWatchdog: false
            )
        )

        try executor.execute(
            .replaceRootfsBase,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        )
    }

    func testDelegatesUnsupportedStepWithoutWorkflowInterpretation() throws {
        let executor = RuntimeApplyBundleStepExecutor(
            executeStepPlan: { plan in
                XCTAssertTrue(planLabel(plan).hasPrefix("unsupported:"))
            }
        )

        try executor.execute(
            .loadInstallSettings,
            preflight: preflight(restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: false,
                restartGuestLogSync: false,
                restartProxy: false,
                restartWatchdog: false
            )),
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        )
    }

    func testPropagatesStepPlanExecutionFailure() {
        let executor = RuntimeApplyBundleStepExecutor(
            executeStepPlan: { _ in throw TestError.executionFailed }
        )

        XCTAssertThrowsError(try executor.execute(
            .replaceUpdateArtifacts,
            preflight: preflight(restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: false,
                restartGuestLogSync: false,
                restartProxy: false,
                restartWatchdog: false
            )),
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        )) { error in
            XCTAssertEqual(error as? TestError, .executionFailed)
        }
    }
}

private let rootfsBaseName = "rootfs-base.raw.gz"

private func preflight(
    restartPolicy: RuntimeServiceRestartPolicy
) -> ApplyBundlePreflightContext {
    ApplyBundlePreflightContext(
        stagedBundle: URL(fileURLWithPath: "/staged"),
        manifest: manifest(version: "1.2.3"),
        stagedRootfs: URL(fileURLWithPath: "/staged/rootfs-base.raw.gz"),
        backup: URL(fileURLWithPath: "/backup"),
        restartPolicy: restartPolicy
    )
}

private func manifest(
    version: String,
    artifacts: [UpdateBundleArtifact] = [],
    migrations: [UpdateBundleMigration] = []
) -> UpdateBundleManifest {
    UpdateBundleManifest(
        schemaVersion: 3,
        product: "test-product",
        helperVersion: version,
        releaseLabel: version,
        targetPlatform: "macos-arm64",
        components: ["updater": version],
        createdAt: "2026-05-22T00:00:00Z",
        artifacts: artifacts,
        migrations: migrations
    )
}

private func planLabel(_ plan: ApplyRuntimeBundleStepExecutionPlan) -> String {
    switch plan {
    case .stopRuntimeServices(let stopPlan):
        switch stopPlan {
        case .prepareGuestShutdownAndStopServicesAfterPoweroff:
            return "stopRuntimeServices:guestPoweroff"
        case .stopServicesDirectly:
            return "stopRuntimeServices:direct"
        }
    case .replaceRootfsBase(let rootfsPlan):
        switch rootfsPlan {
        case .skip:
            return "replaceRootfsBase:skip"
        case .replace:
            return "replaceRootfsBase:replace"
        }
    case .replaceUpdateArtifacts:
        return "replaceUpdateArtifacts"
    case .runMigrations:
        return "runMigrations"
    case .refreshCloudInitSeed:
        return "refreshCloudInitSeed"
    case .writeRuntimeVersion(let version, let stagedBundle):
        return "writeRuntimeVersion:\(version):\(stagedBundle.lastPathComponent)"
    case .startRuntimeServices(let restartPolicy):
        return "startRuntimeServices:\(restartPolicy.restartVM):\(restartPolicy.restartProxy):\(restartPolicy.restartWatchdog)"
    case .activateGuestUpdate:
        return "activateGuestUpdate"
    case .waitRuntimeHealth(let restartPolicy):
        return "waitRuntimeHealth:\(restartPolicy.restartVM):\(restartPolicy.restartProxy):\(restartPolicy.restartWatchdog)"
    case .unsupported(let failureMessage):
        return "unsupported:\(failureMessage)"
    }
}

private enum TestError: Error, Equatable {
    case executionFailed
}
