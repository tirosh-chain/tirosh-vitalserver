import Foundation
import RuntimeCore
import HostRuntimeInfrastructure

struct RuntimeLifecycle {
    let paths: LauncherPaths
    private let installedPaths: InstalledRuntimePaths
    private let clock: RuntimeClock
    private let sleeper: RuntimeSleeper
    private let commandRunner: RuntimeCommandRunner
    private let httpProber: RuntimeHTTPProber
    private let statusReporter: RuntimeStatusReporter
    private let healthChecker: RuntimeHealthChecker
    private let serviceController: RuntimeServiceController
    private let guestGateway: RuntimeGuestGateway
    private let fileStore: RuntimeFileStore

    init(
        paths: LauncherPaths,
        clock: RuntimeClock = SystemRuntimeClock(),
        sleeper: RuntimeSleeper = ThreadRuntimeSleeper(),
        commandRunner: RuntimeCommandRunner = SystemRuntimeCommandRunner(),
        httpProber: RuntimeHTTPProber? = nil,
        serviceManager: RuntimeServiceManager? = nil,
        runtimeStatusRepository: RuntimeStatusRepository? = nil,
        guestGateway: RuntimeGuestGateway? = nil,
        fileStore: RuntimeFileStore = LocalRuntimeFileStore()
    ) {
        let composition = RuntimeLifecycleComposition.resolve(
            paths: paths,
            clock: clock,
            commandRunner: commandRunner,
            httpProber: httpProber,
            serviceManager: serviceManager,
            runtimeStatusRepository: runtimeStatusRepository,
            guestGateway: guestGateway,
            fileStore: fileStore
        )
        self.paths = paths
        self.installedPaths = paths.installed
        self.clock = clock
        self.sleeper = sleeper
        self.commandRunner = commandRunner
        self.httpProber = composition.httpProber
        self.fileStore = fileStore
        self.statusReporter = composition.statusReporter
        self.guestGateway = composition.guestGateway
        self.healthChecker = composition.healthChecker
        self.serviceController = composition.serviceController
    }

    private var productRoot: URL {
        installedPaths.productRoot
    }

    private var bundlesDirectory: URL {
        installedPaths.bundlesDirectory
    }

    private var backupsDirectory: URL {
        installedPaths.backupsDirectory
    }

    private var logsDirectory: URL {
        installedPaths.centralRuntimeLogsDirectory
    }

    private var runtimeStatus: URL {
        installedPaths.runtimeStatus
    }

