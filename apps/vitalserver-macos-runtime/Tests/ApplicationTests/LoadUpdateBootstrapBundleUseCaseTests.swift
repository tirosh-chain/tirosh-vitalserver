import Application
import Contracts
import Domain
import XCTest

final class LoadUpdateBootstrapBundleUseCaseTests: XCTestCase {
    func testReturnsEnvelopeAfterExactBundleClosureIsValidated() throws {
        let envelope = applicationEnvelope()
        let entries = exactEntries(for: envelope)

        let loaded = try LoadUpdateBootstrapBundleUseCase().load(
            envelopeRead: .loaded(envelope),
            entriesRead: .loaded(entries)
        )

        XCTAssertEqual(
            loaded,
            LoadedUpdateBootstrapBundle(
                envelope: envelope,
                entries: entries
            )
        )
    }

    func testPreservesEnvelopeAndDirectoryReadFailures() {
        assertError(
            envelopeRead: .missing(path: "/bundle/bootstrap-envelope.json"),
            entriesRead: .loaded([]),
            expected: .envelopeMissing(
                path: "/bundle/bootstrap-envelope.json"
            )
        )
        assertError(
            envelopeRead: .decodeFailed(
                path: "/bundle/bootstrap-envelope.json",
                reason: "unsupported field"
            ),
            entriesRead: .loaded([]),
            expected: .envelopeDecodeFailed(
                path: "/bundle/bootstrap-envelope.json",
                reason: "unsupported field"
            )
        )
        assertError(
            envelopeRead: .loaded(applicationEnvelope()),
            entriesRead: .listingFailed(
                path: "/bundle",
                reason: "permission denied"
            ),
            expected: .bundleListingFailed(
                path: "/bundle",
                reason: "permission denied"
            )
        )
    }

    func testReportsExactClosureFailureWithoutFlatteningIt() {
        assertError(
            envelopeRead: .loaded(applicationEnvelope()),
            entriesRead: .loaded([]),
            expected: .closureInvalid(
                .fileClosureMismatch(
                    missing: [
                        "bootstrap-envelope.json",
                        "payload/bin/vitalserver-update",
                        "payload/update-specification.json",
                    ],
                    unknown: []
                )
            )
        )
    }

    private func assertError(
        envelopeRead: UpdateBootstrapEnvelopeReadResult,
        entriesRead: UpdateBootstrapBundleEntriesReadResult,
        expected: LoadUpdateBootstrapBundleError
    ) {
        XCTAssertThrowsError(
            try LoadUpdateBootstrapBundleUseCase().load(
                envelopeRead: envelopeRead,
                entriesRead: entriesRead
            )
        ) { error in
            XCTAssertEqual(error as? LoadUpdateBootstrapBundleError, expected)
        }
    }
}

private func exactEntries(
    for envelope: UpdateBootstrapEnvelope
) -> [UpdateBootstrapBundleEntry] {
    [
        .init(
            relativePath: UpdateBootstrapBundleLayout.envelopeRelativePath,
            kind: .regularFile
        ),
        .init(
            relativePath: envelope.nextUpdaterArtifact.relativePath,
            kind: .regularFile
        ),
        .init(
            relativePath: envelope.specification.relativePath,
            kind: .regularFile
        ),
    ] + envelope.payloadArtifacts.map {
        .init(relativePath: $0.relativePath, kind: .regularFile)
    }
}

private func applicationEnvelope() -> UpdateBootstrapEnvelope {
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
        payloadArtifacts: [],
        signature: .init(
            algorithm: .ed25519,
            keyId: "helper-release-key-2026",
            signedSha256: String(repeating: "c", count: 64),
            value: "signature"
        ),
        issuedAt: "2026-07-27T00:00:00Z"
    )
}
