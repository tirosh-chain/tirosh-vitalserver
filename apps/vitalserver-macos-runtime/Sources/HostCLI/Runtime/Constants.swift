import Foundation
import Core
import Contracts

enum Constants {
    enum Product {
        static let identifier = "com.tirosh.vitalserver"
        static let managerAppName = "VitalServer Helper.app"
        static let managerAppPath = "/Applications/\(managerAppName)"
    }

    enum Platform {
        static let current = "macos-arm64"
    }

    enum Environment {
        static let vmHome = "VITALSERVER_VM_HOME"
        static let detached = "VITALSERVER_VM_DETACHED"
    }

    enum Paths {
        static let defaultHomeDisplay = "~/.tirosh/vitalserver-vm"
        static let defaultHomePathComponents = [".tirosh", "vitalserver-vm"]
        static let configFile = "runtime/vm-config.json"
        static let dataDirectory = "data"
        static let runtimeDirectory = "runtime"
        static let logsDirectory = "logs"
        static let runDirectory = "run"
        static let pidFile = "vitalserver-vm.pid"
        static let vitalFilesDirectory = "vital-files"
        static let vrReleaseDirectory = "vr-release"
        static let bundlesDirectory = "bundles"
        static let backupsDirectory = "backups"
        static let statusDirectory = "status"
    }

    enum Artifacts {
        static let rootfsBase = "rootfs-base.raw.gz"
        static let runtimeVersion = "runtime-version.json"
        static let backupManifest = "backup-manifest.json"
        static let runtimeConfig = "runtime-config.json"
        static let runtimeStatus = RuntimeFileNames.runtimeStatus
    }

    enum BootAssets {
        static let kernel = "Image"
        static let initialRamdisk = "initrd.img"
        static let disk = "vm-disk.img"
        static let cloudInit = "seed.iso"
        static let commandLine = "console=hvc0 root=/dev/vda1 rw"
    }

    enum Defaults {
        static let minimumCPUCount = 7
        static let maximumCPUCount = 64
        static let minimumSystemCPUCountForDynamicLimit = 8
        static var maximumAllowedCPUCount: Int {
            let systemCPUCount = ProcessInfo.processInfo.processorCount
            guard systemCPUCount >= minimumSystemCPUCountForDynamicLimit else {
                return minimumCPUCount
            }
            return min(maximumCPUCount, systemCPUCount)
        }
        static let defaultDiskGiB = 32
        static let minimumDiskGiB = 4
        static let maximumDiskGiB = 512
        static let diskStepGiB = 4
        static let minimumMemoryGiB = 4
        static let maximumMemoryGiB = 64
        static let reservedHostMemoryGiB = 4
        static let memoryStepGiB = 4
        static var maximumAllowedMemoryGiB: Int {
            let physicalMemoryGiB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
            let hostAwareMaximum = physicalMemoryGiB - reservedHostMemoryGiB
            let cappedMaximum = min(maximumMemoryGiB, hostAwareMaximum)
            let steppedMaximum = (cappedMaximum / memoryStepGiB) * memoryStepGiB
            return max(minimumMemoryGiB, steppedMaximum)
        }
        static var defaultMemoryGiB: Int {
            min(8, maximumAllowedMemoryGiB)
        }
        static var maximumAllowedMemoryMiB: UInt64 {
            UInt64(maximumAllowedMemoryGiB * 1024)
        }
        static var memoryMiB: UInt64 {
            UInt64(defaultMemoryGiB * 1024)
        }
        static let sharedDirectoryTag = "tirosh"
        static let sharedDirectoryGuestMountPath = "/mnt/tirosh"
        static let vitalFilesDirectoryTag = "tirosh-vital-files"
        static let vitalFilesDirectoryGuestMountPath = "/mnt/tirosh-vital-files"
        static let redisBackupRetentionCount = 30
        static let maximumRedisBackupRetentionCount = 30
    }

    enum Network {
        // Locally administered, unicast MAC prefix. The rest is generated once
        // at init time and persisted in vm-config.json for DHCP reservation.
        static let localMacPrefix0: UInt8 = 0x52
    }

