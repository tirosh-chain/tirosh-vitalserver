import Contracts
import CryptoKit
import Foundation

public enum GuestOwnedLayer: Sendable {
    case container
    case guestRuntime

    var updateLayer: UpdateLayer {
        switch self {
        case .container: .container
        case .guestRuntime: .guestRuntime
        }
    }

    var artifactKind: String {
        switch self {
        case .container: "container-image-set"
        case .guestRuntime: "guest-runtime-release"
        }
    }

    var ownerPath: String {
        switch self {
        case .container: "runtime/container-image-set"
        case .guestRuntime: "runtime/guest-runtime-release"
        }
    }

    var evidenceKind: String {
        switch self {
        case .container: "guest-container-image-set-operation"
        case .guestRuntime: "guest-runtime-release-operation"
        }
    }

    var artifactMediaType: String {
        switch self {
        case .container, .guestRuntime:
            "application/x-tar"
        }
    }
}

public enum LayerEffectExecutorError: Error, CustomStringConvertible {
    case usage
    case requestRead(String)
    case requestInvalid(String)
    case receiptAlreadyExists(String)
    case receiptWrite(String)

    public var description: String {
        switch self {
        case .usage:
            "usage: <executor> execute --request <request.json> --receipt <receipt.json>"
        case .requestRead(let reason):
            "effect request read failed: \(reason)"
        case .requestInvalid(let reason):
            "effect request is invalid: \(reason)"
        case .receiptAlreadyExists(let path):
            "effect receipt already exists: \(path)"
        case .receiptWrite(let reason):
            "effect receipt write failed: \(reason)"
        }
    }
}

public protocol LayerEffectHTTPTransport: Sendable {
    func send(
        _ request: URLRequest,
        uploadFile: URL?
    ) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionLayerEffectHTTPTransport: LayerEffectHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(
        _ request: URLRequest,
        uploadFile: URL?
    ) async throws -> (Data, HTTPURLResponse) {
        let result: (Data, URLResponse)
        if let uploadFile {
            result = try await session.upload(for: request, fromFile: uploadFile)
        } else {
            result = try await session.data(for: request)
        }
        guard let response = result.1 as? HTTPURLResponse else {
            throw GuestOwnerEffectFailure.failed(
                code: "guest-owner-http-response-invalid",
                message: "Guest owner response is not HTTP.",
                dependency: "guest-control-api"
            )
        }
        return (result.0, response)
    }
}

public struct GuestOwnerLayerEffectExecutor: Sendable {
    private let transport: any LayerEffectHTTPTransport

    public init(transport: any LayerEffectHTTPTransport) {
        self.transport = transport
    }

    public func execute(
        layer: GuestOwnedLayer,
        invocation: ProductUpdateLayerEffectInvocation,
        configuration: LayerEffectConfiguration
    ) async -> ProductUpdateLayerEffectReceipt {
        do {
            try validate(
                layer: layer,
                invocation: invocation,
                configuration: configuration
            )
            try verifyFile(
                path: invocation.artifactPath,
                expectedSHA256: invocation.artifactSHA256,
                expectedSizeBytes: invocation.artifactSizeBytes,
                role: "layer artifact"
            )
            try verifyFile(
                path: invocation.configurationPath,
                expectedSHA256: invocation.configurationSHA256,
                role: "effect configuration"
            )
            let imported = try await importArtifact(
                layer: layer,
                invocation: invocation,
                configuration: configuration
            )
            let operation = try await submit(
                layer: layer,
                invocation: invocation,
                configuration: configuration,
                imported: imported
            )
            let terminal = try await poll(
                layer: layer,
                invocation: invocation,
                configuration: configuration,
                imported: imported,
                accepted: operation
            )
            return try successfulReceipt(
                layer: layer,
                invocation: invocation,
                terminal: terminal
            )
        } catch let failure as GuestOwnerEffectFailure {
            return failedReceipt(invocation: invocation, failure: failure)
        } catch {
            return failedReceipt(
                invocation: invocation,
                failure: .failed(
                    code: "guest-owner-effect-unclassified",
                    message: String(describing: error),
                    dependency: "guest-owner-layer-effect-executor"
                )
            )
        }
    }

