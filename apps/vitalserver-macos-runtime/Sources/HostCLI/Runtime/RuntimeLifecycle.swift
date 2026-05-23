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

    var vmIPFile: URL {
        installedPaths.vmIPFile
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

    func printStatus() {
        runtimeStatusPrinter().printStatus()
    }

    func health() throws {
        try runtimeHealthCheckRunner().run()
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

    func startServices() throws {
        try runtimeServiceControlRunner().run(.startAll)
    }

    func stopServices() throws {
        try runtimeServiceControlRunner().run(.stopAll)
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
