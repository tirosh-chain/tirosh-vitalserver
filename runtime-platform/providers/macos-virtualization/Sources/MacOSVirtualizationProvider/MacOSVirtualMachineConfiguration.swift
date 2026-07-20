import Foundation
import Virtualization

// MacOSVirtualMachineConfigurationDocument is the Host-owned deployment
// contract for one Linux Guest. It contains every path and resource identity
// needed to create a VZVirtualMachine; the provider never derives them from a
// directory layout, a previous process, or a VM name.
public struct MacOSVirtualMachineConfigurationDocument: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let machineId: String
    public let cpuCount: Int
    public let memoryBytes: UInt64
    public let boot: LinuxBootResources
    public let guestBootConsoleCapture: GuestBootConsoleCapture
    public let guestRuntimeDiskProvisioning: GuestRuntimeDiskProvisioning
    public let guestRuntimeControlHostLocalHTTPBridge: GuestRuntimeControlHostLocalHTTPBridgeConfiguration
    public let guestProductReleaseManagerHostLocalHTTPBridge: GuestProductReleaseManagerHostLocalHTTPBridgeConfiguration
    public let guestBundledUpstreamImageSetManagerHostLocalHTTPBridge: GuestBundledUpstreamImageSetManagerHostLocalHTTPBridgeConfiguration?
    public let guestPublicServiceHostLocalHTTPBridges: [GuestPublicServiceHostLocalHTTPBridgeConfiguration]
    public let storageDevices: [MacOSVirtualMachineStorageDevice]
    public let network: MacOSVirtualMachineNetworkDevice

    public init(
        schemaVersion: String,
        machineId: String,
        cpuCount: Int,
        memoryBytes: UInt64,
        boot: LinuxBootResources,
        guestBootConsoleCapture: GuestBootConsoleCapture,
        guestRuntimeDiskProvisioning: GuestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: GuestRuntimeControlHostLocalHTTPBridgeConfiguration,
        guestProductReleaseManagerHostLocalHTTPBridge: GuestProductReleaseManagerHostLocalHTTPBridgeConfiguration,
        guestBundledUpstreamImageSetManagerHostLocalHTTPBridge: GuestBundledUpstreamImageSetManagerHostLocalHTTPBridgeConfiguration? = nil,
        guestPublicServiceHostLocalHTTPBridges: [GuestPublicServiceHostLocalHTTPBridgeConfiguration],
        storageDevices: [MacOSVirtualMachineStorageDevice],
        network: MacOSVirtualMachineNetworkDevice
    ) {
        self.schemaVersion = schemaVersion
        self.machineId = machineId
        self.cpuCount = cpuCount
        self.memoryBytes = memoryBytes
        self.boot = boot
        self.guestBootConsoleCapture = guestBootConsoleCapture
        self.guestRuntimeDiskProvisioning = guestRuntimeDiskProvisioning
        self.guestRuntimeControlHostLocalHTTPBridge = guestRuntimeControlHostLocalHTTPBridge
        self.guestProductReleaseManagerHostLocalHTTPBridge = guestProductReleaseManagerHostLocalHTTPBridge
        self.guestBundledUpstreamImageSetManagerHostLocalHTTPBridge = guestBundledUpstreamImageSetManagerHostLocalHTTPBridge
        self.guestPublicServiceHostLocalHTTPBridges = guestPublicServiceHostLocalHTTPBridges
        self.storageDevices = storageDevices
        self.network = network
    }

    public var validationMessage: String? {
        guard schemaVersion == "v1", isDeploymentIdentifier(machineId) else {
            return "schemaVersion v1 and machineId are required"
        }
        guard cpuCount > 0, memoryBytes > 0 else {
            return "cpuCount and memoryBytes must be positive"
        }
        guard boot.validationMessage == nil else {
            return boot.validationMessage
        }
        guard guestBootConsoleCapture.validationMessage == nil else {
            return guestBootConsoleCapture.validationMessage
        }
        guard guestRuntimeDiskProvisioning.validationMessage == nil else {
            return guestRuntimeDiskProvisioning.validationMessage
        }
        guard guestRuntimeControlHostLocalHTTPBridge.validationMessage == nil else {
            return guestRuntimeControlHostLocalHTTPBridge.validationMessage
        }
        guard guestProductReleaseManagerHostLocalHTTPBridge.validationMessage == nil else {
            return guestProductReleaseManagerHostLocalHTTPBridge.validationMessage
        }
        if let guestBundledUpstreamImageSetManagerHostLocalHTTPBridge,
           let message = guestBundledUpstreamImageSetManagerHostLocalHTTPBridge.validationMessage {
            return message
        }
        if let message = guestPublicServiceHostLocalHTTPBridgeValidationMessage {
            return message
        }
        guard storageDevices.count == 2 else {
            return "exactly guest-root and guest-product-bootstrap storage devices are required"
        }
        var storageIds = Set<String>()
        for (index, device) in storageDevices.enumerated() {
            guard device.validationMessage == nil else {
                return device.validationMessage
            }
            guard storageIds.insert(device.id).inserted else {
                return "storage device ids must be unique"
            }
            guard device.attachmentIndex == index else {
                return "storage device attachmentIndex must preserve declared attachment order"
            }
        }
        guard Set(storageDevices.map(\.id)) == Set(["guest-root", "guest-product-bootstrap"]) else {
            return "storage devices must be guest-root and guest-product-bootstrap"
        }
        guard storageDevices.first(where: { $0.id == "guest-root" })?.diskImagePath == guestRuntimeDiskProvisioning.runtimeDiskImagePath else {
            return "guest-root diskImagePath must name the Guest Runtime disk provisioning runtimeDiskImagePath"
        }
        return network.validationMessage
    }

    private var guestPublicServiceHostLocalHTTPBridgeValidationMessage: String? {
        guard !guestPublicServiceHostLocalHTTPBridges.isEmpty else {
            return "at least one Guest public service Host-local HTTP bridge is required"
        }
        var routeIDs = Set<String>()
        var hostLoopbackPorts = Set<UInt16>([
            guestRuntimeControlHostLocalHTTPBridge.hostLoopbackPort,
            guestProductReleaseManagerHostLocalHTTPBridge.hostLoopbackPort,
        ])
        guard hostLoopbackPorts.count == 2 else {
            return "Guest Product Release Manager control Host-local HTTP bridge hostLoopbackPort cannot reuse Guest Runtime control"
        }
        if let bundledUpstreamBridge = guestBundledUpstreamImageSetManagerHostLocalHTTPBridge {
            guard hostLoopbackPorts.insert(bundledUpstreamBridge.hostLoopbackPort).inserted else {
                return "Guest Bundled Upstream Image-set Manager control Host-local HTTP bridge hostLoopbackPort cannot reuse another Host listener"
            }
        }
        var guestVirtioSocketPorts = Set<UInt32>([
            guestRuntimeControlHostLocalHTTPBridge.guestVirtioSocketPort,
            guestProductReleaseManagerHostLocalHTTPBridge.guestVirtioSocketPort,
        ])
        guard guestVirtioSocketPorts.count == 2 else {
            return "Guest Product Release Manager control Host-local HTTP bridge guestVirtioSocketPort cannot reuse Guest Runtime control"
        }
        if let bundledUpstreamBridge = guestBundledUpstreamImageSetManagerHostLocalHTTPBridge {
            guard guestVirtioSocketPorts.insert(bundledUpstreamBridge.guestVirtioSocketPort).inserted else {
                return "Guest Bundled Upstream Image-set Manager control Host-local HTTP bridge guestVirtioSocketPort cannot reuse another Guest listener"
            }
        }
        for bridge in guestPublicServiceHostLocalHTTPBridges {
            guard bridge.validationMessage == nil else {
                return bridge.validationMessage
            }
            guard routeIDs.insert(bridge.routeId).inserted else {
                return "Guest public service Host-local HTTP bridge routeId values must be unique"
            }
            guard hostLoopbackPorts.insert(bridge.hostLoopbackPort).inserted else {
                return "Guest public service Host-local HTTP bridge hostLoopbackPort cannot reuse another Host listener"
            }
            guard guestVirtioSocketPorts.insert(bridge.guestVirtioSocketPort).inserted else {
                return "Guest public service Host-local HTTP bridge guestVirtioSocketPort cannot reuse another Guest listener"
            }
        }
        return nil
    }
}

