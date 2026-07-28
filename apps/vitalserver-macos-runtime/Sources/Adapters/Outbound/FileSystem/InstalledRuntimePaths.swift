import Foundation
import Application
import Contracts
import Errors
import RuntimeControl

public struct InstalledRuntimePaths: Equatable, Sendable {
    public static let defaultProductRoot = URL(fileURLWithPath: "/Library/Application Support/VitalServerHelper")
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

    public var updateHandoffSupervisorExecutable: URL {
        URL(
            fileURLWithPath:
                "/usr/local/bin/vitalserver-update-handoff-supervisor"
        )
    }

    public var updateHandoffJobsDirectory: URL {
        productRoot
            .appendingPathComponent("update-handoff", isDirectory: true)
            .appendingPathComponent("jobs", isDirectory: true)
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

    public var runtimeStateDatabase: URL {
        runtimeDirectory.appendingPathComponent("runtime-state.sqlite")
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

    public var runtimeControlSettings: URL {
        productRoot.appendingPathComponent("runtime-control-settings.json")
    }

    public var runtimeControlAPIToken: URL {
        productRoot
            .appendingPathComponent("secrets", isDirectory: true)
            .appendingPathComponent("runtime-control-api-token")
    }

    public var installLog: URL {
        productLogsDirectory.appendingPathComponent("install.log")
    }

    public var centralCommandLog: URL {
        productLogsDirectory.appendingPathComponent("command.log")
    }

    public var backupsDirectory: URL {
        productRoot.appendingPathComponent(RuntimeBackupStorageLayout.rootDirectoryName)
    }

    public var standardUninstallRetainedDataRoot: URL {
        productRoot
            .deletingLastPathComponent()
            .appendingPathComponent("\(productRoot.lastPathComponent)-retained-uninstall-data")
    }

    public var vitalServerHelperBackupsDirectory: URL {
        RuntimeBackupStorageLayout.vitalServerHelperBackupsDirectory(under: backupsDirectory)
    }

    public var redisOnlyBackupsDirectory: URL {
        RuntimeBackupStorageLayout.redisOnlyBackupsDirectory(under: backupsDirectory)
    }

    public var updateRollbackBackupsDirectory: URL {
        RuntimeBackupStorageLayout.updateRollbackBackupsDirectory(under: backupsDirectory)
    }

    public var vmDiskRepairBackupsDirectory: URL {
        RuntimeBackupStorageLayout.vmDiskRepairBackupsDirectory(under: backupsDirectory)
    }

    public var redisBackupsDirectory: URL {
        dataDirectory.appendingPathComponent("backups/redis")
    }

    public var postgresBackupsDirectory: URL {
        dataDirectory.appendingPathComponent("backups/postgres")
    }

    public var bundlesDirectory: URL {
        productRoot.appendingPathComponent("bundles")
    }

    public var updateBootstrapTrustStore: URL {
        productRoot
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("update-bootstrap-trust-store.json")
    }

    public var updateBootstrapStagingDirectory: URL {
        productRoot.appendingPathComponent(
            "update-bootstrap",
            isDirectory: true
        )
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

    public var helperManagedDefaultVitalFilesDirectory: URL {
        URL(fileURLWithPath: RuntimeSettingsInitialValues.vitalFilesDirectory)
    }

    public var vrReleaseDirectory: URL {
        dataDirectory.appendingPathComponent("vr-release")
    }

    public var runtimeStatus: URL {
        statusDirectory.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeStatus)
    }

    public var runtimeProgress: URL {
        statusDirectory.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeProgress)
    }

    public var runtimeOperationLease: URL {
        hostRunDirectory.appendingPathComponent(RuntimeLegacyHostStateFileNames.operationLease)
    }

    public var runtimeEvents: URL {
        statusDirectory.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeEvents)
    }

