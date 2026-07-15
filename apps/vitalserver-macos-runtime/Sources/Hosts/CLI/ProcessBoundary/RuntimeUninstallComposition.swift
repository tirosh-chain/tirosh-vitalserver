import Application
import Bootstrap
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
    let disableAutomaticBackupScheduler: () throws -> Void
    let disableRuntimeServicesForUninstall: () throws -> Void
    let stopRuntimeServicesForUninstall: () throws -> Void
    let forceStopRuntimeServicesForUninstall: () throws -> Void
    let clearLaunchdDisabledOverridesAfterUninstall: () throws -> Void
    let cleanupHostProxyPortAfterStop: (Bool) throws -> Void
    let packageReceiptStates: () -> [RuntimePackageReceiptState]
    let openFilesInDirectory: (URL) -> RuntimeProcessResult
    let forgetPackageReceipt: (String) -> RuntimeProcessResult
    let now: () -> Date
    let log: (String) -> Void
    let operationID: () -> String
    let stateWriter: RuntimeUninstallStateWriter?

    public init(
        fileStore: RuntimeFileStore,
        configuredExternalVitalFilesDirectory: @escaping () -> RuntimeConfiguredExternalVitalFilesDirectoryRead,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        createRedisBackup: @escaping () throws -> Void,
        disableAutomaticBackupScheduler: @escaping () throws -> Void,
        disableRuntimeServicesForUninstall: @escaping () throws -> Void,
        stopRuntimeServicesForUninstall: @escaping () throws -> Void,
        forceStopRuntimeServicesForUninstall: @escaping () throws -> Void,
        clearLaunchdDisabledOverridesAfterUninstall: @escaping () throws -> Void,
        cleanupHostProxyPortAfterStop: @escaping (Bool) throws -> Void,
        packageReceiptStates: @escaping () -> [RuntimePackageReceiptState],
        openFilesInDirectory: @escaping (URL) -> RuntimeProcessResult,
        forgetPackageReceipt: @escaping (String) -> RuntimeProcessResult,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void,
        operationID: @escaping () -> String = { UUID().uuidString.lowercased() },
        stateWriter: RuntimeUninstallStateWriter? = nil
    ) {
        self.fileStore = fileStore
        self.configuredExternalVitalFilesDirectory = configuredExternalVitalFilesDirectory
        self.serviceState = serviceState
        self.createRedisBackup = createRedisBackup
        self.disableAutomaticBackupScheduler = disableAutomaticBackupScheduler
        self.disableRuntimeServicesForUninstall = disableRuntimeServicesForUninstall
        self.stopRuntimeServicesForUninstall = stopRuntimeServicesForUninstall
        self.forceStopRuntimeServicesForUninstall = forceStopRuntimeServicesForUninstall
        self.clearLaunchdDisabledOverridesAfterUninstall = clearLaunchdDisabledOverridesAfterUninstall
        self.cleanupHostProxyPortAfterStop = cleanupHostProxyPortAfterStop
        self.packageReceiptStates = packageReceiptStates
        self.openFilesInDirectory = openFilesInDirectory
        self.forgetPackageReceipt = forgetPackageReceipt
        self.now = now
        self.log = log
        self.operationID = operationID
        self.stateWriter = stateWriter
    }
}

public struct RuntimeUninstallRunner {
    private let paths: RuntimeUninstallPaths
    private let readers: RuntimeUninstallStateReaders
    private let effects: RuntimeUninstallEffects
    private let writer: RuntimeUninstallStateWriter
    private let diagnostics: RuntimeUninstallDiagnostics
    private let packageReceiptIdentifiers: [String]

    public init(
        paths: RuntimeUninstallPaths,
        readers: RuntimeUninstallStateReaders,
        effects: RuntimeUninstallEffects,
        writer: RuntimeUninstallStateWriter,
        diagnostics: RuntimeUninstallDiagnostics,
        packageReceiptIdentifiers: [String]
    ) {
        self.paths = paths
        self.readers = readers
        self.effects = effects
        self.writer = writer
        self.diagnostics = diagnostics
        self.packageReceiptIdentifiers = packageReceiptIdentifiers
    }

    public func run(_ command: RuntimeUninstallCommand) throws {
        try writer.acquireOperationLease()
        do {
            try RuntimeUninstallWorkflow().run(
                command,
                paths: paths,
                readers: readers,
                effects: effects,
                writer: writer,
                diagnostics: diagnostics,
                packageReceiptIdentifiers: packageReceiptIdentifiers
            )
        } catch {
            let operationFailure = RuntimeErrorDescription.describe(error)
            do {
                try writer.releaseOperationLease()
            } catch {
                throw UninstallRuntimeUseCaseError.operationFailed(
                    "uninstall failed operationFailure=\(operationFailure) leaseReleaseFailure=\(RuntimeErrorDescription.describe(error))"
                )
            }
            throw error
        }
    }
}