public struct GuestBootConsoleCapture: Codable, Equatable, Sendable {
    public let capturePath: String
    public let writeMode: String

    public init(capturePath: String, writeMode: String) {
        self.capturePath = capturePath
        self.writeMode = writeMode
    }

    var validationMessage: String? {
        guard isSafeHostAbsolutePath(capturePath) else {
            return "Guest boot console capturePath must be an absolute path without traversal"
        }
        guard writeMode == "append" else {
            return "Guest boot console writeMode must be append"
        }
        return nil
    }
}

// GuestRuntimeDiskProvisioning distinguishes immutable release bytes from the
// Host-persistent disk that the Linux Guest will write after boot. C32 names
// both paths so the supervisor cannot reuse a release artifact as VM state.
public struct GuestRuntimeDiskProvisioning: Codable, Equatable, Sendable {
    public let releaseArtifactManifestPath: String
    public let releaseArtifactPath: String
    public let runtimeDiskImagePath: String
    public let provisioningReceiptPath: String
    public let existingRuntimeDiskPolicy: String

    public init(
        releaseArtifactManifestPath: String,
        releaseArtifactPath: String,
        runtimeDiskImagePath: String,
        provisioningReceiptPath: String,
        existingRuntimeDiskPolicy: String
    ) {
        self.releaseArtifactManifestPath = releaseArtifactManifestPath
        self.releaseArtifactPath = releaseArtifactPath
        self.runtimeDiskImagePath = runtimeDiskImagePath
        self.provisioningReceiptPath = provisioningReceiptPath
        self.existingRuntimeDiskPolicy = existingRuntimeDiskPolicy
    }

