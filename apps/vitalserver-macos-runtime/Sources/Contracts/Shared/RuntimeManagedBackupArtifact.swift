public enum RuntimeManagedBackupArtifact: CaseIterable, Sendable {
    case appBundle
    case nginxBundle
    case guestDeploy
    case runtimeTools

    public static let directoryArtifacts: [RuntimeManagedBackupArtifact] = [
        .appBundle,
        .nginxBundle,
        .guestDeploy,
    ]

    public var updateArtifactType: UpdateBundleArtifactType {
        switch self {
        case .appBundle:
            return .appBundle
        case .nginxBundle:
            return .nginxBundle
        case .guestDeploy:
            return .guestDeploy
        case .runtimeTools:
            return .runtimeTools
        }
    }

    public var backupDirectoryName: String {
        updateArtifactType.rawValue
    }
}
