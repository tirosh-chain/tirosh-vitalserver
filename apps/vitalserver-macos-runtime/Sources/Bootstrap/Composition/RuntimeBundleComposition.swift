import CryptoKit
import Application
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
        requireFreeSpace: @escaping (URL, UInt64, RuntimeOperation) throws -> Void,
        runProcess: @escaping (String, [String]) -> RuntimeProcessResult,
        runRequired: @escaping (String, [String]) throws -> Void,
        runProcessToFile: @escaping (String, [String], URL) throws -> Void,
        replaceFile: @escaping (URL, URL) throws -> Void,
        writeRuntimeVersion: @escaping (String, URL) throws -> Void,
        refreshCloudInitSeedIfNeeded: @escaping (UpdateBundleManifest) throws -> Void,
        activateGuestUpdateIfNeeded: @escaping (UpdateBundleManifest) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        requireGuestCapability: @escaping (RuntimeGuestCapabilityRequirement) throws -> Void,
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
        self.requireFreeSpace = requireFreeSpace
        self.runProcess = runProcess
        self.runRequired = runRequired
        self.runProcessToFile = runProcessToFile
        self.replaceFile = replaceFile
        self.writeRuntimeVersion = writeRuntimeVersion
        self.refreshCloudInitSeedIfNeeded = refreshCloudInitSeedIfNeeded
        self.activateGuestUpdateIfNeeded = activateGuestUpdateIfNeeded
        self.waitForHealth = waitForHealth
        self.requireGuestCapability = requireGuestCapability
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
        let result = try runtimeBundlePreparationWorkflow().verifyBundle(bundleURL)
        print("bundle verified: \(result.sourceURL.path)")
    }

    @discardableResult
    public func stageBundle(_ bundleURL: URL) throws -> URL {
        let result = try runtimeBundlePreparationWorkflow().stageBundle(bundleURL)
        print("bundle staged: \(result.destinationURL.path)")
        return result.destinationURL
    }

    public func applyBundle(_ bundleURL: URL) throws {
        try runtimeApplyBundleWorkflow().applyBundle(bundleURL)
    }

    private func runtimeBundlePreparationWorkflow() -> RuntimeBundlePreparationWorkflow {
        RuntimeBundlePreparationWorkflow(
            operations: RuntimeBundlePreparationWorkflowOperations(
                materialize: { url in
                    try runtimeBundleMaterializer().materialize(url)
                },
                executeMaterializationCleanupPlan: executeMaterializationCleanupPlan,
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

    public func removeMaterializedBundleTemporaryRoot(_ temporaryRoot: URL) {
        do {
            try operations.fileStore.removeItem(at: temporaryRoot)
        } catch {
            operations.log(
                "bundle temporary directory cleanup failed path=\(temporaryRoot.path) error=\(RuntimeErrorDescription.describe(error))"
            )
        }
    }

    private func executeMaterializationCleanupPlan(_ plan: RuntimeBundleMaterializationCleanupPlan) {
        switch plan {
        case .none:
            return
        case .cleanupTemporaryRoot(let temporaryRoot):
            removeMaterializedBundleTemporaryRoot(temporaryRoot)
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
                executePreflight: executeApplyBundlePreflight,
                runtimeHealthSnapshot: operations.runtimeHealthSnapshot,
                executeInitialHealthWarningPlan: executeInitialHealthWarningPlan,
                executePreflightFailurePlan: executeApplyBundlePreflightFailurePlan,
                prepareLogs: prepareApplyBundleLogs,
                executeFailureRecoveryPlan: executeApplyBundleFailureRecoveryPlan,
                statusReporter: operations.statusReporter,
                pruneOldRuntimeArtifacts: operations.pruneOldRuntimeArtifacts,
                executeApplyBundleStepPlan: executeApplyBundleStepPlan,
                describeError: RuntimeErrorDescription.describe,
                log: operations.log
            )
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
                    try loadManifest(stagedBundle.appendingPathComponent(Constants.Bundle.manifest))
                },
                resolveRootfsStorage: resolveRootfsStorage,
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
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
                executeCapabilityInstruction: executePreflightCapabilityInstruction,
                createBackup: operations.createBackup,
                directorySize: directorySize,
                log: operations.log
            )
        )
    }

    private func prepareApplyBundleLogs(_ logsDirectory: URL) {
        do {
            try operations.fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            operations.log(UpdateRuntimeUseCase().applyBundleLogDirectoryPreparationFailedLogMessage(
                reason: RuntimeErrorDescription.describe(error)
            ))
        }
        do {
            try operations.rotateRuntimeLogs()
        } catch {
            operations.log(UpdateRuntimeUseCase().applyBundleLogRotationFailedLogMessage(
                reason: RuntimeErrorDescription.describe(error)
            ))
        }
    }

    private func loadManifest(_ url: URL) throws -> UpdateBundleManifest {
        let data = try operations.fileStore.readData(url)
        return try JSONDecoder().decode(UpdateBundleManifest.self, from: data)
    }

    private func observeRootfsStorage(
        stagedRootfs: URL,
        rootfsBase: URL
    ) throws -> ApplyRuntimeBundleRootfsStorageObservation {
        let stagedRootfsExists = fileExists(stagedRootfs)
        return ApplyRuntimeBundleRootfsStorageObservation(
            stagedRootfs: stagedRootfs,
            stagedRootfsExists: stagedRootfsExists,
            installedRootfsBytes: stagedRootfsExists ? try fileSize(rootfsBase) : nil,
            incomingRootfsBytes: stagedRootfsExists ? try fileSize(stagedRootfs) : nil
        )
    }

    private func resolveRootfsStorage(
        plan: ApplyRuntimeBundleRootfsStorageObservationPlan
    ) throws -> ApplyRuntimeBundleRootfsStoragePreflightPlan {
        let decision: ApplyRuntimeBundleRootfsStorageDecision
        switch plan {
        case .unchanged(let rootfsStoragePlan):
            decision = .planned(rootfsStoragePlan)
        case .replacing(let stagedRootfs, let rootfsBase):
            decision = UpdateRuntimeUseCase().rootfsStorageDecision(
                observation: try observeRootfsStorage(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase)
            )
        }
        return try executeRootfsStorageDecision(decision)
    }

    private func executeRootfsStorageDecision(
        _ decision: ApplyRuntimeBundleRootfsStorageDecision
    ) throws -> ApplyRuntimeBundleRootfsStoragePreflightPlan {
        switch decision {
        case .planned(let plan):
            return plan
        case .failed(let message):
            throw RuntimeApplyBundleWorkflowError.operationFailed(message)
        }
    }

    private func executePreflightCapabilityInstruction(
        _ instruction: ApplyRuntimeBundlePreflightCapabilityInstruction
    ) throws {
        switch instruction {
        case .requireRuntimeDiskHealthAllowsUpdate:
            try requireRuntimeDiskHealthAllowsUpdate()
        case .requireGuestCapability(let capability):
            try operations.requireGuestCapability(capability)
        }
    }

    private func executeInitialHealthWarningPlan(_ plan: ApplyRuntimeBundleInitialHealthWarningPlan) {
        switch plan {
        case .continueWithoutWarning:
            return
        case .continueWithWarning(let logMessage):
            operations.log(logMessage)
        }
    }

    private func executeApplyBundlePreflightFailurePlan(_ plan: ApplyRuntimeBundlePreflightFailurePlan) {
        operations.statusReporter.writeBestEffort(
            plan.statusPlan.status,
            operation: plan.statusPlan.operation,
            message: plan.statusPlan.message
        )
    }

    private func executeApplyBundleFailureRecoveryPlan(_ plan: ApplyRuntimeBundleFailureRecoveryPlan) {
        operations.log(plan.rollbackStartedPlan.logMessage)
        operations.statusReporter.writeBestEffort(
            plan.rollbackStartedPlan.status,
            operation: plan.rollbackStartedPlan.operation,
            message: plan.rollbackStartedPlan.statusMessage
        )
        do {
            try operations.rollback(plan.backup)
            try operations.startRuntimeServices(plan.restartPolicy)
            operations.statusReporter.writeBestEffort(
                plan.rollbackCompletedPlan.status,
                operation: plan.rollbackCompletedPlan.operation,
                message: plan.rollbackCompletedPlan.message
            )
        } catch {
            let rollbackFailedPlan = UpdateRuntimeUseCase().applyBundleRollbackFailedPlan(
                reason: RuntimeErrorDescription.describe(error)
            )
            operations.log(rollbackFailedPlan.logMessage)
            startRuntimeServicesBestEffort(plan.restartPolicy)
            operations.statusReporter.writeBestEffort(
                rollbackFailedPlan.status,
                operation: rollbackFailedPlan.operation,
                message: rollbackFailedPlan.statusMessage
            )
        }
    }

    private func startRuntimeServicesBestEffort(_ policy: RuntimeServiceRestartPolicy) {
        do {
            try operations.startRuntimeServices(policy)
        } catch {
            operations.log(UpdateRuntimeUseCase().applyBundleRollbackFailureServiceRestartFailedLogMessage(
                reason: RuntimeErrorDescription.describe(error)
            ))
        }
    }

    private func requireRuntimeDiskHealthAllowsUpdate() throws {
        let useCase = UpdateRuntimeUseCase()
        let decision = useCase.diskHealthDecision(snapshot: operations.runtimeHealthSnapshot())
        switch decision {
        case .allowed:
            return
        case .blocked(_, let logMessage, let failureMessage):
            operations.log(logMessage)
            throw RuntimeApplyBundleWorkflowError.operationFailed(failureMessage)
        }
    }

    private func executeApplyBundleStepPlan(_ executionPlan: ApplyRuntimeBundleStepExecutionPlan) throws {
        switch executionPlan {
        case .stopRuntimeServices(let stopPlan):
            try executeApplyBundleStopPlan(stopPlan)
        case .replaceRootfsBase(let rootfsPlan):
            try executeApplyBundleRootfsReplacementPlan(rootfsPlan)
        case .replaceUpdateArtifacts(let artifacts, let stagedBundle):
            try replaceUpdateArtifacts(artifacts, stagedBundle: stagedBundle)
        case .runMigrations(let migrations, let stagedBundle):
            try runMigrations(migrations, stagedBundle: stagedBundle)
        case .refreshCloudInitSeed(let manifest):
            try operations.refreshCloudInitSeedIfNeeded(manifest)
        case .writeRuntimeVersion(let version, let stagedBundle):
            try operations.writeRuntimeVersion(version, stagedBundle)
        case .startRuntimeServices(let restartPolicy):
            try operations.startRuntimeServices(restartPolicy)
        case .activateGuestUpdate(let manifest):
            try operations.activateGuestUpdateIfNeeded(manifest)
        case .waitRuntimeHealth(let restartPolicy):
            try operations.waitForHealth(restartPolicy)
        case .unsupported(let failureMessage):
            throw RuntimeApplyBundleWorkflowError.operationFailed(failureMessage)
        }
    }

    private func executeApplyBundleStopPlan(_ stopPlan: ApplyRuntimeBundleStopExecutionPlan) throws {
        switch stopPlan {
        case .prepareGuestShutdownAndStopServicesAfterPoweroff(let manifest):
            let expectedVMProcessID = try operations.runningVMProcessID()
            operations.log(UpdateRuntimeUseCase().capturedVMProcessBeforeGuestUpdateShutdownLogMessage(
                processID: expectedVMProcessID
            ))
            try operations.prepareGuestShutdownForUpdate(manifest)
            defer { clearGuestShutdownPreparationAfterRuntimeStop() }
            try operations.stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID)
        case .stopServicesDirectly:
            try operations.stopRuntimeServices()
        }
    }

    private func executeApplyBundleRootfsReplacementPlan(_ rootfsPlan: ApplyRuntimeBundleRootfsReplacementPlan) throws {
        switch rootfsPlan {
        case .skip(let logMessage):
            operations.log(logMessage)
        case .replace(let stagedRootfs, let rootfsBase):
            try operations.fileStore.createDirectory(
                at: rootfsBase.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let executionPlan = UpdateRuntimeUseCase().rootfsReplacementExecutionPlan(
                observation: try observeRootfsReplacement(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase)
            )
            operations.log(executionPlan.startedLogMessage)
            try operations.replaceFile(stagedRootfs, rootfsBase)
            operations.log(executionPlan.completedLogMessage)
        }
    }

    private func clearGuestShutdownPreparationAfterRuntimeStop() {
        do {
            try operations.clearGuestShutdownPreparation()
        } catch {
            operations.log(UpdateRuntimeUseCase().guestShutdownPreparationCleanupFailedLogMessage(
                reason: RuntimeErrorDescription.describe(error)
            ))
        }
    }

    private func observeRootfsReplacement(
        stagedRootfs: URL,
        rootfsBase: URL
    ) throws -> ApplyRuntimeBundleRootfsReplacementObservation {
        ApplyRuntimeBundleRootfsReplacementObservation(
            stagedRootfs: stagedRootfs,
            rootfsBase: rootfsBase,
            stagedRootfsBytes: try fileSize(stagedRootfs)
        )
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
