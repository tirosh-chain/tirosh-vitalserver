import Foundation
import CryptoKit
import Contracts
import Application
import Errors

public enum RuntimeDataBackupStoreError: Error, Equatable, CustomStringConvertible {
    case requiredArtifactMissing(id: RuntimeDataBackupArtifactID, path: String)
    case requiredArtifactInspectionFailed(id: RuntimeDataBackupArtifactID, path: String, reason: String)
    case requiredArtifactUnexpectedState(id: RuntimeDataBackupArtifactID, path: String, state: String)
    case backupDestinationAlreadyExists(path: String)
    case manifestWriteFailed(path: String, reason: String)
    case manifestReadFailed(path: String, reason: String)
    case manifestInvalid(path: String, errors: [String])
    case artifactPathInvalid(id: RuntimeDataBackupArtifactID, path: String)
    case artifactChecksumMismatch(id: RuntimeDataBackupArtifactID, path: String)
    case artifactSizeMismatch(id: RuntimeDataBackupArtifactID, path: String)
    case restoreDestinationInspectionFailed(id: RuntimeDataBackupArtifactID, path: String, reason: String)
    case restoreDestinationUnexpectedState(id: RuntimeDataBackupArtifactID, path: String, state: String)
    case restoreWriteFailed(id: RuntimeDataBackupArtifactID, path: String, reason: String)

    public var description: String {
        switch self {
        case .requiredArtifactMissing(let id, let path):
            return "required runtime data backup artifact is missing id=\(id.rawValue) path=\(path)"
        case .requiredArtifactInspectionFailed(let id, let path, let reason):
            return "required runtime data backup artifact inspection failed id=\(id.rawValue) path=\(path) reason=\(reason)"
        case .requiredArtifactUnexpectedState(let id, let path, let state):
            return "required runtime data backup artifact path state is unexpected id=\(id.rawValue) path=\(path) state=\(state)"
        case .backupDestinationAlreadyExists(let path):
            return "runtime data backup destination already exists path=\(path)"
        case .manifestWriteFailed(let path, let reason):
            return "runtime data backup manifest write failed path=\(path) reason=\(reason)"
        case .manifestReadFailed(let path, let reason):
            return "runtime data backup manifest read failed path=\(path) reason=\(reason)"
        case .manifestInvalid(let path, let errors):
            return "runtime data backup manifest is invalid path=\(path) errors=\(errors.joined(separator: "; "))"
        case .artifactPathInvalid(let id, let path):
            return "runtime data backup artifact path is invalid id=\(id.rawValue) path=\(path)"
        case .artifactChecksumMismatch(let id, let path):
            return "runtime data backup artifact checksum mismatch id=\(id.rawValue) path=\(path)"
        case .artifactSizeMismatch(let id, let path):
            return "runtime data backup artifact size mismatch id=\(id.rawValue) path=\(path)"
        case .restoreDestinationInspectionFailed(let id, let path, let reason):
            return "runtime data restore destination inspection failed id=\(id.rawValue) path=\(path) reason=\(reason)"
        case .restoreDestinationUnexpectedState(let id, let path, let state):
            return "runtime data restore destination state is unexpected id=\(id.rawValue) path=\(path) state=\(state)"
        case .restoreWriteFailed(let id, let path, let reason):
            return "runtime data restore write failed id=\(id.rawValue) path=\(path) reason=\(reason)"
        }
    }
}

public struct RuntimeDataBackupRestoreResult: Equatable, Sendable {
    public let redisArchive: URL
    public let startOnBootState: RuntimeDataBackupStartOnBootStateDocument

    public init(
        redisArchive: URL,
        startOnBootState: RuntimeDataBackupStartOnBootStateDocument
    ) {
        self.redisArchive = redisArchive
        self.startOnBootState = startOnBootState
    }
}

public struct RuntimeDataBackupStore {
    public var paths: RuntimeDataBackupStorePaths
    public var metadata: RuntimeDataBackupStoreMetadata
    public var timestamp: () -> String
    public var isoTimestamp: () -> String
    public var fileStore: RuntimeFileStore
    public var snapshotSQLiteDatabase: (URL, URL) throws -> Void