    private func validate(
        layer: GuestOwnedLayer,
        invocation: ProductUpdateLayerEffectInvocation,
        configuration: LayerEffectConfiguration
    ) throws {
        guard invocation.schemaVersion ==
                ProductUpdateExecutionContract.layerEffectInvocationSchemaVersion,
              invocation.layer == layer.updateLayer,
              invocation.effectExecutorId == configuration.effectExecutorId,
              invocation.operation == .apply || invocation.operation == .rollback,
              invocation.artifactPath.hasPrefix("/"),
              invocation.configurationPath.hasPrefix("/"),
              isSHA256(invocation.artifactSHA256),
              isSHA256(invocation.configurationSHA256),
              invocation.artifactSizeBytes > 0,
              invocation.artifactMediaType == layer.artifactMediaType else {
            throw GuestOwnerEffectFailure.failed(
                code: "layer-effect-invocation-invalid",
                message: "Layer invocation identity, paths, or digests are invalid.",
                dependency: "bundle-owned-update-runner"
            )
        }
        try configuration.validate(for: layer)
    }

    private func importArtifact(
        layer: GuestOwnedLayer,
        invocation: ProductUpdateLayerEffectInvocation,
        configuration: LayerEffectConfiguration
    ) async throws -> ImportedArtifact {
        let digest = "sha256:\(invocation.artifactSHA256)"
        let url = try endpoint(
            configuration,
            path: "runtime/update-artifacts/\(layer.artifactKind)/\(digest)"
        )
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = configuration.requestTimeoutSeconds
        request.setValue(
            "application/octet-stream",
            forHTTPHeaderField: "Content-Type"
        )
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: invocation.artifactPath
            )
            guard let size = attributes[.size] as? NSNumber,
                  size.int64Value > 0 else {
                throw GuestOwnerEffectFailure.failed(
                    code: "layer-effect-artifact-size-invalid",
                    message: "Layer artifact size is unavailable or zero.",
                    dependency: "host-update-staging"
                )
            }
            request.setValue(
                size.stringValue,
                forHTTPHeaderField: "Content-Length"
            )
        } catch let failure as GuestOwnerEffectFailure {
            throw failure
        } catch {
            throw GuestOwnerEffectFailure.unavailable(
                code: "layer-effect-artifact-size-unavailable",
                message: "Layer artifact size read failed: \(error)",
                dependency: "host-update-staging"
            )
        }
        let (data, response) = try await send(
            request,
            uploadFile: URL(fileURLWithPath: invocation.artifactPath)
        )
        guard response.statusCode == 201 else {
            throw httpFailure(
                response: response,
                data: data,
                operation: "artifact import"
            )
        }
        let imported: ImportedArtifact = try decodeStrict(data)
        guard imported.kind == layer.artifactKind,
              imported.digest == digest,
              !imported.ownerReference.isEmpty else {
            throw GuestOwnerEffectFailure.failed(
                code: "guest-artifact-import-correlation-mismatch",
                message: "Guest artifact import response does not match the request.",
                dependency: "guest-update-artifact-owner"
            )
        }
        return imported
    }

    private func submit(
        layer: GuestOwnedLayer,
        invocation: ProductUpdateLayerEffectInvocation,
        configuration: LayerEffectConfiguration,
        imported: ImportedArtifact
    ) async throws -> GuestOwnerOperation {
        let intent = try configuration.intent(for: invocation.operation)
        let url = try endpoint(
            configuration,
            path: "\(layer.ownerPath)/\(invocation.operation.rawValue)"
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try commandData(
            layer: layer,
            intent: intent,
            digest: imported.digest,
            ownerReference: imported.ownerReference
        )
        let (data, response) = try await send(request, uploadFile: nil)
        guard response.statusCode == 202 else {
            throw httpFailure(
                response: response,
                data: data,
                operation: "owner command"
            )
        }
        let operation = try decodeOperation(layer: layer, data: data)
        try correlate(
            layer: layer,
            invocation: invocation,
            intent: intent,
            imported: imported,
            operation: operation
        )
        guard operation.state == "pending" else {
            throw GuestOwnerEffectFailure.failed(
                code: "guest-owner-acceptance-state-invalid",
                message: "Guest owner did not accept the command as pending.",
                dependency: layer.ownerPath
            )
        }
        return operation
    }

    private func poll(
        layer: GuestOwnedLayer,
        invocation: ProductUpdateLayerEffectInvocation,
        configuration: LayerEffectConfiguration,
        imported: ImportedArtifact,
        accepted: GuestOwnerOperation
    ) async throws -> GuestOwnerOperation {
        let intent = try configuration.intent(for: invocation.operation)
        let deadline = Date().addingTimeInterval(
            configuration.operationTimeoutSeconds
        )
        var lastUnavailable: GuestOwnerEffectFailure?
        while Date() < deadline {
            let url = try endpoint(
                configuration,
                path: "\(layer.ownerPath)/operations/\(accepted.operationId)"
            )
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = configuration.requestTimeoutSeconds
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await send(request, uploadFile: nil)
            } catch let failure as GuestOwnerEffectFailure
                where failure.state == .unavailable {
                lastUnavailable = failure
                try await Task.sleep(
                    for: .milliseconds(configuration.pollIntervalMilliseconds)
                )
                continue
            }
            lastUnavailable = nil
            guard response.statusCode == 200 else {
                throw httpFailure(
                    response: response,
                    data: data,
                    operation: "operation poll"
                )
            }
            let operation = try decodeOperation(layer: layer, data: data)
            try correlate(
                layer: layer,
                invocation: invocation,
                intent: intent,
                imported: imported,
                operation: operation
            )
            guard operation.operationId == accepted.operationId else {
                throw GuestOwnerEffectFailure.failed(
                    code: "guest-owner-operation-id-mismatch",
                    message: "Polled Guest operation ID changed.",
                    dependency: layer.ownerPath
                )
            }
            switch operation.state {
            case "succeeded", "failed", "unavailable":
                return operation
            case "pending", "running":
                try await Task.sleep(
                    for: .milliseconds(configuration.pollIntervalMilliseconds)
                )
            default:
                throw GuestOwnerEffectFailure.failed(
                    code: "guest-owner-operation-state-invalid",
                    message: "Guest owner returned an unsupported operation state.",
                    dependency: layer.ownerPath
                )
            }
        }
        if let lastUnavailable {
            throw lastUnavailable
        }
        throw GuestOwnerEffectFailure.unavailable(
            code: "guest-owner-operation-timeout",
            message: "Guest owner operation did not become terminal before timeout.",
            dependency: layer.ownerPath
        )
    }

    private func successfulReceipt(
        layer: GuestOwnedLayer,
        invocation: ProductUpdateLayerEffectInvocation,
        terminal: GuestOwnerOperation
    ) throws -> ProductUpdateLayerEffectReceipt {
        guard terminal.state == "succeeded", terminal.failure == nil else {
            if terminal.state == "unavailable" {
                throw GuestOwnerEffectFailure.unavailable(
                    code: terminal.failure?.kind ??
                        "guest-owner-operation-unavailable",
                    message: terminal.failure?.message ??
                        "Guest owner operation is unavailable.",
                    dependency: layer.ownerPath
                )
            }
            throw GuestOwnerEffectFailure.failed(
                code: terminal.failure?.kind ?? "guest-owner-operation-failed",
                message: terminal.failure?.message ??
                    "Guest owner operation failed.",
                dependency: layer.ownerPath
            )
        }
        return ProductUpdateLayerEffectReceipt(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: invocation.updateId,
            layer: invocation.layer,
            effectExecutorId: invocation.effectExecutorId,
            operation: invocation.operation,
            artifactSHA256: invocation.artifactSHA256,
            state: .succeeded,
            observedAt: ISO8601DateFormatter().string(from: Date()),
            evidence: ProductUpdateEvidenceReference(
                kind: layer.evidenceKind,
                id: terminal.operationId
            ),
            issue: nil
        )
    }

    private func failedReceipt(
        invocation: ProductUpdateLayerEffectInvocation,
        failure: GuestOwnerEffectFailure
    ) -> ProductUpdateLayerEffectReceipt {
        ProductUpdateLayerEffectReceipt(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: invocation.updateId,
            layer: invocation.layer,
            effectExecutorId: invocation.effectExecutorId,
            operation: invocation.operation,
            artifactSHA256: invocation.artifactSHA256,
            state: failure.state,
            observedAt: ISO8601DateFormatter().string(from: Date()),
            evidence: ProductUpdateEvidenceReference(
                kind: "guest-owner-layer-effect-executor",
                id: "\(invocation.updateId):\(invocation.layer.rawValue)"
            ),
            issue: ProductUpdateIssue(
                code: failure.code,
                message: failure.message,
                retryable: failure.state == .unavailable,
                dependency: failure.dependency
            )
        )
    }

    private func correlate(
        layer: GuestOwnedLayer,
        invocation: ProductUpdateLayerEffectInvocation,
        intent: LayerEffectIntent,
        imported: ImportedArtifact,
        operation: GuestOwnerOperation
    ) throws {
        guard operation.command == invocation.operation.rawValue,
              operation.expectedIdentity == intent.expectedIdentity,
              operation.targetIdentity == intent.targetIdentity,
              operation.targetDigest == imported.digest,
              layer != .guestRuntime ||
                operation.targetArchive == imported.ownerReference else {
            throw GuestOwnerEffectFailure.failed(
                code: "guest-owner-operation-correlation-mismatch",
                message: "Guest owner operation does not match the submitted command.",
                dependency: layer.ownerPath
            )
        }
    }

    private func send(
        _ request: URLRequest,
        uploadFile: URL?
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request, uploadFile: uploadFile)
        } catch let failure as GuestOwnerEffectFailure {
            throw failure
        } catch {
            throw GuestOwnerEffectFailure.unavailable(
                code: "guest-owner-connection-unavailable",
                message: "Guest owner request failed: \(error)",
                dependency: "guest-control-api"
            )
        }
    }
}

