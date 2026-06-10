import Contracts
import Domain
import XCTest

final class RuntimeDataBackupPolicyTests: XCTestCase {
    func testCompleteManifestIsValidWhenAllRequiredArtifactsAreArchived() {
        let manifest = completeManifest()

        XCTAssertEqual(
            RuntimeDataBackupPolicy.validateCompletedBackup(
                manifest,
                expectedProduct: "ai.tirosh.vitalserver.helper"
            ),
            .valid
        )
    }

    func testMissingRequiredArtifactInvalidatesManifest() {
        let manifest = completeManifest(
            artifacts: completeArtifacts(for: RuntimeDataBackupArtifactID.requiredForRecovery)
                .filter { $0.id != .runtimeVMConfig }
        )

        XCTAssertEqual(
            RuntimeDataBackupPolicy.validateCompletedBackup(manifest),
            .invalid([
                "required runtime data backup artifact is missing: runtime-vm-config",
            ])
        )
    }

    func testOptionalArtifactsCanBeMissing() {
        let manifest = completeManifest(
            artifacts: completeArtifacts(for: RuntimeDataBackupArtifactID.requiredForRecovery)
        )

        XCTAssertEqual(
            RuntimeDataBackupPolicy.validateCompletedBackup(manifest),
            .valid
        )
    }

    func testNonArchivedRequiredArtifactInvalidatesManifest() {
        let artifacts = completeArtifacts().map { artifact in
            artifact.id == .redisData
                ? RuntimeDataBackupArtifact(
                    id: artifact.id,
                    owner: artifact.owner,
                    sourceKind: artifact.sourceKind,
                    sourcePath: artifact.sourcePath,
                    volumeName: artifact.volumeName,
                    backupPath: artifact.backupPath,
                    state: .readFailed,
                    sizeBytes: artifact.sizeBytes,
                    sha256: artifact.sha256,
                    error: "permission denied"
                )
                : artifact
        }
        let manifest = completeManifest(artifacts: artifacts)

        XCTAssertEqual(
            RuntimeDataBackupPolicy.validateCompletedBackup(manifest),
            .invalid([
                "required runtime data backup artifact is not archived: redis-data state=read-failed",
            ])
        )
    }

    func testProductMismatchInvalidatesManifest() {
        XCTAssertEqual(
            RuntimeDataBackupPolicy.validateCompletedBackup(
                completeManifest(product: "wrong.product"),
                expectedProduct: "ai.tirosh.vitalserver.helper"
            ),
            .invalid([
                "runtime data backup product mismatch: wrong.product",
            ])
        )
    }

    private func completeManifest(
        product: String = "ai.tirosh.vitalserver.helper",
        artifacts: [RuntimeDataBackupArtifact]? = nil
    ) -> RuntimeDataBackupManifest {
        RuntimeDataBackupManifest(
            product: product,
            createdAt: "2026-06-10T00:00:00Z",
            reason: "manual",
            sourceRuntimeHome: "/runtime-home",
            artifacts: artifacts ?? completeArtifacts()
        )
    }

    private func completeArtifacts() -> [RuntimeDataBackupArtifact] {
        completeArtifacts(for: RuntimeDataBackupArtifactID.requiredForUIContinuity)
    }

    private func completeArtifacts(for ids: [RuntimeDataBackupArtifactID]) -> [RuntimeDataBackupArtifact] {
        ids.map { id in
            let role = RuntimeDataBackupArtifactID.optionalForUIContinuity.contains(id)
                ? RuntimeDataBackupArtifactRole.optional
                : .required
            return RuntimeDataBackupArtifact(
                id: id,
                role: role,
                owner: id == .redisData ? .guest : .host,
                sourceKind: id == .redisData ? .dockerVolumeArchive : .file,
                sourcePath: "/source/\(id.rawValue)",
                backupPath: "artifacts/\(id.defaultBackupName)",
                state: .archived,
                sizeBytes: 1,
                sha256: "sha"
            )
        }
    }
}
