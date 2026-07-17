import Testing
@testable import MacOSVirtualizationProvider

private func configuredGuestRuntimeDiskProvisioning() -> GuestRuntimeDiskProvisioning {
    GuestRuntimeDiskProvisioning(
        releaseArtifactManifestPath: "/Library/Application Support/VitalServerRuntimePlatform/release/macos-guest-artifact-manifest.json",
        releaseArtifactPath: "/Library/Application Support/VitalServerRuntimePlatform/release/guest-root.raw",
        runtimeDiskImagePath: "/Library/Application Support/VitalServerRuntimePlatform/data/vm/guest-root.raw",
        provisioningReceiptPath: "/Library/Application Support/VitalServerRuntimePlatform/data/vm/guest-root-provisioning-receipt.json",
        existingRuntimeDiskPolicy: "retain-when-receipt-matches-release-artifact"
    )
}

private func configuredGuest() -> MacOSVirtualMachineConfigurationDocument {
    MacOSVirtualMachineConfigurationDocument(
        schemaVersion: "v1",
        machineId: "vitalserver-guest",
        cpuCount: 4,
        memoryBytes: 4 * 1024 * 1024 * 1024,
        boot: LinuxBootResources(
            kernelPath: "/Library/Application Support/VitalServerRuntimePlatform/guest/vmlinuz",
            initialRamdiskPath: "/Library/Application Support/VitalServerRuntimePlatform/guest/initrd.img",
            guestRootDevicePath: "/dev/vda1",
            commandLine: "console=hvc0 root=/dev/vda1"
        ),
        guestBootConsoleCapture: GuestBootConsoleCapture(
            capturePath: "/var/lib/vitalserver/data/guest-boot-console.log",
            writeMode: "append"
        ),
        guestRuntimeDiskProvisioning: configuredGuestRuntimeDiskProvisioning(),
        guestRuntimeControlHostLocalHTTPBridge: GuestRuntimeControlHostLocalHTTPBridgeConfiguration(
            hostLoopbackAddress: "127.0.0.1",
            hostLoopbackPort: 18443,
            guestVirtioSocketPort: 18443
        ),
        guestPublicServiceHostLocalHTTPBridges: [
            GuestPublicServiceHostLocalHTTPBridgeConfiguration(
                routeId: "recorder-gateway",
                hostLoopbackAddress: "127.0.0.1",
                hostLoopbackPort: 18090,
                guestVirtioSocketPort: 18090
            ),
            GuestPublicServiceHostLocalHTTPBridgeConfiguration(
                routeId: "vitalserver-browser",
                hostLoopbackAddress: "127.0.0.1",
                hostLoopbackPort: 18088,
                guestVirtioSocketPort: 18088
            ),
        ],
        storageDevices: [
            MacOSVirtualMachineStorageDevice(
                id: "guest-root",
                role: "guest-root-storage",
                storageImageFormat: "raw",
                guestVolumeFileSystem: nil,
                diskImagePath: "/Library/Application Support/VitalServerRuntimePlatform/data/vm/guest-root.raw",
                readOnly: false,
                attachmentIndex: 0
            ),
            MacOSVirtualMachineStorageDevice(
                id: "guest-product-bootstrap",
                role: "guest-product-bootstrap-volume",
                storageImageFormat: "raw",
                guestVolumeFileSystem: "iso9660",
                diskImagePath: "/Library/Application Support/VitalServerRuntimePlatform/guest/bootstrap.raw",
                readOnly: true,
                attachmentIndex: 1
            )
        ],
        network: MacOSVirtualMachineNetworkDevice(attachment: "nat", macAddress: "02:00:00:00:00:01")
    )
}

@Test("configured macOS Guest contract requires explicit resources")
func configuredGuestContractIsExplicit() {
    #expect(configuredGuest().validationMessage == nil)
}

@Test("configured macOS Guest contract keeps public route identity and transport ports distinct")
func configuredGuestContractRejectsAmbiguousPublicServiceBridge() {
    let configured = configuredGuest()
    let duplicateRoute = MacOSVirtualMachineConfigurationDocument(
        schemaVersion: configured.schemaVersion,
        machineId: configured.machineId,
        cpuCount: configured.cpuCount,
        memoryBytes: configured.memoryBytes,
        boot: configured.boot,
        guestBootConsoleCapture: configured.guestBootConsoleCapture,
        guestRuntimeDiskProvisioning: configured.guestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: configured.guestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: [
            configured.guestPublicServiceHostLocalHTTPBridges[0],
            GuestPublicServiceHostLocalHTTPBridgeConfiguration(
                routeId: "recorder-gateway",
                hostLoopbackAddress: "127.0.0.1",
                hostLoopbackPort: 18088,
                guestVirtioSocketPort: 18088
            ),
        ],
        storageDevices: configured.storageDevices,
        network: configured.network
    )
    #expect(duplicateRoute.validationMessage == "Guest public service Host-local HTTP bridge routeId values must be unique")
}