    public init(
        paths: RuntimeDataBackupStorePaths,
        metadata: RuntimeDataBackupStoreMetadata,
        timestamp: @escaping () -> String,
        isoTimestamp: @escaping () -> String,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        snapshotSQLiteDatabase: @escaping (URL, URL) throws -> Void = { source, destination in
            try SQLiteRuntimeObservabilitySnapshotter().snapshot(source: source, destination: destination)
        }
    ) {
        self.paths = paths
        self.metadata = metadata
        self.timestamp = timestamp
        self.isoTimestamp = isoTimestamp
        self.fileStore = fileStore
        self.snapshotSQLiteDatabase = snapshotSQLiteDatabase
    }

    public func createBackup(
        reason: String,
        redisArchive: URL,
        startOnBootState: Data
    ) throws -> URL {
        let stamp = timestamp()
        let backupRoot = paths.backupsDirectory.appendingPathComponent("runtime-data")
        let finalBackup = backupRoot.appendingPathComponent("\(stamp)-\(sanitizedPathComponent(reason))")
        let stagingBackup = backupRoot.appendingPathComponent(".staging-\(stamp)")
        let artifactsDirectory = stagingBackup.appendingPathComponent("artifacts")

        guard fileStore.pathState(at: finalBackup) == .missing else {
            throw RuntimeDataBackupStoreError.backupDestinationAlreadyExists(path: finalBackup.path)
        }
        guard fileStore.pathState(at: stagingBackup) == .missing else {
            throw RuntimeDataBackupStoreError.backupDestinationAlreadyExists(path: stagingBackup.path)
        }

        do {
            try fileStore.createDirectory(at: artifactsDirectory, withIntermediateDirectories: true)

            var artifacts: [RuntimeDataBackupArtifact] = []
            artifacts.append(try archiveRequiredFile(
                id: .redisData,
                owner: .guest,
                sourceKind: .dockerVolumeArchive,
                source: redisArchive,
                sourceVolumeName: metadata.redisVolumeName,
                destination: artifactsDirectory.appendingPathComponent(RuntimeDataBackupArtifactID.redisData.defaultBackupName)
            ))
            artifacts.append(try archiveRequiredFile(
                id: .runtimeVMConfig,
                owner: .host,
                sourceKind: .file,
                source: paths.vmConfig,
                destination: artifactsDirectory.appendingPathComponent(RuntimeDataBackupArtifactID.runtimeVMConfig.defaultBackupName)
            ))
            artifacts.append(try archiveRequiredFile(
                id: .guestRuntimeConfig,
                owner: .host,
                sourceKind: .file,
                source: paths.guestRuntimeConfig,
                destination: artifactsDirectory.appendingPathComponent(RuntimeDataBackupArtifactID.guestRuntimeConfig.defaultBackupName)
            ))
            artifacts.append(try archiveRequiredFile(
                id: .guestRuntimeSettings,
                owner: .host,
                sourceKind: .file,
                source: paths.guestRuntimeSettings,
                destination: artifactsDirectory.appendingPathComponent(RuntimeDataBackupArtifactID.guestRuntimeSettings.defaultBackupName)
            ))
            artifacts.append(try archiveRequiredFile(
                id: .proxyLaunchDaemonSettings,
                owner: .host,
                sourceKind: .file,
                source: paths.proxyLaunchDaemon,
                destination: artifactsDirectory.appendingPathComponent(RuntimeDataBackupArtifactID.proxyLaunchDaemonSettings.defaultBackupName)
            ))
            artifacts.append(try archiveGeneratedState(
                id: .startOnBootState,
                data: startOnBootState,
                destination: artifactsDirectory.appendingPathComponent(RuntimeDataBackupArtifactID.startOnBootState.defaultBackupName)
            ))
            artifacts.append(try archiveOptionalFile(
                id: .runtimeStatusDocument,
                owner: .host,
                sourceKind: .file,
                source: paths.runtimeStatus,
                destination: artifactsDirectory.appendingPathComponent(RuntimeDataBackupArtifactID.runtimeStatusDocument.defaultBackupName)
            ))
            artifacts.append(try archiveOptionalFile(
                id: .runtimeEventsDocument,
                owner: .host,
                sourceKind: .file,
                source: paths.runtimeEvents,
                destination: artifactsDirectory.appendingPathComponent(RuntimeDataBackupArtifactID.runtimeEventsDocument.defaultBackupName)
            ))
            artifacts.append(try archiveOptionalSQLiteSnapshot(
                source: paths.runtimeObservabilityDatabase,
                destination: artifactsDirectory.appendingPathComponent(RuntimeDataBackupArtifactID.runtimeObservabilityDatabase.defaultBackupName)
            ))

            let manifest = RuntimeDataBackupManifest(
                product: metadata.productIdentifier,
                createdAt: isoTimestamp(),
                reason: reason,
                runtimeVersion: readRuntimeVersion(),
                sourceRuntimeHome: paths.runtimeHome.path,
                artifacts: artifacts
            )
            try writeManifest(manifest, to: stagingBackup.appendingPathComponent(metadata.manifestName))
            try fileStore.moveItem(at: stagingBackup, to: finalBackup)
            return finalBackup
        } catch {
            try? fileStore.removeItem(at: stagingBackup)
            throw error
        }
    }