    private var rootfsBase: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)
    }

    private var vmDisk: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)
    }

    private var runtimeVersion: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.runtimeVersion)
    }

    private var vmIPFile: URL {
        installedPaths.vmIPFile
    }

    private var guestRunDirectory: URL {
        installedPaths.guestRunDirectory
    }

    func run(arguments: [String]) throws {
        switch try RuntimeLifecycleCommand.parse(arguments) {
        case .install:
            try install()
        case .status:
            printStatus()
        case .health:
            try health()
        case .watchdog:
            try watchdog()
        case .configure(let command):
            try configure(command)
        case .verifyBundle(let bundleURL):
            try verifyBundle(bundleURL)
        case .stageBundle(let bundleURL):
            _ = try stageBundle(bundleURL)
        case .applyBundle(let bundleURL):
            try applyBundle(bundleURL)
        case .rollback(let command):
            try rollback(command)
        case .repairDatastore:
            try repairDatastore()
        case .startServices:
            try startServices()
        case .stopServices:
            try stopServices()
        case .help:
            printUsage()
        }
    }

    func printUsage() {
        print(RuntimeLifecycleCommand.usage)
    }

    func install() throws {
        try runtimeInstallWorkflow().install()
    }

    private func runtimeInstallWorkflow() -> RuntimeInstallWorkflow {
        RuntimeInstallWorkflow(
            context: RuntimeInstallWorkflowContext(
                paths: paths,
                installedPaths: installedPaths,
                productRoot: productRoot,
                rootfsBase: rootfsBase,
                vmDisk: vmDisk
            ),
            operations: RuntimeInstallWorkflowOperations(
                fileStore: fileStore,
                now: { clock.now },
                writeRuntimeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                },
                writeRuntimeProgress: { event in
                    try writeRuntimeProgress(
                        event.status,
                        operation: event.operation,
                        step: event.step,
                        stepStatus: event.stepStatus,
                        phase: event.phase,
                        message: event.message
                    )
                },
                rotateRuntimeLogs: rotateRuntimeLogs,
                requireFreeSpace: { url, minimumBytes, operation in
                    try requireFreeSpace(at: url, minimumBytes: minimumBytes, operation: operation)
                },
                runRequired: runRequired,
                runProcessToFile: runProcessToFile,
                writeInstalledRuntimeVersion: {
                    try runtimeVersionStore().writeInstalledVersion(version: Constants.launcherVersion)
                },
                setStartOnBoot: setStartOnBoot,
                startLaunchdService: startLaunchdService,
                restrictSecretFile: restrictSecretFile,
                log: log
            )
        )
    }

    func printStatus() {
        runtimeStatusPrinter().printStatus()
    }

    private func runtimeStatusPrinter() -> RuntimeStatusPrinter {
        RuntimeStatusPrinter(
            productRoot: productRoot,
            runtimeDirectory: installedPaths.runtimeDirectory,
            runtimeStatus: runtimeStatus,
            rootfsBase: rootfsBase,
            vmDisk: vmDisk,
            latestBackupPath: { latestBackup()?.path },
            runtimeStatusValue: runtimeStatusValue,
            runtimeVersionValue: runtimeVersionValue,
            vmIP: { healthChecker.guestRuntimeState()?.vmIP ?? healthChecker.readTrimmed(vmIPFile) ?? "waiting" },
            installedProxyPort: healthChecker.installedProxyPort,
            hostProxyHTTP: { port in
                httpProber.statusCode(url: Constants.Runtime.proxyHealthURL(port: port))
            },
            isExecutableFile: { path in
                fileStore.isExecutableFile(atPath: path)
            },
            fileExists: fileExists,
            serviceState: { label in
                healthChecker.launchdState(label)
            }
        )
    }

    private func runtimeCloudInitSeedWriter() -> RuntimeCloudInitSeedWriter {
        RuntimeCloudInitSeedWriter(
            installedPaths: installedPaths,
            fileStore: fileStore,
            runRequired: runRequired
        )
    }

    func health() throws {
        try runtimeHealthCheckRunner().run()
    }

    private func runtimeHealthCheckRunner() -> RuntimeHealthCheckRunner {
        RuntimeHealthCheckRunner(
            printStatus: printStatus,
            healthSnapshot: runtimeHealthSnapshot,
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            reasonText: reasonText,
            printLine: { line in print(line) }
        )
    }

    func watchdog() throws {
        try runtimeWatchdogRunner().run()
    }

    private func automaticRecoveryEnabled() -> Bool {
        guard let config = try? VMRuntimeConfig.load(from: paths.config, fileStore: fileStore) else {
            return true
        }
        return config.autoRecoveryEnabled ?? true
    }

    private func runtimeManagedOperationGuard() -> RuntimeManagedOperationGuard {
        RuntimeManagedOperationGuard(
            statusReporter: statusReporter,
            now: { clock.now },
            graceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            log: log
        )
    }

    private func runtimeWatchdogRunner() -> RuntimeWatchdogRunner {
        RuntimeWatchdogRunner(
            actions: RuntimeWatchdogActions(
                prepareLogs: {
                    try? fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                    try? rotateRuntimeLogs()
                },
                activeManagedOperation: {
                    runtimeManagedOperationGuard().activeOperation()
                },
                healthSnapshot: {
                    runtimeHealthSnapshot()
                },
                proxyLivenessHTTP: { port in
                    httpProber.statusCode(url: Constants.Runtime.proxyLivenessURL(port: port))
                },
                automaticRecoveryEnabled: {
                    automaticRecoveryEnabled()
                },
                restartService: { label in
                    restartLaunchdService(label)
                },
                sleep: { interval in
                    sleeper.sleep(forTimeInterval: interval)
                },
                writeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                }
            ),
            log: log
        )
    }

    private func runtimeConfigureRunner() -> RuntimeConfigureRunner {
        RuntimeConfigureRunner(
            installedPaths: installedPaths,
            configURL: paths.config,
            fileStore: fileStore,
            actions: RuntimeConfigureActions(
                resizeVMDiskIfNeeded: { diskGiB in
                    try resizeVMDiskIfNeeded(diskGiB: diskGiB)
                },
                setInstalledProxyPort: { port in
                    try setInstalledProxyPort(port)
                },
                readSecretFile: { url in
                    try readSecretFile(url)
                },
                restrictSecretFile: { url in
                    try restrictSecretFile(url)
                },
                setStartOnBoot: { enabled in
                    try setStartOnBoot(enabled)
                },
                restartRuntimeServices: {
                    restartLaunchdService(Constants.Launchd.vmService)
                    restartLaunchdService(Constants.Launchd.proxyService)
                    restartLaunchdService(Constants.Launchd.watchdogService)
                }
            ),
            log: { message in
                log(message)
            }
        )
    }

    func configure(_ command: RuntimeConfigureCommand) throws {
        let result = try runtimeConfigureRunner().configure(command)
        try writeRuntimeStatus(.degraded, operation: .configure, message: "runtime configuration updated")

        guard result.restart else {
            print("runtime configuration updated; restart required for VM/guest changes")
            return
        }
        print("runtime configuration updated and services restarted")
    }

    func verifyBundle(_ bundleURL: URL) throws {
        try runtimeBundleWorkflow().verifyBundle(bundleURL)
    }

    @discardableResult
    func stageBundle(_ bundleURL: URL) throws -> URL {
        try runtimeBundleWorkflow().stageBundle(bundleURL)
    }

    func applyBundle(_ bundleURL: URL) throws {
        try runtimeBundleWorkflow().applyBundle(bundleURL)
    }

    private func runtimeBundleWorkflow() -> RuntimeBundleWorkflow {
        RuntimeBundleWorkflow(
            context: RuntimeBundleWorkflowContext(
                installedPaths: installedPaths,
                bundlesDirectory: bundlesDirectory,
                backupsDirectory: backupsDirectory,
                logsDirectory: logsDirectory,
                rootfsBase: rootfsBase,
                vmDisk: vmDisk
            ),
            operations: RuntimeBundleWorkflowOperations(
                fileStore: fileStore,
                runtimeHealthSnapshot: runtimeHealthSnapshot,
                rotateRuntimeLogs: rotateRuntimeLogs,
                rollback: { backup in
                    try rollback(backup.map(RuntimeRollbackCommand.specificBackup) ?? .latestBackup)
                },
                startRuntimeServices: startRuntimeServices,
                stopRuntimeServices: stopRuntimeServices,
                isLaunchdLoaded: isLaunchdLoaded,
                createBackup: { reason in try backupStore().createBackup(reason: reason) },
                writeRuntimeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                },
                writeRuntimeProgress: { event in
                    try writeRuntimeProgress(
                        event.status,
                        operation: event.operation,
                        step: event.step,
                        stepStatus: event.stepStatus,
                        phase: event.phase,
                        message: event.message
                    )
                },
                pruneOldRuntimeArtifacts: pruneOldRuntimeArtifacts,
                reasonText: reasonText,
                requireFreeSpace: { url, minimumBytes, operation in
                    try requireFreeSpace(at: url, minimumBytes: minimumBytes, operation: operation)
                },
                runProcess: runProcess,
                runRequired: runRequired,
                runProcessToFile: runProcessToFile,
                replaceFile: { source, destination in try replaceFile(from: source, to: destination) },
                writeRuntimeVersion: { version, bundle in try writeRuntimeVersion(version: version, bundle: bundle) },
                refreshCloudInitSeedIfNeeded: refreshCloudInitSeedIfNeeded,
                activateGuestUpdateIfNeeded: activateGuestUpdateIfNeeded,
                waitForHealth: waitForHealth,
                log: log
            )
        )
    }

    func repairDatastore() throws {
        try runtimeDatastoreRepairRunner().run()
    }

    private func runtimeDatastoreRepairRunner() -> RuntimeDatastoreRepairRunner {
        RuntimeDatastoreRepairRunner(
            prepareGuestRunDirectory: {
                try fileStore.createDirectory(at: guestRunDirectory, withIntermediateDirectories: true)
            },
            removePreviousResult: {
                try guestGateway.removeDatastoreRepairResult()
            },
            writeRequest: { request in
                try guestGateway.writeDatastoreRepairRequest(requestId: request.id, requestedAt: request.requestedAt)
            },
            isVMServiceLoaded: {
                isLaunchdLoaded(Constants.Launchd.vmService)
            },
            startVMService: {
                startLaunchdService(Constants.Launchd.vmService)
            },
            restartVMService: {
                restartLaunchdService(Constants.Launchd.vmService)
            },
            waitForResult: { request in
                try runtimeDatastoreRepairResultWaiter().wait(for: request)
            },
            restartProxyService: {
                restartLaunchdService(Constants.Launchd.proxyService)
            },
            restartWatchdogService: {
                restartLaunchdService(Constants.Launchd.watchdogService)
            },
            waitForHealth: waitForHealth,
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            makeRequestID: {
                UUID().uuidString
            },
            timestamp: isoTimestamp,
            log: log
        )
    }

    func startServices() throws {
        try runtimeServiceControlRunner().run(.startAll)
    }

    func stopServices() throws {
        try runtimeServiceControlRunner().run(.stopAll)
    }

    private func runtimeServiceControlRunner() -> RuntimeServiceControlRunner {
        RuntimeServiceControlRunner(
            startRuntimeServices: startRuntimeServices,
            stopRuntimeServices: stopRuntimeServices,
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            log: log
        )
    }

    func rollback(_ command: RuntimeRollbackCommand) throws {
        try runtimeRollbackRunner().run(command)
    }

    private func runtimeRollbackRunner() -> RuntimeRollbackRunner {
        RuntimeRollbackRunner(
            preparePreflight: prepareRollbackPreflight,
            executeStep: executeRollbackStep,
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            writeProgress: { event in
                try writeRuntimeProgress(
                    event.status,
                    operation: event.operation,
                    step: event.step,
                    stepStatus: event.stepStatus,
                    phase: event.phase,
                    message: event.message
                )
            },
            vmDiskPath: { vmDisk.path },
            log: log
        )
    }

    private func prepareRollbackPreflight(_ command: RuntimeRollbackCommand) throws -> RollbackPreflightContext {
        try RuntimeRollbackPreflightRunner(
            requireLatestBackup: { try backupStore().requireLatestBackup() },
            directoryExists: directoryExists,
            fileExists: fileExists,
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(
                    restartVM: isLaunchdLoaded(Constants.Launchd.vmService),
                    restartProxy: isLaunchdLoaded(Constants.Launchd.proxyService),
                    restartWatchdog: isLaunchdLoaded(Constants.Launchd.watchdogService)
                )
            },
            log: log
        ).prepare(command)
    }

    private func executeRollbackStep(
        _ step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext
    ) throws {
        let executor = RuntimeRollbackStepExecutor(
            stopRuntimeServices: stopRuntimeServices,
            replaceFile: { source, destination in try replaceFile(from: source, to: destination) },
            fileExists: fileExists,
            writeRuntimeVersion: { version, bundle in try writeRuntimeVersion(version: version, bundle: bundle) },
            restoreBackupPathIfExists: { source, destination in
                try backupStore().restoreBackupPathIfExists(source, to: destination)
            },
            restoreRuntimeToolsIfExists: { source in try backupStore().restoreRuntimeToolsIfExists(source) },
            startRuntimeServices: startRuntimeServices,
            waitForHealth: waitForHealth
        )
        try executor.execute(
            step,
            preflight: preflight,
            rootfsBase: rootfsBase,
            runtimeVersion: runtimeVersion,
            managerAppPath: URL(fileURLWithPath: Constants.Product.managerAppPath),
            nginxDirectory: installedPaths.nginxDirectory,
            deployDirectory: installedPaths.deployDirectory
        )
    }

    private func latestBackup() -> URL? {
        backupStore().latestBackup()
    }

    private func backupStore() -> RuntimeBackupStore {
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

    private func runtimeVersionStore() -> RuntimeVersionStore {
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

    private func pruneOldRuntimeArtifacts() throws {
        try pruneOldDirectories(in: backupsDirectory, keep: Constants.Runtime.backupKeepCount, requiredNameFragment: "-before-")
        try pruneOldDirectories(in: bundlesDirectory, keep: Constants.Runtime.stagedBundleKeepCount, requiredNameFragment: "update-bundle-")
    }

    private func pruneOldDirectories(in directory: URL, keep: Int, requiredNameFragment: String) throws {
        guard let matchingDirectories = try? fileStore.childDirectories(
            at: directory,
            nameContains: requiredNameFragment,
            skipsHiddenFiles: true
        ) else {
            return
        }
        let directories = matchingDirectories.sorted { $0.lastPathComponent < $1.lastPathComponent }

        for directory in directories.dropLast(keep) {
            try fileStore.removeItem(at: directory)
            log("pruned runtime artifact path=\(directory.path)")
        }
    }

    private func replaceFile(from source: URL, to destination: URL) throws {
        try fileStore.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp")
        log(
            "file replacement started source=\(source.path) destination=\(destination.path) temporary=\(temporary.path) size=\(formatBytes(try fileSize(source)))"
        )
        if fileExists(temporary) {
            try fileStore.removeItem(at: temporary)
        }
        try fileStore.copyItem(at: source, to: temporary)
        if fileExists(destination) {
            try fileStore.removeItem(at: destination)
        }
        try fileStore.moveItem(at: temporary, to: destination)
        log("file replacement completed destination=\(destination.path)")
    }

    private func writeRuntimeVersion(version: String, bundle: URL) throws {
        try runtimeVersionStore().writeAppliedVersion(version: version, bundle: bundle)
    }

    private func isLaunchdLoaded(_ label: String) -> Bool {
        healthChecker.isLaunchdLoaded(label)
    }

    private func stopRuntimeServices() throws {
        serviceController.stopRuntimeServices()
    }

    private func startRuntimeServices(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) throws {
        serviceController.startRuntimeServices(
            restartVM: restartVM,
            restartProxy: restartProxy,
            restartWatchdog: restartWatchdog
        )
    }

    private func startRuntimeServices(_ policy: RuntimeServiceRestartPolicy) throws {
        serviceController.startRuntimeServices(policy)
    }

    private func startLaunchdService(_ label: String) {
        serviceController.startLaunchdService(label)
    }

    private func restartLaunchdService(_ label: String) {
        serviceController.restartLaunchdService(label)
    }

    private func launchDaemonPlist(_ label: String) -> String {
        "\(Constants.InstallPaths.launchDaemons)/\(label).plist"
    }

    private func refreshCloudInitSeedIfNeeded(_ manifest: UpdateBundleManifest) throws {
        guard manifest.artifacts.contains(where: { $0.type == .guestDeploy }) else {
            log("cloud-init seed refresh not required")
            return
        }
        log("refreshing cloud-init seed so guest bootstrap can activate updated deploy bundle")
        try runtimeCloudInitSeedWriter().create(hostname: Constants.Guest.hostname)
    }

    private func activateGuestUpdateIfNeeded(_ manifest: UpdateBundleManifest) throws {
        try RuntimeGuestActivationRunner(
            createRunDirectory: {
                try fileStore.createDirectory(at: guestRunDirectory, withIntermediateDirectories: true)
            },
            removePreviousResult: {
                try guestGateway.removeUpdateActivationResult()
            },
            requestID: { UUID().uuidString },
            timestamp: isoTimestamp,
            writeRequest: { request in
                try guestGateway.writeUpdateActivationRequest(
                    requestId: request.id,
                    requestedAt: request.requestedAt,
                    version: request.version
                )
            },
            isVMServiceLoaded: {
                isLaunchdLoaded(Constants.Launchd.vmService)
            },
            startVMService: {
                startLaunchdService(Constants.Launchd.vmService)
            },
            loadResult: {
                guestGateway.loadUpdateActivationResult()
            },
            reportProgress: { message in
                try? writeRuntimeStatus(
                    .recovering,
                    operation: .activateGuestUpdate,
                    message: message
                )
            },
            sleep: {
                sleeper.sleep(forTimeInterval: 3)
            },
            log: log
        ).activateIfNeeded(manifest: manifest)
    }

    private func waitForHealth(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) throws {
        try runtimeHealthWaitRunner().wait(for: RuntimeServiceRestartPolicy(
            restartVM: restartVM,
            restartProxy: restartProxy,
            restartWatchdog: restartWatchdog
        ))
    }

    private func waitForHealth(_ policy: RuntimeServiceRestartPolicy) throws {
        try runtimeHealthWaitRunner().wait(for: policy)
    }

    private func runtimeHealthWaitRunner() -> RuntimeHealthWaitRunner {
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

    private func runtimeDatastoreRepairResultWaiter() -> RuntimeDatastoreRepairResultWaiter {
        RuntimeDatastoreRepairResultWaiter(
            loadResult: {
                guestGateway.loadDatastoreRepairResult()
            },
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            sleep: {
                sleeper.sleep(forTimeInterval: 3)
            },
            log: log
        )
    }

    private func reasonText(_ reasons: [RuntimeFailureReason]) -> String {
        RuntimeFailureReasonText.describe(reasons)
    }

    private func rotateRuntimeLogs() throws {
        try RuntimeLogRotator(
            logsDirectory: logsDirectory,
            fileStore: fileStore,
            log: log
        ).rotate()
    }

    private func requireFreeSpace(at url: URL, minimumBytes: UInt64, operation: String) throws {
        let available = try availableBytes(at: url)
        guard available >= minimumBytes else {
            throw LauncherError.insufficientFreeSpace(
                operation: operation,
                required: minimumBytes,
                available: available
            )
        }
        log("free-space preflight passed operation=\(operation) required=\(formatBytes(minimumBytes)) available=\(formatBytes(available))")
    }

    private func requireFreeSpace(at url: URL, minimumBytes: UInt64, operation: RuntimeOperation) throws {
        try requireFreeSpace(at: url, minimumBytes: minimumBytes, operation: operation.rawValue)
    }

    private func availableBytes(at url: URL) throws -> UInt64 {
        let attributes = try fileStore.fileSystemAttributes(forPath: url.path)
        guard attributes.freeBytes > 0 else {
            throw LauncherError.missingArgument("could not determine free space for \(url.path)")
        }
        return attributes.freeBytes
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        try fileStore.fileSize(url)
    }

    private func resizeVMDiskIfNeeded(diskGiB: Int) throws {
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

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: clock.now)
    }

    private func log(_ message: String) {
        print("[\(isoTimestamp())] \(message)")
    }

    private func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: clock.now)
    }

    private func runtimeVersionValue() -> String {
        runtimeVersionStore().readVersionValue(default: "unknown")
    }

    private func runtimeStatusValue() -> String {
        statusReporter.statusValue()
    }

    private func runtimeHealthSnapshot() -> RuntimeHealthSnapshot {
        healthChecker.snapshot()
    }

    private func writeRuntimeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        try statusReporter.writeStatus(
            status,
            operation: operation,
            message: message,
            updatedAt: isoTimestamp(),
            runtimeVersion: runtimeVersionValue(),
            healthSnapshot: runtimeHealthSnapshot(),
            latestBackup: latestBackup(),
            progress: progress
        )
    }

    private func writeRuntimeProgress(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = []
    ) throws {
        try statusReporter.writeProgress(
            status,
            operation: operation,
            step: step,
            stepStatus: stepStatus,
            phase: phase,
            message: message,
            reasonCodes: reasonCodes,
            updatedAt: isoTimestamp(),
            runtimeVersion: runtimeVersionValue(),
            healthSnapshot: runtimeHealthSnapshot(),
            latestBackup: latestBackup()
        )
    }

    private func setInstalledProxyPort(_ port: Int) throws {
        try runRequired(
            Constants.Commands.plistBuddy,
            arguments: [
                "-c",
                "Set :EnvironmentVariables:VITALSERVER_PROXY_PORT \(port)",
                launchDaemonPlist(Constants.Launchd.proxyService),
            ]
        )
    }

    private func readSecretFile(_ url: URL) throws -> String {
        guard url.path.hasPrefix("/private/tmp/") || url.path.hasPrefix("/tmp/") else {
            throw LauncherError.missingArgument("--admin-password-file must be under /private/tmp")
        }
        let data = try fileStore.readData(url)
        guard let value = String(data: data, encoding: .utf8) else {
            throw LauncherError.missingArgument("--admin-password-file must be UTF-8")
        }
        return value
    }

    private func restrictSecretFile(_ url: URL) throws {
        try runRequired(Constants.Commands.chmod, arguments: ["0600", url.path])
    }

    private func setStartOnBoot(_ enabled: Bool) throws {
        try serviceController.setStartOnBoot(enabled)
    }

    private func runtimeCommandExecutor() -> RuntimeCommandExecutor {
        RuntimeCommandExecutor(commandRunner: commandRunner, log: log)
    }

    private func runProcess(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        runtimeCommandExecutor().run(executable, arguments)
    }

    private func runRequired(_ executable: String, arguments: [String]) throws {
        try runtimeCommandExecutor().runRequired(executable, arguments)
    }

    private func runProcessToFile(_ executable: String, arguments: [String], output: URL) throws {
        try runtimeCommandExecutor().runWritingOutput(executable, arguments, output: output)
    }

    private func fileExists(_ url: URL) -> Bool {
        fileStore.fileExists(url)
    }

    private func directoryExists(_ url: URL) -> Bool {
        fileStore.directoryExists(url)
    }
}
