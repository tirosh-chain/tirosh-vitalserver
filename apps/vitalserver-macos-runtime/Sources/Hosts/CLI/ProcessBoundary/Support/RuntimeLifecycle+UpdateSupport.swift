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
    func fileSize(_ url: URL) throws -> UInt64 {
        try fileStore.fileSize(url)
    }

    func materializeRuntimeUpdateBundle(_ bundleURL: URL) throws -> RuntimeMaterializedBundle {
        try RuntimeBundleMaterializer(
            context: RuntimeBundleMaterializationContext(
                tarExecutable: Constants.Commands.tar
            ),
            operations: RuntimeBundleMaterializationOperations(
                directoryExists: directoryExists,
                fileExists: fileExists,
                temporaryRoot: {
                    fileStore.temporaryDirectory
                        .appendingPathComponent("tirosh-update-bundle-\(UUID().uuidString)", isDirectory: true)
                },
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                runProcess: runProcess,
                runRequired: runRequired,
                missingFileError: { url in
                    LauncherError.missingFile(url.path)
                },
                invalidArchiveError: { url in
                    LauncherError.bundleVerificationFailed("invalid update bundle archive: \(url.path)")
                },
                archiveValidationError: { error in
                    LauncherError.bundleVerificationFailed(error.description)
                },
                log: log
            )
        ).materialize(bundleURL)
    }

    func stageRuntimeUpdateBundle(_ input: RuntimeBundleStagingInput) throws -> URL {
        try RuntimeBundleStager(
            context: RuntimeBundleStagingContext(
                bundlesDirectory: bundlesDirectory,
                updateFreeSpaceMarginBytes: Constants.Runtime.updateFreeSpaceMarginBytes
            ),
            operations: RuntimeBundleStagingOperations(
                directorySize: directorySize,
                compressedSourceSize: compressedBundleSize,
                fileExists: fileExists,
                directoryExists: directoryExists,
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                removeItem: { url in
                    try fileStore.removeItem(at: url)
                },
                copyItem: { source, destination in
                    try fileStore.copyItem(at: source, to: destination)
                },
                requireFreeSpace: { url, minimumBytes, operation in
                    try storageMaintenance().requireFreeSpace(
                        at: url,
                        minimumBytes: minimumBytes,
                        operation: operation.rawValue
                    )
                },
                log: log
            )
        ).stage(input: input)
    }

    private func compressedBundleSize(_ url: URL) throws -> UInt64 {
        fileExists(url) ? try fileSize(url) : 0
    }

    private func directorySize(_ url: URL) throws -> UInt64 {
        try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
    }

    func replaceRuntimeUpdateArtifacts(_ artifacts: [UpdateBundleArtifact], stagedBundle: URL) throws {
        try runtimeArtifactReplacer().replace(artifacts, stagedBundle: stagedBundle)
    }

    func runRuntimeUpdateMigrations(_ migrations: [UpdateBundleMigration], stagedBundle: URL) throws {
        try RuntimeMigrationRunner(
            isExecutableFile: { path in fileStore.isExecutableFile(atPath: path) },
            runRequired: runRequired,
            log: log
        ).run(migrations, stagedBundle: stagedBundle)
    }

    func validateRuntimeUpdateArtifactPayload(_ artifact: UpdateBundleArtifact, source: URL) throws {
        try runtimeArtifactReplacer().validatePayload(artifact, source: source)
    }

    private func runtimeArtifactReplacer() -> RuntimeArtifactReplacer {
        RuntimeArtifactReplacer(
            destinations: RuntimeArtifactReplacementDestinations(
                managerApp: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxBundle: installedPaths.nginxDirectory,
                guestDeploy: installedPaths.deployDirectory,
                runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
            ),
            rules: RuntimeArtifactReplacementRules(
                tarCommand: Constants.Commands.tar,
                appBundleRoot: Constants.Product.managerAppName,
                nginxBundleRoot: "nginx",
                guestDeployRoot: "deploy",
                runtimeToolsAllowedRootEntries: [
                    "vitalserver-vm",
                    "vitalserver-proxy-run",
                    URL(fileURLWithPath: Constants.InstallPaths.uninstall).lastPathComponent,
                ]
            ),
            temporaryDirectory: fileStore.temporaryDirectory,
            fileExists: fileExists,
            directoryExists: directoryExists,
            fileSize: fileSize,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            removeItem: { url in try fileStore.removeItem(at: url) },
            moveItem: { source, destination in try fileStore.moveItem(at: source, to: destination) },
            readUTF8Text: { url in try fileStore.readUTF8Text(url) },
            runRequired: runRequired,
            runProcessToFile: runProcessToFile,
            log: log
        )
    }

    func resizeVMDiskIfNeeded(diskGiB: Int) throws {
        guard fileExists(vmDisk) else {
            throw LauncherError.missingFile(vmDisk.path)
        }
        let bytesPerGiB: UInt64 = 1024 * 1024 * 1024
        let currentGiB = Int((try fileSize(vmDisk) + bytesPerGiB - 1) / bytesPerGiB)
        guard diskGiB >= currentGiB else {
            throw LauncherError.missingArgument(
                "--disk-gib can only increase the VM disk; current disk is \(currentGiB) GiB"
            )
        }
        guard diskGiB > currentGiB else {
            return
        }
        try runRequired(Constants.Commands.truncate, arguments: ["-s", "\(diskGiB)G", vmDisk.path])
        log("resized vm disk path=\(vmDisk.path) from=\(currentGiB) GiB to=\(diskGiB) GiB")
    }

    func createReplacementVMDisk(_ plan: RepairRuntimeVMDiskReplacementBuildPlan) throws {
        try runProcessToFile(
            Constants.Commands.gunzip,
            arguments: ["-c", plan.rootfsBase.path],
            output: plan.temporaryDisk
        )
        try runRequired(
            Constants.Commands.truncate,
            arguments: ["-s", "\(plan.targetDiskGiB)G", plan.temporaryDisk.path]
        )
    }

    func storageMaintenance() -> RuntimeStorageMaintenance {
        RuntimeStorageMaintenance(
            fileStore: fileStore,
            configuration: RuntimeStorageMaintenanceConfiguration(
                backupKeepCount: Constants.Runtime.backupKeepCount,
                stagedBundleKeepCount: Constants.Runtime.stagedBundleKeepCount
            ),
            log: log
        )
    }
}