    var validationMessage: String? {
        let paths = [
            releaseArtifactManifestPath,
            releaseArtifactPath,
            runtimeDiskImagePath,
            provisioningReceiptPath,
        ]
        guard paths.allSatisfy(isSafeHostAbsolutePath) else {
            return "Guest Runtime disk provisioning paths must be absolute without traversal"
        }
        guard Set(paths).count == paths.count else {
            return "Guest Runtime disk provisioning paths must name distinct Host resources"
        }
        guard existingRuntimeDiskPolicy == "retain-when-receipt-matches-release-artifact" else {
            return "Guest Runtime disk provisioning must declare retain-when-receipt-matches-release-artifact"
        }
        return nil
    }
}

// GuestRuntimeControlHostLocalHTTPBridgeConfiguration names a Host-local HTTP
// boundary separately from the Guest-local virtio socket boundary. Apple NAT
// permits outbound Guest networking but is not a Host-to-Guest control
// contract, so neither address nor port is inferred from the NAT attachment.
public struct GuestRuntimeControlHostLocalHTTPBridgeConfiguration: Codable, Equatable, Sendable {
    public let hostLoopbackAddress: String
    public let hostLoopbackPort: UInt16
    public let guestVirtioSocketPort: UInt32

    public init(
        hostLoopbackAddress: String,
        hostLoopbackPort: UInt16,
        guestVirtioSocketPort: UInt32
    ) {
        self.hostLoopbackAddress = hostLoopbackAddress
        self.hostLoopbackPort = hostLoopbackPort
        self.guestVirtioSocketPort = guestVirtioSocketPort
    }

