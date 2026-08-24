import Contracts
import Domain
import XCTest

final class UpdateBootstrapBundleClosurePolicyTests: XCTestCase {
    func testStructureAcceptsEnvelopeOwnedPayloadFiles() throws {
        try UpdateBootstrapBundleClosurePolicy.validateStructure(
            envelope: envelope(),
            entries: bundleEntries()
        )
    }

    func testStructureAllowsUnknownRegularFilesUntilExactClosure() throws {
        var entries = bundleEntries()
        entries.append(
            .init(relativePath: "payload/layers/unknown", kind: .regularFile)
        )
        try UpdateBootstrapBundleClosurePolicy.validateStructure(
            envelope: envelope(),
            entries: entries
        )
    }

    func testStructureRejectsMissingEnvelopeOwnedFiles() {
        assertStructureError(
            entries: [
                .init(
                    relativePath: UpdateBootstrapBundleLayout.envelopeRelativePath,
                    kind: .regularFile
                ),
            ],
            expected: .fileClosureMismatch(
                missing: ([
                    "payload/bin/vitalserver-update",
                    "payload/update-specification.json",
                ] + envelope().payloadArtifacts.map(\.relativePath)).sorted(),
                unknown: []
            )
        )
    }

    func testExactClosureAcceptsEnvelopeOwnedPayload() throws {
        try UpdateBootstrapBundleClosurePolicy.validateExact(
            envelope: envelope(),
            entries: bundleEntries()
        )
    }

    func testDeclaredArtifactsAreTheSpecificationOwnedLayerClosure() {
        let specification = ProductUpdateSpecification(
            schemaVersion: "vitalserver.product-update-specification/v1",
            id: "helper-update-specification",
            bootstrapEnvelopeId: "helper-update-0.2.2",
            layerPlan: [
                ProductUpdateLayerPlan(
                    layer: .container,
                    dependsOn: [],
                    artifact: UpdateBootstrapArtifact(
                        id: "container-artifact",
                        relativePath: "payload/layers/container/artifact",
                        sha256: String(repeating: "a", count: 64),
                        sizeBytes: 10,
                        mediaType: "application/octet-stream"
                    ),
                    effectExecutor: ProductUpdateLayerEffectExecutor(
                        id: "container-executor",
                        relativePath: "payload/layers/container/effect-executor",
                        sha256: String(repeating: "b", count: 64),
                        sizeBytes: 10,
                        mediaType:
                            "application/vnd.tirosh.vitalserver.update-layer-effect-executor",
                        configurationArtifact: UpdateBootstrapArtifact(
                            id: "container-configuration",
                            relativePath:
                                "payload/layers/container/effect-configuration.json",
                            sha256: String(repeating: "c", count: 64),
                            sizeBytes: 10,
                            mediaType:
                                "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"
                        )
                    ),
                    rollback: ProductUpdateLayerRollbackPlan(
                        state: .available,
                        artifact: UpdateBootstrapArtifact(
                            id: "container-rollback",
                            relativePath: "payload/layers/container/rollback-artifact",
                            sha256: String(repeating: "d", count: 64),
                            sizeBytes: 10,
                            mediaType: "application/octet-stream"
                        ),
                        reason: nil
                    )
                )
            ]
        )

        XCTAssertEqual(
            UpdateBootstrapBundleClosurePolicy.declaredArtifacts(specification).map(\.id),
            [
                "container-artifact",
                "container-executor",
                "container-configuration",
                "container-rollback",
            ]
        )
    }

    func testExactClosureRejectsUnknownPayloadFile() {
        var entries = bundleEntries()
        entries.append(
            .init(relativePath: "payload/layers/unknown", kind: .regularFile)
        )

        XCTAssertThrowsError(
            try UpdateBootstrapBundleClosurePolicy.validateExact(
                envelope: envelope(),
                entries: entries
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapBundleClosureError,
                .fileClosureMismatch(
                    missing: [],
                    unknown: ["payload/layers/unknown"]
                )
            )
        }
    }

    func testRejectsUnsupportedEntryKind() {
        assertStructureError(
            entries: [
                .init(relativePath: "payload/link", kind: .other("symbolic-link")),
            ],
            expected: .unsupportedEntry(
                path: "payload/link",
                kind: "symbolic-link"
            )
        )
    }

