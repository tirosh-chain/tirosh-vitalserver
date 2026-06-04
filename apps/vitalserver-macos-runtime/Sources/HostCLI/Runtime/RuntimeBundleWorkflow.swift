import CryptoKit
import Foundation
import HostInfrastructure
import Core
import Contracts
import RuntimeWorkflow

struct RuntimeBundleWorkflowContext {
    let installedPaths: InstalledRuntimePaths
    let bundlesDirectory: URL
    let backupsDirectory: URL
    let logsDirectory: URL
    let rootfsBase: URL
    let vmDisk: URL
}

struct RuntimeBundleWorkflowOperations {
    let fileStore: RuntimeFileStore
    let runtimeHealthSnapshot: () -> RuntimeHealthSnapshot
    let rotateRuntimeLogs: () throws -> Void
    let rollback: (URL?) throws -> Void
    let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    let stopRuntimeServices: () throws -> Void
    let runningVMProcessID: () throws -> pid_t
    let stopRuntimeServicesAfterGuestPoweroff: (pid_t) throws -> Void
    let prepareGuestShutdownForUpdate: (UpdateBundleManifest) throws -> Void
    let clearGuestShutdownPreparation: () throws -> Void
    let isLaunchdLoaded: (RuntimeManagedService) -> Bool
    let createBackup: (String) throws -> URL
    let statusReporter: RuntimeWorkflowStatusReporter
    let pruneOldRuntimeArtifacts: () throws -> Void
    let reasonText: ([RuntimeFailureReason]) -> String
    let requireFreeSpace: (URL, UInt64, RuntimeOperation) throws -> Void
    let runProcess: (String, [String]) -> RuntimeProcessResult
    let runRequired: (String, [String]) throws -> Void
    let runProcessToFile: (String, [String], URL) throws -> Void
    let replaceFile: (URL, URL) throws -> Void
    let writeRuntimeVersion: (String, URL) throws -> Void
    let refreshCloudInitSeedIfNeeded: (UpdateBundleManifest) throws -> Void
    let activateGuestUpdateIfNeeded: (UpdateBundleManifest) throws -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let requireGuestCapability: (RuntimeGuestCapabilityRequirement) throws -> Void
    let log: (String) -> Void
}

struct RuntimeBundleWorkflow {
    let context: RuntimeBundleWorkflowContext
    let operations: RuntimeBundleWorkflowOperations

    func verifyBundle(_ bundleURL: URL) throws {
        let result = try runtimeBundlePreparationWorkflow().verifyBundle(bundleURL)
        print("bundle verified: \(result.sourceURL.path)")
    }

    @discardableResult
    func stageBundle(_ bundleURL: URL) throws -> URL {
        let result = try runtimeBundlePreparationWorkflow().stageBundle(bundleURL)
        print("bundle staged: \(result.destinationURL.path)")
        return result.destinationURL
    }

    func applyBundle(_ bundleURL: URL) throws {
        try runtimeApplyBundleWorkflow().applyBundle(bundleURL)
    }

    private func runtimeBundlePreparationWorkflow() -> RuntimeBundlePreparationWorkflow {
        RuntimeBundlePreparationWorkflow(
            operations: RuntimeBundlePreparationWorkflowOperations(
                materialize: { url in
                    try runtimeBundleMaterializer().materialize(url)
                },
                cleanupTemporaryRoot: removeMaterializedBundleTemporaryRoot,
                verifyDirectory: verifyBundleDirectory,
                stageBundle: stageMaterializedBundle,
                log: operations.log
            )
        )
    }

    private func stageMaterializedBundle(_ input: RuntimeBundleStagingInput) throws -> URL {
        try RuntimeBundleStager(
            context: RuntimeBundleStagingContext(
                bundlesDirectory: context.bundlesDirectory,
                updateFreeSpaceMarginBytes: Constants.Runtime.updateFreeSpaceMarginBytes
            ),
            operations: RuntimeBundleStagingOperations(
                directorySize: directorySize,
                compressedSourceSize: compressedBundleSize,
                fileExists: fileExists,
                directoryExists: directoryExists,
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                removeItem: { url in
                    try operations.fileStore.removeItem(at: url)
                },
                copyItem: { source, destination in
                    try operations.fileStore.copyItem(at: source, to: destination)
                },
                requireFreeSpace: operations.requireFreeSpace,
                log: operations.log
            )
        ).stage(input: input)
    }

