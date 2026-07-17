import Darwin
import Foundation
@preconcurrency import Virtualization

// HostLocalHTTPToGuestVirtioSocketByteRelaySocketResultPolicy preserves
// the distinction between an established nonblocking transport that is waiting
// for bytes and one that has reached a terminal socket error. It is adapter
// policy, not a Guest Runtime readiness or lifecycle decision.
enum HostLocalHTTPToGuestVirtioSocketByteRelaySocketResultPolicy {
    static func preservesEstablishedConnection(forSocketError errorNumber: Int32) -> Bool {
        errorNumber == EINTR || errorNumber == EAGAIN || errorNumber == EWOULDBLOCK
    }
}

// HostLocalHTTPToGuestVirtioSocketByteRelay is the common technical adapter
// behind C32 Host-local endpoints. Its callers own whether the bytes represent
// the Runtime control contract or a C36 public-service route. It owns only
// Host-loopback TCP acceptance and VZ virtio-socket byte forwarding; it never
// interprets HTTP or creates service, readiness, or lifecycle state.
@available(macOS 13.0, *)
final class HostLocalHTTPToGuestVirtioSocketByteRelay: @unchecked Sendable {
    private let boundaryDescription: String
    private let hostLoopbackAddress: String
    private let hostLoopbackPort: UInt16
    private let guestVirtioSocketPort: UInt32
    private let guestVirtioSocketDevice: VZVirtioSocketDevice
    // The VZVirtualMachine is created with this explicitly named serial queue.
    // Apple requires every VZ operation, including socket connection creation,
    // to run on that queue. The Host listener queue must therefore never call
    // VZ APIs directly.
    private let guestRuntimeVirtualMachineOperationQueue: DispatchQueue
    private let synchronizationQueue: DispatchQueue
    private var listenerFileDescriptor: Int32 = -1
    private var listenerReadSource: DispatchSourceRead?
    private let activeConnectionRegistry = HostLocalHTTPToGuestVirtioSocketByteRelayConnectionRegistry()

    init(
        boundaryDescription: String,
        hostLoopbackAddress: String,
        hostLoopbackPort: UInt16,
        guestVirtioSocketPort: UInt32,
        guestVirtioSocketDevice: VZVirtioSocketDevice,
        guestRuntimeVirtualMachineOperationQueue: DispatchQueue
    ) {
        self.boundaryDescription = boundaryDescription
        self.hostLoopbackAddress = hostLoopbackAddress
        self.hostLoopbackPort = hostLoopbackPort
        self.guestVirtioSocketPort = guestVirtioSocketPort
        self.guestVirtioSocketDevice = guestVirtioSocketDevice
        self.guestRuntimeVirtualMachineOperationQueue = guestRuntimeVirtualMachineOperationQueue
        self.synchronizationQueue = DispatchQueue(label: "com.tirosh.vitalserver.host-local-http-to-guest-virtio-socket-byte-relay.\(hostLoopbackPort)")
    }

    deinit {
        stop()
    }

    // start binds only one C32-declared Host-loopback endpoint. The VM remains
    // the owner of the virtio device; this adapter owns no Guest lifecycle or
    // Guest service state.
    func start() throws {
        try synchronizationQueue.sync {
            guard listenerFileDescriptor == -1 else {
                return
            }
            let fileDescriptor = try makeHostLoopbackListenerFileDescriptor()
            let readSource = DispatchSource.makeReadSource(
                fileDescriptor: fileDescriptor,
                queue: synchronizationQueue
            )
            readSource.setEventHandler { [weak self] in
                self?.acceptHostLoopbackConnections()
            }
            readSource.setCancelHandler {
                Darwin.close(fileDescriptor)
            }
            listenerFileDescriptor = fileDescriptor
            listenerReadSource = readSource
            readSource.resume()
        }
    }

    // stop closes Host resources owned by this adapter. It deliberately does
    // not infer a Guest stop request or mutate Guest Runtime state.
    func stop() {
        synchronizationQueue.sync {
            listenerReadSource?.cancel()
            listenerReadSource = nil
            listenerFileDescriptor = -1
            let connections = activeConnectionRegistry.removeAll()
            connections.forEach { $0.close() }
        }
    }

