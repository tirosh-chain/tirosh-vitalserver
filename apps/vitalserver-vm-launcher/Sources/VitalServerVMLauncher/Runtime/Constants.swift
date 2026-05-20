enum Constants {
    static let launcherVersion = "0.1.0"

    enum Environment {
        static let vmHome = "VITALSERVER_VM_HOME"
        static let detached = "VITALSERVER_VM_DETACHED"
    }

    enum Paths {
        static let defaultHomeDisplay = "~/.tirosh/vitalserver-vm"
        static let defaultHomePathComponents = [".tirosh", "vitalserver-vm"]
        static let configFile = "config.json"
        static let dataDirectory = "data"
        static let imagesDirectory = "images"
        static let logsDirectory = "logs"
        static let runDirectory = "run"
        static let pidFile = "vitalserver-vm.pid"
        static let vitalFilesDirectory = "vital-files"
        static let vrReleaseDirectory = "vr-release"
    }

    enum BootAssets {
        static let kernel = "Image"
        static let initialRamdisk = "initrd.img"
        static let disk = "rootfs.raw"
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
        // at init time and persisted in config.json for DHCP reservation.
        static let localMacPrefix0: UInt8 = 0x52
    }
}