    private func verifyBundleDirectory(_ bundleURL: URL, sourceURL: URL) throws -> UpdateBundleManifest {
        try RuntimeBundleDirectoryVerifier(
            context: RuntimeBundleDirectoryVerificationContext(
                manifestFileName: Constants.Bundle.manifest,
                checksumsFileName: Constants.Bundle.checksums,
                signatureFileName: Constants.Bundle.signature
            ),
            operations: RuntimeBundleDirectoryVerificationOperations(
                requireDirectory: { url in
                    guard directoryExists(url) else {
                        throw LauncherError.missingFile(url.path)
                    }
                },
                requireFile: { url in
                    guard fileExists(url) else {
                        throw LauncherError.missingFile(url.path)
                    }
                },
                loadManifest: loadManifest,
                makeVerificationPlan: makeBundleVerificationPlan,
                loadChecksums: loadChecksums,
                verifyDigest: { url, fileVerification, checksumMap in
                    try verifyDigestedFile(
                        url,
                        fileVerification: fileVerification,
                        checksumMap: checksumMap
                    )
                },
                validateArtifactPayload: validateUpdateArtifactPayload,
                log: operations.log
            )
        ).verify(bundleURL: bundleURL, sourceURL: sourceURL)
    }

    private func runtimeBundleMaterializer() -> RuntimeBundleMaterializer {
        RuntimeBundleMaterializer(
            context: RuntimeBundleMaterializationContext(
                tarExecutable: Constants.Commands.tar
            ),
            operations: RuntimeBundleMaterializationOperations(
                directoryExists: directoryExists,
                fileExists: fileExists,
                temporaryRoot: {
                    operations.fileStore.temporaryDirectory
                        .appendingPathComponent("tirosh-update-bundle-\(UUID().uuidString)", isDirectory: true)
                },
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                runProcess: operations.runProcess,
                runRequired: operations.runRequired,
                missingFileError: { url in
                    LauncherError.missingFile(url.path)
                },
                invalidArchiveError: { url in
                    LauncherError.bundleVerificationFailed("invalid update bundle archive: \(url.path)")
                },
                archiveValidationError: { error in
                    LauncherError.bundleVerificationFailed(error.description)
                },
                log: operations.log
            )
        )
    }

    func removeMaterializedBundleTemporaryRoot(_ temporaryRoot: URL) {
        do {
            try operations.fileStore.removeItem(at: temporaryRoot)
        } catch {
            operations.log("bundle temporary directory cleanup failed path=\(temporaryRoot.path) error=\(error)")
        }
    }

    private func compressedBundleSize(_ url: URL) throws -> UInt64 {
        fileExists(url) ? try fileSize(url) : 0
    }

    private func runtimeApplyBundleWorkflow() -> RuntimeApplyBundleWorkflow {
        RuntimeApplyBundleWorkflow(
            context: RuntimeApplyBundleWorkflowContext(
                backupsDirectory: context.backupsDirectory,
                logsDirectory: context.logsDirectory,
                rootfsBase: context.rootfsBase,
                vmDisk: context.vmDisk,
                updateFreeSpaceMarginBytes: Constants.Runtime.updateFreeSpaceMarginBytes
            ),
            operations: RuntimeApplyBundleWorkflowOperations(
                stageBundle: stageBundle,
                loadManifest: loadManifest,
                fileExists: fileExists,
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                fileSize: fileSize,
                directorySize: directorySize,
                requireFreeSpace: operations.requireFreeSpace,
                checkCompatibility: { manifest in
                    try RuntimeUpdatePreflightPolicy.checkCompatibility(
                        manifest: manifest,
                        currentUpdaterVersion: Constants.launcherVersion,
                        currentChannel: Constants.launcherChannel,
                        currentPlatform: Constants.Platform.current
                    )
                },
                serviceRestartPolicy: {
                    RuntimeServiceRestartPolicy(
                        restartVM: operations.isLaunchdLoaded(.vm),
                        restartGuestLogSync: operations.isLaunchdLoaded(.guestLogSync),
                        restartProxy: operations.isLaunchdLoaded(.proxy),
                        restartWatchdog: operations.isLaunchdLoaded(.watchdog)
                    )
                },
                runtimeHealthSnapshot: operations.runtimeHealthSnapshot,
                requireGuestCapability: operations.requireGuestCapability,
                createBackup: operations.createBackup,
                rotateRuntimeLogs: operations.rotateRuntimeLogs,
                rollback: { backup in
                    try operations.rollback(backup)
                },
                startRuntimeServices: operations.startRuntimeServices,
                statusReporter: operations.statusReporter,
                pruneOldRuntimeArtifacts: operations.pruneOldRuntimeArtifacts,
                reasonText: operations.reasonText,
                stopRuntimeServices: operations.stopRuntimeServices,
                runningVMProcessID: operations.runningVMProcessID,
                stopRuntimeServicesAfterGuestPoweroff: operations.stopRuntimeServicesAfterGuestPoweroff,
                prepareGuestShutdownForUpdate: operations.prepareGuestShutdownForUpdate,
                clearGuestShutdownPreparation: operations.clearGuestShutdownPreparation,
                replaceFile: operations.replaceFile,
                replaceUpdateArtifacts: { artifacts, stagedBundle in
                    try replaceUpdateArtifacts(artifacts, stagedBundle: stagedBundle)
                },
                runMigrations: { migrations, stagedBundle in
                    try runMigrations(migrations, stagedBundle: stagedBundle)
                },
                refreshCloudInitSeedIfNeeded: operations.refreshCloudInitSeedIfNeeded,
                writeRuntimeVersion: operations.writeRuntimeVersion,
                activateGuestUpdateIfNeeded: operations.activateGuestUpdateIfNeeded,
                waitForHealth: operations.waitForHealth,
                log: operations.log
            )
        )
    }