public enum RuntimeUninstallComposition {
    public static func make(
        context: RuntimeUninstallCompositionContext,
        operations: RuntimeUninstallCompositionOperations
    ) -> RuntimeUninstallRunner {
        let vitalFilesDirectoryRead = operations.configuredExternalVitalFilesDirectory()
        let uninstallPaths = RuntimeUninstallPaths(
            productRoot: context.installedPaths.productRoot,
            runtimeStateDatabase: context.installedPaths.runtimeStateDatabase,
            managerApp: context.installedPaths.managerApp,
            defaultVitalFilesDirectory: context.installedPaths.vitalFilesDirectory,
            externalVitalFilesDirectory: vitalFilesDirectoryRead.externalDirectory,
            configuredVitalFilesDirectoryReadFailure: vitalFilesDirectoryRead.failure,
            launchDaemonPlists: RuntimeManagedService.uninstallOrder.map {
                URL(fileURLWithPath: RuntimeManagedServicePaths.launchDaemonPlist($0))
            } + [context.installedPaths.automaticBackupLaunchDaemon],
            runtimeTools: [
                context.installedPaths.launcher,
                URL(fileURLWithPath: Constants.InstallPaths.proxyRun),
                context.installedPaths.uninstaller,
            ]
        )
        let operationID = operations.operationID()
        let stateWriter = operations.stateWriter ?? RuntimeUninstallWorkflowOperationStateSession(
            operationID: operationID,
            databaseURL: context.installedPaths.runtimeStateDatabase,
            now: operations.now,
            ownerPID: Int(ProcessInfo.processInfo.processIdentifier),
            leaseDurationSeconds: Constants.Runtime.runtimeOperationLeaseDurationSeconds,
            repositoryFactory: { databaseURL in
                SQLiteRuntimeWorkflowOperationStateRepository(databaseURL: databaseURL)
            },
            leaseOwnerFactory: { databaseURL in
                SQLiteRuntimeOperationLeaseRepository(databaseURL: databaseURL)
            }
        ).writer()
        return RuntimeUninstallRunner(
            paths: uninstallPaths,
            readers: RuntimeUninstallStateReaders(
                serviceStates: {
                    Dictionary(uniqueKeysWithValues: RuntimeManagedService.uninstallOrder.map { service in
                        (service, operations.serviceState(service))
                    })
                },
                vmProcessState: {
                    ProcessState.inspect(pidFile: context.pidFile, fileStore: operations.fileStore)
                },
                packageReceiptStates: {
                    operations.packageReceiptStates()
                },
                cleanupArtifactStates: { clean in
                    RuntimeInstallArtifactStateReader.states(
                        paths: cleanupArtifactPaths(clean: clean, paths: uninstallPaths).map(\.path),
                        fileStore: operations.fileStore
                    )
                }
            ),
            effects: RuntimeUninstallEffects(
                createRedisBackup: operations.createRedisBackup,
                stopRuntimeServices: { clean, forceClean in
                    try operations.disableAutomaticBackupScheduler()
                    try operations.disableRuntimeServicesForUninstall()
                    if forceClean {
                        try operations.forceStopRuntimeServicesForUninstall()
                    } else if clean {
                        do {
                            try operations.stopRuntimeServicesForUninstall()
                        } catch {
                            let reason = RuntimeErrorDescription.describe(error)
                            operations.log(
                                "clean uninstall graceful stop failed; forcing runtime service cleanup reason=\(reason)"
                            )
                            try operations.forceStopRuntimeServicesForUninstall()
                        }
                    } else {
                        try operations.stopRuntimeServicesForUninstall()
                    }
                    try operations.cleanupHostProxyPortAfterStop(clean)
                },
                clearLaunchdDisabledOverrides: operations.clearLaunchdDisabledOverridesAfterUninstall,
                describeError: RuntimeErrorDescription.describe,
                temporaryDirectory: {
                    operations.fileStore.temporaryDirectory
                },
                uniqueID: {
                    UUID().uuidString
                },
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(
                        at: url,
                        withIntermediateDirectories: withIntermediateDirectories
                    )
                },
                pathState: { url in
                    operations.fileStore.pathState(at: url)
                },
                removeItem: { url in
                    do {
                        try operations.fileStore.removeItem(at: url)
                        return .removed(path: url.path)
                    } catch {
                        if isNoSuchFileError(error) {
                            return .alreadyAbsent(path: url.path)
                        }
                        throw error
                    }
                },
                moveItem: { source, destination in
                    try operations.fileStore.moveItem(at: source, to: destination)
                },
                contentsOfDirectory: { url, skipsHiddenFiles in
                    try operations.fileStore.contentsOfDirectory(
                        at: url,
                        skipsHiddenFiles: skipsHiddenFiles
                    )
                },
                openFilesInDirectory: { target in
                    operations.openFilesInDirectory(target)
                },
                forgetPackageReceipt: { identifier in
                    operations.forgetPackageReceipt(identifier)
                }
            ),
            writer: stateWriter,
            diagnostics: RuntimeUninstallDiagnostics(log: operations.log),
            packageReceiptIdentifiers: Constants.Product.packageReceiptIdentifiers
        )
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

    private static func isNoSuchFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }
}