    private func makeHostLoopbackListenerFileDescriptor() throws -> Int32 {
        let fileDescriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw MacOSVirtualMachineConfigurationError.unavailable(
                "\(boundaryDescription) Host-local HTTP bridge socket cannot be created: \(String(cString: strerror(errno)))"
            )
        }
        var reuseAddress: Int32 = 1
        guard setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            Darwin.close(fileDescriptor)
            throw MacOSVirtualMachineConfigurationError.unavailable(
                "\(boundaryDescription) Host-local HTTP bridge socket reuse cannot be configured: \(String(cString: strerror(errno)))"
            )
        }
        guard fcntl(fileDescriptor, F_SETFL, O_NONBLOCK) == 0 else {
            Darwin.close(fileDescriptor)
            throw MacOSVirtualMachineConfigurationError.unavailable(
                "\(boundaryDescription) Host-local HTTP bridge listener cannot be made nonblocking: \(String(cString: strerror(errno)))"
            )
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = hostLoopbackPort.bigEndian
        let conversionResult = "127.0.0.1".withCString { pointer in
            inet_pton(AF_INET, pointer, &address.sin_addr)
        }
        guard conversionResult == 1 else {
            Darwin.close(fileDescriptor)
            throw MacOSVirtualMachineConfigurationError.invalid(
                "\(boundaryDescription) Host-local HTTP bridge loopback address is invalid"
            )
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(fileDescriptor)
            throw MacOSVirtualMachineConfigurationError.unavailable(
                "\(boundaryDescription) Host-local HTTP bridge cannot bind \(hostLoopbackAddress):\(hostLoopbackPort): \(reason)"
            )
        }
        guard Darwin.listen(fileDescriptor, SOMAXCONN) == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(fileDescriptor)
            throw MacOSVirtualMachineConfigurationError.unavailable(
                "\(boundaryDescription) Host-local HTTP bridge cannot listen: \(reason)"
            )
        }
        return fileDescriptor
    }

    private func acceptHostLoopbackConnections() {
        while true {
            let acceptedFileDescriptor = Darwin.accept(listenerFileDescriptor, nil, nil)
            guard acceptedFileDescriptor >= 0 else {
                guard errno == EINTR else {
                    return
                }
                continue
            }
            connectAcceptedHostHTTPClientToGuestRuntime(acceptedFileDescriptor: acceptedFileDescriptor)
        }
    }

    private func connectAcceptedHostHTTPClientToGuestRuntime(acceptedFileDescriptor: Int32) {
        guestRuntimeVirtualMachineOperationQueue.async { [weak self] in
            guard let self else {
                Darwin.close(acceptedFileDescriptor)
                return
            }
            self.guestVirtioSocketDevice.connect(toPort: self.guestVirtioSocketPort) { [weak self] result in
                guard let self else {
                    Darwin.close(acceptedFileDescriptor)
                    return
                }
                switch result {
                case .success(let guestConnection):
                    // VZ invokes this completion on its declared operation
                    // queue. Wrap the non-Sendable VZ resource before handing
                    // it to the Host bridge queue; the wrapper represents one
                    // explicit established Guest virtio-socket connection.
                    let guestConnectionReference = GuestVirtioSocketConnectionReference(
                        guestVirtioSocketConnection: guestConnection
                    )
                    self.synchronizationQueue.async {
                        let identifier = UUID()
                        let connection = HostLocalHTTPToGuestVirtioSocketByteRelayConnection(
                            hostHTTPClientFileDescriptor: acceptedFileDescriptor,
                            guestVirtioSocketConnection: guestConnectionReference.guestVirtioSocketConnection,
                            didClose: { [activeConnectionRegistry = self.activeConnectionRegistry] in
                                activeConnectionRegistry.remove(identifier: identifier)
                            }
                        )
                        self.activeConnectionRegistry.retain(connection, identifier: identifier)
                        connection.startByteForwarding()
                    }
                case .failure:
                    // No synthetic HTTP response: the Host Agent owns the
                    // control transport observation and must see this as an
                    // unavailable connection rather than a guessed success.
                    Darwin.close(acceptedFileDescriptor)
                }
            }
        }
    }
}

// VZVirtioSocketConnection is an Apple framework resource whose calls are
// serialized by the established connection's own lifecycle. This reference
// is the explicit bridge-boundary handoff from the VZ operation queue to the
// Host byte-forwarding queue.
@available(macOS 13.0, *)
private final class GuestVirtioSocketConnectionReference: @unchecked Sendable {
    let guestVirtioSocketConnection: VZVirtioSocketConnection

    init(guestVirtioSocketConnection: VZVirtioSocketConnection) {
        self.guestVirtioSocketConnection = guestVirtioSocketConnection
    }
}

// This registry owns only active byte-forwarding references. Its lock keeps
// the bridge's VZ callback and relay threads from manufacturing a lifecycle
// state or racing Host resource cleanup.
@available(macOS 13.0, *)
private final class HostLocalHTTPToGuestVirtioSocketByteRelayConnectionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [UUID: HostLocalHTTPToGuestVirtioSocketByteRelayConnection] = [:]

    func retain(_ connection: HostLocalHTTPToGuestVirtioSocketByteRelayConnection, identifier: UUID) {
        lock.lock()
        connections[identifier] = connection
        lock.unlock()
    }

    func remove(identifier: UUID) {
        lock.lock()
        connections.removeValue(forKey: identifier)
        lock.unlock()
    }

    func removeAll() -> [HostLocalHTTPToGuestVirtioSocketByteRelayConnection] {
        lock.lock()
        let activeConnections = Array(connections.values)
        connections.removeAll()
        lock.unlock()
        return activeConnections
    }
}

