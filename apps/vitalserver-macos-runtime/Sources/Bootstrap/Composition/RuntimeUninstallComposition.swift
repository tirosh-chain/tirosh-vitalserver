import Application
import Contracts
import Foundation
import HostAdapters
import Infrastructure
import Workflow

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
                fileExists: operations.fileStore.fileExists,
                directoryExists: operations.fileStore.directoryExists,
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
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(
                        at: url,
                        withIntermediateDirectories: withIntermediateDirectories
                    )
                },
                removeItem: { url in
                    try operations.fileStore.removeItem(at: url)
                },
                moveItem: { source, destination in
                    try operations.fileStore.moveItem(at: source, to: destination)
                },
                forgetPackageReceipt: { identifier in
                    operations.runProcess(Constants.Commands.pkgutil, ["--forget", identifier])
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
            diagnostics: RuntimeUninstallDiagnostics(
                contentsOfDirectory: { url in
                    try operations.fileStore.contentsOfDirectory(at: url, skipsHiddenFiles: false)
                },
                openFileDiagnosticExecutable: Constants.Commands.lsof,
                runProcess: operations.runProcess,
                log: operations.log
            ),
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
}
