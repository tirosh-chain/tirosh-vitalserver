enum Constants {
    static let launcherVersion = "0.1.0"

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
        static let runtimeStatus = "runtime-status.json"
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
        static let memoryMiB: UInt64 = 8192
        static let sharedDirectoryTag = "tirosh"
        static let sharedDirectoryGuestMountPath = "/mnt/tirosh"
        static let vitalFilesDirectoryTag = "tirosh-vital-files"
        static let vitalFilesDirectoryGuestMountPath = "/mnt/tirosh-vital-files"
    }

    enum Network {
        // Locally administered, unicast MAC prefix. The rest is generated once
        // at init time and persisted in vm-config.json for DHCP reservation.
        static let localMacPrefix0: UInt8 = 0x52
    }

    enum InstallPaths {
        static let vmBin = "/usr/local/bin/vitalserver-vm"
        static let proxyRun = "/usr/local/bin/vitalserver-proxy-run"
    }

    enum Launchd {
        static let vmService = "com.tirosh.vitalserver-vm"
        static let proxyService = "com.tirosh.vitalserver-proxy"
        static let watchdogService = "com.tirosh.vitalserver-watchdog"
    }

    enum Runtime {
        static let vmIPFile = "vm-ip"
        static let waitTimeoutSeconds = 600.0
        static let watchdogRecoveryWaitSeconds = 20.0
        static let freeSpaceMarginBytes: UInt64 = 4 * 1024 * 1024 * 1024
        static let updateFreeSpaceMarginBytes: UInt64 = 2 * 1024 * 1024 * 1024
        static let logRotationMaxBytes: UInt64 = 10 * 1024 * 1024
        static let logRotationKeepCount = 5

        static func proxyHealthURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/"
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
    }
}
