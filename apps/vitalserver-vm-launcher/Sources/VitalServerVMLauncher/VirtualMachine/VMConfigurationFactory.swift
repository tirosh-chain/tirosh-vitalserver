import Foundation
import Virtualization

struct VMConfigurationFactory {
    // Build only the Virtualization.framework object graph here.
    func build(from config: VMRuntimeConfig) throws -> VZVirtualMachineConfiguration {
        let bootLoader = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: config.kernelPath))
        if let initialRamdiskPath = config.initialRamdiskPath, !initialRamdiskPath.isEmpty {
            bootLoader.initialRamdiskURL = URL(fileURLWithPath: initialRamdiskPath)
        }
        bootLoader.commandLine = config.kernelCommandLine

        let vmConfiguration = VZVirtualMachineConfiguration()
        vmConfiguration.platform = VZGenericPlatformConfiguration()
        vmConfiguration.bootLoader = bootLoader
        vmConfiguration.cpuCount = config.cpuCount
        vmConfiguration.memorySize = config.memoryMiB * 1024 * 1024
        vmConfiguration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        vmConfiguration.serialPorts = [serialPortConfiguration()]
        vmConfiguration.networkDevices = [try networkDeviceConfiguration(config.network)]
        if let sharedDirectory = config.sharedDirectory {
            vmConfiguration.directorySharingDevices = [
                try directorySharingConfiguration(sharedDirectory)
            ]
        }

        if let diskPath = config.diskPath, !diskPath.isEmpty {
            let attachment = try VZDiskImageStorageDeviceAttachment(
                url: URL(fileURLWithPath: diskPath),
                readOnly: false
            )
            vmConfiguration.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: attachment)]
        }

        try vmConfiguration.validate()
        return vmConfiguration
    }

    // Attach the guest console to this CLI for the PoC.
    private func serialPortConfiguration() -> VZVirtioConsoleDeviceSerialPortConfiguration {
        let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
        serialPort.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: FileHandle.standardInput,
            fileHandleForWriting: FileHandle.standardOutput
        )
        return serialPort
    }

    // Bridged mode is the production hypothesis; shared mode is only for boot
    // smoke tests where source IP preservation is not being validated.
    private func networkDeviceConfiguration(_ network: NetworkConfig) throws -> VZVirtioNetworkDeviceConfiguration {
        let networkDevice = VZVirtioNetworkDeviceConfiguration()

        switch network.mode {
        case .shared:
            networkDevice.attachment = VZNATNetworkDeviceAttachment()
        case .bridged:
            guard let bridgedInterface = network.bridgedInterface, !bridgedInterface.isEmpty else {
                throw LauncherError.missingArgument("bridged network requires `bridgedInterface` in config.json")
            }
            let interfaces = VZBridgedNetworkInterface.networkInterfaces
            guard !interfaces.isEmpty else {
                throw LauncherError.noBridgedInterfaces
            }
            guard let interface = interfaces.first(where: {
                $0.identifier == bridgedInterface || $0.localizedDisplayName == bridgedInterface
            }) else {
                throw LauncherError.bridgedInterfaceUnavailable(bridgedInterface)
            }
            networkDevice.attachment = VZBridgedNetworkDeviceAttachment(interface: interface)
        }

        return networkDevice
    }

    // Expose a macOS host directory to the Linux guest through VirtioFS.
    private func directorySharingConfiguration(
        _ config: SharedDirectoryConfig
    ) throws -> VZVirtioFileSystemDeviceConfiguration {
        let sharedDirectory = VZSharedDirectory(
            url: URL(fileURLWithPath: config.hostPath),
            readOnly: config.readOnly
        )
        let fileSystem = VZVirtioFileSystemDeviceConfiguration(tag: config.tag)
        fileSystem.share = VZSingleDirectoryShare(directory: sharedDirectory)
        return fileSystem
    }
}
