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
    let disableRuntimeServicesForUninstall: () throws -> Void
    let stopRuntimeServices: () throws -> Void
    let clearLaunchdDisabledOverridesAfterUninstall: () throws -> Void
    let cleanupHostProxyPortAfterStop: () throws -> Void
    let packageReceiptStates: () -> [RuntimePackageReceiptState]
    let openFilesInDirectory: (URL) -> RuntimeProcessResult
    let forgetPackageReceipt: (String) -> RuntimeProcessResult
    let now: () -> Date
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        configuredExternalVitalFilesDirectory: @escaping () -> RuntimeConfiguredExternalVitalFilesDirectoryRead,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        createRedisBackup: @escaping () throws -> Void,
        disableRuntimeServicesForUninstall: @escaping () throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        clearLaunchdDisabledOverridesAfterUninstall: @escaping () throws -> Void,
        cleanupHostProxyPortAfterStop: @escaping () throws -> Void,
        packageReceiptStates: @escaping () -> [RuntimePackageReceiptState],
        openFilesInDirectory: @escaping (URL) -> RuntimeProcessResult,
        forgetPackageReceipt: @escaping (String) -> RuntimeProcessResult,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.configuredExternalVitalFilesDirectory = configuredExternalVitalFilesDirectory
        self.serviceState = serviceState
        self.createRedisBackup = createRedisBackup
        self.disableRuntimeServicesForUninstall = disableRuntimeServicesForUninstall
        self.stopRuntimeServices = stopRuntimeServices
        self.clearLaunchdDisabledOverridesAfterUninstall = clearLaunchdDisabledOverridesAfterUninstall
        self.cleanupHostProxyPortAfterStop = cleanupHostProxyPortAfterStop
        self.packageReceiptStates = packageReceiptStates
        self.openFilesInDirectory = openFilesInDirectory
        self.forgetPackageReceipt = forgetPackageReceipt
        self.now = now
        self.log = log
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
        try RuntimeUninstallWorkflow().run(
            command,
            paths: paths,
            readers: readers,
            effects: effects,
            writer: writer,
            diagnostics: diagnostics,
            packageReceiptIdentifiers: packageReceiptIdentifiers
        )
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
        return RuntimeUninstallRunner(
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
                    operations.packageReceiptStates()
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
                fileExists: { url in
                    operations.fileStore.fileExists(url)
                },
                directoryExists: { url in
                    operations.fileStore.directoryExists(url)
                },
                removeItem: { url in
                    try operations.fileStore.removeItem(at: url)
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
