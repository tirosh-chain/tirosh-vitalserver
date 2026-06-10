import Contracts
import XCTest

final class RuntimeDataBackupDocumentsTests: XCTestCase {
    func testManifestEncodesRequiredRuntimeDataBackupArtifacts() throws {
        let manifest = RuntimeDataBackupManifest(
            product: "ai.tirosh.vitalserver.helper",
            createdAt: "2026-06-10T00:00:00Z",
            reason: "manual",
            runtimeVersion: "0.1.13",
            sourceRuntimeHome: "/Library/Application Support/VitalServerHelper",
            artifacts: RuntimeDataBackupArtifactID.requiredForUIContinuity.map { id in
                RuntimeDataBackupArtifact(
                    id: id,
                    owner: id == .redisData ? .guest : .host,
                    sourceKind: id == .redisData ? .dockerVolumeArchive : .file,
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
        XCTAssertEqual(decoded.backupKind, .runtimeData)
        XCTAssertEqual(decoded.artifacts.map(\.id), RuntimeDataBackupArtifactID.requiredForUIContinuity)
        XCTAssertEqual(decoded.artifacts.first?.state, .archived)
    }
}
