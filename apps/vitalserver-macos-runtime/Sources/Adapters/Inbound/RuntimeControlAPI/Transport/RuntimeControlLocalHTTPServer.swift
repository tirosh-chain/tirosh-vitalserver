import Foundation
import Network
import Errors

public enum RuntimeControlLocalHTTPServerState: Equatable, Sendable {
    case ready(port: UInt16?)
    case failed(String)
    case stopped
}

public struct RuntimeControlLocalHTTPServerConfiguration: Equatable, Sendable {
    public let port: UInt16
    public let servesDevConsole: Bool
    public let staticFileDirectory: URL?
    public let bindsToLoopbackOnly: Bool
    public let browserSession: RuntimeControlLoopbackBrowserSession?
    public let uploadStagingRoot: URL?

    public init(
        port: UInt16,
        servesDevConsole: Bool = false,
        staticFileDirectory: URL? = nil,
        bindsToLoopbackOnly: Bool = true,
        browserSession: RuntimeControlLoopbackBrowserSession? = nil,
        uploadStagingRoot: URL? = nil
    ) {
        self.port = port
        self.servesDevConsole = servesDevConsole
        self.staticFileDirectory = staticFileDirectory
        self.bindsToLoopbackOnly = bindsToLoopbackOnly
        self.browserSession = browserSession
        self.uploadStagingRoot = uploadStagingRoot
    }
}

public final class RuntimeControlLocalHTTPServer: @unchecked Sendable {
    private static let maximumRequestHeaderBytes = 64 * 1024
    private static let vitalFileUploadPath = "/runtime/lab/vital-files/upload"

    private let configuration: RuntimeControlLocalHTTPServerConfiguration
    private let router: RuntimeControlAPIRouter
    private let staticFileResponder: RuntimeControlStaticFileResponder?
    private let corsPolicy = RuntimeControlLocalHTTPCORSPolicy()
    private let stateHandler: (@Sendable (RuntimeControlLocalHTTPServerState) -> Void)?
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var requestBuffers: [ObjectIdentifier: Data] = [:]
    private var stagedRequests: [ObjectIdentifier: RuntimeControlStagedIncomingRequest] = [:]
    private var streamTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    public var activePort: UInt16? {
        syncOnQueue {
            guard let rawValue = listener?.port?.rawValue, rawValue != 0 else {
                return nil
            }
            return rawValue
        }
    }

