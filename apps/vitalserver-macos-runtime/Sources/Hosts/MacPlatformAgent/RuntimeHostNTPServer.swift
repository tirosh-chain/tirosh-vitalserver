import Domain
import Foundation
import Network

public struct RuntimeHostNTPServerConfiguration: Equatable, Sendable {
    public let bindAddress: String
    public let port: UInt16
    public let allowedClientAddress: String

    public init(
        bindAddress: String,
        port: UInt16 = 123,
        allowedClientAddress: String
    ) {
        self.bindAddress = bindAddress
        self.port = port
        self.allowedClientAddress = allowedClientAddress
    }
}

public enum RuntimeHostNTPServerState: Equatable, Sendable {
    case starting
    case ready(address: String, port: UInt16)
    case failed(String)
    case stopped
}

protocol RuntimeHostNTPServing: AnyObject {
    func start() throws
    func stop()
}

public final class RuntimeHostNTPServer: RuntimeHostNTPServing, @unchecked Sendable {
    private let configuration: RuntimeHostNTPServerConfiguration
    private let now: @Sendable () -> Date
    private let stateHandler: (@Sendable (RuntimeHostNTPServerState) -> Void)?
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var referenceAt: Date?

    public init(
        configuration: RuntimeHostNTPServerConfiguration,
        now: @escaping @Sendable () -> Date = Date.init,
        stateHandler: (@Sendable (RuntimeHostNTPServerState) -> Void)? = nil,
        queue: DispatchQueue = DispatchQueue(label: "tirosh.runtime.host-ntp")
    ) {
        self.configuration = configuration
        self.now = now
        self.stateHandler = stateHandler
        self.queue = queue
        self.queue.setSpecific(key: queueKey, value: ())
    }

    public var activePort: UInt16? {
        syncOnQueue {
            listener?.port?.rawValue
        }
    }

    public func start() throws {
        guard listener == nil else {
            return
        }
        let port: NWEndpoint.Port
        if configuration.port == 0 {
            port = .any
        } else {
            guard let selected = NWEndpoint.Port(rawValue: configuration.port) else {
                throw RuntimeHostNTPServerError.invalidPort(configuration.port)
            }
            port = selected
        }
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(configuration.bindAddress),
            port: port
        )
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else {
                return
            }
            switch state {
            case .ready:
                let activePort = listener?.port?.rawValue ?? self.configuration.port
                self.stateHandler?(.ready(
                    address: self.configuration.bindAddress,
                    port: activePort
                ))
            case .failed(let error):
                self.stop()
                self.stateHandler?(.failed(String(describing: error)))
            case .cancelled:
                self.stateHandler?(.stopped)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        syncOnQueue {
            referenceAt = now()
            self.listener = listener
        }
        stateHandler?(.starting)
        listener.start(queue: queue)
    }

    public func stop() {
        syncOnQueue {
            listener?.cancel()
            listener = nil
            for connection in connections.values {
                connection.cancel()
            }
            connections.removeAll()
            referenceAt = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        guard remoteAddress(connection.endpoint) == configuration.allowedClientAddress else {
            connection.cancel()
            return
        }
        syncOnQueue {
            connections[ObjectIdentifier(connection)] = connection
        }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else {
                return
            }
            if case .failed = state {
                self.remove(connection)
            } else if case .cancelled = state {
                self.remove(connection)
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection else {
                return
            }
            guard let data else {
                self.remove(connection)
                return
            }
            let receivedAt = self.now()
            guard let referenceAt = self.syncOnQueue({ self.referenceAt }),
                  let bytes = RuntimeNTPPacketPolicy.response(
                    to: [UInt8](data),
                    receivedAt: receivedAt,
                    transmittedAt: self.now(),
                    referenceAt: referenceAt
                  ) else {
                self.receive(on: connection)
                return
            }
            connection.send(
                content: Data(bytes),
                completion: .contentProcessed { [weak self, weak connection] error in
                    guard let self, let connection else {
                        return
                    }
                    if error == nil {
                        self.receive(on: connection)
                    } else {
                        self.remove(connection)
                    }
                }
            )
        }
    }

    private func remove(_ connection: NWConnection) {
        _ = syncOnQueue {
            connections.removeValue(forKey: ObjectIdentifier(connection))
        }
        connection.cancel()
    }

    private func remoteAddress(_ endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else {
            return nil
        }
        return String(describing: host)
    }

    private func syncOnQueue<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return operation()
        }
        return queue.sync(execute: operation)
    }
}

public enum RuntimeHostNTPServerError: Error, Equatable {
    case invalidPort(UInt16)
}
