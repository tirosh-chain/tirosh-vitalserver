import Foundation
import RuntimeControl
import HostRuntimeInfrastructure
import RuntimeCore

public enum RuntimeAdapterConstants {
    public enum Product {
        public static let defaultProxyPort = 80

        public static func redisUIURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/redis-ui/"
        }

        public static func swaggerURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/swagger/"
        }

        public static func hostProxyHealthURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/ready"
        }

        public static func guestHealthURL(vmIP: String) -> String {
            "http://\(vmIP)/ready"
        }
    }

    public enum StatusText {
        public static let failed = "failed"
        public static let noLogData = "No log data for this source yet."
        public static let missingLauncher = "vitalserver-vm launcher is missing. Reinstall the app or package."
        public static let missingUninstaller = "Uninstaller is missing. Reinstall the package before uninstalling."
        public static let logExportFailed = "Failed to export logs."
    }

    public enum RuntimeCommand {
        public static let runtime = "runtime"
        public static let configure = "configure"
        public static let applyBundle = "apply-bundle"
        public static let verifyBundle = "verify-bundle"
        public static let rollback = "rollback"
        public static let repairDatastore = "repair-datastore"
        public static let startServices = "start-services"
        public static let stopServices = "stop-services"
        public static let optionCPU = "--cpu"
        public static let optionMemoryGiB = "--memory-gib"
        public static let optionDiskGiB = "--disk-gib"
        public static let optionNetwork = "--network"
        public static let optionProxyPort = "--proxy-port"
        public static let optionVitalFilesDirectory = "--vital-files-dir"
        public static let optionPublicHost = "--public-host"
        public static let optionPublicPort = "--public-port"
        public static let optionStartOnBoot = "--start-on-boot"
        public static let optionAutoRecovery = "--auto-recovery"
        public static let optionBridgedInterface = "--bridged-interface"
        public static let optionAdminPasswordFile = "--admin-password-file"
        public static let optionRestart = "--restart"
    }

    public enum Environment {
        public static let vmHome = "VITALSERVER_VM_HOME"
    }

    public enum Paths {
        private static let installed = InstalledRuntimePaths.defaultInstalled

        public static let vmHome = installed.runtimeHome.path
        public static let launcher = installed.launcher.path
        public static let uninstaller = installed.uninstaller.path
        public static let vmIPFile = installed.vmIPFile.path
        public static let runtimeState = installed.runtimeState.path
        public static let runtimeStatus = installed.runtimeStatus.path
        public static let managerApp = installed.managerApp.path
        public static let installLog = installed.installLog.path
        public static let productLogs = installed.productLogsDirectory.path
        public static let runtimeLogs = installed.centralRuntimeLogsDirectory.path
        public static let runtimeLogSources = installed.logsDirectory.path
        public static let guestLogs = installed.centralGuestLogsDirectory.path
        public static let guestRunDirectory = installed.guestRunDirectory.path
        public static let logArchive = installed.logArchiveDirectory.path
        public static let commandLog = installed.centralCommandLog.path
        public static let containerLogs = installed.centralContainerLogs.path
        public static let containerLogSource = installed.containerLogs.path
        public static let updateActivationLog = installed.centralUpdateActivationLog.path
        public static let updateActivationLogSource = installed.updateActivationLog.path
        public static let bootstrapLog = installed.centralBootstrapLog.path
        public static let bootstrapLogSource = installed.bootstrapLog.path
        public static let datastoreRepairLog = installed.centralDatastoreRepairLog.path
        public static let datastoreRepairLogSource = installed.guestRunDirectory
            .appendingPathComponent(RuntimeFileNames.datastoreRepairLog)
            .path
        public static let vitalFiles = installed.vitalFilesDirectory.path
        public static let backups = installed.backupsDirectory.path
        public static let vmConfig = installed.vmConfig.path
        public static let vmDisk = installed.vmDisk.path
        public static let guestRuntimeConfig = installed.guestRuntimeConfig.path
        public static let proxyNginxPid = installed.proxyNginxPID.path
        public static let proxyLaunchDaemon = installed.proxyLaunchDaemon.path
        public static let commandLogFile = installed.managerCommandLog.path
    }

    public enum Commands {
        public static let osascript = "/usr/bin/osascript"
        public static let env = "/usr/bin/env"
        public static let open = "/usr/bin/open"
        public static let sleep = "/bin/sleep"
        public static let curl = "/usr/bin/curl"
        public static let launchctl = "/bin/launchctl"
        public static let lsof = "/usr/sbin/lsof"
        public static let rm = "/bin/rm"
        public static let ditto = "/usr/bin/ditto"
    }
}
