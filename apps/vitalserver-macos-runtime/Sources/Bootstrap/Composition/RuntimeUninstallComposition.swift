import Application
import Contracts
import Foundation
import OutboundAdapters
import Workflow
import Errors

public struct RuntimeUninstallCompositionContext {
    let installedPaths: InstalledRuntimePaths
    let pidFile: URL

    public init(
        installedPaths: InstalledRuntimePaths,
        pidFile: URL
    ) {
        self.installedPaths = installedPaths
        self.pidFile = pidFile
    }
}

public struct RuntimeUninstallCompositionOperations {
    let fileStore: RuntimeFileStore
    let configuredExternalVitalFilesDirectory: () -> RuntimeConfiguredExternalVitalFilesDirectoryRead
    let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    let createRedisBackup: () throws -> Void
    let disableRuntimeServicesForUninstall: () throws -> Void
    let stopRuntimeServices: () throws -> Void
    let cleanupHostProxyPortAfterStop: () throws -> Void
    let runProcess: (String, [String]) -> RuntimeProcessResult
    let now: () -> Date
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        configuredExternalVitalFilesDirectory: @escaping () -> RuntimeConfiguredExternalVitalFilesDirectoryRead,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        createRedisBackup: @escaping () throws -> Void,
        disableRuntimeServicesForUninstall: @escaping () throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        cleanupHostProxyPortAfterStop: @escaping () throws -> Void,
        runProcess: @escaping (String, [String]) -> RuntimeProcessResult,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.configuredExternalVitalFilesDirectory = configuredExternalVitalFilesDirectory
        self.serviceState = serviceState
        self.createRedisBackup = createRedisBackup
        self.disableRuntimeServicesForUninstall = disableRuntimeServicesForUninstall
        self.stopRuntimeServices = stopRuntimeServices
        self.cleanupHostProxyPortAfterStop = cleanupHostProxyPortAfterStop
        self.runProcess = runProcess
        self.now = now
        self.log = log
    }
}

public enum RuntimeUninstallComposition {
    public static func make(
        context: RuntimeUninstallCompositionContext,
        operations: RuntimeUninstallCompositionOperations
    ) -> RuntimeUninstallWorkflow {
        let vitalFilesDirectoryRead = operations.configuredExternalVitalFilesDirectory()
        let uninstallPaths = RuntimeUninstallPaths(
            productRoot: context.installedPaths.productRoot,
            managerApp: context.installedPaths.managerApp,
            defaultVitalFilesDirectory: context.installedPaths.vitalFilesDirectory,
            externalVitalFilesDirectory: vitalFilesDirectoryRead.externalDirectory,
            configuredVitalFilesDirectoryReadFailure: vitalFilesDirectoryRead.failure,
            launchDaemonPlists: RuntimeManagedService.stopOrder.map {
                URL(fileURLWithPath: RuntimeManagedServicePaths.launchDaemonPlist($0))
            },
            runtimeTools: [
                context.installedPaths.launcher,
                URL(fileURLWithPath: Constants.InstallPaths.proxyRun),
                context.installedPaths.uninstaller,
            ]
        )
        return RuntimeUninstallWorkflow(
            paths: uninstallPaths,
            readers: RuntimeUninstallStateReaders(
                serviceStates: {
                    Dictionary(uniqueKeysWithValues: RuntimeManagedService.stopOrder.map { service in
                        (service, operations.serviceState(service))
                    })
                },
                vmProcessState: {
                    ProcessState.inspect(pidFile: context.pidFile, fileStore: operations.fileStore)
                },
                packageReceiptStates: {
                    RuntimePackageReceiptStateReader.states(
                        identifiers: Constants.Product.packageReceiptIdentifiers,
                        runProcess: operations.runProcess
                    )
                },
                cleanupArtifactStates: { clean in
                    RuntimeInstallArtifactStateReader.states(
                        paths: cleanupArtifactPaths(clean: clean, paths: uninstallPaths).map(\.path)
                    )
                }
            ),
            effects: RuntimeUninstallEffects(
                createRedisBackup: operations.createRedisBackup,
                stopRuntimeServices: {
                    try operations.disableRuntimeServicesForUninstall()
                    try operations.stopRuntimeServices()
                    try operations.cleanupHostProxyPortAfterStop()
                },
                describeError: RuntimeErrorDescription.describe,
                executeFileRemoval: { paths, clean in
                    try executeFileRemoval(
                        paths: paths,
                        clean: clean,
                        operations: operations
                    )
                },
                executeReceiptForgetting: { identifiers, observedReceiptStates in
                    try executeReceiptForgetting(
                        identifiers: identifiers,
                        observedReceiptStates: observedReceiptStates,
                        operations: operations
                    )
                }
            ),
            writer: RuntimeUninstallStateWriter(
                writeState: { state, clean, message, blockers in
                    try RuntimeUninstallStateStore(
                        url: context.installedPaths.runtimeUninstallState,
                        fileStore: operations.fileStore,
                        now: operations.now
                    ).write(
                        state: state,
                        clean: clean,
                        message: message,
                        blockers: blockers
                    )
                }
            ),
            diagnostics: RuntimeUninstallDiagnostics(log: operations.log),
            packageReceiptIdentifiers: Constants.Product.packageReceiptIdentifiers
        )
    }

