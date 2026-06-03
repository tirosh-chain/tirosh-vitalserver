import Foundation
import Core
import Contracts

public struct InstalledRuntimePaths: Equatable, Sendable {
    public static let defaultProductRoot = URL(fileURLWithPath: "/Library/Application Support/TiroshVitalServer")
    public static let defaultInstalled = InstalledRuntimePaths(productRoot: defaultProductRoot)

    public let productRoot: URL
    public let runtimeHome: URL

    public init(productRoot: URL, runtimeHome: URL? = nil) {
        self.productRoot = productRoot
        self.runtimeHome = runtimeHome ?? productRoot.appendingPathComponent("vm")
    }

    public init(runtimeHome: URL) {
        self.init(productRoot: runtimeHome.deletingLastPathComponent(), runtimeHome: runtimeHome)
    }

    public var launcher: URL {
        URL(fileURLWithPath: "/usr/local/bin/vitalserver-vm")
    }

    public var uninstaller: URL {
        URL(fileURLWithPath: "/usr/local/bin/tirosh-vitalserver-uninstall")
    }

    public var managerApp: URL {
        URL(fileURLWithPath: "/Applications/VitalServer Helper.app")
    }

    public var dataDirectory: URL {
        runtimeHome.appendingPathComponent("data")
    }

    public var deployDirectory: URL {
        dataDirectory.appendingPathComponent("deploy")
    }

    public var guestRunDirectory: URL {
        dataDirectory.appendingPathComponent("run")
    }

    public var guestObservabilityDirectory: URL {
        guestRunDirectory.appendingPathComponent("guest-observability")
    }

    public var hostRunDirectory: URL {
        runtimeHome.appendingPathComponent("run")
    }

    public var runtimeDirectory: URL {
        runtimeHome.appendingPathComponent("runtime")
    }

    public var logsDirectory: URL {
        runtimeHome.appendingPathComponent("logs")
    }

    public var productLogsDirectory: URL {
        productRoot.appendingPathComponent("logs")
    }

    public var centralRuntimeLogsDirectory: URL {
        productLogsDirectory.appendingPathComponent("runtime")
    }

    public var centralGuestLogsDirectory: URL {
        productLogsDirectory.appendingPathComponent("guest")
    }

    public var centralGuestObservabilityDirectory: URL {
        centralGuestLogsDirectory.appendingPathComponent("guest-observability")
    }

    public var logArchiveDirectory: URL {
        productLogsDirectory.appendingPathComponent("archive")
    }

    public var statusDirectory: URL {
        productRoot.appendingPathComponent("status")
    }

    public var installLog: URL {
        productLogsDirectory.appendingPathComponent("install.log")
    }

    public var centralCommandLog: URL {
        productLogsDirectory.appendingPathComponent("command.log")
    }

    public var backupsDirectory: URL {
        productRoot.appendingPathComponent("backups")
    }

    public var redisBackupsDirectory: URL {
        dataDirectory.appendingPathComponent("backups/redis")
    }

    public var bundlesDirectory: URL {
        productRoot.appendingPathComponent("bundles")
    }

    public var nginxDirectory: URL {
        productRoot.appendingPathComponent("nginx")
    }

    public var nginxLogsDirectory: URL {
        nginxDirectory.appendingPathComponent("logs")
    }

    public var nginxExecutable: URL {
        nginxDirectory.appendingPathComponent("sbin/nginx")
    }

    public var vitalFilesDirectory: URL {
        dataDirectory.appendingPathComponent("vital-files")
    }

    public var vrReleaseDirectory: URL {
        dataDirectory.appendingPathComponent("vr-release")
    }

    public var runtimeStatus: URL {
        statusDirectory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
    }

    public var runtimeEvents: URL {
        statusDirectory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
    }

    public var runtimeObservabilityDB: URL {
        statusDirectory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
    }

    public var runtimeUninstallState: URL {
        URL(fileURLWithPath: "/private/tmp/\(RuntimeFileNames.runtimeUninstallState)")
    }

    public var runtimeInstallState: URL {
        URL(fileURLWithPath: "/private/tmp/\(RuntimeFileNames.runtimeInstallState)")
    }

    public var vmIPFile: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.vmIP)
    }

    public var vmLifecycle: URL {
        hostRunDirectory.appendingPathComponent(RuntimeFileNames.vmLifecycle)
    }

    public var runtimeState: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.runtimeState)
    }

    public var bootstrapLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.bootstrapLog)
    }

    public var bootstrapResult: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.bootstrapResult)
    }

    public var updateActivationLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.updateActivationLog)
    }

    public var updateActivationResult: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.updateActivationResult)
    }

    public var updateShutdownLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.updateShutdownLog)
    }

    public var updateShutdownResult: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.updateShutdownResult)
    }

    public var datastoreRepairLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.datastoreRepairLog)
    }

    public var datastoreRepairResult: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.datastoreRepairResult)
    }

    public var centralBootstrapLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeFileNames.bootstrapLog)
    }

    public var centralUpdateActivationLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeFileNames.updateActivationLog)
    }

    public var centralUpdateShutdownLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeFileNames.updateShutdownLog)
    }

    public var centralDatastoreRepairLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeFileNames.datastoreRepairLog)
    }

    public var redisBackupLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeFileNames.redisBackupLog)
    }

    public var centralRedisBackupLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeFileNames.redisBackupLog)
    }

    public var containerLogs: URL {
        guestRunDirectory.appendingPathComponent("container-logs.log")
    }

    public var centralContainerLogs: URL {
        centralGuestLogsDirectory.appendingPathComponent("container-logs.log")
    }

    public var pidFile: URL {
        hostRunDirectory.appendingPathComponent("vitalserver-vm.pid")
    }

    public var vmConfig: URL {
        runtimeDirectory.appendingPathComponent("vm-config.json")
    }

    public var vmDisk: URL {
        runtimeDirectory.appendingPathComponent("vm-disk.img")
    }

    public var guestRuntimeConfig: URL {
        deployDirectory.appendingPathComponent("runtime-config.json")
    }

    public var guestRuntimeSettings: URL {
        deployDirectory.appendingPathComponent("runtime-settings.json")
    }

    public var proxyNginxPID: URL {
        nginxLogsDirectory.appendingPathComponent("nginx.pid")
    }

    public var proxyNginxAccessLog: URL {
        centralRuntimeLogsDirectory.appendingPathComponent("proxy-nginx.access.log")
    }

    public var proxyNginxErrorLog: URL {
        centralRuntimeLogsDirectory.appendingPathComponent("proxy-nginx.error.log")
    }

    public var proxyLaunchDaemon: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist")
    }

    public var managerCommandLog: URL {
        URL(fileURLWithPath: "/private/tmp/\(RuntimeFileNames.managerCommandLog)")
    }

    public var managerHelperMessageLog: URL {
        URL(fileURLWithPath: "/private/tmp/\(RuntimeFileNames.managerHelperMessageLog)")
    }
}
