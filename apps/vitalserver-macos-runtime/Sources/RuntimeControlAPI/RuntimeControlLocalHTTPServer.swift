import Foundation
import Network

public enum RuntimeControlLocalHTTPServerError: Error, Equatable {
    case invalidPort(UInt16)
    case listenerUnavailable
}

public struct RuntimeControlLocalHTTPServerConfiguration: Equatable, Sendable {
    public let host: String
    public let port: UInt16

    public init(host: String = "127.0.0.1", port: UInt16) {
        self.host = host
        self.port = port
    }
}

public final class RuntimeControlLocalHTTPServer: @unchecked Sendable {
    private let configuration: RuntimeControlLocalHTTPServerConfiguration
    private let router: RuntimeControlAPIRouter
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    public var activePort: UInt16? {
        listener?.port?.rawValue
    }

    @MainActor
    public init(
        configuration: RuntimeControlLocalHTTPServerConfiguration,
        router: RuntimeControlAPIRouter,
        queue: DispatchQueue = DispatchQueue(label: "tirosh.runtime-control.local-http")
    ) {
        self.configuration = configuration
        self.router = router
        self.queue = queue
    }

    public func start() throws {
        let port: NWEndpoint.Port
        if configuration.port == 0 {
            port = .any
        } else {
            guard let configuredPort = NWEndpoint.Port(rawValue: configuration.port) else {
                throw RuntimeControlLocalHTTPServerError.invalidPort(configuration.port)
            }
            port = configuredPort
        }

        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                self?.connections.removeValue(forKey: id)
            }
        }
        connection.start(queue: queue)
        receive(from: connection)
    }

    private func receive(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let data, !data.isEmpty {
                self.respond(to: data, on: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(from: connection)
        }
    }

    private func respond(to data: Data, on connection: NWConnection) {
        let request: RuntimeControlHTTPRequest
        do {
            request = try RuntimeControlHTTPWireCodec.decodeRequest(data)
        } catch {
            send(RuntimeControlHTTPWireCodec.badRequestResponse(message: "Invalid HTTP request."), on: connection)
            return
        }

        Task { @MainActor [router] in
            let response = await router.route(request)
            let encoded = RuntimeControlHTTPWireCodec.encodeResponse(response)
            connection.send(content: encoded, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func send(_ response: RuntimeControlHTTPResponse, on connection: NWConnection) {
        let encoded = RuntimeControlHTTPWireCodec.encodeResponse(response)
        connection.send(content: encoded, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