    fileprivate var validationMessage: String? {
        guard hostLoopbackAddress == "127.0.0.1" else {
            return "Guest Runtime control Host-local HTTP bridge must bind 127.0.0.1"
        }
        guard hostLoopbackPort > 0 else {
            return "Guest Runtime control Host-local HTTP bridge hostLoopbackPort must be positive"
        }
        guard guestVirtioSocketPort > 0, guestVirtioSocketPort <= UInt32(UInt16.max) else {
            return "Guest Runtime control Host-local HTTP bridge guestVirtioSocketPort must be between 1 and 65535"
        }
        return nil
    }
}

// GuestProductReleaseManagerHostLocalHTTPBridgeConfiguration names C59's
// delivery boundary independently from C37 Guest Runtime control. Its HTTP
// transport shape is identical, but its lifecycle is deliberately not: C59
// remains reachable while a release restart replaces Guest Runtime.
public struct GuestProductReleaseManagerHostLocalHTTPBridgeConfiguration: Codable, Equatable, Sendable {
    public let hostLoopbackAddress: String
    public let hostLoopbackPort: UInt16
    public let guestVirtioSocketPort: UInt32

    public init(
        hostLoopbackAddress: String,
        hostLoopbackPort: UInt16,
        guestVirtioSocketPort: UInt32
    ) {
        self.hostLoopbackAddress = hostLoopbackAddress
        self.hostLoopbackPort = hostLoopbackPort
        self.guestVirtioSocketPort = guestVirtioSocketPort
    }

    fileprivate var validationMessage: String? {
        guard hostLoopbackAddress == "127.0.0.1" else {
            return "Guest Product Release Manager control Host-local HTTP bridge must bind 127.0.0.1"
        }
        guard hostLoopbackPort > 0 else {
            return "Guest Product Release Manager control Host-local HTTP bridge hostLoopbackPort must be positive"
        }
        guard guestVirtioSocketPort > 0, guestVirtioSocketPort <= UInt32(UInt16.max) else {
            return "Guest Product Release Manager control Host-local HTTP bridge guestVirtioSocketPort must be between 1 and 65535"
        }
        return nil
    }
}

// GuestBundledUpstreamImageSetManagerHostLocalHTTPBridgeConfiguration names
// C64's optional Host-local control transport. It remains separate from C59:
// a Guest Product code restart must not own or disguise container image state.
public struct GuestBundledUpstreamImageSetManagerHostLocalHTTPBridgeConfiguration: Codable, Equatable, Sendable {
    public let hostLoopbackAddress: String
    public let hostLoopbackPort: UInt16
    public let guestVirtioSocketPort: UInt32

    public init(hostLoopbackAddress: String, hostLoopbackPort: UInt16, guestVirtioSocketPort: UInt32) {
        self.hostLoopbackAddress = hostLoopbackAddress
        self.hostLoopbackPort = hostLoopbackPort
        self.guestVirtioSocketPort = guestVirtioSocketPort
    }

    fileprivate var validationMessage: String? {
        guard hostLoopbackAddress == "127.0.0.1" else { return "Guest Bundled Upstream Image-set Manager control Host-local HTTP bridge must bind 127.0.0.1" }
        guard hostLoopbackPort > 0 else { return "Guest Bundled Upstream Image-set Manager control Host-local HTTP bridge hostLoopbackPort must be positive" }
        guard guestVirtioSocketPort > 0, guestVirtioSocketPort <= UInt32(UInt16.max) else { return "Guest Bundled Upstream Image-set Manager control Host-local HTTP bridge guestVirtioSocketPort must be between 1 and 65535" }
        return nil
    }
}

// GuestPublicServiceHostLocalHTTPBridgeConfiguration is one C32-declared
// Host-local endpoint for a C36 public route. The name carries route identity
// because a transport port alone cannot explain which public capability it
// exposes. C37 owns the matching Guest-loopback target.
public struct GuestPublicServiceHostLocalHTTPBridgeConfiguration: Codable, Equatable, Sendable {
    public let routeId: String
    public let hostLoopbackAddress: String
    public let hostLoopbackPort: UInt16
    public let guestVirtioSocketPort: UInt32

