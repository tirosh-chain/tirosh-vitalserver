import Application
import Foundation
import Virtualization
import Errors

public final class VMConfigurationFactory {
    private var retainedSerialInputPipes: [Pipe] = []
    private let fileStore: RuntimeFileReading
    private let detached: Bool
    private let serialInput: FileHandle
    private let serialOutput: FileHandle

    public init(
        fileStore: RuntimeFileReading,
        detached: Bool,
        serialInput: FileHandle,
        serialOutput: FileHandle
    ) {
        self.fileStore = fileStore
        self.detached = detached
        self.serialInput = serialInput
        self.serialOutput = serialOutput
    }

    // Build only the Virtualization.framework object graph here.
    public func build(from config: VMRuntimeConfig) throws -> VZVirtualMachineConfiguration {
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
        vmConfiguration.directorySharingDevices = try [config.sharedDirectory, config.vitalFilesDirectory]
            .compactMap { $0 }
            .map(directorySharingConfiguration)

        vmConfiguration.storageDevices = try storageDeviceConfigurations(config)

        try vmConfiguration.validate()
        return vmConfiguration
    }

    private func storageDeviceConfigurations(
        _ config: VMRuntimeConfig
    ) throws -> [VZVirtioBlockDeviceConfiguration] {
        var storageDevices: [VZVirtioBlockDeviceConfiguration] = []

        if let diskPath = config.diskPath, !diskPath.isEmpty {
            try validateStoragePath(diskPath)
            let attachment = try VZDiskImageStorageDeviceAttachment(
                url: URL(fileURLWithPath: diskPath),
                readOnly: false
            )
            storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: attachment))
        }

        if let cloudInitPath = config.cloudInitPath,
           !cloudInitPath.isEmpty {
            try validateStoragePath(cloudInitPath)
            let attachment = try VZDiskImageStorageDeviceAttachment(
                url: URL(fileURLWithPath: cloudInitPath),
                readOnly: true
            )
            storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: attachment))
        }

        return storageDevices
    }

    private func validateStoragePath(_ path: String) throws {
        let state = fileStore.pathState(at: URL(fileURLWithPath: path))
        switch state {
        case .file:
            return
        case .missing:
            throw VMConfigurationFactoryError.missingStorageFile(path)
        case .inspectFailed(let reason):
            throw VMConfigurationFactoryError.storagePathInspectionFailed(path: path, reason: reason)
        case .directory, .other, .unknown:
            throw VMConfigurationFactoryError.unexpectedStoragePathState(path: path, state: state.rawValue)
        }
    }

    // Attach the guest console to this CLI for the PoC.
    private func serialPortConfiguration() -> VZVirtioConsoleDeviceSerialPortConfiguration {
        let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
        let input: FileHandle
        if detached {
            let pipe = Pipe()
            retainedSerialInputPipes.append(pipe)
            input = pipe.fileHandleForReading
        } else {
            input = serialInput
        }
        serialPort.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: input,
            fileHandleForWriting: serialOutput
        )
        return serialPort
    }

    // Bridged mode is the production hypothesis; shared mode is only for boot
    // smoke tests where source IP preservation is not being validated.
    private func networkDeviceConfiguration(_ network: NetworkConfig) throws -> VZVirtioNetworkDeviceConfiguration {
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        if let macAddressValue = network.macAddress, !macAddressValue.isEmpty {
            guard let macAddress = VZMACAddress(string: macAddressValue) else {
                throw VMConfigurationFactoryError.invalidMacAddress(macAddressValue)
            }
            networkDevice.macAddress = macAddress
        }

        switch network.mode {
        case .shared:
            networkDevice.attachment = VZNATNetworkDeviceAttachment()
        case .bridged:
            guard let bridgedInterface = network.bridgedInterface, !bridgedInterface.isEmpty else {
                throw VMConfigurationFactoryError.missingBridgedInterface
            }
            let interfaces = VZBridgedNetworkInterface.networkInterfaces
            guard !interfaces.isEmpty else {
                throw VMConfigurationFactoryError.noBridgedInterfaces
            }
            guard let interface = interfaces.first(where: {
                $0.identifier == bridgedInterface || $0.localizedDisplayName == bridgedInterface
            }) else {
                throw VMConfigurationFactoryError.bridgedInterfaceUnavailable(bridgedInterface)
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
