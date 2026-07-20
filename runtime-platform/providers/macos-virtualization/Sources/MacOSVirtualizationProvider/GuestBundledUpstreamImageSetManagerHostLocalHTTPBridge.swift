import Foundation
@preconcurrency import Virtualization

// GuestBundledUpstreamImageSetManagerHostLocalHTTPBridge is C32's byte-only
// control adapter for C64. It deliberately has no container engine, C59, or
// image-set state knowledge.
@available(macOS 13.0, *)
public final class GuestBundledUpstreamImageSetManagerHostLocalHTTPBridge: @unchecked Sendable {
    private let byteRelay: HostLocalHTTPToGuestVirtioSocketByteRelay

    public init(configuration: GuestBundledUpstreamImageSetManagerHostLocalHTTPBridgeConfiguration, guestVirtioSocketDevice: VZVirtioSocketDevice, guestRuntimeVirtualMachineOperationQueue: DispatchQueue) {
        byteRelay = HostLocalHTTPToGuestVirtioSocketByteRelay(
            boundaryDescription: "Guest Bundled Upstream Image-set Manager control",
            hostLoopbackAddress: configuration.hostLoopbackAddress,
            hostLoopbackPort: configuration.hostLoopbackPort,
            guestVirtioSocketPort: configuration.guestVirtioSocketPort,
            guestVirtioSocketDevice: guestVirtioSocketDevice,
            guestRuntimeVirtualMachineOperationQueue: guestRuntimeVirtualMachineOperationQueue
        )
    }
    public func start() throws { try byteRelay.start() }
    public func stop() { byteRelay.stop() }
}