    public init(
        routeId: String,
        hostLoopbackAddress: String,
        hostLoopbackPort: UInt16,
        guestVirtioSocketPort: UInt32
    ) {
        self.routeId = routeId
        self.hostLoopbackAddress = hostLoopbackAddress
        self.hostLoopbackPort = hostLoopbackPort
        self.guestVirtioSocketPort = guestVirtioSocketPort
    }

    fileprivate var validationMessage: String? {
        guard isDeploymentIdentifier(routeId) else {
            return "Guest public service Host-local HTTP bridge routeId is invalid"
        }
        guard hostLoopbackAddress == "127.0.0.1" else {
            return "Guest public service Host-local HTTP bridge must bind 127.0.0.1"
        }
        guard hostLoopbackPort > 0 else {
            return "Guest public service Host-local HTTP bridge hostLoopbackPort must be positive"
        }
        guard guestVirtioSocketPort > 0, guestVirtioSocketPort <= UInt32(UInt16.max) else {
            return "Guest public service Host-local HTTP bridge guestVirtioSocketPort must be between 1 and 65535"
        }
        return nil
    }
}

public struct LinuxBootResources: Codable, Equatable, Sendable {
    public let kernelPath: String
    public let initialRamdiskPath: String?
    public let guestRootDevicePath: String
    public let commandLine: String

    public init(
        kernelPath: String,
        initialRamdiskPath: String?,
        guestRootDevicePath: String,
        commandLine: String
    ) {
        self.kernelPath = kernelPath
        self.initialRamdiskPath = initialRamdiskPath
        self.guestRootDevicePath = guestRootDevicePath
        self.commandLine = commandLine
    }

    fileprivate var validationMessage: String? {
        guard isSafeHostAbsolutePath(kernelPath) else {
            return "boot kernelPath must be an absolute path without traversal"
        }
        if let initialRamdiskPath, !isSafeHostAbsolutePath(initialRamdiskPath) {
            return "boot initialRamdiskPath must be an absolute path without traversal"
        }
        guard !commandLine.isEmpty, commandLine.count <= 4096 else {
            return "boot commandLine must contain between 1 and 4096 characters"
        }
        guard guestRootDevicePath == "/dev/vda1" else {
            return "boot guestRootDevicePath must name the C43 MBR root partition /dev/vda1"
        }
        guard commandLine.split(whereSeparator: { $0.isWhitespace }).contains("root=" + guestRootDevicePath) else {
            return "boot commandLine must explicitly name root=\(guestRootDevicePath)"
        }
        return nil
    }
}

public struct MacOSVirtualMachineStorageDevice: Codable, Equatable, Sendable {
    public let id: String
    public let role: String
    public let storageImageFormat: String
    public let guestVolumeFileSystem: String?
    public let diskImagePath: String
    public let readOnly: Bool
    public let attachmentIndex: Int

    public init(
        id: String,
        role: String,
        storageImageFormat: String,
        guestVolumeFileSystem: String?,
        diskImagePath: String,
        readOnly: Bool,
        attachmentIndex: Int
    ) {
        self.id = id
        self.role = role
        self.storageImageFormat = storageImageFormat
        self.guestVolumeFileSystem = guestVolumeFileSystem
        self.diskImagePath = diskImagePath
        self.readOnly = readOnly
        self.attachmentIndex = attachmentIndex
    }

    fileprivate var validationMessage: String? {
        guard isDeploymentIdentifier(id), isSafeHostAbsolutePath(diskImagePath) else {
            return "storage device id and absolute diskImagePath without traversal are required"
        }
        switch (id, role, storageImageFormat, guestVolumeFileSystem, readOnly, attachmentIndex) {
        case ("guest-root", "guest-root-storage", "raw", nil, false, 0),
             ("guest-product-bootstrap", "guest-product-bootstrap-volume", "raw", "iso9660", true, 1):
            return nil
        default:
            return "storage device must declare one supported Guest storage role, storage image format, Guest volume filesystem, and attachment intent"
        }
    }
}

public struct MacOSVirtualMachineNetworkDevice: Codable, Equatable, Sendable {
    public let attachment: String
    public let macAddress: String

