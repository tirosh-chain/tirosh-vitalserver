import Contracts
import CryptoKit
import Foundation
import Testing
@testable import UpdateLayerEffectExecutor

@Test
func containerExecutorImportsCommandsPollsAndReceiptsCorrelatedSuccess() async throws {
    let fixture = try EffectFixture(layer: .container)
    let transport = FakeTransport(
        responses: [
            response(
                status: 201,
                body: [
                    "kind": "container-image-set",
                    "digest": fixture.digest,
                    "ownerReference":
                        "container-image-set/\(fixture.digest).archive",
                ]
            ),
            response(
                status: 202,
                body: containerOperation(
                    fixture,
                    state: "pending"
                )
            ),
            response(
                status: 200,
                body: containerOperation(
                    fixture,
                    state: "running"
                )
            ),
            response(
                status: 200,
                body: containerOperation(
                    fixture,
                    state: "succeeded"
                )
            ),
        ]
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: fixture.invocation,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .succeeded)
    #expect(receipt.issue == nil)
    #expect(receipt.evidence.kind == "guest-container-image-set-operation")
    let requests = await transport.requests
    #expect(requests.count == 4)
    #expect(requests.allSatisfy { $0.host == "192.168.64.3" })
    #expect(requests[0].method == "PUT")
    #expect(requests[0].uploadPath == fixture.artifact.path)
    #expect(requests[1].method == "POST")
    #expect(requests[2].method == "GET")
}

@Test
func guestRuntimeExecutorCorrelatesImportedOwnerReference() async throws {
    let fixture = try EffectFixture(layer: .guestRuntime)
    let ownerReference = "guest-runtime-release/\(fixture.digest).archive"
    let transport = FakeTransport(
        responses: [
            response(
                status: 201,
                body: [
                    "kind": "guest-runtime-release",
                    "digest": fixture.digest,
                    "ownerReference": ownerReference,
                ]
            ),
            response(
                status: 202,
                body: guestRuntimeOperation(
                    fixture,
                    ownerReference: ownerReference,
                    state: "pending"
                )
            ),
            response(
                status: 200,
                body: guestRuntimeOperation(
                    fixture,
                    ownerReference: ownerReference,
                    state: "succeeded"
                )
            ),
        ]
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .guestRuntime,
        invocation: fixture.invocation,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .succeeded)
    #expect(receipt.evidence.kind == "guest-runtime-release-operation")
}

@Test
func containerRollbackConsumesTheExplicitPreviousImageSetIntent() async throws {
    let fixture = try EffectFixture(layer: .container)
    let rollback = invocation(fixture, operation: .rollback)
    let transport = FakeTransport(
        responses: [
            importedArtifactResponse(fixture, kind: "container-image-set"),
            response(
                status: 202,
                body: containerOperation(
                    fixture,
                    state: "pending",
                    command: "rollback",
                    expectedIdentity: "target-022",
                    targetIdentity: "current-021"
                )
            ),
            response(
                status: 200,
                body: containerOperation(
                    fixture,
                    state: "succeeded",
                    command: "rollback",
                    expectedIdentity: "target-022",
                    targetIdentity: "current-021"
                )
            ),
        ]
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: rollback,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .succeeded)
    let requests = await transport.requests
    let commandBody = try #require(requests[1].body)
    let command = try #require(
        try JSONSerialization.jsonObject(with: commandBody)
            as? [String: Any]
    )
    #expect(command["expectedCurrentIdentity"] as? String == "target-022")
    let target = try #require(command["target"] as? [String: String])
    #expect(target["identity"] == "current-021")
    #expect(target["digest"] == fixture.digest)
}

