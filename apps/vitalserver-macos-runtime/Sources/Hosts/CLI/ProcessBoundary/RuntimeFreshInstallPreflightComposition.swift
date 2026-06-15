import Application
import Bootstrap
import Contracts
import Domain
import Foundation
import OutboundAdapters
import Errors

public struct RuntimeFreshInstallPreflightCompositionContext {
    let installedPaths: InstalledRuntimePaths

    public init(installedPaths: InstalledRuntimePaths) {
        self.installedPaths = installedPaths
    }
}

public struct RuntimeFreshInstallPreflightCompositionOperations {
    let fileStore: RuntimeFileReading
    let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    let packageReceiptStates: () -> [RuntimePackageReceiptState]
    let proxyPortState: (Int) -> RuntimeHostProxyPortState

    public init(
        fileStore: RuntimeFileReading,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        packageReceiptStates: @escaping () -> [RuntimePackageReceiptState],
        proxyPortState: @escaping (Int) -> RuntimeHostProxyPortState
    ) {
        self.fileStore = fileStore
        self.serviceState = serviceState
        self.packageReceiptStates = packageReceiptStates
        self.proxyPortState = proxyPortState
    }
}

public enum RuntimeFreshInstallPreflightComposition {
    public static func make(
        context: RuntimeFreshInstallPreflightCompositionContext,
        operations: RuntimeFreshInstallPreflightCompositionOperations
    ) -> FreshInstallPreflightOperations {
        FreshInstallPreflightOperations(
            settingsState: {
                RuntimeInstallSettingsStateReader.state(
                    path: Constants.InstallPaths.settingsPath,
                    fileStore: operations.fileStore
                )
            },
            settingsDefaultProxyPort: Constants.Guest.publicPort,
            artifactStates: {
                RuntimeInstallArtifactStateReader.states(paths: freshInstallArtifactPaths(
                    installedPaths: context.installedPaths
                ).map(\.path), fileStore: operations.fileStore)
            },
            serviceStates: {
                RuntimeManagedService.stopOrder.map { service in
                    RuntimeFreshInstallServiceState(
                        label: service.label,
                        state: operations.serviceState(service)
                    )
                }
            },
            packageReceiptStates: {
                operations.packageReceiptStates()
            },
            proxyPortState: { port in
                operations.proxyPortState(port)
            }
        )
    }

    public static func freshInstallArtifactPaths(installedPaths: InstalledRuntimePaths) -> [URL] {
        [
            installedPaths.productRoot,
            installedPaths.managerApp,
            installedPaths.launcher,
            URL(fileURLWithPath: Constants.InstallPaths.proxyRun),
            installedPaths.uninstaller,
        ] + RuntimeManagedService.stopOrder.map {
            URL(fileURLWithPath: RuntimeManagedServicePaths.launchDaemonPlist($0))
        } + [installedPaths.automaticBackupLaunchDaemon]
    }
}
