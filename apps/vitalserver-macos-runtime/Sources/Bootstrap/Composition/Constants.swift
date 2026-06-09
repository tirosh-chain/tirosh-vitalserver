import Foundation
import Contracts
import Errors

public enum Constants {
    public enum Product {
        public static let identifier = "ai.tirosh.vitalserver.helper"
        public static let packageReceiptIdentifiers = [
            identifier,
        ]
        public static let managerAppName = "VitalServer Helper.app"
        public static let managerAppPath = "/Applications/\(managerAppName)"
    }

    public enum Platform {
        public static let current = "macos-arm64"
    }

    public enum Environment {
        public static let vmHome = "VITALSERVER_VM_HOME"
        public static let detached = "VITALSERVER_VM_DETACHED"
    }

    public enum Paths {
        public static let defaultHomeDisplay = "~/.tirosh/vitalserver-vm"
        public static let defaultHomePathComponents = [".tirosh", "vitalserver-vm"]
        public static let configFile = "runtime/vm-config.json"
        public static let dataDirectory = "data"
        public static let runtimeDirectory = "runtime"
        public static let logsDirectory = "logs"
        public static let runDirectory = "run"
        public static let pidFile = "vitalserver-vm.pid"
        public static let vitalFilesDirectory = "vital-files"
        public static let vrReleaseDirectory = "vr-release"
        public static let bundlesDirectory = "bundles"
        public static let backupsDirectory = "backups"
        public static let statusDirectory = "status"
    }

    public enum Artifacts {
        public static let rootfsBase = RuntimeFileNames.rootfsBase
        public static let runtimeVersion = RuntimeFileNames.runtimeVersion
        public static let backupManifest = RuntimeFileNames.backupManifest
        public static let runtimeConfig = "runtime-config.json"
        public static let runtimeStatus = RuntimeFileNames.runtimeStatus
    }

    public enum BootAssets {
        public static let kernel = "Image"
        public static let initialRamdisk = "initrd.img"
        public static let disk = "vm-disk.img"
        public static let cloudInit = "seed.iso"
        public static let commandLine = "console=hvc0 root=/dev/vda1 rw"
    }

    public enum Defaults {
        public static let minimumCPUCount = 7
        public static let maximumCPUCount = 64
        public static let minimumSystemCPUCountForDynamicLimit = 8
        public static func maximumAllowedCPUCount(systemCPUCount: Int) -> Int {
            guard systemCPUCount >= minimumSystemCPUCountForDynamicLimit else {
                return minimumCPUCount
            }
            return min(maximumCPUCount, systemCPUCount)
        }
        public static let defaultDiskGiB = 32
        public static let minimumDiskGiB = 4
        public static let maximumDiskGiB = 512
        public static let diskStepGiB = 4
        public static let minimumMemoryGiB = 4
        public static let maximumMemoryGiB = 64
        public static let reservedHostMemoryGiB = 4
        public static let memoryStepGiB = 4
        public static func maximumAllowedMemoryGiB(physicalMemoryBytes: UInt64) -> Int {
            let physicalMemoryGiB = Int(physicalMemoryBytes / 1_073_741_824)
            let hostAwareMaximum = physicalMemoryGiB - reservedHostMemoryGiB
            let cappedMaximum = min(maximumMemoryGiB, hostAwareMaximum)
            let steppedMaximum = (cappedMaximum / memoryStepGiB) * memoryStepGiB
            return max(minimumMemoryGiB, steppedMaximum)
        }
        public static func defaultMemoryGiB(physicalMemoryBytes: UInt64) -> Int {
            min(8, maximumAllowedMemoryGiB(physicalMemoryBytes: physicalMemoryBytes))
        }
        public static func maximumAllowedMemoryMiB(physicalMemoryBytes: UInt64) -> UInt64 {
            UInt64(maximumAllowedMemoryGiB(physicalMemoryBytes: physicalMemoryBytes) * 1024)
        }
        public static func memoryMiB(physicalMemoryBytes: UInt64) -> UInt64 {
            UInt64(defaultMemoryGiB(physicalMemoryBytes: physicalMemoryBytes) * 1024)
        }
        public static let sharedDirectoryTag = "tirosh"
        public static let sharedDirectoryGuestMountPath = "/mnt/tirosh"
        public static let vitalFilesDirectoryTag = "tirosh-vital-files"
        public static let vitalFilesDirectoryGuestMountPath = "/mnt/tirosh-vital-files"
        public static let redisBackupRetentionCount = 30
        public static let maximumRedisBackupRetentionCount = 30
    }

    public enum Network {
        // Locally administered, unicast MAC prefix. The rest is generated once
        // at init time and persisted in vm-config.json for DHCP reservation.
        public static let localMacPrefix0: UInt8 = 0x52
    }