@Test
func digestMismatchFailsWithoutCallingGuest() async throws {
    let fixture = try EffectFixture(layer: .container)
    let transport = FakeTransport(responses: [])
    let invalid = ProductUpdateLayerEffectInvocation(
        schemaVersion: fixture.invocation.schemaVersion,
        updateId: fixture.invocation.updateId,
        layer: fixture.invocation.layer,
        effectExecutorId: fixture.invocation.effectExecutorId,
        operation: fixture.invocation.operation,
        guestControlBaseURL: fixture.invocation.guestControlBaseURL,
        artifactRelativePath: fixture.invocation.artifactRelativePath,
        artifactPath: fixture.invocation.artifactPath,
        artifactSHA256: String(repeating: "0", count: 64),
        artifactSizeBytes: fixture.invocation.artifactSizeBytes,
        artifactMediaType: fixture.invocation.artifactMediaType,
        configurationRelativePath:
            fixture.invocation.configurationRelativePath,
        configurationPath: fixture.invocation.configurationPath,
        configurationSHA256: fixture.invocation.configurationSHA256
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: invalid,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .failed)
    #expect(receipt.issue?.code == "layer-effect-file-digest-mismatch")
    #expect(await transport.requests.isEmpty)
}

@Test
func artifactSizeMismatchFailsWithoutCallingGuest() async throws {
    let fixture = try EffectFixture(layer: .container)
    let transport = FakeTransport(responses: [])
    let invalid = invocation(
        fixture,
        artifactSizeBytes: fixture.invocation.artifactSizeBytes + 1
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: invalid,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .failed)
    #expect(receipt.issue?.code == "layer-effect-file-size-mismatch")
    #expect(await transport.requests.isEmpty)
}

@Test(arguments: [
    GuestOwnedLayer.container,
    GuestOwnedLayer.guestRuntime,
])
func artifactMediaTypeMismatchFailsWithoutCallingGuest(
    layer: GuestOwnedLayer
) async throws {
    let fixture = try EffectFixture(layer: layer)
    let transport = FakeTransport(responses: [])
    let invalid = invocation(
        fixture,
        artifactMediaType: "application/octet-stream"
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: layer,
        invocation: invalid,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .failed)
    #expect(receipt.issue?.code == "layer-effect-invocation-invalid")
    #expect(await transport.requests.isEmpty)
}

@Test
func configurationForAnotherLayerIsRejectedBeforeCallingGuest() async throws {
    let fixture = try EffectFixture(
        layer: .container,
        declaredLayer: "guest-runtime"
    )
    let transport = FakeTransport(responses: [])

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: fixture.invocation,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .failed)
    #expect(receipt.issue?.code == "layer-effect-configuration-invalid")
    #expect(await transport.requests.isEmpty)
}

@Test
func signedConfigurationCannotOwnTheGuestControlEndpoint() throws {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "schemaVersion":
                "vitalserver.guest-owner-layer-effect-configuration/v1",
            "layer": "container",
            "effectExecutorId": "container-effect-022",
            "guestControlBaseURL": "http://127.0.0.1:18330/",
            "requestTimeoutSeconds": 10,
            "operationTimeoutSeconds": 10,
            "pollIntervalMilliseconds": 50,
            "apply": [
                "expectedIdentity": "current-021",
                "targetIdentity": "target-022",
            ],
            "rollback": [
                "expectedIdentity": "target-022",
                "targetIdentity": "current-021",
            ],
        ]
    )

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
            LayerEffectConfiguration.self,
            from: data
        )
    }
}

@Test
func hostLoopbackGuestControlEndpointIsRejectedBeforeCallingGuest() async throws {
    let fixture = try EffectFixture(layer: .container)
    let loopback = ProductUpdateLayerEffectInvocation(
        schemaVersion: fixture.invocation.schemaVersion,
        updateId: fixture.invocation.updateId,
        layer: fixture.invocation.layer,
        effectExecutorId: fixture.invocation.effectExecutorId,
        operation: fixture.invocation.operation,
        guestControlBaseURL: "http://127.0.0.2:18330/",
        artifactRelativePath: fixture.invocation.artifactRelativePath,
        artifactPath: fixture.invocation.artifactPath,
        artifactSHA256: fixture.invocation.artifactSHA256,
        artifactSizeBytes: fixture.invocation.artifactSizeBytes,
        artifactMediaType: fixture.invocation.artifactMediaType,
        configurationRelativePath:
            fixture.invocation.configurationRelativePath,
        configurationPath: fixture.invocation.configurationPath,
        configurationSHA256: fixture.invocation.configurationSHA256
    )
    let transport = FakeTransport(responses: [])

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: loopback,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .failed)
    #expect(receipt.issue?.code == "guest-owner-endpoint-invalid")
    #expect(await transport.requests.isEmpty)
}

