import Foundation
import HostRuntimeInfrastructure
import RuntimeCore

enum RuntimeAdapterConstants {
    enum RuntimeCommand {
        static let runtime = "runtime"
        static let configure = "configure"
        static let applyBundle = "apply-bundle"
        static let verifyBundle = "verify-bundle"
        static let rollback = "rollback"
        static let repairDatastore = "repair-datastore"
        static let startServices = "start-services"
        static let stopServices = "stop-services"
        static let optionCPU = "--cpu"
        static let optionMemoryGiB = "--memory-gib"
        static let optionDiskGiB = "--disk-gib"
        static let optionNetwork = "--network"
        static let optionProxyPort = "--proxy-port"
        static let optionVitalFilesDirectory = "--vital-files-dir"
        static let optionPublicHost = "--public-host"
        static let optionPublicPort = "--public-port"
        static let optionStartOnBoot = "--start-on-boot"
        static let optionAutoRecovery = "--auto-recovery"
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
        static let vmIPFile = installed.vmIPFile.path
        static let runtimeState = installed.runtimeState.path
        static let runtimeStatus = installed.runtimeStatus.path
        static let managerApp = installed.managerApp.path
        static let installLog = installed.installLog.path
        static let productLogs = installed.productLogsDirectory.path
        static let runtimeLogs = installed.centralRuntimeLogsDirectory.path
        static let runtimeLogSources = installed.logsDirectory.path
        static let guestLogs = installed.centralGuestLogsDirectory.path
        static let guestRunDirectory = installed.guestRunDirectory.path
        static let logArchive = installed.logArchiveDirectory.path
        static let commandLog = installed.centralCommandLog.path
        static let containerLogs = installed.centralContainerLogs.path
        static let containerLogSource = installed.containerLogs.path
        static let updateActivationLog = installed.centralUpdateActivationLog.path
        static let updateActivationLogSource = installed.updateActivationLog.path
        static let bootstrapLog = installed.centralBootstrapLog.path
        static let bootstrapLogSource = installed.bootstrapLog.path
        static let datastoreRepairLog = installed.centralDatastoreRepairLog.path
        static let datastoreRepairLogSource = installed.guestRunDirectory
            .appendingPathComponent(RuntimeFileNames.datastoreRepairLog)
            .path
        static let vitalFiles = installed.vitalFilesDirectory.path
        static let backups = installed.backupsDirectory.path
        static let vmConfig = installed.vmConfig.path
        static let vmDisk = installed.vmDisk.path
        static let guestRuntimeConfig = installed.guestRuntimeConfig.path
        static let proxyNginxPid = installed.proxyNginxPID.path
        static let proxyLaunchDaemon = installed.proxyLaunchDaemon.path
        static let commandLogFile = installed.managerCommandLog.path
    }

    enum Launchd {
        static let vmService = "com.tirosh.vitalserver-vm"
        static let proxyService = "com.tirosh.vitalserver-proxy"
        static let watchdogService = "com.tirosh.vitalserver-watchdog"
    }

    enum Commands {
        static let osascript = "/usr/bin/osascript"
        static let env = "/usr/bin/env"
        static let open = "/usr/bin/open"
        static let sleep = "/bin/sleep"
        static let curl = "/usr/bin/curl"
        static let launchctl = "/bin/launchctl"
        static let lsof = "/usr/sbin/lsof"
        static let rm = "/bin/rm"
        static let ditto = "/usr/bin/ditto"
    }
}
