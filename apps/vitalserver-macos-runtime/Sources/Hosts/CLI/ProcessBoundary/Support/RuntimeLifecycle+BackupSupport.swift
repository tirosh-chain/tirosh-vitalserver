import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Workflow
import Errors

extension RuntimeLifecycle {
    func latestBackup() -> URL? {
        do {
            return try backupStore().latestBackup()
        } catch {
            log("failed to read latest backup error=\(error.localizedDescription)")
            return nil
        }
    }

    func backupStore() -> RuntimeBackupStore {
        RuntimeBackupStoreComposition.make(
            context: RuntimeBackupStoreCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeBackupStoreCompositionOperations(
                fileStore: fileStore,
                timestamp: backupTimestamp,
                isoTimestamp: isoTimestamp,
                chmodExecutable: chmodRuntimeBackupExecutable,
                log: log
            )
        )
    }

    func chmodRuntimeBackupExecutable(_ url: URL) throws {
        try runRequired(Constants.Commands.chmod, arguments: ["0755", url.path])
    }

    func buildCloudInitSeedImage(_ request: RuntimeCloudInitSeedImageBuildRequest) throws {
        try runRequired(
            Constants.Commands.hdiutil,
            arguments: [
                "makehybrid",
                "-iso",
                "-joliet",
                "-default-volume-name",
                request.volumeName,
                "-o",
                request.outputImage.path,
                request.sourceDirectory.path,
            ]
        )
    }

    func runtimeVersionStore() -> RuntimeVersionStore {
        RuntimeVersionStoreComposition.make(
            context: RuntimeVersionStoreCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeVersionStoreCompositionOperations(
                fileStore: fileStore,
                timestamp: isoTimestamp
            )
        )
    }

    func writeRuntimeVersion(version: String, bundle: URL) throws {
        try runtimeVersionStore().writeAppliedVersion(version: version, bundle: bundle)
    }
}