    private static func executeFileRemoval(
        paths: RuntimeUninstallPaths,
        clean: Bool,
        operations: RuntimeUninstallCompositionOperations
    ) throws {
        let useCase = UninstallRuntimeUseCase()
        var preservedPaths: RuntimeUninstallPreservedPaths?
        do {
            try removeFiles(
                paths: paths,
                clean: clean,
                preservedPaths: &preservedPaths,
                useCase: useCase,
                operations: operations
            )
        } catch {
            let blockers = restorePreservedDataAfterFailureIfNeeded(
                error: error,
                preserved: preservedPaths,
                useCase: useCase,
                operations: operations
            )
            throw RuntimeUninstallFileRemovalExecutionError(
                underlyingError: error,
                blockers: blockers
            )
        }
    }

    private static func removeFiles(
        paths: RuntimeUninstallPaths,
        clean: Bool,
        preservedPaths: inout RuntimeUninstallPreservedPaths?,
        useCase: UninstallRuntimeUseCase,
        operations: RuntimeUninstallCompositionOperations
    ) throws {
        operations.log(useCase.stepLogMessage(step: .removePlists, status: .started))
        for plist in paths.launchDaemonPlists {
            try removeIfPresent(plist, useCase: useCase, operations: operations)
        }
        operations.log(useCase.stepLogMessage(step: .removePlists, status: .completed))

        let preserved = clean ? nil : try preserveUserData(paths: paths, useCase: useCase, operations: operations)
        preservedPaths = preserved

        operations.log(useCase.stepLogMessage(step: .removeInstalledFiles, status: .started))
        let removalPlan = useCase.removalPlan(
            clean: clean,
            managerApp: paths.managerApp,
            productRoot: paths.productRoot,
            externalVitalFilesDirectory: paths.externalVitalFilesDirectory,
            configuredVitalFilesDirectoryReadFailure: paths.configuredVitalFilesDirectoryReadFailure
        )
        for target in removalPlan.targets {
            try safeRemove(target, useCase: useCase, operations: operations)
        }
        if let skippedExternalDirectoryLogMessage = removalPlan.skippedExternalDirectoryLogMessage {
            operations.log(skippedExternalDirectoryLogMessage)
        }
        operations.log(useCase.stepLogMessage(step: .removeInstalledFiles, status: .completed))

        operations.log(useCase.stepLogMessage(step: .removeRuntimeTools, status: .started))
        for tool in paths.runtimeTools {
            try removeIfPresent(tool, useCase: useCase, operations: operations)
        }
        operations.log(useCase.stepLogMessage(step: .removeRuntimeTools, status: .completed))

        if let preserved {
            operations.log(useCase.stepLogMessage(step: .restorePreservedUserData, status: .started))
            try restorePreservedPaths(preserved, useCase: useCase, operations: operations)
            operations.log(useCase.stepLogMessage(step: .restorePreservedUserData, status: .completed))
        }
    }

