import Application
import Bootstrap
import Foundation
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Workflow
import Errors

public struct RuntimeBundleCompositionContext {
    let installedPaths: InstalledRuntimePaths
    let bundlesDirectory: URL
    let backupsDirectory: URL
    let logsDirectory: URL
    let rootfsBase: URL
    let vmDisk: URL

    public init(
        installedPaths: InstalledRuntimePaths,
        bundlesDirectory: URL,
        backupsDirectory: URL,
        logsDirectory: URL,
        rootfsBase: URL,
        vmDisk: URL
    ) {
        self.installedPaths = installedPaths
        self.bundlesDirectory = bundlesDirectory
        self.backupsDirectory = backupsDirectory
        self.logsDirectory = logsDirectory
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
    }
}

public struct RuntimeBundleCompositionOperations {
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
    let materializeBundle: (URL) throws -> RuntimeMaterializedBundle
    let executeMaterializationCleanupPlan: (RuntimeBundleMaterializationCleanupPlan) -> Void
    let removeMaterializedBundleTemporaryRoot: (URL) -> Void
    let stageMaterializedBundle: (RuntimeBundleStagingInput) throws -> URL
    let validateUpdateArtifactPayload: (UpdateBundleArtifact, URL) throws -> Void
    let replaceUpdateArtifacts: ([UpdateBundleArtifact], URL) throws -> Void
    let runMigrations: ([UpdateBundleMigration], URL) throws -> Void
    let requireFreeSpace: (URL, UInt64, RuntimeOperation) throws -> Void
    let directorySize: (URL) throws -> UInt64
    let replaceFile: (URL, URL) throws -> Void
    let writeRuntimeVersion: (String, URL) throws -> Void
    let refreshCloudInitSeedIfNeeded: (UpdateBundleManifest) throws -> Void
    let activateGuestUpdateIfNeeded: (UpdateBundleManifest) throws -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let requireGuestCapability: (RuntimeGuestCapabilityRequirement) throws -> Void
    let acquireOperationLease: (RuntimeOperation) throws -> RuntimeOperationLeaseDocument
    let releaseOperationLease: (RuntimeOperationLeaseDocument) throws -> Void
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        runtimeHealthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        rotateRuntimeLogs: @escaping () throws -> Void,
        rollback: @escaping (URL?) throws -> Void,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        runningVMProcessID: @escaping () throws -> pid_t,
        stopRuntimeServicesAfterGuestPoweroff: @escaping (pid_t) throws -> Void,
        prepareGuestShutdownForUpdate: @escaping (UpdateBundleManifest) throws -> Void,
        clearGuestShutdownPreparation: @escaping () throws -> Void,
        isLaunchdLoaded: @escaping (RuntimeManagedService) -> Bool,
        createBackup: @escaping (String) throws -> URL,
        statusReporter: RuntimeWorkflowStatusReporter,
        pruneOldRuntimeArtifacts: @escaping () throws -> Void,
        materializeBundle: @escaping (URL) throws -> RuntimeMaterializedBundle,
        executeMaterializationCleanupPlan: @escaping (RuntimeBundleMaterializationCleanupPlan) -> Void,
        removeMaterializedBundleTemporaryRoot: @escaping (URL) -> Void,
        stageMaterializedBundle: @escaping (RuntimeBundleStagingInput) throws -> URL,
        validateUpdateArtifactPayload: @escaping (UpdateBundleArtifact, URL) throws -> Void,
        replaceUpdateArtifacts: @escaping ([UpdateBundleArtifact], URL) throws -> Void,
        runMigrations: @escaping ([UpdateBundleMigration], URL) throws -> Void,
        requireFreeSpace: @escaping (URL, UInt64, RuntimeOperation) throws -> Void,
        directorySize: @escaping (URL) throws -> UInt64,
        replaceFile: @escaping (URL, URL) throws -> Void,
        writeRuntimeVersion: @escaping (String, URL) throws -> Void,
        refreshCloudInitSeedIfNeeded: @escaping (UpdateBundleManifest) throws -> Void,
        activateGuestUpdateIfNeeded: @escaping (UpdateBundleManifest) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        requireGuestCapability: @escaping (RuntimeGuestCapabilityRequirement) throws -> Void,
        acquireOperationLease: @escaping (RuntimeOperation) throws -> RuntimeOperationLeaseDocument,
        releaseOperationLease: @escaping (RuntimeOperationLeaseDocument) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.runtimeHealthSnapshot = runtimeHealthSnapshot
        self.rotateRuntimeLogs = rotateRuntimeLogs
        self.rollback = rollback
        self.startRuntimeServices = startRuntimeServices
        self.stopRuntimeServices = stopRuntimeServices
        self.runningVMProcessID = runningVMProcessID
        self.stopRuntimeServicesAfterGuestPoweroff = stopRuntimeServicesAfterGuestPoweroff
        self.prepareGuestShutdownForUpdate = prepareGuestShutdownForUpdate
        self.clearGuestShutdownPreparation = clearGuestShutdownPreparation
        self.isLaunchdLoaded = isLaunchdLoaded
        self.createBackup = createBackup
        self.statusReporter = statusReporter
        self.pruneOldRuntimeArtifacts = pruneOldRuntimeArtifacts
        self.materializeBundle = materializeBundle
        self.executeMaterializationCleanupPlan = executeMaterializationCleanupPlan
        self.removeMaterializedBundleTemporaryRoot = removeMaterializedBundleTemporaryRoot
        self.stageMaterializedBundle = stageMaterializedBundle
        self.validateUpdateArtifactPayload = validateUpdateArtifactPayload
        self.replaceUpdateArtifacts = replaceUpdateArtifacts
        self.runMigrations = runMigrations
        self.requireFreeSpace = requireFreeSpace
        self.directorySize = directorySize
        self.replaceFile = replaceFile
        self.writeRuntimeVersion = writeRuntimeVersion
        self.refreshCloudInitSeedIfNeeded = refreshCloudInitSeedIfNeeded
        self.activateGuestUpdateIfNeeded = activateGuestUpdateIfNeeded
        self.waitForHealth = waitForHealth
        self.requireGuestCapability = requireGuestCapability
        self.acquireOperationLease = acquireOperationLease
        self.releaseOperationLease = releaseOperationLease
        self.log = log
    }
}

