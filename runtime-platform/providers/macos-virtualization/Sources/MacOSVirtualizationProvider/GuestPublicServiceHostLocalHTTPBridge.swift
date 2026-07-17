import Foundation
@preconcurrency import Virtualization

// GuestPublicServiceHostLocalHTTPBridge is the C32 data-plane adapter for one
// named C36 public route. It owns no route policy: C36 owns public matching,
// C32 owns the Host listener declaration, and C37 owns the Guest-loopback
// target declaration that uses the matching virtio-socket port.
@available(macOS 13.0, *)
public final class GuestPublicServiceHostLocalHTTPBridge: @unchecked Sendable {
    public let routeID: String
    private let byteRelay: HostLocalHTTPToGuestVirtioSocketByteRelay

    public init(
        configuration: GuestPublicServiceHostLocalHTTPBridgeConfiguration,
        guestVirtioSocketDevice: VZVirtioSocketDevice,
        guestRuntimeVirtualMachineOperationQueue: DispatchQueue
    ) {
        routeID = configuration.routeId
        byteRelay = HostLocalHTTPToGuestVirtioSocketByteRelay(
            boundaryDescription: "Guest public service route \(configuration.routeId)",
            hostLoopbackAddress: configuration.hostLoopbackAddress,
            hostLoopbackPort: configuration.hostLoopbackPort,
            guestVirtioSocketPort: configuration.guestVirtioSocketPort,
            guestVirtioSocketDevice: guestVirtioSocketDevice,
            guestRuntimeVirtualMachineOperationQueue: guestRuntimeVirtualMachineOperationQueue
        )
    }

    public func start() throws {
        try byteRelay.start()
    }

    public func stop() {
        byteRelay.stop()
    }
}