    public init(attachment: String, macAddress: String) {
        self.attachment = attachment
        self.macAddress = macAddress
    }

    fileprivate var validationMessage: String? {
        guard attachment == "nat" else {
            return "network attachment must be nat"
        }
        guard VZMACAddress(string: macAddress) != nil, isUnicastMacAddress(macAddress) else {
            return "network macAddress must be a valid unicast MAC address"
        }
        return nil
    }
}

public enum MacOSVirtualMachineConfigurationError: LocalizedError {
    case unavailable(String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message), .invalid(let message):
            message
        }
    }
}

public enum MacOSVirtualMachineConfigurationLoader {
    public static func load(fromFile path: String) throws -> MacOSVirtualMachineConfigurationDocument {
        guard isSafeHostAbsolutePath(path) else {
            throw MacOSVirtualMachineConfigurationError.invalid("virtual machine configuration path must be absolute without traversal")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MacOSVirtualMachineConfigurationError.unavailable("virtual machine configuration file is missing")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw MacOSVirtualMachineConfigurationError.unavailable("virtual machine configuration file cannot be read")
        }
        let document: MacOSVirtualMachineConfigurationDocument
        do {
            let decoder = JSONDecoder()
            document = try decoder.decode(MacOSVirtualMachineConfigurationDocument.self, from: data)
        } catch {
            throw MacOSVirtualMachineConfigurationError.invalid("virtual machine configuration JSON is invalid")
        }
        if let message = document.validationMessage {
            throw MacOSVirtualMachineConfigurationError.invalid(message)
        }
        return document
    }
}

