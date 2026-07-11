import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

enum RuntimeControlClientConstants {
    enum Product {
        static let defaultProxyPort = 80
        static let packageIdentifier = "ai.tirosh.vitalserver.helper"

        static func redisUIURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/redis-ui/"
        }

        static func swaggerURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/swagger/"
        }

        static func hostProxyHealthURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/ready"
        }

        static func guestHealthURL(vmIP: String) -> String {
            "http://\(vmIP)/ready"
        }

        static func guestControlAPIBaseURL(vmIP: String) -> String {
            "http://\(vmIP):18330"
        }

        static let localGuestControlAPIBaseURL = "http://127.0.0.1:18330"
        static let guestControlAPIReadinessTimeoutSeconds: TimeInterval = 5
        static let guestControlAPIStackStatusTimeoutSeconds: TimeInterval = 5
        static let guestControlAPIProductReadModelTimeoutSeconds: TimeInterval = 5
        static let guestControlAPIDiagnosticsTimeoutSeconds: TimeInterval = 5
    }

    enum StatusText {
        static let failed = "failed"
        static let missingLauncher = "vitalserver-vm launcher is missing. Reinstall the app or package."
        static let missingUninstaller = "Uninstaller is missing. Reinstall the package before uninstalling."
        static let logExportFailed = "Failed to export logs."
    }

    enum RuntimeCommand {
        static let runtime = "runtime"
        static let configure = "configure"
        static let applyBundle = "apply-bundle"
        static let verifyBundle = "verify-bundle"
        static let rollback = "rollback"
        static let redisBackup = "redis-backup"
        static let redisRestore = "redis-restore"
        static let runtimeDataBackup = "runtime-data-backup"
        static let runtimeDataRestore = "runtime-data-restore"
        static let repairDatastore = "repair-datastore"
        static let repairVMDisk = "repair-vm-disk"
        static let repairProxy = "repair-proxy"
        static let repairServices = "repair-services"
        static let startServices = "start-services"
        static let stopServices = "stop-services"
        static let boolTrue = "true"
        static let boolFalse = "false"
        static let optionCPU = "--cpu"
        static let optionMemoryGiB = "--memory-gib"
        static let optionDiskGiB = "--disk-gib"
        static let optionNetwork = "--network"
        static let optionProxyPort = "--proxy-port"
        static let optionRuntimeControlPort = "--runtime-control-port"
        static let optionVitalFilesDirectory = "--vital-files-dir"
        static let optionVitalServerURL = "--vitalserver-url"
        static let optionRemoteConsoleURL = "--remote-console-url"
        static let optionPublicHost = "--public-host"
        static let optionPublicPort = "--public-port"
        static let optionRecorderIngressSendDataMode = "--recorder-ingress-send-data-mode"
        static let optionRecorderIngressSendDataReplayBatchSize = "--recorder-ingress-send-data-replay-batch-size"
        static let optionRecorderIngressSendDataReplayMaxMiBPerSecond = "--recorder-ingress-send-data-replay-max-mib-per-second"
        static let optionRecorderIngressSettingsFile = "--recorder-ingress-settings-file"
        static let optionContainerMemoryLimits = "--container-memory-limits"
        static let optionVitalServerContainerMemoryLimitMiB = "--vitalserver-container-memory-limit-mib"
        static let optionRecorderIngressContainerMemoryLimitMiB = "--recorder-ingress-container-memory-limit-mib"
        static let optionRedisContainerMemoryLimitMiB = "--redis-container-memory-limit-mib"
        static let optionStartOnBoot = "--start-on-boot"
        static let optionAutoRecovery = "--auto-recovery"
        static let optionPreventSystemSleep = "--prevent-system-sleep"
        static let optionAutomaticBackup = "--automatic-backup"
        static let optionBackupScheduleTimes = "--backup-schedule-times"
        static let optionBackupRetention = "--backup-retention"
        static let optionLogArchiveRetentionDays = "--log-archive-retention-days"
        static let optionLogArchiveMaximumGiB = "--log-archive-maximum-gib"
        static let optionBridgedInterface = "--bridged-interface"
        static let optionAdminPasswordFile = "--admin-password-file"
        static let optionRestart = "--restart"
    }

    enum Environment {
        static let vmHome = "VITALSERVER_VM_HOME"
    }

    enum Paths {
        private static let installed = InstalledRuntimePaths.defaultInstalled

        static let vmHome = installed.runtimeHome.path
        static let launcher = installed.launcher.path
        static let uninstaller = installed.uninstaller.path
        static let runtimeControlSettings = installed.runtimeControlSettings.path
        static let managerApp = installed.managerApp.path
        static let installLog = installed.installLog.path
        static let productLogs = installed.productLogsDirectory.path
        static let uninstallLog = installed.runtimeUninstallLog.path
        static let runtimeLogs = installed.centralRuntimeLogsDirectory.path
        static let runtimeLogSources = installed.logsDirectory.path
        static let guestLogs = installed.centralGuestLogsDirectory.path
        static let guestRunDirectory = installed.guestRunDirectory.path
        static let guestObservability = installed.centralGuestObservabilityDirectory.path
        static let guestObservabilitySource = installed.guestObservabilityDirectory.path
        static let logArchive = installed.logArchiveDirectory.path
        static let commandLog = installed.centralCommandLog.path
        static let containerLogs = installed.centralContainerLogs.path
        static let containerLogSource = installed.containerLogs.path
        static let updateActivationLog = installed.centralUpdateActivationLog.path
        static let updateActivationLogSource = installed.updateActivationLog.path
        static let updateShutdownLog = installed.centralUpdateShutdownLog.path
        static let updateShutdownLogSource = installed.updateShutdownLog.path
        static let bootstrapLog = installed.centralBootstrapLog.path
        static let bootstrapLogSource = installed.bootstrapLog.path
        static let datastoreRepairLog = installed.centralDatastoreRepairLog.path
        static let datastoreRepairLogSource = installed.datastoreRepairLog.path
        static let redisBackupLog = installed.centralRedisBackupLog.path
        static let redisBackupLogSource = installed.redisBackupLog.path
        static let vitalFiles = installed.vitalFilesDirectory.path
        static let backups = installed.backupsDirectory.path
        static let redisBackups = installed.redisBackupsDirectory.path
        static let runtimeDataBackups = installed.vitalServerHelperBackupsDirectory.path
        static let vmConfig = installed.vmConfig.path
        static let vmDisk = installed.vmDisk.path
        static let guestRuntimeConfig = installed.guestRuntimeConfig.path
        static let guestRuntimeSettings = installed.guestRuntimeSettings.path
        static let redisRelayConfig = installed.redisRelayConfig.path
        static let redisRelayTargetPassword = installed.redisRelayTargetPassword.path
        static let redisRelayStatus = installed.redisRelayStatusDirectory
            .appendingPathComponent("redis-relay-status.json")
            .path
        static let runtimeVersion = installed.runtimeDirectory.appendingPathComponent("runtime-version.json").path
        static let proxyNginxPid = installed.proxyNginxPID.path
        static let proxyNginxConfig = installed.nginxDirectory.appendingPathComponent("vitalserver.conf").path
        static let proxyNginxAccessLog = installed.proxyNginxAccessLog.path
        static let proxyNginxErrorLog = installed.proxyNginxErrorLog.path
        static let proxyLaunchDaemon = installed.proxyLaunchDaemon.path
        static let commandLogFile = installed.managerCommandLog.path
        static let helperMessageLogFile = installed.managerHelperMessageLog.path
    }

    enum Commands {
        static let osascript = "/usr/bin/osascript"
        static let env = "/usr/bin/env"
        static let curl = "/usr/bin/curl"
        static let launchctl = "/bin/launchctl"
        static let lsof = "/usr/sbin/lsof"
        static let rm = "/bin/rm"
        static let ditto = "/usr/bin/ditto"
    }
}