    public enum InstallPaths {
        public static let vmBin = "/usr/local/bin/vitalserver-vm"
        public static let proxyRun = "/usr/local/bin/vitalserver-proxy-run"
        public static let uninstall = "/usr/local/bin/tirosh-vitalserver-uninstall"
        public static let settingsPath = "/private/tmp/tirosh-vitalserver-install.json"
        public static let launchDaemons = "/Library/LaunchDaemons"
    }

    public enum Guest {
        public static let hostname = "tirosh-vitalserver"
        public static let vitalserverHTTPPort = 18080
        public static let redisHost = "redis"
        public static let redisPort = 6379
        public static let redisUIPort = 18081
        public static let swaggerUIPort = 18082
        public static let publicPort = 80
        public static let defaultAdminPassword = "admin"
    }

    public enum Runtime {
        public static let vmIPFile = RuntimeFileNames.vmIP
        public static let runtimeStateFile = RuntimeFileNames.runtimeState
        public static let bootstrapLogFile = RuntimeFileNames.bootstrapLog
        public static let bootstrapResultFile = RuntimeFileNames.bootstrapResult
        public static let datastoreRepairRequestFile = RuntimeFileNames.datastoreRepairRequest
        public static let datastoreRepairResultFile = RuntimeFileNames.datastoreRepairResult
        public static let datastoreRepairLogFile = RuntimeFileNames.datastoreRepairLog
        public static let redisBackupRequestFile = RuntimeFileNames.redisBackupRequest
        public static let redisBackupResultFile = RuntimeFileNames.redisBackupResult
        public static let updateActivationRequestFile = RuntimeFileNames.updateActivationRequest
        public static let updateActivationResultFile = RuntimeFileNames.updateActivationResult
        public static let updateActivationLogFile = RuntimeFileNames.updateActivationLog
        public static let updateShutdownRequestFile = RuntimeFileNames.updateShutdownRequest
        public static let updateShutdownResultFile = RuntimeFileNames.updateShutdownResult
        public static let updateShutdownLogFile = RuntimeFileNames.updateShutdownLog
        public static let waitTimeoutSeconds = 600.0
        public static let serviceStopWaitTimeoutSeconds = 30.0
        public static let vmStopWaitTimeoutSeconds = 900.0
        public static let vmForceStopWaitTimeoutSeconds = 30.0
        public static let serviceStopPollIntervalSeconds = 0.5
        public static let datastoreRepairWaitTimeoutSeconds = 300.0
        public static let redisBackupWaitTimeoutSeconds = 300.0
        public static let updateActivationWaitTimeoutSeconds = 180.0
        public static let updateShutdownWaitTimeoutSeconds = 300.0
        public static let vmBootLifecycleDeadlineSeconds = 600.0
        public static let runtimeStateStaleAfterSeconds = 30.0
        public static let watchdogRecoveryWaitSeconds = 20.0
        public static let watchdogManagedOperationGraceSeconds = 1_800.0
        public static let guestLogSyncIntervalSeconds = 1.0
        public static let freeSpaceMarginBytes: UInt64 = 4 * 1024 * 1024 * 1024
        public static let updateFreeSpaceMarginBytes: UInt64 = 2 * 1024 * 1024 * 1024
        public static let logRotationMaxBytes: UInt64 = 10 * 1024 * 1024
        public static let logRotationKeepCount = 5
        public static let backupKeepCount = 5
        public static let stagedBundleKeepCount = 3
        public static let livenessPath = "/health"
        public static let readinessPath = "/ready"

        public static func proxyLivenessURL(port: Int) -> String {
            "http://127.0.0.1:\(port)\(livenessPath)"
        }

        public static func proxyHealthURL(port: Int) -> String {
            "http://127.0.0.1:\(port)\(readinessPath)"
        }

        public static func redisUIHealthURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/redis-ui/"
        }

        public static func swaggerUIHealthURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/swagger/"
        }

        public static func auditProxyStatusURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/audit-proxy/status"
        }
    }

    public enum Bundle {
        public static let manifest = RuntimeFileNames.updateBundleManifest
        public static let checksums = "checksums.txt"
        public static let signature = "signature"
    }

    public enum Commands {
        public static let launchctl = "/bin/launchctl"
        public static let curl = "/usr/bin/curl"
        public static let gunzip = "/usr/bin/gunzip"
        public static let truncate = "/usr/bin/truncate"
        public static let hdiutil = "/usr/bin/hdiutil"
        public static let plistBuddy = "/usr/libexec/PlistBuddy"
        public static let chmod = "/bin/chmod"
        public static let chown = "/usr/sbin/chown"
        public static let kill = "/bin/kill"
        public static let ps = "/bin/ps"
        public static let tar = "/usr/bin/tar"
        public static let lsof = "/usr/sbin/lsof"
        public static let pkgutil = "/usr/sbin/pkgutil"
    }
}
