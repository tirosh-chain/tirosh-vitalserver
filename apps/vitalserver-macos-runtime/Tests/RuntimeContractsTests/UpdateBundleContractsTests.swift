import RuntimeContracts
import XCTest

final class UpdateBundleContractsTests: XCTestCase {
    func testDecodesKnownArtifactTypesAsEnumValues() throws {
        let manifest = try JSONDecoder().decode(UpdateBundleManifest.self, from: Data("""
        {
          "schemaVersion": 2,
          "product": "com.tirosh.vitalserver",
          "bundleKind": "product-update",
          "helperVersion": "1.2.3",
          "targetPlatforms": ["macos-arm64"],
          "components": {
            "updater": "4.5.6"
          },
          "minUpdaterVersion": "1.2.0",
          "requiresGuestActivation": true,
          "requiresTwoPhaseUpdate": false,
          "createdAt": "2026-05-21T12:00:00Z",
          "artifacts": [
            { "name": "rootfs-base.raw.gz", "type": "rootfs-base", "sha256": "abc", "size": 10 },
            { "name": "guest-deploy.tar.gz", "type": "guest-deploy", "sha256": "def", "size": 20 }
          ],
          "migrations": [
            { "name": "001.sh", "sha256": "123", "size": 30 }
          ]
        }
        """.utf8))

        XCTAssertEqual(manifest.version, "1.2.3")
        XCTAssertEqual(manifest.runtimeVersion, "4.5.6")
        XCTAssertEqual(manifest.minUpdaterVersion, "1.2.0")
        XCTAssertTrue(manifest.requiresGuestActivation)
        XCTAssertFalse(manifest.requiresTwoPhaseUpdate)
        XCTAssertEqual(manifest.artifacts.map(\.type), [.rootfsBase, .guestDeploy])
        XCTAssertEqual(manifest.migrations.first?.name, "001.sh")
    }

    func testManifestRequiresLayeredVersionFields() {
        XCTAssertThrowsError(try JSONDecoder().decode(UpdateBundleManifest.self, from: Data("""
        {
          "schemaVersion": 2,
          "product": "TiroshVitalServer",
          "version": "1.2.3",
          "runtimeVersion": "4.5.6",
          "createdAt": "2026-05-21T12:00:00Z",
          "artifacts": [],
          "migrations": []
        }
        """.utf8)))
    }

    func testManifestCompatibilityFieldsDefaultForNewDocuments() throws {
        let manifest = try JSONDecoder().decode(UpdateBundleManifest.self, from: Data("""
        {
          "schemaVersion": 2,
          "product": "com.tirosh.vitalserver",
          "bundleKind": "product-update",
          "helperVersion": "1.2.3",
          "targetPlatforms": [],
          "components": {
            "updater": "4.5.6"
          },
          "createdAt": "2026-05-21T12:00:00Z",
          "artifacts": [],
          "migrations": []
        }
        """.utf8))

        XCTAssertEqual(manifest.bundleKind, .productUpdate)
        XCTAssertEqual(manifest.version, "1.2.3")
        XCTAssertEqual(manifest.runtimeVersion, "4.5.6")
        XCTAssertEqual(manifest.helperVersion, "1.2.3")
        XCTAssertEqual(manifest.targetPlatforms, [])
        XCTAssertEqual(manifest.components, ["updater": "4.5.6"])
        XCTAssertNil(manifest.minUpdaterVersion)
        XCTAssertFalse(manifest.requiresGuestActivation)
        XCTAssertFalse(manifest.requiresTwoPhaseUpdate)
    }

    func testDecodesLayeredManifestShape() throws {
        let manifest = try JSONDecoder().decode(UpdateBundleManifest.self, from: Data("""
        {
          "schemaVersion": 2,
          "product": "com.tirosh.vitalserver",
          "bundleKind": "product-update",
          "helperVersion": "0.2.0",
          "targetPlatforms": ["macos-arm64"],
          "minUpdaterVersion": "0.1.6",
          "components": {
            "helperUI": "0.2.0+macos.1",
            "updater": "0.2.0",
            "supervisor": "0.2.0",
            "vmDriver": "0.2.0+macos.1",
            "serviceStack": "2.3.4-stack.1",
            "vitalServer": "2.3.4"
          },
          "requiresGuestActivation": true,
          "requiresTwoPhaseUpdate": false,
          "createdAt": "2026-05-22T00:00:00Z",
          "artifacts": [],
          "migrations": []
        }
        """.utf8))

        XCTAssertEqual(manifest.bundleKind, .productUpdate)
        XCTAssertEqual(manifest.version, "0.2.0")
        XCTAssertEqual(manifest.runtimeVersion, "0.2.0")
        XCTAssertEqual(manifest.helperVersion, "0.2.0")
        XCTAssertEqual(manifest.targetPlatforms, ["macos-arm64"])
        XCTAssertEqual(manifest.components["vmDriver"], "0.2.0+macos.1")
        XCTAssertEqual(manifest.components["serviceStack"], "2.3.4-stack.1")
        XCTAssertEqual(manifest.minUpdaterVersion, "0.1.6")
    }

    func testUnknownBundleKindRoundTrips() throws {
        let manifest = try JSONDecoder().decode(UpdateBundleManifest.self, from: Data("""
        {
          "schemaVersion": 2,
          "product": "com.tirosh.vitalserver",
          "bundleKind": "future-kind",
          "helperVersion": "0.2.0",
          "targetPlatforms": ["macos-arm64"],
          "components": {
            "updater": "0.2.0"
          },
          "createdAt": "2026-05-22T00:00:00Z",
          "artifacts": [],
          "migrations": []
        }
        """.utf8))

        XCTAssertEqual(manifest.bundleKind, .unknown("future-kind"))

        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(UpdateBundleManifest.self, from: encoded)
        XCTAssertEqual(decoded.bundleKind, .unknown("future-kind"))
    }

    func testUnknownArtifactTypeRoundTrips() throws {
        let artifact = try JSONDecoder().decode(UpdateBundleArtifact.self, from: Data("""
        { "name": "future.tar.gz", "type": "future-artifact", "sha256": "abc", "size": 10 }
        """.utf8))

        XCTAssertEqual(artifact.type, .unknown("future-artifact"))
        XCTAssertEqual(artifact.type.rawValue, "future-artifact")

        let encoded = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(UpdateBundleArtifact.self, from: encoded)
        XCTAssertEqual(decoded.type, .unknown("future-artifact"))
    }

    func testUpdateActivationRequestRequiresRequestId() throws {
        let request = GuestUpdateActivationRequestDocument(
            requestId: "request-1",
            requestedAt: "2026-05-22T00:00:00Z",
            version: "1.2.3"
        )

        let decoded = try JSONDecoder().decode(
            GuestUpdateActivationRequestDocument.self,
            from: try JSONEncoder().encode(request)
        )
        XCTAssertEqual(decoded.requestId, "request-1")
        XCTAssertEqual(decoded.operation, .activateGuestUpdate)
        let encodedJSON = String(data: try JSONEncoder().encode(request), encoding: .utf8)
        XCTAssertTrue(encodedJSON?.contains("\"activate-update\"") == true)

        XCTAssertThrowsError(try JSONDecoder().decode(GuestUpdateActivationRequestDocument.self, from: Data("""
        {
          "schemaVersion": 2,
          "operation": "activate-update",
          "requestedAt": "2026-05-22T00:00:00Z",
          "version": "1.2.3"
        }
        """.utf8)))
    }
}
