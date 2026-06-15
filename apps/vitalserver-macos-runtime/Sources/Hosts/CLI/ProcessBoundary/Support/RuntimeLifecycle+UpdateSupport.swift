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
        let archiveValidator = ValidateUpdateBundleArchiveUseCase()
        return try RuntimeBundleMaterializer(
            context: RuntimeBundleMaterializationContext(
                tarExecutable: Constants.Commands.tar
            ),
            operations: RuntimeBundleMaterializationOperations(
                pathState: { url in
                    fileStore.pathState(at: url)
                },
                temporaryRoot: {
                    fileStore.temporaryDirectory
                        .appendingPathComponent("tirosh-update-bundle-\(UUID().uuidString)", isDirectory: true)
                },
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                runProcess: runProcess,
                runRequired: runRequired,
                rootDirectory: archiveValidator.rootDirectory,
                validateArchiveEntryTypes: archiveValidator.rejectUnsupportedEntryTypes,
                missingFileError: { url in
                    LauncherError.missingFile(url.path)
                },
                invalidArchiveError: { url in
                    LauncherError.bundleVerificationFailed("invalid update bundle archive: \(url.path)")
                },
                pathInspectionError: { url, reason in
                    LauncherError.runtimeOperationFailed(
                        "update bundle path inspection failed: \(url.path) reason=\(reason)"
                    )
                },
                unexpectedPathStateError: { url, state in
                    LauncherError.runtimeOperationFailed(
                        "update bundle path state is unexpected: \(url.path) state=\(state.rawValue)"
                    )
                },
                archiveValidationError: { error in
                    LauncherError.bundleVerificationFailed(String(describing: error))
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
                destinationState: { url in
                    fileStore.pathState(at: url)
                },
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
        switch fileStore.pathState(at: url) {
        case .file:
            return try fileSize(url)
        case .missing:
            return 0
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "compressed update bundle path inspection failed: \(url.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "compressed update bundle path state is unexpected: \(url.path) state=\(fileStore.pathState(at: url).rawValue)"
            )
        }
    }

    private func directorySize(_ url: URL) throws -> UInt64 {
        try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
    }

    func replaceRuntimeUpdateArtifacts(_ artifacts: [UpdateBundleArtifact], stagedBundle: URL) throws {
        try runtimeArtifactReplacer().replace(artifacts, stagedBundle: stagedBundle)
    }

    func runRuntimeUpdateMigrations(_ migrations: [UpdateBundleMigration], stagedBundle: URL) throws {
        try RuntimeMigrationRunner(
            executableState: { path in fileStore.fileState(atPath: path) },
            runRequired: runRequired,
            log: log
        ).run(migrations, stagedBundle: stagedBundle)
    }

    func validateRuntimeUpdateArtifactPayload(_ artifact: UpdateBundleArtifact, source: URL) throws {
        try runtimeArtifactReplacer().validatePayload(artifact, source: source)
    }

    private func runtimeArtifactReplacer() -> RuntimeArtifactReplacer {
        let archiveValidator = ValidateUpdateBundleArchiveUseCase()
        return RuntimeArtifactReplacer(
            destinations: RuntimeArtifactReplacementDestinations(
                managerApp: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxBundle: installedPaths.nginxDirectory,
                guestDeploy: installedPaths.deployDirectory,
                runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
            ),
            rules: RuntimeArtifactReplacementRules(
                tarCommand: Constants.Commands.tar
            ),
            temporaryDirectory: fileStore.temporaryDirectory,
            pathState: { url in
                fileStore.pathState(at: url)
            },
            fileSize: fileSize,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            removeItem: { url in try fileStore.removeItem(at: url) },
            moveItem: { source, destination in try fileStore.moveItem(at: source, to: destination) },
            readUTF8Text: { url in try fileStore.readUTF8Text(url) },
            runRequired: runRequired,
            runProcessToFile: runProcessToFile,
            validateArchiveEntries: archiveValidator.validateArtifactArchiveEntries,
            validateArchiveEntryTypes: archiveValidator.rejectUnsupportedEntryTypes,
            archiveValidationFailureMessage: { error, source in
                archiveValidator.artifactArchiveValidationFailureMessage(
                    error,
                    archiveName: source.lastPathComponent
                )
            },
            log: log
        )
    }

    func resizeVMDiskIfNeeded(diskGiB: Int) throws {
        switch fileStore.pathState(at: vmDisk) {
        case .file:
            break
        case .missing:
            throw LauncherError.missingFile(vmDisk.path)
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "VM disk path inspection failed: \(vmDisk.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "VM disk path state is unexpected: \(vmDisk.path) state=\(fileStore.pathState(at: vmDisk).rawValue)"
            )
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
