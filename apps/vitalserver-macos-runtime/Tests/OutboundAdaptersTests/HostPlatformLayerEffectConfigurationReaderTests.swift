import Application
import Contracts
import CryptoKit
import Domain
import Foundation
import OutboundAdapters
import XCTest

final class HostPlatformLayerEffectConfigurationReaderTests: XCTestCase {
    func testReadsDigestBoundHostPlatformConfiguration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = makeConfiguration(
            databasePath: root.appendingPathComponent("state.sqlite").path
        )
        let data = try JSONEncoder().encode(configuration)
        let relativePath = "payload/host-platform-configuration.json"
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("payload"),
            withIntermediateDirectories: true
        )
        try data.write(to: root.appendingPathComponent(relativePath))
        let specification = makeSpecification(
            configurationRelativePath: relativePath,
            configurationSHA256: sha256(data)
        )
        let store = SystemRuntimeFileStore()
        let reader = HostPlatformLayerEffectConfigurationReader(
            operations: BundleOwnedProductUpdateInputReadOperations(
                pathState: store.pathState,
                fileSize: store.fileSize,
                readData: store.readData
            )
        )

        let documents = try reader.read(
            specification: specification,
            stagedBundleRoot: root
        )

        XCTAssertEqual(documents.layerPlan.layer, .hostPlatform)
        XCTAssertEqual(documents.configuration, configuration)
    }

    func testRejectsMissingHostPlatformLayerWithoutGuessingAPath() {
        let reader = HostPlatformLayerEffectConfigurationReader(
            operations: BundleOwnedProductUpdateInputReadOperations(
                pathState: { _ in .missing },
                fileSize: { _ in 0 },
                readData: { _ in Data() }
            )
        )
        let specification = ProductUpdateSpecification(
            schemaVersion: "vitalserver.product-update-specification/v1",
            id: "specification-42",
            bootstrapEnvelopeId: "envelope-42",
            layerPlan: []
        )

        XCTAssertThrowsError(
            try reader.read(
                specification: specification,
                stagedBundleRoot: URL(fileURLWithPath: "/updates/update-42")
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformLayerEffectConfigurationReadError,
                .hostPlatformLayerMissing
            )
        }
    }

    func testRejectsDigestMismatchWithoutDecodingTheBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = makeConfiguration(databasePath: "/tmp/state.sqlite")
        let data = try JSONEncoder().encode(configuration)
        let relativePath = "payload/host-platform-configuration.json"
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("payload"),
            withIntermediateDirectories: true
        )
        try data.write(to: root.appendingPathComponent(relativePath))
        let specification = makeSpecification(
            configurationRelativePath: relativePath,
            configurationSHA256: String(repeating: "a", count: 64)
        )
        let store = SystemRuntimeFileStore()
        let reader = HostPlatformLayerEffectConfigurationReader(
            operations: BundleOwnedProductUpdateInputReadOperations(
                pathState: store.pathState,
                fileSize: store.fileSize,
                readData: store.readData
            )
        )

        XCTAssertThrowsError(
            try reader.read(
                specification: specification,
                stagedBundleRoot: root
            )
        ) { error in
            guard case let .digestMismatch(path, expected, actual) =
                error as? HostPlatformLayerEffectConfigurationReadError
            else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(path.hasSuffix(relativePath))
            XCTAssertEqual(expected, String(repeating: "a", count: 64))
            XCTAssertEqual(actual, self.sha256(data))
        }
    }

    func testRejectsMissingConfigurationFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let relativePath = "payload/host-platform-configuration.json"
        let specification = makeSpecification(
            configurationRelativePath: relativePath,
            configurationSHA256: String(repeating: "a", count: 64)
        )
        let store = SystemRuntimeFileStore()
        let reader = HostPlatformLayerEffectConfigurationReader(
            operations: BundleOwnedProductUpdateInputReadOperations(
                pathState: store.pathState,
                fileSize: store.fileSize,
                readData: store.readData
            )
        )

        XCTAssertThrowsError(
            try reader.read(
                specification: specification,
                stagedBundleRoot: root
            )
        ) { error in
            guard case let .missing(path) =
                error as? HostPlatformLayerEffectConfigurationReadError
            else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(path.hasSuffix(relativePath))
        }
    }

    private func makeSpecification(
        configurationRelativePath: String,
        configurationSHA256: String
    ) -> ProductUpdateSpecification {
        ProductUpdateSpecification(
            schemaVersion: "vitalserver.product-update-specification/v1",
            id: "specification-42",
            bootstrapEnvelopeId: "envelope-42",
            layerPlan: [
                ProductUpdateLayerPlan(
                    layer: .hostPlatform,
                    dependsOn: [],
                    artifact: UpdateBootstrapArtifact(
                        id: "host-platform-apply",
                        relativePath: "payload/host-platform.tar.gz",
                        sha256: String(repeating: "b", count: 64),
                        sizeBytes: 10,
                        mediaType: HostPlatformReleaseArchiveContract.mediaType
                    ),
                    effectExecutor: ProductUpdateLayerEffectExecutor(
                        id: "helper-host-effect",
                        relativePath: "payload/host-platform-executor",
                        sha256: String(repeating: "c", count: 64),
                        sizeBytes: 10,
                        mediaType: BundleOwnedProductUpdatePlanner
                            .effectExecutorMediaType,
                        configurationArtifact: UpdateBootstrapArtifact(
                            id: "host-platform-configuration",
                            relativePath: configurationRelativePath,
                            sha256: configurationSHA256,
                            sizeBytes: 10,
                            mediaType: BundleOwnedProductUpdatePlanner
                                .effectConfigurationMediaType
                        )
                    ),
                    rollback: ProductUpdateLayerRollbackPlan(
                        state: .available,
                        artifact: UpdateBootstrapArtifact(
                            id: "host-platform-rollback",
                            relativePath: "payload/host-platform-rollback.tar.gz",
                            sha256: String(repeating: "d", count: 64),
                            sizeBytes: 10,
                            mediaType:
                                HostPlatformReleaseArchiveContract.mediaType
                        ),
                        reason: nil
                    )
                ),
            ]
        )
    }

    private func makeConfiguration(
        databasePath: String
    ) -> HostPlatformLayerEffectConfiguration {
        HostPlatformLayerEffectConfiguration(
            schemaVersion:
                HostPlatformLayerEffectPolicy.configurationSchemaVersion,
            effectExecutorId: "helper-host-effect",
            manager: HostPlatformManagerEndpoint(
                executablePath:
                    "/usr/local/bin/vitalserver-host-installation-manager",
                databasePath: databasePath,
                installationRootPath:
                    "/Library/Application Support/VitalServerHelper/host-platform",
                launchctlExecutablePath: "/bin/launchctl",
                exchangeRootPath:
                    "/Library/Application Support/VitalServerHelper/update-manager/exchange"
            ),
            apply: HostPlatformLayerTransition(
                installationId: "installation-1",
                expectedInstallationRevision: 1,
                targetReleaseId: "host-0.2.2",
                targetReleaseVersion: "0.2.2",
                targetSlotRelativePath: "releases/host-0.2.2"
            ),
            rollback: HostPlatformLayerTransition(
                installationId: "installation-1",
                expectedInstallationRevision: 2,
                targetReleaseId: "host-0.2.1",
                targetReleaseVersion: "0.2.1",
                targetSlotRelativePath: "releases/host-0.2.1"
            )
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