public struct LayerEffectConfiguration: Decodable, Sendable {
    public static let schemaVersion =
        "vitalserver.guest-owner-layer-effect-configuration/v1"

    public let schemaVersion: String
    public let layer: UpdateLayer
    public let effectExecutorId: String
    public let guestControlBaseURL: String
    public let requestTimeoutSeconds: Double
    public let operationTimeoutSeconds: Double
    public let pollIntervalMilliseconds: Int64
    public let apply: LayerEffectIntent
    public let rollback: LayerEffectIntent

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case layer
        case effectExecutorId
        case guestControlBaseURL
        case requestTimeoutSeconds
        case operationTimeoutSeconds
        case pollIntervalMilliseconds
        case apply
        case rollback
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "LayerEffectConfiguration"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(String.self, forKey: .schemaVersion)
        layer = try values.decode(UpdateLayer.self, forKey: .layer)
        effectExecutorId = try values.decode(
            String.self,
            forKey: .effectExecutorId
        )
        guestControlBaseURL = try values.decode(
            String.self,
            forKey: .guestControlBaseURL
        )
        requestTimeoutSeconds = try values.decode(
            Double.self,
            forKey: .requestTimeoutSeconds
        )
        operationTimeoutSeconds = try values.decode(
            Double.self,
            forKey: .operationTimeoutSeconds
        )
        pollIntervalMilliseconds = try values.decode(
            Int64.self,
            forKey: .pollIntervalMilliseconds
        )
        apply = try values.decode(LayerEffectIntent.self, forKey: .apply)
        rollback = try values.decode(LayerEffectIntent.self, forKey: .rollback)
    }

    func validate(for layer: GuestOwnedLayer) throws {
        guard schemaVersion == Self.schemaVersion,
              self.layer == layer.updateLayer,
              !effectExecutorId.isEmpty,
              let baseURL = URL(string: guestControlBaseURL),
              baseURL.scheme == "http",
              baseURL.host == "127.0.0.1",
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/",
              requestTimeoutSeconds > 0,
              requestTimeoutSeconds <= 900,
              operationTimeoutSeconds > 0,
              operationTimeoutSeconds <= 3600,
              pollIntervalMilliseconds >= 50,
              pollIntervalMilliseconds <= 5_000,
              !apply.expectedIdentity.isEmpty,
              !apply.targetIdentity.isEmpty,
              !rollback.expectedIdentity.isEmpty,
              !rollback.targetIdentity.isEmpty,
              apply.expectedIdentity != apply.targetIdentity,
              rollback.expectedIdentity == apply.targetIdentity,
              rollback.targetIdentity == apply.expectedIdentity else {
            throw GuestOwnerEffectFailure.failed(
                code: "layer-effect-configuration-invalid",
                message: "Effect configuration is invalid for \(layer.updateLayer.rawValue).",
                dependency: "effect-configuration"
            )
        }
    }

    func intent(
        for operation: ProductUpdateLayerEffectOperation
    ) throws -> LayerEffectIntent {
        switch operation {
        case .apply: apply
        case .rollback: rollback
        }
    }
}