@Test("C32 public-service bridges retain route identity and cannot share control endpoints")
func configuredGuestContractRejectsAmbiguousPublicServiceBridgeDeclarations() {
    let configured = configuredGuest()
    let controlPortCollision = MacOSVirtualMachineConfigurationDocument(
        schemaVersion: configured.schemaVersion,
        machineId: configured.machineId,
        cpuCount: configured.cpuCount,
        memoryBytes: configured.memoryBytes,
        boot: configured.boot,
        guestBootConsoleCapture: configured.guestBootConsoleCapture,
        guestRuntimeDiskProvisioning: configured.guestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: configured.guestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: [
            GuestPublicServiceHostLocalHTTPBridgeConfiguration(
                routeId: "recorder-gateway",
                hostLoopbackAddress: "127.0.0.1",
                hostLoopbackPort: configured.guestRuntimeControlHostLocalHTTPBridge.hostLoopbackPort,
                guestVirtioSocketPort: 18090
            ),
        ],
        storageDevices: configured.storageDevices,
        network: configured.network
    )
    #expect(
        controlPortCollision.validationMessage
            == "Guest public service Host-local HTTP bridge hostLoopbackPort cannot reuse another Host listener"
    )

    let missingPublicServiceBridge = MacOSVirtualMachineConfigurationDocument(
        schemaVersion: configured.schemaVersion,
        machineId: configured.machineId,
        cpuCount: configured.cpuCount,
        memoryBytes: configured.memoryBytes,
        boot: configured.boot,
        guestBootConsoleCapture: configured.guestBootConsoleCapture,
        guestRuntimeDiskProvisioning: configured.guestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: configured.guestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: [],
        storageDevices: configured.storageDevices,
        network: configured.network
    )
    #expect(
        missingPublicServiceBridge.validationMessage
            == "at least one Guest public service Host-local HTTP bridge is required"
    )
}

@Test("configured macOS Guest contract rejects traversal and implicit network mode")
func configuredGuestContractRejectsUnsafeValues() {
    let unsafeBoot = MacOSVirtualMachineConfigurationDocument(
        schemaVersion: "v1",
        machineId: "vitalserver-guest",
        cpuCount: 1,
        memoryBytes: 1,
        boot: LinuxBootResources(kernelPath: "/Library/../tmp/vmlinuz", initialRamdiskPath: nil, guestRootDevicePath: "/dev/vda1", commandLine: "console=hvc0 root=/dev/vda1"),
        guestBootConsoleCapture: configuredGuest().guestBootConsoleCapture,
        guestRuntimeDiskProvisioning: configuredGuest().guestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: configuredGuest().guestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: configuredGuest().guestPublicServiceHostLocalHTTPBridges,
        storageDevices: configuredGuest().storageDevices,
        network: MacOSVirtualMachineNetworkDevice(attachment: "nat", macAddress: "02:00:00:00:00:01")
    )
    #expect(unsafeBoot.validationMessage != nil)

    let implicitNetwork = MacOSVirtualMachineConfigurationDocument(
        schemaVersion: "v1",
        machineId: "vitalserver-guest",
        cpuCount: 1,
        memoryBytes: 1,
        boot: LinuxBootResources(kernelPath: "/var/lib/vitalserver/vmlinuz", initialRamdiskPath: nil, guestRootDevicePath: "/dev/vda1", commandLine: "console=hvc0 root=/dev/vda1"),
        guestBootConsoleCapture: configuredGuest().guestBootConsoleCapture,
        guestRuntimeDiskProvisioning: configuredGuest().guestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: configuredGuest().guestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: configuredGuest().guestPublicServiceHostLocalHTTPBridges,
        storageDevices: configuredGuest().storageDevices,
        network: MacOSVirtualMachineNetworkDevice(attachment: "", macAddress: "02:00:00:00:00:01")
    )
    #expect(implicitNetwork.validationMessage != nil)
}