    @MainActor
    public init(
        configuration: RuntimeControlLocalHTTPServerConfiguration,
        router: RuntimeControlAPIRouter,
        stateHandler: (@Sendable (RuntimeControlLocalHTTPServerState) -> Void)? = nil,
        queue: DispatchQueue = DispatchQueue(label: "tirosh.runtime-control.local-http")
    ) {
        self.configuration = configuration
        self.router = router
        self.staticFileResponder = configuration.staticFileDirectory.map {
            RuntimeControlStaticFileResponder(rootDirectory: $0)
        }
        self.stateHandler = stateHandler
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
        if configuration.bindsToLoopbackOnly {
            parameters.requiredInterfaceType = .loopback
        }
        let listener = try NWListener(using: parameters, on: port)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else {
                return
            }
            switch state {
            case .ready:
                self.stateHandler?(.ready(port: listener?.port?.rawValue))
            case .failed(let error):
                self.syncOnQueue {
                    if self.listener === listener {
                        self.stopLocked()
                    }
                }
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
        for request in stagedRequests.values {
            request.cleanup()
        }
        stagedRequests.removeAll()
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
                self?.stagedRequests.removeValue(forKey: id)?.cleanup()
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
                self.buffer(data, isComplete: isComplete, from: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(from: connection)
        }
    }

    private func buffer(
        _ data: Data,
        isComplete: Bool,
        from connection: NWConnection
    ) {
        let id = ObjectIdentifier(connection)
        if let staged = stagedRequests[id] {
            do {
                let request = try staged.append(data)
                if let request {
                    stagedRequests.removeValue(forKey: id)
                    respond(
                        to: request,
                        cleanupDirectory: staged.temporaryDirectoryURL,
                        on: connection
                    )
                    return
                }
                if isComplete {
                    throw RuntimeControlHTTPWireCodecError.invalidRequest
                }
                receive(from: connection)
            } catch {
                stagedRequests.removeValue(forKey: id)?.cleanup()
                send(stagingResponse(for: error), on: connection)
            }
            return
        }

        var buffered = requestBuffers[id] ?? Data()
        buffered.append(data)

        do {
            if RuntimeControlHTTPWireCodec.headerSeparatorRange(in: buffered) == nil {
                guard buffered.count <= Self.maximumRequestHeaderBytes else {
                    throw RuntimeControlHTTPWireCodecError.invalidRequest
                }
                if isComplete {
                    throw RuntimeControlHTTPWireCodecError.invalidRequest
                }
                requestBuffers[id] = buffered
                receive(from: connection)
                return
            }

            let head = try RuntimeControlHTTPWireCodec.decodeRequestHead(buffered)
            if head.method == .post,
               head.path.split(separator: "?", maxSplits: 1).first
                == Substring(Self.vitalFileUploadPath) {
                guard head.contentLength != nil else {
                    requestBuffers.removeValue(forKey: id)
                    send(RuntimeControlHTTPWireCodec.badRequestResponse(
                        message: "Vital Files upload requires Content-Length."
                    ), on: connection)
                    return
                }
                let staged = try makeStagedRequest(head: head, buffered: buffered)
                requestBuffers.removeValue(forKey: id)
                if let request = try staged.completeRequestIfReady() {
                    respond(
                        to: request,
                        cleanupDirectory: staged.temporaryDirectoryURL,
                        on: connection
                    )
                    return
                }
                if isComplete {
                    staged.cleanup()
                    throw RuntimeControlHTTPWireCodecError.invalidRequest
                }
                stagedRequests[id] = staged
                receive(from: connection)
                return
            }

            guard try RuntimeControlHTTPWireCodec.requestIsComplete(buffered) else {
                if isComplete {
                    throw RuntimeControlHTTPWireCodecError.invalidRequest
                }
                requestBuffers[id] = buffered
                receive(from: connection)
                return
            }
            requestBuffers.removeValue(forKey: id)
            respond(to: buffered, on: connection)
        } catch {
            requestBuffers.removeValue(forKey: id)
            send(stagingResponse(for: error), on: connection)
        }
    }

    private func makeStagedRequest(
        head: RuntimeControlHTTPRequestHead,
        buffered: Data
    ) throws -> RuntimeControlStagedIncomingRequest {
        guard let headerRange = RuntimeControlHTTPWireCodec.headerSeparatorRange(in: buffered),
              let contentLength = head.contentLength else {
            throw RuntimeControlHTTPWireCodecError.invalidRequest
        }
        do {
            let root = configuration.uploadStagingRoot
                ?? FileManager.default.temporaryDirectory
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            let directory = root.appendingPathComponent(
                "tirosh-runtime-vital-upload-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false
            )
            let bodyURL = directory.appendingPathComponent("request.multipart")
            guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
                throw RuntimeControlMultipartStagingError(
                    "Vital Files upload request staging file could not be created."
                )
            }
            let request: RuntimeControlStagedIncomingRequest
            do {
                request = try RuntimeControlStagedIncomingRequest(
                    head: head,
                    temporaryDirectoryURL: directory,
                    bodyURL: bodyURL,
                    expectedBodyBytes: contentLength
                )
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
            do {
                let initialBody = Data(buffered[headerRange.upperBound...])
                try request.appendInitial(initialBody)
                return request
            } catch {
                request.cleanup()
                throw error
            }
        } catch let error as RuntimeControlHTTPWireCodecError {
            throw error
        } catch let error as RuntimeControlMultipartStagingError {
            throw error
        } catch {
            throw RuntimeControlMultipartStagingError(
                "Vital Files upload request staging failed: \(error.localizedDescription)"
            )
        }
    }

    private func respond(to data: Data, on connection: NWConnection) {
        let request: RuntimeControlHTTPRequest
        do {
            request = try RuntimeControlHTTPWireCodec.decodeRequest(data)
        } catch {
            send(RuntimeControlHTTPWireCodec.badRequestResponse(for: error), on: connection)
            return
        }

        respond(to: request, cleanupDirectory: nil, on: connection)
    }

    private func respond(
        to request: RuntimeControlHTTPRequest,
        cleanupDirectory: URL?,
        on connection: NWConnection
    ) {
        if request.method == .options {
            cleanup(cleanupDirectory)
            send(preflightResponse(for: request), on: connection)
            return
        }

        if request.path == RuntimeControlLoopbackBrowserSession.bootstrapPath {
            guard let browserSession = configuration.browserSession else {
                cleanup(cleanupDirectory)
                send(RuntimeControlHTTPResponseFactory.error(
                    status: .unauthorized,
                    code: .unauthorized,
                    message: "Local browser session support is unavailable."
                ), on: connection)
                return
            }
            cleanup(cleanupDirectory)
            send(browserSession.bootstrapResponse(for: request, port: activePort), on: connection)
            return
        }

        if let browserSession = configuration.browserSession,
           browserSession.allows(request: request),
           browserSession.needsOriginCheck(request: request),
           !browserSession.isSameOrigin(request: request, port: activePort) {
            cleanup(cleanupDirectory)
            send(RuntimeControlHTTPResponseFactory.error(
                status: .unauthorized,
                code: .unauthorized,
                message: "Local browser session origin is missing or invalid."
            ), on: connection)
            return
        }

        if configuration.servesDevConsole,
           let devConsoleResponse = RuntimeControlDevConsoleDocument.response(for: request) {
            cleanup(cleanupDirectory)
            send(corsResponse(devConsoleResponse, for: request), on: connection)
            return
        }

        if let staticResponse = staticFileResponder?.response(for: request) {
            cleanup(cleanupDirectory)
            send(corsResponse(staticResponse, for: request), on: connection)
            return
        }

        Task { @MainActor [router] in
            let result = await router.routeResult(request)
            self.cleanup(cleanupDirectory)
            self.send(result, for: request, on: connection)
        }
    }

    private func cleanup(_ directory: URL?) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func stagingResponse(for error: Error) -> RuntimeControlHTTPResponse {
        if error is RuntimeControlMultipartStagingError {
            return RuntimeControlHTTPResponseFactory.error(
                status: .serviceUnavailable,
                code: .handlerFailed,
                message: error.localizedDescription
            )
        }
        return RuntimeControlHTTPWireCodec.badRequestResponse(for: error)
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
                    let data = try RuntimeControlServerSentEventCodec.encode(event)
                    guard await self.sendData(data, on: connection) else {
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
            headers: corsPolicy.headers(for: request)
        )
    }

    private func corsResponse(
        _ response: RuntimeControlHTTPResponse,
        for request: RuntimeControlHTTPRequest
    ) -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: response.status,
            headers: response.headers.merging(corsPolicy.headers(for: request)) { current, _ in current },
            body: response.body
        )
    }

    private func corsStream(
        _ stream: RuntimeControlHTTPStreamResponse,
        for request: RuntimeControlHTTPRequest
    ) -> RuntimeControlHTTPStreamResponse {
        RuntimeControlHTTPStreamResponse(
            status: stream.status,
            headers: stream.headers.merging(corsPolicy.headers(for: request)) { current, _ in current },
            events: stream.events
        )
    }
}