    private static func preserveUserData(
        paths: RuntimeUninstallPaths,
        useCase: UninstallRuntimeUseCase,
        operations: RuntimeUninstallCompositionOperations
    ) throws -> RuntimeUninstallPreservedPaths {
        operations.log(useCase.stepLogMessage(step: .preserveUserData, status: .started))
        let preserveRoot = useCase.preserveRootDirectory(
            temporaryDirectory: operations.fileStore.temporaryDirectory,
            uniqueID: UUID().uuidString
        )
        try operations.fileStore.createDirectory(at: preserveRoot, withIntermediateDirectories: true)

        var items: [RuntimeUninstallPreservedPath] = []
        let plan = useCase.preservePlan(
            productRoot: paths.productRoot,
            defaultVitalFilesDirectory: paths.defaultVitalFilesDirectory,
            externalVitalFilesDirectory: paths.externalVitalFilesDirectory,
            configuredVitalFilesDirectoryReadFailure: paths.configuredVitalFilesDirectoryReadFailure
        )
        for candidate in plan.candidates {
            try preservePath(candidate.source, preserveRoot, candidate.token, into: &items, useCase: useCase, operations: operations)
        }
        if let externalDirectoryLogMessage = plan.externalDirectoryLogMessage {
            operations.log(externalDirectoryLogMessage)
        }
        if let configuredDirectoryReadFailureLogMessage = plan.configuredDirectoryReadFailureLogMessage {
            operations.log(configuredDirectoryReadFailureLogMessage)
        }

        operations.log(useCase.stepLogMessage(step: .preserveUserData, status: .completed))
        return RuntimeUninstallPreservedPaths(root: preserveRoot, items: items)
    }

    private static func preservePath(
        _ source: URL,
        _ preserveRoot: URL,
        _ token: String,
        into items: inout [RuntimeUninstallPreservedPath],
        useCase: UninstallRuntimeUseCase,
        operations: RuntimeUninstallCompositionOperations
    ) throws {
        guard exists(source, operations: operations) else {
            return
        }
        let destination = preserveRoot.appendingPathComponent(token)
        try removeIfPresent(destination, useCase: useCase, operations: operations)
        try operations.fileStore.moveItem(at: source, to: destination)
        items.append(RuntimeUninstallPreservedPath(source: source, destination: destination))
        operations.log(useCase.preservedSourceLogMessage(path: source.path))
    }

    private static func restorePreservedDataAfterFailureIfNeeded(
        error: Error,
        preserved: RuntimeUninstallPreservedPaths?,
        useCase: UninstallRuntimeUseCase,
        operations: RuntimeUninstallCompositionOperations
    ) -> [String] {
        var preservedRestoreFailureReason: String?
        if let preserved {
            operations.log(useCase.restoringPreservedUserDataAfterFailureLogMessage())
            do {
                try restorePreservedPaths(preserved, useCase: useCase, operations: operations)
            } catch {
                operations.log(useCase.preservedUserDataRestoreFailedLogMessage(reason: error.localizedDescription))
                preservedRestoreFailureReason = error.localizedDescription
            }
        }
        return useCase.fileRemovalBlockers(
            removalFailureReason: error.localizedDescription,
            preservedRestoreFailureReason: preservedRestoreFailureReason
        )
    }

    private static func restorePreservedPaths(
        _ preserved: RuntimeUninstallPreservedPaths,
        useCase: UninstallRuntimeUseCase,
        operations: RuntimeUninstallCompositionOperations
    ) throws {
        for item in preserved.items {
            try operations.fileStore.createDirectory(at: item.source.deletingLastPathComponent(), withIntermediateDirectories: true)
            try removeIfPresent(item.source, useCase: useCase, operations: operations)
            try operations.fileStore.moveItem(at: item.destination, to: item.source)
            operations.log(useCase.restoredPreservedLogMessage(path: item.source.path))
        }
        try removeIfPresent(preserved.root, useCase: useCase, operations: operations)
    }

