import Foundation
import Core
import Contracts
import HostInfrastructure
import RuntimeWorkflow

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
        RuntimeBackupStore(
            paths: RuntimeBackupStorePaths(
                backupsDirectory: backupsDirectory,
                rootfsBase: rootfsBase,
                runtimeVersion: runtimeVersion,
                managerApp: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxBundle: installedPaths.nginxDirectory,
                guestDeploy: installedPaths.deployDirectory,
                runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
            ),
            timestamp: backupTimestamp,
            isoTimestamp: isoTimestamp,
            fileExists: fileExists,
            directoryExists: directoryExists,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            copyItem: { source, destination in try fileStore.copyItem(at: source, to: destination) },
            removeItem: { url in try fileStore.removeItem(at: url) },
            writeData: { data, url in try fileStore.writeData(data, to: url, options: []) },
            contentsOfDirectory: { url in try fileStore.contentsOfDirectory(at: url, skipsHiddenFiles: false) },
            childDirectories: { url, fragment in
                try fileStore.childDirectories(at: url, nameContains: fragment, skipsHiddenFiles: true)
            },
            chmodExecutable: { url in try runRequired(Constants.Commands.chmod, arguments: ["0755", url.path]) },
            log: log
        )
    }

    func runtimeVersionStore() -> RuntimeVersionStore {
        RuntimeVersionStore(
            versionFile: runtimeVersion,
            timestamp: isoTimestamp,
            fileExists: fileExists,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            readData: { url in try fileStore.readData(url) },
            writeData: { data, url in try fileStore.writeData(data, to: url, options: []) }
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

    func stopRuntimeServicesAfterGuestPoweroff() throws {
        try serviceController.stopRuntimeServicesAfterGuestPoweroff()
    }

    func startRuntimeServices(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) throws {
        if restartVM, preventSystemSleepEnabled() {
            try startLaunchdService(.sleepPrevention)
        }
        try serviceController.startRuntimeServices(restartVM: restartVM, restartProxy: false, restartWatchdog: false)
        if restartProxy {
            try cleanupHostProxyPortBeforeStart()
            try serviceController.startRuntimeServices(restartVM: false, restartProxy: true, restartWatchdog: false)
        }
        try serviceController.startRuntimeServices(restartVM: false, restartProxy: false, restartWatchdog: restartWatchdog)
    }

    func startRuntimeServices(_ policy: RuntimeServiceRestartPolicy) throws {
        try startRuntimeServices(
            restartVM: policy.restartVM,
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
                healthChecker.readTrimmed(installedPaths.proxyNginxPID)
            },
            ownedNginxPathFragments: [
                installedPaths.nginxExecutable.path,
                installedPaths.nginxDirectory.path,
                "vitalserver-nginx.conf",
            ],
            runProcess: runProcess,
            log: log
        ).cleanupBeforeStartingProxy()
    }

    func runtimeHealthWaitRunner() -> RuntimeHealthWaitRunner {
        RuntimeHealthWaitRunner(
            isLaunchdLoaded: isLaunchdLoaded,
            healthSnapshot: runtimeHealthSnapshot,
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            sleep: {
                sleeper.sleep(forTimeInterval: 3)
            },
            log: log
        )
    }

    func runtimeUninstallRunner() throws -> RuntimeUninstallWorkflow {
        let vitalFilesDirectoryRead = configuredExternalVitalFilesDirectory()
        let uninstallPaths = RuntimeUninstallPaths(
            productRoot: installedPaths.productRoot,
            managerApp: installedPaths.managerApp,
            defaultVitalFilesDirectory: installedPaths.vitalFilesDirectory,
            externalVitalFilesDirectory: vitalFilesDirectoryRead.externalDirectory,
            configuredVitalFilesDirectoryReadFailure: vitalFilesDirectoryRead.failure,
            launchDaemonPlists: RuntimeManagedService.stopOrder.map {
                URL(fileURLWithPath: $0.launchDaemonPlist)
            },
            runtimeTools: [
                installedPaths.launcher,
                URL(fileURLWithPath: Constants.InstallPaths.proxyRun),
                installedPaths.uninstaller,
            ]
        )
        return RuntimeUninstallWorkflow(
            paths: uninstallPaths,
            readers: RuntimeUninstallStateReaders(
                serviceStates: {
                    Dictionary(uniqueKeysWithValues: RuntimeManagedService.stopOrder.map { service in
                        (service, healthChecker.launchdState(service))
                    })
                },
                vmProcessState: {
                    ProcessState.inspect(pidFile: paths.pidFile, fileStore: fileStore)
                },
                fileExists: fileExists,
                directoryExists: directoryExists,
                packageReceiptStates: {
                    RuntimePackageReceiptStateReader.states(
                        identifiers: Constants.Product.packageReceiptIdentifiers,
                        runProcess: { executable, arguments in
                            runProcess(executable, arguments: arguments)
                        }
                    )
                },
                cleanupArtifactStates: { clean in
                    RuntimeInstallArtifactStateReader.states(
                        paths: cleanupArtifactPaths(clean: clean, paths: uninstallPaths).map(\.path)
                    )
                }
            ),
            effects: RuntimeUninstallEffects(
                createRedisBackup: createRedisBackup,
                stopRuntimeServices: stopRuntimeServices,
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                removeItem: { url in
                    try fileStore.removeItem(at: url)
                },
                moveItem: { source, destination in
                    try fileStore.moveItem(at: source, to: destination)
                },
                forgetPackageReceipt: { identifier in
                    runProcess("/usr/sbin/pkgutil", arguments: ["--forget", identifier])
                }
            ),
            writer: RuntimeUninstallStateWriter(
                writeState: { state, clean, message, blockers in
                    try RuntimeUninstallStateStore(
                        url: installedPaths.runtimeUninstallState,
                        fileStore: fileStore,
                        now: { clock.now }
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
                    try fileStore.contentsOfDirectory(at: url, skipsHiddenFiles: false)
                },
                runProcess: runProcess,
                log: log
            ),
            packageReceiptIdentifiers: Constants.Product.packageReceiptIdentifiers
        )
    }

    func cleanupArtifactPaths(clean: Bool, paths: RuntimeUninstallPaths) -> [URL] {
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

    func runtimeFreshInstallPreflightRunner() -> RuntimeFreshInstallPreflightRunner {
        RuntimeFreshInstallPreflightRunner(
            settingsState: {
                RuntimeInstallSettingsStateReader.state(
                    path: Constants.InstallPaths.settingsPath,
                    fileStore: fileStore
                )
            },
            artifactStates: {
                RuntimeInstallArtifactStateReader.states(paths: freshInstallArtifactPaths().map(\.path))
            },
            serviceStates: {
                RuntimeManagedService.stopOrder.map { service in
                    RuntimeFreshInstallServiceState(
                        label: service.label,
                        state: healthChecker.launchdState(service)
                    )
                }
            },
            packageReceiptStates: {
                RuntimePackageReceiptStateReader.states(
                    identifiers: Constants.Product.packageReceiptIdentifiers,
                    runProcess: { executable, arguments in
                        runProcess(executable, arguments: arguments)
                    }
                )
            },
            proxyPortState: { port in
                RuntimeHostProxyPortStateReader.state(
                    port: port,
                    runProcess: { executable, arguments in
                        runProcess(executable, arguments: arguments)
                    }
                )
            }
        )
    }

    func freshInstallArtifactPaths() -> [URL] {
        [
            installedPaths.productRoot,
            installedPaths.managerApp,
            installedPaths.launcher,
            URL(fileURLWithPath: Constants.InstallPaths.proxyRun),
            installedPaths.uninstaller,
        ] + RuntimeManagedService.stopOrder.map {
            URL(fileURLWithPath: $0.launchDaemonPlist)
        }
    }

    func reasonText(_ reasons: [RuntimeFailureReason]) -> String {
        RuntimeFailureReasonText.describe(reasons)
    }

    func rotateRuntimeLogs() throws {
        try RuntimeLogRotator(
            logsDirectory: logsDirectory,
            fileStore: fileStore,
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
        RuntimeStorageMaintenance(fileStore: fileStore, log: log)
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
        RuntimeStatusWriter(
            reporter: statusReporter,
            timestamp: isoTimestamp,
            runtimeVersion: runtimeVersionValue,
            healthSnapshot: runtimeHealthSnapshot,
            latestBackup: latestBackup
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
            loadConfig: {
                try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
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