    public var hostRuntimeStateEvents: URL {
        statusDirectory.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.hostRuntimeStateEvents)
    }

    public var hostRuntimeStateSnapshot: URL {
        statusDirectory.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.hostRuntimeState)
    }

    public var runtimeObservabilityDB: URL {
        statusDirectory.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)
    }

    public var appliedVMConfig: URL {
        statusDirectory.appendingPathComponent(RuntimeHostContractFileNames.appliedVMConfig)
    }

    public var runtimeInstallState: URL {
        URL(fileURLWithPath: "/private/tmp/\(RuntimeWorkflowArtifactFileNames.runtimeInstallState)")
    }

    public var vmIPFile: URL {
        guestRunDirectory.appendingPathComponent(RuntimeBootstrapEvidenceFileNames.vmIP)
    }

    public var runtimeObservation: URL {
        guestRunDirectory.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeObservation)
    }

    public var bootstrapLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.bootstrapLog)
    }

    public var bootstrapResult: URL {
        guestRunDirectory.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.bootstrapResult)
    }

    public var updateActivationLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.updateActivationLog)
    }

    public var updateShutdownLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.updateShutdownLog)
    }

    public var datastoreRepairLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.datastoreRepairLog)
    }

    public var centralBootstrapLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.bootstrapLog)
    }

    public var centralUpdateActivationLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.updateActivationLog)
    }

    public var centralUpdateShutdownLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.updateShutdownLog)
    }

    public var centralDatastoreRepairLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.datastoreRepairLog)
    }

    public var redisBackupLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.redisBackupLog)
    }

    public var redisRestoreLog: URL {
        guestRunDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.redisRestoreLog)
    }

    public var centralRedisBackupLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.redisBackupLog)
    }

    public var centralRedisRestoreLog: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.redisRestoreLog)
    }

    public var containerLogs: URL {
        guestRunDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.containerLogs)
    }

    public var centralContainerLogs: URL {
        centralGuestLogsDirectory.appendingPathComponent(RuntimeLogArtifactFileNames.containerLogs)
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

    public var runtimeDataDisk: URL {
        runtimeDirectory.appendingPathComponent("runtime-data.img")
    }

    public var guestRuntimeConfig: URL {
        deployDirectory.appendingPathComponent("runtime-config.json")
    }

    public var guestRuntimeSettings: URL {
        deployDirectory.appendingPathComponent("runtime-settings.json")
    }

    public var redisRelayConfigDirectory: URL {
        deployDirectory.appendingPathComponent("redis-relay-config")
    }

    public var redisRelayConfig: URL {
        redisRelayConfigDirectory.appendingPathComponent("redis-relay.toml")
    }

    public var redisRelaySecretsDirectory: URL {
        deployDirectory.appendingPathComponent("redis-relay-secrets")
    }

    public var redisRelayTargetPassword: URL {
        redisRelaySecretsDirectory.appendingPathComponent("redis-relay-target-password")
    }

    public var redisRelayStatusDirectory: URL {
        guestRunDirectory.appendingPathComponent("redis-relay-status")
    }

    public var hostTime: URL {
        deployDirectory.appendingPathComponent(RuntimeHostContractFileNames.hostTime)
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
        URL(fileURLWithPath: "/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.proxy.plist")
    }

    public var updateHandoffSupervisorLaunchDaemon: URL {
        URL(
            fileURLWithPath:
                "/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.update-handoff-supervisor.plist"
        )
    }

    public var automaticBackupLaunchDaemon: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons/\(RuntimeAutomaticBackupSchedule.launchDaemonPlistName)")
    }

    public var managerCommandLog: URL {
        URL(fileURLWithPath: "/private/tmp/\(RuntimeLogArtifactFileNames.managerCommandLog)")
    }

    public var managerHelperMessageLog: URL {
        URL(fileURLWithPath: "/private/tmp/\(RuntimeLogArtifactFileNames.managerHelperMessageLog)")
    }

    public var runtimeUninstallLog: URL {
        URL(fileURLWithPath: "/private/tmp/\(RuntimeLogArtifactFileNames.runtimeUninstallLog)")
    }
}
