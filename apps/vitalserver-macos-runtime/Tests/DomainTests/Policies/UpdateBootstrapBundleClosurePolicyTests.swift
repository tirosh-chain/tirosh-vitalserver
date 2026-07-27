import Contracts
import Domain
import XCTest

final class UpdateBootstrapBundleClosurePolicyTests: XCTestCase {
    func testAcceptsOnlyEnvelopeAndDeclaredArtifactsAsRegularFiles() throws {
        try UpdateBootstrapBundleClosurePolicy.validate(
            envelope: envelope(),
            entries: [
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
            ]
        )
    }

    func testRejectsMissingAndUnknownRegularFilesAsExactClosureMismatch() {
        assertClosureError(
            entries: [
                .init(
                    relativePath: UpdateBootstrapBundleLayout.envelopeRelativePath,
                    kind: .regularFile
                ),
                .init(relativePath: "payload/unknown", kind: .regularFile),
            ],
            expected: .fileClosureMismatch(
                missing: [
                    "payload/bin/vitalserver-update",
                    "payload/update-specification.json",
                ],
                unknown: ["payload/unknown"]
            )
        )
    }

    func testRejectsUnsupportedEntryKind() {
        assertClosureError(
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
        assertClosureError(
            entries: [.init(relativePath: "../escape", kind: .regularFile)],
            expected: .invalidEntryPath("../escape")
        )
        assertClosureError(
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
            signature: value.signature,
            issuedAt: value.issuedAt
        )

        XCTAssertThrowsError(
            try UpdateBootstrapBundleClosurePolicy.validate(
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

    private func assertClosureError(
        entries: [UpdateBootstrapBundleEntry],
        expected: UpdateBootstrapBundleClosureError
    ) {
        XCTAssertThrowsError(
            try UpdateBootstrapBundleClosurePolicy.validate(
                envelope: envelope(),
                entries: entries
            )
        ) { error in
            XCTAssertEqual(error as? UpdateBootstrapBundleClosureError, expected)
        }
    }
}

private func envelope() -> UpdateBootstrapEnvelope {
    UpdateBootstrapEnvelope(
        schemaVersion: "v1",
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
        signature: .init(
            algorithm: .ed25519,
            keyId: "helper-release-key-2026",
            signedSha256: String(repeating: "c", count: 64),
            value: "signature"
        ),
        issuedAt: "2026-07-27T00:00:00Z"
    )
}
