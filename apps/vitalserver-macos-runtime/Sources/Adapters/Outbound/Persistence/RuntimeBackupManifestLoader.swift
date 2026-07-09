import Application
import Contracts
import Foundation
import Errors

public struct RuntimeBackupManifestLoader {
    public let manifestFileName: String
    public let pathState: (URL) -> RuntimePathState
    public let readData: (URL) throws -> Data

    public init(
        manifestFileName: String = RuntimePackageArtifactFileNames.backupManifest,
        pathState: @escaping (URL) -> RuntimePathState,
        readData: @escaping (URL) throws -> Data
    ) {
        self.manifestFileName = manifestFileName
        self.pathState = pathState
        self.readData = readData
    }

    public init(
        fileStore: RuntimeFileReading,
        manifestFileName: String = RuntimePackageArtifactFileNames.backupManifest
    ) {
        self.init(
            manifestFileName: manifestFileName,
            pathState: fileStore.pathState(at:),
            readData: fileStore.readData
        )
    }

    public func load(from backup: URL) throws -> BackupManifest {
        let manifestURL = backup.appendingPathComponent(manifestFileName)
        let manifestPathState = pathState(manifestURL)
        switch manifestPathState {
        case .file:
            break
        case .missing:
            throw RuntimeBackupManifestLoaderError.missingFile(path: manifestURL.path)
        case .inspectFailed(let reason):
            throw RuntimeBackupManifestLoaderError.pathInspectionFailed(
                path: manifestURL.path,
                reason: reason
            )
        case .directory, .other, .unknown:
            throw RuntimeBackupManifestLoaderError.unexpectedPathState(
                path: manifestURL.path,
                state: manifestPathState.rawValue
            )
        }

        let data: Data
        do {
            data = try readData(manifestURL)
        } catch {
            throw RuntimeBackupManifestLoaderError.readFailed(
                path: manifestURL.path,
                reason: String(describing: error)
            )
        }

        do {
            return try JSONDecoder().decode(BackupManifest.self, from: data)
        } catch {
            throw RuntimeBackupManifestLoaderError.decodeFailed(
                path: manifestURL.path,
                reason: String(describing: error)
            )
        }
    }
}