    func testRejectsUnsafeAndDuplicateEntryPaths() {
        assertStructureError(
            entries: [.init(relativePath: "../escape", kind: .regularFile)],
            expected: .invalidEntryPath("../escape")
        )
        assertStructureError(
            entries: [
                .init(relativePath: "payload", kind: .directory),
                .init(relativePath: "payload", kind: .directory),
            ],
            expected: .duplicateEntry("payload")
        )
    }

    func testRejectsEnvelopeThatAssignsBothArtifactsToOnePath() {
        var value = envelope()
        value = UpdateBootstrapEnvelope(
            schemaVersion: value.schemaVersion,
            id: value.id,
            productId: value.productId,
            target: value.target,
            targetRelease: value.targetRelease,
            layerOrder: value.layerOrder,
            nextUpdaterArtifact: value.nextUpdaterArtifact,
            specification: UpdateBootstrapArtifact(
                id: value.specification.id,
                relativePath: value.nextUpdaterArtifact.relativePath,
                sha256: value.specification.sha256,
                sizeBytes: value.specification.sizeBytes,
                mediaType: value.specification.mediaType
            ),
            payloadArtifacts: value.payloadArtifacts,
            signature: value.signature,
            issuedAt: value.issuedAt
        )

        XCTAssertThrowsError(
            try UpdateBootstrapBundleClosurePolicy.validateStructure(
                envelope: value,
                entries: []
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapBundleClosureError,
                .duplicateArtifactPath("payload/bin/vitalserver-update")
            )
        }
    }

    private func assertStructureError(
        entries: [UpdateBootstrapBundleEntry],
        expected: UpdateBootstrapBundleClosureError
    ) {
        XCTAssertThrowsError(
            try UpdateBootstrapBundleClosurePolicy.validateStructure(
                envelope: envelope(),
                entries: entries
            )
        ) { error in
            XCTAssertEqual(error as? UpdateBootstrapBundleClosureError, expected)
        }
    }
}

private func bundleEntries() -> [UpdateBootstrapBundleEntry] {
    [
        .init(relativePath: "payload", kind: .directory),
        .init(relativePath: "payload/bin", kind: .directory),
        .init(
            relativePath: UpdateBootstrapBundleLayout.envelopeRelativePath,
            kind: .regularFile
        ),
        .init(
            relativePath: "payload/bin/vitalserver-update",
            kind: .regularFile
        ),
        .init(
            relativePath: "payload/update-specification.json",
            kind: .regularFile
        ),
    ] + envelope().payloadArtifacts.map {
        .init(relativePath: $0.relativePath, kind: .regularFile)
    }
}

private func envelope() -> UpdateBootstrapEnvelope {
    UpdateBootstrapEnvelope(
        schemaVersion: "v2",
        id: "helper-update-0.2.2",
        productId: "ai.tirosh.vitalserver.helper",
        target: .init(platform: .macos, architecture: .arm64),
        targetRelease: .init(
            productVersion: "0.2.2",
            runtimeVersion: "0.2.2"
        ),
        layerOrder: [.container, .guestRuntime, .hostPlatform],
        nextUpdaterArtifact: .init(
            id: "helper-next-updater",
            relativePath: "payload/bin/vitalserver-update",
            sha256: String(repeating: "a", count: 64),
            sizeBytes: 100,
            mediaType: "application/octet-stream"
        ),
        specification: .init(
            id: "helper-update-specification",
            relativePath: "payload/update-specification.json",
            sha256: String(repeating: "b", count: 64),
            sizeBytes: 200,
            mediaType: "application/json"
        ),
        payloadArtifacts: [
            UpdateBootstrapArtifact(
                id: "host-platform-apply",
                relativePath: "payload/layers/host-platform/apply.bin",
                sha256: String(repeating: "d", count: 64),
                sizeBytes: 30,
                mediaType: "application/octet-stream"
            ),
        ],
        signature: .init(
            algorithm: .ed25519,
            keyId: "helper-release-key-2026",
            signedSha256: String(repeating: "c", count: 64),
            value: "signature"
        ),
        issuedAt: "2026-07-27T00:00:00Z"
    )
}
