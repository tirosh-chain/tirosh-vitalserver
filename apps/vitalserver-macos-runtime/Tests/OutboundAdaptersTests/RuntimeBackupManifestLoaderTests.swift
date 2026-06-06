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
            fileExists: { url in
                events.append("exists:\(url.path)")
                return true
            },
            readData: { url in
                events.append("read:\(url.path)")
                return try JSONEncoder().encode(backupManifest(rootfsBase: RuntimeFileNames.rootfsBase))
            }
        )

        let manifest = try loader.load(from: backup)

        XCTAssertEqual(manifest.rootfsBase, RuntimeFileNames.rootfsBase)
        XCTAssertEqual(events, [
            "exists:/runtime/backups/backup-1/backup-manifest.json",
            "read:/runtime/backups/backup-1/backup-manifest.json",
        ])
    }

    func testLoadReportsMissingReadAndDecodeFailuresSeparately() {
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")
        let manifestURL = backup.appendingPathComponent(RuntimeFileNames.backupManifest)

        XCTAssertThrowsError(try RuntimeBackupManifestLoader(
            fileExists: { _ in false },
            readData: { _ in Data() }
        ).load(from: backup)) { error in
            XCTAssertEqual(
                error as? RuntimeBackupManifestLoaderError,
                .missingFile(path: manifestURL.path)
            )
        }

        XCTAssertThrowsError(try RuntimeBackupManifestLoader(
            fileExists: { _ in true },
            readData: { _ in throw TestError.permissionDenied }
        ).load(from: backup)) { error in
            XCTAssertEqual(
                error as? RuntimeBackupManifestLoaderError,
                .readFailed(path: manifestURL.path, reason: "permissionDenied")
            )
        }

        XCTAssertThrowsError(try RuntimeBackupManifestLoader(
            fileExists: { _ in true },
            readData: { _ in Data(#"{"rootfsBase":7}"#.utf8) }
        ).load(from: backup)) { error in
            guard case .decodeFailed(let path, let reason) = error as? RuntimeBackupManifestLoaderError else {
                return XCTFail("expected decodeFailed error")
            }
            XCTAssertEqual(path, manifestURL.path)
            XCTAssertFalse(reason.isEmpty)
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
