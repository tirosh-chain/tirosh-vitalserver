import Foundation
import Network

public enum RuntimeControlLocalHTTPServerError: Error, Equatable {
    case invalidPort(UInt16)
    case listenerUnavailable
}

public struct RuntimeControlLocalHTTPServerConfiguration: Equatable, Sendable {
    public let port: UInt16
    public let servesDevConsole: Bool
    public let staticFileDirectory: URL?

    public init(
        port: UInt16,
        servesDevConsole: Bool = false,
        staticFileDirectory: URL? = nil
    ) {
        self.port = port
        self.servesDevConsole = servesDevConsole
        self.staticFileDirectory = staticFileDirectory
    }
}

public final class RuntimeControlLocalHTTPServer: @unchecked Sendable {
    private let configuration: RuntimeControlLocalHTTPServerConfiguration
    private let router: RuntimeControlAPIRouter
    private let testKitRouter: RuntimeTestKitAPIRouter?
    private let staticFileResponder: RuntimeControlStaticFileResponder?
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var requestBuffers: [ObjectIdentifier: Data] = [:]
    private var streamTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    public var activePort: UInt16? {
        syncOnQueue {
            listener?.port?.rawValue
        }
    }

    @MainActor
    public init(
        configuration: RuntimeControlLocalHTTPServerConfiguration,
        router: RuntimeControlAPIRouter,
        testKitRouter: RuntimeTestKitAPIRouter? = nil,
        queue: DispatchQueue = DispatchQueue(label: "tirosh.runtime-control.local-http")
    ) {
        self.configuration = configuration
        self.router = router
        self.testKitRouter = testKitRouter
        self.staticFileResponder = configuration.staticFileDirectory.map {
            RuntimeControlStaticFileResponder(rootDirectory: $0)
        }
        self.queue = queue
        self.queue.setSpecific(key: queueKey, value: ())
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
        syncOnQueue {
            self.listener = listener
        }
        listener.start(queue: queue)
    }

    public func stop() {
        syncOnQueue {
            stopLocked()
        }
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        for task in streamTasks.values {
            task.cancel()
        }
        connections.removeAll()
        requestBuffers.removeAll()
        streamTasks.removeAll()
    }

    private func syncOnQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return work()
        }
        return queue.sync(execute: work)
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                self?.connections.removeValue(forKey: id)
                self?.requestBuffers.removeValue(forKey: id)
                self?.streamTasks.removeValue(forKey: id)?.cancel()
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
                self.buffer(data, from: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(from: connection)
        }
    }

    private func buffer(_ data: Data, from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        var buffered = requestBuffers[id] ?? Data()
        buffered.append(data)

        do {
            guard try RuntimeControlHTTPWireCodec.requestIsComplete(buffered) else {
                requestBuffers[id] = buffered
                receive(from: connection)
                return
            }
            requestBuffers.removeValue(forKey: id)
            respond(to: buffered, on: connection)
        } catch {
            requestBuffers.removeValue(forKey: id)
            send(RuntimeControlHTTPWireCodec.badRequestResponse(message: "Invalid HTTP request."), on: connection)
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

        if request.method == .options {
            send(preflightResponse(for: request), on: connection)
            return
        }

        if configuration.servesDevConsole,
           let devConsoleResponse = RuntimeControlDevConsoleDocument.response(for: request) {
            send(corsResponse(devConsoleResponse, for: request), on: connection)
            return
        }

        if let staticResponse = staticFileResponder?.response(for: request) {
            send(corsResponse(staticResponse, for: request), on: connection)
            return
        }

        Task { @MainActor [router, testKitRouter] in
            if let testKitRouter,
               let result = await testKitRouter.routeResult(request) {
                self.send(result, for: request, on: connection)
                return
            }
            let result = await router.routeResult(request)
            self.send(result, for: request, on: connection)
        }
    }

    private func send(_ result: RuntimeControlHTTPRouteResult, for request: RuntimeControlHTTPRequest, on connection: NWConnection) {
        switch result {
        case .response(let response):
            queue.async {
                let encoded = RuntimeControlHTTPWireCodec.encodeResponse(self.corsResponse(response, for: request))
                connection.send(content: encoded, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        case .stream(let stream):
            queue.async {
                self.startStream(self.corsStream(stream, for: request), on: connection)
            }
        }
    }

    private func startStream(_ stream: RuntimeControlHTTPStreamResponse, on connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        let task = Task { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            let head = RuntimeControlHTTPWireCodec.encodeStreamHeader(status: stream.status, headers: stream.headers)
            guard await self.sendData(head, on: connection) else {
                connection.cancel()
                return
            }
            do {
                for try await event in stream.events {
                    guard !Task.isCancelled else {
                        break
                    }
                    guard await self.sendData(RuntimeControlServerSentEventCodec.encode(event), on: connection) else {
                        break
                    }
                }
            } catch {
                _ = await self.sendData(Data(": stream-error\n\n".utf8), on: connection)
            }
            connection.cancel()
        }
        streamTasks[id] = task
    }

    private func sendData(_ data: Data, on connection: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    private func send(_ response: RuntimeControlHTTPResponse, on connection: NWConnection) {
        let encoded = RuntimeControlHTTPWireCodec.encodeResponse(response)
        connection.send(content: encoded, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func preflightResponse(for request: RuntimeControlHTTPRequest) -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .noContent,
            headers: corsHeaders(for: request)
        )
    }

    private func corsResponse(
        _ response: RuntimeControlHTTPResponse,
        for request: RuntimeControlHTTPRequest
    ) -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: response.status,
            headers: response.headers.merging(corsHeaders(for: request)) { current, _ in current },
            body: response.body
        )
    }

    private func corsStream(
        _ stream: RuntimeControlHTTPStreamResponse,
        for request: RuntimeControlHTTPRequest
    ) -> RuntimeControlHTTPStreamResponse {
        RuntimeControlHTTPStreamResponse(
            status: stream.status,
            headers: stream.headers.merging(corsHeaders(for: request)) { current, _ in current },
            events: stream.events
        )
    }

    private func corsHeaders(for request: RuntimeControlHTTPRequest) -> [String: String] {
        guard let origin = headerValue("Origin", in: request.headers),
              isLoopbackOrigin(origin) else {
            return [:]
        }

        return [
            "Access-Control-Allow-Headers": "Accept, Content-Type, X-Runtime-Control-Token",
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Origin": origin,
            "Access-Control-Max-Age": "600",
            "Vary": "Origin",
        ]
    }

    private func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    private func isLoopbackOrigin(_ origin: String) -> Bool {
        guard let components = URLComponents(string: origin),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased() else {
            return false
        }

        return host == "localhost"
            || host == "::1"
            || host == "0:0:0:0:0:0:0:1"
            || host.hasPrefix("127.")
    }
}