    enum InstallPaths {
        static let vmBin = "/usr/local/bin/vitalserver-vm"
        static let proxyRun = "/usr/local/bin/vitalserver-proxy-run"
        static let uninstall = "/usr/local/bin/tirosh-vitalserver-uninstall"
        static let settingsPath = "/private/tmp/tirosh-vitalserver-install.json"
        static let launchDaemons = "/Library/LaunchDaemons"
    }

    enum Guest {
        static let hostname = "tirosh-vitalserver"
        static let vitalserverHTTPPort = 18080
        static let redisHost = "redis"
        static let redisPort = 6379
        static let redisUIPort = 18081
        static let swaggerUIPort = 18082
        static let publicPort = 80
        static let defaultAdminPassword = "admin"
    }

    enum Runtime {
        static let vmIPFile = RuntimeFileNames.vmIP
        static let runtimeStateFile = RuntimeFileNames.runtimeState
        static let bootstrapLogFile = RuntimeFileNames.bootstrapLog
        static let bootstrapResultFile = RuntimeFileNames.bootstrapResult
        static let datastoreRepairRequestFile = RuntimeFileNames.datastoreRepairRequest
        static let datastoreRepairResultFile = RuntimeFileNames.datastoreRepairResult
        static let datastoreRepairLogFile = RuntimeFileNames.datastoreRepairLog
        static let redisBackupRequestFile = RuntimeFileNames.redisBackupRequest
        static let redisBackupResultFile = RuntimeFileNames.redisBackupResult
        static let updateActivationRequestFile = RuntimeFileNames.updateActivationRequest
        static let updateActivationResultFile = RuntimeFileNames.updateActivationResult
        static let updateActivationLogFile = RuntimeFileNames.updateActivationLog
        static let waitTimeoutSeconds = 600.0
        static let serviceStopWaitTimeoutSeconds = 30.0
        static let vmStopWaitTimeoutSeconds = 330.0
        static let vmDiskSafeShutdownWaitTimeoutSeconds = 240.0
        static let vmForceStopWaitTimeoutSeconds = 30.0
        static let serviceStopPollIntervalSeconds = 0.5
        static let datastoreRepairWaitTimeoutSeconds = 300.0
        static let redisBackupWaitTimeoutSeconds = 300.0
        static let updateActivationWaitTimeoutSeconds = 180.0
        static let runtimeStateStaleAfterSeconds = 30.0
        static let watchdogRecoveryWaitSeconds = 20.0
        static let watchdogManagedOperationGraceSeconds = 1_800.0
        static let guestLogSyncIntervalSeconds = 1.0
        static let freeSpaceMarginBytes: UInt64 = 4 * 1024 * 1024 * 1024
        static let updateFreeSpaceMarginBytes: UInt64 = 2 * 1024 * 1024 * 1024
        static let logRotationMaxBytes: UInt64 = 10 * 1024 * 1024
        static let logRotationKeepCount = 5
        static let backupKeepCount = 5
        static let stagedBundleKeepCount = 3
        static let livenessPath = "/health"
        static let readinessPath = "/ready"

        static func proxyLivenessURL(port: Int) -> String {
            "http://127.0.0.1:\(port)\(livenessPath)"
        }

        static func proxyHealthURL(port: Int) -> String {
            "http://127.0.0.1:\(port)\(readinessPath)"
        }

        static func redisUIHealthURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/redis-ui/"
        }

        static func swaggerUIHealthURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/swagger/"
        }

        static func auditProxyStatusURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/audit-proxy/status"
        }
    }

    enum Bundle {
        static let manifest = "manifest.json"
        static let checksums = "checksums.txt"
        static let signature = "signature"
    }

    enum Commands {
        static let launchctl = "/bin/launchctl"
        static let curl = "/usr/bin/curl"
        static let gunzip = "/usr/bin/gunzip"
        static let truncate = "/usr/bin/truncate"
        static let hdiutil = "/usr/bin/hdiutil"
        static let plistBuddy = "/usr/libexec/PlistBuddy"
        static let chmod = "/bin/chmod"
        static let chown = "/usr/sbin/chown"
        static let kill = "/bin/kill"
        static let ps = "/bin/ps"
        static let tar = "/usr/bin/tar"
        static let lsof = "/usr/sbin/lsof"
    }
}
