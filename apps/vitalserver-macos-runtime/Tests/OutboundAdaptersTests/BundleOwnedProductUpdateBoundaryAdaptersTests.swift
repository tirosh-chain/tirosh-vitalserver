import Application
import Contracts
import CryptoKit
import Foundation
import OutboundAdapters
import XCTest

final class BundleOwnedProductUpdateBoundaryAdaptersTests: XCTestCase {
    func testInputReaderAuthenticatesSpecificationBeforeDecoding() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = root.appendingPathComponent("handoff")
        let specificationDirectory = root.appendingPathComponent("spec")
        try FileManager.default.createDirectory(
            at: handoff,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: specificationDirectory,
            withIntermediateDirectories: true
        )
        let specification = ProductUpdateSpecification(
            schemaVersion: "vitalserver.product-update-specification/v1",
            id: "specification-42",
            bootstrapEnvelopeId: "envelope-42",
            layerPlan: []
        )
        let specificationData = try JSONEncoder().encode(specification)
        try specificationData.write(
            to: specificationDirectory.appendingPathComponent("update.json")
        )
        let invocation = invocation(
            specificationSHA256: sha256(specificationData)
        )
        let invocationURL = handoff.appendingPathComponent("invocation.json")
        try JSONEncoder().encode(invocation).write(to: invocationURL)
        let store = SystemRuntimeFileStore()
        let reader = BundleOwnedProductUpdateInputReader(
            operations: BundleOwnedProductUpdateInputReadOperations(
                pathState: store.pathState,
                fileSize: store.fileSize,
                readData: store.readData
            )
        )

        let input = try reader.read(invocationURL: invocationURL)

