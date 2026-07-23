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
    func runtimeUninstallRunner() throws -> RuntimeUninstallRunner {
        RuntimeUninstallComposition.make(
            context: RuntimeUninstallCompositionContext(
                installedPaths: installedPaths,
                pidFile: paths.pidFile
            ),
            operations: RuntimeUninstallCompositionOperations(
                fileStore: fileStore,
                configuredExternalVitalFilesDirectory: configuredExternalVitalFilesDirectory,
                serviceState: { service in
                    healthChecker.launchdState(service)
                },
                createVitalServerBackup: {
                    _ = try runtimeDataBackupComposition().createBackup(
                        reason: "uninstall"
                    )
                },
                disableAutomaticBackupScheduler: {
                    try setAutomaticBackupSchedule(enabled: false, scheduleTimes: [])
                },
                disableRuntimeServicesForUninstall: {
                    try serviceController.disableRuntimeServicesForUninstall()
                },
                stopRuntimeServicesForUninstall: stopRuntimeServicesForUninstall,
                forceStopRuntimeServicesForUninstall: stopRuntimeServicesForCleanUninstallRecovery,
                clearLaunchdDisabledOverridesAfterUninstall: {
                    try serviceController.clearDisabledOverridesAfterUninstall()
                },
                cleanupHostProxyPortAfterStop: cleanupHostProxyPortAfterStopForUninstall,
                packageReceiptStates: runtimePackageReceiptStates,
                openFilesInDirectory: openFilesInDirectory,
                forgetPackageReceipt: forgetPackageReceipt,
                now: { clock.now },
                log: log
            )
        )
    }

    func runtimeFreshInstallPreflight() -> RuntimeFreshInstallPreflightDocument {
        FreshInstallPreflightUseCase().run(operations: runtimeFreshInstallPreflightOperations())
    }

    func runtimeFreshInstallPreflightOperations() -> FreshInstallPreflightOperations {
        RuntimeFreshInstallPreflightComposition.make(
            context: RuntimeFreshInstallPreflightCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeFreshInstallPreflightCompositionOperations(
                fileStore: fileStore,
                serviceState: { service in
                    healthChecker.launchdState(service)
                },
                packageReceiptStates: runtimePackageReceiptStates,
                proxyPortState: { port in
                    RuntimeHostProxyPortStateReader.state(
                        port: port,
                        lsofPath: Constants.Commands.lsof,
                        fileStore: fileStore,
                        commandRunner: SystemRuntimeCommandRunner()
                    )
                }
            )
        )
    }

    func runtimePackageReceiptStates() -> [RuntimePackageReceiptState] {
        RuntimePackageReceiptStateReader.states(
            identifiers: Constants.Product.packageReceiptIdentifiers,
            runProcess: { executable, arguments in
                runProcess(executable, arguments: arguments)
            }
        )
    }

    func openFilesInDirectory(_ target: URL) -> RuntimeProcessResult {
        runProcess(Constants.Commands.lsof, arguments: ["+D", target.path])
    }

    func forgetPackageReceipt(_ identifier: String) -> RuntimeProcessResult {
        runProcess(Constants.Commands.pkgutil, arguments: ["--forget", identifier])
    }

    func freshInstallArtifactPaths() -> [URL] {
        RuntimeFreshInstallPreflightComposition.freshInstallArtifactPaths(installedPaths: installedPaths)
    }

    func installProvisionPayloadPaths() -> [URL] {
        freshInstallArtifactPaths()
    }

    func rotateRuntimeLogs() throws {
        try RuntimeLogRotator(
            logsDirectory: logsDirectory,
            fileStore: fileStore,
            configuration: RuntimeLogRotationConfiguration(
                fileNames: [
                    "launcher.log",
                    "launchd.out.log",
                    "launchd.err.log",
                    "proxy.out.log",
                    "proxy.err.log",
                    "proxy-nginx.access.log",
                    "proxy-nginx.error.log",
                    "guest-log-sync.out.log",
                    "guest-log-sync.err.log",
                    "sleep-prevention.out.log",
                    "sleep-prevention.err.log",
                    "watchdog.out.log",
                    "watchdog.err.log",
                ],
                maxBytes: Constants.Runtime.logRotationMaxBytes,
                keepCount: Constants.Runtime.logRotationKeepCount
            ),
            log: log
        ).rotate()
    }

    func executeBundleMaterializationCleanupPlan(_ plan: RuntimeBundleMaterializationCleanupPlan) {
        switch plan {
        case .none:
            return
        case .cleanupTemporaryRoot(let temporaryRoot):
            removeMaterializedBundleTemporaryRoot(temporaryRoot)
        }
    }

    func removeMaterializedBundleTemporaryRoot(_ temporaryRoot: URL) {
        do {
            try fileStore.removeItem(at: temporaryRoot)
        } catch {
            log(
                "bundle temporary directory cleanup failed path=\(temporaryRoot.path) error=\(RuntimeErrorDescription.describe(error))"
            )
        }
    }
}