public struct LayerEffectIntent: Decodable, Sendable {
    public let expectedIdentity: String
    public let targetIdentity: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case expectedIdentity
        case targetIdentity
    }

    public init(expectedIdentity: String, targetIdentity: String) {
        self.expectedIdentity = expectedIdentity
        self.targetIdentity = targetIdentity
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "LayerEffectIntent"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        expectedIdentity = try values.decode(
            String.self,
            forKey: .expectedIdentity
        )
        targetIdentity = try values.decode(
            String.self,
            forKey: .targetIdentity
        )
    }
}

public func runLayerEffectExecutor(_ layer: GuestOwnedLayer) async {
    do {
        let arguments = try invocationArguments(
            Array(CommandLine.arguments.dropFirst())
        )
        guard !FileManager.default.fileExists(atPath: arguments.receipt.path) else {
            throw LayerEffectExecutorError.receiptAlreadyExists(
                arguments.receipt.path
            )
        }
        let invocation = try decodeFile(
            ProductUpdateLayerEffectInvocation.self,
            at: arguments.request,
            role: "effect request"
        )
        let configuration = try decodeFile(
            LayerEffectConfiguration.self,
            at: URL(fileURLWithPath: invocation.configurationPath),
            role: "effect configuration"
        )
        let receipt = await GuestOwnerLayerEffectExecutor(
            transport: URLSessionLayerEffectHTTPTransport()
        ).execute(
            layer: layer,
            invocation: invocation,
            configuration: configuration
        )
        try writeReceipt(receipt, to: arguments.receipt)
    } catch {
        fputs("\(error)\n", stderr)
        Foundation.exit(1)
    }
}

