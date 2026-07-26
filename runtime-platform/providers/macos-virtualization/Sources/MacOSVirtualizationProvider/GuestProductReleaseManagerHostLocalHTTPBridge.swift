import Foundation
@preconcurrency import Virtualization

// GuestProductReleaseManagerHostLocalHTTPBridge is the C32 delivery-control
// adapter. It has a separate semantic type from Guest Runtime control because
// a product release may restart Guest Runtime while this C59 request remains
// connected. The lower byte relay intentionally knows neither operation state
// nor release filesystem details.
@available(macOS 13.0, *)
public final class GuestProductReleaseManagerHostLocalHTTPBridge: @unchecked Sendable {
    private let byteRelay: HostLocalHTTPToGuestVirtioSocketByteRelay

    public init(
        configuration: GuestProductReleaseManagerHostLocalHTTPBridgeConfiguration,
        guestVirtioSocketDevice: VZVirtioSocketDevice,
        guestRuntimeVirtualMachineOperationQueue: DispatchQueue
    ) {
        byteRelay = HostLocalHTTPToGuestVirtioSocketByteRelay(
            boundaryDescription: "Guest Product Release Manager control",
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
