import Application
import Bootstrap
import Contracts
import Domain
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeRollbackCompositionTests: XCTestCase {
    func testRollbackCompositionExecutesUseCasePlansThroughBootstrapEffects() throws {
        let fileStore = RuntimeFileStoreSpy()
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let backup = URL(fileURLWithPath: "/product/backups/before-1.2.3")
        fileStore.directories.insert(backup)
        fileStore.files[backup.appendingPathComponent(RuntimeFileNames.backupManifest)] = try JSONEncoder().encode(backupManifest())
        fileStore.files[backup.appendingPathComponent(RuntimeFileNames.rootfsBase)] = Data("rootfs".utf8)
        var events: [String] = []

        let workflow = RuntimeRollbackComposition.make(
            context: RuntimeRollbackCompositionContext(installedPaths: installedPaths),
            operations: RuntimeRollbackCompositionOperations(
                fileStore: fileStore,
                requireLatestBackup: {
                    XCTFail("specific rollback should not ask for latest backup")
                    return backup
                },
                isLaunchdLoaded: { _ in false },
                stopRuntimeServices: { events.append("stop") },
                startRuntimeServices: { policy in
                    events.append("start:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
                },
                waitForHealth: { policy in
                    events.append("wait:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
                },
                replaceFile: { source, destination in
                    events.append("replace:\(source.lastPathComponent):\(destination.lastPathComponent)")
                },
                writeRuntimeVersion: { version, destinationDirectory in
                    events.append("version:\(version):\(destinationDirectory.lastPathComponent)")
                },
                restoreBackupPathIfExists: { source, destination in
                    events.append("restore:\(source.lastPathComponent):\(destination.lastPathComponent)")
                },
                restoreRuntimeToolsIfExists: { source in
                    events.append("tools:\(source.lastPathComponent)")
                },
                writeStatus: { _, _, _ in },
                writeProgress: { _ in },
                log: { _ in }
            )
        )

        try workflow.rollback(.specificBackup(backup))

        XCTAssertEqual(events, [
            "stop",
            "replace:rootfs-base.raw.gz:rootfs-base.raw.gz",
            "version:rolled-back:before-1.2.3",
            "restore:app-bundle:VitalServer Helper.app",
            "restore:nginx-bundle:nginx",
            "restore:guest-deploy:deploy",
            "tools:runtime-tools",
            "start:true:true:true",
            "wait:true:true:true",
        ])
    }
}

private func backupManifest() -> BackupManifest {
    BackupManifest(
        product: "ai.tirosh.vitalserver.helper",
        createdAt: "2026-05-31T00:00:00Z",
        reason: "before-1.2.3",
        rootfsBase: RuntimeFileNames.rootfsBase,
        vmDisk: "vm-disk.img",
        vmDiskPreserved: true
    )
}