    private static func safeRemove(
        _ target: URL,
        useCase: UninstallRuntimeUseCase,
        operations: RuntimeUninstallCompositionOperations
    ) throws {
        guard target.path != "/" else {
            throw RuntimeUninstallWorkflowError.operationFailed(
                useCase.unsafeRemovalTargetFailureMessage(path: target.path)
            )
        }
        guard exists(target, operations: operations) else {
            return
        }
        do {
            try operations.fileStore.removeItem(at: target)
        } catch {
            logRemovalDiagnostics(target, useCase: useCase, operations: operations)
            throw error
        }
        if exists(target, operations: operations) {
            logRemovalDiagnostics(target, useCase: useCase, operations: operations)
            throw RuntimeUninstallWorkflowError.operationFailed(
                useCase.removalIncompleteFailureMessage(path: target.path)
            )
        }
    }

    private static func logRemovalDiagnostics(
        _ target: URL,
        useCase: UninstallRuntimeUseCase,
        operations: RuntimeUninstallCompositionOperations
    ) {
        operations.log(useCase.removalDiagnosticTargetLogMessage(path: target.path))
        do {
            let items = try operations.fileStore.contentsOfDirectory(at: target, skipsHiddenFiles: false)
            for item in items.prefix(200) {
                operations.log(useCase.removalDiagnosticResidualLogMessage(path: item.path))
            }
        } catch {
            operations.log(useCase.removalDiagnosticContentsReadFailedLogMessage(
                path: target.path,
                reason: error.localizedDescription
            ))
        }
        let openFilePlan = useCase.removalDiagnosticOpenFilePlan(
            executable: Constants.Commands.lsof,
            target: target
        )
        let result = operations.runProcess(openFilePlan.executable, openFilePlan.arguments)
        if result.exitCode == 0 {
            for line in result.stdout.split(separator: "\n").prefix(200) {
                operations.log(useCase.removalDiagnosticOpenFileLogMessage(line: String(line)))
            }
        }
        if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            operations.log(useCase.removalDiagnosticOpenFileStderrLogMessage(
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
    }

    private static func removeIfPresent(
        _ url: URL,
        useCase: UninstallRuntimeUseCase,
        operations: RuntimeUninstallCompositionOperations
    ) throws {
        guard exists(url, operations: operations) else {
            return
        }
        try operations.fileStore.removeItem(at: url)
    }

    private static func exists(_ url: URL, operations: RuntimeUninstallCompositionOperations) -> Bool {
        operations.fileStore.fileExists(url) || operations.fileStore.directoryExists(url)
    }

    private static func executeReceiptForgetting(
        identifiers: [String],
        observedReceiptStates: [String: RuntimePackageReceiptState],
        operations: RuntimeUninstallCompositionOperations
    ) throws {
        let useCase = UninstallRuntimeUseCase()
        for identifier in identifiers {
            switch useCase.receiptForgetDecision(identifier: identifier, observedReceiptStates: observedReceiptStates) {
            case .skip(let logMessage):
                operations.log(logMessage)
                continue
            case .forget(let logMessage):
                operations.log(logMessage)
            }
            let result = operations.runProcess(Constants.Commands.pkgutil, ["--forget", identifier])
            guard result.exitCode == 0 else {
                throw RuntimeUninstallReceiptForgetExecutionError(
                    identifier: identifier,
                    reason: useCase.processFailureReason(result)
                )
            }
        }
    }

    private static func cleanupArtifactPaths(clean: Bool, paths: RuntimeUninstallPaths) -> [URL] {
        var artifactPaths = [paths.managerApp]
        artifactPaths.append(contentsOf: paths.launchDaemonPlists)
        artifactPaths.append(contentsOf: paths.runtimeTools)
        if clean {
            artifactPaths.append(paths.productRoot)
            if let externalVitalFilesDirectory = paths.externalVitalFilesDirectory {
                artifactPaths.append(externalVitalFilesDirectory)
            }
        }
        return artifactPaths
    }
}

private struct RuntimeUninstallPreservedPaths {
    let root: URL
    let items: [RuntimeUninstallPreservedPath]
}

private struct RuntimeUninstallPreservedPath {
    let source: URL
    let destination: URL
}
