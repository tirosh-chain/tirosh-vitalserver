import Contracts

public enum RuntimeDataBackupManifestValidation: Equatable, Sendable {
    case valid
    case invalid([String])
}

public enum RuntimeDataBackupPolicy {
    public static func validateCompletedBackup(
        _ manifest: RuntimeDataBackupManifest,
        expectedProduct: String? = nil,
        requiredArtifacts: [RuntimeDataBackupArtifactID] = RuntimeDataBackupArtifactID.requiredForRecovery
    ) -> RuntimeDataBackupManifestValidation {
        var errors: [String] = []

        if manifest.schemaVersion != 1 {
            errors.append("runtime data backup schemaVersion is unsupported: \(manifest.schemaVersion)")
        }
        if manifest.backupKind != .runtimeData {
            errors.append("runtime data backup kind is unsupported: \(manifest.backupKind.rawValue)")
        }
        if let expectedProduct, manifest.product != expectedProduct {
            errors.append("runtime data backup product mismatch: \(manifest.product)")
        }

        let artifactsByID = Dictionary(grouping: manifest.artifacts, by: \.id)
        for requiredID in requiredArtifacts {
            guard let artifacts = artifactsByID[requiredID], !artifacts.isEmpty else {
                errors.append("required runtime data backup artifact is missing: \(requiredID.rawValue)")
                continue
            }
            if artifacts.count > 1 {
                errors.append("required runtime data backup artifact is duplicated: \(requiredID.rawValue)")
                continue
            }
            let artifact = artifacts[0]
            if artifact.role != .required {
                errors.append("runtime data backup artifact role is invalid: \(requiredID.rawValue)")
            }
            if artifact.state != .archived {
                errors.append("required runtime data backup artifact is not archived: \(requiredID.rawValue) state=\(artifact.state.rawValue)")
            }
            if artifact.backupPath == nil || artifact.backupPath?.isEmpty == true {
                errors.append("required runtime data backup artifact has no backupPath: \(requiredID.rawValue)")
            }
            if artifact.sizeBytes == nil {
                errors.append("required runtime data backup artifact has no sizeBytes: \(requiredID.rawValue)")
            }
            if artifact.sha256 == nil || artifact.sha256?.isEmpty == true {
                errors.append("required runtime data backup artifact has no sha256: \(requiredID.rawValue)")
            }
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }
}
