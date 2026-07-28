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
func digestMismatchFailsWithoutCallingGuest() async throws {
    let fixture = try EffectFixture(layer: .container)
    let transport = FakeTransport(responses: [])
    let invalid = ProductUpdateLayerEffectInvocation(
        schemaVersion: fixture.invocation.schemaVersion,
        updateId: fixture.invocation.updateId,
        layer: fixture.invocation.layer,
        effectExecutorId: fixture.invocation.effectExecutorId,
        operation: fixture.invocation.operation,
        artifactRelativePath: fixture.invocation.artifactRelativePath,
        artifactPath: fixture.invocation.artifactPath,
        artifactSHA256: String(repeating: "0", count: 64),
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
                    "vitalserver.guest-owner-layer-effect-configuration/v1",
                "layer": declaredLayer ?? (
                    layer == .container
                        ? "container"
                        : "guest-runtime"
                ),
                "effectExecutorId": executorId,
                "guestControlBaseURL": "http://127.0.0.1:18330/",
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
            artifactRelativePath: "payload/layer/artifact",
            artifactPath: artifact.path,
            artifactSHA256: digest.replacingOccurrences(
                of: "sha256:",
                with: ""
            ),
            configurationRelativePath: "payload/layer/configuration.json",
            configurationPath: configurationURL.path,
            configurationSHA256: sha256(configurationData)
        )
    }
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
        let path: String
        let uploadPath: String?
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
                path: request.url?.path ?? "",
                uploadPath: uploadFile?.path
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
    state: String
) -> [String: Any] {
    [
        "operationId": "container-operation-1",
        "command": "apply",
        "expectedCurrentIdentity": "current-021",
        "target": [
            "identity": "target-022",
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