    private func loadManifest(_ url: URL) throws -> UpdateBundleManifest {
        let data = try operations.fileStore.readData(url)
        return try JSONDecoder().decode(UpdateBundleManifest.self, from: data)
    }

    private func loadChecksums(_ url: URL) throws -> [String: String] {
        let text = try operations.fileStore.readUTF8Text(url)
        return UpdateBundleChecksumFileParser.parse(text)
    }

    private func makeBundleVerificationPlan(_ manifest: UpdateBundleManifest) throws -> UpdateBundleVerificationPlan {
        do {
            return try UpdateBundleVerifier.makePlan(
                manifest: manifest,
                expectedProduct: Constants.Product.identifier
            )
        } catch let error as UpdateBundleVerificationError {
            throw launcherError(error)
        }
    }

    private func sha256(_ url: URL) throws -> String {
        let data = try operations.fileStore.readData(url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func verifyDigestedFile(
        _ url: URL,
        fileVerification: UpdateBundleFileVerification,
        checksumMap: [String: String]
    ) throws {
        do {
            try RuntimeBundleDigestVerifier(
                operations: RuntimeBundleDigestVerificationOperations(
                    sha256: sha256,
                    fileSize: fileSize,
                    log: operations.log
                )
            ).verify(input: RuntimeBundleDigestVerificationInput(
                fileURL: url,
                fileVerification: fileVerification,
                checksumMap: checksumMap
            ))
        } catch let error as UpdateBundleVerificationError {
            throw launcherError(error)
        }
    }

    private func launcherError(_ error: UpdateBundleVerificationError) -> LauncherError {
        switch error {
        case .unsupportedSchema(let schemaVersion):
            return .missingArgument("unsupported bundle schema: \(schemaVersion)")
        case .unsupportedProduct(let product):
            return .missingArgument("unsupported bundle product: \(product)")
        case .invalidArtifactName(let name):
            return .missingArgument("invalid artifact name: \(name)")
        case .invalidMigrationName(let name):
            return .missingArgument("invalid migration name: \(name)")
        case .unsupportedArtifactType(let type):
            return .bundleVerificationFailed("unsupported artifact type: \(type)")
        case .manifestChecksumMismatch(let checksumKey):
            return .bundleVerificationFailed("manifest checksum mismatch for \(checksumKey)")
        case .checksumFileMismatch(let checksumKey):
            return .bundleVerificationFailed("checksums.txt mismatch for \(checksumKey)")
        case .sizeMismatch(let checksumKey):
            return .bundleVerificationFailed("size mismatch for \(checksumKey)")
        }
    }

    private func runMigrations(_ migrations: [UpdateBundleMigration], stagedBundle: URL) throws {
        try RuntimeMigrationRunner(
            isExecutableFile: { path in operations.fileStore.isExecutableFile(atPath: path) },
            runRequired: operations.runRequired,
            log: operations.log
        ).run(migrations, stagedBundle: stagedBundle)
    }

    private func replaceUpdateArtifacts(_ artifacts: [UpdateBundleArtifact], stagedBundle: URL) throws {
        try makeArtifactReplacer().replace(artifacts, stagedBundle: stagedBundle)
    }

    private func validateUpdateArtifactPayload(_ artifact: UpdateBundleArtifact, source: URL) throws {
        try makeArtifactReplacer().validatePayload(artifact, source: source)
    }

    private func makeArtifactReplacer() -> RuntimeArtifactReplacer {
        RuntimeArtifactReplacer(
            destinations: RuntimeArtifactReplacementDestinations(
                managerApp: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxBundle: context.installedPaths.nginxDirectory,
                guestDeploy: context.installedPaths.deployDirectory,
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
            temporaryDirectory: operations.fileStore.temporaryDirectory,
            fileExists: fileExists,
            directoryExists: directoryExists,
            fileSize: fileSize,
            createDirectory: { url, withIntermediateDirectories in
                try operations.fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            removeItem: { url in try operations.fileStore.removeItem(at: url) },
            moveItem: { source, destination in try operations.fileStore.moveItem(at: source, to: destination) },
            readUTF8Text: { url in try operations.fileStore.readUTF8Text(url) },
            runRequired: operations.runRequired,
            runProcessToFile: operations.runProcessToFile,
            log: operations.log
        )
    }

    private func fileExists(_ url: URL) -> Bool {
        operations.fileStore.fileExists(url)
    }

    private func directoryExists(_ url: URL) -> Bool {
        operations.fileStore.directoryExists(url)
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        try operations.fileStore.fileSize(url)
    }

    private func directorySize(_ url: URL) throws -> UInt64 {
        try operations.fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
    }

}