private final class RuntimeControlStagedIncomingRequest {
    let temporaryDirectoryURL: URL

    private let head: RuntimeControlHTTPRequestHead
    private let bodyURL: URL
    private let expectedBodyBytes: Int
    private let output: FileHandle
    private var receivedBodyBytes = 0
    private var closed = false

    init(
        head: RuntimeControlHTTPRequestHead,
        temporaryDirectoryURL: URL,
        bodyURL: URL,
        expectedBodyBytes: Int
    ) throws {
        self.head = head
        self.temporaryDirectoryURL = temporaryDirectoryURL
        self.bodyURL = bodyURL
        self.expectedBodyBytes = expectedBodyBytes
        self.output = try FileHandle(forWritingTo: bodyURL)
    }

    func appendInitial(_ data: Data) throws {
        try write(data)
    }

    func append(_ data: Data) throws -> RuntimeControlHTTPRequest? {
        try write(data)
        return try completeRequestIfReady()
    }

    func completeRequestIfReady() throws -> RuntimeControlHTTPRequest? {
        guard receivedBodyBytes == expectedBodyBytes else { return nil }
        guard !closed else {
            throw RuntimeControlHTTPWireCodecError.invalidRequest
        }
        do {
            try output.synchronize()
            try output.close()
            closed = true
        } catch {
            throw RuntimeControlMultipartStagingError(
                "Vital Files upload request staging could not be finalized: \(error.localizedDescription)"
            )
        }
        return RuntimeControlHTTPRequest(
            method: head.method,
            path: head.path,
            headers: head.headers,
            stagedBody: RuntimeControlStagedHTTPRequestBody(
                fileURL: bodyURL,
                temporaryDirectoryURL: temporaryDirectoryURL,
                sizeBytes: Int64(expectedBodyBytes)
            )
        )
    }

    private func write(_ data: Data) throws {
        guard !closed,
              receivedBodyBytes <= expectedBodyBytes,
              data.count <= expectedBodyBytes - receivedBodyBytes else {
            throw RuntimeControlHTTPWireCodecError.invalidRequest
        }
        do {
            try output.write(contentsOf: data)
        } catch {
            throw RuntimeControlMultipartStagingError(
                "Vital Files upload request body could not be staged: \(error.localizedDescription)"
            )
        }
        receivedBodyBytes += data.count
    }

    func cleanup() {
        if !closed {
            try? output.close()
            closed = true
        }
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}