    public func restoreBackup(_ backup: URL) throws -> RuntimeDataBackupRestoreResult {
        let manifestURL = backup.appendingPathComponent(metadata.manifestName)
        let manifest = try loadManifest(from: manifestURL)
        let errors = completedBackupManifestErrors(manifest)
        if !errors.isEmpty {
            throw RuntimeDataBackupStoreError.manifestInvalid(path: manifestURL.path, errors: errors)
        }

        let artifacts = Dictionary(uniqueKeysWithValues: manifest.artifacts.map { ($0.id, $0) })
        let redisArtifact = try requiredVerifiedArtifact(.redisData, artifacts: artifacts, backup: backup)
        let startOnBootArtifact = try requiredVerifiedArtifact(.startOnBootState, artifacts: artifacts, backup: backup)

        try restoreRequiredFile(.runtimeVMConfig, artifacts: artifacts, backup: backup, destination: paths.vmConfig)
        try restoreRequiredFile(.guestRuntimeConfig, artifacts: artifacts, backup: backup, destination: paths.guestRuntimeConfig)
        try restoreRequiredFile(.guestRuntimeSettings, artifacts: artifacts, backup: backup, destination: paths.guestRuntimeSettings)
        try restoreRequiredFile(
            .proxyLaunchDaemonSettings,
            artifacts: artifacts,
            backup: backup,
            destination: paths.proxyLaunchDaemon
        )
        try restoreOptionalFile(.runtimeStatusDocument, artifacts: artifacts, backup: backup, destination: paths.runtimeStatus)
        try restoreOptionalFile(.runtimeEventsDocument, artifacts: artifacts, backup: backup, destination: paths.runtimeEvents)
        try restoreOptionalSQLiteSnapshot(artifacts: artifacts, backup: backup, destination: paths.runtimeObservabilityDatabase)

        let startOnBootState = try JSONDecoder().decode(
            RuntimeDataBackupStartOnBootStateDocument.self,
            from: fileStore.readData(startOnBootArtifact)
        )
        return RuntimeDataBackupRestoreResult(
            redisArchive: redisArtifact,
            startOnBootState: startOnBootState
        )
    }

    private func archiveRequiredFile(
        id: RuntimeDataBackupArtifactID,
        owner: RuntimeDataBackupArtifactOwner,
        sourceKind: RuntimeDataBackupSourceKind,
        source: URL,
        sourceVolumeName: String? = nil,
        destination: URL,
        role: RuntimeDataBackupArtifactRole = .required
    ) throws -> RuntimeDataBackupArtifact {
        try requireRequiredFile(id: id, source: source)
        try fileStore.copyItem(at: source, to: destination)
        return try archivedArtifact(
            id: id,
            owner: owner,
            sourceKind: sourceKind,
            sourcePath: source.path,
            volumeName: sourceVolumeName,
            destination: destination,
            role: role
        )
    }