        XCTAssertEqual(input.invocation, invocation)
        XCTAssertEqual(input.specification, specification)
        XCTAssertEqual(input.stagedBundleRoot, root.standardizedFileURL)
    }

    func testInputReaderDoesNotDecodeSpecificationWithWrongDigest() throws {
        let invocationData = try JSONEncoder().encode(invocation())
        let specificationData = try JSONEncoder().encode(
            ProductUpdateSpecification(
                schemaVersion: "vitalserver.product-update-specification/v1",
                id: "specification-42",
                bootstrapEnvelopeId: "envelope-42",
                layerPlan: []
            )
        )
        let reader = BundleOwnedProductUpdateInputReader(
            operations: BundleOwnedProductUpdateInputReadOperations(
                pathState: { _ in .file },
                fileSize: { url in
                    UInt64(
                        url.lastPathComponent == "invocation.json"
                            ? invocationData.count
                            : specificationData.count
                    )
                },
                readData: { url in
                    url.lastPathComponent == "invocation.json"
                        ? invocationData
                        : specificationData
                }
            )
        )

        XCTAssertThrowsError(
            try reader.read(
                invocationURL: URL(
                    fileURLWithPath:
                        "/updates/update-42/handoff/invocation.json"
                )
            )
        ) { error in
            guard case let .digestMismatch(path, expected, actual) =
                error as? BundleOwnedProductUpdateInputReadError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(path, "/updates/update-42/spec/update.json")
            XCTAssertEqual(expected, String(repeating: "b", count: 64))
            XCTAssertEqual(actual, self.sha256(specificationData))
        }
    }

    func testEffectExecutorUsesFixedProtocolAndRequiresTypedReceipt() throws {
        let documents = TestDocumentStore()
        var command: (String, [String])?
        let request = effectRequest()
        let receipt = ProductUpdateLayerEffectReceipt(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: request.updateId,
            layer: request.layer,
            effectExecutorId: request.effectExecutor.id,
            operation: request.operation,
            artifactSHA256: request.artifact.sha256,
            state: .succeeded,
            observedAt: "2026-07-28T00:00:00Z",
            evidence: ProductUpdateEvidenceReference(
                kind: "executor-receipt",
                id: "receipt-1"
            ),
            issue: nil
        )
        let executor = BundleOwnedProductUpdateLayerEffectExecutor(
            stagedBundleRoot: URL(fileURLWithPath: "/updates/update-42"),
            operations: effectOperations(
                documents: documents,
                run: { executable, arguments in
                    command = (executable, arguments)
                    documents.values[arguments[4]] =
                        try! JSONEncoder().encode(receipt)
                    return RuntimeProcessResult(
                        exitCode: 0,
                        stdout: "",
                        stderr: ""
                    )
                }
            )
        )

        XCTAssertEqual(executor.execute(request), .completed(receipt))
        XCTAssertEqual(command?.0, "/updates/update-42/executors/host")
        XCTAssertEqual(command?.1, [
            "execute",
            "--request",
            "/updates/update-42/handoff/layer-effects/host-platform-apply-request.json",
            "--receipt",
            "/updates/update-42/handoff/layer-effects/host-platform-apply-receipt.json",
        ])
        let invocation = try JSONDecoder().decode(
            ProductUpdateLayerEffectInvocation.self,
            from: try XCTUnwrap(documents.values[command!.1[2]])
        )
        XCTAssertEqual(
            invocation.schemaVersion,
            ProductUpdateExecutionContract.layerEffectInvocationSchemaVersion
        )
        XCTAssertEqual(invocation.artifactSHA256, request.artifact.sha256)
        XCTAssertEqual(invocation.artifactSizeBytes, request.artifact.sizeBytes)
        XCTAssertEqual(invocation.artifactMediaType, request.artifact.mediaType)
        XCTAssertEqual(
            invocation.artifactPath,
            "/updates/update-42/payload/host.pkg"
        )
        XCTAssertEqual(
            invocation.configurationPath,
            "/updates/update-42/config/host.json"
        )
    }

    func testZeroExitWithoutReceiptIsUnavailableNotSuccess() {
        let documents = TestDocumentStore()
        let executor = BundleOwnedProductUpdateLayerEffectExecutor(
            stagedBundleRoot: URL(fileURLWithPath: "/updates/update-42"),
            operations: effectOperations(
                documents: documents,
                run: { _, _ in
                    RuntimeProcessResult(
                        exitCode: 0,
                        stdout: "",
                        stderr: ""
                    )
                }
            )
        )

        XCTAssertEqual(
            executor.execute(effectRequest()),
            .unavailable(
                reason:
                    "effect receipt unavailable after zero exit: receipt is missing"
            )
        )
    }

    func testCompletionPublisherWritesReportBeforeCorrelatedReceipt() throws {
        var paths: [String] = []
        var documents: [String: Data] = [:]
        let publisher = BundleOwnedProductUpdateCompletionPublisher(
            stagedBundleRoot: URL(fileURLWithPath: "/updates/update-42"),
            operations:
                BundleOwnedProductUpdateCompletionPublishOperations(
                    pathState: { url in
                        documents[url.path] == nil ? .missing : .file
                    },
                    createDirectory: { _, _ in },
                    writeData: { data, url, options in
                        XCTAssertTrue(options.contains(.atomic))
                        paths.append(url.path)
                        documents[url.path] = data
                    }
                )
        )
        let report = executionReport()

        let published = try publisher.publish(
            report: report,
            invocation: invocation()
        )

        XCTAssertEqual(paths, [
            "/updates/update-42/handoff/product-update-execution-report.json",
            "/updates/update-42/handoff/completion-receipt.json",
        ])
        let receipt = try JSONDecoder().decode(
            UpdateBootstrapCompletionReceipt.self,
            from: try XCTUnwrap(documents[published.receiptURL.path])
        )
        XCTAssertEqual(receipt.updateId, report.updateId)
        XCTAssertEqual(receipt.outcome, .succeeded)
        XCTAssertEqual(receipt.reportSHA256, published.reportSHA256)
        XCTAssertNil(receipt.failureReason)
    }

    private func effectOperations(
        documents: TestDocumentStore,
        run: @escaping (String, [String]) -> RuntimeProcessResult
    ) -> BundleOwnedProductUpdateLayerEffectExecutorOperations {
        BundleOwnedProductUpdateLayerEffectExecutorOperations(
            observe: { artifact in
                .available(
                    sha256: artifact.sha256,
                    sizeBytes: artifact.sizeBytes
                )
            },
            fileState: { _ in .executable },
            pathState: { url in
                documents.values[url.path] == nil ? .missing : .file
            },
            createDirectory: { _, _ in },
            writeData: { data, url, _ in
                documents.values[url.path] = data
            },
            fileSize: { url in
                guard let data = documents.values[url.path] else {
                    throw TestReadError.missing
                }
                return UInt64(data.count)
            },
            readData: { url in
                guard let data = documents.values[url.path] else {
                    throw TestReadError.missing
                }
                return data
            },
            run: run
        )
    }

    private func effectRequest() -> ProductUpdateLayerEffectRequest {
        ProductUpdateLayerEffectRequest(
            updateId: "update-42",
            layer: .hostPlatform,
            effectExecutor: ProductUpdateLayerEffectExecutor(
                id: "host-executor",
                relativePath: "executors/host",
                sha256: String(repeating: "e", count: 64),
                sizeBytes: 100,
                mediaType: "application/x-executable",
                configurationArtifact: artifact(
                    id: "host-config",
                    path: "config/host.json",
                    digest: "c"
                )
            ),
            operation: .apply,
            artifact: artifact(
                id: "host-payload",
                path: "payload/host.pkg",
                digest: "a"
            )
        )
    }

    private func artifact(
        id: String,
        path: String,
        digest: Character
    ) -> UpdateBootstrapArtifact {
        UpdateBootstrapArtifact(
            id: id,
            relativePath: path,
            sha256: String(repeating: digest, count: 64),
            sizeBytes: 100,
            mediaType: "application/octet-stream"
        )
    }

    private func invocation(
        specificationSHA256: String = String(repeating: "b", count: 64)
    ) -> UpdateBootstrapHandoffInvocation {
        UpdateBootstrapHandoffInvocation(
            schemaVersion: "vitalserver.update-bootstrap-handoff/v1",
            updateId: "update-42",
            operationId: "operation-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            bootstrapSignedSHA256: String(repeating: "a", count: 64),
            updateSpecificationSHA256: specificationSHA256,
            layerOrder: [.hostPlatform],
            expectedJournalRevision: 3,
            updaterRelativePath: "updater/next-updater",
            specificationRelativePath: "spec/update.json",
            completionReceiptRelativePath:
                "handoff/completion-receipt.json"
        )
    }

    private func executionReport() -> ProductUpdateExecutionReport {
        ProductUpdateExecutionReport(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: "update-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            updateSpecificationSHA256: String(repeating: "b", count: 64),
            state: .succeeded,
            startedAt: "2026-07-28T00:00:00Z",
            finishedAt: "2026-07-28T00:01:00Z",
            applyReceipts: [],
            rollbackReceipts: [],
            rollback: ProductUpdateRollbackEvidence(
                state: .notRequired,
                observedAt: "2026-07-28T00:01:00Z",
                evidence: nil,
                issue: nil
            ),
            failure: nil
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private enum TestReadError: Error {
    case missing
}

private final class TestDocumentStore {
    var values: [String: Data] = [:]
}