@Test
func identityMismatchIsFailedAndNeverBecomesSuccess() async throws {
    let fixture = try EffectFixture(layer: .container)
    var mismatch = containerOperation(fixture, state: "pending")
    var target = mismatch["target"] as! [String: Any]
    target["identity"] = "unexpected-images"
    mismatch["target"] = target
    let transport = FakeTransport(
        responses: [
            response(
                status: 201,
                body: [
                    "kind": "container-image-set",
                    "digest": fixture.digest,
                    "ownerReference": "container-image-set/archive",
                ]
            ),
            response(status: 202, body: mismatch),
        ]
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: fixture.invocation,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .failed)
    #expect(
        receipt.issue?.code == "guest-owner-operation-correlation-mismatch"
    )
}

@Test
func connectionLossRemainsExplicitUnavailable() async throws {
    let fixture = try EffectFixture(layer: .container)
    let transport = FakeTransport(
        responses: [.failure(FakeTransportFailure.disconnected)]
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: fixture.invocation,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .unavailable)
    #expect(receipt.issue?.code == "guest-owner-connection-unavailable")
}

@Test
func acceptedOperationRetriesTransientConnectionLossDuringServiceRestart()
    async throws {
    let fixture = try EffectFixture(layer: .guestRuntime)
    let ownerReference = "guest-runtime-release/\(fixture.digest).archive"
    let transport = FakeTransport(
        responses: [
            importedArtifactResponse(fixture, kind: "guest-runtime-release"),
            response(
                status: 202,
                body: guestRuntimeOperation(
                    fixture,
                    ownerReference: ownerReference,
                    state: "pending"
                )
            ),
            .failure(FakeTransportFailure.disconnected),
            response(
                status: 200,
                body: guestRuntimeOperation(
                    fixture,
                    ownerReference: ownerReference,
                    state: "succeeded"
                )
            ),
        ]
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .guestRuntime,
        invocation: fixture.invocation,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .succeeded)
    #expect(await transport.requests.count == 4)
}

@Test
func malformedGuestOperationRemainsExplicitFailure() async throws {
    let fixture = try EffectFixture(layer: .container)
    var malformed = containerOperation(fixture, state: "pending")
    malformed["undeclaredState"] = "must-not-be-ignored"
    let transport = FakeTransport(
        responses: [
            importedArtifactResponse(fixture, kind: "container-image-set"),
            response(status: 202, body: malformed),
        ]
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: fixture.invocation,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .failed)
    #expect(receipt.issue?.code == "guest-owner-response-malformed")
}

@Test
func guestOwnerFailedTerminalStateRemainsFailed() async throws {
    let fixture = try EffectFixture(layer: .container)
    var terminal = containerOperation(fixture, state: "failed")
    terminal["failure"] = [
        "kind": "container-compose-apply-failed",
        "message": "compose rejected the image set",
    ]
    let transport = FakeTransport(
        responses: [
            importedArtifactResponse(fixture, kind: "container-image-set"),
            response(
                status: 202,
                body: containerOperation(fixture, state: "pending")
            ),
            response(status: 200, body: terminal),
        ]
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: fixture.invocation,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .failed)
    #expect(receipt.issue?.code == "container-compose-apply-failed")
    #expect(receipt.issue?.retryable == false)
}