private struct InvocationArguments {
    let request: URL
    let receipt: URL
}

private func invocationArguments(_ arguments: [String]) throws -> InvocationArguments {
    guard arguments.count == 5,
          arguments[0] == "execute",
          arguments[1] == "--request",
          arguments[3] == "--receipt",
          arguments[2].hasPrefix("/"),
          arguments[4].hasPrefix("/") else {
        throw LayerEffectExecutorError.usage
    }
    return InvocationArguments(
        request: URL(fileURLWithPath: arguments[2]),
        receipt: URL(fileURLWithPath: arguments[4])
    )
}

private func decodeFile<T: Decodable>(
    _ type: T.Type,
    at url: URL,
    role: String
) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    } catch {
        throw LayerEffectExecutorError.requestRead(
            "\(role) path=\(url.path) reason=\(error)"
        )
    }
}

private func writeReceipt(
    _ receipt: ProductUpdateLayerEffectReceipt,
    to url: URL
) throws {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipt).write(to: url, options: [.atomic])
    } catch {
        throw LayerEffectExecutorError.receiptWrite(String(describing: error))
    }
}

private struct ImportedArtifact: Decodable {
    let kind: String
    let digest: String
    let ownerReference: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case digest
        case ownerReference
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ImportedArtifact"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(String.self, forKey: .kind)
        digest = try values.decode(String.self, forKey: .digest)
        ownerReference = try values.decode(String.self, forKey: .ownerReference)
    }
}

private struct GuestOwnerOperation {
    let operationId: String
    let command: String
    let expectedIdentity: String
    let targetIdentity: String
    let targetArchive: String?
    let targetDigest: String
    let state: String
    let failure: GuestOwnerFailure?
}

private struct GuestOwnerFailure: Decodable {
    let kind: String
    let message: String
}

private struct ContainerOperationDocument: Decodable {
    let operationId: String
    let command: String
    let expectedCurrentIdentity: String
    let target: ContainerTarget
    let state: String
    let failure: GuestOwnerFailure?
}

private struct ContainerTarget: Decodable {
    let identity: String
    let digest: String
}

private struct GuestRuntimeOperationDocument: Decodable {
    let operationId: String
    let command: String
    let expectedActiveIdentity: String
    let target: GuestRuntimeTarget
    let state: String
    let failure: GuestOwnerFailure?
}

private struct GuestRuntimeTarget: Decodable {
    let identity: String
    let archive: String
    let digest: String
}

private struct GuestHTTPFailure: Decodable {
    let detail: String
    let code: String
}