@available(macOS 13.0, *)
private final class HostLocalHTTPToGuestVirtioSocketByteRelayConnection: @unchecked Sendable {
    private let hostHTTPClientFileDescriptor: Int32
    private let guestVirtioSocketConnection: VZVirtioSocketConnection
    private let didClose: () -> Void
    private let closureLock = NSLock()
    private var isClosed = false

    init(
        hostHTTPClientFileDescriptor: Int32,
        guestVirtioSocketConnection: VZVirtioSocketConnection,
        didClose: @escaping () -> Void
    ) {
        self.hostHTTPClientFileDescriptor = hostHTTPClientFileDescriptor
        self.guestVirtioSocketConnection = guestVirtioSocketConnection
        self.didClose = didClose
    }

    func startByteForwarding() {
        let guestFileDescriptor = guestVirtioSocketConnection.fileDescriptor
        guard guestFileDescriptor >= 0 else {
            close()
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.forwardBytes(
                from: self?.hostHTTPClientFileDescriptor ?? -1,
                to: guestFileDescriptor
            )
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.forwardBytes(
                from: guestFileDescriptor,
                to: self?.hostHTTPClientFileDescriptor ?? -1
            )
        }
    }

    func close() {
        closureLock.lock()
        guard !isClosed else {
            closureLock.unlock()
            return
        }
        isClosed = true
        closureLock.unlock()
        Darwin.shutdown(hostHTTPClientFileDescriptor, SHUT_RDWR)
        Darwin.close(hostHTTPClientFileDescriptor)
        guestVirtioSocketConnection.close()
        didClose()
    }

    private func forwardBytes(from sourceFileDescriptor: Int32, to destinationFileDescriptor: Int32) {
        guard sourceFileDescriptor >= 0, destinationFileDescriptor >= 0 else {
            close()
            return
        }
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(sourceFileDescriptor, bytes.baseAddress, bytes.count)
            }
            if bytesRead == 0 {
                close()
                return
            }
            if bytesRead < 0 {
                guard HostLocalHTTPToGuestVirtioSocketByteRelaySocketResultPolicy.preservesEstablishedConnection(forSocketError: errno) else {
                    close()
                    return
                }
                // Both the accepted Host socket and VZ's connection file
                // descriptor may be nonblocking. "Would block" means that
                // this direction has no bytes yet, not that this declared
                // Host-to-Guest transport has failed. Keep the established connection
                // alive until it reaches a terminal socket result.
                usleep(1_000)
                continue
            }
            var written = 0
            while written < bytesRead {
                let bytesWritten = buffer.withUnsafeBytes { bytes in
                    Darwin.write(
                        destinationFileDescriptor,
                        bytes.baseAddress!.advanced(by: written),
                        bytesRead - written
                    )
                }
                if bytesWritten > 0 {
                    written += bytesWritten
                    continue
                }
                if bytesWritten < 0, HostLocalHTTPToGuestVirtioSocketByteRelaySocketResultPolicy.preservesEstablishedConnection(forSocketError: errno) {
                    usleep(1_000)
                    continue
                }
                close()
                return
            }
        }
    }

}

// GuestRuntimeControlHostLocalHTTPBridge is the C32 control-contract adapter.
// The semantic name deliberately distinguishes it from public data-plane
// routes even though both use the same lower-level byte relay.
@available(macOS 13.0, *)
public final class GuestRuntimeControlHostLocalHTTPBridge: @unchecked Sendable {
    private let byteRelay: HostLocalHTTPToGuestVirtioSocketByteRelay

    public init(
        configuration: GuestRuntimeControlHostLocalHTTPBridgeConfiguration,
        guestRuntimeControlVirtioSocketDevice: VZVirtioSocketDevice,
        guestRuntimeVirtualMachineOperationQueue: DispatchQueue
    ) {
        byteRelay = HostLocalHTTPToGuestVirtioSocketByteRelay(
            boundaryDescription: "Guest Runtime control",
            hostLoopbackAddress: configuration.hostLoopbackAddress,
            hostLoopbackPort: configuration.hostLoopbackPort,
            guestVirtioSocketPort: configuration.guestVirtioSocketPort,
            guestVirtioSocketDevice: guestRuntimeControlVirtioSocketDevice,
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