@Test
func guestOwnerUnavailableTerminalStateRemainsUnavailable() async throws {
    let fixture = try EffectFixture(layer: .container)
    var terminal = containerOperation(fixture, state: "unavailable")
    terminal["failure"] = [
        "kind": "docker-service-unavailable",
        "message": "Docker is unavailable",
    ]
    let transport = FakeTransport(
        responses: [
            importedArtifactResponse(fixture, kind: "container-image-set"),
            response(
                status: 202,
                body: containerOperation(fixture, state: "pending")
            ),
            response(status: 200, body: terminal),
        ]
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: fixture.invocation,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .unavailable)
    #expect(receipt.issue?.code == "docker-service-unavailable")
    #expect(receipt.issue?.retryable == true)
}

@Test
func guestOwnerTimeoutRemainsUnavailable() async throws {
    let fixture = try EffectFixture(
        layer: .container,
        operationTimeoutSeconds: 0.01
    )
    let transport = FakeTransport(
        responses: [
            importedArtifactResponse(fixture, kind: "container-image-set"),
            response(
                status: 202,
                body: containerOperation(fixture, state: "pending")
            ),
            response(
                status: 200,
                body: containerOperation(fixture, state: "running")
            ),
        ]
    )

    let receipt = await GuestOwnerLayerEffectExecutor(
        transport: transport
    ).execute(
        layer: .container,
        invocation: fixture.invocation,
        configuration: fixture.configuration
    )

    #expect(receipt.state == .unavailable)
    #expect(receipt.issue?.code == "guest-owner-operation-timeout")
}

private struct EffectFixture {
    let root: URL
    let artifact: URL
    let configurationURL: URL
    let digest: String
    let invocation: ProductUpdateLayerEffectInvocation
    let configuration: LayerEffectConfiguration

    init(
        layer: GuestOwnedLayer,
        operationTimeoutSeconds: Double = 10,
        declaredLayer: String? = nil
    ) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        artifact = root.appendingPathComponent("artifact.tar")
        try Data("artifact".utf8).write(to: artifact)
        digest = "sha256:\(sha256(try Data(contentsOf: artifact)))"
        configurationURL = root.appendingPathComponent("configuration.json")
        let executorId = layer == .container
            ? "container-effect-022"
            : "guest-runtime-effect-022"
        let configurationData = try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion":
                    "vitalserver.guest-owner-layer-effect-configuration/v2",
                "layer": declaredLayer ?? (
                    layer == .container
                        ? "container"
                        : "guest-runtime"
                ),
                "effectExecutorId": executorId,
                "requestTimeoutSeconds": 10,
                "operationTimeoutSeconds": operationTimeoutSeconds,
                "pollIntervalMilliseconds": 50,
                "apply": [
                    "expectedIdentity": "current-021",
                    "targetIdentity": "target-022",
                ],
                "rollback": [
                    "expectedIdentity": "target-022",
                    "targetIdentity": "current-021",
                ],
            ],
            options: [.sortedKeys]
        )
        try configurationData.write(to: configurationURL)
        configuration = try JSONDecoder().decode(
            LayerEffectConfiguration.self,
            from: configurationData
        )
        invocation = ProductUpdateLayerEffectInvocation(
            schemaVersion:
                ProductUpdateExecutionContract
                .layerEffectInvocationSchemaVersion,
            updateId: "update-022",
            layer: layer == .container ? .container : .guestRuntime,
            effectExecutorId: executorId,
            operation: .apply,
            guestControlBaseURL: "http://192.168.64.3:18330/",
            artifactRelativePath: "payload/layer/artifact",
            artifactPath: artifact.path,
            artifactSHA256: digest.replacingOccurrences(
                of: "sha256:",
                with: ""
            ),
            artifactSizeBytes: try Data(contentsOf: artifact).count,
            artifactMediaType: "application/x-tar",
            configurationRelativePath: "payload/layer/configuration.json",
            configurationPath: configurationURL.path,
            configurationSHA256: sha256(configurationData)
        )
    }
}