private struct GuestOwnerEffectFailure: Error {
    let state: ProductUpdateLayerEffectState
    let code: String
    let message: String
    let dependency: String

    static func failed(
        code: String,
        message: String,
        dependency: String
    ) -> Self {
        .init(
            state: .failed,
            code: code,
            message: message,
            dependency: dependency
        )
    }

    static func unavailable(
        code: String,
        message: String,
        dependency: String
    ) -> Self {
        .init(
            state: .unavailable,
            code: code,
            message: message,
            dependency: dependency
        )
    }
}

private func endpoint(
    _ configuration: LayerEffectConfiguration,
    path: String
) throws -> URL {
    guard let baseURL = URL(string: configuration.guestControlBaseURL),
          let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
        throw GuestOwnerEffectFailure.failed(
            code: "guest-owner-endpoint-invalid",
            message: "Guest owner endpoint could not be constructed.",
            dependency: "effect-configuration"
        )
    }
    return url
}

private func commandData(
    layer: GuestOwnedLayer,
    intent: LayerEffectIntent,
    digest: String,
    ownerReference: String
) throws -> Data {
    let target: [String: String]
    let expectedKey: String
    switch layer {
    case .container:
        target = [
            "identity": intent.targetIdentity,
            "digest": digest,
        ]
        expectedKey = "expectedCurrentIdentity"
    case .guestRuntime:
        target = [
            "identity": intent.targetIdentity,
            "archive": ownerReference,
            "digest": digest,
        ]
        expectedKey = "expectedActiveIdentity"
    }
    return try JSONSerialization.data(
        withJSONObject: [
            expectedKey: intent.expectedIdentity,
            "target": target,
        ],
        options: [.sortedKeys]
    )
}

private func decodeOperation(
    layer: GuestOwnedLayer,
    data: Data
) throws -> GuestOwnerOperation {
    do {
        try validateOperationDocument(layer: layer, data: data)
        switch layer {
        case .container:
            let value = try decodeStrict(
                data,
                as: ContainerOperationDocument.self
            )
            return GuestOwnerOperation(
                operationId: value.operationId,
                command: value.command,
                expectedIdentity: value.expectedCurrentIdentity,
                targetIdentity: value.target.identity,
                targetArchive: nil,
                targetDigest: value.target.digest,
                state: value.state,
                failure: value.failure
            )
        case .guestRuntime:
            let value = try decodeStrict(
                data,
                as: GuestRuntimeOperationDocument.self
            )
            return GuestOwnerOperation(
                operationId: value.operationId,
                command: value.command,
                expectedIdentity: value.expectedActiveIdentity,
                targetIdentity: value.target.identity,
                targetArchive: value.target.archive,
                targetDigest: value.target.digest,
                state: value.state,
                failure: value.failure
            )
        }
    } catch let failure as GuestOwnerEffectFailure {
        throw failure
    } catch {
        throw GuestOwnerEffectFailure.failed(
            code: "guest-owner-response-malformed",
            message: "Guest owner operation response is malformed: \(error)",
            dependency: layer.ownerPath
        )
    }
}

private func validateOperationDocument(
    layer: GuestOwnedLayer,
    data: Data
) throws {
    guard let document = try JSONSerialization.jsonObject(with: data)
            as? [String: Any] else {
        throw GuestOwnerEffectFailure.failed(
            code: "guest-owner-response-malformed",
            message: "Guest owner operation response must be an object.",
            dependency: layer.ownerPath
        )
    }
    let expectedKey = layer == .container
        ? "expectedCurrentIdentity"
        : "expectedActiveIdentity"
    try requireExactKeys(
        document,
        expected: [
            "operationId",
            "command",
            expectedKey,
            "target",
            "state",
            "createdAt",
            "updatedAt",
            "failure",
        ],
        type: "GuestOwnerOperation"
    )
    guard let target = document["target"] as? [String: Any] else {
        throw GuestOwnerEffectFailure.failed(
            code: "guest-owner-response-malformed",
            message: "Guest owner operation target must be an object.",
            dependency: layer.ownerPath
        )
    }
    try requireExactKeys(
        target,
        expected: layer == .container
            ? ["identity", "digest"]
            : ["identity", "archive", "digest"],
        type: "GuestOwnerOperation.target"
    )
    if let failure = document["failure"] as? [String: Any] {
        try requireExactKeys(
            failure,
            expected: ["kind", "message"],
            type: "GuestOwnerOperation.failure"
        )
    } else if !(document["failure"] is NSNull) {
        throw GuestOwnerEffectFailure.failed(
            code: "guest-owner-response-malformed",
            message: "Guest owner operation failure must be an object or null.",
            dependency: layer.ownerPath
        )
    }
}