    private func archiveGeneratedState(
        id: RuntimeDataBackupArtifactID,
        data: Data,
        destination: URL
    ) throws -> RuntimeDataBackupArtifact {
        try fileStore.writeData(data, to: destination, options: .atomic)
        return try archivedArtifact(
            id: id,
            owner: .host,
            sourceKind: .generatedState,
            sourcePath: nil,
            volumeName: nil,
            destination: destination,
            role: .required
        )
    }

    private func archiveOptionalFile(
        id: RuntimeDataBackupArtifactID,
        owner: RuntimeDataBackupArtifactOwner,
        sourceKind: RuntimeDataBackupSourceKind,
        source: URL,
        sourceVolumeName: String? = nil,
        destination: URL
    ) throws -> RuntimeDataBackupArtifact {
        do {
            return try archiveRequiredFile(
                id: id,
                owner: owner,
                sourceKind: sourceKind,
                source: source,
                sourceVolumeName: sourceVolumeName,
                destination: destination,
                role: .optional
            )
        } catch let error as RuntimeDataBackupStoreError {
            switch error {
            case .requiredArtifactMissing(let id, let path):
                return optionalArtifact(
                    id: id,
                    owner: owner,
                    sourceKind: sourceKind,
                    sourcePath: path,
                    volumeName: sourceVolumeName,
                    state: .missing,
                    error: nil
                )
            case .requiredArtifactInspectionFailed(let id, let path, let reason):
                return optionalArtifact(
                    id: id,
                    owner: owner,
                    sourceKind: sourceKind,
                    sourcePath: path,
                    volumeName: sourceVolumeName,
                    state: .readFailed,
                    error: reason
                )
            case .requiredArtifactUnexpectedState(let id, let path, let state):
                return optionalArtifact(
                    id: id,
                    owner: owner,
                    sourceKind: sourceKind,
                    sourcePath: path,
                    volumeName: sourceVolumeName,
                    state: .readFailed,
                    error: state
                )
            default:
                throw error
            }
        } catch {
            return optionalArtifact(
                id: id,
                owner: owner,
                sourceKind: sourceKind,
                sourcePath: source.path,
                volumeName: sourceVolumeName,
                state: .readFailed,
                error: error.localizedDescription
            )
        }
    }

    private func archiveOptionalSQLiteSnapshot(
        source: URL,
        destination: URL
    ) throws -> RuntimeDataBackupArtifact {
        do {
            return try archiveSQLiteSnapshot(source: source, destination: destination, role: .optional)
        } catch let error as RuntimeDataBackupStoreError {
            switch error {
            case .requiredArtifactMissing:
                return optionalArtifact(
                    id: .runtimeObservabilityDatabase,
                    owner: .host,
                    sourceKind: .sqliteSnapshot,
                    sourcePath: source.path,
                    volumeName: nil,
                    state: .missing,
                    error: nil
                )
            case .requiredArtifactInspectionFailed(_, let path, let reason):
                return optionalArtifact(
                    id: .runtimeObservabilityDatabase,
                    owner: .host,
                    sourceKind: .sqliteSnapshot,
                    sourcePath: path,
                    volumeName: nil,
                    state: .readFailed,
                    error: reason
                )
            case .requiredArtifactUnexpectedState(_, let path, let state):
                return optionalArtifact(
                    id: .runtimeObservabilityDatabase,
                    owner: .host,
                    sourceKind: .sqliteSnapshot,
                    sourcePath: path,
                    volumeName: nil,
                    state: .readFailed,
                    error: state
                )
            default:
                throw error
            }
        } catch {
            return optionalArtifact(
                id: .runtimeObservabilityDatabase,
                owner: .host,
                sourceKind: .sqliteSnapshot,
                sourcePath: source.path,
                volumeName: nil,
                state: .readFailed,
                error: error.localizedDescription
            )
        }
    }