@available(macOS 13.0, *)
public enum MacOSVirtualMachineFactory {
    public static func makeController(document: MacOSVirtualMachineConfigurationDocument) throws -> AppleVirtualMachineController {
        if let message = document.validationMessage {
            throw MacOSVirtualMachineConfigurationError.invalid(message)
        }
        let configuration = VZVirtualMachineConfiguration()
        configuration.cpuCount = document.cpuCount
        configuration.memorySize = document.memoryBytes

        let bootLoader = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: document.boot.kernelPath))
        bootLoader.commandLine = document.boot.commandLine
        if let initialRamdiskPath = document.boot.initialRamdiskPath {
            bootLoader.initialRamdiskURL = URL(fileURLWithPath: initialRamdiskPath)
        }
        configuration.bootLoader = bootLoader

        configuration.storageDevices = try document.storageDevices.map { device in
            do {
                let attachment = try VZDiskImageStorageDeviceAttachment(
                    url: URL(fileURLWithPath: device.diskImagePath),
                    readOnly: device.readOnly
                )
                return VZVirtioBlockDeviceConfiguration(attachment: attachment)
            } catch {
                throw MacOSVirtualMachineConfigurationError.unavailable(
                    "configured \(device.id) \(device.role) storage attachment cannot be opened: \(error.localizedDescription)"
                )
            }
        }

        guard let macAddress = VZMACAddress(string: document.network.macAddress) else {
            throw MacOSVirtualMachineConfigurationError.invalid("network macAddress is invalid")
        }
        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        network.macAddress = macAddress
        configuration.networkDevices = [network]
        configuration.socketDevices = [VZVirtioSocketDeviceConfiguration()]

        let guestBootConsoleCaptureFileHandle: FileHandle
        do {
            guestBootConsoleCaptureFileHandle = try FileHandle(
                forWritingTo: URL(fileURLWithPath: document.guestBootConsoleCapture.capturePath)
            )
            try guestBootConsoleCaptureFileHandle.seekToEnd()
        } catch {
            throw MacOSVirtualMachineConfigurationError.unavailable(
                "configured Guest boot console capture cannot be opened: \(error.localizedDescription)"
            )
        }
        let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
        serialPort.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: nil,
            fileHandleForWriting: guestBootConsoleCaptureFileHandle
        )
        configuration.serialPorts = [serialPort]

        do {
            try configuration.validate()
            // VZVirtualMachine does not permit operations from arbitrary
            // queues. Naming and retaining its serial queue makes the Host
            // ownership boundary explicit for lifecycle and virtio-socket
            // operations alike.
            let guestRuntimeVirtualMachineOperationQueue = DispatchQueue(
                label: "com.tirosh.vitalserver.guest-runtime-virtual-machine-operation"
            )
            let virtualMachine = VZVirtualMachine(
                configuration: configuration,
                queue: guestRuntimeVirtualMachineOperationQueue
            )
            guard let guestRuntimeControlVirtioSocketDevice = virtualMachine.socketDevices.first as? VZVirtioSocketDevice else {
                throw MacOSVirtualMachineConfigurationError.unavailable(
                    "configured Guest Runtime control virtio socket device is unavailable"
                )
            }
            let guestPublicServiceHostLocalHTTPBridges = document.guestPublicServiceHostLocalHTTPBridges.map {
                GuestPublicServiceHostLocalHTTPBridge(
                    configuration: $0,
                    guestVirtioSocketDevice: guestRuntimeControlVirtioSocketDevice,
                    guestRuntimeVirtualMachineOperationQueue: guestRuntimeVirtualMachineOperationQueue
                )
            }
            let guestProductReleaseManagerHostLocalHTTPBridge = GuestProductReleaseManagerHostLocalHTTPBridge(
                configuration: document.guestProductReleaseManagerHostLocalHTTPBridge,
                guestVirtioSocketDevice: guestRuntimeControlVirtioSocketDevice,
                guestRuntimeVirtualMachineOperationQueue: guestRuntimeVirtualMachineOperationQueue
            )
            let guestBundledUpstreamImageSetManagerHostLocalHTTPBridge = document.guestBundledUpstreamImageSetManagerHostLocalHTTPBridge.map {
                GuestBundledUpstreamImageSetManagerHostLocalHTTPBridge(
                    configuration: $0,
                    guestVirtioSocketDevice: guestRuntimeControlVirtioSocketDevice,
                    guestRuntimeVirtualMachineOperationQueue: guestRuntimeVirtualMachineOperationQueue
                )
            }
            return AppleVirtualMachineController(
                virtualMachine: virtualMachine,
                guestRuntimeVirtualMachineOperationQueue: guestRuntimeVirtualMachineOperationQueue,
                guestRuntimeControlHostLocalHTTPBridge: GuestRuntimeControlHostLocalHTTPBridge(
                    configuration: document.guestRuntimeControlHostLocalHTTPBridge,
                    guestRuntimeControlVirtioSocketDevice: guestRuntimeControlVirtioSocketDevice,
                    guestRuntimeVirtualMachineOperationQueue: guestRuntimeVirtualMachineOperationQueue
                ),
                guestProductReleaseManagerHostLocalHTTPBridge: guestProductReleaseManagerHostLocalHTTPBridge,
                guestBundledUpstreamImageSetManagerHostLocalHTTPBridge: guestBundledUpstreamImageSetManagerHostLocalHTTPBridge,
                guestPublicServiceHostLocalHTTPBridges: guestPublicServiceHostLocalHTTPBridges,
                guestBootConsoleCaptureFileHandle: guestBootConsoleCaptureFileHandle
            )
        } catch {
            throw MacOSVirtualMachineConfigurationError.invalid(
                "virtual machine configuration is not accepted by Apple Virtualization: \(error.localizedDescription)"
            )
        }
    }
}

private func isDeploymentIdentifier(_ value: String) -> Bool {
    value.count <= 128
        && value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
}

private func isSafeHostAbsolutePath(_ path: String) -> Bool {
    guard path.hasPrefix("/"), !path.contains("\\") else {
        return false
    }
    return !path.split(separator: "/").contains("..")
}

private func isUnicastMacAddress(_ value: String) -> Bool {
    let octets = value.split(separator: ":")
    guard let firstOctet = octets.first, let number = UInt8(firstOctet, radix: 16) else {
        return false
    }
    return number & 1 == 0
}
