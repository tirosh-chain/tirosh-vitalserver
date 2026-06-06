import Contracts
import Foundation
import Workflow
import XCTest

final class RuntimeBundlePreparationWorkflowTests: XCTestCase {
    func testVerifyMaterializesVerifiesAndCleansTemporaryRoot() throws {
        let sourceURL = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        let bundleURL = URL(fileURLWithPath: "/tmp/update-bundle")
        let temporaryRoot = URL(fileURLWithPath: "/tmp/materialized")
        let manifest = Self.makeManifest(version: "1.2.3")
        var events: [String] = []
        let workflow = makeWorkflow(
            materialize: { url in
                events.append("materialize:\(url.path)")
                return RuntimeMaterializedBundle(bundleURL: bundleURL, temporaryRoot: temporaryRoot)
            },
            verifyDirectory: { bundle, source in
                events.append("verify:\(bundle.path):\(source.path)")
                return manifest
            },
            cleanupTemporaryRoot: { url in
                events.append("cleanup:\(url.path)")
            },
            log: { message in
                events.append("log:\(message)")
            }
        )

        let result = try workflow.verifyBundle(sourceURL)

        XCTAssertEqual(result, RuntimeBundlePreparationVerification(
            sourceURL: sourceURL,
            bundleURL: bundleURL,
            manifest: manifest
        ))
        XCTAssertEqual(events, [
            "log:bundle verification started path=/input/update-bundle.tar.gz",
            "materialize:/input/update-bundle.tar.gz",
            "verify:/tmp/update-bundle:/input/update-bundle.tar.gz",
            "cleanup:/tmp/materialized",
        ])
    }

    func testStageUsesVerifiedManifestVersionAndCleansTemporaryRoot() throws {
        let sourceURL = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        let bundleURL = URL(fileURLWithPath: "/tmp/update-bundle")
        let destinationURL = URL(fileURLWithPath: "/product/bundles/update-bundle-2.0.0")
        let temporaryRoot = URL(fileURLWithPath: "/tmp/materialized")
        let manifest = Self.makeManifest(version: "2.0.0")
        var events: [String] = []
        let workflow = makeWorkflow(
            materialize: { url in
                events.append("materialize:\(url.path)")
                return RuntimeMaterializedBundle(bundleURL: bundleURL, temporaryRoot: temporaryRoot)
            },
            verifyDirectory: { bundle, source in
                events.append("verify:\(bundle.path):\(source.path)")
                return manifest
            },
            stageBundle: { input in
                events.append(
                    "stage:\(input.sourceURL.path):\(input.bundleURL.path):\(input.manifestVersion)"
                )
                return destinationURL
            },
            cleanupTemporaryRoot: { url in
                events.append("cleanup:\(url.path)")
            },
            log: { message in
                events.append("log:\(message)")
            }
        )

        let result = try workflow.stageBundle(sourceURL)

        XCTAssertEqual(result, RuntimeBundlePreparationStageResult(
            sourceURL: sourceURL,
            bundleURL: bundleURL,
            destinationURL: destinationURL,
            manifest: manifest
        ))
        XCTAssertEqual(events, [
            "log:bundle stage started source=/input/update-bundle.tar.gz",
            "materialize:/input/update-bundle.tar.gz",
            "verify:/tmp/update-bundle:/input/update-bundle.tar.gz",
            "stage:/input/update-bundle.tar.gz:/tmp/update-bundle:2.0.0",
            "cleanup:/tmp/materialized",
        ])
    }

    func testVerifyDoesNotCleanWhenInputIsAlreadyDirectory() throws {
        let sourceURL = URL(fileURLWithPath: "/input/update-bundle")
        let manifest = Self.makeManifest(version: "1.2.3")
        var cleaned = false
        let workflow = makeWorkflow(
            materialize: { url in
                RuntimeMaterializedBundle(bundleURL: url, temporaryRoot: nil)
            },
            verifyDirectory: { _, _ in manifest },
            cleanupTemporaryRoot: { _ in cleaned = true }
        )

        _ = try workflow.verifyBundle(sourceURL)

        XCTAssertFalse(cleaned)
    }

    func testStageCleansMaterializedBundleWhenVerificationFails() {
        let sourceURL = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        let temporaryRoot = URL(fileURLWithPath: "/tmp/materialized")
        var events: [String] = []
        let workflow = makeWorkflow(
            materialize: { _ in
                RuntimeMaterializedBundle(
                    bundleURL: URL(fileURLWithPath: "/tmp/update-bundle"),
                    temporaryRoot: temporaryRoot
                )
            },
            verifyDirectory: { _, _ in
                events.append("verify")
                throw TestBundlePreparationWorkflowError.verifyFailed
            },
            stageBundle: { _ in
                events.append("stage")
                return URL(fileURLWithPath: "/product/bundles/update-bundle-1.2.3")
            },
            cleanupTemporaryRoot: { url in
                events.append("cleanup:\(url.path)")
            }
        )

        XCTAssertThrowsError(try workflow.stageBundle(sourceURL)) { error in
            XCTAssertEqual(error as? TestBundlePreparationWorkflowError, .verifyFailed)
        }
        XCTAssertEqual(events, ["verify", "cleanup:/tmp/materialized"])
    }

    private func makeWorkflow(
        materialize: @escaping (URL) throws -> RuntimeMaterializedBundle = { url in
            RuntimeMaterializedBundle(bundleURL: url, temporaryRoot: nil)
        },
        verifyDirectory: @escaping (URL, URL) throws -> UpdateBundleManifest = { _, _ in
            RuntimeBundlePreparationWorkflowTests.makeManifest(version: "1.2.3")
        },
        stageBundle: @escaping (RuntimeBundleStagingInput) throws -> URL = { _ in
            URL(fileURLWithPath: "/product/bundles/update-bundle-1.2.3")
        },
        cleanupTemporaryRoot: @escaping (URL) -> Void = { _ in },
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeBundlePreparationWorkflow {
        RuntimeBundlePreparationWorkflow(
            operations: RuntimeBundlePreparationWorkflowOperations(
                materialize: materialize,
                cleanupTemporaryRoot: cleanupTemporaryRoot,
                verifyDirectory: verifyDirectory,
                stageBundle: stageBundle,
                log: log
            )
        )
    }

    private static func makeManifest(version: String) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: version,
            releaseLabel: version,
            targetPlatform: "macos-arm64",
            components: ["runtime": version],
            createdAt: "2026-06-05T00:00:00Z",
            artifacts: [],
            migrations: []
        )
    }
}

private enum TestBundlePreparationWorkflowError: Error, Equatable {
    case verifyFailed
}
