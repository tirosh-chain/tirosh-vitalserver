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
    func isLaunchdLoaded(_ service: RuntimeManagedService) -> Bool {
        healthChecker.isLaunchdLoaded(service)
    }

    func stopRuntimeServices() throws {
        try serviceController.stopRuntimeServices()
    }

    func stopRuntimeServicesForCleanUninstallRecovery() throws {
        log("force clean uninstall requested; forcing VM process stop before launchd unload")
        let vmProcessStopState = StopRuntimeVMProcessUseCase().forceKillAndWaitState(
            killSignal: SIGKILL,
            noSuchProcessErrorNumber: Int32(ESRCH),
            timeoutSeconds: Constants.Runtime.vmForceStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
            operations: ProcessState.stopOperations(
                pidFile: paths.pidFile,
                fileStore: fileStore,
                log: log
            )
        )
        if let message = RuntimeVMProcessStopStatePolicy.blockingFailureMessage(
            for: vmProcessStopState,
            allowMissingPidFile: true
        ) {
            log("force clean uninstall VM process stop blocked before launchd unload state=\(vmProcessStopState.rawValue) error=\(message)")
            throw LauncherError.runtimeOperationFailed(message)
        }
        if case .pidFileMissing = vmProcessStopState {
            log("VM process pid file is missing during force clean uninstall; unloading launchd services from explicit launchd state")
        }
        serviceController.unloadRuntimeServicesAfterForcedVMStop()
        log("runtime services force-stopped for clean uninstall recovery")
    }

    func stopRuntimeServicesForVMDiskReplacement() throws {
        do {
            try stopRuntimeServices()
            return
        } catch {
            log("graceful runtime services stop failed before VM disk replacement; forcing VM process stop error=\(error.localizedDescription)")
        }

        try StopRuntimeVMProcessUseCase().forceKillAndWait(
            killSignal: SIGKILL,
            noSuchProcessErrorNumber: Int32(ESRCH),
            timeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
            operations: ProcessState.stopOperations(
                pidFile: paths.pidFile,
                fileStore: fileStore,
                log: log
            )
        )
        serviceController.unloadRuntimeServicesAfterForcedVMStop()
        log("runtime services stopped for VM disk replacement")
    }

    func runningVMProcessID() throws -> pid_t {
        try ProcessState.runningPid(pidFile: paths.pidFile, fileStore: fileStore)
    }

    func stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID: pid_t) throws {
        try serviceController.stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID: expectedVMProcessID)
    }

    func startRuntimeServices(
        restartVM: Bool,
        restartGuestLogSync: Bool,
        restartProxy: Bool,
        restartWatchdog: Bool
    ) throws {
        if restartVM, try preventSystemSleepEnabled() {
            try startLaunchdService(.sleepPrevention)
        }
        try serviceController.startRuntimeServices(
            restartVM: restartVM,
            restartGuestLogSync: restartGuestLogSync,
            restartProxy: false,
            restartWatchdog: false
        )
        if restartProxy {
            try cleanupHostProxyPortBeforeStart()
            try serviceController.startRuntimeServices(
                restartVM: false,
                restartGuestLogSync: false,
                restartProxy: true,
                restartWatchdog: false
            )
        }
        try serviceController.startRuntimeServices(
            restartVM: false,
            restartGuestLogSync: false,
            restartProxy: false,
            restartWatchdog: restartWatchdog
        )
    }

    func startRuntimeServices(_ policy: RuntimeServiceRestartPolicy) throws {
        try startRuntimeServices(
            restartVM: policy.restartVM,
            restartGuestLogSync: policy.restartGuestLogSync,
            restartProxy: policy.restartProxy,
            restartWatchdog: policy.restartWatchdog
        )
    }

    func startLaunchdService(_ service: RuntimeManagedService) throws {
        try serviceController.startLaunchdService(service)
    }

    func restartOrStartLaunchdService(_ service: RuntimeManagedService) throws {
        try serviceController.restartOrStartLaunchdService(service)
    }

    func restartVMRuntimeServices() throws {
        try serviceController.restartVMRuntimeServices()
    }

    func stopLaunchdService(_ service: RuntimeManagedService) throws {
        try serviceController.stopLaunchdService(service)
    }

    func launchDaemonPlist(_ service: RuntimeManagedService) -> String {
        service.launchDaemonPlist
    }

    func waitForHealth(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) throws {
        try runtimeHealthWaitRunner().wait(for: RuntimeServiceRestartPolicy(
            restartVM: restartVM,
            restartGuestLogSync: restartVM,
            restartProxy: restartProxy,
            restartWatchdog: restartWatchdog
        ))
    }

    func waitForHealth(_ policy: RuntimeServiceRestartPolicy) throws {
        try runtimeHealthWaitRunner().wait(for: policy)
    }

    func cleanupHostProxyPortBeforeStart() throws {
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: healthChecker.installedProxyPort,
            proxyServiceState: {
                healthChecker.launchdState(.proxy)
            },
            expectedProxyNginxPID: {
                healthChecker.readInstalledProxyNginxPID()
            },
            ownedNginxPathFragments: [
                installedPaths.nginxExecutable.path,
                installedPaths.nginxDirectory.path,
                "vitalserver-nginx.conf",
            ],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: runProcess,
            log: log
        )
        try CleanRuntimeHostProxyPortUseCase()
            .cleanupBeforeStartingProxy(operations: cleaner.operations)
    }

    func cleanupHostProxyPortAfterStop() throws {
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: healthChecker.installedProxyPort,
            proxyServiceState: {
                healthChecker.launchdState(.proxy)
            },
            expectedProxyNginxPID: {
                healthChecker.readInstalledProxyNginxPID()
            },
            ownedNginxPathFragments: [
                installedPaths.nginxExecutable.path,
                installedPaths.nginxDirectory.path,
                "vitalserver-nginx.conf",
            ],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: runProcess,
            log: log
        )
        try CleanRuntimeHostProxyPortUseCase()
            .cleanupOwnedListenersAfterProxyStop(operations: cleaner.operations)
    }

    func cleanupHostProxyPortAfterStopForUninstall(clean: Bool) throws {
        if clean,
           healthChecker.installedProxyPort() == nil,
           cleanUninstallCanSkipMissingProxyPortCleanup()
        {
            log(
                "proxy port cleanup after stop skipped during clean uninstall recovery; "
                    + "proxy configuration and runtime artifacts are already absent"
            )
            return
        }

        try cleanupHostProxyPortAfterStop()
    }

    private func cleanUninstallCanSkipMissingProxyPortCleanup() -> Bool {
        let requiredMissingArtifacts = [
            installedPaths.proxyLaunchDaemon,
            installedPaths.vmConfig,
            installedPaths.nginxDirectory,
            URL(fileURLWithPath: Constants.InstallPaths.proxyRun),
            installedPaths.launcher,
        ]
        return requiredMissingArtifacts.allSatisfy { fileStore.pathState(at: $0) == .missing }
    }

    func runtimeHealthWaitRunner() -> RuntimeHealthWaitRunner {
        RuntimeHealthWaitRunnerComposition.make(
            operations: RuntimeHealthWaitRunnerCompositionOperations(
                serviceState: { service in
                    healthChecker.launchdState(service)
                },
                healthSnapshot: runtimeHealthSnapshot,
                writeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                },
                sleep: { interval in
                    sleeper.sleep(forTimeInterval: interval)
                },
                log: log
            )
        )
    }
}