    private func optionalArtifact(
        id: RuntimeDataBackupArtifactID,
        owner: RuntimeDataBackupArtifactOwner,
        sourceKind: RuntimeDataBackupSourceKind,
        sourcePath: String,
        volumeName: String? = nil,
        state: RuntimeDataBackupArtifactState,
        error: String?
    ) -> RuntimeDataBackupArtifact {
        RuntimeDataBackupArtifact(
            id: id,
            role: .optional,
            owner: owner,
            sourceKind: sourceKind,
            sourcePath: sourcePath,
            volumeName: volumeName,
            backupPath: nil,
            state: state,
            sizeBytes: nil,
            sha256: nil,
            error: error
        )
    }

    private func archiveSQLiteSnapshot(
        source: URL,
        destination: URL,
        role: RuntimeDataBackupArtifactRole = .required
    ) throws -> RuntimeDataBackupArtifact {
        try requireRequiredFile(id: .runtimeObservabilityDatabase, source: source)
        try snapshotSQLiteDatabase(source, destination)
        return try archivedArtifact(
            id: .runtimeObservabilityDatabase,
            owner: .host,
            sourceKind: .sqliteSnapshot,
            sourcePath: source.path,
            volumeName: nil,
            destination: destination,
            role: role
        )
    }

    private func requireRequiredFile(id: RuntimeDataBackupArtifactID, source: URL) throws {
        switch fileStore.pathState(at: source) {
        case .file:
            return
        case .missing:
            throw RuntimeDataBackupStoreError.requiredArtifactMissing(id: id, path: source.path)
        case .inspectFailed(let reason):
            throw RuntimeDataBackupStoreError.requiredArtifactInspectionFailed(
                id: id,
                path: source.path,
                reason: reason
            )
        case .directory, .other, .unknown:
            throw RuntimeDataBackupStoreError.requiredArtifactUnexpectedState(
                id: id,
                path: source.path,
                state: fileStore.pathState(at: source).rawValue
            )
        }
    }

    private func archivedArtifact(
        id: RuntimeDataBackupArtifactID,
        owner: RuntimeDataBackupArtifactOwner,
        sourceKind: RuntimeDataBackupSourceKind,
        sourcePath: String?,
        volumeName: String?,
        destination: URL,
        role: RuntimeDataBackupArtifactRole
    ) throws -> RuntimeDataBackupArtifact {
        let data = try fileStore.readData(destination)
        return RuntimeDataBackupArtifact(
            id: id,
            role: role,
            owner: owner,
            sourceKind: sourceKind,
            sourcePath: sourcePath,
            volumeName: volumeName,
            backupPath: relativeArtifactPath(destination.lastPathComponent),
            state: .archived,
            sizeBytes: UInt64(data.count),
            sha256: sha256(data)
        )
    }

    private func readRuntimeVersion() -> String? {
        guard case .file = fileStore.pathState(at: paths.runtimeVersion),
              let data = try? fileStore.readData(paths.runtimeVersion),
              let document = try? JSONDecoder().decode(RuntimeVersionDocument.self, from: data) else {
            return nil
        }
        return document.runtimeVersion
    }

