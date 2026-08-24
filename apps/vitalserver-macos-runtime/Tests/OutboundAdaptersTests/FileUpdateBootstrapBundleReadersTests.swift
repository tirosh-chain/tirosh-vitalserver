import Application
import Contracts
import Foundation
import OutboundAdapters
import XCTest

final class FileUpdateBootstrapBundleReadersTests: XCTestCase {
    func testEnvelopeReaderDecodesStrictEnvelopeFromDeclaredPath() throws {
        let root = URL(fileURLWithPath: "/bundle")
        let envelope = outboundEnvelope()
        let store = UpdateBootstrapReaderFileStore(
            pathStates: [
                "/bundle/bootstrap-envelope.json": .file,
            ],
            data: [
                "/bundle/bootstrap-envelope.json": try JSONEncoder().encode(envelope),
            ]
        )

        XCTAssertEqual(
            FileUpdateBootstrapEnvelopeReader(
                bundleRoot: root,
                fileStore: store
            ).readEnvelope(),
            .loaded(envelope)
        )
    }

    func testEnvelopeReaderKeepsInspectionReadAndDecodeFailuresDistinct() {
        let root = URL(fileURLWithPath: "/bundle")
        XCTAssertEqual(
            FileUpdateBootstrapEnvelopeReader(
                bundleRoot: root,
                fileStore: UpdateBootstrapReaderFileStore(
                    pathStates: [
                        "/bundle/bootstrap-envelope.json":
                            .inspectFailed("permission denied"),
                    ]
                )
            ).readEnvelope(),
            .inspectionFailed(
                path: "/bundle/bootstrap-envelope.json",
                reason: "permission denied"
            )
        )

        let readFailure = FileUpdateBootstrapEnvelopeReader(
            bundleRoot: root,
            fileStore: UpdateBootstrapReaderFileStore(
                pathStates: [
                    "/bundle/bootstrap-envelope.json": .file,
                ],
                readFailures: [
                    "/bundle/bootstrap-envelope.json": "I/O error",
                ]
            )
        ).readEnvelope()
        guard case .readFailed(let readPath, let readReason) = readFailure else {
            return XCTFail("expected read failure, got \(readFailure)")
        }
        XCTAssertEqual(readPath, "/bundle/bootstrap-envelope.json")
        XCTAssertTrue(readReason.contains("I/O error"))

        let decodeFailure = FileUpdateBootstrapEnvelopeReader(
            bundleRoot: root,
            fileStore: UpdateBootstrapReaderFileStore(
                pathStates: [
                    "/bundle/bootstrap-envelope.json": .file,
                ],
                data: [
                    "/bundle/bootstrap-envelope.json":
                        Data(#"{"unsupported":true}"#.utf8),
                ]
            )
        ).readEnvelope()
        guard case .decodeFailed(let decodePath, _) = decodeFailure else {
            return XCTFail("expected decode failure, got \(decodeFailure)")
        }
        XCTAssertEqual(decodePath, "/bundle/bootstrap-envelope.json")
    }

    func testEntriesReaderPreservesRootAndListingFailures() {
        let root = URL(fileURLWithPath: "/bundle")
        let missing = FileUpdateBootstrapBundleEntriesReader(
            bundleRoot: root,
            fileStore: UpdateBootstrapReaderFileStore(
                pathStates: ["/bundle": .missing]
            ),
            entryEnumerator: StubUpdateBootstrapEntryEnumerator(entries: [])
        )
        XCTAssertEqual(missing.readEntries(), .rootMissing(path: "/bundle"))

        let listing = FileUpdateBootstrapBundleEntriesReader(
            bundleRoot: root,
            fileStore: UpdateBootstrapReaderFileStore(
                pathStates: ["/bundle": .directory]
            ),
            entryEnumerator: StubUpdateBootstrapEntryEnumerator(
                error: UpdateBootstrapReaderTestError("listing denied")
            )
        ).readEntries()
        guard case .listingFailed(let path, let reason) = listing else {
            return XCTFail("expected listing failure, got \(listing)")
        }
        XCTAssertEqual(path, "/bundle")
        XCTAssertTrue(reason.contains("listing denied"))
    }

    func testSystemEnumeratorReportsRegularDirectoriesAndSymbolicLinksExplicitly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let payload = root.appendingPathComponent("payload")
        try FileManager.default.createDirectory(
            at: payload,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let artifact = payload.appendingPathComponent("artifact")
        try Data("artifact".utf8).write(to: artifact)
        try FileManager.default.createSymbolicLink(
            at: payload.appendingPathComponent("artifact-link"),
            withDestinationURL: artifact
        )

        let entries = try SystemUpdateBootstrapBundleEntryEnumerator()
            .entries(beneath: root)

        XCTAssertEqual(
            entries,
            [
                .init(relativePath: "payload", kind: .directory),
                .init(
                    relativePath: "payload/artifact",
                    kind: .regularFile
                ),
                .init(
                    relativePath: "payload/artifact-link",
                    kind: .other("symbolic-link")
                ),
            ]
        )
    }
}

private final class UpdateBootstrapReaderFileStore:
    RuntimeFileReading,
    @unchecked Sendable
{
    let pathStates: [String: RuntimePathState]
    let data: [String: Data]
    let readFailures: [String: String]

    init(
        pathStates: [String: RuntimePathState],
        data: [String: Data] = [:],
        readFailures: [String: String] = [:]
    ) {
        self.pathStates = pathStates
        self.data = data
        self.readFailures = readFailures
    }

    func pathState(at url: URL) -> RuntimePathState {
        pathStates[url.path] ?? .missing
    }

    func readData(_ url: URL) throws -> Data {
        if let reason = readFailures[url.path] {
            throw UpdateBootstrapReaderTestError(reason)
        }
        guard let data = data[url.path] else {
            throw UpdateBootstrapReaderTestError("undeclared test data")
        }
        return data
    }

    func fileExists(_ url: URL) -> Bool { false }
    func directoryExists(_ url: URL) -> Bool { false }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func fileState(atPath path: String) -> RuntimeFileState { .missing }
    func fileState(at url: URL) -> RuntimeFileState { .missing }
    func readUTF8Text(_ url: URL) throws -> String {
        throw UpdateBootstrapReaderTestError("unsupported")
    }
    func fileSize(_ url: URL) throws -> UInt64 {
        throw UpdateBootstrapReaderTestError("unsupported")
    }
    func modificationDate(_ url: URL) throws -> Date {
        throw UpdateBootstrapReaderTestError("unsupported")
    }
}

private struct StubUpdateBootstrapEntryEnumerator:
    UpdateBootstrapBundleEntryEnumerating
{
    let entries: [UpdateBootstrapBundleEntry]
    let error: Error?

    init(
        entries: [UpdateBootstrapBundleEntry] = [],
        error: Error? = nil
    ) {
        self.entries = entries
        self.error = error
    }

    func entries(
        beneath root: URL
    ) throws -> [UpdateBootstrapBundleEntry] {
        if let error {
            throw error
        }
        return entries
    }
}

private struct UpdateBootstrapReaderTestError: Error, LocalizedError {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var errorDescription: String? { value }
}

private func outboundEnvelope() -> UpdateBootstrapEnvelope {
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
