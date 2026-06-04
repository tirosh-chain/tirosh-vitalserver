import Core
import Contracts

struct RuntimeInstallStepExecutor {
    var prepareInstallDirectories: (InstallSettings) throws -> Void
    var rotateRuntimeLogs: () throws -> Void
    var configureDeployEnvironment: (InstallSettings) throws -> Void
    var prepareInstalledExecutables: () throws -> Void
    var provisionVMDisk: (InstallSettings) throws -> Void
    var configureInstalledVMRuntime: (InstallSettings) throws -> Void
    var createCloudInitSeed: (InstallSettings) throws -> Void
    var writeInstalledRuntimeVersion: () throws -> Void
    var configureInstalledPermissions: (InstallSettings) throws -> Void
    var startInstalledServices: (InstallSettings) throws -> Void
    var applyStartOnBootPolicy: (InstallSettings) throws -> Void
    var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    var cleanupInstallSettings: () throws -> Void
    var log: (String) -> Void

    func execute(_ step: RuntimeWorkflowStep, settings: InstallSettings) throws {
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
            try waitForHealth(RuntimeServiceRestartPolicy(
                restartVM: settings.startAfterInstall,
                restartGuestLogSync: settings.startAfterInstall,
                restartProxy: settings.startAfterInstall,
                restartWatchdog: settings.startAfterInstall
            ))
        case .cleanupInstallSettings:
            try cleanupInstallSettings()
        default:
            throw LauncherError.unsupportedCommand("install step \(step.rawValue)")
        }
    }
}
