import Contracts
import XCTest

final class RuntimeDataBackupDocumentsTests: XCTestCase {
    func testManifestEncodesRuntimeDataBackupArtifactsInContractOrder() throws {
        let manifest = RuntimeDataBackupManifest(
            product: "ai.tirosh.vitalserver.helper",
            createdAt: "2026-06-10T00:00:00Z",
            reason: "manual",
            runtimeVersion: "0.1.13",
            sourceRuntimeHome: "/Library/Application Support/VitalServerHelper",
            artifacts: RuntimeDataBackupArtifactID.manifestArtifactOrder.map { id in
                let guestOwned = id == .redisData || id == .postgresDatabase
                return RuntimeDataBackupArtifact(
                    id: id,
                    role: RuntimeDataBackupArtifactID.optionalForDiagnosticsContinuity.contains(id) ? .optional : .required,
                    owner: guestOwned ? .guest : .host,
                    sourceKind: id == .redisData
                        ? .dockerVolumeArchive
                        : (id == .postgresDatabase ? .postgresBackupArchive : .file),
                    sourcePath: "/source/\(id.rawValue)",
                    backupPath: "artifacts/\(id.defaultBackupName)",
                    state: .archived,
                    sizeBytes: 1,
                    sha256: "sha"
                )
            }
        )

        let decoded = try JSONDecoder().decode(
            RuntimeDataBackupManifest.self,
            from: JSONEncoder().encode(manifest)
        )

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.backupKind, .vitalServerHelper)
        XCTAssertEqual(decoded.artifacts.map(\.id), RuntimeDataBackupArtifactID.manifestArtifactOrder)
        XCTAssertEqual(
            decoded.artifacts.filter { $0.role == .optional }.map(\.id),
            RuntimeDataBackupArtifactID.optionalForDiagnosticsContinuity
        )
        XCTAssertEqual(decoded.artifacts.first?.state, .archived)
    }
}