@Test("configured macOS Guest contract rejects multicast identity and overlong boot command")
func configuredGuestContractRejectsValuesOutsideC32() {
    let multicastGuest = MacOSVirtualMachineConfigurationDocument(
        schemaVersion: "v1",
        machineId: "vitalserver-guest",
        cpuCount: 1,
        memoryBytes: 1,
        boot: LinuxBootResources(kernelPath: "/var/lib/vitalserver/vmlinuz", initialRamdiskPath: nil, guestRootDevicePath: "/dev/vda1", commandLine: "console=hvc0 root=/dev/vda1"),
        guestBootConsoleCapture: configuredGuest().guestBootConsoleCapture,
        guestRuntimeDiskProvisioning: configuredGuest().guestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: configuredGuest().guestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: configuredGuest().guestPublicServiceHostLocalHTTPBridges,
        storageDevices: configuredGuest().storageDevices,
        network: MacOSVirtualMachineNetworkDevice(attachment: "nat", macAddress: "01:16:3e:00:00:01")
    )
    #expect(multicastGuest.validationMessage == "network macAddress must be a valid unicast MAC address")

    var overlongGuest = configuredGuest()
    overlongGuest = MacOSVirtualMachineConfigurationDocument(
        schemaVersion: overlongGuest.schemaVersion,
        machineId: overlongGuest.machineId,
        cpuCount: overlongGuest.cpuCount,
        memoryBytes: overlongGuest.memoryBytes,
        boot: LinuxBootResources(
            kernelPath: overlongGuest.boot.kernelPath,
            initialRamdiskPath: overlongGuest.boot.initialRamdiskPath,
            guestRootDevicePath: overlongGuest.boot.guestRootDevicePath,
            commandLine: String(repeating: "x", count: 4097)
        ),
        guestBootConsoleCapture: overlongGuest.guestBootConsoleCapture,
        guestRuntimeDiskProvisioning: overlongGuest.guestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: overlongGuest.guestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: overlongGuest.guestPublicServiceHostLocalHTTPBridges,
        storageDevices: overlongGuest.storageDevices,
        network: overlongGuest.network
    )
    #expect(overlongGuest.validationMessage == "boot commandLine must contain between 1 and 4096 characters")
}

@Test("configured macOS Guest contract keeps C43 root partition and kernel boot argument explicit")
func configuredGuestContractRejectsImplicitOrWrongRootPartition() {
    let configured = configuredGuest()
    let wrongRootPartition = MacOSVirtualMachineConfigurationDocument(
        schemaVersion: configured.schemaVersion,
        machineId: configured.machineId,
        cpuCount: configured.cpuCount,
        memoryBytes: configured.memoryBytes,
        boot: LinuxBootResources(
            kernelPath: configured.boot.kernelPath,
            initialRamdiskPath: configured.boot.initialRamdiskPath,
            guestRootDevicePath: "/dev/vda",
            commandLine: "console=hvc0 root=/dev/vda"
        ),
        guestBootConsoleCapture: configured.guestBootConsoleCapture,
        guestRuntimeDiskProvisioning: configured.guestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: configured.guestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: configured.guestPublicServiceHostLocalHTTPBridges,
        storageDevices: configured.storageDevices,
        network: configured.network
    )
    #expect(
        wrongRootPartition.validationMessage
            == "boot guestRootDevicePath must name the C43 MBR root partition /dev/vda1"
    )
}

@Test("configured macOS Guest contract requires an append-only Host-owned boot console capture")
func configuredGuestContractRejectsImplicitOrUnsafeBootConsoleCapture() {
    let configured = configuredGuest()
    let missingCapturePath = MacOSVirtualMachineConfigurationDocument(
        schemaVersion: configured.schemaVersion,
        machineId: configured.machineId,
        cpuCount: configured.cpuCount,
        memoryBytes: configured.memoryBytes,
        boot: configured.boot,
        guestBootConsoleCapture: GuestBootConsoleCapture(capturePath: "", writeMode: "append"),
        guestRuntimeDiskProvisioning: configured.guestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: configured.guestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: configured.guestPublicServiceHostLocalHTTPBridges,
        storageDevices: configured.storageDevices,
        network: configured.network
    )
    #expect(missingCapturePath.validationMessage == "Guest boot console capturePath must be an absolute path without traversal")

    let replacingCapture = MacOSVirtualMachineConfigurationDocument(
        schemaVersion: configured.schemaVersion,
        machineId: configured.machineId,
        cpuCount: configured.cpuCount,
        memoryBytes: configured.memoryBytes,
        boot: configured.boot,
        guestBootConsoleCapture: GuestBootConsoleCapture(
            capturePath: "/var/lib/vitalserver/data/guest-boot-console.log",
            writeMode: "truncate"
        ),
        guestRuntimeDiskProvisioning: configured.guestRuntimeDiskProvisioning,
        guestRuntimeControlHostLocalHTTPBridge: configured.guestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: configured.guestPublicServiceHostLocalHTTPBridges,
        storageDevices: configured.storageDevices,
        network: configured.network
    )
    #expect(replacingCapture.validationMessage == "Guest boot console writeMode must be append")
}