public struct RuntimeBundleComposition {
    let context: RuntimeBundleCompositionContext
    let operations: RuntimeBundleCompositionOperations

    public init(
        context: RuntimeBundleCompositionContext,
        operations: RuntimeBundleCompositionOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func verifyBundle(_ bundleURL: URL) throws {
        let result = try PrepareRuntimeBundleUseCase().verifyBundle(
            bundleURL,
            operations: runtimeBundlePreparationOperations()
        )
        print("bundle verified: \(result.sourceURL.path)")
    }

    @discardableResult
    public func stageBundle(_ bundleURL: URL) throws -> URL {
        let result = try PrepareRuntimeBundleUseCase().stageBundle(
            bundleURL,
            operations: runtimeBundlePreparationOperations()
        )
        print("bundle staged: \(result.destinationURL.path)")
        return result.destinationURL
    }

    public func applyBundle(_ bundleURL: URL) throws {
        let operationLease = try operations.acquireOperationLease(.applyBundle)
        defer {
            do {
                try operations.releaseOperationLease(operationLease)
            } catch {
                operations.log("runtime operation lease release failed operation=\(operationLease.operation.rawValue) operationId=\(operationLease.operationId) error=\(RuntimeErrorDescription.describe(error))")
            }
        }
        try RuntimeApplyBundleWorkflow().run(
            input: ApplyRuntimeBundleInput(bundleURL: bundleURL),
            operations: applyRuntimeBundleOperations()
        )
        operations.log(ApplyRuntimeBundleUseCase().mutableVMDiskPreservedLogMessage(path: context.vmDisk.path))
    }

    private func runtimeBundlePreparationOperations() -> RuntimeBundlePreparationOperations {
        RuntimeBundlePreparationOperations(
            materialize: operations.materializeBundle,
            executeMaterializationCleanupPlan: operations.executeMaterializationCleanupPlan,
            verifyDirectory: verifyBundleDirectory,
            stageBundle: operations.stageMaterializedBundle,
            log: operations.log
        )
    }

    private func verifyBundleDirectory(_ bundleURL: URL, sourceURL: URL) throws -> UpdateBundleManifest {
        let verificationFileReader = bundleVerificationFileReader()
        let digestUseCase = VerifyRuntimeBundleDigestUseCase()
        return try RuntimeBundleDirectoryVerifier(
            context: RuntimeBundleDirectoryVerificationContext(
                manifestFileName: Constants.Bundle.manifest,
                checksumsFileName: Constants.Bundle.checksums,
                signatureFileName: Constants.Bundle.signature
            ),
            operations: RuntimeBundleDirectoryVerificationOperations(
                requireDirectory: { url in
                    switch operations.fileStore.pathState(at: url) {
                    case .directory:
                        break
                    case .missing:
                        throw LauncherError.missingFile(url.path)
                    case .inspectFailed(let reason):
                        throw LauncherError.runtimeOperationFailed(
                            "bundle directory path inspection failed: \(url.path) reason=\(reason)"
                        )
                    case .file, .other, .unknown:
                        throw LauncherError.runtimeOperationFailed(
                            "bundle directory path state is unexpected: \(url.path) state=\(operations.fileStore.pathState(at: url).rawValue)"
                        )
                    }
                },
                requireFile: { url in
                    switch operations.fileStore.pathState(at: url) {
                    case .file:
                        break
                    case .missing:
                        throw LauncherError.missingFile(url.path)
                    case .inspectFailed(let reason):
                        throw LauncherError.runtimeOperationFailed(
                            "bundle file path inspection failed: \(url.path) reason=\(reason)"
                        )
                    case .directory, .other, .unknown:
                        throw LauncherError.runtimeOperationFailed(
                            "bundle file path state is unexpected: \(url.path) state=\(operations.fileStore.pathState(at: url).rawValue)"
                        )
                    }
                },
                loadManifest: verificationFileReader.loadManifest,
                makeVerificationPlan: { manifest in
                    try MakeUpdateBundleVerificationPlanUseCase().makePlan(
                        manifest: manifest,
                        expectedProduct: Constants.Product.identifier
                    )
                },
                loadChecksums: verificationFileReader.loadChecksums,
                verifyDigest: { url, fileVerification, checksumMap in
                    try digestUseCase.verify(
                        input: RuntimeBundleDigestVerificationInput(
                            fileURL: url,
                            fileVerification: fileVerification,
                            checksumMap: checksumMap
                        ),
                        operations: RuntimeBundleDigestVerificationOperations(
                            sha256: verificationFileReader.sha256,
                            fileSize: fileSize,
                            log: operations.log
                        )
                    )
                },
                validateArtifactPayload: operations.validateUpdateArtifactPayload,
                log: operations.log
            )
        ).verify(bundleURL: bundleURL, sourceURL: sourceURL)
    }

    public func removeMaterializedBundleTemporaryRoot(_ temporaryRoot: URL) {
        operations.removeMaterializedBundleTemporaryRoot(temporaryRoot)
    }

    private func applyRuntimeBundleOperations() -> ApplyRuntimeBundleOperations {
        ApplyRuntimeBundleOperations(
            prepareLogs: {
                prepareApplyBundleLogs(context.logsDirectory)
            },
            initialHealthSnapshot: operations.runtimeHealthSnapshot,
            preparePreflight: { bundleURL in
                try executeApplyBundlePreflight(ApplyRuntimeBundlePreflightInput(
                    bundleURL: bundleURL,
                    backupsDirectory: context.backupsDirectory,
                    rootfsBase: context.rootfsBase,
                    updateFreeSpaceMarginBytes: Constants.Runtime.updateFreeSpaceMarginBytes,
                    currentUpdaterVersion: Constants.launcherVersion,
                    currentChannel: Constants.launcherChannel,
                    currentPlatform: Constants.Platform.current
                ))
            },
            rootfsBase: context.rootfsBase,
            runningVMProcessID: operations.runningVMProcessID,
            prepareGuestShutdownForUpdate: operations.prepareGuestShutdownForUpdate,
            clearGuestShutdownPreparation: operations.clearGuestShutdownPreparation,
            stopRuntimeServicesAfterGuestPoweroff: operations.stopRuntimeServicesAfterGuestPoweroff,
            stopRuntimeServices: operations.stopRuntimeServices,
            createDirectory: { url, withIntermediateDirectories in
                try operations.fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            fileSize: fileSize,
            replaceFile: operations.replaceFile,
            replaceUpdateArtifacts: operations.replaceUpdateArtifacts,
            runMigrations: operations.runMigrations,
            refreshCloudInitSeedIfNeeded: operations.refreshCloudInitSeedIfNeeded,
            writeRuntimeVersion: operations.writeRuntimeVersion,
            startRuntimeServices: operations.startRuntimeServices,
            activateGuestUpdateIfNeeded: operations.activateGuestUpdateIfNeeded,
            waitForHealth: operations.waitForHealth,
            rollback: operations.rollback,
            writeStatus: { status, operation, message in
                try operations.statusReporter.write(status, operation: operation, message: message)
            },
            writeBestEffortStatus: { status, operation, message in
                operations.statusReporter.writeBestEffort(status, operation: operation, message: message)
            },
            publishProgress: operations.statusReporter.publishProgress,
            pruneOldRuntimeArtifacts: operations.pruneOldRuntimeArtifacts,
            describeError: RuntimeErrorDescription.describe,
            log: operations.statusReporter.log
        )
    }

    private func executeApplyBundlePreflight(
        _ input: ApplyRuntimeBundlePreflightInput
    ) throws -> ApplyBundlePreflightContext {
        try ApplyRuntimeBundlePreflightUseCase().prepare(
            input: input,
            operations: ApplyRuntimeBundlePreflightOperations(
                stageBundle: stageBundle,
                loadStagedManifest: { stagedBundle in
                    try bundleVerificationFileReader().loadManifest(
                        stagedBundle.appendingPathComponent(Constants.Bundle.manifest)
                    )
                },
                observeRootfsStorage: { stagedRootfs, rootfsBase in
                    try observeRootfsStorage(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase)
                },
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                requireFreeSpace: operations.requireFreeSpace,
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
                directorySize: operations.directorySize,
                log: operations.log
            )
        )
    }

    private func prepareApplyBundleLogs(_ logsDirectory: URL) {
        do {
            try operations.fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            operations.log(ApplyRuntimeBundleUseCase().applyBundleLogDirectoryPreparationFailedLogMessage(
                reason: RuntimeErrorDescription.describe(error)
            ))
        }
        do {
            try operations.rotateRuntimeLogs()
        } catch {
            operations.log(ApplyRuntimeBundleUseCase().applyBundleLogRotationFailedLogMessage(
                reason: RuntimeErrorDescription.describe(error)
            ))
        }
    }

    private func observeRootfsStorage(
        stagedRootfs: URL,
        rootfsBase: URL
    ) throws -> ApplyRuntimeBundleRootfsStorageObservation {
        let stagedRootfsState = operations.fileStore.pathState(at: stagedRootfs)
        return ApplyRuntimeBundleRootfsStorageObservation(
            stagedRootfs: stagedRootfs,
            stagedRootfsState: stagedRootfsState,
            installedRootfsBytes: stagedRootfsState == .file ? try fileSize(rootfsBase) : nil,
            incomingRootfsBytes: stagedRootfsState == .file ? try fileSize(stagedRootfs) : nil
        )
    }

    private func bundleVerificationFileReader() -> RuntimeBundleVerificationFileReader {
        RuntimeBundleVerificationFileReader(
            operations: RuntimeBundleVerificationFileReaderOperations(
                readData: operations.fileStore.readData,
                readUTF8Text: operations.fileStore.readUTF8Text,
                parseChecksums: ParseUpdateBundleChecksumFileUseCase().parse
            )
        )
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        try operations.fileStore.fileSize(url)
    }

}
