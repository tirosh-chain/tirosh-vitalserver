import Contracts
import Foundation
import XCTest

final class ProductUpdateSpecificationContractsTests: XCTestCase {
    func testDecodesStrictBundleOwnedSpecification() throws {
        let data = try XCTUnwrap(document().data(using: .utf8))

        let specification = try JSONDecoder().decode(
            ProductUpdateSpecification.self,
            from: data
        )

        XCTAssertEqual(
            specification.schemaVersion,
            "vitalserver.product-update-specification/v1"
        )
        XCTAssertEqual(specification.bootstrapEnvelopeId, "envelope-42")
        XCTAssertEqual(specification.layerPlan.map(\.layer), [.container])
        XCTAssertEqual(
            specification.layerPlan[0].effectExecutor.id,
            "container-executor"
        )
        XCTAssertEqual(
            specification.layerPlan[0].rollback.state,
            .available
        )
    }

    func testRejectsUnknownSpecificationField() throws {
        let data = try XCTUnwrap(
            document(extraRootField: #","legacyCommand":"apply.sh""#)
                .data(using: .utf8)
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ProductUpdateSpecification.self,
                from: data
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("legacyCommand")
            )
        }
    }

    private func document(extraRootField: String = "") -> String {
        """
        {
          "schemaVersion": "vitalserver.product-update-specification/v1",
          "id": "specification-42",
          "bootstrapEnvelopeId": "envelope-42",
          "layerPlan": [{
            "layer": "container",
            "dependsOn": [],
            "artifact": {
              "id": "container-release",
              "relativePath": "payload/container.tar",
              "sha256": "\(String(repeating: "a", count: 64))",
              "sizeBytes": 10,
              "mediaType": "application/x-tar"
            },
            "effectExecutor": {
              "id": "container-executor",
              "relativePath": "payload/bin/container-executor",
              "sha256": "\(String(repeating: "b", count: 64))",
              "sizeBytes": 20,
              "mediaType": "application/vnd.tirosh.vitalserver.update-layer-effect-executor",
              "configurationArtifact": {
                "id": "container-configuration",
                "relativePath": "payload/config/container.json",
                "sha256": "\(String(repeating: "c", count: 64))",
                "sizeBytes": 30,
                "mediaType": "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"
              }
            },
            "rollback": {
              "state": "available",
              "artifact": {
                "id": "container-rollback",
                "relativePath": "payload/container-rollback.tar",
                "sha256": "\(String(repeating: "d", count: 64))",
                "sizeBytes": 40,
                "mediaType": "application/x-tar"
              }
            }
          }]
          \(extraRootField)
        }
        """
    }
}