private func invocation(
    _ fixture: EffectFixture,
    operation: ProductUpdateLayerEffectOperation? = nil,
    artifactSizeBytes: Int? = nil,
    artifactMediaType: String? = nil
) -> ProductUpdateLayerEffectInvocation {
    ProductUpdateLayerEffectInvocation(
        schemaVersion: fixture.invocation.schemaVersion,
        updateId: fixture.invocation.updateId,
        layer: fixture.invocation.layer,
        effectExecutorId: fixture.invocation.effectExecutorId,
        operation: operation ?? fixture.invocation.operation,
        guestControlBaseURL: fixture.invocation.guestControlBaseURL,
        artifactRelativePath: fixture.invocation.artifactRelativePath,
        artifactPath: fixture.invocation.artifactPath,
        artifactSHA256: fixture.invocation.artifactSHA256,
        artifactSizeBytes: artifactSizeBytes ??
            fixture.invocation.artifactSizeBytes,
        artifactMediaType: artifactMediaType ??
            fixture.invocation.artifactMediaType,
        configurationRelativePath:
            fixture.invocation.configurationRelativePath,
        configurationPath: fixture.invocation.configurationPath,
        configurationSHA256: fixture.invocation.configurationSHA256
    )
}

private func importedArtifactResponse(
    _ fixture: EffectFixture,
    kind: String
) -> Result<(Data, HTTPURLResponse), any Error> {
    response(
        status: 201,
        body: [
            "kind": kind,
            "digest": fixture.digest,
            "ownerReference": "\(kind)/\(fixture.digest).archive",
        ]
    )
}

private actor FakeTransport: LayerEffectHTTPTransport {
    struct Request: Sendable {
        let method: String
        let host: String?
        let path: String
        let uploadPath: String?
        let body: Data?
    }

    private var responses: [
        Result<(Data, HTTPURLResponse), any Error>
    ]
    private(set) var requests: [Request] = []

    init(responses: [Result<(Data, HTTPURLResponse), any Error>]) {
        self.responses = responses
    }

    func send(
        _ request: URLRequest,
        uploadFile: URL?
    ) async throws -> (Data, HTTPURLResponse) {
        requests.append(
            Request(
                method: request.httpMethod ?? "",
                host: request.url?.host,
                path: request.url?.path ?? "",
                uploadPath: uploadFile?.path,
                body: request.httpBody
            )
        )
        guard !responses.isEmpty else {
            throw FakeTransportFailure.missingResponse
        }
        return try responses.removeFirst().get()
    }
}

private enum FakeTransportFailure: Error {
    case disconnected
    case missingResponse
}

private func response(
    status: Int,
    body: [String: Any]
) -> Result<(Data, HTTPURLResponse), any Error> {
    let url = URL(string: "http://127.0.0.1:18330/runtime")!
    return .success(
        (
            try! JSONSerialization.data(
                withJSONObject: body,
                options: [.sortedKeys]
            ),
            HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
    )
}

private func containerOperation(
    _ fixture: EffectFixture,
    state: String,
    command: String = "apply",
    expectedIdentity: String = "current-021",
    targetIdentity: String = "target-022"
) -> [String: Any] {
    [
        "operationId": "container-operation-1",
        "command": command,
        "expectedCurrentIdentity": expectedIdentity,
        "target": [
            "identity": targetIdentity,
            "digest": fixture.digest,
        ],
        "state": state,
        "createdAt": "2026-07-29T00:00:00+00:00",
        "updatedAt": "2026-07-29T00:00:01+00:00",
        "failure": NSNull(),
    ]
}

private func guestRuntimeOperation(
    _ fixture: EffectFixture,
    ownerReference: String,
    state: String
) -> [String: Any] {
    [
        "operationId": "guest-runtime-operation-1",
        "command": "apply",
        "expectedActiveIdentity": "current-021",
        "target": [
            "identity": "target-022",
            "archive": ownerReference,
            "digest": fixture.digest,
        ],
        "state": state,
        "createdAt": "2026-07-29T00:00:00+00:00",
        "updatedAt": "2026-07-29T00:00:01+00:00",
        "failure": NSNull(),
    ]
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}
