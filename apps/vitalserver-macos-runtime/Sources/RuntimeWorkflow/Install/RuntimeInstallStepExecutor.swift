import Contracts
import Core

public struct RuntimeInstallStepExecutor<Settings> {
    public var prepareInstallDirectories: (Settings) throws -> Void
    public var rotateRuntimeLogs: () throws -> Void
    public var configureDeployEnvironment: (Settings) throws -> Void
    public var prepareInstalledExecutables: () throws -> Void
    public var provisionVMDisk: (Settings) throws -> Void
    public var configureInstalledVMRuntime: (Settings) throws -> Void
    public var createCloudInitSeed: (Settings) throws -> Void
    public var writeInstalledRuntimeVersion: () throws -> Void
    public var configureInstalledPermissions: (Settings) throws -> Void
    public var startInstalledServices: (Settings) throws -> Void
    public var applyStartOnBootPolicy: (Settings) throws -> Void
    public var runtimeServiceRestartPolicy: (Settings) -> RuntimeServiceRestartPolicy
    public var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public var cleanupInstallSettings: () throws -> Void
    public var log: (String) -> Void

    public init(
        prepareInstallDirectories: @escaping (Settings) throws -> Void,
        rotateRuntimeLogs: @escaping () throws -> Void,
        configureDeployEnvironment: @escaping (Settings) throws -> Void,
        prepareInstalledExecutables: @escaping () throws -> Void,
        provisionVMDisk: @escaping (Settings) throws -> Void,
        configureInstalledVMRuntime: @escaping (Settings) throws -> Void,
        createCloudInitSeed: @escaping (Settings) throws -> Void,
        writeInstalledRuntimeVersion: @escaping () throws -> Void,
        configureInstalledPermissions: @escaping (Settings) throws -> Void,
        startInstalledServices: @escaping (Settings) throws -> Void,
        applyStartOnBootPolicy: @escaping (Settings) throws -> Void,
        runtimeServiceRestartPolicy: @escaping (Settings) -> RuntimeServiceRestartPolicy,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        cleanupInstallSettings: @escaping () throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.prepareInstallDirectories = prepareInstallDirectories
        self.rotateRuntimeLogs = rotateRuntimeLogs
        self.configureDeployEnvironment = configureDeployEnvironment
        self.prepareInstalledExecutables = prepareInstalledExecutables
        self.provisionVMDisk = provisionVMDisk
        self.configureInstalledVMRuntime = configureInstalledVMRuntime
        self.createCloudInitSeed = createCloudInitSeed
        self.writeInstalledRuntimeVersion = writeInstalledRuntimeVersion
        self.configureInstalledPermissions = configureInstalledPermissions
        self.startInstalledServices = startInstalledServices
        self.applyStartOnBootPolicy = applyStartOnBootPolicy
        self.runtimeServiceRestartPolicy = runtimeServiceRestartPolicy
        self.waitForHealth = waitForHealth
        self.cleanupInstallSettings = cleanupInstallSettings
        self.log = log
    }

    public func execute(_ step: RuntimeWorkflowStep, settings: Settings) throws {
        switch step {
        case .loadInstallSettings:
            log("install settings loaded")
        case .prepareInstallDirectories:
            try prepareInstallDirectories(settings)
        case .rotateRuntimeLogs:
            try rotateRuntimeLogs()
        case .configureGuestRuntimeConfig:
            try configureDeployEnvironment(settings)
        case .prepareInstalledExecutables:
            try prepareInstalledExecutables()
        case .provisionVMDisk:
            try provisionVMDisk(settings)
        case .configureVMRuntime:
            try configureInstalledVMRuntime(settings)
        case .createCloudInitSeed:
            try createCloudInitSeed(settings)
        case .writeInstallRuntimeVersion:
            try writeInstalledRuntimeVersion()
        case .configureInstalledPermissions:
            try configureInstalledPermissions(settings)
        case .startInstalledServices:
            try startInstalledServices(settings)
        case .applyStartOnBootPolicy:
            try applyStartOnBootPolicy(settings)
        case .waitInstallRuntimeHealth:
            try waitForHealth(runtimeServiceRestartPolicy(settings))
        case .cleanupInstallSettings:
            try cleanupInstallSettings()
        default:
            throw RuntimeWorkflowError.operationFailed("unsupported command: install step \(step.rawValue)")
        }
    }
}
