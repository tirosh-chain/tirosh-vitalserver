import Foundation
import Core
import Contracts
import HostInfrastructure

struct RuntimeLifecycle {
    let paths: LauncherPaths
    let installedPaths: InstalledRuntimePaths
    let clock: RuntimeClock
    let sleeper: RuntimeSleeper
    let commandRunner: RuntimeCommandRunner
    let httpProber: RuntimeHTTPProber
    let statusReporter: RuntimeStatusReporter
    let healthChecker: RuntimeHealthChecker
    let serviceController: RuntimeServiceController
    let guestGateway: RuntimeGuestGateway
    let fileStore: RuntimeFileStore

    init(
        paths: LauncherPaths,
        clock: RuntimeClock = SystemRuntimeClock(),
        sleeper: RuntimeSleeper = ThreadRuntimeSleeper(),
        commandRunner: RuntimeCommandRunner = SystemRuntimeCommandRunner(),
        httpProber: RuntimeHTTPProber? = nil,
        serviceManager: RuntimeServiceManager? = nil,
        runtimeStatusRepository: RuntimeStatusRepository? = nil,
        guestGateway: RuntimeGuestGateway? = nil,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore()
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

    var productRoot: URL {
        installedPaths.productRoot
    }

    var bundlesDirectory: URL {
        installedPaths.bundlesDirectory
    }

    var backupsDirectory: URL {
        installedPaths.backupsDirectory
    }

    var logsDirectory: URL {
        installedPaths.centralRuntimeLogsDirectory
    }

    var runtimeStatus: URL {
        installedPaths.runtimeStatus
    }

    var rootfsBase: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)
    }

    var vmDisk: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)
    }

    var runtimeVersion: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.runtimeVersion)
    }

    var guestRunDirectory: URL {
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
        case .guestLogSync:
            guestLogSync()
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
        case .redisBackup:
            try createRedisBackup()
        case .repairDatastore:
            try repairDatastore()
        case .repairVMDisk:
            try repairVMDisk()
        case .repairServices:
            try repairServices()
        case .startServices:
            try startServices()
        case .stopServices:
            try stopServices()
        case .uninstall(let command):
            try uninstall(command)
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

    func printStatus() {
        runtimeStatusPrinter().printStatus()
    }

    func health() throws {
        do {
            try collectGuestLogs()
        } catch {
            log("health guest log collection failed error=\(error.localizedDescription)")
        }
        try runtimeHealthCheckRunner().run()
    }

    func guestLogSync() {
        log("guest log sync started")
        while true {
            do {
                try collectGuestLogs()
            } catch {
                log("guest log sync failed error=\(error.localizedDescription)")
            }
            sleeper.sleep(forTimeInterval: Constants.Runtime.guestLogSyncIntervalSeconds)
        }
    }

    func watchdog() throws {
        try runtimeWatchdogRunner().run()
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

    func repairDatastore() throws {
        try runtimeDatastoreRepairWorkflow().repair()
    }

    func repairVMDisk() throws {
        try runtimeVMDiskRepairRunner().repair()
    }

    func createRedisBackup() throws {
        log("redis backup requested")
        try requireGuestCapability(.redisBackup)
        try fileStore.createDirectory(at: guestRunDirectory, withIntermediateDirectories: true)
        try fileStore.createDirectory(
            at: installedPaths.redisBackupsDirectory,
            withIntermediateDirectories: true
        )

        let resultURL = guestRunDirectory.appendingPathComponent(Constants.Runtime.redisBackupResultFile)
        if fileStore.fileExists(resultURL) {
            try fileStore.removeItem(at: resultURL)
        }

        try writeRuntimeStatus(.recovering, operation: .redisBackup, message: "redis backup requested")

        let requestID = UUID().uuidString
        let requestedAt = isoTimestamp()
        let requestURL = guestRunDirectory.appendingPathComponent(Constants.Runtime.redisBackupRequestFile)
        let request = RedisBackupRequestDocument(requestId: requestID, requestedAt: requestedAt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileStore.writeData(try encoder.encode(request), to: requestURL, options: .atomic)

        if !isLaunchdLoaded(.vm) {
            try startLaunchdService(.vm)
        }

        let maxAttempts = Int(ceil(Constants.Runtime.redisBackupWaitTimeoutSeconds / 3.0))
        for attempt in 0..<maxAttempts {
            switch loadRedisBackupResult(from: resultURL) {
            case .loaded(let result):
                if let resultRequestId = result.requestId, resultRequestId != requestID {
                    log("stale redis backup result ignored")
                } else if result.status == .completed {
                    let message = result.message ?? "Redis backup completed."
                    try writeRuntimeStatus(.healthy, operation: .redisBackup, message: message)
                    print(message)
                    if let archive = result.archive, !archive.isEmpty {
                        print("archive: \(archive)")
                    }
                    log("redis backup completed")
                    return
                } else if result.status == .failed {
                    let message = result.message ?? "Redis backup failed."
                    try writeRuntimeStatus(.degraded, operation: .redisBackup, message: message)
                    throw LauncherError.runtimeOperationFailed(message)
                } else if attempt % 10 == 0 {
                    log(result.message ?? "waiting for redis backup")
                }
            case .missing:
                if attempt % 10 == 0 {
                    log("waiting for redis backup guest worker")
                }
            case .failed(let message):
                let failureMessage = "failed to read redis backup result: \(message)"
                try writeRuntimeStatus(.degraded, operation: .redisBackup, message: failureMessage)
                throw LauncherError.runtimeOperationFailed(failureMessage)
            }
            if attempt < maxAttempts - 1 {
                sleeper.sleep(forTimeInterval: 3)
            }
        }

        try writeRuntimeStatus(.degraded, operation: .redisBackup, message: "redis backup timed out")
        throw LauncherError.runtimeOperationFailed("redis backup timed out")
    }

    private func loadRedisBackupResult(from url: URL) -> RedisBackupResultLoadResult {
        RedisBackupResultReader.load(from: url, fileStore: fileStore)
    }

    func collectGuestLogs() throws {
        try RuntimeGuestLogCollector(installedPaths: installedPaths, fileStore: fileStore).collect()
    }

    func startServices() throws {
        try runtimeServiceControlRunner().run(.startAll)
    }

    func repairServices() throws {
        try runtimeServiceControlRunner().run(.repairAll)
    }

    func stopServices() throws {
        try runtimeServiceControlRunner().run(.stopAll)
    }

    func uninstall(_ command: RuntimeUninstallCommand) throws {
        try runtimeUninstallRunner().run(command)
    }

    func rollback(_ command: RuntimeRollbackCommand) throws {
        try runtimeRollbackWorkflow().rollback(command)
    }

    func refreshCloudInitSeedIfNeeded(_ manifest: UpdateBundleManifest) throws {
        guard manifest.artifacts.contains(where: { $0.type == .guestDeploy }) else {
            log("cloud-init seed refresh not required")
            return
        }
        log("refreshing cloud-init seed so guest bootstrap can activate updated deploy bundle")
        try runtimeCloudInitSeedWriter().create(hostname: Constants.Guest.hostname)
    }

    func activateGuestUpdateIfNeeded(_ manifest: UpdateBundleManifest) throws {
        try runtimeGuestActivationWorkflow().activateIfNeeded(manifest: manifest)
    }

}

private struct RedisBackupRequestDocument: Encodable {
    let schemaVersion = 2
    let requestId: String
    let requestedAt: String
    let operation = RuntimeOperation.redisBackup.rawValue
}

enum RedisBackupResultLoadResult {
    case missing
    case loaded(RedisBackupResultDocument)
    case failed(String)
}

enum RedisBackupResultReader {
    static func load(from url: URL, fileStore: RuntimeFileStore) -> RedisBackupResultLoadResult {
        guard fileStore.fileExists(url) else {
            return .missing
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(RedisBackupResultDocument.self, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

struct RedisBackupResultDocument: Decodable {
    let requestId: String?
    let status: DatastoreRepairStatus
    let message: String?
    let archive: String?
}