    private func writeManifest(_ manifest: RuntimeDataBackupManifest, to destination: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try fileStore.writeData(try encoder.encode(manifest), to: destination, options: .atomic)
        } catch {
            throw RuntimeDataBackupStoreError.manifestWriteFailed(
                path: destination.path,
                reason: error.localizedDescription
            )
        }
    }

    private func loadManifest(from url: URL) throws -> RuntimeDataBackupManifest {
        do {
            return try JSONDecoder().decode(RuntimeDataBackupManifest.self, from: fileStore.readData(url))
        } catch {
            throw RuntimeDataBackupStoreError.manifestReadFailed(path: url.path, reason: error.localizedDescription)
        }
    }

    private func completedBackupManifestErrors(_ manifest: RuntimeDataBackupManifest) -> [String] {
        var errors: [String] = []
        if manifest.schemaVersion != 1 {
            errors.append("schemaVersion must be 1")
        }
        if let restoreCompatibilityVersion = manifest.restoreCompatibilityVersion {
            if restoreCompatibilityVersion != RuntimeDataBackupCompatibility.currentRestoreCompatibilityVersion {
                errors.append(
                    "restoreCompatibilityVersion must be \(RuntimeDataBackupCompatibility.currentRestoreCompatibilityVersion)"
                )
            }
        } else {
            errors.append("restoreCompatibilityVersion is missing")
        }
        if manifest.backupKind != .runtimeData {
            errors.append("backupKind must be runtime-data")
        }
        if manifest.product != metadata.productIdentifier {
            errors.append("product mismatch expected=\(metadata.productIdentifier) actual=\(manifest.product)")
        }
        let artifactsByID = Dictionary(grouping: manifest.artifacts, by: \.id)
        for id in RuntimeDataBackupArtifactID.requiredForRecovery {
            guard let artifacts = artifactsByID[id], artifacts.count == 1, let artifact = artifacts.first else {
                errors.append("missing required artifact id=\(id.rawValue)")
                continue
            }
            if artifact.role != .required {
                errors.append("artifact role must be required id=\(id.rawValue)")
            }
            if artifact.state != .archived {
                errors.append("artifact must be archived id=\(id.rawValue) state=\(artifact.state.rawValue)")
            }
            if artifact.backupPath == nil {
                errors.append("artifact backupPath is missing id=\(id.rawValue)")
            }
            if artifact.sizeBytes == nil {
                errors.append("artifact sizeBytes is missing id=\(id.rawValue)")
            }
            if artifact.sha256 == nil {
                errors.append("artifact sha256 is missing id=\(id.rawValue)")
            }
        }
        return errors
    }

    private func restoreRequiredFile(
        _ id: RuntimeDataBackupArtifactID,
        artifacts: [RuntimeDataBackupArtifactID: RuntimeDataBackupArtifact],
        backup: URL,
        destination: URL
    ) throws {
        let source = try requiredVerifiedArtifact(id, artifacts: artifacts, backup: backup)
        do {
            try fileStore.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try removeDestinationFileIfNeeded(id: id, destination: destination)
            try fileStore.copyItem(at: source, to: destination)
        } catch let error as RuntimeDataBackupStoreError {
            throw error
        } catch {
            throw RuntimeDataBackupStoreError.restoreWriteFailed(
                id: id,
                path: destination.path,
                reason: error.localizedDescription
            )
        }
    }

    private func restoreOptionalFile(
        _ id: RuntimeDataBackupArtifactID,
        artifacts: [RuntimeDataBackupArtifactID: RuntimeDataBackupArtifact],
        backup: URL,
        destination: URL
    ) throws {
        guard let source = optionalVerifiedArtifact(id, artifacts: artifacts, backup: backup) else {
            return
        }

        do {
            try fileStore.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try removeDestinationFileIfNeeded(id: id, destination: destination)
            try fileStore.copyItem(at: source, to: destination)
        } catch let error as RuntimeDataBackupStoreError {
            throw error
        } catch {
            throw RuntimeDataBackupStoreError.restoreWriteFailed(
                id: id,
                path: destination.path,
                reason: error.localizedDescription
            )
        }
    }

    private func restoreOptionalSQLiteSnapshot(
        artifacts: [RuntimeDataBackupArtifactID: RuntimeDataBackupArtifact],
        backup: URL,
        destination: URL
    ) throws {
        guard optionalVerifiedArtifact(
            .runtimeObservabilityDatabase,
            artifacts: artifacts,
            backup: backup
        ) != nil else {
            return
        }

        try removeSQLiteSidecar(URL(fileURLWithPath: destination.path + "-wal"))
        try removeSQLiteSidecar(URL(fileURLWithPath: destination.path + "-shm"))
        try restoreRequiredFile(
            .runtimeObservabilityDatabase,
            artifacts: artifacts,
            backup: backup,
            destination: destination
        )
    }

    private func requiredVerifiedArtifact(
        _ id: RuntimeDataBackupArtifactID,
        artifacts: [RuntimeDataBackupArtifactID: RuntimeDataBackupArtifact],
        backup: URL
    ) throws -> URL {
        guard let artifact = artifacts[id], let backupPath = artifact.backupPath else {
            throw RuntimeDataBackupStoreError.requiredArtifactMissing(id: id, path: backup.path)
        }
        let source = try artifactURL(id: id, backupPath: backupPath, backup: backup)
        try requireRequiredFile(id: id, source: source)
        let data = try fileStore.readData(source)
        if artifact.sizeBytes != UInt64(data.count) {
            throw RuntimeDataBackupStoreError.artifactSizeMismatch(id: id, path: source.path)
        }
        if artifact.sha256 != sha256(data) {
            throw RuntimeDataBackupStoreError.artifactChecksumMismatch(id: id, path: source.path)
        }
        return source
    }

    private func optionalVerifiedArtifact(
        _ id: RuntimeDataBackupArtifactID,
        artifacts: [RuntimeDataBackupArtifactID: RuntimeDataBackupArtifact],
        backup: URL
    ) -> URL? {
        guard let artifact = artifacts[id],
              (artifact.role == .optional || RuntimeDataBackupArtifactID.optionalForUIContinuity.contains(id)),
              artifact.state == .archived,
              let backupPath = artifact.backupPath else {
            return nil
        }

        guard let source = try? artifactURL(id: id, backupPath: backupPath, backup: backup),
              case .file = fileStore.pathState(at: source) else {
            return nil
        }

        guard let data = try? fileStore.readData(source) else {
            return nil
        }
        if artifact.sizeBytes != UInt64(data.count) {
            return nil
        }
        if artifact.sha256 != sha256(data) {
            return nil
        }

        return source
    }

    private func artifactURL(
        id: RuntimeDataBackupArtifactID,
        backupPath: String,
        backup: URL
    ) throws -> URL {
        guard !backupPath.hasPrefix("/") else {
            throw RuntimeDataBackupStoreError.artifactPathInvalid(id: id, path: backupPath)
        }
        let components = backupPath.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains("..") else {
            throw RuntimeDataBackupStoreError.artifactPathInvalid(id: id, path: backupPath)
        }
        return components.reduce(backup) { $0.appendingPathComponent($1) }
    }

    private func removeDestinationFileIfNeeded(
        id: RuntimeDataBackupArtifactID,
        destination: URL
    ) throws {
        switch fileStore.pathState(at: destination) {
        case .file:
            try fileStore.removeItem(at: destination)
        case .missing:
            return
        case .inspectFailed(let reason):
            throw RuntimeDataBackupStoreError.restoreDestinationInspectionFailed(
                id: id,
                path: destination.path,
                reason: reason
            )
        case .directory, .other, .unknown:
            throw RuntimeDataBackupStoreError.restoreDestinationUnexpectedState(
                id: id,
                path: destination.path,
                state: fileStore.pathState(at: destination).rawValue
            )
        }
    }

    private func removeSQLiteSidecar(_ url: URL) throws {
        switch fileStore.pathState(at: url) {
        case .file:
            try fileStore.removeItem(at: url)
        case .missing:
            return
        case .inspectFailed(let reason):
            throw RuntimeDataBackupStoreError.restoreDestinationInspectionFailed(
                id: .runtimeObservabilityDatabase,
                path: url.path,
                reason: reason
            )
        case .directory, .other, .unknown:
            throw RuntimeDataBackupStoreError.restoreDestinationUnexpectedState(
                id: .runtimeObservabilityDatabase,
                path: url.path,
                state: fileStore.pathState(at: url).rawValue
            )
        }
    }

    private func relativeArtifactPath(_ fileName: String) -> String {
        "artifacts/\(fileName)"
    }

    private func sanitizedPathComponent(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let sanitized = String(value.map { allowed.contains($0) ? $0 : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return sanitized.isEmpty ? "manual" : sanitized
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