private func requireExactKeys(
    _ document: [String: Any],
    expected: Set<String>,
    type: String
) throws {
    let actual = Set(document.keys)
    guard actual == expected else {
        throw GuestOwnerEffectFailure.failed(
            code: "guest-owner-response-malformed",
            message:
                "\(type) keys disagree expected=\(expected.sorted()) actual=\(actual.sorted()).",
            dependency: "guest-control-api"
        )
    }
}

private func decodeStrict<T: Decodable>(
    _ data: Data,
    as type: T.Type = T.self
) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw GuestOwnerEffectFailure.failed(
            code: "guest-owner-response-malformed",
            message: "Guest owner response is malformed: \(error)",
            dependency: "guest-control-api"
        )
    }
}

private func httpFailure(
    response: HTTPURLResponse,
    data: Data,
    operation: String
) -> GuestOwnerEffectFailure {
    if let issue = try? JSONDecoder().decode(GuestHTTPFailure.self, from: data) {
        let maker = response.statusCode >= 500
            ? GuestOwnerEffectFailure.unavailable
            : GuestOwnerEffectFailure.failed
        return maker(
            issue.code,
            "\(operation) rejected: \(issue.detail)",
            "guest-control-api"
        )
    }
    return .failed(
        code: "guest-owner-http-failure-malformed",
        message: "\(operation) returned HTTP \(response.statusCode) without typed failure.",
        dependency: "guest-control-api"
    )
}

private func verifyFile(
    path: String,
    expectedSHA256: String,
    expectedSizeBytes: Int? = nil,
    role: String
) throws {
    guard path.hasPrefix("/"), isSHA256(expectedSHA256) else {
        throw GuestOwnerEffectFailure.failed(
            code: "layer-effect-file-contract-invalid",
            message: "\(role) path or digest is invalid.",
            dependency: "bundle-owned-update-runner"
        )
    }
    let url = URL(fileURLWithPath: path)
    let handle: FileHandle
    do {
        handle = try FileHandle(forReadingFrom: url)
    } catch {
        throw GuestOwnerEffectFailure.unavailable(
            code: "layer-effect-file-unavailable",
            message: "\(role) is unavailable: \(error)",
            dependency: "host-update-staging"
        )
    }
    defer {
        try? handle.close()
    }
    var digest = SHA256()
    var sizeBytes = 0
    do {
        while let chunk = try handle.read(upToCount: 1024 * 1024),
              !chunk.isEmpty {
            digest.update(data: chunk)
            sizeBytes += chunk.count
        }
    } catch {
        throw GuestOwnerEffectFailure.unavailable(
            code: "layer-effect-file-unavailable",
            message: "\(role) digest read failed: \(error)",
            dependency: "host-update-staging"
        )
    }
    if let expectedSizeBytes, sizeBytes != expectedSizeBytes {
        throw GuestOwnerEffectFailure.failed(
            code: "layer-effect-file-size-mismatch",
            message: "\(role) size mismatch expected=\(expectedSizeBytes) actual=\(sizeBytes).",
            dependency: "host-update-staging"
        )
    }
    let actual = digest.finalize()
        .map { String(format: "%02x", $0) }
        .joined()
    guard actual == expectedSHA256 else {
        throw GuestOwnerEffectFailure.failed(
            code: "layer-effect-file-digest-mismatch",
            message: "\(role) digest mismatch expected=\(expectedSHA256) actual=\(actual).",
            dependency: "host-update-staging"
        )
    }
}

private func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy {
        ("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0))
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private func rejectUnknownKeys(
    _ decoder: Decoder,
    allowed: [String],
    type: String
) throws {
    let values = try decoder.container(keyedBy: AnyCodingKey.self)
    let unknown = Set(values.allKeys.map(\.stringValue))
        .subtracting(allowed)
        .sorted()
    guard unknown.isEmpty else {
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "\(type) contains unknown keys: \(unknown)"
            )
        )
    }
}
