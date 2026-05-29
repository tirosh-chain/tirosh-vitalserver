import Foundation
import Core
import Contracts
import HostInfrastructure

extension RuntimeLifecycle {
    func latestBackup() -> URL? {
        backupStore().latestBackup()
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

    func startRuntimeServices(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) throws {
        if restartVM, preventSystemSleepEnabled() {
            startLaunchdService(.sleepPrevention)
        }
        serviceController.startRuntimeServices(restartVM: restartVM, restartProxy: false, restartWatchdog: false)
        if restartProxy {
            try cleanupHostProxyPortBeforeStart()
            serviceController.startRuntimeServices(restartVM: false, restartProxy: true, restartWatchdog: false)
        }
        serviceController.startRuntimeServices(restartVM: false, restartProxy: false, restartWatchdog: restartWatchdog)
    }

    func startRuntimeServices(_ policy: RuntimeServiceRestartPolicy) throws {
        try startRuntimeServices(
            restartVM: policy.restartVM,
            restartProxy: policy.restartProxy,
            restartWatchdog: policy.restartWatchdog
        )
    }

    func startLaunchdService(_ service: RuntimeManagedService) {
        serviceController.startLaunchdService(service)
    }

    func restartLaunchdService(_ service: RuntimeManagedService) {
        serviceController.restartLaunchdService(service)
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
        runtimeVersionStore().readVersionValue(default: "unknown")
    }

    func runtimeStatusValue() -> String {
        statusReporter.statusValue()
    }

    func recordRuntimeEvent(
        _ status: RuntimeStatusLevel,
        previousStatus: RuntimeStatusLevel?,
        operation: RuntimeOperation,
        message: String,
        healthSnapshot: RuntimeHealthSnapshot,
        eventType: RuntimeEventType = .statusChanged,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        let event = RuntimeEventDocument(
            id: UUID().uuidString,
            eventType: eventType,
            timestamp: isoTimestamp(),
            product: Constants.Product.identifier,
            status: status,
            previousStatus: previousStatus,
            operation: operation,
            message: message,
            runtimeVersion: runtimeVersionValue(),
            vmState: healthSnapshot.vmState,
            vmErrors: healthSnapshot.vmErrors,
            failureReasons: healthSnapshot.failureReasons,
            containerObservation: healthSnapshot.containerObservation,
            vitalDBObservation: healthSnapshot.vitalDBObservation,
            progress: progress
        )
        try runtimeObservationRecorder().record(event)
    }

    func recordRuntimeEventBestEffort(
        _ status: RuntimeStatusLevel,
        previousStatus: RuntimeStatusLevel?,
        operation: RuntimeOperation,
        message: String,
        healthSnapshot: RuntimeHealthSnapshot,
        eventType: RuntimeEventType = .statusChanged,
        progress: RuntimeProgressDocument? = nil
    ) {
        let event = RuntimeEventDocument(
            id: UUID().uuidString,
            eventType: eventType,
            timestamp: isoTimestamp(),
            product: Constants.Product.identifier,
            status: status,
            previousStatus: previousStatus,
            operation: operation,
            message: message,
            runtimeVersion: runtimeVersionValue(),
            vmState: healthSnapshot.vmState,
            vmErrors: healthSnapshot.vmErrors,
            failureReasons: healthSnapshot.failureReasons,
            containerObservation: healthSnapshot.containerObservation,
            vitalDBObservation: healthSnapshot.vitalDBObservation,
            progress: progress
        )
        runtimeObservationRecorder().recordBestEffort(event)
    }

    func recordRuntimeLifecycleEventBestEffort(
        operation: RuntimeOperation,
        message: String,
        eventType: RuntimeEventType
    ) {
        let currentStatus = statusReporter.loadStatus()
        let event = RuntimeEventDocument(
            id: UUID().uuidString,
            eventType: eventType,
            timestamp: isoTimestamp(),
            product: Constants.Product.identifier,
            status: currentStatus?.status ?? .unknown("unknown"),
            previousStatus: currentStatus?.status,
            operation: operation,
            message: message,
            runtimeVersion: runtimeVersionValue(),
            failureReasons: [],
            progress: nil
        )
        runtimeObservationRecorder().recordBestEffort(event)
    }

    func runtimeObservationRecorder() -> RuntimeObservationRecorder {
        RuntimeObservationRecorder(
            eventRepository: CompositeRuntimeEventRepository(
                primary: JSONLRuntimeEventRepository(url: installedPaths.runtimeEvents),
                secondary: SQLiteRuntimeEventRepository(url: installedPaths.runtimeObservabilityDB)
            ),
            observabilityStore: SQLiteRuntimeObservabilityStore(url: installedPaths.runtimeObservabilityDB),
            log: log
        )
    }

    func domainEventType(for snapshot: RuntimeHealthSnapshot, defaultEventType: RuntimeEventType = .statusChanged) -> RuntimeEventType {
        if !snapshot.vmErrors.isEmpty {
            return .vmErrorObserved
        }
        if !snapshot.failureReasons.isEmpty {
            return .domainErrorObserved
        }
        return defaultEventType
    }

    func runtimeHealthSnapshot() -> RuntimeHealthSnapshot {
        healthChecker.snapshot()
    }

    func lightweightRuntimeHealthSnapshot() -> RuntimeHealthSnapshot {
        if let status = statusReporter.loadStatus() {
            return RuntimeHealthSnapshot(
                vmExecutable: false,
                proxyExecutable: false,
                rootfsBase: status.rootfsBase,
                vmDisk: status.vmDisk,
                vmService: status.vmService,
                proxyService: status.proxyService,
                watchdogService: status.watchdogService,
                vmState: status.vmState ?? .unknown(RuntimeHTTPStatusText.notEvaluated),
                vmErrors: status.vmErrors ?? [],
                vmIP: status.vmIP,
                proxyPort: status.proxyPort,
                hostProxyHTTP: status.hostProxyHTTP,
                guestHTTP: status.guestHTTP,
                redisUIHTTP: status.redisUIHTTP ?? RuntimeHTTPStatusText.notEvaluated,
                swaggerUIHTTP: status.swaggerUIHTTP ?? RuntimeHTTPStatusText.notEvaluated,
                containerObservation: status.containerObservation,
                vitalDBObservation: status.vitalDBObservation,
                failureReasons: status.failureReasons
            )
        }
        return RuntimeHealthSnapshot(
            vmExecutable: false,
            proxyExecutable: false,
            rootfsBase: .unknown(RuntimeHTTPStatusText.notEvaluated),
            vmDisk: .unknown(RuntimeHTTPStatusText.notEvaluated),
            vmService: .unknown(RuntimeHTTPStatusText.notEvaluated),
            proxyService: .unknown(RuntimeHTTPStatusText.notEvaluated),
            watchdogService: .unknown(RuntimeHTTPStatusText.notEvaluated),
            vmState: .unknown(RuntimeHTTPStatusText.notEvaluated),
            vmIP: nil,
            proxyPort: 0,
            hostProxyHTTP: RuntimeHTTPStatusText.notEvaluated,
            guestHTTP: RuntimeHTTPStatusText.notEvaluated,
            redisUIHTTP: RuntimeHTTPStatusText.notEvaluated,
            swaggerUIHTTP: RuntimeHTTPStatusText.notEvaluated,
            failureReasons: []
        )
    }

    func runtimeStatusWriter() -> RuntimeStatusWriter {
        RuntimeStatusWriter(
            reporter: statusReporter,
            timestamp: isoTimestamp,
            runtimeVersion: runtimeVersionValue,
            healthSnapshot: runtimeHealthSnapshot,
            progressHealthSnapshot: lightweightRuntimeHealthSnapshot,
            latestBackup: latestBackup
        )
    }

    func writeRuntimeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        try runtimeStatusWriter().writeStatus(
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
        try runtimeStatusWriter().writeProgress(
            status,
            operation: operation,
            step: step,
            stepStatus: stepStatus,
            phase: phase,
            message: message,
            reasonCodes: reasonCodes
        )
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
        let previousStatus = statusReporter.loadStatus()?.status
        recordRuntimeEventBestEffort(
            status,
            previousStatus: previousStatus,
            operation: operation,
            message: message,
            healthSnapshot: lightweightRuntimeHealthSnapshot(),
            eventType: .progressUpdated,
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
            startLaunchdService(.sleepPrevention)
        } else {
            stopLaunchdService(.sleepPrevention)
        }
        log("system sleep prevention \(enabled ? "enabled" : "disabled")")
    }

    func preventSystemSleepEnabled() -> Bool {
        guard let config = try? VMRuntimeConfig.load(from: paths.config, fileStore: fileStore) else {
            return true
        }
        return config.preventSystemSleep ?? true
    }

    func runtimeCommandExecutor() -> RuntimeCommandExecutor {
        RuntimeCommandExecutor(
            commandRunner: commandRunner,
            log: log,
            recordCommandEvent: { eventType, executable, arguments, result in
                let exitSuffix = result.map { " exitCode=\($0.exitCode)" } ?? ""
                let message = "command \(eventType.rawValue) executable=\(executable) arguments=\(arguments.joined(separator: " "))\(exitSuffix)"
                let currentStatus = statusReporter.loadStatus()
                recordRuntimeEventBestEffort(
                    currentStatus?.status ?? .unknown("unknown"),
                    previousStatus: currentStatus?.status,
                    operation: currentStatus?.operation ?? .unknown("command"),
                    message: message,
                    healthSnapshot: lightweightRuntimeHealthSnapshot(),
                    eventType: eventType
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
