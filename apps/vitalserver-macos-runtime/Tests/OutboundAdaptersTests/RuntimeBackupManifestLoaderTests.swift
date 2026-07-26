import Contracts
import Foundation
import OutboundAdapters
import XCTest
import Errors

final class RuntimeBackupManifestLoaderTests: XCTestCase {
    func testLoadReadsBackupManifestFromExplicitBackupDirectory() throws {
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")
        var events: [String] = []
        let loader = RuntimeBackupManifestLoader(
            pathState: { url in
                events.append("state:\(url.path)")
                return .file
            },
            readData: { url in
                events.append("read:\(url.path)")
                return try JSONEncoder().encode(backupManifest(rootfsBase: RuntimePackageArtifactFileNames.rootfsBase))
            }
        )

        let manifest = try loader.load(from: backup)

        XCTAssertEqual(manifest.rootfsBase, RuntimePackageArtifactFileNames.rootfsBase)
        XCTAssertEqual(events, [
            "state:/runtime/backups/backup-1/backup-manifest.json",
            "read:/runtime/backups/backup-1/backup-manifest.json",
        ])
    }

    func testLoadReportsMissingReadAndDecodeFailuresSeparately() {
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")
        let manifestURL = backup.appendingPathComponent(RuntimePackageArtifactFileNames.backupManifest)

        XCTAssertThrowsError(try RuntimeBackupManifestLoader(
            pathState: { _ in .missing },
            readData: { _ in Data() }
        ).load(from: backup)) { error in
            XCTAssertEqual(
                error as? RuntimeBackupManifestLoaderError,
                .missingFile(path: manifestURL.path)
            )
        }

        XCTAssertThrowsError(try RuntimeBackupManifestLoader(
            pathState: { _ in .file },
            readData: { _ in throw TestError.permissionDenied }
        ).load(from: backup)) { error in
            XCTAssertEqual(
                error as? RuntimeBackupManifestLoaderError,
                .readFailed(path: manifestURL.path, reason: "permissionDenied")
            )
        }

        XCTAssertThrowsError(try RuntimeBackupManifestLoader(
            pathState: { _ in .file },
            readData: { _ in Data(#"{"rootfsBase":7}"#.utf8) }
        ).load(from: backup)) { error in
            guard case .decodeFailed(let path, let reason) = error as? RuntimeBackupManifestLoaderError else {
                return XCTFail("expected decodeFailed error")
            }
            XCTAssertEqual(path, manifestURL.path)
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testLoadReportsManifestPathInspectionFailures() {
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")
        let manifestURL = backup.appendingPathComponent(RuntimePackageArtifactFileNames.backupManifest)

        XCTAssertThrowsError(try RuntimeBackupManifestLoader(
            pathState: { _ in .inspectFailed("permission denied") },
            readData: { _ in Data() }
        ).load(from: backup)) { error in
            XCTAssertEqual(
                error as? RuntimeBackupManifestLoaderError,
                .pathInspectionFailed(path: manifestURL.path, reason: "permission denied")
            )
        }

        XCTAssertThrowsError(try RuntimeBackupManifestLoader(
            pathState: { _ in .directory },
            readData: { _ in Data() }
        ).load(from: backup)) { error in
            XCTAssertEqual(
                error as? RuntimeBackupManifestLoaderError,
                .unexpectedPathState(path: manifestURL.path, state: "directory")
            )
        }
    }
}

private func backupManifest(rootfsBase: String?) -> BackupManifest {
    BackupManifest(
        product: "ai.tirosh.vitalserver.helper",
        createdAt: "2026-06-06T00:00:00Z",
        reason: "before-1.2.3",
        rootfsBase: rootfsBase,
        vmDisk: "vm-disk.img",
        vmDiskPreserved: true
    )
}

private enum TestError: Error {
    case permissionDenied
}
