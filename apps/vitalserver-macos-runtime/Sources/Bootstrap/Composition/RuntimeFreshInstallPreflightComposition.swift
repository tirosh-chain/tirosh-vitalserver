import Application
import Contracts
import Domain
import Foundation
import OutboundAdapters
import Workflow
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
    let runProcess: (String, [String]) -> RuntimeProcessResult

    public init(
        fileStore: RuntimeFileReading,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        runProcess: @escaping (String, [String]) -> RuntimeProcessResult
    ) {
        self.fileStore = fileStore
        self.serviceState = serviceState
        self.runProcess = runProcess
    }
}

public enum RuntimeFreshInstallPreflightComposition {
    public static func make(
        context: RuntimeFreshInstallPreflightCompositionContext,
        operations: RuntimeFreshInstallPreflightCompositionOperations
    ) -> RuntimeFreshInstallPreflightRunner {
        RuntimeFreshInstallPreflightRunner(
            settingsState: {
                RuntimeInstallSettingsStateReader.state(
                    path: Constants.InstallPaths.settingsPath,
                    defaultProxyPort: Constants.Guest.publicPort,
                    fileStore: operations.fileStore
                )
            },
            artifactStates: {
                RuntimeInstallArtifactStateReader.states(paths: freshInstallArtifactPaths(
                    installedPaths: context.installedPaths
                ).map(\.path))
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
                RuntimePackageReceiptStateReader.states(
                    identifiers: Constants.Product.packageReceiptIdentifiers,
                    runProcess: operations.runProcess
                )
            },
            proxyPortState: { port in
                RuntimeHostProxyPortStateReader.state(
                    port: port,
                    lsofPath: Constants.Commands.lsof,
                    runProcess: operations.runProcess
                )
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
        }
    }
}
