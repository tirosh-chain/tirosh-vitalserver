import Application
import Contracts
import Foundation
import Errors

public struct RuntimeBackupManifestLoader {
    public let manifestFileName: String
    public let fileExists: (URL) -> Bool
    public let readData: (URL) throws -> Data

    public init(
        manifestFileName: String = RuntimeFileNames.backupManifest,
        fileExists: @escaping (URL) -> Bool,
        readData: @escaping (URL) throws -> Data
    ) {
        self.manifestFileName = manifestFileName
        self.fileExists = fileExists
        self.readData = readData
    }

    public init(
        fileStore: RuntimeFileReading,
        manifestFileName: String = RuntimeFileNames.backupManifest
    ) {
        self.init(
            manifestFileName: manifestFileName,
            fileExists: fileStore.fileExists,
            readData: fileStore.readData
        )
    }

    public func load(from backup: URL) throws -> BackupManifest {
        let manifestURL = backup.appendingPathComponent(manifestFileName)
        guard fileExists(manifestURL) else {
            throw RuntimeBackupManifestLoaderError.missingFile(path: manifestURL.path)
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
