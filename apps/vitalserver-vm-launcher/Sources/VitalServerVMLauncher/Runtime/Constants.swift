enum Constants {
    static let launcherVersion = "0.1.0"

    enum Environment {
        static let vmHome = "VITALSERVER_VM_HOME"
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
        static let kernel = "vmlinuz"
        static let initialRamdisk = "initrd.img"
        static let disk = "rootfs.raw"
        static let commandLine = "console=hvc0 root=/dev/vda rw"
    }

    enum Defaults {
        static let minimumCPUCount = 2
        static let maximumCPUCount = 8
        static let memoryMiB: UInt64 = 4096
        static let sharedDirectoryTag = "tirosh"
        static let sharedDirectoryGuestMountPath = "/mnt/tirosh"
    }
}
