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
    func latestBackup() -> URL? {
        do {
            return try backupStore().latestBackup()
        } catch {
            log("failed to read latest backup error=\(error.localizedDescription)")
            return nil
        }
    }

    func backupStore() -> RuntimeBackupStore {
        RuntimeBackupStoreComposition.make(
            context: RuntimeBackupStoreCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeBackupStoreCompositionOperations(
                fileStore: fileStore,
                timestamp: backupTimestamp,
                isoTimestamp: isoTimestamp,
                runRequired: { executable, arguments in
                    _ = try runRequired(executable, arguments: arguments)
                },
                log: log
            )
        )
    }

    func runtimeVersionStore() -> RuntimeVersionStore {
        RuntimeVersionStoreComposition.make(
            context: RuntimeVersionStoreCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeVersionStoreCompositionOperations(
                fileStore: fileStore,
                timestamp: isoTimestamp
            )
        )
    }

    func writeRuntimeVersion(version: String, bundle: URL) throws {
        try runtimeVersionStore().writeAppliedVersion(version: version, bundle: bundle)
    }

    func isLaunchdLoaded(_ service: RuntimeManagedService) -> Bool {
        healthChecker.isLaunchdLoaded(service)
    }

    func stopRuntimeServices() throws {
        try serviceController.stopRuntimeServices()
    }

    func stopRuntimeServicesForVMDiskReplacement() throws {
        do {
            try stopRuntimeServices()
            return
        } catch {
            log("graceful runtime services stop failed before VM disk replacement; forcing VM process stop error=\(error.localizedDescription)")
        }

        try ProcessState.forceKillAndWait(
            pidFile: paths.pidFile,
            fileStore: fileStore,
            timeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
            log: log
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
        if restartVM, preventSystemSleepEnabled() {
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

    func stopLaunchdService(_ service: RuntimeManagedService) {
        serviceController.stopLaunchdService(service)
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
        try RuntimeHostProxyPortCleaner(
            proxyPort: healthChecker.installedProxyPort,
            proxyServiceLoaded: {
                isLaunchdLoaded(.proxy)
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
        ).cleanupBeforeStartingProxy()
    }

    func cleanupHostProxyPortAfterStop() throws {
        try RuntimeHostProxyPortCleaner(
            proxyPort: healthChecker.installedProxyPort,
            proxyServiceLoaded: {
                isLaunchdLoaded(.proxy)
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
        ).cleanupOwnedListenersAfterProxyStop()
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

    func runtimeUninstallRunner() throws -> RuntimeUninstallWorkflow {
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
                createRedisBackup: createRedisBackup,
                disableRuntimeServicesForUninstall: {
                    try serviceController.disableRuntimeServicesForUninstall()
                },
                stopRuntimeServices: stopRuntimeServices,
                cleanupHostProxyPortAfterStop: cleanupHostProxyPortAfterStop,
                runProcess: runProcess,
                now: { clock.now },
                log: log
            )
        )
    }

    func runtimeFreshInstallPreflightRunner() -> RuntimeFreshInstallPreflightRunner {
        RuntimeFreshInstallPreflightComposition.make(
            context: RuntimeFreshInstallPreflightCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeFreshInstallPreflightCompositionOperations(
                fileStore: fileStore,
                serviceState: { service in
                    healthChecker.launchdState(service)
                },
                runProcess: { executable, arguments in
                    runProcess(executable, arguments: arguments)
                }
            )
        )
    }

    func freshInstallArtifactPaths() -> [URL] {
        RuntimeFreshInstallPreflightComposition.freshInstallArtifactPaths(installedPaths: installedPaths)
    }

    func installProvisionPayloadPaths() -> [URL] {
        freshInstallArtifactPaths()
    }

    func reasonText(_ reasons: [RuntimeFailureReason]) -> String {
        RuntimeFailureReasonText.describe(reasons)
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

    func fileSize(_ url: URL) throws -> UInt64 {
        try fileStore.fileSize(url)
    }

    func resizeVMDiskIfNeeded(diskGiB: Int) throws {
        guard fileExists(vmDisk) else {
            throw LauncherError.missingFile(vmDisk.path)
        }
        let bytesPerGiB: UInt64 = 1024 * 1024 * 1024
        let currentGiB = Int((try fileSize(vmDisk) + bytesPerGiB - 1) / bytesPerGiB)
        guard diskGiB >= currentGiB else {
            throw LauncherError.missingArgument(
                "--disk-gib can only increase the VM disk; current disk is \(currentGiB) GiB"
            )
        }
        guard diskGiB > currentGiB else {
            return
        }
        try runRequired(Constants.Commands.truncate, arguments: ["-s", "\(diskGiB)G", vmDisk.path])
        log("resized vm disk path=\(vmDisk.path) from=\(currentGiB) GiB to=\(diskGiB) GiB")
    }

    func storageMaintenance() -> RuntimeStorageMaintenance {
        RuntimeStorageMaintenance(
            fileStore: fileStore,
            configuration: RuntimeStorageMaintenanceConfiguration(
                backupKeepCount: Constants.Runtime.backupKeepCount,
                stagedBundleKeepCount: Constants.Runtime.stagedBundleKeepCount
            ),
            log: log
        )
    }

    func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: clock.now)
    }

    func log(_ message: String) {
        print("[\(isoTimestamp())] \(message)")
    }

    func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: clock.now)
    }

    func runtimeVersionValue() -> String {
        switch runtimeVersionStore().readVersion() {
        case .loaded(let version):
            return version
        case .missing:
            log("runtime version unavailable reason=missing")
            return RuntimeVersionStore.missingVersionValue
        case .failed(let reason):
            log("runtime version unavailable reason=invalid error=\(reason)")
            return RuntimeVersionStore.invalidVersionValue
        }
    }

    func runtimeStatusValue() -> String? {
        statusReporter.statusValue()
    }

    func runtimeObservedEventPublisher() -> RuntimeObservedEventPublisher {
        RuntimeObservedEventPublisher(
            previousStatus: {
                statusReporter.loadStatus()?.status
            },
            recordEvent: { status, previousStatus, operation, message, snapshot, eventType in
                try runtimeEventPublisher().recordObservedEvent(
                    status,
                    previousStatus: previousStatus,
                    operation: operation,
                    message: message,
                    healthSnapshot: snapshot,
                    eventType: eventType
                )
            },
            recordEventBestEffort: { status, previousStatus, operation, message, snapshot, eventType in
                runtimeEventPublisher().recordObservedEventBestEffort(
                    status,
                    previousStatus: previousStatus,
                    operation: operation,
                    message: message,
                    healthSnapshot: snapshot,
                    eventType: eventType
                )
            }
        )
    }

    func runtimeEventPublisher() -> RuntimeEventPublisher {
        RuntimeEventPublisher(
            factory: runtimeEventFactory(),
            recorder: runtimeObservationRecorder()
        )
    }

    func runtimeObservationRecorder() -> RuntimeObservationRecorder {
        RuntimeObservationRecorder(
            eventRepository: CompositeRuntimeEventRepository(
                primary: JSONLRuntimeEventRepository(url: installedPaths.runtimeEvents),
                secondary: SQLiteRuntimeEventRepository(url: installedPaths.runtimeObservabilityDB),
                log: log
            ),
            log: log
        )
    }

    func runtimeEventFactory() -> RuntimeEventFactory {
        RuntimeEventFactory(
            timestamp: isoTimestamp,
            product: Constants.Product.identifier,
            runtimeVersion: runtimeVersionValue
        )
    }

    func vitalDBObservationProjector() -> RuntimeVitalDBObservationProjector {
        RuntimeVitalDBObservationProjector(
            appendObservation: { observation in
                try SQLiteVitalDBObservationRepository(url: installedPaths.runtimeObservabilityDB).append(observation)
            },
            log: log
        )
    }

    func projectVitalDBObservationBestEffort(_ observation: VitalDBObservationDocument) {
        vitalDBObservationProjector().projectBestEffort(observation)
    }

    func runtimeHealthSnapshot() -> RuntimeHealthSnapshot {
        healthChecker.snapshot()
    }

    func runtimeStatusWriter() -> RuntimeStatusWriter {
        RuntimeStatusWriterComposition.make(
            operations: RuntimeStatusWriterCompositionOperations(
                reporter: statusReporter,
                timestamp: isoTimestamp,
                runtimeVersion: runtimeVersionValue,
                healthSnapshot: runtimeHealthSnapshot,
                latestBackup: latestBackup
            )
        )
    }

    func runtimeObservedStatusPublisher() -> RuntimeObservedStatusPublisher {
        RuntimeObservedStatusPublisher(
            writeStatus: { status, operation, message, progress in
                try runtimeStatusWriter().writeStatus(
                    status,
                    operation: operation,
                    message: message,
                    progress: progress
                )
            },
            projectObservation: { observation in
                projectVitalDBObservationBestEffort(observation)
            }
        )
    }

    func writeRuntimeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        try runtimeObservedStatusPublisher().publishStatus(
            status,
            operation: operation,
            message: message,
            progress: progress
        )
    }

    func writeRuntimeProgress(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = []
    ) throws {
        let progress = RuntimeProgressDocument(
            operation: operation,
            phase: phase,
            step: step,
            stepStatus: stepStatus,
            message: message,
            reasonCodes: reasonCodes,
            startedAt: nil,
            updatedAt: isoTimestamp()
        )
        do {
            try runtimeStatusWriter().writeProgress(
                status,
                operation: operation,
                step: step,
                stepStatus: stepStatus,
                phase: phase,
                message: message,
                reasonCodes: reasonCodes
            )
        } catch {
            runtimeEventPublisher().recordProgressEventBestEffort(
                status: status,
                message: message,
                progress: progress
            )
            throw error
        }
        runtimeEventPublisher().recordProgressEventBestEffort(
            status: status,
            message: message,
            progress: progress
        )
    }

    func setInstalledProxyPort(_ port: Int) throws {
        try runRequired(
            Constants.Commands.plistBuddy,
            arguments: [
                "-c",
                "Set :EnvironmentVariables:VITALSERVER_PROXY_PORT \(port)",
                launchDaemonPlist(.proxy),
            ]
        )
    }

    func readSecretFile(_ url: URL) throws -> String {
        guard url.path.hasPrefix("/private/tmp/") || url.path.hasPrefix("/tmp/") else {
            throw LauncherError.missingArgument("--admin-password-file must be under /private/tmp")
        }
        let data = try fileStore.readData(url)
        guard let value = String(data: data, encoding: .utf8) else {
            throw LauncherError.missingArgument("--admin-password-file must be UTF-8")
        }
        return value
    }

    func restrictSecretFile(_ url: URL) throws {
        try runRequired(Constants.Commands.chmod, arguments: ["0600", url.path])
    }

    func setStartOnBoot(_ enabled: Bool) throws {
        try serviceController.setStartOnBoot(enabled)
    }

    func setSystemSleepPrevention(_ enabled: Bool) throws {
        let plist = URL(fileURLWithPath: RuntimeManagedService.sleepPrevention.launchDaemonPlist)
        guard fileExists(plist) else {
            log("system sleep prevention service is not installed; setting recorded only")
            return
        }
        let action = enabled ? "enable" : "disable"
        try runRequired(Constants.Commands.launchctl, arguments: [
            action,
            "system/\(RuntimeManagedService.sleepPrevention.label)",
        ])
        if enabled {
            try startLaunchdService(.sleepPrevention)
        } else {
            stopLaunchdService(.sleepPrevention)
        }
        log("system sleep prevention \(enabled ? "enabled" : "disabled")")
    }

    func preventSystemSleepEnabled() -> Bool {
        runtimeConfigFlagReader().preventSystemSleepEnabled()
    }

    func runtimeConfigFlagReader() -> RuntimeConfigFlagReader {
        RuntimeConfigFlagReader(
            loadFlags: {
                let config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
                return RuntimeConfigFlagValues(
                    autoRecoveryEnabled: config.autoRecoveryEnabled,
                    preventSystemSleep: config.preventSystemSleep
                )
            },
            log: log
        )
    }

    func configuredExternalVitalFilesDirectory() -> RuntimeConfiguredExternalVitalFilesDirectoryRead {
        do {
            let config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
            if let hostPath = config.vitalFilesDirectory?.hostPath, hostPath.hasPrefix("/") {
                let url = URL(fileURLWithPath: hostPath)
                guard url.path != installedPaths.vitalFilesDirectory.path else {
                    return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: nil, failure: nil)
                }
                return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: url, failure: nil)
            }
            return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: nil, failure: nil)
        } catch {
            let reason = error.localizedDescription
            log("failed to read configured vital files directory error=\(reason)")
            return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: nil, failure: reason)
        }
    }

    func runtimeCommandExecutor() -> RuntimeCommandExecutor {
        RuntimeCommandExecutor(
            commandRunner: commandRunner,
            log: log,
            recordCommandEvent: { eventType, executable, arguments, result in
                runtimeEventPublisher().recordCommandEventBestEffort(
                    eventType,
                    executable: executable,
                    arguments: arguments,
                    result: result
                )
            }
        )
    }

    func runProcess(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        runtimeCommandExecutor().run(executable, arguments)
    }

    func runRequired(_ executable: String, arguments: [String]) throws {
        try runtimeCommandExecutor().runRequired(executable, arguments)
    }

    func runProcessToFile(_ executable: String, arguments: [String], output: URL) throws {
        try runtimeCommandExecutor().runWritingOutput(executable, arguments, output: output)
    }

    func fileExists(_ url: URL) -> Bool {
        fileStore.fileExists(url)
    }

    func directoryExists(_ url: URL) -> Bool {
        fileStore.directoryExists(url)
    }
}
