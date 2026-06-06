public enum RuntimeBackupManifestLoaderError: Error, Equatable, CustomStringConvertible {
    case missingFile(path: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .missingFile(let path):
            return "missing file: \(path)"
        case .readFailed(let path, let reason):
            return "failed to read backup manifest: \(path) reason=\(reason)"
        case .decodeFailed(let path, let reason):
            return "failed to decode backup manifest: \(path) reason=\(reason)"
        }
    }
}
